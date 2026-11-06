// =============================================================================
// tb_uart_hello
//
// Milestone B (P1-12) core-in-loop software test.
//
// The real VeeR EL2 core boots from the hex image loaded into instruction
// memory, runs the uart_hello program, and transmits "Hello UART\n" through
// the real UART IP.  The testbench UART model decodes the DUT's TX line and
// the test checks every received byte against the expected string.
//
// The test passes when:
//   * the UART model decodes exactly the bytes of "Hello UART\n"
//   * the software reports PASS via the simulation status device
//   * no AXI protocol checkers fire
//
// The hex file path comes from the +hex plusarg (set by the make flow's
// swbuild.py).  The testbench does not drive any AXI bus itself; the core is
// the only master.
// =============================================================================

`default_nettype none
`include "pp_test_lib.svh"

module tb_uart_hello;

    import pp_soc_cfg_pkg::*;

    // ---- clock and reset (config-driven) -----------------------------------
    logic clk, rst_n;

    pp_clk_rst #(.CLK_PERIOD_PS(PP_CLK_PERIOD_PS), .RESET_CYCLES(PP_RESET_CYCLES))
    u_clk_rst (.clk(clk), .rst_n(rst_n));

    // ---- UART serial lines -------------------------------------------------
    wire uart_rx;   // driven by the UART model (unused for TX-only test)
    wire uart_tx;   // driven by the DUT, sampled by the model
    wire uart_irq;

    // ---- the SoC under test ------------------------------------------------
    powerpulse_soc dut (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .gpio_in(8'h00),
        .gpio_out(),
        .uart_irq(uart_irq),
        .timer_irq(),
        .gpio_irq()
    );

    // ---- UART bus functional model -----------------------------------------
    // RX_INJECT = 0: receive-only (this test does not send bytes to the DUT).
    pp_uart_model #(
        .CLK_FREQ_HZ(PP_CLK_FREQ_HZ),
        .BAUD(PP_UART_BAUD),
        .DATA_BITS(8),
        .PARITY(0),
        .STOP_BITS(1),
        .RX_INJECT(0)
    ) uart_model (
        .rx_clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx)
    );

    // =====================================================================
    // expected output: "Hello UART\n"
    // =====================================================================
    localparam string EXPECTED = "Hello UART\n";
    localparam int unsigned EXPECTED_LEN = 11;

    logic [7:0] expected_bytes [0:EXPECTED_LEN-1];

    initial begin
        // Build the expected byte array from the string constant.
        for (int i = 0; i < EXPECTED_LEN; i++) begin
            expected_bytes[i] = EXPECTED[i];
        end
    end

    // =====================================================================
    // watchdog: the external +timeout plusarg provides the hard limit.
    // The watchdog here is a generous backstop measured in clock cycles.
    // 11 bytes at 115200 baud = ~95K cycles; give 10x headroom + boot time.
    // =====================================================================
    initial begin
        longint unsigned watchdog;
        watchdog = 50000000;  // 50M cycles = 500 ms at 10 ns/clock
        void'($value$plusargs("timeout=%d", watchdog));
        // Convert ns timeout to cycle count (period is ~10 ns)
        watchdog = watchdog / 10;
        repeat (watchdog) @(posedge clk);
        $display("");
        $display("  [FAIL] TIMEOUT after %0d cycles -- the DUT did not produce UART output", watchdog);
        $display("PP_RESULT: FAIL uart_hello (timeout)");
        $finish;
    end

    // ---- debug: trace core AXI activity ----
    initial begin
        wait (rst_n === 1'b1);
        repeat (5) @(posedge clk);
        $display("[dbg] rst_n=%0d ifu_arvalid=%0d ifu_arready=%0d ifu_awvalid=%0d",
                 rst_n, dut.ifu_arvalid, dut.ifu_arready, dut.ifu_awvalid);
        $display("[dbg] lsu_arvalid=%0d lsu_awvalid=%0d", dut.lsu_arvalid, dut.lsu_awvalid);
        $display("[dbg] trace_valid=%0d trace_insn=0x%08h", dut.trace_valid, dut.trace_insn);
        // sample every 100 cycles for the first 2000 cycles
        for (int i = 0; i < 20; i++) begin
            repeat (100) @(posedge clk);
            if (dut.ifu_arvalid || dut.lsu_awvalid || dut.lsu_arvalid)
                $display("[dbg] t=%0t: ifu_ar=%0d/%0d lsu_aw=%0d lsu_ar=%0d trace=%0d",
                         $time, dut.ifu_arvalid, dut.ifu_arready,
                         dut.lsu_awvalid, dut.lsu_arvalid, dut.trace_valid);
        end
    end

    // =====================================================================
    // main test sequence: wait for the UART model to collect bytes, then
    // check them.  This runs in parallel with the watchdog above.  The
    // software's pp_status_pass() call (via the status device) will call
    // $finish and end the simulation; we do NOT call pp_test_end here.
    // =====================================================================
    initial begin
        integer seed;
        logic [7:0] rx_byte;
        bit         match;
        int         received;

        seed = 1;
        void'($value$plusargs("seed=%d", seed));
        pp_test_begin("uart_hello",
                      {"VeeR core runs software that prints a string; ",
                       "the UART model decodes it exactly"},
                      seed);

        // Wait for reset to deassert.
        wait (rst_n === 1'b1);
        repeat (4) @(posedge clk);

        // ---- wait for the UART model to receive all expected bytes ----
        // The core needs time to boot, fetch instructions, and start
        // transmitting.  Each byte at 115200 baud takes ~8680 cycles.
        // 11 bytes * ~10000 cycles = ~110K cycles minimum.
        // Give generous headroom for core boot and I-cache fills.
        fork : wait_uart
            begin
                // Wait until the model has collected all expected bytes.
                wait (uart_model.num_received() >= EXPECTED_LEN);
            end
            begin
                // Backstop: wait a very long time (the watchdog will kill us
                // if this takes too long).
                forever @(posedge clk);
            end
        join_any
        disable wait_uart;

        // ---- give a few extra cycles for the model to finish decoding ----
        repeat (500) @(posedge clk);

        // ---- dump what the model received, for log diagnostics ----
        uart_model.dump_received();

        // ---- check the received bytes against the expected string ----
        received = uart_model.num_received();
        pp_check_eq(received, EXPECTED_LEN,
                    "UART model received the expected number of bytes");

        if (received >= EXPECTED_LEN) begin
            match = 1'b1;
            for (int i = 0; i < EXPECTED_LEN; i++) begin
                uart_model.get_byte(rx_byte);
                if (rx_byte !== expected_bytes[i]) begin
                    match = 1'b0;
                    $display("  [FAIL] byte %0d: got 0x%02h ('%c'), expected 0x%02h ('%c')",
                             i, rx_byte,
                             (rx_byte >= 8'h20 && rx_byte < 8'h7f) ? rx_byte : 8'h2e,
                             expected_bytes[i],
                             (expected_bytes[i] >= 8'h20 && expected_bytes[i] < 8'h7f) ?
                                 expected_bytes[i] : 8'h2e);
                end else begin
                    $display("  [ ok ] byte %0d: 0x%02h '%c'", i, rx_byte,
                             (rx_byte >= 8'h20 && rx_byte < 8'h7f) ? rx_byte : 8'h2e);
                end
            end
            pp_check(match, "UART output matches \"Hello UART\\n\" exactly");
        end else begin
            pp_fail("did not receive enough bytes from the UART");
        end

        // ---- check for framing/parity errors ----
        pp_check_eq(uart_model.num_framing_errors(), 0, "no UART framing errors");
        pp_check_eq(uart_model.num_parity_errors(),  0, "no UART parity errors");

        // ---- Now wait for the software to report PASS via the status ----
        // device.  pp_status_pass() writes to the status device which calls
        // $finish with PP_RESULT: PASS.  We do NOT call pp_test_end here
        // because the status device's $finish is the authoritative result.
        // If the software never reports, the watchdog will catch it.
        //
        // If we get here and the UART checks passed, but the software has
        // not yet reported, just wait.  The status device will end the sim.
        // If the UART checks failed, we report the failure and finish.
        if (pp_failures > 0) begin
            pp_test_end();
        end
        // Otherwise: let the simulation continue.  The status device will
        // call $finish when the software reports PASS.
    end

endmodule

`default_nettype wire
