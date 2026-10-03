// -----------------------------------------------------------------------------
// pp_uart
//
// Wrapper that puts the vendored BSC/CIC-IPN AXI4-Lite UART IP
// (rtl/vendor/axi-lite-uart) behind this project's conventions.  The IP source
// is **not** modified; everything project-specific lives here or in generated
// files.
//
// What the wrapper adds
//   * the project reset convention: one active-low `rst_n` instead of the IP's
//     `axi_aresetn_i`;
//   * explicit clock ports (`clk` for the AXI domain, `uart_clk` for the fixed
//     oversampling domain).  Both are driven from the single SoC clock by the
//     SoC top -- see docs/uart/ for why that is correct here and what would have
//     to change for genuinely different domains;
//   * a PowerPulse naming scheme and the reserved activity/enable hooks the
//     Phase 2 custom IPs need (pp_activity_o, pp_enable_i), tied to harmless
//     constants today so the RTL does not change again in Phase 2;
//   * the IP's 12-bit AXI ID field exposed as a parameter, so the AXI4 -> AXI4-
//     Lite bridge in front of it does not care how wide it is.
//
// Baud rate
//   Not hardcoded here.  The IP's reset value of the divisor register comes from
//   the macros in sim/gen/uart/pp_uart_defines.vh, which tools/gen_uart_defines.py
//   derives from config/soc_config.yaml (clock.freq_hz / uart.baud).  Software
//   can also reprogram the divisor at run time through the divisor register.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_uart #(
    parameter integer ADDR_WIDTH = 5,        // as in the IP's defines header
    parameter integer ID_WIDTH   = 12,       // as in the IP's defines header
    // Phase 2 hooks.  Default values keep Phase 1 behaviour identical.
    parameter bit     EN_DEFAULT = 1'b1
) (
    input  wire                     clk,           // AXI / bus clock domain
    input  wire                     uart_clk,      // fixed oversampling domain
    input  wire                     rst_n,

    // ---------------- AXI4-Lite slave ----------------
    input  wire [ID_WIDTH-1:0]      axi_arid_i,
    input  wire [ADDR_WIDTH-1:0]    axi_araddr_i,
    input  wire                     axi_arvalid_i,
    output wire                     axi_arready_o,

    output wire [ID_WIDTH-1:0]      axi_rid_o,
    output wire [31:0]              axi_rdata_o,
    output wire [1:0]               axi_rresp_o,
    output wire                     axi_rvalid_o,
    input  wire                     axi_rready_i,

    input  wire [ID_WIDTH-1:0]      axi_awid_i,
    input  wire [ADDR_WIDTH-1:0]    axi_awaddr_i,
    input  wire                     axi_awvalid_i,
    output wire                     axi_awready_o,

    input  wire [31:0]              axi_wdata_i,
    input  wire [3:0]               axi_wstrb_i,
    input  wire                     axi_wvalid_i,
    output wire                     axi_wready_o,

    output wire [ID_WIDTH-1:0]      axi_bid_o,
    output wire [1:0]               axi_bresp_o,
    output wire                     axi_bvalid_o,
    input  wire                     axi_bready_i,

    // ---------------- serial ----------------
    input  wire                     uart_rx_i,
    output wire                     uart_tx_o,

    // ---------------- Phase 2 hooks (reserved, tied off today) ----------------
    // Peripheral enable: while low the IP's clock is gated.  Default is 1, so
    // Phase 1 behaviour is unchanged; see PHASES.md P2-00 step 2.
    input  wire                     pp_enable_i,
    // Peripheral activity: pulses when the receiver sees a character, i.e. what
    // the HAP observes.  Default constant today; see P2-00 step 3.
    output wire                     pp_activity_o,
    // Interrupt: reserved for the core's interrupt controller (P2-00 step 4).
    output wire                     irq_o
);

    // ---------------------------------------------------------------------
    // Clock gating for the Phase 2 power-management path.
    //   enable = pp_enable_i & EN_DEFAULT
    // Held in reset-low exactly like the rest of the project, so a disabled
    // peripheral is quiet.  With pp_enable_i tied high (Phase 1) this is a wire.
    // ---------------------------------------------------------------------
    reg enable_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) enable_q <= EN_DEFAULT;
        else        enable_q <= pp_enable_i & EN_DEFAULT;
    end

    wire axi_clk_en   = enable_q;
    wire uart_clk_en  = enable_q;

    // ---------------------------------------------------------------------
    // The IP itself.  Unmodified.
    // ---------------------------------------------------------------------
    axi_uart_top u_uart_ip (
        .fixed_clk_i       (uart_clk_en ? uart_clk  : 1'b0),
        .axi_aclk_i        (axi_clk_en  ? clk       : 1'b0),
        .axi_aresetn_i     (rst_n),

        .axi_arid_i        (axi_arid_i),
        .axi_araddr_i      (axi_araddr_i),
        .axi_arvalid_i     (axi_arvalid_i),
        .axi_arready_o     (axi_arready_o),

        .axi_rid_o         (axi_rid_o),
        .axi_rdata_o       (axi_rdata_o),
        .axi_rresp_o       (axi_rresp_o),
        .axi_rvalid_o      (axi_rvalid_o),
        .axi_rready_i      (axi_rready_i),

        .axi_awid_i        (axi_awid_i),
        .axi_awaddr_i      (axi_awaddr_i),
        .axi_awvalid_i     (axi_awvalid_i),
        .axi_awready_o     (axi_awready_o),

        .axi_wdata_i       (axi_wdata_i),
        .axi_wstrb_i       (axi_wstrb_i),
        .axi_wvalid_i      (axi_wvalid_i),
        .axi_wready_o      (axi_wready_o),

        .axi_bid_o         (axi_bid_o),
        .axi_bresp_o       (axi_bresp_o),
        .axi_bvalid_o      (axi_bvalid_o),
        .axi_bready_i      (axi_bready_i),

        .read_interrupt_o  (irq_o),
        .uart_rx_i         (uart_rx_i),
        .uart_tx_o         (uart_tx_o)
    );

    // Activity indication for the HAP (Phase 2).  Tied to the interrupt request
    // today, which is exactly "a character arrived and is waiting to be read".
    assign pp_activity_o = irq_o;

endmodule

`default_nettype wire
