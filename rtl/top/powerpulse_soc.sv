// -----------------------------------------------------------------------------
// powerpulse_soc
//
// PowerPulse SoC top level: the VeeR EL2 core plus the interconnect fabric.
//
//   VeeR EL2 core
//     |-- IFU (64b) --\
//     |-- LSU (64b) --- pp_soc_interconnect --> 32-bit AXI interconnect
//     |-- SB  (64b) --/                            |
//                                                 +-- imem / dmem  (pp_axi_ram, AXI4)
//                                                 +-- uart          (bridge -> pp_uart)
//                                                 +-- timer / gpio / hap / ppmc / awec
//                                                 |       (decode-error stubs, Phase 2)
//                                                 +-- status        (simulation reporter)
//                                                 +-- default       (decode-error stub)
//
// The fabric lives in its own module, `pp_soc_interconnect`, for one reason:
// the core-less integration tests drive *exactly the same* fabric with 64-bit
// AXI master models, so Milestone A tests the real thing rather than a copy of
// it.  Nothing in this file hardcodes an address, a width or a size: everything
// comes from pp_soc_cfg_pkg, which tools/gen_interconnect.py generates from
// config/soc_config.yaml.
//
// The one deliberate exception to "simulation-only code lives in tb/" is the
// status slot: software needs a way to report PASS/FAIL.  It is instantiated
// only when the build defines PP_SIM; in a synthesis build the slot decodes as
// an error.  See docs/soc_top/status_device.md.
// -----------------------------------------------------------------------------

