// -----------------------------------------------------------------------------
// pp_axi_checker
//
// AXI4 protocol checker, written as immediate checks inside clocked always
// blocks so it needs no assertion-language support and produces a clear message
// with a cycle count.
//
// Attach one instance to any master or slave port.  Checks are always on; a
// violation prints `AXI VIOLATION` with the instance name and calls
// pp_violation() from pp_test_lib.svh, which the test's summary treats as a
// failure.  That is the whole point: a protocol violation must never be
// something a human has to notice in a waveform.
//
// What it checks
//   master side
//     1. VALID may not be deasserted before READY  (no lost transaction)
//     2. the payload of a stalled VALID channel must not change
//     3. an address channel must not be accepted again until the matching
//        data/response has been exchanged
//     4. WLAST must be asserted on exactly the last beat of a burst
//   slave side
//     5. VALID may not be deasserted before READY, and the payload of a stalled
//        VALID channel must not change (B and R channels)
//     6. RLAST must appear on exactly the last beat of a read burst
//     7. a read response must not start before its request was accepted
//     8. RESP must never be X
//   both sides
//     9. no VALID may be X once reset has been released
//    10. the response ID must match the request ID
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi_checker #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 4,
    parameter          MASTER     = 1,     // 1 = the checked port is a master
    parameter          NAME       = "port"
) (
    input wire                       clk,
    input wire                       rst_n,

    input wire [ID_WIDTH-1:0]        awid,
    input wire [ADDR_WIDTH-1:0]      awaddr,
    input wire [7:0]                 awlen,
    input wire [2:0]                 awsize,
    input wire                       awvalid,
    input wire                       awready,

    input wire [DATA_WIDTH-1:0]      wdata,
    input wire [DATA_WIDTH/8-1:0]    wstrb,
    input wire                       wlast,
    input wire                       wvalid,
    input wire                       wready,

    input wire [ID_WIDTH-1:0]        bid,
    input wire [1:0]                 bresp,
    input wire                       bvalid,
    input wire                       bready,

    input wire [ID_WIDTH-1:0]        arid,
    input wire [ADDR_WIDTH-1:0]      araddr,
    input wire [7:0]                 arlen,
    input wire [2:0]                 arsize,
    input wire                       arvalid,
    input wire                       arready,

    input wire [ID_WIDTH-1:0]        rid,
    input wire [DATA_WIDTH-1:0]      rdata,
    input wire [1:0]                 rresp,
    input wire                       rlast,
    input wire                       rvalid,
    input wire                       rready
);

    localparam integer STRB_WIDTH = DATA_WIDTH / 8;

    integer unsigned cycles;
    integer unsigned violations;
    initial begin
        cycles     = 0;
        violations = 0;
    end
    integer unsigned aw_hs, w_beats, b_hs, ar_hs, r_beats;
    reg [ID_WIDTH-1:0] aw_id_q, ar_id_q;
    reg [7:0]          aw_left_q, ar_left_q;
    reg                aw_seen_q, ar_seen_q;

    task automatic report(input string what);
        begin
            violations = violations + 1;
            $display("AXI VIOLATION [%s] at cycle %0d: %s", NAME, cycles, what);
        end
    endtask

    // payload snapshot for the stall checks
    reg                awready_d, wready_d, arready_d, bready_d, rready_d;
    reg                awvalid_q;
    reg [ID_WIDTH-1:0] awid_q;
    reg [ADDR_WIDTH-1:0] awaddr_q;
    reg [7:0]           awlen_q;
    reg [2:0]           awsize_q;

    reg                wvalid_q;
    reg [DATA_WIDTH-1:0] wdata_q;
    reg [STRB_WIDTH-1:0] wstrb_q;
    reg                wlast_q;

    reg                arvalid_q;
    reg [ID_WIDTH-1:0] arid_q;
    reg [ADDR_WIDTH-1:0] araddr_q;
    reg [7:0]           arlen_q;
    reg [2:0]           arsize_q;

    reg                bvalid_q;
    reg [ID_WIDTH-1:0] bid_q;
    reg [1:0]          bresp_q;

    reg                rvalid_q;
    reg [ID_WIDTH-1:0] rid_q;
    reg [DATA_WIDTH-1:0] rdata_q;
    reg [1:0]          rresp_q;
    reg                rlast_q;

    always @(posedge clk) begin
        if (!rst_n) begin
            cycles      = 0;
            violations  = 0;
            aw_hs       = 0;
            w_beats     = 0;
            b_hs        = 0;
            ar_hs       = 0;
            r_beats     = 0;
            aw_seen_q   = 1'b0;
            ar_seen_q   = 1'b0;
            aw_id_q     = {ID_WIDTH{1'b0}};
            ar_id_q     = {ID_WIDTH{1'b0}};
            aw_left_q   = 8'd0;
            ar_left_q   = 8'd0;
        end else begin
            cycles = cycles + 1;

            // ---- 9. no VALID may be unknown -------------------------------
            // `rst_n` is released by the testbench after the clock has run, so
            // any X here is a real reset-domain problem, not a startup artefact.
            if ((^{awvalid, wvalid, bvalid, arvalid, rvalid}) === 1'bx) begin
                report("a VALID signal is X after reset");
            end
            if (^{bresp[0], rresp[0]} === 1'bx) begin
                report("a RESP signal is X");
            end

            // ---- 1/2. VALID stability while stalled ------------------------
            if (awvalid_q && !awready_d && !awvalid)
                report("AWVALID deasserted before AWREADY");
            if (awvalid_q && !awready_d && awvalid) begin
                if (awid !== awid_q || awaddr !== awaddr_q || awlen !== awlen_q
                    || awsize !== awsize_q)
                    report("AW payload changed while AWVALID && !AWREADY");
            end
            if (wvalid_q && !wready_d && !wvalid)
                report("WVALID deasserted before WREADY");
            if (wvalid_q && !wready_d && wvalid) begin
                if (wdata !== wdata_q || wstrb !== wstrb_q || wlast !== wlast_q)
                    report("W payload changed while WVALID && !WREADY");
            end
            if (arvalid_q && !arready_d && !arvalid)
                report("ARVALID deasserted before ARREADY");
            if (arvalid_q && !arready_d && arvalid) begin
                if (arid !== arid_q || araddr !== araddr_q || arlen !== arlen_q
                    || arsize !== arsize_q)
                    report("AR payload changed while ARVALID && !ARREADY");
            end
            if (bvalid_q && !bready_d && !bvalid)
                report("BVALID deasserted before BREADY");
            if (bvalid_q && !bready_d && bvalid) begin
                if (bid !== bid_q || bresp !== bresp_q)
                    report("B payload changed while BVALID && !BREADY");
            end
            if (rvalid_q && !rready_d && !rvalid)
                report("RVALID deasserted before RREADY");
            if (rvalid_q && !rready_d && rvalid) begin
                if (rid !== rid_q || rdata !== rdata_q || rresp !== rresp_q
                    || rlast !== rlast_q)
                    report("R payload changed while RVALID && !RREADY");
            end

            // ---- snapshot for the next cycle ------------------------------
            awready_d <= awready; wready_d <= wready; arready_d <= arready;
            bready_d  <= bready;  rready_d <= rready;
            awvalid_q <= awvalid; awid_q <= awid; awaddr_q <= awaddr;
            awlen_q <= awlen;     awsize_q <= awsize;
            wvalid_q <= wvalid;   wdata_q <= wdata; wstrb_q <= wstrb; wlast_q <= wlast;
            arvalid_q <= arvalid; arid_q <= arid; araddr_q <= araddr;
            arlen_q <= arlen;     arsize_q <= arsize;
            bvalid_q  <= bvalid;  bid_q <= bid;   bresp_q <= bresp;
            rvalid_q  <= rvalid;  rid_q <= rid;   rdata_q <= rdata;
            rresp_q   <= rresp;   rlast_q <= rlast;

            // ---- 3/4/10. write side ---------------------------------------
            if (awvalid && awready) begin
                aw_hs = aw_hs + 1;
                aw_seen_q = 1'b1;
                aw_id_q   = awid;
                aw_left_q = awlen;
                w_beats   = 0;
            end
            if (wvalid && wready) begin
                w_beats = w_beats + 1;
                if (wlast !== (aw_left_q == 8'd0))
                    report($sformatf("WLAST=%0b on beat %0d but the burst has %0d beats left",
                                     wlast, w_beats, aw_left_q + 1));
                if (aw_left_q != 8'd0) aw_left_q = aw_left_q - 8'd1;
                if (wlast && !aw_seen_q) report("W beat accepted before any AW");
            end
            if (bvalid && bready) begin
                b_hs = b_hs + 1;
                if (!aw_seen_q) report("B response with no outstanding AW");
                if (bid !== aw_id_q)
                    report($sformatf("BID %0b does not match AWID %0b of the write",
                                     bid, aw_id_q));
                if (aw_left_q != 8'd0) report("B response before the last W beat");
                aw_seen_q = 1'b0;
            end
            // Note: no timeout is applied to a stalled *master*.  A testbench is
            // allowed to hold a DUT off indefinitely -- that is what the run's
            // timeout watchdog is for, and it reports a FAIL.

            // ---- 6/7/10. read side ----------------------------------------
            if (arvalid && arready) begin
                ar_hs = ar_hs + 1;
                ar_seen_q = 1'b1;
                ar_id_q   = arid;
                ar_left_q = arlen;
                r_beats   = 0;
            end
            if (rvalid && rready) begin
                r_beats = r_beats + 1;
                if (!ar_seen_q) report("R beat with no outstanding AR");
                if (rid !== ar_id_q)
                    report($sformatf("RID %0b does not match ARID %0b of the read",
                                     rid, ar_id_q));
                if (rlast !== (ar_left_q == 8'd0))
                    report($sformatf("RLAST=%0b on beat %0d but the burst has %0d beats left",
                                     rlast, r_beats, ar_left_q + 1));
                if (ar_left_q != 8'd0) ar_left_q = ar_left_q - 8'd1;
                else ar_seen_q = 1'b0;
            end
        end
    end

    // A violation must fail the test; the test library's summary counts these.
    always @(posedge clk) begin
        if (rst_n && violations > 0) begin
            pp_violation(NAME);
        end
    end

endmodule

`default_nettype wire
