#!/usr/bin/env python3
"""PowerPulse interconnect generator.

Reads `config/soc_config.yaml`, runs the map checker, and emits every derived
artefact of the SoC.  Nothing here is hand-editable; change the config (or this
generator) and re-run `make gen`.

Outputs (all git-ignored except under docs/):

  sim/gen/bus/pp_axi_interconnect.v   the generated AXI4 crossbar
  sim/gen/pp_soc_cfg_pkg.sv            SystemVerilog package: every width, size
                                       and base address the RTL needs
  sim/gen/pp_memmap.h                  C header for software
  sim/gen/powerpulse.ld                linker script (origins/sizes from config)
  sim/gen/config.mk                    Makefile fragment
  sim/gen/veer_opts.txt                options for the VeeR config generator
  sim/gen/filelist.f                   VCS compile order for generated + core RTL
  docs/generated/memory_map.md         the human-readable map (documentation)

Run standalone:  python3 tools/gen_interconnect.py [--check-only]
"""

from __future__ import print_function

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

from soc_config import load_config, ConfigError       # noqa: E402
import map_checker                                     # noqa: E402

BANNER = """// =============================================================================
// GENERATED FILE -- DO NOT EDIT
//
// Produced by tools/gen_interconnect.py from config/soc_config.yaml.
// Any change here is lost on the next `make gen`; change the config instead.
//
// config : {config}
// slots  : {nslots} ({names})
// masters: {masters}
// =============================================================================
"""


def ensure_dir(path):
    if not os.path.isdir(path):
        os.makedirs(path)
    return path


def w(path, text):
    ensure_dir(os.path.dirname(path))
    with open(path, "w") as handle:
        handle.write(text)
    return path


def banner(cfg):
    return BANNER.format(
        config=os.path.relpath(cfg.path, ROOT),
        nslots=cfg.n_slots,
        names=", ".join(s.name for s in cfg.slots),
        masters=", ".join(cfg.master_names))


# =============================================================================
# 1. the crossbar
# =============================================================================

# AXI channel signal -> width key.  Everything emitted is derived from this
# table, so the generated RTL can never disagree with itself about a width.
AW_SIGS = [("awid", "ID"), ("awaddr", "ADDR"), ("awlen", 8), ("awsize", 3),
           ("awburst", 2), ("awlock", 1), ("awprot", 3)]
AR_SIGS = [("arid", "ID"), ("araddr", "ADDR"), ("arlen", 8), ("arsize", 3),
           ("arburst", 2), ("arlock", 1), ("arprot", 3)]

# slave-side nets driven *by* the crossbar
OUT_SIG = ([(n, 1) for n in ("awvalid", "wvalid", "wlast", "bready", "arvalid", "rready")]
           + [("wdata", "DW"), ("wstrb", "STRB")]
           + [(n, k) for n, k in AW_SIGS if n != "awvalid"]
           + [(n, k) for n, k in AR_SIGS if n != "arvalid"])
# slave-side nets driven *by* the slave
IN_SIG = [("awready", 1), ("wready", 1), ("bid", "ID"), ("bresp", 2), ("bvalid", 1),
          ("arready", 1), ("rid", "ID"), ("rdata", "DW"), ("rresp", 2), ("rlast", 1),
          ("rvalid", 1)]


class W(object):
    """All widths the crossbar needs, resolved once."""

    def __init__(self, cfg):
        self.M = cfg.n_masters
        self.S = cfg.n_slots
        self.NS = cfg.n_slots + 1        # + the internal decode-error default slave
        self.DEFS = cfg.n_slots
        self.ID = cfg.id_width
        self.ADDR = cfg.addr_width
        self.DW = cfg.xbar_data_width
        self.STRB = cfg.strb_width
        self.CLM = 1 if self.M <= 1 else (self.M - 1).bit_length()

    def __getitem__(self, key):
        if isinstance(key, int):
            return key
        return {"ID": self.ID, "ADDR": self.ADDR, "DW": self.DW, "STRB": self.STRB}[key]


def _wd(W_, width):
    return W_[width] if isinstance(width, str) else width


def _decl(width, count, name):
    """Declaration of a packed vector of `count` slices of `width` bits."""
    return "wire [%d:0] %s" % (count * width - 1, name)


def _reg_decl(width, count, name):
    return "reg  [%d:0] %s" % (count * width - 1, name)


def _sl(name, width):
    """Slice of a per-slice packed vector, indexed by genvar `g`."""
    if width == 1:
        return "%s[g]" % name
    return "%s[(g)*%d +: %d]" % (name, width, width)


def _sln(name, idx, width):
    """Slice of a per-slice packed vector, numeric or symbolic index."""
    if width == 1:
        return "%s[%s]" % (name, idx)
    return "%s[(%s)*%d +: %d]" % (name, idx, width, width)


def _fs(name, m, width, g="g"):
    """Slice of a flat per-(slave, master) vector inside a generate block.

    `g` is the *identifier* of the slave loop genvar, so this works both inside
    the per-slave loop (the default) and inside the master-output loop.
    """
    if width == 1:
        return "%s[(%s)*M_COUNT + %s]" % (name, g, m)
    return "%s[((%s)*M_COUNT + %s)*%d +: %d]" % (name, g, m, width, width)


def _reduce(terms):
    return " | ".join(terms) if terms else "1'b0"


