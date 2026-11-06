// -----------------------------------------------------------------------------
// pp_clk_rst
//
// Clock and reset generation, driven entirely by configuration.
//
//   * `clk` toggles every CLK_PERIOD_PS/2, so the simulation timescale and the
//     configured clock frequency cannot disagree.
//   * `rst_n` is the project's single reset: active-low, asynchronously asserted
//     and synchronously released (see docs/config/conventions.md).  It is held
//     at the asserted level for RESET_CYCLES configured cycles after the clock
//     starts, then released on a falling clock edge -- an edge away from any
//     sampling edge, so recovery/removal is clean.  Assertion is immediate, so
//     nothing downstream can see a half-reset state.
//
// The plusarg `+rst_cycles=<n>` overrides the configured count, which is how a
// test can check that the design comes out of reset cleanly at awkward times.
//
// Everything about the reset is resolved *before* the first clock edge, in one
// initial block: two initial blocks racing to set a delay count is exactly the
// kind of thing that only shows up in simulation.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_clk_rst #(
    parameter integer CLK_PERIOD_PS = 10000,   // 100 MHz
    parameter integer RESET_CYCLES  = 20,
    parameter          RESET_VALUE  = 1'b0    // the *asserted* level (active low)
) (
    output reg clk,
    output reg rst_n
);

    integer cycles;

    // Clock -------------------------------------------------------------
    initial clk = 1'b0;
    always #(CLK_PERIOD_PS / 2) clk = ~clk;

    // Reset -------------------------------------------------------------
    initial begin
        cycles = RESET_CYCLES;
        if ($value$plusargs("rst_cycles=%d", cycles)) begin
            // the run asked for a specific reset length
        end

        rst_n = RESET_VALUE;                  // asserted while in reset
        repeat (cycles) @(posedge clk);
        @(negedge clk) rst_n = ~RESET_VALUE;  // release, away from a clock edge

        $display("[pp_clk_rst] clock period %0d ps (%0d MHz), reset held %0d cycles",
                 CLK_PERIOD_PS, 1000000000 / CLK_PERIOD_PS, cycles);
    end

endmodule

`default_nettype wire
