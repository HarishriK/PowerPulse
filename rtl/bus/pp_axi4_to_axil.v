// -----------------------------------------------------------------------------
// pp_axi4_to_axil
//
// AXI4 -> AXI4-Lite protocol bridge.
//
// Instantiated in front of every slot whose config entry says
// `protocol: axil` (all peripherals, and the simulation status device).  It
// exists because the interconnect and the VeeR masters speak AXI4, while
// register-style slaves only implement AXI4-Lite.
//
// What it does
//   * converts each burst into a sequence of single-beat AXI4-Lite transfers --
//     one AW/W pair per beat -- which is exactly how AXI4-Lite is defined to be
//     driven (see PROJECT_CONTEXT.md section 7);
//   * splits the ID: the AXI4-Lite side is driven with ID 0, and the upstream
//     ID is latched and returned on the response, so a slave with a narrower ID
//     field than the interconnect (the vendored UART has a 12-bit field, the
//     interconnect 4) changes nothing upstream;
//   * keeps beats in order and carries AWLEN/ARLEN down to a counter, generating
//     the per-beat address (INCR) itself;
//   * single outstanding transaction, so no ID tracking is needed.
//
// Reset: active-low, asynchronous assert, synchronous release (project-wide).
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi4_to_axil #(
    parameter integer ADDR_WIDTH  = 32,
    parameter integer DATA_WIDTH  = 32,
    parameter integer STRB_WIDTH  = DATA_WIDTH / 8,
    parameter integer ID_WIDTH_M  = 4,   // upstream (interconnect side)
    parameter integer ID_WIDTH_S  = 12   // downstream (AXI4-Lite slave side)
) (
    input  wire                       clk,
    input  wire                       rst_n,

    // ---------------- upstream AXI4 ----------------
    input  wire [ID_WIDTH_M-1:0]      s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire [7:0]                 s_axi_awlen,
    input  wire [2:0]                 s_axi_awsize,
    input  wire [1:0]                 s_axi_awburst,
    input  wire                       s_axi_awlock,
    input  wire [2:0]                 s_axi_awprot,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,

    input  wire [DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]      s_axi_wstrb,
    input  wire                       s_axi_wlast,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,

    output wire [ID_WIDTH_M-1:0]      s_axi_bid,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready,

    input  wire [ID_WIDTH_M-1:0]      s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire [7:0]                 s_axi_arlen,
    input  wire [2:0]                 s_axi_arsize,
    input  wire [1:0]                 s_axi_arburst,
    input  wire                       s_axi_arlock,
    input  wire [2:0]                 s_axi_arprot,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,

    output wire [ID_WIDTH_M-1:0]      s_axi_rid,
    output wire [DATA_WIDTH-1:0]      s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rlast,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    // ---------------- downstream AXI4-Lite ----------------
    output wire [ID_WIDTH_S-1:0]      m_axi_awid,
    output wire [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output wire [7:0]                 m_axi_awlen,
    output wire [2:0]                 m_axi_awsize,
    output wire [1:0]                 m_axi_awburst,
    output wire                       m_axi_awlock,
    output wire [2:0]                 m_axi_awprot,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,

    output wire [DATA_WIDTH-1:0]      m_axi_wdata,
    output wire [STRB_WIDTH-1:0]      m_axi_wstrb,
    output wire                       m_axi_wlast,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,

    input  wire [ID_WIDTH_S-1:0]      m_axi_bid,
    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready,

    output wire [ID_WIDTH_S-1:0]      m_axi_arid,
    output wire [ADDR_WIDTH-1:0]      m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arlock,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,

    input  wire [ID_WIDTH_S-1:0]      m_axi_rid,
    input  wire [DATA_WIDTH-1:0]      m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready
);

    // =====================================================================
    // write: burst -> sequence of single AXI4-Lite transfers
    // =====================================================================
    localparam [2:0] W_IDLE = 3'd0, W_AW = 3'd1, W_W = 3'd2, W_B = 3'd3;

    reg [2:0]            w_state;
    reg [ID_WIDTH_M-1:0] w_id;
    reg [ADDR_WIDTH-1:0] w_beat_addr;
    reg [2:0]            w_size;
    reg [1:0]            w_burst;
    reg                  w_lock;
    reg [2:0]            w_prot;
    reg [8:0]            w_left;        // beats still to issue

    assign s_axi_awready = (w_state == W_IDLE);

    assign m_axi_awid    = {ID_WIDTH_S{1'b0}};
    assign m_axi_awaddr  = w_beat_addr;
    assign m_axi_awlen   = 8'd0;                       // AXI4-Lite: never a burst
    assign m_axi_awsize  = w_size;
    assign m_axi_awburst = 2'b10;                      // INCR
    assign m_axi_awlock  = w_lock;
    assign m_axi_awprot  = w_prot;
    assign m_axi_awvalid = (w_state == W_AW);

    assign m_axi_wdata   = s_axi_wdata;
    assign m_axi_wstrb   = s_axi_wstrb;
    assign m_axi_wlast   = 1'b1;                       // one beat per transfer
    assign m_axi_wvalid  = (w_state == W_W) && s_axi_wvalid;
    assign s_axi_wready  = m_axi_wready && (w_state == W_W);

    assign m_axi_bready  = (w_state == W_B);
    assign s_axi_bid     = w_id;
    assign s_axi_bresp   = m_axi_bresp;
    assign s_axi_bvalid  = (w_state == W_B) && m_axi_bvalid;

    wire [ADDR_WIDTH-1:0] w_next_addr = w_beat_addr + (32'd1 << w_size);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_state     <= W_IDLE;
            w_id        <= {ID_WIDTH_M{1'b0}};
            w_beat_addr <= {ADDR_WIDTH{1'b0}};
            w_size      <= 3'd0;
            w_burst     <= 2'b10;
            w_lock      <= 1'b0;
            w_prot      <= 3'b000;
            w_left      <= 9'd0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    if (s_axi_awvalid && s_axi_awready) begin
                        w_id        <= s_axi_awid;
                        w_beat_addr <= s_axi_awaddr;
                        w_size      <= s_axi_awsize;
                        w_burst     <= s_axi_awburst;
                        w_lock      <= s_axi_awlock;
                        w_prot      <= s_axi_awprot;
                        w_left      <= {1'b0, s_axi_awlen} + 9'd1;
                        w_state     <= W_AW;
                    end
                end
                W_AW: begin
                    if (m_axi_awready) w_state <= W_W;
                end
                W_W: begin
                    if (s_axi_wvalid && s_axi_wready) begin
                        if (w_left == 9'd1) begin
                            w_state <= W_B;
                        end else begin
                            w_left      <= w_left - 9'd1;
                            w_beat_addr <= w_next_addr;
                            w_state     <= W_AW;
                        end
                    end
                end
                W_B: begin
                    if (m_axi_bvalid && m_axi_bready) w_state <= W_IDLE;
                end
                default: w_state <= W_IDLE;
            endcase
        end
    end

    // =====================================================================
    // read: burst -> sequence of single AXI4-Lite transfers
    // =====================================================================
    localparam [2:0] R_IDLE = 3'd0, R_AR = 3'd1, R_R = 3'd2;

    reg [2:0]            r_state;
    reg [ID_WIDTH_M-1:0] r_id;
    reg [ADDR_WIDTH-1:0] r_beat_addr;
    reg [2:0]            r_size;
    reg [1:0]            r_burst;
    reg                  r_lock;
    reg [2:0]            r_prot;
    reg [8:0]            r_left;

    assign s_axi_arready = (r_state == R_IDLE);

    assign m_axi_arid    = {ID_WIDTH_S{1'b0}};
    assign m_axi_araddr  = r_beat_addr;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = r_size;
    assign m_axi_arburst = 2'b10;
    assign m_axi_arlock  = r_lock;
    assign m_axi_arprot  = r_prot;
    assign m_axi_arvalid = (r_state == R_AR);

    assign m_axi_rready  = (r_state == R_R);
    assign s_axi_rid     = r_id;
    assign s_axi_rdata   = m_axi_rdata;
    assign s_axi_rresp   = m_axi_rresp;
    assign s_axi_rvalid  = (r_state == R_R) && m_axi_rvalid;
    assign s_axi_rlast   = (r_state == R_R) && m_axi_rvalid && (r_left == 9'd1);

    wire [ADDR_WIDTH-1:0] r_next_addr = r_beat_addr + (32'd1 << r_size);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state     <= R_IDLE;
            r_id        <= {ID_WIDTH_M{1'b0}};
            r_beat_addr <= {ADDR_WIDTH{1'b0}};
            r_size      <= 3'd0;
            r_burst     <= 2'b10;
            r_lock      <= 1'b0;
            r_prot      <= 3'b000;
            r_left      <= 9'd0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    if (s_axi_arvalid && s_axi_arready) begin
                        r_id        <= s_axi_arid;
                        r_beat_addr <= s_axi_araddr;
                        r_size      <= s_axi_arsize;
                        r_burst     <= s_axi_arburst;
                        r_lock      <= s_axi_arlock;
                        r_prot      <= s_axi_arprot;
                        r_left      <= {1'b0, s_axi_arlen} + 9'd1;
                        r_state     <= R_AR;
                    end
                end
                R_AR: begin
                    if (m_axi_arready) r_state <= R_R;
                end
                R_R: begin
                    if (m_axi_rvalid && m_axi_rready) begin
                        if (r_left == 9'd1) begin
                            r_state <= R_IDLE;
                        end else begin
                            r_left      <= r_left - 9'd1;
                            r_beat_addr <= r_next_addr;
                            r_state     <= R_AR;
                        end
                    end
                end
                default: r_state <= R_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