def gen_crossbar(cfg, path):
    W_ = W(cfg)
    M, NS, CLM = W_.M, W_.NS, W_.CLM
    L = []
    a = L.append

    a(banner(cfg))
    a("`default_nettype none")
    a("")
    a("// -----------------------------------------------------------------------------")
    a("// %d master AXI4 ports  <->  %d configured slave slots  +  1 internal"
      % (M, W_.S))
    a("// decode-error default slave.")
    a("//")
    a("// The master side is the *interconnect* width (%d bit).  VeeR's %d-bit ports"
      % (W_.DW, cfg.core_data_width))
    a("// are narrowed first by rtl/bus/pp_axi_downsize.v.")
    a("//")
    a("// Arbitration: one round-robin arbiter per (slave, channel), built from")
    a("// rtl/vendor/verilog-axi/arbiter.v.  A master owns a slave from the moment its")
    a("// AW/AR is accepted until the B handshake (writes) or the RLAST handshake")
    a("// (reads) completes, so write-data and response routing never has to")
    a("// disambiguate between masters.  Documented consequence: a slave completes")
    a("// one transaction at a time.")
    a("//")
    a("// A master holds at most one outstanding write and one outstanding read, which")
    a("// keeps that master's W channel unambiguous -- AXI requires write data to stay")
    a("// in order per master.  The interconnect back-pressures, it never re-orders.")
    a("//")
    a("// Any address matching no configured slot goes to u_default_stub and returns")
    a("// DECERR, so an unmapped access can never hang the bus.")
    a("// -----------------------------------------------------------------------------")
    a("")
    a("module pp_axi_interconnect #(")
    a("    parameter integer M_COUNT    = %d," % M)
    a("    parameter integer S_COUNT    = %d," % W_.S)
    a("    parameter integer ADDR_WIDTH = %d," % W_.ADDR)
    a("    parameter integer DATA_WIDTH = %d," % W_.DW)
    a("    parameter integer STRB_WIDTH = DATA_WIDTH / 8,")
    a("    parameter integer ID_WIDTH   = %d" % W_.ID)
    a(") (")
    a("    input  wire                         clk,")
    a("    input  wire                         rst_n,")
    a("")
    a("    // ---- masters ----------------------------------------------------------")
    for name, key in AW_SIGS:
        a("    input  wire [M_COUNT*%-2d-1:0]        m_axi_%s," % (W_[key], name))
    a("    input  wire [M_COUNT-1:0]           m_axi_awvalid,")
    a("    output wire [M_COUNT-1:0]           m_axi_awready,")
    a("    input  wire [M_COUNT*%-2d-1:0]        m_axi_wdata," % W_.DW)
    a("    input  wire [M_COUNT*%-2d-1:0]        m_axi_wstrb," % W_.STRB)
    a("    input  wire [M_COUNT-1:0]           m_axi_wlast,")
    a("    input  wire [M_COUNT-1:0]           m_axi_wvalid,")
    a("    output wire [M_COUNT-1:0]           m_axi_wready,")
    a("    output wire [M_COUNT*%-2d-1:0]        m_axi_bid," % W_.ID)
    a("    output wire [M_COUNT*2-1:0]          m_axi_bresp,")
    a("    output wire [M_COUNT-1:0]           m_axi_bvalid,")
    a("    input  wire [M_COUNT-1:0]           m_axi_bready,")
    for name, key in AR_SIGS:
        a("    input  wire [M_COUNT*%-2d-1:0]        m_axi_%s," % (W_[key], name))
    a("    input  wire [M_COUNT-1:0]           m_axi_arvalid,")
    a("    output wire [M_COUNT-1:0]           m_axi_arready,")
    a("    output wire [M_COUNT*%-2d-1:0]        m_axi_rid," % W_.ID)
    a("    output wire [M_COUNT*%-2d-1:0]        m_axi_rdata," % W_.DW)
    a("    output wire [M_COUNT*2-1:0]          m_axi_rresp,")
    a("    output wire [M_COUNT-1:0]           m_axi_rlast,")
    a("    output wire [M_COUNT-1:0]           m_axi_rvalid,")
    a("    input  wire [M_COUNT-1:0]           m_axi_rready,")
    a("")
    a("    // ---- slaves (one AXI4 port per configured slot) ----------------------")
    for name, key in AW_SIGS:
        a("    output wire [S_COUNT*%-2d-1:0]        s_axi_%s," % (W_[key], name))
    a("    output wire [S_COUNT-1:0]           s_axi_awvalid,")
    a("    input  wire [S_COUNT-1:0]           s_axi_awready,")
    a("    output wire [S_COUNT*%-2d-1:0]        s_axi_wdata," % W_.DW)
    a("    output wire [S_COUNT*%-2d-1:0]        s_axi_wstrb," % W_.STRB)
    a("    output wire [S_COUNT-1:0]           s_axi_wlast,")
    a("    output wire [S_COUNT-1:0]           s_axi_wvalid,")
    a("    input  wire [S_COUNT-1:0]           s_axi_wready,")
    a("    input  wire [S_COUNT*%-2d-1:0]        s_axi_bid," % W_.ID)
    a("    input  wire [S_COUNT*2-1:0]          s_axi_bresp,")
    a("    input  wire [S_COUNT-1:0]           s_axi_bvalid,")
    a("    output wire [S_COUNT-1:0]           s_axi_bready,")
    for name, key in AR_SIGS:
        a("    output wire [S_COUNT*%-2d-1:0]        s_axi_%s," % (W_[key], name))
    a("    output wire [S_COUNT-1:0]           s_axi_arvalid,")
    a("    input  wire [S_COUNT-1:0]           s_axi_arready,")
    a("    input  wire [S_COUNT*%-2d-1:0]        s_axi_rid," % W_.ID)
    a("    input  wire [S_COUNT*%-2d-1:0]        s_axi_rdata," % W_.DW)
    a("    input  wire [S_COUNT*2-1:0]          s_axi_rresp,")
    a("    input  wire [S_COUNT-1:0]           s_axi_rlast,")
    a("    input  wire [S_COUNT-1:0]           s_axi_rvalid,")
    a("    output wire [S_COUNT-1:0]           s_axi_rready")
    a(");")
    a("")
    a("    localparam integer NS   = S_COUNT + 1;   // + the internal default slave")
    a("    localparam integer DEFS = S_COUNT;       // its index")
    a("    localparam integer CL_M = (M_COUNT <= 1) ? 1 : $clog2(M_COUNT);")
    a("    // address bits that select which output word of a wide beat is being")
    a("    // transferred (1 bit for the 2:1 adapter this interconnect sits behind)")
    a("    localparam integer WORD_BITS = 1;")
    a("")
    a("    // genvars are declared up front so the file parses as plain Verilog too")
    a("    genvar gm, bm, g, pm, qm, om;")
    a("")
    a("    wire rst = ~rst_n;   // arbiter.v expects a synchronous active-high reset")
    a("")

    # ------------------------------------------------------------------ decode
    a("    // ======================================================================")
    a("    // Address decode: one region per master, one target slot per region.")
    a("    // A slot is a power-of-two-aligned, power-of-two-sized window, so it is")
    a("    // matched by clearing the offset bits inside the window and comparing")
    a("    // what is left with the (aligned) base address.")
    a("    // The map checker guarantees the windows do not overlap, so the order of")
    a("    // the comparisons below is irrelevant.")
    a("    // ======================================================================")
    a("    reg  [7:0] sel_aw [0:M_COUNT-1];")
    a("    reg  [7:0] sel_ar [0:M_COUNT-1];")
    a("")
    a("    generate")
    a("    for (gm = 0; gm < M_COUNT; gm = gm + 1) begin : g_decode")
    for chan, sel in (("aw", "sel_aw"), ("ar", "sel_ar")):
        a("        always @* begin")
        a("            %s[gm] = 8'd%d;   // default: decode error" % (sel, W_.DEFS))
        for slot in cfg.slots:
            if slot.addr_bits >= W_.ADDR:
                a("            %s[gm] = 8'd%d;   // %s spans the whole address space"
                  % (sel, slot.index, slot.name))
                continue
            # A slot is a power-of-two-aligned, power-of-two-sized window, so it is
            # matched by clearing the *offset* bits inside the window and comparing
            # the result with the (already aligned) base.
            offset_mask = slot.size - 1
            keep_mask = ((1 << W_.ADDR) - 1) & ~offset_mask
            a("            if ((m_axi_%saddr[(gm)*%d +: %d] & %d'h%x) == %d'h%x)  // %s"
              % (chan, W_.ADDR, W_.ADDR, W_.ADDR, keep_mask, W_.ADDR, slot.base,
                 slot.name))
            a("                %s[gm] = 8'd%d;" % (sel, slot.index))
        a("        end")
    a("    end")
    a("    endgenerate")
    a("")

    # ------------------------------------------------- internal slave-side nets
    a("    // ======================================================================")
    a("    // Internal slave-side nets, one slice per internal slave.  Slices")
    a("    // 0..S_COUNT-1 come from the module ports; slice DEFS is driven by the")
    a("    // internal decode-error stub (port map further down).")
    a("    // ======================================================================")
    for name, width in OUT_SIG + IN_SIG:
        a("    %s;" % _decl(_wd(W_, width), NS, "x_" + name))
    a("")
    a("    // responses coming back from the internal decode-error stub")
    for name, width in IN_SIG:
        a("    %s;" % _decl(_wd(W_, width), 1, "d_" + name))
    a("")

    # ------------------------------------------- flat per-(slave, master) nets
    a("    // ---- per-(slave, master) contributions, flattened --------------------")
    flat_bits = [("aw_ready_f", 1), ("w_ready_f", 1), ("b_valid_f", 1), ("b_ready_f", 1),
                 ("ar_ready_f", 1), ("r_valid_f", 1), ("r_ready_f", 1)]
    flat_wide = [("b_id_f", "ID"), ("b_resp_f", 2), ("r_id_f", "ID"),
                 ("r_data_f", "DW"), ("r_resp_f", 2), ("r_last_f", 1)]
    for name, width in flat_bits + flat_wide:
        a("    %s;" % _decl(_wd(W_, width), NS * M, name))
    a("    %s;" % _decl(1, NS * M, "w_ready_flat"))
    a("")

    # --------------------------------------------------------- master outputs
    a("    // ---- master-side outputs: OR of every slave's contribution ----------")
    a("    // A master owns at most one slave per channel, so the reduction is")
    a("    // unambiguous.")
    a("    generate")
    a("    for (om = 0; om < M_COUNT; om = om + 1) begin : g_mout")
    a("        // The slave index is unrolled here, so the reduction is explicit.")
    for sig, flat in (("awready", "aw_ready_f"), ("arready", "ar_ready_f"),
                      ("wready", "w_ready_f"), ("bvalid", "b_valid_f"),
                      ("bready", "b_ready_f"), ("rvalid", "r_valid_f"),
                      ("rready", "r_ready_f")):
        terms = ["%s" % _fs(flat, "om", 1, str(sl)) for sl in range(NS)]
        a("        assign m_axi_%s[om] = %s;" % (sig, _reduce(terms)))
    for base, width, sig, vld in (("b_id_f", "ID", "m_axi_bid", "b_valid_f"),
                                  ("b_resp_f", 2, "m_axi_bresp", "b_valid_f"),
                                  ("r_id_f", "ID", "m_axi_rid", "r_valid_f"),
                                  ("r_data_f", "DW", "m_axi_rdata", "r_valid_f"),
                                  ("r_resp_f", 2, "m_axi_rresp", "r_valid_f"),
                                  ("r_last_f", 1, "m_axi_rlast", "r_valid_f")):
        wv = _wd(W_, width)
        terms = ["(%s & {%d{%s}})" % (_fs(base, "om", wv, str(sl)), wv,
                                     _fs(vld, "om", 1, str(sl)))
                 for sl in range(NS)]
        a("        assign %s[om*%d +: %d] = %s;" % (sig, wv, wv, _reduce(terms)))
    a("    end")
    a("    endgenerate")
    a("")

    # ------------------------------------------------------------------ state
    a("    // ---- per-slave ownership --------------------------------------------")
    a("    // Each register below lives *inside* the per-slave generate block and is")
    a("    // written by exactly one process.  Nothing is shared, so there is no")
    a("    // possibility of two processes driving the same variable.")
    a("    //")
    a("    // `w_busy_flat` / `r_busy_flat` are the only cross-slave signals, and they")
    a("    // are wires, so a single reduction at module scope is enough to answer")
    a("    // \"is master m already busy on some slave?\" without any shared state.")
    a("    %s;" % _decl(1, NS * M, "w_busy_flat"))
    a("    %s;" % _decl(1, NS * M, "r_busy_flat"))
    a("    wire [M_COUNT-1:0] w_busy_m;")
    a("    wire [M_COUNT-1:0] r_busy_m;")
    for m in range(M):
        a("    assign w_busy_m[%d] = %s;" % (m, _reduce(
            ["w_busy_flat[(%d)*M_COUNT + %d]" % (sl, m) for sl in range(NS)])))
        a("    assign r_busy_m[%d] = %s;" % (m, _reduce(
            ["r_busy_flat[(%d)*M_COUNT + %d]" % (sl, m) for sl in range(NS)])))
    a("")
    a("    // Response skid buffers, one beat deep per slave, live inside the slave")
    a("    // block as well.  They exist because AXI allows READY to be combinational")
    a("    // from the slave to the master: without a buffer, a response could be")
    a("    // consumed by the slave and then lost because the master was not ready.")
    a("    // The slave sees READY only while its buffer is free, and the master sees")
    a("    // the buffered beat until it accepts it.")
    a("")

    # ------------------------------------------------------- per-slave channels
    a("    // ======================================================================")
    a("    // Per-slave write and read channels")
    a("    // ======================================================================")
    a("    generate")
    a("    for (g = 0; g < NS; g = g + 1) begin : g_slave")
    a("")
    a("        wire [7:0] MY_SLOT = g[7:0];")
    a("")
    a("        // ---------------- this slave's state: one register, one driver -------")
    a("        reg                 w_act;        // a write transaction is in flight")
    a("        reg [%-2d-1:0]       w_own;        // and which master owns it" % CLM)
    a("        reg                 w_aw_sent;    // downstream AW accepted")
    a("        reg                 w_last_seen;  // final W beat accepted downstream")
    a("        reg                 w_b_buf_v;    // write response buffered")
    a("        reg [%-2d-1:0]       w_b_buf_id;" % W_.ID)
    a("        reg [1:0]           w_b_buf_resp;")
    a("        reg                 r_act;        // a read transaction is in flight")
    a("        reg [%-2d-1:0]       r_own;" % CLM)
    a("        reg                 r_ar_sent;    // downstream AR accepted")
    a("        reg                 r_r_buf_v;    // read beat buffered")
    a("        reg                 r_r_buf_end;  // and it was the last of the burst")
    a("        reg [%-2d-1:0]       r_r_buf_id;" % W_.ID)
    a("        reg [%-2d-1:0]       r_r_buf_data;" % W_.DW)
    a("        reg [1:0]           r_r_buf_resp;")
    a("")
    a("        // Cross-slave ownership, as wires: the module-scope reduction turns")
    a("        // these into the per-master busy flags.")
    for _m in range(M):
        a("        assign w_busy_flat[(g)*M_COUNT + %d] = w_act && (w_own == %d);" % (_m, _m))
        a("        assign r_busy_flat[(g)*M_COUNT + %d] = r_act && (r_own == %d);" % (_m, _m))
    a("")

    # ---------------------------------------------------------- write channel
    a("        // ================= write channel =================")
    _emit_payload_regs(a, W_, "aw")
    _emit_payload_drivers(a, W_, "aw")
    a("        assign %s = w_act && !w_aw_sent;" % _sl("x_awvalid", 1))
    a("")
    a("        wire [M_COUNT-1:0] w_req;")
    a("        for (qm = 0; qm < M_COUNT; qm = qm + 1) begin : g_wreq")
    a("            assign w_req[qm] = m_axi_awvalid[qm] && (sel_aw[qm] == MY_SLOT)")
    a("                               && !w_act && !w_busy_m[qm];")
    a("        end")
    a("")
    a("        wire [M_COUNT-1:0] w_grant;")
    a("        wire               w_grant_valid;")
    a("        wire [CL_M-1:0]    w_grant_encoded;")
    a("")
    _emit_arbiter(a, "u_arb_wr", "w")
    a("")
    a("        wire aw_accept = |w_grant;")
    for m in range(M):
        a("        assign %s = w_grant_valid && w_grant[%d];" % (_fs("aw_ready_f", m, 1), m))
    a("")
    a("        // Write data and the write response follow the owner, so the master's")
    a("        // W channel never has to be split between two slaves.")
    a("        assign %s = w_act && w_aw_sent && m_axi_wvalid[w_own];"
      % _sl("x_wvalid", 1))
    a("        assign %s = m_axi_wdata[((w_own)*%d) +: %d];" % (_sl("x_wdata", W_.DW), W_.DW, W_.DW))
    a("        assign %s = m_axi_wstrb[((w_own)*%d) +: %d];" % (_sl("x_wstrb", W_.STRB), W_.STRB, W_.STRB))
    a("        assign %s = m_axi_wlast[w_own];" % _sl("x_wlast", 1))
    a("")
    # WREADY must only rise once this transaction's AW has actually been accepted
    # downstream.  A slave commonly holds WREADY low until it has seen the AW, and
    # some hold it high immediately; asserting master-side WREADY early would let
    # the master believe a beat was taken when nothing downstream can accept it,
    # and the beat would be silently dropped.
    for m in range(M):
        a("        assign %s = (w_own == %d) && w_aw_sent && !w_b_buf_v && %s;"
          % (_fs("w_ready_f", m, 1), m, _sl("x_wready", 1)))
        a("        assign w_ready_flat[(g)*M_COUNT + %d] = (w_own == %d) && w_aw_sent && !w_b_buf_v && %s;"
          % (m, m, _sl("x_wready", 1)))
    a("")
    a("        wire w_last_beat = w_act && w_aw_sent && %s && %s && %s;"
      % (_sl("x_wvalid", 1), _sl("x_wready", 1), _sl("x_wlast", 1)))
    a("        wire w_data_done = w_act && w_aw_sent && (w_last_seen || w_last_beat);")
    a("        // Accept the write response only while the skid buffer is free.")
    a("        assign %s = w_data_done && !w_b_buf_v;" % _sl("x_bready", 1))
    a("")
    a("        wire w_b_push = %s && %s;" % (_sl("x_bready", 1), _sl("x_bvalid", 1)))
    a("        wire w_b_pop  = %s;" % _reduce(
        ["(%s && %s)" % (_fs("b_valid_f", m, 1), _fs("b_ready_f", m, 1))
         for m in range(M)]))
    a("")
    for m in range(M):
        sel = "(w_own == %d)" % m
        a("        assign %s = %s && w_b_buf_v;" % (_fs("b_valid_f", m, 1), sel))
        a("        assign %s = %s && w_b_buf_v;" % (_fs("b_ready_f", m, 1), sel))
        a("        assign %s = %s ? w_b_buf_id : {%d{1'b0}};"
          % (_fs("b_id_f", m, W_.ID), sel, W_.ID))
        a("        assign %s = %s ? w_b_buf_resp : {2{1'b0}};"
          % (_fs("b_resp_f", m, 2), sel))
    a("        wire w_bhs = %s;" % _reduce(
        ["(%s && %s)" % (_fs("b_valid_f", m, 1), _fs("b_ready_f", m, 1)) for m in range(M)]))
    a("")
    _emit_payload_latch(a, W_, M, "aw", "aw_accept", "w")
    a("")
    a("        always @(posedge clk or negedge rst_n) begin")
    a("            if (!rst_n) begin")
    _emit_state_reset(a, "w", CLM)
    a("                w_b_buf_v   <= 1'b0;")
    a("                w_b_buf_id <= {%d{1'b0}};" % W_.ID)
    a("                w_b_buf_resp <= 2'b00;")
    a("            end else begin")
    a("                if (w_b_push) begin")
    a("                    w_b_buf_v   <= 1'b1;")
    a("                    w_b_buf_id <= %s;" % _sl("x_bid", W_.ID))
    a("                    w_b_buf_resp <= %s;" % _sl("x_bresp", 2))
    a("                end else if (w_b_pop) begin")
    a("                    w_b_buf_v <= 1'b0;")
    a("                end")
    a("                if (w_bhs) begin")
    _emit_state_clear(a, "w", CLM)
    a("                end else begin")
    a("                    if (aw_accept && !w_act) begin")
    a("                        w_act      <= 1'b1;")
    a("                        w_own <= w_grant_encoded;")
    a("                        w_aw_sent     <= 1'b0;")
    a("                        w_last_seen   <= 1'b0;")
    a("                    end")
    a("                    if (w_act && !w_aw_sent && %s) w_aw_sent <= 1'b1;"
      % _sl("x_awready", 1))
    a("                    if (w_last_beat) w_last_seen <= 1'b1;")
    a("                end")
    a("            end")
    a("        end")
    a("")

    # ----------------------------------------------------------- read channel
    a("        // ================= read channel =================")
    a("        reg [8:0]           r_left;   // output beats still to return")
    a("        reg [WORD_BITS-1:0] r_word;   // output word index of the current beat")
    a("        reg                 r_wide_q; // latched wide/narrow decision")
    _emit_payload_regs(a, W_, "ar")
    _emit_payload_drivers(a, W_, "ar")
    a("        assign %s = r_act && !r_ar_sent;" % _sl("x_arvalid", 1))
    a("        // Accept one read beat only while the skid buffer is free, so a")
    a("        // response can never be consumed and then lost to a master that was")
    a("        // not ready yet.")
    a("        assign %s = r_act && r_ar_sent && !r_r_buf_v;" % _sl("x_rready", 1))
    a("")
    a("        wire [M_COUNT-1:0] r_req;")
    a("        for (qm = 0; qm < M_COUNT; qm = qm + 1) begin : g_rreq")
    a("            assign r_req[qm] = m_axi_arvalid[qm] && (sel_ar[qm] == MY_SLOT)")
    a("                               && !r_act && !r_busy_m[qm];")
    a("        end")
    a("")
    a("        wire [M_COUNT-1:0] r_grant;")
    a("        wire               r_grant_valid;")
    a("    wire [CL_M-1:0]    r_grant_encoded;")
    a("")
    _emit_arbiter(a, "u_arb_rd", "r")
    a("")
    a("        wire ar_accept = |r_grant;")
    for m in range(M):
        a("        assign %s = r_grant_valid && r_grant[%d];" % (_fs("ar_ready_f", m, 1), m))
    a("")
    a("        wire r_push = %s && %s;" % (_sl("x_rready", 1), _sl("x_rvalid", 1)))
    a("        wire r_pop  = %s;" % _reduce(
        ["(%s && %s)" % (_fs("r_valid_f", m, 1), _fs("r_ready_f", m, 1))
         for m in range(M)]))
    a("        // A buffered beat that was the last of its burst ends the read once")
    a("        // the master has taken it.")
    a("        wire r_finish = %s && r_r_buf_end;" % _reduce(
        ["(%s && %s)" % (_fs("r_valid_f", m, 1), _fs("r_ready_f", m, 1))
         for m in range(M)]))
    a("")
    for m in range(M):
        sel = "(r_own == %d)" % m
        a("        assign %s = %s && r_r_buf_v;" % (_fs("r_valid_f", m, 1), sel))
        a("        assign %s = %s && r_r_buf_v;" % (_fs("r_ready_f", m, 1), sel))
        a("        assign %s = %s ? r_r_buf_id : {%d{1'b0}};"
          % (_fs("r_id_f", m, W_.ID), sel, W_.ID))
        a("        assign %s = %s ? r_r_buf_data : {%d{1'b0}};"
          % (_fs("r_data_f", m, W_.DW), sel, W_.DW))
        a("        assign %s = %s ? r_r_buf_resp : {2{1'b0}};"
          % (_fs("r_resp_f", m, 2), sel))
        a("        assign %s = %s && r_r_buf_end;" % (_fs("r_last_f", m, 1), sel))
    a("")
    _emit_payload_latch(a, W_, M, "ar", "ar_accept", "r")
    a("")
    a("        always @(posedge clk or negedge rst_n) begin")
    a("            if (!rst_n) begin")
    _emit_state_reset(a, "r", CLM)
    a("                r_r_buf_v   <= 1'b0;")
    a("                r_r_buf_end <= 1'b0;")
    a("                r_r_buf_id <= {%d{1'b0}};" % W_.ID)
    a("                r_r_buf_data <= {%d{1'b0}};" % W_.DW)
    a("                r_r_buf_resp <= 2'b00;")
    a("                r_left   <= 9'd0;")
    a("                r_word   <= {WORD_BITS{1'b0}};")
    a("                r_wide_q <= 1'b0;")
    a("            end else begin")
    a("                if (r_push) begin")
    a("                    r_r_buf_v   <= 1'b1;")
    a("                    r_r_buf_end <= %s;" % _sl("x_rlast", 1))
    a("                    r_r_buf_id <= %s;" % _sl("x_rid", W_.ID))
    a("                    r_r_buf_data <= %s;" % _sl("x_rdata", W_.DW))
    a("                    r_r_buf_resp <= %s;" % _sl("x_rresp", 2))
    a("                end else if (r_pop) begin")
    a("                    r_r_buf_v <= 1'b0;")
    a("                end")
    a("                if (r_finish) begin")
    _emit_state_clear(a, "r", CLM)
    a("                end else begin")
    a("                    if (ar_accept && !r_act) begin")
    a("                        r_act      <= 1'b1;")
    a("                        r_own <= r_grant_encoded;")
    a("                        r_ar_sent     <= 1'b0;")
    a("                    end else if (r_act && !r_ar_sent && %s) begin"
      % _sl("x_arready", 1))
    a("                        r_ar_sent <= 1'b1;")
    a("                    end")
    a("                    if (r_push && !%s) begin" % _sl("x_rlast", 1))
    a("                        r_left <= r_left - 9'd1;")
    a("                        r_word <= r_wide_q ? ~r_word : r_word;")
    a("                    end")
    a("                end")
    a("            end")
    a("        end")
    a("")
    a("    end")
    a("    endgenerate")
    a("")

    # ------------------------------------------------- port <-> internal map
    a("    // ======================================================================")
    a("    // Port map: internal slice i <-> s_axi_*[i] for every configured slot.")
    a("    // ======================================================================")
    a("    generate")
    a("    for (pm = 0; pm < S_COUNT; pm = pm + 1) begin : g_portmap")
    a("        // IN_SIG: the slave drives the interconnect, so the internal net is")
    a("        // driven from the port.")
    for name, width in IN_SIG:
        wv = _wd(W_, width)
        a("        assign %s = %s;" % (_sln("x_" + name, "pm", wv), _sln("s_axi_" + name, "pm", wv)))
    a("        // OUT_SIG: the interconnect drives the slave, so the port is driven")
    a("        // from the internal net.")
    for name, width in OUT_SIG:
        wv = _wd(W_, width)
        a("        assign %s = %s;" % (_sln("s_axi_" + name, "pm", wv), _sln("x_" + name, "pm", wv)))
    a("    end")
    a("    endgenerate")
    a("")

    # ------------------------------------------------------------ default stub
    a("    // ======================================================================")
    a("    // Internal decode-error default slave.  An address matching no configured")
    a("    // slot is routed here and answered with DECERR, so an unmapped access")
    a("    // completes with correct handshakes instead of hanging the bus.")
    a("    // ======================================================================")
    a("    pp_axi_stub_slave #(")
    a("        .ADDR_WIDTH(ADDR_WIDTH),")
    a("        .DATA_WIDTH(DATA_WIDTH),")
    a("        .STRB_WIDTH(STRB_WIDTH),")
    a("        .ID_WIDTH(ID_WIDTH)")
    a("    ) u_default_stub (")
    a("        .clk(clk),")
    a("        .rst_n(rst_n),")
    for name, width in OUT_SIG:
        a("        .s_axi_%s(%s)," % (name, _sln("x_" + name, "DEFS", _wd(W_, width))))
    for idx, (name, width) in enumerate(IN_SIG):
        sep = "," if idx < len(IN_SIG) - 1 else ""
        a("        .s_axi_%s(d_%s)%s" % (name, name, sep))
    a("    );")
    a("")
    for name, width in IN_SIG:
        a("    assign %s = d_%s;" % (_sln("x_" + name, "DEFS", _wd(W_, width)), name))
    a("")
    a("endmodule")
    a("")
    a("`default_nettype wire")
    a("")

    return w(path, "\n".join(L))


