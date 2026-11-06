// ==============================================================================
// PowerPulse SoC Verification Environment
// File: tb_soc_uvm_top.sv
// Description: Top-level Testbench Module instantiating DUT, Interface, and UVM Root
// ==============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import powerpulse_uvm_pkg::*;

module tb_soc_uvm_top;

    // --------------------------------------------------------------------------
    // Clock & Timing Generation (50 MHz System Clock -> 20ns period)
    // --------------------------------------------------------------------------
    logic clk;

    initial begin
        clk = 1'b0;
        forever #10ns clk = ~clk;
    end

    // --------------------------------------------------------------------------
    // Interface Instance
    // --------------------------------------------------------------------------
    powerpulse_soc_if soc_if (
        .clk (clk)
    );

    // --------------------------------------------------------------------------
    // Design Under Test (DUT) Instance
    // --------------------------------------------------------------------------
    wire uart_irq_unused;

    powerpulse_soc u_dut (
        .clk       (clk),
        .rst_n     (soc_if.rst_n),
        .uart_rx   (soc_if.uart_rx),
        .uart_tx   (soc_if.uart_tx),
        .gpio_in   (soc_if.gpio_in),
        .gpio_out  (soc_if.gpio_out),
        .uart_irq  (uart_irq_unused),
        .timer_irq (soc_if.timer_irq),
        .gpio_irq  (soc_if.gpio_irq)
    );

    // --------------------------------------------------------------------------
    // Optional Waveform Dumping (Verdi FSDB & Standard VCD)
    // --------------------------------------------------------------------------
    initial begin
        string dump_vcd;
        if ($value$plusargs("DUMP_VCD=%s", dump_vcd) || $test$plusargs("DUMP")) begin
            $dumpfile("powerpulse_uvm.vcd");
            $dumpvars(0, tb_soc_uvm_top);
        end
`ifdef FSDB
        $fsdbDumpfile("powerpulse_uvm.fsdb");
        $fsdbDumpvars(0, tb_soc_uvm_top);
`endif
    end

    // --------------------------------------------------------------------------
    // Memory Backdoor Hex Loading for Firmware execution
    // --------------------------------------------------------------------------
    initial begin
        string hex_file;
        if ($value$plusargs("HEX=%s", hex_file)) begin
            `uvm_info("UVM_TOP", $sformatf("Loading Firmware HEX into IMEM: %s", hex_file), UVM_LOW)
            $readmemh(hex_file, u_dut.u_fabric.u_s0_imem.mem);
        end
    end

    // --------------------------------------------------------------------------
    // Testbench Initialization and UVM Phase Start
    // --------------------------------------------------------------------------
    initial begin
        // Store virtual interface in uvm_config_db
        uvm_config_db#(virtual powerpulse_soc_if)::set(null, "*", "vif", soc_if);

        // Run the test passed on the command line via +UVM_TESTNAME=<test>
        // Defaults to powerpulse_base_test if omitted
        run_test("powerpulse_base_test");
    end

    // --------------------------------------------------------------------------
    // Global Simulation Watchdog Timeout (100 ms)
    // --------------------------------------------------------------------------
    initial begin
        #100ms;
        `uvm_fatal("UVM_WATCHDOG", "Global simulation watchdog timeout exceeded! Potential deadlock.")
    end

endmodule: tb_soc_uvm_top
