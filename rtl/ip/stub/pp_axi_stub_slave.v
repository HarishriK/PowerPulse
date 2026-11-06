// -----------------------------------------------------------------------------
// pp_axi_stub_slave
//
// Decode-error / tie-off AXI4 slave.
//
// Used in two places, both created by the interconnect generator or the SoC top
// from config/soc_config.yaml:
//   * for every slot that is `enabled: false` (a reserved Phase 2 slot), and
//   * as the interconnect's *default* slave, so an unmapped address returns
//     DECERR with correct handshakes instead of hanging the bus.
//
// Behaviour (see docs/interconnect_generator/, "Error behaviour"):
//   * AWREADY / WREADY / ARREADY are permanently asserted, so a master never
//     stalls and never deadlocks on a reserved or unmapped slot.
//   * A write response (BID/BRESP = DECERR) is presented only after the final
//     write-data beat (WLAST) has been accepted, as AXI requires.
//   * A read burst is answered beat-for-beat (RLAST on the last one) with
//     RDATA = 0 and RRESP = DECERR.
//   * An AXI4-Lite master (which never bursts) is handled by the same logic,
//     because AWLEN/ARLEN are then always 0.
//
// Reset: active-low, asynchronous assert, synchronous release (project-wide
// convention, see docs/config/conventions.md).
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi_stub_slave #(
    parameter ADDR_WIDTH   = 32,
    parameter DATA_WIDTH   = 32,
    parameter STRB_WIDTH   = DATA_WIDTH / 8,
    parameter ID_WIDTH     = 4
) (
    input  wire                    clk,
    input  wire                    rst_n,

    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire [7:0]              s_axi_awlen,
    input  wire [2:0]              s_axi_awsize,
    input  wire [1:0]              s_axi_awburst,
    input  wire                    s_axi_awlock,
    input  wire [2:0]              s_axi_awprot,
    input  wire                    s_axi_awvalid,
    output wire                    s_axi_awready,

    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]   s_axi_wstrb,
    input  wire                    s_axi_wlast,
    input  wire                    s_axi_wvalid,
    output wire                    s_axi_wready,

    output wire [ID_WIDTH-1:0]     s_axi_bid,
    output wire [1:0]              s_axi_bresp,
    output wire                    s_axi_bvalid,
    input  wire                    s_axi_bready,

    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire [7:0]              s_axi_arlen,
    input  wire [2:0]              s_axi_arsize,
    input  wire [1:0]              s_axi_arburst,
    input  wire                    s_axi_arlock,
    input  wire [2:0]              s_axi_arprot,
    input  wire                    s_axi_arvalid,
    output wire                    s_axi_arready,

    output wire [ID_WIDTH-1:0]     s_axi_rid,
    output wire [DATA_WIDTH-1:0]   s_axi_rdata,
    output wire [1:0]              s_axi_rresp,
    output wire                    s_axi_rlast,
    output wire                    s_axi_rvalid,
    input  wire                    s_axi_rready
);

localparam [1:0] RESP_DECERR = 2'b11;

// write side ---------------------------------------------------------------
reg                 w_pending;      // an AW has been accepted, W not finished
reg [ID_WIDTH-1:0]  w_id;
reg                 w_resp;         // present the write response

// read side ----------------------------------------------------------------
reg                 r_pending;      // an AR has been accepted, R not finished
reg [ID_WIDTH-1:0]  r_id;
reg [8:0]           r_left;         // beats still to return

wire                w_beat_done = s_axi_wvalid && s_axi_wlast;
wire                r_beat_done = s_axi_rvalid && s_axi_rlast;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        w_pending <= 1'b0;
        w_id      <= {ID_WIDTH{1'b0}};
        w_resp    <= 1'b0;
        r_pending <= 1'b0;
        r_id      <= {ID_WIDTH{1'b0}};
        r_left    <= 9'd0;
    end else begin
        // ---------------- write ----------------
        if (s_axi_awvalid) begin
            w_id      <= s_axi_awid;
            w_pending <= 1'b1;
        end
        if (w_resp && s_axi_bready) begin
            w_resp    <= 1'b0;
            w_pending <= 1'b0;
        end else if (w_pending && w_beat_done) begin
            w_resp <= 1'b1;
        end

        // ---------------- read -----------------
        if (s_axi_arvalid) begin
            r_id      <= s_axi_arid;
            r_left    <= {1'b0, s_axi_arlen};
            r_pending <= 1'b1;
        end else if (r_pending && r_beat_done) begin
            r_pending <= 1'b0;
        end else if (r_pending && s_axi_rvalid && s_axi_rready) begin
            r_left <= r_left - 9'd1;
        end
    end
end

// Never stall the master.
assign s_axi_awready = 1'b1;
assign s_axi_wready  = 1'b1;
assign s_axi_arready = 1'b1;

assign s_axi_bid    = w_id;
assign s_axi_bresp  = RESP_DECERR;
assign s_axi_bvalid = w_resp;

assign s_axi_rid    = r_id;
assign s_axi_rdata  = {DATA_WIDTH{1'b0}};
assign s_axi_rresp  = RESP_DECERR;
assign s_axi_rlast  = (r_left == 9'd0);
assign s_axi_rvalid = r_pending;

// Unused, accepted only to keep the AXI interface complete.
wire _unused_ok = &{1'b0, s_axi_awaddr, s_axi_awsize, s_axi_awburst, s_axi_awlock,
                    s_axi_awprot, s_axi_wdata, s_axi_wstrb, s_axi_araddr, s_axi_arsize,
                    s_axi_arburst, s_axi_arlock, s_axi_arprot};

endmodule

`default_nettype wire