_PAYLOAD = [("id", "ID"), ("addr", "ADDR"), ("len", 8), ("size", 3),
            ("burst", 2), ("lock", 1), ("prot", 3)]


def _emit_payload_regs(a, W_, chan):
    for suffix, key in _PAYLOAD:
        a("        reg [%d-1:0] %s%s_r;" % (W_[key], chan, suffix))


def _emit_payload_drivers(a, W_, chan):
    for suffix, key in _PAYLOAD:
        width = W_[key]
        a("        assign %s = %s%s_r;" % (_sl("x_%s%s" % (chan, suffix), width), chan, suffix))


def _emit_payload_latch(a, W_, M, chan, accept, gvar):
    a("        always @(posedge clk or negedge rst_n) begin")
    a("            if (!rst_n) begin")
    for suffix, key in _PAYLOAD:
        a("                %s%s_r <= {%d{1'b0}};" % (chan, suffix, W_[key]))
    a("            end else if (%s) begin" % accept)
    for m in range(M):
        for suffix, key in _PAYLOAD:
            width = W_[key]
            a("                if (%s_grant[%d]) %s%s_r <= m_axi_%s%s[(%d)*%d +: %d];"
              % (gvar, m, chan, suffix, chan, suffix, m, width, width))
    a("            end")
    a("        end")


