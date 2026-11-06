// -----------------------------------------------------------------------------
// pp_awec.sv
//
// PowerPulse Autonomous Wake-Up Event Controller (AWEC)
// Captures asynchronous wake events from UART, Timer, and GPIO,
// identifies the wake source, and signals PPMC to restore peripheral clocks.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_awec #(
    parameter integer NUM_PERIPHS = 3,
    parameter integer ADDR_WIDTH  = 5,
    parameter integer DATA_WIDTH  = 32,
    parameter integer ID_WIDTH    = 12
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Inter-IP Raw Wake Events from Peripherals
    // [0]: UART RX, [1]: Timer Compare, [2]: GPIO Edge
    input  wire [NUM_PERIPHS-1:0]  wake_event_i,

    // Inter-IP Wake Request Output to PPMC
    output reg                     wakeup_req_o,
    output reg  [1:0]              wakeup_source_id_o,

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
    // 0x00: AWEC_CTRL      [0] Wake monitoring global enable
    // 0x04: AWEC_ENABLE    [2:0] Enable per wake source
    // 0x08: AWEC_STATUS    [2:0] Pending wake event flags
    // 0x0C: AWEC_EVENT_ID  [1:0] Latched wake source ID
    // 0x10: AWEC_ACK       [2:0] Write 1 to clear pending wake event
    reg                   awec_en;
    reg [NUM_PERIPHS-1:0] source_en;
    reg [NUM_PERIPHS-1:0] pending_status;
    reg [1:0]             event_id_reg;

    reg [NUM_PERIPHS-1:0] wake_prev;

    // Wake Event Detection & Latching Logic
    integer p;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wakeup_req_o       <= 1'b0;
            wakeup_source_id_o <= 2'b00;
            pending_status     <= {NUM_PERIPHS{1'b0}};
            event_id_reg       <= 2'b00;
            wake_prev          <= {NUM_PERIPHS{1'b0}};
        end else if (awec_en) begin
            wake_prev <= wake_event_i;
            wakeup_req_o <= 1'b0;

            for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                if (source_en[p] && wake_event_i[p] && !wake_prev[p]) begin
                    // Rising edge of wake event detected
                    pending_status[p]  <= 1'b1;
                    wakeup_req_o       <= 1'b1; // Trigger PPMC restoration!
                    event_id_reg       <= p[1:0] + 2'b01; // 1: UART, 2: Timer, 3: GPIO
                    wakeup_source_id_o <= p[1:0] + 2'b01;
                end
            end
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
            awec_en        <= 1'b1; // Default enabled
            source_en      <= {NUM_PERIPHS{1'b1}}; // Default all enabled
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
                    5'h00: awec_en   <= s_axi_wdata[0];
                    5'h04: source_en <= s_axi_wdata[NUM_PERIPHS-1:0];
                    5'h10: begin
                        // Acknowledge and clear pending bits
                        pending_status <= pending_status & ~s_axi_wdata[NUM_PERIPHS-1:0];
                        if ((pending_status & ~s_axi_wdata[NUM_PERIPHS-1:0]) == {NUM_PERIPHS{1'b0}}) begin
                            event_id_reg <= 2'b00;
                        end
                    end
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
                    5'h00: s_axi_rdata <= {31'd0, awec_en};
                    5'h04: s_axi_rdata <= {{(DATA_WIDTH-NUM_PERIPHS){1'b0}}, source_en};
                    5'h08: s_axi_rdata <= {{(DATA_WIDTH-NUM_PERIPHS){1'b0}}, pending_status};
                    5'h0C: s_axi_rdata <= {30'd0, event_id_reg};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
