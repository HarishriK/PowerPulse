// ==============================================================================
// PowerPulse SoC Verification Environment
// File: tb_top.sv
// Description: Alternative Top-level Testbench Module (tb_top) alias
// ==============================================================================

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import powerpulse_uvm_pkg::*;

module tb_top;

    // --------------------------------------------------------------------------
    // Clock & Timing Generation (50 MHz System Clock -> 20ns period)
    // --------------------------------------------------------------------------
    logic clk;

    initial begin
        clk = 1'b0;
        forever #10ns clk = ~clk;
    end

    // --------------------------------------------------------------------------
    // SystemVerilog Interface Instance
    // --------------------------------------------------------------------------
    powerpulse_soc_if soc_if (
        .clk (clk)
    );

    // --------------------------------------------------------------------------
    // Design Under Test (DUT) Instance: PowerPulse SoC
    // --------------------------------------------------------------------------
    powerpulse_soc u_dut (
        .clk       (clk),
        .rst_n     (soc_if.rst_n),
        .uart_rx   (soc_if.uart_rx),
        .uart_tx   (soc_if.uart_tx),
        .gpio_in   (soc_if.gpio_in),
        .gpio_out  (soc_if.gpio_out),
        .uart_irq  (soc_if.uart_irq),
        .timer_irq (soc_if.timer_irq),
        .gpio_irq  (soc_if.gpio_irq)
    );

    // --------------------------------------------------------------------------
    // Waveform Dumping (Verdi FSDB & Standard VCD)
    // --------------------------------------------------------------------------
    initial begin
        $dumpfile("powerpulse_uvm.vcd");
        $dumpvars(0, tb_top);

`ifdef FSDB
        $fsdbDumpfile("powerpulse_uvm.fsdb");
        $fsdbDumpvars(0, tb_top);
`endif
    end

    // --------------------------------------------------------------------------
    // Memory Backdoor Hex Loading for Firmware Execution
    // --------------------------------------------------------------------------
    initial begin
        string hex_file;
        if ($value$plusargs("HEX=%s", hex_file) || $value$plusargs("hex=%s", hex_file)) begin
            `uvm_info("UVM_TOP", $sformatf("Loading Firmware HEX into IMEM: %s", hex_file), UVM_LOW)
            $readmemh(hex_file, u_dut.u_fabric.u_imem.mem);
        end
    end

    // --------------------------------------------------------------------------
    // Virtual Interface Configuration and UVM Phase Start
    // --------------------------------------------------------------------------
    initial begin
        // Configure virtual interface handles using uvm_config_db::set()
        uvm_config_db#(virtual powerpulse_soc_if)::set(
            null,
            "uvm_test_top.env.agent*",
            "vif",
            soc_if
        );

        uvm_config_db#(virtual powerpulse_soc_if)::set(
            null,
            "*",
            "vif",
            soc_if
        );

        run_test("powerpulse_base_test");
    end

    // --------------------------------------------------------------------------
    // Global Simulation Watchdog Timeout (100 ms)
    // --------------------------------------------------------------------------
    initial begin
        #100ms;
        `uvm_fatal("UVM_WATCHDOG", "Global simulation watchdog timeout exceeded! Potential deadlock.")
    end

endmodule: tb_top