def _emit_arbiter(a, inst, gvar):
    a("        arbiter #(")
    a("            .PORTS(M_COUNT),")
    a("            .ARB_TYPE_ROUND_ROBIN(1),")
    a("            .ARB_BLOCK(1),")
    a("            .ARB_BLOCK_ACK(0),")
    a("            .ARB_LSB_HIGH_PRIORITY(0)")
    a("        ) %s (" % inst)
    a("            .clk(clk),")
    a("            .rst(rst),")
    a("            .request(%s_req)," % gvar)
    a("            .acknowledge({M_COUNT{1'b1}}),")
    a("            .grant(%s_grant)," % gvar)
    a("            .grant_valid(%s_grant_valid)," % gvar)
    a("            .grant_encoded(%s_grant_encoded)" % gvar)
    a("        );")


def _emit_state_reset(a, chan, CLM):
    a("                %s_act <= 1'b0;" % chan)
    a("                %s_own <= {%d{1'b0}};" % (chan, CLM))
    if chan == "w":
        a("                w_aw_sent   <= 1'b0;")
        a("                w_last_seen <= 1'b0;")
    else:
        a("                r_ar_sent <= 1'b0;")


def _emit_state_clear(a, chan, CLM):
    a("                %s_act <= 1'b0;" % chan)
    a("                %s_own <= {%d{1'b0}};" % (chan, CLM))
    if chan == "w":
        a("                w_aw_sent   <= 1'b0;")
        a("                w_last_seen <= 1'b0;")
    else:
        a("                r_ar_sent <= 1'b0;")


