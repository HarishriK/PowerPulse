// -----------------------------------------------------------------------------
// pp_uart_model
//
// UART bus functional model.  One instance models one UART line pair from the
// DUT's point of view:
//
//   * `send_byte(byte)` drives the DUT's RX pin with a correctly framed
//     character, bit by bit, at the configured baud rate.
//   * the DUT's TX pin is sampled continuously; every complete frame is decoded
//     and pushed into a queue that the test can pop and compare.
//
// Parameters
//   CLK_FREQ_HZ   the serial clock the DUT counts (config: clock.freq_hz)
//   BAUD          the baud rate both ends agree on (config: uart.baud)
//   DATA_BITS     5..8
//   PARITY        0 = none, 1 = even, 2 = odd
//   STOP_BITS     1 or 2
//   RX_INJECT     1 = enable send_byte / error injection, 0 = receive only
//
// Error injection (used by uart_error_cases)
//   `send_bad_stop(bit)` frames a character but drives the stop bit to `bit`,
//   which a compliant receiver must reject.
//   `send_break()` holds RX low for several frame times, which the DUT's
//   receiver must treat as a framing error, not as data.
//
// Framing, by construction: 1 start bit, DATA_BITS data bits LSB first,
// [parity], STOP_BITS stop bits.  Both directions use the same model, so the
// model is never the thing under test -- only the DUT is.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_uart_model #(
    parameter integer CLK_FREQ_HZ = 100000000,
    parameter integer BAUD        = 115200,
    parameter integer DATA_BITS   = 8,
    parameter integer PARITY      = 0,     // 0 none, 1 even, 2 odd
    parameter integer STOP_BITS   = 1,
    parameter          RX_INJECT   = 1
) (
    input  wire rx_clk,        // the clock the serial line is sampled on
    input  wire rst_n,
    output wire uart_rx,       // driven by this model into the DUT
    input  wire uart_tx        // driven by the DUT, sampled by this model
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD;
    localparam integer BIT_HALF    = CLKS_PER_BIT / 2;

    // ---------------------------------------------------------------------
    // transmit: this model -> DUT RX
    // ---------------------------------------------------------------------
    reg rx_line;
    assign uart_rx = rx_line;

    task automatic drive_bit(input bit level);
        begin
            rx_line = level;
            repeat (CLKS_PER_BIT) @(posedge rx_clk);
        end
    endtask

    // Frame one character on the RX line.  `bad_stop` = 0 sends a valid frame;
    // otherwise the stop bit is forced to the given level so a compliant
    // receiver must report a framing error.
    task automatic send_byte(input logic [7:0] value, input bit bad_stop,
                             input bit bad_parity);
        logic parity_bit;
        begin
            parity_bit = 1'b0;
            if (PARITY == 1) begin                    // even
                parity_bit = ^value;
            end else if (PARITY == 2) begin           // odd
                parity_bit = ~^value;
            end

            drive_bit(1'b1);                          // idle
            drive_bit(1'b0);                          // start
            for (int i = 0; i < DATA_BITS; i++) begin
                drive_bit(value[i]);
            end
            if (PARITY != 0) drive_bit(bad_parity ? ~parity_bit : parity_bit);
            for (int i = 0; i < STOP_BITS; i++) begin
                drive_bit(bad_stop ? bad_stop : 1'b1);
            end
            drive_bit(1'b1);                          // back to idle
        end
    endtask

    task automatic send_byte_ok(input logic [7:0] value);
        send_byte(value, 1'b1, 1'b0);
    endtask

    // Hold the line low for several frame times: a break condition.
    task automatic send_break();
        begin
            rx_line = 1'b0;
            repeat (CLKS_PER_BIT * 4) @(posedge rx_clk);
            rx_line = 1'b1;
        end
    endtask

    initial rx_line = 1'b1;

    // ---------------------------------------------------------------------
    // receive: DUT TX -> this model
    // ---------------------------------------------------------------------
    localparam integer MAX_BYTES = 4096;
    logic [7:0] rx_queue [0:MAX_BYTES-1];
    integer     rx_count;
    integer     rx_head;
    integer     framing_errors;
    integer     parity_errors;
    bit         rx_busy;
    bit         rx_start_seen;

    // A falling edge on TX is a candidate start bit; the bit-level receiver
    // below does the real work, sampling in the middle of every bit.
    always @(negedge uart_tx) begin
        rx_start_seen = 1'b1;
    end

    // Bit-level receiver.  Sampling in the middle of each bit is what makes the
    // model tolerant of the DUT's own baud rounding.
    task automatic receive_one(output logic [7:0] value, output bit framing_error,
                               output bit parity_error);
        logic [7:0] shift;
        logic       pbit;
        logic       stop_ok;
        begin
            value         = 8'h00;
            framing_error = 1'b0;
            parity_error  = 1'b0;
            shift         = 8'h00;

            repeat (BIT_HALF) @(posedge rx_clk);        // to the middle of the start bit
            for (int i = 0; i < DATA_BITS; i++) begin
                shift[i] = uart_tx;
                repeat (CLKS_PER_BIT) @(posedge rx_clk);
            end
            if (PARITY != 0) begin
                pbit = uart_tx;
                repeat (CLKS_PER_BIT) @(posedge rx_clk);
            end
            stop_ok = 1'b1;
            for (int i = 0; i < STOP_BITS; i++) begin
                if (uart_tx !== 1'b1) stop_ok = 1'b0;
                repeat (CLKS_PER_BIT) @(posedge rx_clk);
            end

            value         = shift;
            framing_error = !stop_ok;
            if (PARITY == 1)      parity_error = (pbit !== (^shift));
            else if (PARITY == 2) parity_error = (pbit !== (~^shift));
        end
    endtask

    // Continuously drain the DUT's TX line.
    initial begin
        rx_count         = 0;
        rx_head          = 0;
        framing_errors   = 0;
        parity_errors    = 0;
        rx_busy          = 1'b0;
        rx_start_seen    = 1'b0;
        forever begin
            @(posedge uart_tx);
            if (uart_tx == 1'b0 && !rx_busy) begin
                rx_busy = 1'b1;
                fork
                    begin
                        logic [7:0] b;
                        bit fe, pe;
                        // wait for the middle of the start bit
                        receive_one(b, fe, pe);
                        if (fe) framing_errors = framing_errors + 1;
                        if (pe) parity_errors  = parity_errors + 1;
                        if (!fe && !pe && rx_count < MAX_BYTES) begin
                            rx_queue[rx_count] = b;
                            rx_count = rx_count + 1;
                        end
                        rx_busy = 1'b0;
                    end
                join_none
            end
        end
    end

    // ---------------------------------------------------------------------
    // test-facing accessors
    // ---------------------------------------------------------------------
    function automatic int unsigned num_received();
        num_received = rx_count - rx_head;
    endfunction

    task automatic get_byte(output logic [7:0] value);
        while (rx_head >= rx_count) @(posedge rx_clk);
        value = rx_queue[rx_head];
        rx_head = rx_head + 1;
    endtask

    function automatic int unsigned num_framing_errors();
        num_framing_errors = framing_errors;
    endfunction

    function automatic int unsigned num_parity_errors();
        num_parity_errors = parity_errors;
    endfunction

    task automatic wait_tx_idle(input int unsigned cycles);
        repeat (cycles) @(posedge rx_clk);
    endtask

    // Echo the whole received stream into the log, so a failure can be
    // diagnosed from the log without opening a waveform.
    task automatic dump_received();
        $display("[uart_model] received %0d byte(s):", num_received());
        for (int i = rx_head; i < rx_count; i++) begin
            logic [7:0] ch;
            string     printable;
            ch        = rx_queue[i];
            printable = "";
            if (ch == 8'h0a)               printable = "\\n";
            else if (ch == 8'h0d)          printable = "\\r";
            else if (ch == 8'h09)          printable = "\\t";
            else if (ch >= 8'h20 && ch < 8'h7f) printable = ch;
            if (printable == "")
                $display("[uart_model]   [%0d] 0x%02h", i - rx_head, ch);
            else
                $display("[uart_model]   [%0d] 0x%02h '%s'", i - rx_head, ch, printable);
        end
        if (framing_errors || parity_errors) begin
            $display("[uart_model] framing errors: %0d, parity errors: %0d",
                     framing_errors, parity_errors);
        end
    endtask

endmodule

`default_nettype wire
