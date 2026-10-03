// -----------------------------------------------------------------------------
// pp_veer_core
//
// The project's integration boundary around the pinned, unmodified VeeR EL2 core
// (rtl/core/veer_el2).  Nothing in the core tree is edited; every project
// decision -- reset, reset vector, tie-offs -- is made here and documented in
// docs/veer_integration/.
//
// Master ports exposed
//   The core has three AXI4 masters: IFU, LSU and SB, each 64 bit wide.  All
//   three are brought out at full 64-bit width; the SoC top narrows them with
//   pp_axi_downsize before they reach the 32-bit interconnect.  Keeping the
//   narrowing outside this file keeps the core boundary honest.
//
// Master port map
//   IFU -> interconnect master 0   (instruction fetch, bursts)
//   LSU -> interconnect master 1   (data loads/stores)
//   SB  -> interconnect master 2   (store buffer)
//   DMA -> not connected (tied off, see docs/veer_integration/)
//
// Every tie-off is intentional and listed in the table at the bottom of
// docs/veer_integration/tie_offs.md.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_veer_core #(
    // AXI geometry of the core's own ports.  These come from the generated
    // VeeR parameter package (IFU_BUS_TAG / LSU_BUS_TAG / SB_BUS_TAG), which is
    // 3 for this configuration; the SoC top widens them to the interconnect's
    // ID width, so they are parameters here rather than literals.
    parameter integer ID_WIDTH_IFU = 3,
    parameter integer ID_WIDTH_LSU = 3,
    parameter integer ID_WIDTH_SB  = 1,
    // Reset vector, already shifted right by one because el2_veer_wrapper takes
    // rst_vec[31:1].  Comes from pp_soc_cfg_pkg::PP_RESET_VECTOR_HI.
    parameter logic [30:0] RESET_VECTOR_HI = 31'h4000_0000
) (
    input  wire                              clk,
    input  wire                              rst_n,

    // ---- IFU master (interconnect master 0) ----
    output wire [ID_WIDTH_IFU-1:0]           ifu_axi_awid,
    output wire [31:0]                       ifu_axi_awaddr,
    output wire [3:0]                        ifu_axi_awregion,
    output wire [7:0]                        ifu_axi_awlen,
    output wire [2:0]                        ifu_axi_awsize,
    output wire [1:0]                        ifu_axi_awburst,
    output wire                              ifu_axi_awlock,
    output wire [3:0]                        ifu_axi_awcache,
    output wire [2:0]                        ifu_axi_awprot,
    output wire [3:0]                        ifu_axi_awqos,
    output wire                              ifu_axi_awvalid,
    input  wire                              ifu_axi_awready,
    output wire [63:0]                       ifu_axi_wdata,
    output wire [7:0]                        ifu_axi_wstrb,
    output wire                              ifu_axi_wlast,
    output wire                              ifu_axi_wvalid,
    input  wire                              ifu_axi_wready,
    input  wire [1:0]                        ifu_axi_bresp,
    input  wire [ID_WIDTH_IFU-1:0]           ifu_axi_bid,
    input  wire                              ifu_axi_bvalid,
    output wire                              ifu_axi_bready,
    output wire [ID_WIDTH_IFU-1:0]           ifu_axi_arid,
    output wire [31:0]                       ifu_axi_araddr,
    output wire [3:0]                        ifu_axi_arregion,
    output wire [7:0]                        ifu_axi_arlen,
    output wire [2:0]                        ifu_axi_arsize,
    output wire [1:0]                        ifu_axi_arburst,
    output wire                              ifu_axi_arlock,
    output wire [3:0]                        ifu_axi_arcache,
    output wire [2:0]                        ifu_axi_arprot,
    output wire [3:0]                        ifu_axi_arqos,
    output wire                              ifu_axi_arvalid,
    input  wire                              ifu_axi_arready,
    input  wire [ID_WIDTH_IFU-1:0]           ifu_axi_rid,
    input  wire [63:0]                       ifu_axi_rdata,
    input  wire [1:0]                        ifu_axi_rresp,
    input  wire                              ifu_axi_rlast,
    input  wire                              ifu_axi_rvalid,
    output wire                              ifu_axi_rready,

    // ---- LSU master (interconnect master 1) ----
    output wire [ID_WIDTH_LSU-1:0]           lsu_axi_awid,
    output wire [31:0]                       lsu_axi_awaddr,
    output wire [3:0]                        lsu_axi_awregion,
    output wire [7:0]                        lsu_axi_awlen,
    output wire [2:0]                        lsu_axi_awsize,
    output wire [1:0]                        lsu_axi_awburst,
    output wire                              lsu_axi_awlock,
    output wire [3:0]                        lsu_axi_awcache,
    output wire [2:0]                        lsu_axi_awprot,
    output wire [3:0]                        lsu_axi_awqos,
    output wire                              lsu_axi_awvalid,
    input  wire                              lsu_axi_awready,
    output wire [63:0]                       lsu_axi_wdata,
    output wire [7:0]                        lsu_axi_wstrb,
    output wire                              lsu_axi_wlast,
    output wire                              lsu_axi_wvalid,
    input  wire                              lsu_axi_wready,
    input  wire [1:0]                        lsu_axi_bresp,
    input  wire [ID_WIDTH_LSU-1:0]           lsu_axi_bid,
    input  wire                              lsu_axi_bvalid,
    output wire                              lsu_axi_bready,
    output wire [ID_WIDTH_LSU-1:0]           lsu_axi_arid,
    output wire [31:0]                       lsu_axi_araddr,
    output wire [3:0]                        lsu_axi_arregion,
    output wire [7:0]                        lsu_axi_arlen,
    output wire [2:0]                        lsu_axi_arsize,
    output wire [1:0]                        lsu_axi_arburst,
    output wire                              lsu_axi_arlock,
    output wire [3:0]                        lsu_axi_arcache,
    output wire [2:0]                        lsu_axi_arprot,
    output wire [3:0]                        lsu_axi_arqos,
    output wire                              lsu_axi_arvalid,
    input  wire                              lsu_axi_arready,
    input  wire [ID_WIDTH_LSU-1:0]           lsu_axi_rid,
    input  wire [63:0]                       lsu_axi_rdata,
    input  wire [1:0]                        lsu_axi_rresp,
    input  wire                              lsu_axi_rlast,
    input  wire                              lsu_axi_rvalid,
    output wire                              lsu_axi_rready,

    // ---- SB master (interconnect master 2) ----
    output wire [ID_WIDTH_SB-1:0]            sb_axi_awid,
    output wire [31:0]                       sb_axi_awaddr,
    output wire [3:0]                        sb_axi_awregion,
    output wire [7:0]                        sb_axi_awlen,
    output wire [2:0]                        sb_axi_awsize,
    output wire [1:0]                        sb_axi_awburst,
    output wire                              sb_axi_awlock,
    output wire [3:0]                        sb_axi_awcache,
    output wire [2:0]                        sb_axi_awprot,
    output wire [3:0]                        sb_axi_awqos,
    output wire                              sb_axi_awvalid,
    input  wire                              sb_axi_awready,
    output wire [63:0]                       sb_axi_wdata,
    output wire [7:0]                        sb_axi_wstrb,
    output wire                              sb_axi_wlast,
    output wire                              sb_axi_wvalid,
    input  wire                              sb_axi_wready,
    input  wire [1:0]                        sb_axi_bresp,
    input  wire [ID_WIDTH_SB-1:0]            sb_axi_bid,
    input  wire                              sb_axi_bvalid,
    output wire                              sb_axi_bready,
    output wire [ID_WIDTH_SB-1:0]            sb_axi_arid,
    output wire [31:0]                       sb_axi_araddr,
    output wire [3:0]                        sb_axi_arregion,
    output wire [7:0]                        sb_axi_arlen,
    output wire [2:0]                        sb_axi_arsize,
    output wire [1:0]                        sb_axi_arburst,
    output wire                              sb_axi_arlock,
    output wire [3:0]                        sb_axi_arcache,
    output wire [2:0]                        sb_axi_arprot,
    output wire [3:0]                       sb_axi_arqos,
    output wire                              sb_axi_arvalid,
    input  wire                              sb_axi_arready,
    input  wire [ID_WIDTH_SB-1:0]            sb_axi_rid,
    input  wire [63:0]                       sb_axi_rdata,
    input  wire [1:0]                        sb_axi_rresp,
    input  wire                              sb_axi_rlast,
    input  wire                              sb_axi_rvalid,
    output wire                              sb_axi_rready,

    // ---- observation (unused in Phase 1, brought out for debug) ----
    output wire [31:0]                       trace_rv_i_insn_ip,
    output wire [31:0]                       trace_rv_i_address_ip,
    output wire                              trace_rv_i_valid_ip,
    output wire                              trace_rv_i_exception_ip,
    output wire [4:0]                        trace_rv_i_ecause_ip,
    output wire                              trace_rv_i_interrupt_ip,
    output wire [31:0]                       trace_rv_i_tval_ip
);

    // ---------------------------------------------------------------------
    // Signals the core drives that this project does not consume.
    // Declared so elaboration is explicit rather than accidental; see
    // docs/veer_integration/tie_offs.md for the reason in each case.
    // ---------------------------------------------------------------------
    wire [3:0]  unused_awregion;
    wire [3:0]  unused_awcache;
    wire [3:0]  unused_awqos;
    wire [1:0]  unused_awburst_lsu;   // kept for the waveform; never changed
    wire        unused_iccm_ecc_single_error;
    wire        unused_iccm_ecc_double_error;
    wire        unused_dccm_ecc_single_error;
    wire        unused_dccm_ecc_double_error;
    wire        unused_dccm_write_readback_error;
    wire        unused_perfcnt0;
    wire        unused_perfcnt1;
    wire        unused_perfcnt2;
    wire        unused_perfcnt3;
    wire        unused_mpc_debug_halt_ack;
    wire        unused_mpc_debug_run_ack;
    wire        unused_debug_brkpt_status;
    wire        unused_o_cpu_halt_ack;
    wire        unused_o_cpu_halt_status;
    wire        unused_o_debug_mode_status;
    wire        unused_o_cpu_run_ack;
    wire        unused_jtag_tdo;
    wire        unused_jtag_tdoEn;
    wire        unused_dmi_uncore_en;
    wire        unused_dmi_uncore_wr_en;
    wire [6:0]  unused_dmi_uncore_addr;
    wire [31:0] unused_dmi_uncore_wdata;
    wire        unused_dmi_active;
    wire [63:0] unused_dma_axi_rdata;
    wire        unused_dma_axi_rvalid;
    wire        unused_dma_axi_rready;
    wire [1:0]  unused_dma_axi_bresp;
    wire [1:0]  unused_dma_axi_rresp;

    // The core's memory-export interfaces.  They exist so a system built with
    // core-internal ICCM/DCCM memories can drive them; this configuration has
    // both disabled (config: core.veer_options), so nothing connects to them and
    // they stay as bare interface instances.  See docs/veer_integration/.
    el2_mem_if u_icache_export();
    el2_mem_if u_sram_export();

    // The DMA slave port is tied off (Phase 1 decision, PHASES.md / PROJECT_CONTEXT
    // section 7).  Every input is driven to its inactive value and every output
    // is left unconnected.
    localparam [ID_WIDTH_SB-1:0] DMA_ID_ZERO = {ID_WIDTH_SB{1'b0}};

    el2_veer_wrapper u_veer (
        .clk                     (clk),
        .rst_l                   (rst_n),
        .dbg_rst_l               (rst_n),

        // Reset vector: configuration-provided, already shifted right by one.
        .rst_vec                 (RESET_VECTOR_HI),
        .nmi_int                 (1'b0),
        .nmi_vec                 (31'd0),
        .jtag_id                 (31'd0),

        .trace_rv_i_insn_ip      (trace_rv_i_insn_ip),
        .trace_rv_i_address_ip   (trace_rv_i_address_ip),
        .trace_rv_i_valid_ip     (trace_rv_i_valid_ip),
        .trace_rv_i_exception_ip (trace_rv_i_exception_ip),
        .trace_rv_i_ecause_ip    (trace_rv_i_ecause_ip),
        .trace_rv_i_interrupt_ip (trace_rv_i_interrupt_ip),
        .trace_rv_i_tval_ip      (trace_rv_i_tval_ip),

        // ---------------- IFU ----------------
        .ifu_axi_awvalid         (ifu_axi_awvalid),
        .ifu_axi_awready         (ifu_axi_awready),
        .ifu_axi_awid            (ifu_axi_awid),
        .ifu_axi_awaddr          (ifu_axi_awaddr),
        .ifu_axi_awregion        (unused_awregion),
        .ifu_axi_awlen           (ifu_axi_awlen),
        .ifu_axi_awsize          (ifu_axi_awsize),
        .ifu_axi_awburst         (ifu_axi_awburst),
        .ifu_axi_awlock          (ifu_axi_awlock),
        .ifu_axi_awcache         (unused_awcache),
        .ifu_axi_awprot          (ifu_axi_awprot),
        .ifu_axi_awqos           (unused_awqos),
        .ifu_axi_wvalid          (ifu_axi_wvalid),
        .ifu_axi_wready          (ifu_axi_wready),
        .ifu_axi_wdata           (ifu_axi_wdata),
        .ifu_axi_wstrb           (ifu_axi_wstrb),
        .ifu_axi_wlast           (ifu_axi_wlast),
        .ifu_axi_bvalid          (ifu_axi_bvalid),
        .ifu_axi_bready          (ifu_axi_bready),
        .ifu_axi_bresp           (ifu_axi_bresp),
        .ifu_axi_bid             (ifu_axi_bid),
        .ifu_axi_arvalid         (ifu_axi_arvalid),
        .ifu_axi_arready         (ifu_axi_arready),
        .ifu_axi_arid            (ifu_axi_arid),
        .ifu_axi_araddr          (ifu_axi_araddr),
        .ifu_axi_arregion        (unused_awregion),
        .ifu_axi_arlen           (ifu_axi_arlen),
        .ifu_axi_arsize          (ifu_axi_arsize),
        .ifu_axi_arburst         (ifu_axi_arburst),
        .ifu_axi_arlock          (ifu_axi_arlock),
        .ifu_axi_arcache         (unused_awcache),
        .ifu_axi_arprot          (ifu_axi_arprot),
        .ifu_axi_arqos           (unused_awqos),
        .ifu_axi_rvalid          (ifu_axi_rvalid),
        .ifu_axi_rready          (ifu_axi_rready),
        .ifu_axi_rid             (ifu_axi_rid),
        .ifu_axi_rdata           (ifu_axi_rdata),
        .ifu_axi_rresp           (ifu_axi_rresp),
        .ifu_axi_rlast           (ifu_axi_rlast),

        // ---------------- LSU ----------------
        .lsu_axi_awvalid         (lsu_axi_awvalid),
        .lsu_axi_awready         (lsu_axi_awready),
        .lsu_axi_awid            (lsu_axi_awid),
        .lsu_axi_awaddr          (lsu_axi_awaddr),
        .lsu_axi_awregion        (unused_awregion),
        .lsu_axi_awlen           (lsu_axi_awlen),
        .lsu_axi_awsize          (lsu_axi_awsize),
        .lsu_axi_awburst         (lsu_axi_awburst),
        .lsu_axi_awlock          (lsu_axi_awlock),
        .lsu_axi_awcache         (unused_awcache),
        .lsu_axi_awprot          (lsu_axi_awprot),
        .lsu_axi_awqos           (unused_awqos),
        .lsu_axi_wvalid          (lsu_axi_wvalid),
        .lsu_axi_wready          (lsu_axi_wready),
        .lsu_axi_wdata           (lsu_axi_wdata),
        .lsu_axi_wstrb           (lsu_axi_wstrb),
        .lsu_axi_wlast           (lsu_axi_wlast),
        .lsu_axi_bvalid          (lsu_axi_bvalid),
        .lsu_axi_bready          (lsu_axi_bready),
        .lsu_axi_bresp           (lsu_axi_bresp),
        .lsu_axi_bid             (lsu_axi_bid),
        .lsu_axi_arvalid         (lsu_axi_arvalid),
        .lsu_axi_arready         (lsu_axi_arready),
        .lsu_axi_arid            (lsu_axi_arid),
        .lsu_axi_araddr          (lsu_axi_araddr),
        .lsu_axi_arregion        (unused_awregion),
        .lsu_axi_arlen           (lsu_axi_arlen),
        .lsu_axi_arsize          (lsu_axi_arsize),
        .lsu_axi_arburst         (lsu_axi_arburst),
        .lsu_axi_arlock          (lsu_axi_arlock),
        .lsu_axi_arcache         (unused_awcache),
        .lsu_axi_arprot          (lsu_axi_arprot),
        .lsu_axi_arqos           (unused_awqos),
        .lsu_axi_rvalid          (lsu_axi_rvalid),
        .lsu_axi_rready          (lsu_axi_rready),
        .lsu_axi_rid             (lsu_axi_rid),
        .lsu_axi_rdata           (lsu_axi_rdata),
        .lsu_axi_rresp           (lsu_axi_rresp),
        .lsu_axi_rlast           (lsu_axi_rlast),

        // ---------------- SB ----------------
        .sb_axi_awvalid          (sb_axi_awvalid),
        .sb_axi_awready          (sb_axi_awready),
        .sb_axi_awid             (sb_axi_awid),
        .sb_axi_awaddr           (sb_axi_awaddr),
        .sb_axi_awregion         (unused_awregion),
        .sb_axi_awlen            (sb_axi_awlen),
        .sb_axi_awsize           (sb_axi_awsize),
        .sb_axi_awburst          (sb_axi_awburst),
        .sb_axi_awlock           (sb_axi_awlock),
        .sb_axi_awcache          (unused_awcache),
        .sb_axi_awprot           (sb_axi_awprot),
        .sb_axi_awqos            (unused_awqos),
        .sb_axi_wvalid           (sb_axi_wvalid),
        .sb_axi_wready           (sb_axi_wready),
        .sb_axi_wdata            (sb_axi_wdata),
        .sb_axi_wstrb            (sb_axi_wstrb),
        .sb_axi_wlast            (sb_axi_wlast),
        .sb_axi_bvalid           (sb_axi_bvalid),
        .sb_axi_bready           (sb_axi_bready),
        .sb_axi_bresp            (sb_axi_bresp),
        .sb_axi_bid              (sb_axi_bid),
        .sb_axi_arvalid          (sb_axi_arvalid),
        .sb_axi_arready          (sb_axi_arready),
        .sb_axi_arid             (sb_axi_arid),
        .sb_axi_araddr           (sb_axi_araddr),
        .sb_axi_arregion         (unused_awregion),
        .sb_axi_arlen            (sb_axi_arlen),
        .sb_axi_arsize           (sb_axi_arsize),
        .sb_axi_arburst          (sb_axi_arburst),
        .sb_axi_arlock           (sb_axi_arlock),
        .sb_axi_arcache          (unused_awcache),
        .sb_axi_arprot           (sb_axi_arprot),
        .sb_axi_arqos            (unused_awqos),
        .sb_axi_rvalid           (sb_axi_rvalid),
        .sb_axi_rready           (sb_axi_rready),
        .sb_axi_rid              (sb_axi_rid),
        .sb_axi_rdata            (sb_axi_rdata),
        .sb_axi_rresp            (sb_axi_rresp),
        .sb_axi_rlast            (sb_axi_rlast),

        // ---------------- DMA slave port: tied off ----------------
        .dma_axi_awvalid         (1'b0),
        .dma_axi_awready         (),
        .dma_axi_awid            (DMA_ID_ZERO),
        .dma_axi_awaddr          (32'd0),
        .dma_axi_awsize          (3'd0),
        .dma_axi_awprot          (3'd0),
        .dma_axi_awlen           (8'd0),
        .dma_axi_awburst         (2'd0),
        .dma_axi_wvalid          (1'b0),
        .dma_axi_wready          (),
        .dma_axi_wdata           (64'd0),
        .dma_axi_wstrb           (8'd0),
        .dma_axi_wlast           (1'b0),
        .dma_axi_bvalid          (1'b0),
        .dma_axi_bready          (1'b0),
        .dma_axi_bresp           (2'b00),
        .dma_axi_bid             (DMA_ID_ZERO),
        .dma_axi_arvalid         (1'b0),
        .dma_axi_arready         (),
        .dma_axi_arid            (DMA_ID_ZERO),
        .dma_axi_araddr          (32'd0),
        .dma_axi_arsize          (3'd0),
        .dma_axi_arprot          (3'd0),
        .dma_axi_arlen           (8'd0),
        .dma_axi_arburst         (2'd0),
        .dma_axi_rvalid          (1'b0),
        .dma_axi_rready          (1'b0),
        .dma_axi_rid             (DMA_ID_ZERO),
        .dma_axi_rdata           (64'd0),
        .dma_axi_rresp           (2'b00),
        .dma_axi_rlast           (1'b0),

        // ---------------- clock-ratio enables ----------------
        .lsu_bus_clk_en          (1'b1),
        .ifu_bus_clk_en          (1'b1),
        .dbg_bus_clk_en          (1'b1),
        .dma_bus_clk_en          (1'b1),

        // ---------------- ICCM/DCCM ECC status (unused) ----------------
        .iccm_ecc_single_error   (unused_iccm_ecc_single_error),
        .iccm_ecc_double_error   (unused_iccm_ecc_double_error),
        .dccm_ecc_single_error   (unused_dccm_ecc_single_error),
        .dccm_ecc_double_error   (unused_dccm_ecc_double_error),
        .dccm_write_readback_error (unused_dccm_write_readback_error),

        // ---------------- memory export interfaces (unused) ----------------
        .el2_icache_export       (u_icache_export),
        .el2_mem_export          (u_sram_export),

        // ---------------- interrupts ----------------
        .timer_int               (1'b0),
        .soft_int                (1'b0),
        .extintsrc_req           ('0),

        // ---------------- performance counters (unused) ----------------
        .dec_tlu_perfcnt0        (unused_perfcnt0),
        .dec_tlu_perfcnt1        (unused_perfcnt1),
        .dec_tlu_perfcnt2        (unused_perfcnt2),
        .dec_tlu_perfcnt3        (unused_perfcnt3),

        // ---------------- JTAG / debug ----------------
        .jtag_tck                (1'b0),
        .jtag_tms                (1'b0),
        .jtag_tdi                (1'b0),
        .jtag_trst_n             (1'b0),
        .jtag_tdo                (unused_jtag_tdo),
        .jtag_tdoEn              (unused_jtag_tdoEn),

        .core_id                 (28'd0),

        // ---------------- MPC / halt-run control: idle ----------------
        .mpc_debug_halt_req      (1'b0),
        .mpc_debug_run_req       (1'b0),
        .mpc_reset_run_req       (1'b0),
        .mpc_debug_halt_ack      (unused_mpc_debug_halt_ack),
        .mpc_debug_run_ack       (unused_mpc_debug_run_ack),
        .debug_brkpt_status      (unused_debug_brkpt_status),
        .i_cpu_halt_req          (1'b0),
        .o_cpu_halt_ack          (unused_o_cpu_halt_ack),
        .o_cpu_halt_status       (unused_o_cpu_halt_status),
        .o_debug_mode_status     (unused_o_debug_mode_status),
        .i_cpu_run_req           (1'b0),
        .o_cpu_run_ack           (unused_o_cpu_run_ack),

        // ---------------- DFT: off ----------------
        .scan_mode               (1'b0),
        .mbist_mode              (1'b0),

        // ---------------- DMI: no uncore ----------------
        .dmi_core_enable         (1'b0),
        .dmi_uncore_enable       (1'b0),
        .dmi_uncore_en           (unused_dmi_uncore_en),
        .dmi_uncore_wr_en        (unused_dmi_uncore_wr_en),
        .dmi_uncore_addr         (unused_dmi_uncore_addr),
        .dmi_uncore_wdata        (unused_dmi_uncore_wdata),
        .dmi_uncore_rdata        (32'd0),
        .dmi_active              (unused_dmi_active)
    );

    // Keep the unused-signal bundle referenced so nothing is optimised away
    // silently and the intent stays visible in the source.
    wire _unused_ok = &{1'b0, unused_awregion, unused_awcache, unused_awqos,
                        unused_awburst_lsu,
                        unused_iccm_ecc_single_error, unused_iccm_ecc_double_error,
                        unused_dccm_ecc_single_error, unused_dccm_ecc_double_error,
                        unused_dccm_write_readback_error,
                        unused_perfcnt0, unused_perfcnt1,
                        unused_perfcnt2, unused_perfcnt3,
                        unused_mpc_debug_halt_ack, unused_mpc_debug_run_ack,
                        unused_debug_brkpt_status, unused_o_cpu_halt_ack,
                        unused_o_cpu_halt_status, unused_o_debug_mode_status,
                        unused_o_cpu_run_ack, unused_jtag_tdo, unused_jtag_tdoEn,
                        unused_dmi_uncore_en, unused_dmi_uncore_wr_en,
                        unused_dmi_uncore_addr, unused_dmi_uncore_wdata,
                        unused_dmi_active,
                        unused_dma_axi_rdata, unused_dma_axi_rvalid,
                        unused_dma_axi_rready, unused_dma_axi_bresp,
                        unused_dma_axi_rresp};

endmodule

`default_nettype wire