# =============================================================================
# 2. SystemVerilog configuration package
# =============================================================================

def gen_sv_pkg(cfg, path):
    L = []
    a = L.append
    a(banner(cfg))
    a("`ifndef PP_SOC_CFG_PKG_SV")
    a("`define PP_SOC_CFG_PKG_SV")
    a("")
    a("// Every width, size and base address the RTL needs, derived from config.")
    a("// The SoC top uses these instead of literals, so a config change needs no RTL edit.")
    a("package pp_soc_cfg_pkg;")
    a("")
    a("    // ---- bus ----")
    a("    localparam int PP_M_COUNT       = %d;" % cfg.n_masters)
    a("    localparam int PP_S_COUNT       = %d;" % cfg.n_slots)
    a("    localparam int PP_ADDR_WIDTH    = %d;" % cfg.addr_width)
    a("    localparam int PP_CORE_DW       = %d;" % cfg.core_data_width)
    a("    localparam int PP_XBAR_DW       = %d;" % cfg.xbar_data_width)
    a("    localparam int PP_STRB_WIDTH    = %d;" % cfg.strb_width)
    a("    localparam int PP_CORE_STRB     = %d;" % cfg.core_strb_width)
    a("    localparam int PP_ID_WIDTH      = %d;" % cfg.id_width)
    a("")
    a("    // ---- system ----")
    a("    localparam int unsigned PP_CLK_FREQ_HZ   = %d;" % cfg.clock_freq_hz)
    a("    localparam int unsigned PP_CLK_PERIOD_PS = %d;" % cfg.clock_period_ps)
    a("    localparam int unsigned PP_RESET_CYCLES  = %d;" % cfg.reset_cycles)
    a("    localparam logic [31:0] PP_RESET_VECTOR  = 32'h%08x;" % cfg.reset_vector)
    a("    localparam logic [30:0] PP_RESET_VECTOR_HI = 31'h%07x;" % (cfg.reset_vector >> 1))
    a("")
    a("    // ---- uart ----")
    a("    localparam int unsigned PP_UART_BAUD    = %d;" % cfg.uart_baud)
    a("    localparam int unsigned PP_UART_DIVISOR = %d;" % cfg.uart_divisor)
    a("")
    for slot in cfg.slots:
        a("    // %s" % slot.name)
        a("    localparam logic [31:0] PP_%s_BASE = 32'h%08x;" % (slot.name.upper(), slot.base))
        a("    localparam logic [31:0] PP_%s_SIZE = 32'h%08x;" % (slot.name.upper(), slot.size))
        a("    localparam bit PP_%s_ENABLED = 1'b%d;" % (slot.name.upper(), 1 if slot.enabled else 0))
        a("    localparam bit PP_%s_SIM_ONLY = 1'b%d;" % (slot.name.upper(), 1 if slot.sim_only else 0))
        a("    localparam bit PP_%s_BRIDGE = 1'b%d;" % (slot.name.upper(), 1 if slot.bridge else 0))
    a("")
    a("endpackage")
    a("")
    a("`endif")
    a("")
    return w(path, "\n".join(L))


