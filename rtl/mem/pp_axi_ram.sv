// -----------------------------------------------------------------------------
// pp_axi_ram
//
// Parameterised AXI4 memory slave, 32-bit, byte-addressed, initialised from a
// hex file.  Two instances make up the SoC's memory system: instruction memory
// and data memory (both declared in config/soc_config.yaml).
//
// Contents come from a hex file whose word width is `HEX_WORD_BYTES` from the
// config (4), i.e. one hex word per bus word.  The path is taken from, in order
// of precedence:
//   1. the `+hex=<path>` plusarg (so `make hex T=... HEX=...` works), then
//   2. the HEX_FILE parameter (so a test can bake in its own image).
//
// Access rules
//   * INCR bursts of any length are supported on both channels.
//   * Narrow accesses are handled through WSTRB on writes; reads return the
//     whole aligned bus word, which is what the width adapter in front expects.
//   * WRITEs are accepted and BRESP is produced after the final W beat, as AXI
//     requires.  Reads are answered with RDATA = 0 and RRESP = OKAY.
//
// Reset: active-low, asynchronous assert, synchronous release (project-wide).
// The memory contents are *not* cleared by reset -- they are the program image.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi_ram #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer ID_WIDTH   = 4,
    // Number of DATA_WIDTH words.  Must be a power of two and match the slot
    // size in config (the map checker enforces the slot; this is the RTL side).
    parameter integer DEPTH      = 65536,
    parameter [1023:0] HEX_FILE  = "",
    // Optional name reported in the log, purely for readability.
    parameter [255:0]  NAME       = "ram"
) (
    input  wire                         clk,
    input  wire                         rst_n,

    input  wire [ID_WIDTH-1:0]          s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire [7:0]                   s_axi_awlen,
    input  wire [2:0]                   s_axi_awsize,
    input  wire [1:0]                   s_axi_awburst,
    input  wire                         s_axi_awlock,
    input  wire [2:0]                   s_axi_awprot,
    input  wire                         s_axi_awvalid,
    output wire                         s_axi_awready,

    input  wire [DATA_WIDTH-1:0]        s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]        s_axi_wstrb,
    input  wire                         s_axi_wlast,
    input  wire                         s_axi_wvalid,
    output wire                         s_axi_wready,

    output wire [ID_WIDTH-1:0]          s_axi_bid,
    output wire [1:0]                   s_axi_bresp,
    output wire                         s_axi_bvalid,
    input  wire                         s_axi_bready,

    input  wire [ID_WIDTH-1:0]          s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]        s_axi_araddr,
    input  wire [7:0]                   s_axi_arlen,
    input  wire [2:0]                   s_axi_arsize,
    input  wire [1:0]                   s_axi_arburst,
    input  wire                         s_axi_arlock,
    input  wire [2:0]                   s_axi_arprot,
    input  wire                         s_axi_arvalid,
    output wire                         s_axi_arready,

    output wire [ID_WIDTH-1:0]          s_axi_rid,
    output wire [DATA_WIDTH-1:0]        s_axi_rdata,
    output wire [1:0]                   s_axi_rresp,
    output wire                         s_axi_rlast,
    output wire                         s_axi_rvalid,
    input  wire                         s_axi_rready
);

    localparam [1:0] RESP_OKAY   = 2'b00;
    localparam [1:0] RESP_SLVERR = 2'b10;

    localparam integer WORD_BITS  = $clog2(DEPTH);
    localparam integer ADDR_LSB   = $clog2(STRB_WIDTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    initial begin
        if ((DEPTH & (DEPTH - 1)) != 0) begin
            $error("pp_axi_ram: DEPTH (%0d) must be a power of two", DEPTH);
            $finish;
        end
    end

    // ------------------------------------------------------------------
    // hex image
    // ------------------------------------------------------------------
    reg [1023:0] hexfile;
    reg          hex_loaded;
    integer      i;
    initial begin
        hexfile    = HEX_FILE;
        hex_loaded = 1'b0;
        if ($value$plusargs("hex=%s", hexfile)) begin
            hex_loaded = 1'b1;
        end else if (HEX_FILE != 0) begin
            hex_loaded = 1'b1;
        end
        if (hex_loaded) begin
            $readmemh(hexfile, mem);
            $display("[%0s] pp_axi_ram: loaded %0s into %0d words (%0d bytes)",
                     NAME, hexfile, DEPTH, DEPTH * (DATA_WIDTH / 8));
        end else begin
            // Deterministic contents matter more than speed here: an uninitialised
            // array would read back as X, and a test could not tell a real bug from
            // a memory that was never written.  Real images always come from a hex
            // file, so this loop runs only for the "no image" case.
            for (i = 0; i < DEPTH; i = i + 1) mem[i] = {DATA_WIDTH{1'b0}};
            $display("[%0s] pp_axi_ram: no hex image (all zeros), %0d words (%0d bytes)",
                     NAME, DEPTH, DEPTH * (DATA_WIDTH / 8));
        end
    end

    // ------------------------------------------------------------------
    // write channel
    // ------------------------------------------------------------------
    reg                 w_pending;
    reg [ID_WIDTH-1:0]  w_id;
    reg [ADDR_WIDTH-1:0] w_addr;
    reg                 r_pending;
    reg [ID_WIDTH-1:0]  r_id;
    reg [ADDR_WIDTH-1:0] r_addr;
    reg [8:0]            r_left;

    // write strobe, expanded to the full data width for the read-modify-write
    reg [DATA_WIDTH-1:0] wstrb_expanded;
    integer k;
    always @(*) begin
        wstrb_expanded = {DATA_WIDTH{1'b0}};
        for (k = 0; k < STRB_WIDTH; k = k + 1) begin
            if (s_axi_wstrb[k]) wstrb_expanded[k*8 +: 8] = 8'hff;
        end
    end

    wire [WORD_BITS-1:0] w_index = w_addr[ADDR_LSB +: WORD_BITS];
    wire [WORD_BITS-1:0] r_index = r_addr[ADDR_LSB +: WORD_BITS];

    // BRESP is sticky: it is raised when the last W beat is accepted and stays
    // up until the write response is actually taken.  Gating it on WVALID instead
    // would drop the response as soon as the master released WVALID, which
    // deadlocks any slave whose interconnect registers the beat one cycle later.
    reg w_rsp_valid;

    assign s_axi_awready = ~w_pending;
    assign s_axi_wready  = w_pending;

    assign s_axi_bid     = w_id;
    assign s_axi_bresp   = RESP_OKAY;
    assign s_axi_bvalid  = w_rsp_valid;

    wire w_last_beat = w_pending && s_axi_wvalid && s_axi_wready && s_axi_wlast;
    wire w_accept    = ~w_pending && s_axi_awvalid && s_axi_awready;
    wire w_done      = w_rsp_valid && s_axi_bready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_pending   <= 1'b0;
            w_rsp_valid <= 1'b0;
            w_id        <= {ID_WIDTH{1'b0}};
            w_addr      <= {ADDR_WIDTH{1'b0}};
        end else begin
            if (w_accept) begin
                w_pending <= 1'b1;
                w_id      <= s_axi_awid;
                w_addr    <= s_axi_awaddr;
            end
            // Store every accepted beat.  This is deliberately *not* gated on the
            // response state: a slave may assert BRESP in the very same cycle as
            // the last W beat, and the store must still happen.
            if (w_pending && s_axi_wvalid && s_axi_wready) begin
                mem[w_index] <= (mem[w_index] & ~wstrb_expanded)
                              | (s_axi_wdata & wstrb_expanded);
                // The narrow bus is DATA_WIDTH bits wide, so consecutive beats are
                // always ADDR_LSB bytes apart -- independent of the burst's AW size.
                if (!s_axi_wlast) w_addr <= w_addr + (32'd1 << ADDR_LSB);
            end
            if (w_last_beat) w_rsp_valid <= 1'b1;
            if (w_done) begin
                w_rsp_valid <= 1'b0;
                w_pending   <= 1'b0;
            end
        end
    end

    // ------------------------------------------------------------------
    // read channel
    // ------------------------------------------------------------------
    // RRESP/RLAST are sticky for the same reason BRESP is: the beat being
    // presented must not vanish because the master released ARVALID.
    reg r_rsp_valid;

    assign s_axi_arready = ~r_pending;
    assign s_axi_rid     = r_id;
    assign s_axi_rdata   = mem[r_index];
    assign s_axi_rresp   = RESP_OKAY;
    assign s_axi_rlast   = (r_left == 9'd1);
    assign s_axi_rvalid  = r_rsp_valid;

    wire r_accept = ~r_pending && s_axi_arvalid && s_axi_arready;
    wire r_beat   = r_rsp_valid && s_axi_rready;
    wire r_done   = r_beat && s_axi_rlast;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_pending   <= 1'b0;
            r_rsp_valid <= 1'b0;
            r_id        <= {ID_WIDTH{1'b0}};
            r_addr      <= {ADDR_WIDTH{1'b0}};
            r_left      <= 9'd0;
        end else begin
            if (r_accept) begin
                r_pending   <= 1'b1;
                r_rsp_valid <= 1'b1;
                r_id        <= s_axi_arid;
                r_addr      <= s_axi_araddr;
                r_left      <= {1'b0, s_axi_arlen} + 9'd1;
            end else if (r_beat) begin
                if (s_axi_rlast) begin
                    r_rsp_valid <= 1'b0;
                    r_pending   <= 1'b0;
                end else begin
                    r_left <= r_left - 9'd1;
                    r_addr <= r_addr + (32'd1 << ADDR_LSB);
                end
            end
        end
    end

    // Unused sideband, kept so the interface stays complete and lintable.
    wire _unused_ok = &{1'b0, s_axi_awburst, s_axi_awlock, s_axi_awprot,
                        s_axi_arburst, s_axi_arlock, s_axi_arprot,
                        RESP_SLVERR[0]};

endmodule

`default_nettype wire
