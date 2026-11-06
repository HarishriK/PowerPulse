// -----------------------------------------------------------------------------
// pp_hap.sv
//
// PowerPulse Hardware Activity Profiler (HAP)
// Monitors peripheral activity, tracks inactivity intervals, and raises
// autonomous idle indications to PPMC when thresholds are reached.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_hap #(
    parameter integer NUM_PERIPHS = 3,
    parameter integer ADDR_WIDTH  = 5,
    parameter integer DATA_WIDTH  = 32,
    parameter integer ID_WIDTH    = 12
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Inter-IP Activity Signals from Peripherals
    // [0]: UART, [1]: Timer, [2]: GPIO
    input  wire [NUM_PERIPHS-1:0]  periph_activity_i,

    // Inter-IP Idle Output to PPMC
    output reg  [NUM_PERIPHS-1:0]  hap_idle_o,

    // AXI4-Lite Read Address Channel
    input  wire [ID_WIDTH-1:0]     s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_araddr,
    input  wire                    s_axi_arvalid,
    output reg                     s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [ID_WIDTH-1:0]     s_axi_rid,
    output reg  [DATA_WIDTH-1:0]   s_axi_rdata,
    output reg  [1:0]              s_axi_rresp,
    output reg                     s_axi_rvalid,
    input  wire                    s_axi_rready,

    // AXI4-Lite Write Address Channel
    input  wire [ID_WIDTH-1:0]     s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  wire                    s_axi_awvalid,
    output reg                     s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]   s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0]  s_axi_wstrb,
    input  wire                    s_axi_wvalid,
    output reg                     s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [ID_WIDTH-1:0]     s_axi_bid,
    output reg  [1:0]              s_axi_bresp,
    output reg                     s_axi_bvalid,
    input  wire                    s_axi_bready
);

    // Registers:
    // 0x00: HAP_CTRL       [0] EN (global enable)
    // 0x04: HAP_MANAGE_EN  [2:0] enable monitoring per peripheral
    // 0x08: HAP_IDLE_TH    [31:0] inactivity threshold in clock cycles
    // 0x0C: HAP_IDLE_CNT   [31:0] primary inactivity counter value
    // 0x10: HAP_STATUS     [2:0] active indications, [6:4] idle flags
    reg                   hap_en;
    reg  [NUM_PERIPHS-1:0] manage_en;
    reg  [31:0]           idle_threshold;
    reg  [31:0]           inactivity_cnt [0:NUM_PERIPHS-1];
    reg  [NUM_PERIPHS-1:0] activity_latch;

    integer p;

    // Profiler & Inactivity Counter Engine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hap_idle_o     <= {NUM_PERIPHS{1'b0}};
            activity_latch <= {NUM_PERIPHS{1'b0}};
            for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                inactivity_cnt[p] <= 32'd0;
            end
        end else if (hap_en) begin
            for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                activity_latch[p] <= periph_activity_i[p];
                if (manage_en[p]) begin
                    if (periph_activity_i[p]) begin
                        // Activity detected: reset inactivity counter and clear idle flag
                        inactivity_cnt[p] <= 32'd0;
                        hap_idle_o[p]     <= 1'b0;
                    end else begin
                        // Inactivity continues: increment counter until threshold
                        if (inactivity_cnt[p] >= idle_threshold) begin
                            hap_idle_o[p] <= 1'b1; // Raise idle indication!
                        end else begin
                            inactivity_cnt[p] <= inactivity_cnt[p] + 32'd1;
                        end
                    end
                end else begin
                    inactivity_cnt[p] <= 32'd0;
                    hap_idle_o[p]     <= 1'b0;
                end
            end
        end else begin
            hap_idle_o <= {NUM_PERIPHS{1'b0}};
        end
    end

    // AXI4-Lite Write Channel
    wire write_fire = s_axi_awvalid && s_axi_wvalid && (!s_axi_bvalid || s_axi_bready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready  <= 1'b0;
            s_axi_wready   <= 1'b0;
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            s_axi_bid      <= {ID_WIDTH{1'b0}};
            hap_en         <= 1'b0;
            manage_en      <= {NUM_PERIPHS{1'b1}}; // Default monitor all
            idle_threshold <= 32'd1000;            // Default 1000 cycles
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (write_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
                s_axi_bid     <= s_axi_awid;

                case (s_axi_awaddr[4:0])
                    5'h00: hap_en         <= s_axi_wdata[0];
                    5'h04: manage_en      <= s_axi_wdata[NUM_PERIPHS-1:0];
                    5'h08: idle_threshold <= s_axi_wdata;
                    default: ;
                endcase
            end
        end
    end

    // AXI4-Lite Read Channel
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rresp   <= 2'b00;
            s_axi_rdata   <= {DATA_WIDTH{1'b0}};
            s_axi_rid     <= {ID_WIDTH{1'b0}};
        end else begin
            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid  <= 1'b0;
                s_axi_arready <= 1'b0;
            end else if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                s_axi_rid     <= s_axi_arid;

                case (s_axi_araddr[4:0])
                    5'h00:   s_axi_rdata <= {31'd0, hap_en};
                    5'h04:   s_axi_rdata <= {{(DATA_WIDTH-NUM_PERIPHS){1'b0}}, manage_en};
                    5'h08:   s_axi_rdata <= idle_threshold;
                    5'h0C:   s_axi_rdata <= inactivity_cnt[0]; // primary UART/peripheral count
                    5'h10:   s_axi_rdata <= {24'd0, 1'b0, hap_idle_o, 1'b0, activity_latch};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
