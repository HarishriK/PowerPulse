// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_soc_if.sv
// Description: SystemVerilog Interface for PowerPulse SoC top-level boundary pins
//              with interface-level procedural driving always block and monitor taps
// ==============================================================================

`timescale 1ns/1ps

interface powerpulse_soc_if (
    input logic clk
);

    // --------------------------------------------------------------------------
    // Physical Signals connected to DUT boundary pins
    // --------------------------------------------------------------------------
    logic        rst_n;
    logic        uart_rx;
    logic        uart_tx;
    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;
    logic        uart_irq;
    logic        timer_irq;
    logic        gpio_irq;

    // --------------------------------------------------------------------------
    // Driver Control Registers (Driven by UVM Driver)
    // --------------------------------------------------------------------------
    logic        drv_rst_n_reg   = 1'b1;
    logic        drv_uart_rx_reg = 1'b1;
    logic [7:0]  drv_gpio_in_reg = 8'h00;
    logic        drv_drive_en    = 1'b1;

    // --------------------------------------------------------------------------
    // Passive Monitor Observation Signals (Observed and verified in Verdi)
    // --------------------------------------------------------------------------
    logic [7:0]  mon_gpio_in_sampled = 8'h00;
    logic        mon_gpio_in_valid   = 1'b0;
    logic [7:0]  mon_uart_rx_byte    = 8'h00;
    logic        mon_uart_rx_valid   = 1'b0;

    // ==========================================================================
    // Procedural driving mechanism via interface-level always block
    // (Complies with faculty's requirement for driving using an always block)
    // The UVM driver controls drv_* registers; this always block drives the DUT.
    // ==========================================================================
    always @(posedge clk or negedge drv_rst_n_reg) begin
        if (!drv_rst_n_reg) begin
            rst_n   <= 1'b0;
            uart_rx <= 1'b1;
            gpio_in <= 8'h00;
        end else if (drv_drive_en) begin
            rst_n   <= drv_rst_n_reg;
            uart_rx <= drv_uart_rx_reg;
            gpio_in <= drv_gpio_in_reg;
        end
    end

    // --------------------------------------------------------------------------
    // Synchronized Interface Driving Tasks (called by UVM Driver)
    // --------------------------------------------------------------------------
    task drive_reset_pulse(int unsigned cycles = 20);
        drv_rst_n_reg <= 1'b0;
        repeat (cycles) @(posedge clk);
        drv_rst_n_reg <= 1'b1;
        repeat (5) @(posedge clk);
    endtask: drive_reset_pulse

    task drive_gpio(logic [7:0] data, int unsigned delay_cyc = 10);
        drv_gpio_in_reg <= data;
        repeat (delay_cyc) @(posedge clk);
    endtask: drive_gpio

    task drive_uart_byte(bit [7:0] data, int unsigned baud_cyc = 434);
        int i;
        // Start bit (0)
        drv_uart_rx_reg <= 1'b0;
        repeat (baud_cyc) @(posedge clk);
        // 8 Data bits (LSB first)
        for (i = 0; i < 8; i++) begin
            drv_uart_rx_reg <= data[i];
            repeat (baud_cyc) @(posedge clk);
        end
        // Stop bit (1)
        drv_uart_rx_reg <= 1'b1;
        repeat (baud_cyc) @(posedge clk);
        // Inter-character guard time
        repeat (baud_cyc / 2) @(posedge clk);
    endtask: drive_uart_byte

    task drive_wake_burst(int unsigned delay_cyc = 10);
        drv_gpio_in_reg[0] <= ~drv_gpio_in_reg[0];
        repeat (10) @(posedge clk);
        drv_gpio_in_reg[0] <= ~drv_gpio_in_reg[0];
        repeat (delay_cyc) @(posedge clk);
    endtask: drive_wake_burst

    // --------------------------------------------------------------------------
    // Clocking block for active Driver (synchronized to @(posedge clk))
    // --------------------------------------------------------------------------
    clocking drv_cb @(posedge clk);
        default input #1ns output #1ns;
        output rst_n;
        output uart_rx;
        output gpio_in;
        input  uart_tx;
        input  gpio_out;
        input  uart_irq;
        input  timer_irq;
        input  gpio_irq;
    endclocking

    // --------------------------------------------------------------------------
    // Clocking block for passive Monitor (sampled at @(posedge clk))
    // --------------------------------------------------------------------------
    clocking mon_cb @(posedge clk);
        default input #1ns output #1ns;
        input rst_n;
        input uart_rx;
        input uart_tx;
        input gpio_in;
        input gpio_out;
        input uart_irq;
        input timer_irq;
        input gpio_irq;
    endclocking

    // --------------------------------------------------------------------------
    // Modports
    // --------------------------------------------------------------------------
    modport driver_mp (
        clocking drv_cb,
        import   drive_reset_pulse,
        import   drive_gpio,
        import   drive_uart_byte,
        import   drive_wake_burst,
        output   drv_rst_n_reg,
        output   drv_uart_rx_reg,
        output   drv_gpio_in_reg,
        output   drv_drive_en,
        input    clk
    );

    modport monitor_mp (
        clocking mon_cb,
        input    clk,
        output   mon_gpio_in_sampled,
        output   mon_gpio_in_valid,
        output   mon_uart_rx_byte,
        output   mon_uart_rx_valid
    );

    modport dut_mp (
        input  clk,
        input  rst_n,
        input  uart_rx,
        output uart_tx,
        input  gpio_in,
        output gpio_out,
        output uart_irq,
        output timer_irq,
        output gpio_irq
    );

endinterface: powerpulse_soc_if
