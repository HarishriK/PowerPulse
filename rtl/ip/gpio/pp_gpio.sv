// -----------------------------------------------------------------------------
// pp_gpio.sv
//
// PowerPulse General Purpose Input/Output (GPIO) Peripheral
// with AXI4-Lite slave interface, 2-flop input synchronizers, configurable
// edge detection, and autonomous wake/activity hooks for PowerPulse.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_gpio #(
    parameter integer WIDTH      = 8,
    parameter integer ADDR_WIDTH = 5,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 12
) (
    input  wire                   clk,
    input  wire                   rst_n,

    // External GPIO Boundary Pins
    input  wire [WIDTH-1:0]       gpio_in,
    output wire [WIDTH-1:0]       gpio_out,

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

    reg [WIDTH-1:0] dir_reg;
    reg [WIDTH-1:0] out_reg;
    reg [WIDTH-1:0] intcfg_reg;
    reg [WIDTH-1:0] inten_reg;
    reg [WIDTH-1:0] intstat_reg;

    // 2-stage synchronizer for input pins
    reg [WIDTH-1:0] in_sync1;
    reg [WIDTH-1:0] in_sync2;
    reg [WIDTH-1:0] in_prev;

    assign gpio_out = out_reg;
    assign irq_o    = |(intstat_reg & inten_reg);

    // Synchronizer & Edge Detection (always listening for wake events)
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_sync1    <= {WIDTH{1'b0}};
            in_sync2    <= {WIDTH{1'b0}};
            in_prev     <= {WIDTH{1'b0}};
            intstat_reg <= {WIDTH{1'b0}};
            pp_wake_o   <= 1'b0;
        end else begin
            in_sync1  <= gpio_in;
            in_sync2  <= in_sync1;
            in_prev   <= in_sync2;
            pp_wake_o <= 1'b0;

            for (i = 0; i < WIDTH; i = i + 1) begin
                if (inten_reg[i]) begin
                    if (intcfg_reg[i] == 1'b0) begin
                        // Rising edge
                        if (!in_prev[i] && in_sync2[i]) begin
                            intstat_reg[i] <= 1'b1;
                            pp_wake_o      <= 1'b1; // Wake up system on GPIO edge!
                        end
                    end else begin
                        // Falling edge
                        if (in_prev[i] && !in_sync2[i]) begin
                            intstat_reg[i] <= 1'b1;
                            pp_wake_o      <= 1'b1; // Wake up system on GPIO edge!
                        end
                    end
                end
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
            dir_reg       <= {WIDTH{1'b0}};
            out_reg       <= {WIDTH{1'b0}};
            intcfg_reg    <= {WIDTH{1'b0}};
            inten_reg     <= {WIDTH{1'b0}};
            pp_activity_o <= 1'b0;
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            pp_activity_o <= 1'b0;

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end

            // Activity is generated on pin changes or register accesses
            if (in_prev != in_sync2) begin
                pp_activity_o <= 1'b1;
            end

            if (write_fire) begin
                s_axi_awready <= 1'b1;
                s_axi_wready  <= 1'b1;
                s_axi_bvalid  <= 1'b1;
                s_axi_bresp   <= 2'b00;
                s_axi_bid     <= s_axi_awid;
                pp_activity_o <= 1'b1;

                case (s_axi_awaddr[4:0])
                    5'h00: dir_reg    <= s_axi_wdata[WIDTH-1:0];
                    5'h04: out_reg    <= s_axi_wdata[WIDTH-1:0];
                    5'h0C: intcfg_reg <= s_axi_wdata[WIDTH-1:0];
                    5'h10: inten_reg  <= s_axi_wdata[WIDTH-1:0];
                    5'h18: intstat_reg <= intstat_reg & ~s_axi_wdata[WIDTH-1:0]; // Clear on write
                    default: ;
                endcase
            end else if (s_axi_arvalid && s_axi_rready) begin
                pp_activity_o <= 1'b1;
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
                    5'h00:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, dir_reg};
                    5'h04:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, out_reg};
                    5'h08:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, in_sync2};
                    5'h0C:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, intcfg_reg};
                    5'h10:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, inten_reg};
                    5'h14:   s_axi_rdata <= {{(DATA_WIDTH-WIDTH){1'b0}}, intstat_reg};
                    default: s_axi_rdata <= 32'd0;
                endcase
            end
        end
    end

endmodule
`default_nettype wire
