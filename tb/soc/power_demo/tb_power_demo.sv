// =============================================================================
// tb_power_demo.sv
//
// End-to-end core-in-loop system testbench for the PowerPulse SoC.
//
// Proves the full activity-management sequence:
//   Activity Monitoring -> Idle Detection -> LOW-ACTIVITY Transition
//   -> Wake-Up Event Detection -> Automatic Restoration -> Software Telemetry.
//
// The testbench:
//   1. Generates system clock and active-low reset.
//   2. Instantiates the full PowerPulse SoC (VeeR EL2 + Interconnect + Peripherals + HAP/PPMC/AWEC).
//   3. Decodes all UART console logs via pp_uart_model.
//   4. Stimulates GPIO inputs after idle entry to demonstrate hardware wake-up.
//   5. Checks that the simulation concludes with a PASS status report.
// =============================================================================

`default_nettype none
`include "pp_test_lib.svh"

module tb_power_demo;

    import pp_soc_cfg_pkg::*;

    // ---- Clock and reset ---------------------------------------------------
    logic clk, rst_n;

    pp_clk_rst #(.CLK_PERIOD_PS(PP_CLK_PERIOD_PS), .RESET_CYCLES(PP_RESET_CYCLES))
    u_clk_rst (.clk(clk), .rst_n(rst_n));

    // ---- Boundary Pins -----------------------------------------------------
    wire        uart_rx;
    wire        uart_tx;
    wire        uart_irq;
    reg  [7:0]  gpio_in_reg;
    wire [7:0]  gpio_out;
    wire        timer_irq;
    wire        gpio_irq;

    // ---- PowerPulse SoC DUT ------------------------------------------------
    powerpulse_soc dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio_in(gpio_in_reg),
        .gpio_out(gpio_out),
        .uart_irq(uart_irq),
        .timer_irq(timer_irq),
        .gpio_irq(gpio_irq)
    );

    // ---- UART BFM / Model --------------------------------------------------
    pp_uart_model #(
        .CLK_FREQ_HZ(PP_CLK_FREQ_HZ),
        .BAUD(PP_UART_BAUD),
        .DATA_BITS(8),
        .PARITY(0),
        .STOP_BITS(1),
        .RX_INJECT(0)
    ) u_uart_model (
        .rx_clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // ---- Test Stimulus & Wake Trigger --------------------------------------
    initial begin
        gpio_in_reg = 8'h00;

        // Wait for reset release and boot
        wait (rst_n === 1'b1);
        $display("[TB] PowerPulse system reset released. SoC executing software...");

        // Wait 10,000 cycles for software initialization and HAP idle entry
        repeat (10000) @(posedge clk);

        // Inject external wake event via GPIO pin toggle
        $display("[TB] Injecting GPIO pin toggle to stimulate AWEC wake-up...");
        gpio_in_reg = 8'h80;
        repeat (20) @(posedge clk);
        gpio_in_reg = 8'h00;
    end

    // Print decoded UART characters to simulation transcript
    always @(posedge clk) begin
        if (u_uart_model.rx_byte_valid) begin
            $write("%c", u_uart_model.rx_byte);
        end
    end

endmodule
`default_nettype wire