# =============================================================================
# 3. C memory-map header
# =============================================================================

def gen_c_header(cfg, path):
    L = []
    a = L.append
    a("/*" + "=" * 76)
    a(" * GENERATED FILE -- DO NOT EDIT")
    a(" *")
    a(" * Produced by tools/gen_interconnect.py from config/soc_config.yaml.")
    a(" * Change the config and re-run `make gen`.")
    a(" *" + "=" * 76 + " */")
    a("")
    a("#ifndef PP_MEMMAP_H")
    a("#define PP_MEMMAP_H")
    a("")
    a('#include <stdint.h>')
    a("")
    a("/* ---- bus / system ---- */")
    a("#define PP_CLK_FREQ_HZ     %du" % cfg.clock_freq_hz)
    a("#define PP_UART_BAUD       %du" % cfg.uart_baud)
    a("#define PP_UART_DIVISOR    %du" % cfg.uart_divisor)
    a("#define PP_RESET_VECTOR    0x%08x" % cfg.reset_vector)
    a("")
    a("/* ---- slave slots ---- */")
    for slot in cfg.slots:
        a("")
        a("/* %s%s%s */"
          % (slot.name,
             " [simulation only]" if slot.sim_only else "",
             " [reserved: not enabled yet]" if not slot.enabled else ""))
        a("#define %-22s 0x%08xU" % (cfg.h_addr(slot.name), slot.base))
        a("#define %-22s 0x%08xU" % (cfg.h_size(slot.name), slot.size))
        a("#define %-22s %d" % (cfg.c_define_name(slot.name) + "_ENABLED",
                                1 if slot.enabled else 0))
    a("")
    a("/* ---- core-reserved regions: never allocate software buffers here ---- */")
    for region in cfg.core_regions:
        a("#define PP_%s_BASE 0x%08xU" % (cfg.c_define_name(region["name"]) + "_", region["base"]))
        a("#define PP_%s_SIZE 0x%08xU" % (cfg.c_define_name(region["name"]) + "_", region["size"]))
    a("")
    a("#endif /* PP_MEMMAP_H */")
    a("")
    return w(path, "\n".join(L))


# =============================================================================
# 4. linker script
# =============================================================================

