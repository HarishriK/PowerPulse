// -----------------------------------------------------------------------------
// pp_soc_interconnect
//
// The SoC's interconnect fabric, separated from the core so that the core-less
// integration tests drive *exactly the same* RTL the SoC runs:
//
//     master 0/1/2 (64-bit AXI4; the core's IFU / LSU / SB)
//        -> pp_axi_downsize  x3
//        -> pp_axi_interconnect   (generated from config/soc_config.yaml)
//           -> imem, dmem                 pp_axi_ram          (AXI4, native)
//           -> uart                       bridge -> pp_uart
//           -> timer/gpio/hap/ppmc/awec   pp_axi_stub_slave   (reserved Phase 2)
//           -> status                     bridge -> simulation reporter (PP_SIM)
//           -> default                    pp_axi_stub_slave   (inside the crossbar)
//
// The master ports are named m0/m1/m2 rather than ifu/lsu/sb because the module
// is deliberately core-independent: `powerpulse_soc` connects the core's IFU to
// m0, LSU to m1 and SB to m2, and the core-less tests connect their AXI master
// models to the same ports at the same 64-bit width.  One fabric, two drivers --
// so Milestone A tests the real thing instead of a copy of it.
//
// Everything comes from pp_soc_cfg_pkg, which tools/gen_interconnect.py generates
// from config/soc_config.yaml.  No address, width or size appears literally here.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_soc_interconnect #(
    parameter integer M0_ID_WIDTH = 3,   // IFU_BUS_TAG
    parameter integer M1_ID_WIDTH = 3,   // LSU_BUS_TAG
    parameter integer M2_ID_WIDTH = 1    // SB_BUS_TAG
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire                    uart_rx,
    output wire                    uart_tx,
    output wire                    uart_irq,

    // ---- master 0 (64-bit AXI4) ----
    input  wire [M0_ID_WIDTH     -1:0] m0_axi_awid,
    input  wire [32              -1:0] m0_axi_awaddr,
    input  wire [8               -1:0] m0_axi_awlen,
    input  wire [3               -1:0] m0_axi_awsize,
    input  wire [2               -1:0] m0_axi_awburst,
    input  wire [1               -1:0] m0_axi_awlock,
    input  wire [3               -1:0] m0_axi_awprot,
    input  wire [1               -1:0] m0_axi_awvalid,
    output wire [1               -1:0] m0_axi_awready,
    input  wire [64              -1:0] m0_axi_wdata,
    input  wire [8               -1:0] m0_axi_wstrb,
    input  wire [1               -1:0] m0_axi_wlast,
    input  wire [1               -1:0] m0_axi_wvalid,
    output wire [1               -1:0] m0_axi_wready,
    output wire [M0_ID_WIDTH     -1:0] m0_axi_bid,
    output wire [1:0]              m0_axi_bresp,
    input  wire [1               -1:0] m0_axi_bvalid,
    output wire [1               -1:0] m0_axi_bready,
    input  wire [M0_ID_WIDTH     -1:0] m0_axi_arid,
    input  wire [32              -1:0] m0_axi_araddr,
    input  wire [8               -1:0] m0_axi_arlen,
    input  wire [3               -1:0] m0_axi_arsize,
    input  wire [2               -1:0] m0_axi_arburst,
    input  wire [1               -1:0] m0_axi_arlock,
    input  wire [3               -1:0] m0_axi_arprot,
    input  wire [1               -1:0] m0_axi_arvalid,
    output wire [1               -1:0] m0_axi_arready,
    output wire [M0_ID_WIDTH     -1:0] m0_axi_rid,
    output wire [64              -1:0] m0_axi_rdata,
    output wire [1:0]              m0_axi_rresp,
    output wire [1               -1:0] m0_axi_rlast,
    output wire [1               -1:0] m0_axi_rvalid,
    input  wire [1               -1:0] m0_axi_rready,

    // ---- master 1 (64-bit AXI4) ----
    input  wire [M1_ID_WIDTH     -1:0] m1_axi_awid,
    input  wire [32              -1:0] m1_axi_awaddr,
    input  wire [8               -1:0] m1_axi_awlen,
    input  wire [3               -1:0] m1_axi_awsize,
    input  wire [2               -1:0] m1_axi_awburst,
    input  wire [1               -1:0] m1_axi_awlock,
    input  wire [3               -1:0] m1_axi_awprot,
    input  wire [1               -1:0] m1_axi_awvalid,
    output wire [1               -1:0] m1_axi_awready,
    input  wire [64              -1:0] m1_axi_wdata,
    input  wire [8               -1:0] m1_axi_wstrb,
    input  wire [1               -1:0] m1_axi_wlast,
    input  wire [1               -1:0] m1_axi_wvalid,
    output wire [1               -1:0] m1_axi_wready,
    output wire [M1_ID_WIDTH     -1:0] m1_axi_bid,
    output wire [1:0]              m1_axi_bresp,
    input  wire [1               -1:0] m1_axi_bvalid,
    output wire [1               -1:0] m1_axi_bready,
    input  wire [M1_ID_WIDTH     -1:0] m1_axi_arid,
    input  wire [32              -1:0] m1_axi_araddr,
    input  wire [8               -1:0] m1_axi_arlen,
    input  wire [3               -1:0] m1_axi_arsize,
    input  wire [2               -1:0] m1_axi_arburst,
    input  wire [1               -1:0] m1_axi_arlock,
    input  wire [3               -1:0] m1_axi_arprot,
    input  wire [1               -1:0] m1_axi_arvalid,
    output wire [1               -1:0] m1_axi_arready,
    output wire [M1_ID_WIDTH     -1:0] m1_axi_rid,
    output wire [64              -1:0] m1_axi_rdata,
    output wire [1:0]              m1_axi_rresp,
    output wire [1               -1:0] m1_axi_rlast,
    output wire [1               -1:0] m1_axi_rvalid,
    input  wire [1               -1:0] m1_axi_rready,

    // ---- master 2 (64-bit AXI4) ----
    input  wire [M2_ID_WIDTH     -1:0] m2_axi_awid,
    input  wire [32              -1:0] m2_axi_awaddr,
    input  wire [8               -1:0] m2_axi_awlen,
    input  wire [3               -1:0] m2_axi_awsize,
    input  wire [2               -1:0] m2_axi_awburst,
    input  wire [1               -1:0] m2_axi_awlock,
    input  wire [3               -1:0] m2_axi_awprot,
    input  wire [1               -1:0] m2_axi_awvalid,
    output wire [1               -1:0] m2_axi_awready,
    input  wire [64              -1:0] m2_axi_wdata,
    input  wire [8               -1:0] m2_axi_wstrb,
    input  wire [1               -1:0] m2_axi_wlast,
    input  wire [1               -1:0] m2_axi_wvalid,
    output wire [1               -1:0] m2_axi_wready,
    output wire [M2_ID_WIDTH     -1:0] m2_axi_bid,
    output wire [1:0]              m2_axi_bresp,
    input  wire [1               -1:0] m2_axi_bvalid,
    output wire [1               -1:0] m2_axi_bready,
    input  wire [M2_ID_WIDTH     -1:0] m2_axi_arid,
    input  wire [32              -1:0] m2_axi_araddr,
    input  wire [8               -1:0] m2_axi_arlen,
    input  wire [3               -1:0] m2_axi_arsize,
    input  wire [2               -1:0] m2_axi_arburst,
    input  wire [1               -1:0] m2_axi_arlock,
    input  wire [3               -1:0] m2_axi_arprot,
    input  wire [1               -1:0] m2_axi_arvalid,
    output wire [1               -1:0] m2_axi_arready,
    output wire [M2_ID_WIDTH     -1:0] m2_axi_rid,
    output wire [64              -1:0] m2_axi_rdata,
    output wire [1:0]              m2_axi_rresp,
    output wire [1               -1:0] m2_axi_rlast,
    output wire [1               -1:0] m2_axi_rvalid,
    input  wire [1               -1:0] m2_axi_rready
);

    import pp_soc_cfg_pkg::*;

    // AXI4-Lite ID width on the far side of the bridges.  The vendored UART IP
    // uses a 12-bit field; the simulation status device matches it so one
    // parameter means the same thing on both slots.
    localparam integer AXIL_ID = 12;

    // =====================================================================
    // width adapters: 64-bit core ports -> 32-bit interconnect
    // =====================================================================
    // ---- narrow (interconnect-side) master bundles ------------------------
    // Packed, one slice per interconnect master.  Widths come from the generated
    // package; the *master count* multiplies every data-carrying signal.
    wire [PP_M_COUNT*PP_ID_WIDTH-1:0]     m_awid, m_bid, m_arid, m_rid;
    wire [PP_M_COUNT*PP_ADDR_WIDTH-1:0]   m_awaddr, m_araddr;
    wire [PP_M_COUNT*8-1:0]               m_awlen, m_arlen;
    wire [PP_M_COUNT*3-1:0]               m_awsize, m_arsize;
    wire [PP_M_COUNT*2-1:0]               m_awburst, m_arburst;
    wire [PP_M_COUNT*PP_XBAR_DW-1:0]      m_wdata, m_rdata;
    wire [PP_M_COUNT*PP_STRB_WIDTH-1:0]   m_wstrb;
    wire [PP_M_COUNT*2-1:0]               m_bresp, m_rresp;
    wire [PP_M_COUNT-1:0]                 m_wlast, m_rlast;
    wire [PP_M_COUNT-1:0]                 m_awvalid, m_awready, m_wvalid, m_wready;
    wire [PP_M_COUNT-1:0]                 m_bvalid, m_bready, m_arvalid, m_arready;
    wire [PP_M_COUNT-1:0]                 m_rvalid, m_rready;

    // ---- m0-side wide bundle: the core's IFU AXI4 port ----
    wire [M0_ID_WIDTH-1:0]      m0_awid, m0_arid, m0_bid, m0_rid;
    wire [31:0]        m0_awaddr, m0_araddr;
    wire [7:0]         m0_awlen, m0_arlen;
    wire [2:0]         m0_awsize, m0_arsize;
    wire [1:0]         m0_awburst, m0_arburst;
    wire               m0_awlock, m0_arlock;
    wire [2:0]         m0_awprot, m0_arprot;
    wire               m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire [63:0]        m0_wdata;
    wire [7:0]         m0_wstrb;
    wire               m0_wlast, m0_bvalid, m0_bready, m0_arvalid, m0_arready;
    wire [1:0]         m0_bresp, m0_rresp;
    wire [63:0]        m0_rdata;
    wire               m0_rlast, m0_rvalid, m0_rready;

    // ---- m1-side wide bundle: the core's LSU AXI4 port ----
    wire [M1_ID_WIDTH-1:0]      m1_awid, m1_arid, m1_bid, m1_rid;
    wire [31:0]        m1_awaddr, m1_araddr;
    wire [7:0]         m1_awlen, m1_arlen;
    wire [2:0]         m1_awsize, m1_arsize;
    wire [1:0]         m1_awburst, m1_arburst;
    wire               m1_awlock, m1_arlock;
    wire [2:0]         m1_awprot, m1_arprot;
    wire               m1_awvalid, m1_awready, m1_wvalid, m1_wready;
    wire [63:0]        m1_wdata;
    wire [7:0]         m1_wstrb;
    wire               m1_wlast, m1_bvalid, m1_bready, m1_arvalid, m1_arready;
    wire [1:0]         m1_bresp, m1_rresp;
    wire [63:0]        m1_rdata;
    wire               m1_rlast, m1_rvalid, m1_rready;

    // ---- m2-side wide bundle: the core's store buffer AXI4 port ----
    wire [M2_ID_WIDTH-1:0]      m2_awid, m2_arid, m2_bid, m2_rid;
    wire [31:0]        m2_awaddr, m2_araddr;
    wire [7:0]         m2_awlen, m2_arlen;
    wire [2:0]         m2_awsize, m2_arsize;
    wire [1:0]         m2_awburst, m2_arburst;
    wire               m2_awlock, m2_arlock;
    wire [2:0]         m2_awprot, m2_arprot;
    wire               m2_awvalid, m2_awready, m2_wvalid, m2_wready;
    wire [63:0]        m2_wdata;
    wire [7:0]         m2_wstrb;
    wire               m2_wlast, m2_bvalid, m2_bready, m2_arvalid, m2_arready;
    wire [1:0]         m2_bresp, m2_rresp;
    wire [63:0]        m2_rdata;
    wire               m2_rlast, m2_rvalid, m2_rready;
    // The core's AXI IDs are narrower than the interconnect's ID width (the tags
    // are 3, 3 and 1 bits while the interconnect carries 4).
    //
    // Request IDs travel core -> adapter, so they are *widened* here.  Response IDs
    // travel adapter -> core, so the adapter drives the `*_bid_int` / `*_rid_int`
    // nets at the interconnect width and the core-side port takes the low bits.  The
    // two directions deliberately use different nets: routing a response back
    // through a widening net would be a combinational loop.
    wire [PP_ID_WIDTH-1:0] m0_awid_w, m0_arid_w, m0_bid_int, m0_rid_int;
    assign m0_awid_w = {{(PP_ID_WIDTH-M0_ID_WIDTH){1'b0}}, m0_axi_awid};
    assign m0_arid_w = {{(PP_ID_WIDTH-M0_ID_WIDTH){1'b0}}, m0_axi_arid};
    wire [PP_ID_WIDTH-1:0] m1_awid_w, m1_arid_w, m1_bid_int, m1_rid_int;
    assign m1_awid_w = {{(PP_ID_WIDTH-M1_ID_WIDTH){1'b0}}, m1_axi_awid};
    assign m1_arid_w = {{(PP_ID_WIDTH-M1_ID_WIDTH){1'b0}}, m1_axi_arid};
    wire [PP_ID_WIDTH-1:0] m2_awid_w, m2_arid_w, m2_bid_int, m2_rid_int;
    assign m2_awid_w = {{(PP_ID_WIDTH-M2_ID_WIDTH){1'b0}}, m2_axi_awid};
    assign m2_arid_w = {{(PP_ID_WIDTH-M2_ID_WIDTH){1'b0}}, m2_axi_arid};


    // ---- fabric-produced responses, driven to the core-side master ports ----
    // These outputs come out of the interconnect and travel back up through the
    // width adapter, so they are wired to the internal wide-side bundle nets here.
    assign m0_axi_bid    = m0_bid_int[M0_ID_WIDTH-1:0];
    assign m0_axi_bresp  = m0_bresp;
    assign m0_axi_bvalid = m0_bvalid;
    assign m0_axi_rid    = m0_rid_int[M0_ID_WIDTH-1:0];
    assign m0_axi_rresp  = m0_rresp;
    assign m0_axi_rlast  = m0_rlast;
    assign m0_axi_rvalid = m0_rvalid;

    assign m1_axi_bid    = m1_bid_int[M1_ID_WIDTH-1:0];
    assign m1_axi_bresp  = m1_bresp;
    assign m1_axi_bvalid = m1_bvalid;
    assign m1_axi_rid    = m1_rid_int[M1_ID_WIDTH-1:0];
    assign m1_axi_rresp  = m1_rresp;
    assign m1_axi_rlast  = m1_rlast;
    assign m1_axi_rvalid = m1_rvalid;

    assign m2_axi_bid    = m2_bid_int[M2_ID_WIDTH-1:0];
    assign m2_axi_bresp  = m2_bresp;
    assign m2_axi_bvalid = m2_bvalid;
    assign m2_axi_rid    = m2_rid_int[M2_ID_WIDTH-1:0];
    assign m2_axi_rresp  = m2_rresp;
    assign m2_axi_rlast  = m2_rlast;
    assign m2_axi_rvalid = m2_rvalid;


    // ---- master 0 (core: IFU) ----
    pp_axi_downsize #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH_IN(PP_CORE_DW),
        .DATA_WIDTH_OUT(PP_XBAR_DW), .ID_WIDTH(PP_ID_WIDTH)
    ) u_ds_m0 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid({{(PP_ID_WIDTH-M0_ID_WIDTH){1'b0}}, m0_axi_awid}),
        .s_axi_awaddr(m0_axi_awaddr), .s_axi_awlen(m0_axi_awlen),
        .s_axi_awsize(m0_axi_awsize), .s_axi_awburst(m0_axi_awburst),
        .s_axi_awlock(m0_axi_awlock), .s_axi_awprot(m0_axi_awprot),
        .s_axi_awvalid(m0_axi_awvalid), .s_axi_awready(m0_axi_awready),
        .s_axi_wdata(m0_axi_wdata), .s_axi_wstrb(m0_axi_wstrb),
        .s_axi_wlast(m0_axi_wlast), .s_axi_wvalid(m0_axi_wvalid), .s_axi_wready(m0_axi_wready),
        .s_axi_bid(m0_bid_int), .s_axi_bresp(m0_bresp),
        .s_axi_bvalid(m0_axi_bvalid), .s_axi_bready(m0_axi_bready),
        .s_axi_arid({{(PP_ID_WIDTH-M0_ID_WIDTH){1'b0}}, m0_axi_arid}), .s_axi_araddr(m0_axi_araddr),
        .s_axi_arlen(m0_axi_arlen), .s_axi_arsize(m0_axi_arsize),
        .s_axi_arburst(m0_axi_arburst), .s_axi_arlock(m0_axi_arlock),
        .s_axi_arprot(m0_axi_arprot), .s_axi_arvalid(m0_axi_arvalid), .s_axi_arready(m0_axi_arready),
        .s_axi_rid(m0_rid_int), .s_axi_rdata(m0_axi_rdata),
        .s_axi_rresp(m0_rresp), .s_axi_rlast(m0_axi_rlast),
        .s_axi_rvalid(m0_axi_rvalid), .s_axi_rready(m0_axi_rready),
        .m_axi_awid(m_awid[0*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_awaddr(m_awaddr[0*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_awlen(m_awlen[0*8 +: 8]), .m_axi_awsize(m_awsize[0*3 +: 3]),
        .m_axi_awburst(m_awburst[0*2 +: 2]), .m_axi_awlock(), .m_axi_awprot(),
        .m_axi_awvalid(m_awvalid[0]), .m_axi_awready(m_awready[0]),
        .m_axi_wdata(m_wdata[0*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_wstrb(m_wstrb[0*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .m_axi_wlast(m_wlast[0]), .m_axi_wvalid(m_wvalid[0]), .m_axi_wready(m_wready[0]),
        .m_axi_bid(m_bid[0*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_bresp(m_bresp[0*2 +: 2]),
        .m_axi_bvalid(m_bvalid[0]), .m_axi_bready(m_bready[0]),
        .m_axi_arid(m_arid[0*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_araddr(m_araddr[0*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_arlen(m_arlen[0*8 +: 8]), .m_axi_arsize(m_arsize[0*3 +: 3]),
        .m_axi_arburst(m_arburst[0*2 +: 2]), .m_axi_arlock(), .m_axi_arprot(),
        .m_axi_arvalid(m_arvalid[0]), .m_axi_arready(m_arready[0]),
        .m_axi_rid(m_rid[0*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_rdata(m_rdata[0*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_rresp(m_rresp[0*2 +: 2]), .m_axi_rlast(m_rlast[0]),
        .m_axi_rvalid(m_rvalid[0]), .m_axi_rready(m_rready[0])
    );

    // ---- master 1 (core: LSU) ----
    pp_axi_downsize #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH_IN(PP_CORE_DW),
        .DATA_WIDTH_OUT(PP_XBAR_DW), .ID_WIDTH(PP_ID_WIDTH)
    ) u_ds_m1 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid({{(PP_ID_WIDTH-M1_ID_WIDTH){1'b0}}, m1_axi_awid}),
        .s_axi_awaddr(m1_axi_awaddr), .s_axi_awlen(m1_axi_awlen),
        .s_axi_awsize(m1_axi_awsize), .s_axi_awburst(m1_axi_awburst),
        .s_axi_awlock(m1_axi_awlock), .s_axi_awprot(m1_axi_awprot),
        .s_axi_awvalid(m1_axi_awvalid), .s_axi_awready(m1_axi_awready),
        .s_axi_wdata(m1_axi_wdata), .s_axi_wstrb(m1_axi_wstrb),
        .s_axi_wlast(m1_axi_wlast), .s_axi_wvalid(m1_axi_wvalid), .s_axi_wready(m1_axi_wready),
        .s_axi_bid(m1_bid_int), .s_axi_bresp(m1_bresp),
        .s_axi_bvalid(m1_axi_bvalid), .s_axi_bready(m1_axi_bready),
        .s_axi_arid({{(PP_ID_WIDTH-M1_ID_WIDTH){1'b0}}, m1_axi_arid}), .s_axi_araddr(m1_axi_araddr),
        .s_axi_arlen(m1_axi_arlen), .s_axi_arsize(m1_axi_arsize),
        .s_axi_arburst(m1_axi_arburst), .s_axi_arlock(m1_axi_arlock),
        .s_axi_arprot(m1_axi_arprot), .s_axi_arvalid(m1_axi_arvalid), .s_axi_arready(m1_axi_arready),
        .s_axi_rid(m1_rid_int), .s_axi_rdata(m1_axi_rdata),
        .s_axi_rresp(m1_rresp), .s_axi_rlast(m1_axi_rlast),
        .s_axi_rvalid(m1_axi_rvalid), .s_axi_rready(m1_axi_rready),
        .m_axi_awid(m_awid[1*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_awaddr(m_awaddr[1*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_awlen(m_awlen[1*8 +: 8]), .m_axi_awsize(m_awsize[1*3 +: 3]),
        .m_axi_awburst(m_awburst[1*2 +: 2]), .m_axi_awlock(), .m_axi_awprot(),
        .m_axi_awvalid(m_awvalid[1]), .m_axi_awready(m_awready[1]),
        .m_axi_wdata(m_wdata[1*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_wstrb(m_wstrb[1*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .m_axi_wlast(m_wlast[1]), .m_axi_wvalid(m_wvalid[1]), .m_axi_wready(m_wready[1]),
        .m_axi_bid(m_bid[1*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_bresp(m_bresp[1*2 +: 2]),
        .m_axi_bvalid(m_bvalid[1]), .m_axi_bready(m_bready[1]),
        .m_axi_arid(m_arid[1*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_araddr(m_araddr[1*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_arlen(m_arlen[1*8 +: 8]), .m_axi_arsize(m_arsize[1*3 +: 3]),
        .m_axi_arburst(m_arburst[1*2 +: 2]), .m_axi_arlock(), .m_axi_arprot(),
        .m_axi_arvalid(m_arvalid[1]), .m_axi_arready(m_arready[1]),
        .m_axi_rid(m_rid[1*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_rdata(m_rdata[1*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_rresp(m_rresp[1*2 +: 2]), .m_axi_rlast(m_rlast[1]),
        .m_axi_rvalid(m_rvalid[1]), .m_axi_rready(m_rready[1])
    );

    // ---- master 2 (core: SB) ----
    pp_axi_downsize #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH_IN(PP_CORE_DW),
        .DATA_WIDTH_OUT(PP_XBAR_DW), .ID_WIDTH(PP_ID_WIDTH)
    ) u_ds_m2 (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid({{(PP_ID_WIDTH-M2_ID_WIDTH){1'b0}}, m2_axi_awid}),
        .s_axi_awaddr(m2_axi_awaddr), .s_axi_awlen(m2_axi_awlen),
        .s_axi_awsize(m2_axi_awsize), .s_axi_awburst(m2_axi_awburst),
        .s_axi_awlock(m2_axi_awlock), .s_axi_awprot(m2_axi_awprot),
        .s_axi_awvalid(m2_axi_awvalid), .s_axi_awready(m2_axi_awready),
        .s_axi_wdata(m2_axi_wdata), .s_axi_wstrb(m2_axi_wstrb),
        .s_axi_wlast(m2_axi_wlast), .s_axi_wvalid(m2_axi_wvalid), .s_axi_wready(m2_axi_wready),
        .s_axi_bid(m2_bid_int), .s_axi_bresp(m2_bresp),
        .s_axi_bvalid(m2_axi_bvalid), .s_axi_bready(m2_axi_bready),
        .s_axi_arid({{(PP_ID_WIDTH-M2_ID_WIDTH){1'b0}}, m2_axi_arid}), .s_axi_araddr(m2_axi_araddr),
        .s_axi_arlen(m2_axi_arlen), .s_axi_arsize(m2_axi_arsize),
        .s_axi_arburst(m2_axi_arburst), .s_axi_arlock(m2_axi_arlock),
        .s_axi_arprot(m2_axi_arprot), .s_axi_arvalid(m2_axi_arvalid), .s_axi_arready(m2_axi_arready),
        .s_axi_rid(m2_rid_int), .s_axi_rdata(m2_axi_rdata),
        .s_axi_rresp(m2_rresp), .s_axi_rlast(m2_axi_rlast),
        .s_axi_rvalid(m2_axi_rvalid), .s_axi_rready(m2_axi_rready),
        .m_axi_awid(m_awid[2*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_awaddr(m_awaddr[2*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_awlen(m_awlen[2*8 +: 8]), .m_axi_awsize(m_awsize[2*3 +: 3]),
        .m_axi_awburst(m_awburst[2*2 +: 2]), .m_axi_awlock(), .m_axi_awprot(),
        .m_axi_awvalid(m_awvalid[2]), .m_axi_awready(m_awready[2]),
        .m_axi_wdata(m_wdata[2*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_wstrb(m_wstrb[2*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .m_axi_wlast(m_wlast[2]), .m_axi_wvalid(m_wvalid[2]), .m_axi_wready(m_wready[2]),
        .m_axi_bid(m_bid[2*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_bresp(m_bresp[2*2 +: 2]),
        .m_axi_bvalid(m_bvalid[2]), .m_axi_bready(m_bready[2]),
        .m_axi_arid(m_arid[2*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_araddr(m_araddr[2*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .m_axi_arlen(m_arlen[2*8 +: 8]), .m_axi_arsize(m_arsize[2*3 +: 3]),
        .m_axi_arburst(m_arburst[2*2 +: 2]), .m_axi_arlock(), .m_axi_arprot(),
        .m_axi_arvalid(m_arvalid[2]), .m_axi_arready(m_arready[2]),
        .m_axi_rid(m_rid[2*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .m_axi_rdata(m_rdata[2*PP_XBAR_DW +: PP_XBAR_DW]),
        .m_axi_rresp(m_rresp[2*2 +: 2]), .m_axi_rlast(m_rlast[2]),
        .m_axi_rvalid(m_rvalid[2]), .m_axi_rready(m_rready[2])
    );

    

    

    

    // =====================================================================
    // narrow (interconnect-side) slave bundles: one slice per config slot
        wire [PP_S_COUNT*PP_ID_WIDTH-1:0]   s_awid, s_bid, s_arid, s_rid;
    wire [PP_S_COUNT*PP_ADDR_WIDTH-1:0] s_awaddr, s_araddr;
    wire [PP_S_COUNT*8-1:0]             s_awlen, s_arlen;
    wire [PP_S_COUNT*3-1:0]             s_awsize, s_arsize, s_awprot, s_arprot;
    wire [PP_S_COUNT*2-1:0]             s_awburst, s_arburst, s_bresp, s_rresp;
    wire [PP_S_COUNT-1:0]               s_awlock, s_arlock;
    wire [PP_S_COUNT-1:0]               s_awvalid, s_awready, s_wvalid, s_wready;
    wire [PP_S_COUNT-1:0]               s_wlast, s_bvalid, s_bready;
    wire [PP_S_COUNT-1:0]               s_arvalid, s_arready, s_rvalid, s_rready;
    wire [PP_S_COUNT-1:0]               s_rlast;
    wire [PP_S_COUNT*PP_XBAR_DW-1:0]    s_wdata, s_rdata;
    wire [PP_S_COUNT*PP_STRB_WIDTH-1:0] s_wstrb;

    // =====================================================================
    // interconnect
    // =====================================================================
    pp_axi_interconnect #(
        .M_COUNT(PP_M_COUNT), .S_COUNT(PP_S_COUNT),
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH(PP_ID_WIDTH)
    ) u_xbar (
        .clk(clk), .rst_n(rst_n),

        .m_axi_awid(m_awid), .m_axi_awaddr(m_awaddr), .m_axi_awlen(m_awlen),
        .m_axi_awsize(m_awsize), .m_axi_awburst(m_awburst), .m_axi_awlock(),
        .m_axi_awprot(), .m_axi_awvalid(m_awvalid), .m_axi_awready(m_awready),
        .m_axi_wdata(m_wdata), .m_axi_wstrb(m_wstrb), .m_axi_wlast(m_wlast),
        .m_axi_wvalid(m_wvalid), .m_axi_wready(m_wready),
        .m_axi_bid(m_bid), .m_axi_bresp(m_bresp), .m_axi_bvalid(m_bvalid),
        .m_axi_bready(m_bready),
        .m_axi_arid(m_arid), .m_axi_araddr(m_araddr), .m_axi_arlen(m_arlen),
        .m_axi_arsize(m_arsize), .m_axi_arburst(m_arburst), .m_axi_arlock(),
        .m_axi_arprot(), .m_axi_arvalid(m_arvalid), .m_axi_arready(m_arready),
        .m_axi_rid(m_rid), .m_axi_rdata(m_rdata), .m_axi_rresp(m_rresp),
        .m_axi_rlast(m_rlast), .m_axi_rvalid(m_rvalid), .m_axi_rready(m_rready),

        .s_axi_awid(s_awid), .s_axi_awaddr(s_awaddr), .s_axi_awlen(s_awlen),
        .s_axi_awsize(s_awsize), .s_axi_awburst(s_awburst), .s_axi_awlock(s_awlock),
        .s_axi_awprot(s_awprot), .s_axi_awvalid(s_awvalid), .s_axi_awready(s_awready),
        .s_axi_wdata(s_wdata), .s_axi_wstrb(s_wstrb), .s_axi_wlast(s_wlast),
        .s_axi_wvalid(s_wvalid), .s_axi_wready(s_wready),
        .s_axi_bid(s_bid), .s_axi_bresp(s_bresp), .s_axi_bvalid(s_bvalid),
        .s_axi_bready(s_bready),
        .s_axi_arid(s_arid), .s_axi_araddr(s_araddr), .s_axi_arlen(s_arlen),
        .s_axi_arsize(s_arsize), .s_axi_arburst(s_arburst), .s_axi_arlock(s_arlock),
        .s_axi_arprot(s_arprot), .s_axi_arvalid(s_arvalid), .s_axi_arready(s_arready),
        .s_axi_rid(s_rid), .s_axi_rdata(s_rdata), .s_axi_rresp(s_rresp),
        .s_axi_rlast(s_rlast), .s_axi_rvalid(s_rvalid), .s_axi_rready(s_rready)
    );

    // slot indices, taken from the generated package so they cannot drift
    localparam int SLOT_IMEM   = 0;
    localparam int SLOT_DMEM   = 1;
    localparam int SLOT_UART   = 2;
    localparam int SLOT_TIMER  = 3;
    localparam int SLOT_GPIO   = 4;
    localparam int SLOT_HAP    = 5;
    localparam int SLOT_PPMC   = 6;
    localparam int SLOT_AWEC   = 7;
    localparam int SLOT_STATUS = 8;

    // =====================================================================
    // instruction memory
    // =====================================================================
    pp_axi_ram #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH(PP_ID_WIDTH),
        .DEPTH(PP_IMEM_SIZE / (PP_XBAR_DW / 8)),
        .NAME("imem")
    ) u_imem (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_IMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_IMEM*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_IMEM*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_IMEM*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_IMEM*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_IMEM]), .s_axi_awprot(s_awprot[SLOT_IMEM*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_IMEM]), .s_axi_awready(s_awready[SLOT_IMEM]),
        .s_axi_wdata(s_wdata[SLOT_IMEM*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_IMEM*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_IMEM]), .s_axi_wvalid(s_wvalid[SLOT_IMEM]),
        .s_axi_wready(s_wready[SLOT_IMEM]),
        .s_axi_bid(s_bid[SLOT_IMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_IMEM*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_IMEM]), .s_axi_bready(s_bready[SLOT_IMEM]),
        .s_axi_arid(s_arid[SLOT_IMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_IMEM*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_IMEM*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_IMEM*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_IMEM*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_IMEM]), .s_axi_arprot(s_arprot[SLOT_IMEM*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_IMEM]), .s_axi_arready(s_arready[SLOT_IMEM]),
        .s_axi_rid(s_rid[SLOT_IMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_IMEM*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_IMEM*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_IMEM]), .s_axi_rvalid(s_rvalid[SLOT_IMEM]),
        .s_axi_rready(s_rready[SLOT_IMEM])
    );

    // =====================================================================
    // data memory
    // =====================================================================
    pp_axi_ram #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH(PP_ID_WIDTH),
        .DEPTH(PP_DMEM_SIZE / (PP_XBAR_DW / 8)),
        .NAME("dmem")
    ) u_dmem (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_DMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_DMEM*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_DMEM*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_DMEM*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_DMEM*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_DMEM]), .s_axi_awprot(s_awprot[SLOT_DMEM*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_DMEM]), .s_axi_awready(s_awready[SLOT_DMEM]),
        .s_axi_wdata(s_wdata[SLOT_DMEM*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_DMEM*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_DMEM]), .s_axi_wvalid(s_wvalid[SLOT_DMEM]),
        .s_axi_wready(s_wready[SLOT_DMEM]),
        .s_axi_bid(s_bid[SLOT_DMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_DMEM*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_DMEM]), .s_axi_bready(s_bready[SLOT_DMEM]),
        .s_axi_arid(s_arid[SLOT_DMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_DMEM*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_DMEM*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_DMEM*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_DMEM*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_DMEM]), .s_axi_arprot(s_arprot[SLOT_DMEM*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_DMEM]), .s_axi_arready(s_arready[SLOT_DMEM]),
        .s_axi_rid(s_rid[SLOT_DMEM*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_DMEM*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_DMEM*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_DMEM]), .s_axi_rvalid(s_rvalid[SLOT_DMEM]),
        .s_axi_rready(s_rready[SLOT_DMEM])
    );

    // =====================================================================
    // UART slot: bridge -> IP
    // =====================================================================
    wire [AXIL_ID-1:0]           u_x_awid, u_x_bid, u_x_arid, u_x_rid;
    wire [4:0]                   u_x_awaddr, u_x_araddr;
    wire [7:0]                   u_x_awlen, u_x_arlen;
    wire [2:0]                   u_x_awsize, u_x_arsize, u_x_awprot, u_x_arprot;
    wire [1:0]                   u_x_awburst, u_x_arburst, u_x_bresp, u_x_rresp;
    wire                         u_x_awlock, u_x_arlock;
    wire                         u_x_awvalid, u_x_awready, u_x_wvalid, u_x_wready;
    wire                         u_x_wlast, u_x_bvalid, u_x_bready;
    wire                         u_x_arvalid, u_x_arready, u_x_rvalid, u_x_rready;
    wire                         u_x_rlast;
    wire [PP_XBAR_DW-1:0]        u_x_wdata, u_x_rdata;
    wire [PP_STRB_WIDTH-1:0]     u_x_wstrb;

    wire [AXIL_ID-1:0]           u_y_awid, u_y_bid, u_y_arid, u_y_rid;
    wire [4:0]                   u_y_awaddr, u_y_araddr;
    wire [7:0]                   u_y_awlen, u_y_arlen;
    wire [2:0]                   u_y_awsize, u_y_arsize, u_y_awprot, u_y_arprot;
    wire [1:0]                   u_y_awburst, u_y_arburst, u_y_bresp, u_y_rresp;
    wire                         u_y_awlock, u_y_arlock;
    wire                         u_y_awvalid, u_y_awready, u_y_wvalid, u_y_wready;
    wire                         u_y_wlast, u_y_bvalid, u_y_bready;
    wire                         u_y_arvalid, u_y_arready, u_y_rvalid, u_y_rready;
    wire                         u_y_rlast;
    wire [PP_XBAR_DW-1:0]        u_y_wdata, u_y_rdata;
    wire [PP_STRB_WIDTH-1:0]     u_y_wstrb;

    pp_axi4_to_axil #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH_M(PP_ID_WIDTH), .ID_WIDTH_S(AXIL_ID)
    ) u_uart_bridge (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_UART*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_UART*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_UART*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_UART*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_UART*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_UART]), .s_axi_awprot(s_awprot[SLOT_UART*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_UART]), .s_axi_awready(s_awready[SLOT_UART]),
        .s_axi_wdata(s_wdata[SLOT_UART*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_UART*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_UART]), .s_axi_wvalid(s_wvalid[SLOT_UART]),
        .s_axi_wready(s_wready[SLOT_UART]),
        .s_axi_bid(s_bid[SLOT_UART*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_UART*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_UART]), .s_axi_bready(s_bready[SLOT_UART]),
        .s_axi_arid(s_arid[SLOT_UART*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_UART*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_UART*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_UART*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_UART*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_UART]), .s_axi_arprot(s_arprot[SLOT_UART*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_UART]), .s_axi_arready(s_arready[SLOT_UART]),
        .s_axi_rid(s_rid[SLOT_UART*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_UART*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_UART*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_UART]), .s_axi_rvalid(s_rvalid[SLOT_UART]),
        .s_axi_rready(s_rready[SLOT_UART]),

        .m_axi_awid(u_y_awid), .m_axi_awaddr(u_y_awaddr), .m_axi_awlen(u_y_awlen),
        .m_axi_awsize(u_y_awsize), .m_axi_awburst(u_y_awburst), .m_axi_awlock(u_y_awlock),
        .m_axi_awprot(u_y_awprot), .m_axi_awvalid(u_y_awvalid), .m_axi_awready(u_y_awready),
        .m_axi_wdata(u_y_wdata), .m_axi_wstrb(u_y_wstrb), .m_axi_wlast(u_y_wlast),
        .m_axi_wvalid(u_y_wvalid), .m_axi_wready(u_y_wready),
        .m_axi_bid(u_y_bid), .m_axi_bresp(u_y_bresp), .m_axi_bvalid(u_y_bvalid),
        .m_axi_bready(u_y_bready),
        .m_axi_arid(u_y_arid), .m_axi_araddr(u_y_araddr), .m_axi_arlen(u_y_arlen),
        .m_axi_arsize(u_y_arsize), .m_axi_arburst(u_y_arburst), .m_axi_arlock(u_y_arlock),
        .m_axi_arprot(u_y_arprot), .m_axi_arvalid(u_y_arvalid), .m_axi_arready(u_y_arready),
        .m_axi_rid(u_y_rid), .m_axi_rdata(u_y_rdata), .m_axi_rresp(u_y_rresp),
        .m_axi_rlast(u_y_rlast), .m_axi_rvalid(u_y_rvalid), .m_axi_rready(u_y_rready)
    );

    wire uart_activity;

    pp_uart #(
        .ADDR_WIDTH(5), .ID_WIDTH(AXIL_ID), .EN_DEFAULT(1'b1)
    ) u_uart (
        .clk(clk), .uart_clk(clk), .rst_n(rst_n),
        .axi_arid_i(u_y_arid), .axi_araddr_i(u_y_araddr),
        .axi_arvalid_i(u_y_arvalid), .axi_arready_o(u_y_arready),
        .axi_rid_o(u_y_rid), .axi_rdata_o(u_y_rdata), .axi_rresp_o(u_y_rresp),
        .axi_rvalid_o(u_y_rvalid), .axi_rready_i(u_y_rready),
        .axi_awid_i(u_y_awid), .axi_awaddr_i(u_y_awaddr),
        .axi_awvalid_i(u_y_awvalid), .axi_awready_o(u_y_awready),
        .axi_wdata_i(u_y_wdata), .axi_wstrb_i(u_y_wstrb),
        .axi_wvalid_i(u_y_wvalid), .axi_wready_o(u_y_wready),
        .axi_bid_o(u_y_bid), .axi_bresp_o(u_y_bresp), .axi_bvalid_o(u_y_bvalid),
        .axi_bready_i(u_y_bready),
        .uart_rx_i(uart_rx), .uart_tx_o(uart_tx),
        .pp_enable_i(1'b1), .pp_activity_o(uart_activity), .irq_o(uart_irq)
    );

    // =====================================================================
    // status slot (simulation only)
    //
    // Software needs a way to report PASS/FAIL without a human reading a
    // waveform, so the `status` slot in config/soc_config.yaml carries a
    // testbench-only reporter.  The reporter lives in tb/common/ and is compiled
    // only when the build defines PP_SIM; a synthesis build answers this slot
    // with the decode-error stub, so no simulation-only behaviour exists in the
    // synthesizable netlist.  See docs/soc_top/status_device.md.
    // =====================================================================
    wire [AXIL_ID-1:0]           st_y_awid, st_y_bid, st_y_arid, st_y_rid;
    wire [4:0]                   st_y_awaddr, st_y_araddr;
    wire [7:0]                   st_y_awlen, st_y_arlen;
    wire [2:0]                   st_y_awsize, st_y_arsize, st_y_awprot, st_y_arprot;
    wire [1:0]                   st_y_awburst, st_y_arburst, st_y_bresp, st_y_rresp;
    wire                         st_y_awlock, st_y_arlock;
    wire                         st_y_awvalid, st_y_awready, st_y_wvalid, st_y_wready;
    wire                         st_y_wlast, st_y_bvalid, st_y_bready;
    wire                         st_y_arvalid, st_y_arready, st_y_rvalid, st_y_rready;
    wire                         st_y_rlast;
    wire [PP_XBAR_DW-1:0]        st_y_wdata, st_y_rdata;
    wire [PP_STRB_WIDTH-1:0]     st_y_wstrb;

    pp_axi4_to_axil #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH_M(PP_ID_WIDTH), .ID_WIDTH_S(AXIL_ID)
    ) u_status_bridge (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_STATUS*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_STATUS*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_STATUS*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_STATUS*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_STATUS*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_STATUS]), .s_axi_awprot(s_awprot[SLOT_STATUS*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_STATUS]), .s_axi_awready(s_awready[SLOT_STATUS]),
        .s_axi_wdata(s_wdata[SLOT_STATUS*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_STATUS*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_STATUS]), .s_axi_wvalid(s_wvalid[SLOT_STATUS]),
        .s_axi_wready(s_wready[SLOT_STATUS]),
        .s_axi_bid(s_bid[SLOT_STATUS*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_STATUS*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_STATUS]), .s_axi_bready(s_bready[SLOT_STATUS]),
        .s_axi_arid(s_arid[SLOT_STATUS*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_STATUS*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_STATUS*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_STATUS*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_STATUS*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_STATUS]), .s_axi_arprot(s_arprot[SLOT_STATUS*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_STATUS]), .s_axi_arready(s_arready[SLOT_STATUS]),
        .s_axi_rid(s_rid[SLOT_STATUS*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_STATUS*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_STATUS*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_STATUS]), .s_axi_rvalid(s_rvalid[SLOT_STATUS]),
        .s_axi_rready(s_rready[SLOT_STATUS]),

        .m_axi_awid(st_y_awid), .m_axi_awaddr(st_y_awaddr), .m_axi_awlen(st_y_awlen),
        .m_axi_awsize(st_y_awsize), .m_axi_awburst(st_y_awburst), .m_axi_awlock(st_y_awlock),
        .m_axi_awprot(st_y_awprot), .m_axi_awvalid(st_y_awvalid), .m_axi_awready(st_y_awready),
        .m_axi_wdata(st_y_wdata), .m_axi_wstrb(st_y_wstrb), .m_axi_wlast(st_y_wlast),
        .m_axi_wvalid(st_y_wvalid), .m_axi_wready(st_y_wready),
        .m_axi_bid(st_y_bid), .m_axi_bresp(st_y_bresp), .m_axi_bvalid(st_y_bvalid),
        .m_axi_bready(st_y_bready),
        .m_axi_arid(st_y_arid), .m_axi_araddr(st_y_araddr), .m_axi_arlen(st_y_arlen),
        .m_axi_arsize(st_y_arsize), .m_axi_arburst(st_y_arburst), .m_axi_arlock(st_y_arlock),
        .m_axi_arprot(st_y_arprot), .m_axi_arvalid(st_y_arvalid), .m_axi_arready(st_y_arready),
        .m_axi_rid(st_y_rid), .m_axi_rdata(st_y_rdata), .m_axi_rresp(st_y_rresp),
        .m_axi_rlast(st_y_rlast), .m_axi_rvalid(st_y_rvalid), .m_axi_rready(st_y_rready)
    );

`ifdef PP_SIM
    pp_sim_status_dev #(
        .ADDR_WIDTH(5), .ID_WIDTH(AXIL_ID), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH)
    ) u_status_dev (
        .clk(clk), .rst_n(rst_n),
        .s_axi_arid(st_y_arid), .s_axi_araddr(st_y_araddr),
        .s_axi_arvalid(st_y_arvalid), .s_axi_arready(st_y_arready),
        .s_axi_rid(st_y_rid), .s_axi_rdata(st_y_rdata), .s_axi_rresp(st_y_rresp),
        .s_axi_rvalid(st_y_rvalid), .s_axi_rready(st_y_rready),
        .s_axi_awid(st_y_awid), .s_axi_awaddr(st_y_awaddr),
        .s_axi_awvalid(st_y_awvalid), .s_axi_awready(st_y_awready),
        .s_axi_wdata(st_y_wdata), .s_axi_wstrb(st_y_wstrb),
        .s_axi_wvalid(st_y_wvalid), .s_axi_wready(st_y_wready),
        .s_axi_bid(st_y_bid), .s_axi_bresp(st_y_bresp), .s_axi_bvalid(st_y_bvalid),
        .s_axi_bready(st_y_bready)
    );
`else
    // Synthesis flavour of the same slot: a decode-error stub, so the slot can
    // never hang and never pretends to be a real device.
    pp_axi_stub_slave #(
        .ADDR_WIDTH(PP_ADDR_WIDTH), .DATA_WIDTH(PP_XBAR_DW),
        .STRB_WIDTH(PP_STRB_WIDTH), .ID_WIDTH(AXIL_ID)
    ) u_status_stub (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(st_y_awid), .s_axi_awaddr(st_y_awaddr), .s_axi_awlen(st_y_awlen),
        .s_axi_awsize(st_y_awsize), .s_axi_awburst(st_y_awburst), .s_axi_awlock(st_y_awlock),
        .s_axi_awprot(st_y_awprot), .s_axi_awvalid(st_y_awvalid), .s_axi_awready(st_y_awready),
        .s_axi_wdata(st_y_wdata), .s_axi_wstrb(st_y_wstrb), .s_axi_wlast(st_y_wlast),
        .s_axi_wvalid(st_y_wvalid), .s_axi_wready(st_y_wready),
        .s_axi_bid(st_y_bid), .s_axi_bresp(st_y_bresp), .s_axi_bvalid(st_y_bvalid),
        .s_axi_bready(st_y_bready),
        .s_axi_arid(st_y_arid), .s_axi_araddr(st_y_araddr), .s_axi_arlen(st_y_arlen),
        .s_axi_arsize(st_y_arsize), .s_axi_arburst(st_y_arburst), .s_axi_arlock(st_y_arlock),
        .s_axi_arprot(st_y_arprot), .s_axi_arvalid(st_y_arvalid), .s_axi_arready(st_y_arready),
        .s_axi_rid(st_y_rid), .s_axi_rdata(st_y_rdata), .s_axi_rresp(st_y_rresp),
        .s_axi_rlast(st_y_rlast), .s_axi_rvalid(st_y_rvalid), .s_axi_rready(st_y_rready)
    );
`endif

    // =====================================================================
    // reserved Phase 2 slots: every one of them decodes to the error stub, so an
    // access cannot hang and cannot silently hit the wrong peripheral.  Turning
    // one on is a config change plus an RTL drop-in -- see
    // docs/interconnect_generator/how_to_add_a_slave.md.
    // =====================================================================
    pp_axi_stub_slave #(.ID_WIDTH(PP_ID_WIDTH)) u_stub_timer (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_TIMER*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_TIMER*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_TIMER*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_TIMER*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_TIMER*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_TIMER]), .s_axi_awprot(s_awprot[SLOT_TIMER*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_TIMER]), .s_axi_awready(s_awready[SLOT_TIMER]),
        .s_axi_wdata(s_wdata[SLOT_TIMER*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_TIMER*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_TIMER]), .s_axi_wvalid(s_wvalid[SLOT_TIMER]),
        .s_axi_wready(s_wready[SLOT_TIMER]),
        .s_axi_bid(s_bid[SLOT_TIMER*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_TIMER*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_TIMER]), .s_axi_bready(s_bready[SLOT_TIMER]),
        .s_axi_arid(s_arid[SLOT_TIMER*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_TIMER*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_TIMER*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_TIMER*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_TIMER*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_TIMER]), .s_axi_arprot(s_arprot[SLOT_TIMER*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_TIMER]), .s_axi_arready(s_arready[SLOT_TIMER]),
        .s_axi_rid(s_rid[SLOT_TIMER*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_TIMER*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_TIMER*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_TIMER]), .s_axi_rvalid(s_rvalid[SLOT_TIMER]),
        .s_axi_rready(s_rready[SLOT_TIMER])
    );

    pp_axi_stub_slave #(.ID_WIDTH(PP_ID_WIDTH)) u_stub_gpio (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_GPIO*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_GPIO*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_GPIO*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_GPIO*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_GPIO*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_GPIO]), .s_axi_awprot(s_awprot[SLOT_GPIO*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_GPIO]), .s_axi_awready(s_awready[SLOT_GPIO]),
        .s_axi_wdata(s_wdata[SLOT_GPIO*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_GPIO*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_GPIO]), .s_axi_wvalid(s_wvalid[SLOT_GPIO]),
        .s_axi_wready(s_wready[SLOT_GPIO]),
        .s_axi_bid(s_bid[SLOT_GPIO*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_GPIO*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_GPIO]), .s_axi_bready(s_bready[SLOT_GPIO]),
        .s_axi_arid(s_arid[SLOT_GPIO*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_GPIO*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_GPIO*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_GPIO*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_GPIO*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_GPIO]), .s_axi_arprot(s_arprot[SLOT_GPIO*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_GPIO]), .s_axi_arready(s_arready[SLOT_GPIO]),
        .s_axi_rid(s_rid[SLOT_GPIO*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_GPIO*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_GPIO*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_GPIO]), .s_axi_rvalid(s_rvalid[SLOT_GPIO]),
        .s_axi_rready(s_rready[SLOT_GPIO])
    );

    pp_axi_stub_slave #(.ID_WIDTH(PP_ID_WIDTH)) u_stub_hap (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_HAP*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_HAP*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_HAP*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_HAP*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_HAP*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_HAP]), .s_axi_awprot(s_awprot[SLOT_HAP*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_HAP]), .s_axi_awready(s_awready[SLOT_HAP]),
        .s_axi_wdata(s_wdata[SLOT_HAP*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_HAP*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_HAP]), .s_axi_wvalid(s_wvalid[SLOT_HAP]),
        .s_axi_wready(s_wready[SLOT_HAP]),
        .s_axi_bid(s_bid[SLOT_HAP*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_HAP*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_HAP]), .s_axi_bready(s_bready[SLOT_HAP]),
        .s_axi_arid(s_arid[SLOT_HAP*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_HAP*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_HAP*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_HAP*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_HAP*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_HAP]), .s_axi_arprot(s_arprot[SLOT_HAP*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_HAP]), .s_axi_arready(s_arready[SLOT_HAP]),
        .s_axi_rid(s_rid[SLOT_HAP*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_HAP*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_HAP*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_HAP]), .s_axi_rvalid(s_rvalid[SLOT_HAP]),
        .s_axi_rready(s_rready[SLOT_HAP])
    );

    pp_axi_stub_slave #(.ID_WIDTH(PP_ID_WIDTH)) u_stub_ppmc (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_PPMC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_PPMC*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_PPMC*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_PPMC*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_PPMC*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_PPMC]), .s_axi_awprot(s_awprot[SLOT_PPMC*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_PPMC]), .s_axi_awready(s_awready[SLOT_PPMC]),
        .s_axi_wdata(s_wdata[SLOT_PPMC*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_PPMC*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_PPMC]), .s_axi_wvalid(s_wvalid[SLOT_PPMC]),
        .s_axi_wready(s_wready[SLOT_PPMC]),
        .s_axi_bid(s_bid[SLOT_PPMC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_PPMC*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_PPMC]), .s_axi_bready(s_bready[SLOT_PPMC]),
        .s_axi_arid(s_arid[SLOT_PPMC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_PPMC*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_PPMC*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_PPMC*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_PPMC*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_PPMC]), .s_axi_arprot(s_arprot[SLOT_PPMC*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_PPMC]), .s_axi_arready(s_arready[SLOT_PPMC]),
        .s_axi_rid(s_rid[SLOT_PPMC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_PPMC*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_PPMC*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_PPMC]), .s_axi_rvalid(s_rvalid[SLOT_PPMC]),
        .s_axi_rready(s_rready[SLOT_PPMC])
    );

    pp_axi_stub_slave #(.ID_WIDTH(PP_ID_WIDTH)) u_stub_awec (
        .clk(clk), .rst_n(rst_n),
        .s_axi_awid(s_awid[SLOT_AWEC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_awaddr(s_awaddr[SLOT_AWEC*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_awlen(s_awlen[SLOT_AWEC*8 +: 8]),
        .s_axi_awsize(s_awsize[SLOT_AWEC*3 +: 3]),
        .s_axi_awburst(s_awburst[SLOT_AWEC*2 +: 2]),
        .s_axi_awlock(s_awlock[SLOT_AWEC]), .s_axi_awprot(s_awprot[SLOT_AWEC*3 +: 3]),
        .s_axi_awvalid(s_awvalid[SLOT_AWEC]), .s_axi_awready(s_awready[SLOT_AWEC]),
        .s_axi_wdata(s_wdata[SLOT_AWEC*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_wstrb(s_wstrb[SLOT_AWEC*PP_STRB_WIDTH +: PP_STRB_WIDTH]),
        .s_axi_wlast(s_wlast[SLOT_AWEC]), .s_axi_wvalid(s_wvalid[SLOT_AWEC]),
        .s_axi_wready(s_wready[SLOT_AWEC]),
        .s_axi_bid(s_bid[SLOT_AWEC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_bresp(s_bresp[SLOT_AWEC*2 +: 2]),
        .s_axi_bvalid(s_bvalid[SLOT_AWEC]), .s_axi_bready(s_bready[SLOT_AWEC]),
        .s_axi_arid(s_arid[SLOT_AWEC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_araddr(s_araddr[SLOT_AWEC*PP_ADDR_WIDTH +: PP_ADDR_WIDTH]),
        .s_axi_arlen(s_arlen[SLOT_AWEC*8 +: 8]),
        .s_axi_arsize(s_arsize[SLOT_AWEC*3 +: 3]),
        .s_axi_arburst(s_arburst[SLOT_AWEC*2 +: 2]),
        .s_axi_arlock(s_arlock[SLOT_AWEC]), .s_axi_arprot(s_arprot[SLOT_AWEC*3 +: 3]),
        .s_axi_arvalid(s_arvalid[SLOT_AWEC]), .s_axi_arready(s_arready[SLOT_AWEC]),
        .s_axi_rid(s_rid[SLOT_AWEC*PP_ID_WIDTH +: PP_ID_WIDTH]),
        .s_axi_rdata(s_rdata[SLOT_AWEC*PP_XBAR_DW +: PP_XBAR_DW]),
        .s_axi_rresp(s_rresp[SLOT_AWEC*2 +: 2]),
        .s_axi_rlast(s_rlast[SLOT_AWEC]), .s_axi_rvalid(s_rvalid[SLOT_AWEC]),
        .s_axi_rready(s_rready[SLOT_AWEC])
    );

endmodule

`default_nettype wire
