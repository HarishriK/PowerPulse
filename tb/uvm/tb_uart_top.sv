// ==============================================================================
// PowerPulse SoC Verification Environment
// File: tb_uart_top.sv
// Description: Dedicated UVM Top-Level Testbench for UART Interface
//              (Directly demonstrates Virtual Interface Connection and Driving)
// ==============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import uart_uvm_pkg::*;

module tb_uart_top;

    // --------------------------------------------------------------------------
    // 1. Clock Generation
    // --------------------------------------------------------------------------
    logic clk;

    initial begin
        clk = 1'b0;
        forever #10ns clk = ~clk;
    end

    // --------------------------------------------------------------------------
    // 2. Instantiate Dedicated UART Interface
    // --------------------------------------------------------------------------
    uart_if uart_if_inst (
        .clk (clk)
    );

    // --------------------------------------------------------------------------
    // 3. Connect Interface to the SoC DUT
    // --------------------------------------------------------------------------
    powerpulse_soc u_dut (
        .clk       (clk),
        .rst_n     (uart_if_inst.rst_n),
        .uart_rx   (uart_if_inst.uart_rx),
        .uart_tx   (uart_if_inst.uart_tx),
        .gpio_in   (8'h00),
        .gpio_out  (),
        .uart_irq  (uart_if_inst.uart_irq),
        .timer_irq (),
        .gpio_irq  ()
    );

    // --------------------------------------------------------------------------
    // 4. Waveform Dumping for Synopsys Verdi & VCD
    // --------------------------------------------------------------------------
    initial begin
        $dumpfile("uart_uvm.vcd");
        $dumpvars(0, tb_uart_top);

`ifdef FSDB
        $fsdbDumpfile("uart_uvm.fsdb");
        $fsdbDumpvars(0, tb_uart_top);
`endif
    end

    // --------------------------------------------------------------------------
    // 5. Configure Virtual Interface via uvm_config_db and Launch UVM Test
    // --------------------------------------------------------------------------
    initial begin
        // Configure virtual interface handle (hierarchical scope)
        uvm_config_db#(virtual uart_if)::set(
            null,
            "uvm_test_top.env.agent*",
            "vif",
            uart_if_inst
        );

        // Configure virtual interface handle (wildcard fallback)
        uvm_config_db#(virtual uart_if)::set(
            null,
            "*",
            "vif",
            uart_if_inst
        );

        // Launch UVM Test
        run_test("uart_base_test");
    end

    // --------------------------------------------------------------------------
    // 6. Global Simulation Watchdog Timeout
    // --------------------------------------------------------------------------
    initial begin
        #100ms;
        `uvm_fatal("UART_TOP_TIMEOUT", "Watchdog timeout exceeded!")
    end

endmodule: tb_uart_top