def gen_linker(cfg, path):
    imem, dmem = cfg.imem, cfg.dmem
    stack_size = 0x4000
    L = []
    a = L.append
    a("/*" + "=" * 76)
    a(" * GENERATED FILE -- DO NOT EDIT")
    a(" *")
    a(" * Linker script produced by tools/gen_interconnect.py from")
    a(" * config/soc_config.yaml.  Memory origins, sizes and the reset vector all come")
    a(" * from config; changing software.memory or a slot size needs no manual edit.")
    a(" *" + "=" * 76 + " */")
    a("")
    a("OUTPUT_ARCH(riscv)")
    a("ENTRY(_start)")
    a("")
    a("MEMORY")
    a("{")
    a("  imem  (rx!a)  : ORIGIN = 0x%08x, LENGTH = 0x%08x" % (imem.base, imem.size))
    a("  dmem  (rw!a)  : ORIGIN = 0x%08x, LENGTH = 0x%08x" % (dmem.base, dmem.size - stack_size))
    a("  dstack(rw!a)  : ORIGIN = 0x%08x, LENGTH = 0x%08x"
      % (dmem.base + dmem.size - stack_size, stack_size))
    a("}")
    a("")
    a("SECTIONS")
    a("{")
    a("  .text.init : {")
    a("    KEEP(*( .text.init ))")
    a("    KEEP(*( .text.init.* ))")
    a("    . = ALIGN(4);")
    a("  } > imem")
    a("")
    a("  .text : {")
    a("    *(.text .text.*)")
    a("    . = ALIGN(4);")
    a("  } > imem")
    a("")
    a("  . = ALIGN(4);")
    a("  __global_pointer$ = . + 0x800;")
    a("")
    a("  .rodata : {")
    a("    *(.rodata .rodata.*)")
    a("    *(.srodata .srodata.*)")
    a("    . = ALIGN(4);")
    a("  } > imem")
    a("")
    a("  .data : AT (__global_pointer$) {")
    a("    PROVIDE( __data_start = . );")
    a("    *(.data .data.*)")
    a("    *(.sdata .sdata.*)")
    a("    . = ALIGN(4);")
    a("    PROVIDE( __data_end = . );")
    a("  } > dmem")
    a("")
    a("  .bss (NOLOAD) : {")
    a("    PROVIDE( __bss_start = . );")
    a("    *(.bss .bss.*)")
    a("    *(.sbss .sbss.*)")
    a("    *(COMMON)")
    a("    . = ALIGN(4);")
    a("    PROVIDE( __bss_end = . );")
    a("  } > dmem")
    a("")
    a("  . = ALIGN(4);")
    a("  __heap_start = .;")
    a("  __heap_end   = ORIGIN(dmem) + LENGTH(dmem);")
    a("")
    a("  _end = .;")
    a("  PROVIDE(end = .);")
    a("")
    a("  PROVIDE(_stack_top = ORIGIN(dstack) + LENGTH(dstack));")
    a("  ASSERT((_stack_top > __bss_end), \"stack overlaps bss\")")
    a("}")
    a("")
    return w(path, "\n".join(L))


# =============================================================================
# 5. make fragment
# =============================================================================

def gen_make_fragment(cfg, path):
    defs = [
        ("PP_M_COUNT", cfg.n_masters),
        ("PP_S_COUNT", cfg.n_slots),
        ("PP_ADDR_WIDTH", cfg.addr_width),
        ("PP_CORE_DW", cfg.core_data_width),
        ("PP_XBAR_DW", cfg.xbar_data_width),
        ("PP_ID_WIDTH", cfg.id_width),
        ("PP_CLK_FREQ_HZ", cfg.clock_freq_hz),
        ("PP_CLK_PERIOD_PS", cfg.clock_period_ps),
        ("PP_RESET_CYCLES", cfg.reset_cycles),
        ("PP_RESET_VECTOR", "0x%08x" % cfg.reset_vector),
        ("PP_UART_BAUD", cfg.uart_baud),
        ("PP_UART_DIVISOR", cfg.uart_divisor),
        ("PP_HEX_WORD_BYTES", cfg.hex_word_bytes),
        ("PP_SIM_TIMEOUT_NS", cfg.sim_timeout_ns),
        ("PP_DEFAULT_SEED", cfg.sim_default_seed),
    ]
    L = ["# GENERATED FILE -- DO NOT EDIT (tools/gen_interconnect.py). Do not include by hand.",
         "# The Makefile includes this file; it carries every value that comes from",
         "# config/soc_config.yaml so no address or width is written twice.",
         ""]
    for key, value in defs:
        L.append("%s = %s" % (key, value))
    L.append("")
    L.append("PP_SLOT_NAMES = %s" % " ".join(s.name for s in cfg.slots))
    for slot in cfg.slots:
        L.append("%s_BASE = 0x%08x" % (slot.name.upper(), slot.base))
        L.append("%s_SIZE = 0x%08x" % (slot.name.upper(), slot.size))
    L.append("")
    L.append("PP_MASTER_NAMES = %s" % " ".join(cfg.master_names))
    L.append("")
    L.append("SW_TOOLCHAIN_PATH = %s" % cfg.sw_toolchain_path)
    L.append("SW_PREFIX = %s" % cfg.sw_toolchain_prefix)
    L.append("SW_MARCH = %s" % cfg.sw_march)
    L.append("SW_MABI = %s" % cfg.sw_mabi)
    L.append("SW_OPT = %s" % cfg.sw_opt)
    L.append("SW_LOAD_ADDR = 0x%08x" % cfg.sw_load_addr)
    L.append("SW_ISA = %s" % cfg.sw_isa)
    L.append("SW_ABI = %s" % cfg.sw_abi)
    L.append("")
    L.append("VCS_COMPILE_FLAGS = %s" % cfg.sim_vcs_compile)
    L.append("VCS_ELAB_FLAGS = %s" % cfg.sim_vcs_elab)
    L.append("")
    return w(path, "\n".join(L))


# =============================================================================
# 6. VeeR options + filelist
# =============================================================================

def gen_veer_opts(cfg, path):
    opts = ["reset_vec=0x%08x" % cfg.reset_vector]
    for key in sorted(cfg.veer_options):
        opts.append("%s=%s" % (key, cfg.veer_options[key]))
    return w(path, "# one -set= argument per line, consumed by tools/gen_veer_config.py\n"
                   + "\n".join(opts) + "\n")


