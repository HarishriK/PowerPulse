// -----------------------------------------------------------------------------
// pp_test_lib.svh
//
// The reporting and watchdog layer every PowerPulse test uses.  Include it from
// a testbench; do not instantiate anything.
//
// Why it exists
//   Every test must decide PASS or FAIL by itself, with no human looking at a
//   waveform (PROJECT_CONTEXT.md, verification ethos #1).  This header provides
//   the one convention all tests share:
//
//     * `pp_test_begin` / `pp_test_end` bracket the run and print a header;
//     * `pp_check` and `pp_check_eq` record a check and print PASS or FAIL;
//     * `pp_violation` is what the AXI protocol checkers call;
//     * `pp_summary` prints exactly one `PP_RESULT: PASS|FAIL` line, which is
//       what tools/run_test.py parses;
//     * a watchdog turns a hang into a FAIL, so a broken DUT can never make a
//       test look like it is still working.
//
// `PP_RESULT` is the contract between a testbench and the regression runner.  A
// test that forgets to print it is a FAIL, not a PASS.
// -----------------------------------------------------------------------------

`ifndef PP_TEST_LIB_SVH
`define PP_TEST_LIB_SVH

integer pp_checks;
integer pp_failures;
integer pp_violations;
string  pp_test_name;
string  pp_test_purpose;
bit     pp_finished;

task automatic pp_test_begin(input string name, input string purpose, input integer seed);
    pp_test_name    = name;
    pp_test_purpose = purpose;
    pp_checks       = 0;
    pp_failures     = 0;
    pp_violations   = 0;
    pp_finished     = 0;
    $display("");
    $display("================================================================");
    $display("TEST    : %s", name);
    $display("PURPOSE : %s", purpose);
    $display("SEED    : %0d", seed);
    $display("================================================================");
endtask

task automatic pp_check(input bit ok, input string what);
    pp_checks = pp_checks + 1;
    if (ok) begin
        $display("  [ ok ] %s", what);
    end else begin
        pp_failures = pp_failures + 1;
        $display("  [FAIL] %s", what);
    end
endtask

// Equality check with both values printed, so a failure is diagnosable from the
// log alone.
task automatic pp_check_eq(input longint unsigned got,
                                    input longint unsigned exp,
                                    input string what);
    bit ok = (got === exp);
    pp_checks = pp_checks + 1;
    if (ok) begin
        $display("  [ ok ] %s (= 0x%0h)", what, got);
    end else begin
        pp_failures = pp_failures + 1;
        $display("  [FAIL] %s: got 0x%0h, expected 0x%0h", what, got, exp);
    end
endtask

// Called by pp_axi_checker when it sees a protocol violation.  Counting them
// separately from check failures means the log says clearly whether the DUT or
// the expectation was at fault.
task automatic pp_violation(input string which);
    pp_violations = pp_violations + 1;
    $display("  [FAIL] AXI protocol violation on %s", which);
endtask

// An unconditional failure, for a test that decides for itself (for example
// "the character I decoded was wrong").
task automatic pp_fail(input string what);
    pp_checks = pp_checks + 1;
    pp_failures = pp_failures + 1;
    $display("  [FAIL] %s", what);
endtask

// Finish the test: print the summary and the one machine-readable line the
// regression runner reads, then stop.  Calling it twice is a bug and is reported
// as one.
task automatic pp_test_end();
    if (pp_finished) begin
        $display("  [FAIL] pp_test_end called twice");
        return;
    end
    pp_finished = 1;
    $display("----------------------------------------------------------------");
    $display("%s: %0d checks, %0d failed, %0d protocol violations",
             pp_test_name, pp_checks, pp_failures, pp_violations);
    if (pp_failures == 0 && pp_violations == 0) begin
        $display("PP_RESULT: PASS %s (%0d checks)", pp_test_name, pp_checks);
        $finish;
    end else begin
        $display("PP_RESULT: FAIL %s (%0d failed, %0d protocol violations, %0d checks)",
                 pp_test_name, pp_failures, pp_violations, pp_checks);
        $finish;
    end
endtask

// Watchdog.  `timeout_ns` comes from the test's settings file (via the
// +timeout plusarg the make flow adds), so a hang is always a FAIL with a
// readable reason rather than a build that never finishes.
task automatic pp_watchdog(input longint unsigned timeout_ns);
    #(timeout_ns);
    $display("");
    $display("  [FAIL] TIMEOUT after %0d ns -- the DUT or the stimulus hung", timeout_ns);
    $display("PP_RESULT: FAIL %s (timeout after %0d ns)", pp_test_name, timeout_ns);
    $finish;
endtask

// Watchdog whose limit comes from the run.  The make flow passes the test's
// configured timeout as `+timeout=<ns>`, so a test never has to hardcode one --
// and changing the limit is a settings-file edit, not an RTL edit.
task automatic pp_watchdog_auto(input integer fallback_ns);
    integer t;
    t = fallback_ns;
    if ($value$plusargs("timeout=%d", t)) begin
        // use the run's value
    end
    pp_watchdog(t);
endtask

// Print the run parameters, so a log always says how it was produced.
task automatic pp_print_seed(input integer seed);
    $display("SEED    : %0d", seed);
endtask

`endif