`default_nettype none

module powerpulse_soc (
    input  wire         clk,
    input  wire         rst_n,

    // UART serial lines.  The testbench drives rx and decodes tx.
    input  wire         uart_rx,
    output wire         uart_tx,

    // UART interrupt, reserved for the core's interrupt controller (P2-00).
    // Exposed here, tied to a known state in Phase 1.
    output wire         uart_irq
);

    import pp_soc_cfg_pkg::*;

    // AXI ID widths of the core's own masters, from the generated VeeR parameter
    // package (IFU_BUS_TAG, LSU_BUS_TAG, SB_BUS_TAG).
    localparam integer MID  = 3;
    localparam integer MIFU = 3;
    localparam integer MSB  = 1;

    // ---- 64-bit core-side AXI4 bundles (core <-> width adapters) ----
    // ifu: instruction fetch
    wire [MIFU-1:0]        ifu_awid, ifu_arid, ifu_bid, ifu_rid;
    wire [31:0]            ifu_awaddr, ifu_araddr;
    wire [7:0]             ifu_awlen, ifu_arlen;
    wire [2:0]             ifu_awsize, ifu_arsize;
    wire [1:0]             ifu_awburst, ifu_arburst;
    wire                   ifu_awlock, ifu_arlock;
    wire [2:0]             ifu_awprot, ifu_arprot;
    wire                   ifu_awvalid, ifu_awready;
    wire [63:0]            ifu_wdata;
    wire [7:0]             ifu_wstrb;
    wire                   ifu_wlast, ifu_wvalid, ifu_wready;
    wire [1:0]             ifu_bresp;
    wire                   ifu_bvalid, ifu_bready;
    wire                   ifu_arvalid, ifu_arready;
    wire [63:0]            ifu_rdata;
    wire [1:0]             ifu_rresp;
    wire                   ifu_rlast, ifu_rvalid, ifu_rready;

    // lsu: data loads and stores
    wire [MID-1:0]         lsu_awid, lsu_arid, lsu_bid, lsu_rid;
    wire [31:0]            lsu_awaddr, lsu_araddr;
    wire [7:0]             lsu_awlen, lsu_arlen;
    wire [2:0]             lsu_awsize, lsu_arsize;
    wire [1:0]             lsu_awburst, lsu_arburst;
    wire                   lsu_awlock, lsu_arlock;
    wire [2:0]             lsu_awprot, lsu_arprot;
    wire                   lsu_awvalid, lsu_awready;
    wire [63:0]            lsu_wdata;
    wire [7:0]             lsu_wstrb;
    wire                   lsu_wlast, lsu_wvalid, lsu_wready;
    wire [1:0]             lsu_bresp;
    wire                   lsu_bvalid, lsu_bready;
    wire                   lsu_arvalid, lsu_arready;
    wire [63:0]            lsu_rdata;
    wire [1:0]             lsu_rresp;
    wire                   lsu_rlast, lsu_rvalid, lsu_rready;

    // sb: store buffer
    wire [MSB-1:0]         sb_awid, sb_arid, sb_bid, sb_rid;
    wire [31:0]            sb_awaddr, sb_araddr;
    wire [7:0]             sb_awlen, sb_arlen;
    wire [2:0]             sb_awsize, sb_arsize;
    wire [1:0]             sb_awburst, sb_arburst;
    wire                   sb_awlock, sb_arlock;
    wire [2:0]             sb_awprot, sb_arprot;
    wire                   sb_awvalid, sb_awready;
    wire [63:0]            sb_wdata;
    wire [7:0]             sb_wstrb;
    wire                   sb_wlast, sb_wvalid, sb_wready;
    wire [1:0]             sb_bresp;
    wire                   sb_bvalid, sb_bready;
    wire                   sb_arvalid, sb_arready;
    wire [63:0]            sb_rdata;
    wire [1:0]             sb_rresp;
    wire                   sb_rlast, sb_rvalid, sb_rready;

    wire [31:0] trace_insn, trace_addr, trace_tval;
    wire        trace_valid, trace_exc, trace_intr;
    wire [4:0]  trace_ecause;

    pp_veer_core #(
        .ID_WIDTH_IFU (MIFU),
        .ID_WIDTH_LSU (MID),
        .ID_WIDTH_SB  (MSB),
        .RESET_VECTOR_HI (PP_RESET_VECTOR_HI)
    ) u_core (
        .clk   (clk),
        .rst_n (rst_n),
        .ifu_axi_awid       (ifu_awid),      .ifu_axi_awaddr (ifu_awaddr),
        .ifu_axi_awregion   (),              .ifu_axi_awlen   (ifu_awlen),
        .ifu_axi_awsize     (ifu_awsize),    .ifu_axi_awburst (ifu_awburst),
        .ifu_axi_awlock     (ifu_awlock),    .ifu_axi_awcache  (),
        .ifu_axi_awprot     (ifu_awprot),    .ifu_axi_awqos    (),
        .ifu_axi_awvalid    (ifu_awvalid),   .ifu_axi_awready  (ifu_awready),
        .ifu_axi_wdata      (ifu_wdata),     .ifu_axi_wstrb    (ifu_wstrb),
        .ifu_axi_wlast      (ifu_wlast),     .ifu_axi_wvalid   (ifu_wvalid),
        .ifu_axi_wready     (ifu_wready),
        .ifu_axi_bid        (ifu_bid),       .ifu_axi_bresp    (ifu_bresp),
        .ifu_axi_bvalid     (ifu_bvalid),    .ifu_axi_bready   (ifu_bready),
        .ifu_axi_arid       (ifu_arid),      .ifu_axi_araddr   (ifu_araddr),
        .ifu_axi_arregion   (),              .ifu_axi_arlen    (ifu_arlen),
        .ifu_axi_arsize     (ifu_arsize),    .ifu_axi_arburst  (ifu_arburst),
        .ifu_axi_arlock     (ifu_arlock),    .ifu_axi_arcache  (),
        .ifu_axi_arprot     (ifu_arprot),    .ifu_axi_arqos    (),
        .ifu_axi_arvalid    (ifu_arvalid),   .ifu_axi_arready  (ifu_arready),
        .ifu_axi_rid        (ifu_rid),       .ifu_axi_rdata    (ifu_rdata),
        .ifu_axi_rresp      (ifu_rresp),     .ifu_axi_rlast    (ifu_rlast),
        .ifu_axi_rvalid     (ifu_rvalid),    .ifu_axi_rready   (ifu_rready),
        .lsu_axi_awid       (lsu_awid),      .lsu_axi_awaddr (lsu_awaddr),
        .lsu_axi_awregion   (),              .lsu_axi_awlen   (lsu_awlen),
        .lsu_axi_awsize     (lsu_awsize),    .lsu_axi_awburst (lsu_awburst),
        .lsu_axi_awlock     (lsu_awlock),    .lsu_axi_awcache  (),
        .lsu_axi_awprot     (lsu_awprot),    .lsu_axi_awqos    (),
        .lsu_axi_awvalid    (lsu_awvalid),   .lsu_axi_awready  (lsu_awready),
        .lsu_axi_wdata      (lsu_wdata),     .lsu_axi_wstrb    (lsu_wstrb),
        .lsu_axi_wlast      (lsu_wlast),     .lsu_axi_wvalid   (lsu_wvalid),
        .lsu_axi_wready     (lsu_wready),
        .lsu_axi_bid        (lsu_bid),       .lsu_axi_bresp    (lsu_bresp),
        .lsu_axi_bvalid     (lsu_bvalid),    .lsu_axi_bready   (lsu_bready),
        .lsu_axi_arid       (lsu_arid),      .lsu_axi_araddr   (lsu_araddr),
        .lsu_axi_arregion   (),              .lsu_axi_arlen    (lsu_arlen),
        .lsu_axi_arsize     (lsu_arsize),    .lsu_axi_arburst  (lsu_arburst),
        .lsu_axi_arlock     (lsu_arlock),    .lsu_axi_arcache  (),
        .lsu_axi_arprot     (lsu_arprot),    .lsu_axi_arqos    (),
        .lsu_axi_arvalid    (lsu_arvalid),   .lsu_axi_arready  (lsu_arready),
        .lsu_axi_rid        (lsu_rid),       .lsu_axi_rdata    (lsu_rdata),
        .lsu_axi_rresp      (lsu_rresp),     .lsu_axi_rlast    (lsu_rlast),
        .lsu_axi_rvalid     (lsu_rvalid),    .lsu_axi_rready   (lsu_rready),
        .sb_axi_awid        (sb_awid),       .sb_axi_awaddr (sb_awaddr),
        .sb_axi_awregion    (),              .sb_axi_awlen   (sb_awlen),
        .sb_axi_awsize      (sb_awsize),     .sb_axi_awburst (sb_awburst),
        .sb_axi_awlock      (sb_awlock),     .sb_axi_awcache  (),
        .sb_axi_awprot      (sb_awprot),     .sb_axi_awqos    (),
        .sb_axi_awvalid     (sb_awvalid),    .sb_axi_awready  (sb_awready),
        .sb_axi_wdata       (sb_wdata),      .sb_axi_wstrb    (sb_wstrb),
        .sb_axi_wlast       (sb_wlast),      .sb_axi_wvalid   (sb_wvalid),
        .sb_axi_wready      (sb_wready),
        .sb_axi_bid         (sb_bid),        .sb_axi_bresp    (sb_bresp),
        .sb_axi_bvalid      (sb_bvalid),     .sb_axi_bready   (sb_bready),
        .sb_axi_arid        (sb_arid),       .sb_axi_araddr   (sb_araddr),
        .sb_axi_arregion    (),              .sb_axi_arlen    (sb_arlen),
        .sb_axi_arsize      (sb_arsize),     .sb_axi_arburst  (sb_arburst),
        .sb_axi_arlock      (sb_arlock),     .sb_axi_arcache  (),
        .sb_axi_arprot      (sb_arprot),     .sb_axi_arqos    (),
        .sb_axi_arvalid     (sb_arvalid),    .sb_axi_arready  (sb_arready),
        .sb_axi_rid         (sb_rid),        .sb_axi_rdata    (sb_rdata),
        .sb_axi_rresp       (sb_rresp),      .sb_axi_rlast    (sb_rlast),
        .sb_axi_rvalid      (sb_rvalid),     .sb_axi_rready   (sb_rready),
        .trace_rv_i_insn_ip    (trace_insn),
        .trace_rv_i_address_ip (trace_addr),
        .trace_rv_i_valid_ip   (trace_valid),
        .trace_rv_i_exception_ip (trace_exc),
        .trace_rv_i_ecause_ip  (trace_ecause),
        .trace_rv_i_interrupt_ip (trace_intr),
        .trace_rv_i_tval_ip     (trace_tval)
    );

    // The fabric: width adapters, interconnect, memories, UART, reserved slots.
    pp_soc_interconnect #(
        .M0_ID_WIDTH(MIFU), .M1_ID_WIDTH(MID), .M2_ID_WIDTH(MSB)
    ) u_fabric (
        .clk(clk), .rst_n(rst_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_irq(uart_irq),
        // ---- master 0: IFU ----
        .m0_axi_awid             ({{(PP_ID_WIDTH-MIFU){1'b0}}, ifu_awid}),
        .m0_axi_awaddr           (ifu_awaddr),
        .m0_axi_awlen            (ifu_awlen),
        .m0_axi_awsize           (ifu_awsize),
        .m0_axi_awburst          (ifu_awburst),
        .m0_axi_awlock           (ifu_awlock),
        .m0_axi_awprot           (ifu_awprot),
        .m0_axi_awvalid          (ifu_awvalid),
        .m0_axi_awready          (ifu_awready),
        .m0_axi_wdata            (ifu_wdata),
        .m0_axi_wstrb            (ifu_wstrb),
        .m0_axi_wlast            (ifu_wlast),
        .m0_axi_wvalid           (ifu_wvalid),
        .m0_axi_wready           (ifu_wready),
        .m0_axi_bid              ({{(PP_ID_WIDTH-MIFU){1'b0}}, ifu_bid}),
        .m0_axi_bresp            (ifu_bresp),
        .m0_axi_bvalid           (ifu_bvalid),
        .m0_axi_bready           (ifu_bready),
        .m0_axi_arid             ({{(PP_ID_WIDTH-MIFU){1'b0}}, ifu_arid}),
        .m0_axi_araddr           (ifu_araddr),
        .m0_axi_arlen            (ifu_arlen),
        .m0_axi_arsize           (ifu_arsize),
        .m0_axi_arburst          (ifu_arburst),
        .m0_axi_arlock           (ifu_arlock),
        .m0_axi_arprot           (ifu_arprot),
        .m0_axi_arvalid          (ifu_arvalid),
        .m0_axi_arready          (ifu_arready),
        .m0_axi_rid              ({{(PP_ID_WIDTH-MIFU){1'b0}}, ifu_rid}),
        .m0_axi_rdata            (ifu_rdata),
        .m0_axi_rresp            (ifu_rresp),
        .m0_axi_rlast            (ifu_rlast),
        .m0_axi_rvalid           (ifu_rvalid),
        .m0_axi_rready           (ifu_rready),
        // ---- master 1: LSU ----
        .m1_axi_awid             ({{(PP_ID_WIDTH-MID){1'b0}}, lsu_awid}),
        .m1_axi_awaddr           (lsu_awaddr),
        .m1_axi_awlen            (lsu_awlen),
        .m1_axi_awsize           (lsu_awsize),
        .m1_axi_awburst          (lsu_awburst),
        .m1_axi_awlock           (lsu_awlock),
        .m1_axi_awprot           (lsu_awprot),
        .m1_axi_awvalid          (lsu_awvalid),
        .m1_axi_awready          (lsu_awready),
        .m1_axi_wdata            (lsu_wdata),
        .m1_axi_wstrb            (lsu_wstrb),
        .m1_axi_wlast            (lsu_wlast),
        .m1_axi_wvalid           (lsu_wvalid),
        .m1_axi_wready           (lsu_wready),
        .m1_axi_bid              ({{(PP_ID_WIDTH-MID){1'b0}}, lsu_bid}),
        .m1_axi_bresp            (lsu_bresp),
        .m1_axi_bvalid           (lsu_bvalid),
        .m1_axi_bready           (lsu_bready),
        .m1_axi_arid             ({{(PP_ID_WIDTH-MID){1'b0}}, lsu_arid}),
        .m1_axi_araddr           (lsu_araddr),
        .m1_axi_arlen            (lsu_arlen),
        .m1_axi_arsize           (lsu_arsize),
        .m1_axi_arburst          (lsu_arburst),
        .m1_axi_arlock           (lsu_arlock),
        .m1_axi_arprot           (lsu_arprot),
        .m1_axi_arvalid          (lsu_arvalid),
        .m1_axi_arready          (lsu_arready),
        .m1_axi_rid              ({{(PP_ID_WIDTH-MID){1'b0}}, lsu_rid}),
        .m1_axi_rdata            (lsu_rdata),
        .m1_axi_rresp            (lsu_rresp),
        .m1_axi_rlast            (lsu_rlast),
        .m1_axi_rvalid           (lsu_rvalid),
        .m1_axi_rready           (lsu_rready),
        // ---- master 2: store buffer ----
        .m2_axi_awid             ({{(PP_ID_WIDTH-MSB){1'b0}}, sb_awid}),
        .m2_axi_awaddr           (sb_awaddr),
        .m2_axi_awlen            (sb_awlen),
        .m2_axi_awsize           (sb_awsize),
        .m2_axi_awburst          (sb_awburst),
        .m2_axi_awlock           (sb_awlock),
        .m2_axi_awprot           (sb_awprot),
        .m2_axi_awvalid          (sb_awvalid),
        .m2_axi_awready          (sb_awready),
        .m2_axi_wdata            (sb_wdata),
        .m2_axi_wstrb            (sb_wstrb),
        .m2_axi_wlast            (sb_wlast),
        .m2_axi_wvalid           (sb_wvalid),
        .m2_axi_wready           (sb_wready),
        .m2_axi_bid              ({{(PP_ID_WIDTH-MSB){1'b0}}, sb_bid}),
        .m2_axi_bresp            (sb_bresp),
        .m2_axi_bvalid           (sb_bvalid),
        .m2_axi_bready           (sb_bready),
        .m2_axi_arid             ({{(PP_ID_WIDTH-MSB){1'b0}}, sb_arid}),
        .m2_axi_araddr           (sb_araddr),
        .m2_axi_arlen            (sb_arlen),
        .m2_axi_arsize           (sb_arsize),
        .m2_axi_arburst          (sb_arburst),
        .m2_axi_arlock           (sb_arlock),
        .m2_axi_arprot           (sb_arprot),
        .m2_axi_arvalid          (sb_arvalid),
        .m2_axi_arready          (sb_arready),
        .m2_axi_rid              ({{(PP_ID_WIDTH-MSB){1'b0}}, sb_rid}),
        .m2_axi_rdata            (sb_rdata),
        .m2_axi_rresp            (sb_rresp),
        .m2_axi_rlast            (sb_rlast),
        .m2_axi_rvalid           (sb_rvalid),
        .m2_axi_rready           (sb_rready)
    );

endmodule

`default_nettype wire