def gen_filelist(cfg, path):
    """Compile order for the generated RTL and the pinned VeeR core."""
    veer = os.path.join(ROOT, cfg.core_rtl_dir)
    files = []
    # The core's own compile order, with $RV_ROOT substituted.  Using the core's
    # flist rather than re-deriving it means an upstream re-order is picked up
    # automatically.  Missing files are reported here rather than by the compiler.
    with open(os.path.join(veer, "design", "flist")) as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            line = line.replace("$RV_ROOT", veer)
            for token in line.split():
                if token.startswith("-"):
                    continue
                if not os.path.isfile(token):
                    raise ConfigError("VeeR file list references a missing file: %s" % token)
            files.append(line)
    L = ["# GENERATED FILE -- DO NOT EDIT (tools/gen_interconnect.py).",
         "# Compile order: VeeR core first, then vendor RTL, then generated RTL,",
         "# then hand-written PowerPulse RTL.",
         ""]
    L += ["+incdir+%s" % os.path.join(ROOT, "sim", "gen", "veer"),
          "+incdir+%s" % os.path.join(veer, "design", "include"),
          "+incdir+%s" % os.path.join(veer, "design", "lib"),
          ""]
    # The core's own flist assumes the package header and the include paths are
    # supplied by its makefile, so this wrapper supplies them explicitly.
    L.append(os.path.join(veer, "design", "include", "el2_def.sv"))
    L += files
    uart_src = os.path.join(ROOT, "rtl", "vendor", "axi-lite-uart", "src")
    L += [
        os.path.join(ROOT, "rtl/vendor/verilog-axi/priority_encoder.v"),
        os.path.join(ROOT, "rtl/vendor/verilog-axi/arbiter.v"),
        "+incdir+%s" % os.path.join(ROOT, "sim", "gen", "uart"),
        "+incdir+%s" % os.path.join(uart_src, "include"),
        "+incdir+%s" % os.path.join(uart_src, "rtl"),
        # The generated UART macro prelude must be parsed *before* the IP, so that
        # the IP's own axi_uart.vh expands to nothing and the config-derived
        # baud/clock macros are the ones it sees.
        "sim/gen/uart/pp_uart_prelude.sv",
        os.path.join(uart_src, "rtl", "axi_internal_fifo.v"),
        os.path.join(uart_src, "rtl", "uart_parity_bit_compute.v"),
        os.path.join(uart_src, "rtl", "uart_receiver.v"),
        os.path.join(uart_src, "rtl", "uart_transmitter.v"),
        os.path.join(uart_src, "rtl", "uart_controller.v"),
        os.path.join(uart_src, "rtl", "axi_uart_top.v"),
        "sim/gen/pp_soc_cfg_pkg.sv",
        "sim/gen/bus/pp_axi_interconnect.sv",
        os.path.join(ROOT, "rtl/bus/pp_axi_downsize.v"),
        os.path.join(ROOT, "rtl/bus/pp_axi4_to_axil.v"),
        os.path.join(ROOT, "rtl/ip/stub/pp_axi_stub_slave.v"),
        os.path.join(ROOT, "rtl/mem/pp_axi_ram.sv"),
        os.path.join(ROOT, "rtl/ip/uart/pp_uart.sv"),
        os.path.join(ROOT, "rtl/core/pp_veer_core.sv"),
        os.path.join(ROOT, "rtl/top/pp_soc_interconnect.sv"),
        os.path.join(ROOT, "rtl/top/powerpulse_soc.sv"),
    ]
    return w(path, "\n".join(L) + "\n")


# =============================================================================
# 7. documentation table
# =============================================================================

def gen_doc_table(cfg, path):
    L = []
    a = L.append
    a("# Memory map (generated)")
    a("")
    a("> GENERATED by `tools/gen_interconnect.py` from `config/soc_config.yaml`.")
    a("> Do not edit; change the config and run `make gen`.")
    a("")
    a("| Slot | Module | Base | End | Size | Protocol | Bridge | State |")
    a("|---|---|---|---|---|---|---|---|")
    for slot in sorted(cfg.slots, key=lambda s: s.base):
        state = "enabled" if slot.enabled else "**reserved (stub)**"
        if slot.enabled and slot.sim_only:
            state = "simulation only"
        a("| %d | `%s` | `0x%08x` | `0x%08x` | %d KiB | %s | %s | %s |" % (
            slot.index, slot.name, slot.base, slot.end - 1, slot.size // 1024,
            slot.protocol, "yes" if slot.bridge else "no", state))
    a("| - | *unmapped / default* | any | any | - | AXI4 stub | - | DECERR |")
    for region in cfg.core_regions:
        a("| - | `%s` (core-internal) | `0x%08x` | `0x%08x` | %d KiB | - | - | reserved |" % (
            region["name"], region["base"], region["base"] + region["size"] - 1,
            region["size"] // 1024))
    a("")
    a("Derived system values")
    a("")
    a("| Parameter | Value |")
    a("|---|---|")
    a("| interconnect masters | %d (`%s`) |" % (cfg.n_masters, "`, `".join(cfg.master_names)))
    a("| interconnect slaves | %d slots + 1 internal decode-error default |" % cfg.n_slots)
    a("| core-side AXI data width | %d bit |" % cfg.core_data_width)
    a("| interconnect AXI data width | %d bit |" % cfg.xbar_data_width)
    a("| address width | %d bit |" % cfg.addr_width)
    a("| AXI ID width | %d bit (VeeR uses 3) |" % cfg.id_width)
    a("| arbitration | %s, one arbiter per (slave, channel) |" % cfg.arbitration)
    a("| clock | %d Hz (period %d ps) |" % (cfg.clock_freq_hz, cfg.clock_period_ps))
    a("| reset | active-low, async assert / sync release, %d cycles |" % cfg.reset_cycles)
    a("| reset vector | `0x%08x` |" % cfg.reset_vector)
    a("| UART | %d baud, divisor %d (clock/baud) |" % (cfg.uart_baud, cfg.uart_divisor))
    a("| hex word width | %d bytes |" % cfg.hex_word_bytes)
    a("| instruction memory | %d KiB at `0x%08x` |" % (cfg.imem.size // 1024, cfg.imem.base))
    a("| data memory | %d KiB at `0x%08x` |" % (cfg.dmem.size // 1024, cfg.dmem.base))
    a("")
    return w(path, "\n".join(L))


# =============================================================================
# main
# =============================================================================

def generate(cfg, gendir):
    ensure_dir(gendir)
    outputs = []
    outputs.append(gen_crossbar(cfg, os.path.join(gendir, "bus", "pp_axi_interconnect.sv")))
    outputs.append(gen_sv_pkg(cfg, os.path.join(gendir, "pp_soc_cfg_pkg.sv")))
    outputs.append(gen_c_header(cfg, os.path.join(gendir, "pp_memmap.h")))
    outputs.append(gen_linker(cfg, os.path.join(gendir, "powerpulse.ld")))
    outputs.append(gen_make_fragment(cfg, os.path.join(gendir, "config.mk")))
    outputs.append(gen_veer_opts(cfg, os.path.join(gendir, "veer_opts.txt")))
    outputs.append(gen_filelist(cfg, os.path.join(gendir, "filelist.f")))
    outputs.append(gen_doc_table(cfg, os.path.join(ROOT, "docs", "generated", "memory_map.md")))
    return outputs


def main(argv):
    check_only = "--check-only" in argv
    config_path = "config/soc_config.yaml"
    for arg in argv[1:]:
        if not arg.startswith("-"):
            config_path = arg

    try:
        cfg = load_config(os.path.join(ROOT, config_path))
    except ConfigError as exc:
        print("gen: %s" % exc)
        return 1

    errors = map_checker.check(cfg)
    if errors:
        print("gen: memory map is illegal, refusing to generate")
        for err in errors:
            print("  ERROR %s" % err)
        return 1

    if check_only:
        print("gen: memory map is legal (%d slots)" % cfg.n_slots)
        return 0

    gendir = os.path.join(ROOT, "sim", "gen")
    outputs = generate(cfg, gendir)
    print("gen: config %s -> %d files" % (os.path.relpath(cfg.path, ROOT), len(outputs)))
    for path in outputs:
        print("      %s" % os.path.relpath(path, ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
