// -----------------------------------------------------------------------------
// pp_ppmc.sv
//
// PowerPulse Peripheral Power Management Controller (PPMC)
// Central FSM that controls peripheral power states (ACTIVE, IDLE, LOW-ACTIVITY)
// and drives RTL-level peripheral-enable / clock-enable gating signals.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_ppmc #(
    parameter integer NUM_PERIPHS = 3,
    parameter integer ADDR_WIDTH  = 5,
    parameter integer DATA_WIDTH  = 32,
    parameter integer ID_WIDTH    = 12
) (
    input  wire                    clk,
    input  wire                    rst_n,

    // Inter-IP Inputs from HAP & AWEC
    input  wire [NUM_PERIPHS-1:0]  hap_idle_i,       // Inactivity detected by HAP
    input  wire                    wakeup_req_i,     // Valid wake request from AWEC
    input  wire [1:0]              wakeup_source_id_i,// Captured wake source ID

    // Inter-IP Outputs to Peripherals
    // [0]: UART, [1]: Timer, [2]: GPIO
    output reg  [NUM_PERIPHS-1:0]  periph_enable_o,  // Clock/enable gates

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

    // Power States per peripheral
    localparam [1:0] ST_ACTIVE       = 2'b00;
    localparam [1:0] ST_IDLE         = 2'b01;
    localparam [1:0] ST_LOW_ACTIVITY = 2'b10;

    // Registers:
    // 0x00: PPMC_CTRL       [0] Global enable
    // 0x04: PPMC_POLICY     [0] 1: Auto (hardware-directed), 0: Manual (software)
    // 0x08: PPMC_PERIPH_EN  [2:0] Manual periph enable register
    // 0x0C: PPMC_STATE      [5:0] Current state of each peripheral
    // 0x10: PPMC_WAKE_MASK  [2:0] Permitted wake sources mask
    reg                   ppmc_en;
    reg                   auto_policy;
    reg [NUM_PERIPHS-1:0] manual_en;
    reg [NUM_PERIPHS-1:0] wake_mask;

    reg [1:0] state [0:NUM_PERIPHS-1];

    integer p;

    // Central Power State Machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                state[p] <= ST_ACTIVE;
            end
            periph_enable_o <= {NUM_PERIPHS{1'b1}};
        end else if (ppmc_en) begin
            if (auto_policy) begin
                // Autonomous hardware-directed power management
                for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                    case (state[p])
                        ST_ACTIVE: begin
                            periph_enable_o[p] <= 1'b1;
                            if (hap_idle_i[p]) begin
                                state[p] <= ST_IDLE;
                            end
                        end

                        ST_IDLE: begin
                            // Confirm idle and transition to LOW-ACTIVITY
                            if (hap_idle_i[p]) begin
                                state[p] <= ST_LOW_ACTIVITY;
                                periph_enable_o[p] <= 1'b0; // Gate clock/enable!
                            end else begin
                                state[p] <= ST_ACTIVE;
                                periph_enable_o[p] <= 1'b1;
                            end
                        end

                        ST_LOW_ACTIVITY: begin
                            periph_enable_o[p] <= 1'b0; // Keep gated
                            // Check for wake event from AWEC
                            if (wakeup_req_i && wake_mask[p]) begin
                                state[p] <= ST_ACTIVE;
                                periph_enable_o[p] <= 1'b1; // Restore to ACTIVE!
                            end
                        end

                        default: state[p] <= ST_ACTIVE;
                    endcase
                end
            end else begin
                // Manual software control
                periph_enable_o <= manual_en;
                for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                    state[p] <= manual_en[p] ? ST_ACTIVE : ST_LOW_ACTIVITY;
                end
            end
        end else begin
            // Management disabled: default all peripherals to fully ACTIVE
            periph_enable_o <= {NUM_PERIPHS{1'b1}};
            for (p = 0; p < NUM_PERIPHS; p = p + 1) begin
                state[p] <= ST_ACTIVE;
            end
        end
    end

    // AXI4-Lite Write Channel
    wire write_fire = s_axi_awvalid && s_axi_wvalid && (!s_axi_bvalid || s_axi_bready);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
            s_axi_bid     <= {ID_WIDTH{1'b0}};
            ppmc_en       <= 1'b1; // Default enabled
            auto_policy   <= 1'b1; // Default auto
            manual_en     <= {NUM_PERIPHS{1'b1}};
            wake_mask     <= {NUM_PERIPHS{1'b1}};
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
                    5'h00: ppmc_en     <= s_axi_wdata[0];
                    5'h04: auto_policy <= s_axi_wdata[0];
                    5'h08: manual_en   <= s_axi_wdata[NUM_PERIPHS-1:0];
                    5'h10: wake_mask   <= s_axi_wdata[NUM_PERIPHS-1:0];
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
                    5'h00: s_axi_rdata <= {31'd0, ppmc_en};
                    5'h04: s_axi_rdata <= {31'd0, auto_policy};
                    5'h08: s_axi_rdata <= {{(DATA_WIDTH-NUM_PERIPHS){1'b0}}, periph_enable_o};
                    5'h0C: s_axi_rdata <= {26'd0, state[2], state[1], state[0]};
                    5'h10: s_axi_rdata <= {{(DATA_WIDTH-NUM_PERIPHS){1'b0}}, wake_mask};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
