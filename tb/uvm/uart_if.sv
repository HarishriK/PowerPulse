// ==============================================================================
// PowerPulse SoC Verification Environment
// File: uart_if.sv
// Description: Dedicated SystemVerilog Interface for UART with procedural driving always block
// ==============================================================================

`timescale 1ns/1ps

interface uart_if (
    input logic clk
);

    // --------------------------------------------------------------------------
    // Physical Boundary Signals connected to UART DUT
    // --------------------------------------------------------------------------
    logic rst_n;
    logic uart_rx;
    logic uart_tx;
    logic uart_irq;

    // --------------------------------------------------------------------------
    // Driver Control Registers (Driven by UVM Driver)
    // --------------------------------------------------------------------------
    logic drv_rst_n_reg   = 1'b1;
    logic drv_uart_rx_reg = 1'b1;
    logic drv_drive_en    = 1'b1;

    // --------------------------------------------------------------------------
    // Monitor Observation Signals (Observed and verified in Verdi)
    // --------------------------------------------------------------------------
    logic [7:0] mon_uart_rx_byte  = 8'h00;
    logic       mon_uart_rx_valid = 1'b0;

    // ==========================================================================
    // Procedural driving mechanism via interface-level always block
    // (Complies with faculty's requirement for driving using an always block)
    // ==========================================================================
    always @(posedge clk or negedge drv_rst_n_reg) begin
        if (!drv_rst_n_reg) begin
            rst_n   <= 1'b0;
            uart_rx <= 1'b1;
        end else if (drv_drive_en) begin
            rst_n   <= drv_rst_n_reg;
            uart_rx <= drv_uart_rx_reg;
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

    // --------------------------------------------------------------------------
    // Modports
    // --------------------------------------------------------------------------
    modport driver_mp (
        import drive_reset_pulse,
        import drive_uart_byte,
        output drv_rst_n_reg,
        output drv_uart_rx_reg,
        output drv_drive_en,
        input  clk,
        input  rst_n,
        input  uart_tx,
        input  uart_irq
    );

    modport monitor_mp (
        input  clk,
        input  rst_n,
        input  uart_rx,
        input  uart_tx,
        input  uart_irq,
        output mon_uart_rx_byte,
        output mon_uart_rx_valid
    );

    modport dut_mp (
        input  clk,
        input  rst_n,
        input  uart_rx,
        output uart_tx,
        output uart_irq
    );

endinterface: uart_if
