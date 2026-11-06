// =============================================================================
// tb_adapter_single.sv
//
// Milestone A unit testbench: verifies width adapter (64-to-32 bit downsizer)
// and protocol bridges (AXI4 to AXI4-Lite) with single-beat transactions.
// =============================================================================

`default_nettype none
`include "pp_test_lib.svh"

module tb_adapter_single;

    import pp_soc_cfg_pkg::*;

    logic clk, rst_n;

    pp_clk_rst #(.CLK_PERIOD_PS(PP_CLK_PERIOD_PS), .RESET_CYCLES(PP_RESET_CYCLES))
    u_clk_rst (.clk(clk), .rst_n(rst_n));

    // The bus harness instantiates the 3 AXI masters, protocol checkers,
    // and the full pp_soc_interconnect fabric.
    pp_bus_harness u_h (.clk(clk), .rst_n(rst_n));

    logic [63:0] rdata;
    logic [1:0]  resp;

    initial begin
        u_h.m0.idle();
        u_h.m1.idle();
        u_h.m2.idle();

        wait (rst_n === 1'b1);
        repeat (10) @(posedge clk);
        $display("[TB] Starting adapter single-beat tests via master 0 (64-bit)...");

        // 1. Test 64-bit Write/Read to Instruction Memory (AXI4 native)
        $display("[TEST 1] 64-bit write and read-back to IMEM...");
        u_h.m0.write_single(3'd1, PP_IMEM_BASE, 3'd3, 64'h11223344_55667788, 8'hFF, resp);
        `CHECK_EQUAL(resp, 2'b00, "IMEM write response OKAY")

        u_h.m0.read_single(3'd1, PP_IMEM_BASE, 3'd3, rdata, resp);
        `CHECK_EQUAL(resp, 2'b00, "IMEM read response OKAY")
        `CHECK_EQUAL(rdata, 64'h11223344_55667788, "IMEM read data match")

        // 2. Test 32-bit Lower-word and Upper-word accesses across downsizer
        $display("[TEST 2] 32-bit accesses through downsizer...");
        u_h.m0.write_single(3'd2, PP_DMEM_BASE, 3'd2, 64'h00000000_AABBCCDD, 8'h0F, resp);
        `CHECK_EQUAL(resp, 2'b00, "DMEM lower-word write response")

        u_h.m0.read_single(3'd2, PP_DMEM_BASE, 3'd2, rdata, resp);
        `CHECK_EQUAL(resp, 2'b00, "DMEM lower-word read response")
        `CHECK_EQUAL(rdata[31:0], 32'hAABBCCDD, "DMEM lower-word match")

        // 3. Test Bridge to AXI4-Lite Peripheral (Timer slot)
        $display("[TEST 3] Accessing AXI4-Lite Timer through downsizer + bridge...");
        u_h.m0.write_single(3'd3, PP_TIMER_BASE + 32'h04, 3'd2, 64'h00000000_00001234, 8'h0F, resp);
        `CHECK_EQUAL(resp, 2'b00, "Timer LOAD register write OKAY")

        u_h.m0.read_single(3'd3, PP_TIMER_BASE + 32'h04, 3'd2, rdata, resp);
        `CHECK_EQUAL(resp, 2'b00, "Timer LOAD register read OKAY")
        `CHECK_EQUAL(rdata[31:0], 32'h00001234, "Timer LOAD read-back match")

        // 4. Test Bridge to HAP Peripheral slot
        $display("[TEST 4] Accessing AXI4-Lite HAP through downsizer + bridge...");
        u_h.m0.write_single(3'd4, PP_HAP_BASE + 32'h08, 3'd2, 64'h00000000_00000500, 8'h0F, resp);
        `CHECK_EQUAL(resp, 2'b00, "HAP threshold register write OKAY")

        u_h.m0.read_single(3'd4, PP_HAP_BASE + 32'h08, 3'd2, rdata, resp);
        `CHECK_EQUAL(resp, 2'b00, "HAP threshold register read OKAY")
        `CHECK_EQUAL(rdata[31:0], 32'h00000500, "HAP threshold read-back match")

        repeat (20) @(posedge clk);
        $display("[PASS] All adapter and bridge single-beat tests completed successfully!");
        $display("PP_RESULT: PASS");
        $finish;
    end

endmodule
`default_nettype wire
