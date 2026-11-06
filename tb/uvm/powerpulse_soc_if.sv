// ==============================================================================
// PowerPulse SoC Verification Environment
// File: powerpulse_soc_if.sv
// Description: SystemVerilog Interface for PowerPulse SoC top-level boundary pins
// ==============================================================================

`timescale 1ns/1ps

interface powerpulse_soc_if (
    input logic clk
);

    // Asynchronous / Synchronous Reset
    logic        rst_n;

    // UART Serial Interface
    logic        uart_rx;
    logic        uart_tx;

    // GPIO Parallel Interface
    logic [7:0]  gpio_in;
    logic [7:0]  gpio_out;

    // Interrupt / Observability Outputs
    logic        timer_irq;
    logic        gpio_irq;

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
        input timer_irq;
        input gpio_irq;
    endclocking

    // --------------------------------------------------------------------------
    // Modports
    // --------------------------------------------------------------------------
    modport driver_mp (
        clocking drv_cb,
        output   rst_n,
        output   uart_rx,
        output   gpio_in,
        input    clk
    );

    modport monitor_mp (
        clocking mon_cb,
        input    clk
    );

    modport dut_mp (
        input  clk,
        input  rst_n,
        input  uart_rx,
        output uart_tx,
        input  gpio_in,
        output gpio_out,
        output timer_irq,
        output gpio_irq
    );

endinterface: powerpulse_soc_if
