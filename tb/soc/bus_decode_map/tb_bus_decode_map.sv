// =============================================================================
// bus_decode_map
//
// Proves the address decode is exactly what config/soc_config.yaml says:
//   * every *enabled* slave answers at its configured base with OKAY;
//   * the word immediately below each slot and the word immediately above its
//     end both return DECERR;
//   * the boundaries of neighbouring slots do not bleed into each other.
//
// The expected addresses are taken from the generated pp_soc_cfg_pkg, i.e. from
// the configuration, never from what the RTL happens to decode to.  The expected
// responses come from the interconnect specification: a real slave answers
// OKAY, an address outside every window goes to the decode-error default.
//
// The DUT is the real interconnect fabric (rtl/top/pp_soc_interconnect.sv),
// driven by 64-bit AXI4 master models through the real width adapters, with AXI
// protocol checkers always attached.
// =============================================================================

`default_nettype none
`include "pp_test_lib.svh"

module tb_bus_decode_map;

    import pp_soc_cfg_pkg::*;

    logic clk, rst_n;

    pp_clk_rst #(.CLK_PERIOD_PS(PP_CLK_PERIOD_PS), .RESET_CYCLES(PP_RESET_CYCLES))
    u_clk_rst (.clk(clk), .rst_n(rst_n));

    pp_bus_harness u_h (.clk(clk), .rst_n(rst_n));

    localparam logic [63:0] PATTERN = 64'h0123_4567_89AB_CDEF;

    // ---------------------------------------------------------------------
    // helper: write a wide pattern at `addr` and read it back, returning the
    // response both transactions produced.  Uses the full 64-bit path, so it
    // also proves the width adapters let a doubleword reach a 32-bit slave.
    // ---------------------------------------------------------------------
    task automatic write_readback(input logic [31:0] addr,
                                  input logic [63:0] data,
                                  output logic [1:0] wresp,
                                  output logic [63:0] rdata,
                                  output logic [1:0] rresp);
        logic [1:0] r1, r2;
        u_h.m0.write_single(3'd1, addr,          3'd3, data,        8'hFF, wresp);
        u_h.m0.write_single(3'd2, addr + 32'd4,  3'd3, {32'd0, data[63:32]}, 8'h00, r1);
        u_h.m0.read_single (3'd3, addr,          3'd3, rdata,       rresp);
    endtask

    // ---------------------------------------------------------------------
    // 32-bit read used for the boundary checks: one beat, one response, so the
    // verdict is unambiguous.
    // ---------------------------------------------------------------------
    task automatic probe32(input logic [31:0] addr, output logic [1:0] resp);
        logic [63:0] ignored_data;
        u_h.m0.read_single(3'd0, addr, 3'd2, ignored_data, resp);
    endtask

    // ---------------------------------------------------------------------
    initial begin
        integer seed;
        logic [1:0] wresp, rresp, edge_resp;
        logic [63:0] rdata;

        seed = 1;
        void'($value$plusargs("seed=%d", seed));
        pp_test_begin("bus_decode_map",
                      {"every enabled slave answers at its configured base; ",
                       "addresses just outside return DECERR"},
                      seed);
        pp_watchdog_auto(200000);   // overridden by the run's +timeout

        wait (rst_n === 1'b1);
        repeat (4) @(posedge clk);

        // ---------------- data memory: write then read back ----------------
        write_readback(PP_DMEM_BASE + 32'h0000_0100, PATTERN, wresp, rdata, rresp);
        pp_check_eq({30'd0, wresp}, 32'd0, "dmem write returns OKAY");
        pp_check_eq({30'd0, rresp}, 32'd0, "dmem read returns OKAY");
        pp_check_eq(rdata, PATTERN, "dmem read returns the 64-bit pattern that was written");

        // ---------------- instruction memory: readable and writable --------
        write_readback(PP_IMEM_BASE + 32'h0000_0200, ~PATTERN, wresp, rdata, rresp);
        pp_check_eq({30'd0, wresp}, 32'd0, "imem write returns OKAY");
        pp_check_eq({30'd0, rresp}, 32'd0, "imem read returns OKAY");
        pp_check_eq(rdata, ~PATTERN, "imem read returns the 64-bit pattern that was written");

        // ---------------- UART: a real register read must be OKAY ----------
        // LSR is at offset 0x14 in the vendored IP (see docs/uart).
        probe32(PP_UART_BASE + 32'h14, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd0,
                    "UART LSR read at PP_UART_BASE+0x14 returns OKAY");

        // ---------------- status device: simulation only --------------------
        probe32(PP_STATUS_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd0,
                    "status device read at its base returns OKAY");

        // ---------------- boundaries: one word below each slot --------------
        probe32(PP_DMEM_BASE - 32'd4, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "word below dmem returns DECERR");

        probe32(PP_IMEM_BASE - 32'd4, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "word below imem returns DECERR");

        probe32(PP_UART_BASE - 32'd4, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "word below the UART slot returns DECERR");

        // ---------------- boundaries: first word above each slot ------------
        probe32(PP_DMEM_BASE + PP_DMEM_SIZE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "first word above dmem returns DECERR");

        probe32(PP_IMEM_BASE + PP_IMEM_SIZE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "first word above imem returns DECERR");

        probe32(PP_UART_BASE + PP_UART_SIZE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "first word above the UART slot returns DECERR");

        probe32(PP_STATUS_BASE + PP_STATUS_SIZE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "first word above the status slot returns DECERR");

        // ---------------- last word inside each slot is still inside --------
        probe32(PP_DMEM_BASE + PP_DMEM_SIZE - 32'd4, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd0, "last word of dmem is still inside the slot");

        probe32(PP_UART_BASE + PP_UART_SIZE - 32'd4, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd0,
                    "last word of the UART window is still inside the slot");

        // ---------------- reserved Phase 2 slots answer, with an error --------
        // They are wired to the decode-error stub, so they must complete with
        // DECERR -- never hang, and never answer OKAY as if they were real.
        probe32(PP_TIMER_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "reserved timer slot answers DECERR");
        probe32(PP_GPIO_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "reserved gpio slot answers DECERR");
        probe32(PP_HAP_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "reserved hap slot answers DECERR");
        probe32(PP_PPMC_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "reserved ppmc slot answers DECERR");
        probe32(PP_AWEC_BASE, edge_resp);
        pp_check_eq({30'd0, edge_resp}, 32'd3, "reserved awec slot answers DECERR");

        pp_test_end();
    end

endmodule

`default_nettype wire
