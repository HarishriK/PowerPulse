// -----------------------------------------------------------------------------
// pp_timer.sv
//
// PowerPulse System Timer Peripheral with AXI4-Lite interface and
// autonomous power-management hooks (activity tracking, clock gating, wake).
// -----------------------------------------------------------------------------

`default_nettype none

module pp_timer #(
    parameter integer ADDR_WIDTH = 5,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 12
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // AXI4-Lite Read Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_araddr,
    input  wire                   s_axi_arvalid,
    output reg                    s_axi_arready,

    // AXI4-Lite Read Data Channel
    output reg  [ID_WIDTH-1:0]    s_axi_rid,
    output reg  [DATA_WIDTH-1:0]  s_axi_rdata,
    output reg  [1:0]             s_axi_rresp,
    output reg                    s_axi_rvalid,
    input  wire                   s_axi_rready,

    // AXI4-Lite Write Address Channel
    input  wire [ID_WIDTH-1:0]    s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire                   s_axi_awvalid,
    output reg                    s_axi_awready,

    // AXI4-Lite Write Data Channel
    input  wire [DATA_WIDTH-1:0]  s_axi_wdata,
    input  wire [DATA_WIDTH/8-1:0] s_axi_wstrb,
    input  wire                   s_axi_wvalid,
    output reg                    s_axi_wready,

    // AXI4-Lite Write Response Channel
    output reg  [ID_WIDTH-1:0]    s_axi_bid,
    output reg  [1:0]             s_axi_bresp,
    output reg                    s_axi_bvalid,
    input  wire                   s_axi_bready,

    // Power-Management & Interrupt Hooks
    input  wire                   pp_enable_i,     // Gated enable from PPMC
    output reg                    pp_activity_o,   // Activity pulse to HAP
    output reg                    pp_wake_o,       // Wake pulse to AWEC
    output wire                   irq_o            // Core interrupt
);

    // Registers:
    // 0x00: TIMER_CTRL   [0] EN, [1] AUTO_RELOAD, [2] IRQ_EN
    // 0x04: TIMER_LOAD   [31:0] Reload value
    // 0x08: TIMER_COUNT  [31:0] Current counter (RO)
    // 0x0C: TIMER_STATUS [0] OVERFLOW
    // 0x10: TIMER_IRQ_CLR [0] Clear overflow/IRQ (WO)
    reg        timer_en;
    reg        auto_reload;
    reg        irq_en;
    reg [31:0] load_val;
    reg [31:0] count_val;
    reg        overflow_reg;
    reg        irq_pending;

    assign irq_o = irq_pending & irq_en;

    // Timer Down-Counter Logic
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count_val     <= 32'd0;
            overflow_reg  <= 1'b0;
            irq_pending   <= 1'b0;
            pp_wake_o     <= 1'b0;
        end else begin
            pp_wake_o <= 1'b0;
            // Only advance count if enabled both internally and by PPMC
            if (timer_en && pp_enable_i) begin
                if (count_val == 32'd0) begin
                    overflow_reg <= 1'b1;
                    pp_wake_o    <= 1'b1; // Trigger wake event when timer completes
                    if (irq_en) irq_pending <= 1'b1;
                    if (auto_reload) count_val <= load_val;
                end else begin
                    count_val <= count_val - 32'd1;
                end
            end
        end
    end

    // AXI4-Lite Write Transaction & Register Updates
    wire write_fire = s_axi_awvalid && s_axi_wvalid && (!s_axi_bvalid || s_axi_bready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            timer_en      <= 1'b0;
            auto_reload   <= 1'b0;
            irq_en        <= 1'b0;
            load_val      <= 32'd0;
            pp_activity_o <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            pp_activity_o <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            if (write_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00; // OKAY
                s_axi_bid     <= s_axi_awid;
                pp_activity_o <= 1'b1;  // Register access represents bus activity

                case (s_axi_awaddr[4:0])
                    5'h00: begin
                        timer_en    <= s_axi_wdata[0];
                        auto_reload <= s_axi_wdata[1];
                        irq_en      <= s_axi_wdata[2];
                        if (s_axi_wdata[0] && (count_val == 32'd0)) begin
                            count_val <= load_val;
                        end
                    end
                    5'h04: begin
                        load_val <= s_axi_wdata;
                    end
                    5'h10: begin
                        if (s_axi_wdata[0]) begin
                            overflow_reg <= 1'b0;
                            irq_pending  <= 1'b0;
                        end
                    end
                    default: ;
                endcase
            end else if (s_axi_arvalid && s_axi_rready) begin
                pp_activity_o <= 1'b1; // Read activity
            end else if (timer_en && pp_enable_i) begin
                // While counting, periodically assert activity
                pp_activity_o <= (count_val[3:0] == 4'h0);
            end
        end
    end

    // AXI4-Lite Read Transaction
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
                    5'h00:   s_axi_rdata <= {29'd0, irq_en, auto_reload, timer_en};
                    5'h04:   s_axi_rdata <= load_val;
                    5'h08:   s_axi_rdata <= count_val;
                    5'h0C:   s_axi_rdata <= {31'd0, overflow_reg};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
