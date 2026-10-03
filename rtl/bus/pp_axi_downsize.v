// -----------------------------------------------------------------------------
// pp_axi_downsize
//
// AXI4 2:1 width adapter: DATA_WIDTH_IN on the master (wide) side,
// DATA_WIDTH_OUT on the slave (narrow) side, with DATA_WIDTH_IN == 2 *
// DATA_WIDTH_OUT.  One instance per VeeR core master (IFU, LSU, SB).
//
// What it does
//   * splits every wide beat into the output words it actually touches, taking
//     the byte lanes from WSTRB, so byte / halfword / word / doubleword accesses
//     at every legal alignment all reach the narrow slave correctly;
//   * maps one input burst onto exactly one output burst.  AXI requires all
//     beats of a burst to share AWSIZE, so within an aligned burst the lane
//     pattern repeats identically and the output beat count is known at address
//     time -- which is what makes a single output burst possible at all;
//   * merges the output read words back into one wide word, putting each word
//     back in the lanes it came from, and returns the *worse* of the responses
//     (DECERR > SLVERR > EXOKAY > OKAY), so an error on only one half is not
//     swallowed;
//   * preserves AXIID and all sideband signals.
//
// Restriction -- reported loudly, never silently mis-handled
//   A burst of *narrow* beats (ARSIZE/AWSIZE < log2(DATA_WIDTH_OUT)) cannot be
//   packed into one narrow burst: consecutive wide beats are DATA_WIDTH_IN
//   apart, not DATA_WIDTH_OUT, so a single output burst would break AXI's
//   "each beat advances the address by the beat size" rule.  VeeR never issues
//   one -- its IFU refills with full doublewords, and its LSU and store buffer
//   issue single beats -- so this adapter reports a $error instead of quietly
//   producing wrong bus behaviour.  See docs/width_adapters/.
//
// Outstanding transactions
//   Exactly one transaction is in flight.  The adapter back-pressures; it never
//   re-orders.  That is AXI-legal, and recorded as a throughput note in
//   docs/width_adapters/.
//
// Reset: active-low, asynchronous assert, synchronous release (project-wide).
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi_downsize #(
    parameter integer ADDR_WIDTH   = 32,
    parameter integer DATA_WIDTH_IN  = 64,
    parameter integer DATA_WIDTH_OUT = 32,
    parameter integer ID_WIDTH     = 4,
    // Bytes per output word divided by RATIO.  Only RATIO == 2 is implemented.
    parameter integer RATIO        = 2
) (
    input  wire                            clk,
    input  wire                            rst_n,

    // ---------------- wide (master) side ----------------
    input  wire [ID_WIDTH-1:0]             s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]           s_axi_awaddr,
    input  wire [7:0]                      s_axi_awlen,
    input  wire [2:0]                      s_axi_awsize,
    input  wire [1:0]                      s_axi_awburst,
    input  wire                            s_axi_awlock,
    input  wire [2:0]                      s_axi_awprot,
    input  wire                            s_axi_awvalid,
    output wire                            s_axi_awready,

    input  wire [DATA_WIDTH_IN-1:0]        s_axi_wdata,
    input  wire [DATA_WIDTH_IN/8-1:0]      s_axi_wstrb,
    input  wire                            s_axi_wlast,
    input  wire                            s_axi_wvalid,
    output wire                            s_axi_wready,

    output wire [ID_WIDTH-1:0]             s_axi_bid,
    output wire [1:0]                      s_axi_bresp,
    output wire                            s_axi_bvalid,
    input  wire                            s_axi_bready,

    input  wire [ID_WIDTH-1:0]             s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]           s_axi_araddr,
    input  wire [7:0]                      s_axi_arlen,
    input  wire [2:0]                      s_axi_arsize,
    input  wire [1:0]                      s_axi_arburst,
    input  wire                            s_axi_arlock,
    input  wire [2:0]                      s_axi_arprot,
    input  wire                            s_axi_arvalid,
    output wire                            s_axi_arready,

    output wire [ID_WIDTH-1:0]             s_axi_rid,
    output wire [DATA_WIDTH_IN-1:0]        s_axi_rdata,
    output wire [1:0]                      s_axi_rresp,
    output wire                            s_axi_rlast,
    output wire                            s_axi_rvalid,
    input  wire                            s_axi_rready,

    // ---------------- narrow (slave) side ----------------
    output wire [ID_WIDTH-1:0]             m_axi_awid,
    output wire [ADDR_WIDTH-1:0]           m_axi_awaddr,
    output wire [7:0]                      m_axi_awlen,
    output wire [2:0]                      m_axi_awsize,
    output wire [1:0]                      m_axi_awburst,
    output wire                            m_axi_awlock,
    output wire [2:0]                      m_axi_awprot,
    output wire                            m_axi_awvalid,
    input  wire                            m_axi_awready,

    output wire [DATA_WIDTH_OUT-1:0]       m_axi_wdata,
    output wire [DATA_WIDTH_OUT/8-1:0]     m_axi_wstrb,
    output wire                            m_axi_wlast,
    output wire                            m_axi_wvalid,
    input  wire                            m_axi_wready,

    input  wire [ID_WIDTH-1:0]             m_axi_bid,
    input  wire [1:0]                      m_axi_bresp,
    input  wire                            m_axi_bvalid,
    output wire                            m_axi_bready,

    output wire [ID_WIDTH-1:0]             m_axi_arid,
    output wire [ADDR_WIDTH-1:0]           m_axi_araddr,
    output wire [7:0]                      m_axi_arlen,
    output wire [2:0]                      m_axi_arsize,
    output wire [1:0]                      m_axi_arburst,
    output wire                            m_axi_arlock,
    output wire [2:0]                      m_axi_arprot,
    output wire                            m_axi_arvalid,
    input  wire                            m_axi_arready,

    input  wire [ID_WIDTH-1:0]             m_axi_rid,
    input  wire [DATA_WIDTH_OUT-1:0]       m_axi_rdata,
    input  wire [1:0]                      m_axi_rresp,
    input  wire                            m_axi_rlast,
    input  wire                            m_axi_rvalid,
    output wire                            m_axi_rready
);

    // AXI response severity: OKAY(00) < EXOKAY(01) < SLVERR(10) < DECERR(11)
    function automatic [1:0] worse(input [1:0] a, input [1:0] b);
        begin
            worse = (b[1] && !a[1]) ? b
                  : ((a[1] && !b[1]) ? a
                  : ((|b) && !(|a)) ? b : a);
        end
    endfunction

    // ---------------------------------------------------------------------
    localparam integer IN_STRB     = DATA_WIDTH_IN / 8;
    localparam integer OUT_STRB    = DATA_WIDTH_OUT / 8;
    localparam integer OUT_BYTES   = DATA_WIDTH_OUT / 8;      // 4
    localparam integer WORD_BITS   = 1;                       // log2(RATIO)
    localparam [2:0]    SIZE_WIDE   = 3'd3;                   // log2(DATA_WIDTH_IN)
    localparam [2:0]    SIZE_NARROW = $clog2(DATA_WIDTH_OUT); // == 2 for 32-bit
    // byte offset of output word `w` inside one wide beat
    localparam integer WORD_OFF    = OUT_BYTES;

    initial begin
        if (DATA_WIDTH_IN != RATIO * DATA_WIDTH_OUT) begin
            $error("pp_axi_downsize: DATA_WIDTH_IN (%0d) must equal RATIO (%0d) * DATA_WIDTH_OUT (%0d)",
                   DATA_WIDTH_IN, RATIO, DATA_WIDTH_OUT);
            $finish;
        end
        if (RATIO != 2) begin
            $error("pp_axi_downsize: only RATIO == 2 is implemented, got %0d", RATIO);
            $finish;
        end
    end

    // =====================================================================
    // Address decode
    // =====================================================================
    // A wide (doubleword) beat covers both output words.  A narrower beat
    // touches exactly one output word, selected by address bit 2.
    wire w_wide = (s_axi_awsize == SIZE_WIDE);
    wire r_wide = (s_axi_arsize == SIZE_WIDE);

    wire [WORD_BITS-1:0] w_word0 = s_axi_awaddr[2];
    wire [WORD_BITS-1:0] r_word0 = s_axi_araddr[2];

    // output beats per whole burst, known when the address is accepted
    wire [8:0] aw_out_beats = w_wide ? (({1'b0, s_axi_awlen} + 9'd1) << WORD_BITS)
                                     : ({1'b0, s_axi_awlen} + 9'd1);
    wire [8:0] ar_out_beats = r_wide ? (({1'b0, s_axi_arlen} + 9'd1) << WORD_BITS)
                                     : ({1'b0, s_axi_arlen} + 9'd1);

    // =====================================================================
    // Unsupported-burst guard
    // =====================================================================
    wire narrow_burst = ((s_axi_awlen != 8'd0) && (s_axi_awsize < SIZE_NARROW)) ||
                        ((s_axi_arlen != 8'd0) && (s_axi_arsize < SIZE_NARROW));
    always @(posedge clk) begin
        if (rst_n && narrow_burst) begin
            $error("pp_axi_downsize: narrow multi-beat burst is not supported (awsize=%0d awlen=%0d arsize=%0d arlen=%0d).  Splitting it into several narrow bursts is forbidden by AXI.  VeeR EL2 is not expected to issue this; see docs/width_adapters/.",
                   s_axi_awsize, s_axi_awlen, s_axi_arsize, s_axi_arlen);
        end
    end

    // =====================================================================
    // Write path
    // =====================================================================
    localparam [2:0] W_IDLE = 3'd0, W_AW = 3'd1, W_DATA = 3'd2, W_RESP = 3'd3;

    reg [2:0]           w_state;
    reg [ID_WIDTH-1:0]  w_id;
    reg [ADDR_WIDTH-1:0] w_addr;
    reg [7:0]           w_burst;
    reg                 w_lock;
    reg [2:0]           w_prot;
    reg [8:0]           w_left;      // output beats still to send
    reg [WORD_BITS-1:0] w_word;      // word index of the beat being emitted
    reg [1:0]           w_sub;       // 0 = lower output word, 1 = upper
    reg                 w_wide_q;    // latched copy of the wide/narrow decision

    // wide-side write-data FIFO: AXI4 lets W precede AW, so beats must be able
    // to wait.  Also absorbs a whole burst arriving before the AW is forwarded.
    localparam integer WF_DEPTH = 8;
    localparam integer WF_AW    = 3;
    reg [DATA_WIDTH_IN-1:0] wq_data [0:WF_DEPTH-1];
    reg [IN_STRB-1:0]      wq_strb [0:WF_DEPTH-1];
    reg                   wq_last [0:WF_DEPTH-1];
    reg [WF_AW:0]          wq_count;
    reg [WF_AW:0]          wq_rd;
    reg [WF_AW:0]          wq_wr;

    wire wq_push = s_axi_wvalid && s_axi_wready;
    wire wq_full  = (wq_count == (WF_DEPTH[WF_AW:0]));
    wire wq_empty = (wq_count == '0);

    assign s_axi_wready = ~wq_full;

    wire [DATA_WIDTH_IN-1:0] wq_head_data = wq_data[wq_rd[WF_AW-1:0]];
    wire [IN_STRB-1:0]      wq_head_strb = wq_strb[wq_rd[WF_AW-1:0]];
    wire                    wq_head_last = wq_last[wq_rd[WF_AW-1:0]];

    // slice the current output word out of the wide beat.  w_word starts at the
    // latched word0 and only toggles for wide beats, so it already names the
    // right output word in both cases.
    wire [WORD_BITS-1:0]    w_cur_word = w_word;
    // NOTE: the slice offset is in *bits*, so it steps by DATA_WIDTH_OUT.  Storing
    // the byte count here and using it as a bit offset silently mis-selects the
    // second half of a wide beat.
    wire [DATA_WIDTH_OUT-1:0] w_cur_data = wq_head_data[(w_cur_word * DATA_WIDTH_OUT) +: DATA_WIDTH_OUT];
    wire [OUT_STRB-1:0]      w_cur_strb = wq_head_strb[(w_cur_word * OUT_STRB)  +: OUT_STRB];
    wire                     w_cur_last = wq_head_last && (w_left == 9'd1);

    // A wide beat produces RATIO narrow beats and *both* come out of the same FIFO
    // entry, so the entry is popped when its last narrow beat is accepted -- not
    // when the first one is.  A narrow beat produces one output beat, which is its
    // own last.  Popping on a bare WREADY from the slave would drain an empty
    // FIFO, which is why both conditions are here.
    wire w_out_last_sub = w_wide_q ? (w_sub == 2'd1) : 1'b1;
    wire wq_pop = (w_state == W_DATA) && !wq_empty && m_axi_wvalid && m_axi_wready
                  && w_out_last_sub;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wq_count <= '0;
            wq_rd    <= '0;
            wq_wr    <= '0;
        end else begin
            if (wq_push) begin
                wq_data[wq_wr[WF_AW-1:0]] <= s_axi_wdata;
                wq_strb[wq_wr[WF_AW-1:0]] <= s_axi_wstrb;
                wq_last[wq_wr[WF_AW-1:0]] <= s_axi_wlast;
                wq_wr    <= wq_wr + 1'b1;
            end
            if (wq_pop) wq_rd <= wq_rd + 1'b1;
            case ({wq_push, wq_pop})
                2'b10:   wq_count <= wq_count + 1'b1;
                2'b01:   wq_count <= wq_count - 1'b1;
                default: wq_count <= wq_count;
            endcase
        end
    end


    assign s_axi_awready = (w_state == W_IDLE);
    assign s_axi_arready = (w_state == W_IDLE);

    assign m_axi_awid    = w_id;
    assign m_axi_awaddr  = w_addr;
    assign m_axi_awlen   = w_left[8:0] - 9'd1;
    assign m_axi_awsize  = SIZE_NARROW;
    assign m_axi_awburst = w_burst;
    assign m_axi_awlock  = w_lock;
    assign m_axi_awprot  = w_prot;
    assign m_axi_awvalid = (w_state == W_AW);

    assign m_axi_wdata   = w_cur_data;
    assign m_axi_wstrb   = w_cur_strb;
    assign m_axi_wlast   = w_cur_last;
    assign m_axi_wvalid  = (w_state == W_DATA) && !wq_empty;
    assign m_axi_bready  = (w_state == W_RESP);

    assign s_axi_bid    = w_id;
    assign s_axi_bresp  = m_axi_bresp;
    assign s_axi_bvalid = (w_state == W_RESP) && m_axi_bvalid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state  <= W_IDLE;
            w_id     <= {ID_WIDTH{1'b0}};
            w_addr   <= {ADDR_WIDTH{1'b0}};
            w_burst  <= 2'b10;
            w_lock   <= 1'b0;
            w_prot   <= 3'b000;
            w_left   <= 9'd0;
            w_word   <= {WORD_BITS{1'b0}};
            w_sub    <= 2'd0;
            w_wide_q <= 1'b0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        w_id     <= s_axi_awid;
                        // align down to the output word that is actually used
                        w_addr   <= {s_axi_awaddr[ADDR_WIDTH-1:3],
                                     s_axi_awaddr[2], 2'b00};
                        w_burst  <= s_axi_awburst;
                        w_lock   <= s_axi_awlock;
                        w_prot   <= s_axi_awprot;
                        w_left   <= aw_out_beats;
                        w_word   <= s_axi_awaddr[2];
                        w_wide_q <= w_wide;
                        w_state  <= W_AW;
                    end
                end
                W_AW: begin
                    if (m_axi_awready) w_state <= W_DATA;
                end
                W_DATA: begin
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (w_cur_last) begin
                            w_state <= W_RESP;
                        end else begin
                            w_left <= w_left - 9'd1;
                            if (w_out_last_sub) begin
                                // moving on to the next *wide* beat.  The next wide
                                // beat of a linear burst starts at a fresh aligned
                                // address, so word0 is word 0 again.
                                w_word <= {WORD_BITS{1'b0}};
                            end else begin
                                // second half of the current wide beat
                                w_word <= ~w_word;
                                w_addr <= w_addr + (32'd1 << SIZE_NARROW);
                            end
                        end
                    end
                end
                W_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) w_state <= W_IDLE;
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // =====================================================================
    // Read path
    // =====================================================================
    localparam [2:0] R_IDLE = 3'd0, R_AR = 3'd1, R_DATA = 3'd2, R_RESP = 3'd3;

    reg [2:0]           r_state;
    reg [ID_WIDTH-1:0]  r_id;
    reg [ADDR_WIDTH-1:0] r_addr;
    reg [7:0]           r_burst;
    reg                 r_lock;
    reg [2:0]           r_prot;
    reg [8:0]           r_left;
    reg [WORD_BITS-1:0] r_word;
    reg                 r_wide_q;

    reg [DATA_WIDTH_IN-1:0] r_acc;      // merged wide read data
    reg [1:0]              r_worst;    // worse response seen so far
    reg                    r_done;     // wide-side response is ready

    // Byte mask of the output word currently being fetched, expanded to the wide
    // bus.  Word 0 occupies the *low* lanes and word 1 the *high* lanes, so the
    // mask is all-ones for word 0 and the top DATA_WIDTH_OUT bits for word 1.
    // (Written out rather than shifted: a left shift of an all-ones word would
    // overflow and select nothing.)
    wire [DATA_WIDTH_IN-1:0] r_cur_mask = (r_word == {WORD_BITS{1'b0}})
        ? {DATA_WIDTH_IN{1'b1}}
        : {{(DATA_WIDTH_IN - DATA_WIDTH_OUT){1'b0}}, {DATA_WIDTH_OUT{1'b1}}};
    wire [DATA_WIDTH_IN-1:0] r_acc_base = (r_word == {WORD_BITS{1'b0}})
                                         ? {DATA_WIDTH_IN{1'b0}} : r_acc;

    assign m_axi_arid    = r_id;
    assign m_axi_araddr  = r_addr;
    assign m_axi_arlen   = r_left[8:0] - 9'd1;
    assign m_axi_arsize  = SIZE_NARROW;
    assign m_axi_arburst = r_burst;
    assign m_axi_arlock  = r_lock;
    assign m_axi_arprot  = r_prot;
    assign m_axi_arvalid = (r_state == R_AR);

    assign m_axi_rready  = (r_state == R_DATA);

    assign s_axi_rid    = r_id;
    assign s_axi_rdata  = r_acc;
    assign s_axi_rresp  = r_worst;
    assign s_axi_rlast  = 1'b1;                // one wide beat per wide read
    assign s_axi_rvalid = r_done;
    assign s_axi_rready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state  <= R_IDLE;
            r_id     <= {ID_WIDTH{1'b0}};
            r_addr   <= {ADDR_WIDTH{1'b0}};
            r_burst  <= 2'b10;
            r_lock   <= 1'b0;
            r_prot   <= 3'b000;
            r_left   <= 9'd0;
            r_word   <= {WORD_BITS{1'b0}};
            r_wide_q <= 1'b0;
            r_acc    <= {DATA_WIDTH_IN{1'b0}};
            r_worst  <= 2'b00;
            r_done   <= 1'b0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        r_id     <= s_axi_arid;
                        r_addr   <= {s_axi_araddr[ADDR_WIDTH-1:3],
                                     s_axi_araddr[2], 2'b00};
                        r_burst  <= s_axi_arburst;
                        r_lock   <= s_axi_arlock;
                        r_prot   <= s_axi_arprot;
                        r_left   <= ar_out_beats;
                        r_word   <= s_axi_araddr[2];
                        r_wide_q <= r_wide;
                        r_acc    <= {DATA_WIDTH_IN{1'b0}};
                        r_worst  <= 2'b00;
                        r_done   <= 1'b0;
                        r_state  <= R_AR;
                    end
                end
                R_AR: begin
                    if (m_axi_arready) r_state <= R_DATA;
                end
                R_DATA: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        r_acc <= (r_acc_base & ~r_cur_mask)
                               | ({{(DATA_WIDTH_IN-DATA_WIDTH_OUT){1'b0}},
                                   m_axi_rdata} & r_cur_mask);
                        r_worst <= worse(r_worst, m_axi_rresp);
                        if (m_axi_rlast) begin
                            r_done <= 1'b1;
                        end else begin
                            r_left <= r_left - 9'd1;
                            r_word <= r_wide_q ? ~r_word : r_word;
                        end
                    end
                end
                R_RESP: begin
                    if (s_axi_rready) begin
                        r_done  <= 1'b0;
                        r_state <= R_IDLE;
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
