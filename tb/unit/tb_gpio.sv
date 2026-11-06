// =============================================================================
// tb_gpio.sv -- Standalone unit testbench for pp_gpio
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_gpio;

    localparam int WIDTH      = 8;
    localparam int ADDR_WIDTH = 5;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 12;

    reg clk, rst_n;
    always #5 clk = ~clk;

    reg  [WIDTH-1:0]       gpio_in;
    wire [WIDTH-1:0]       gpio_out;

    reg  [ID_WIDTH-1:0]    s_axi_arid;
    reg  [ADDR_WIDTH-1:0]  s_axi_araddr;
    reg                    s_axi_arvalid;
    wire                   s_axi_arready;
    wire [ID_WIDTH-1:0]    s_axi_rid;
    wire [DATA_WIDTH-1:0]  s_axi_rdata;
    wire [1:0]             s_axi_rresp;
    wire                   s_axi_rvalid;
    reg                    s_axi_rready;

    reg  [ID_WIDTH-1:0]    s_axi_awid;
    reg  [ADDR_WIDTH-1:0]  s_axi_awaddr;
    reg                    s_axi_awvalid;
    wire                   s_axi_awready;
    reg  [DATA_WIDTH-1:0]  s_axi_wdata;
    reg  [DATA_WIDTH/8-1:0] s_axi_wstrb;
    reg                    s_axi_wvalid;
    wire                   s_axi_wready;
    wire [ID_WIDTH-1:0]    s_axi_bid;
    wire [1:0]             s_axi_bresp;
    wire                   s_axi_bvalid;
    reg                    s_axi_bready;

    reg  pp_enable_i;
    wire pp_activity_o;
    wire pp_wake_o;
    wire irq_o;

    pp_gpio #(
        .WIDTH(WIDTH), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .gpio_in(gpio_in), .gpio_out(gpio_out),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .pp_enable_i(pp_enable_i), .pp_activity_o(pp_activity_o), .pp_wake_o(pp_wake_o),
        .irq_o(irq_o)
    );

    task axi_write(input [4:0] addr, input [31:0] data);
    begin
        @(posedge clk);
        s_axi_awaddr  <= addr;
        s_axi_awvalid <= 1'b1;
        s_axi_wdata   <= data;
        s_axi_wvalid  <= 1'b1;
        s_axi_bready  <= 1'b1;
        wait (s_axi_awready && s_axi_wready);
        @(posedge clk);
        s_axi_awvalid <= 1'b0;
        s_axi_wvalid  <= 1'b0;
        wait (s_axi_bvalid);
        @(posedge clk);
        s_axi_bready  <= 1'b0;
    end
    endtask

    task axi_read(input [4:0] addr, output [31:0] data);
    begin
        @(posedge clk);
        s_axi_araddr  <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready  <= 1'b1;
        wait (s_axi_arready);
        @(posedge clk);
        s_axi_arvalid <= 1'b0;
        wait (s_axi_rvalid);
        data = s_axi_rdata;
        @(posedge clk);
        s_axi_rready  <= 1'b0;
    end
    endtask

    reg [31:0] rd_val;

    initial begin
        clk = 0; rst_n = 0;
        gpio_in = 8'h00;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0;
        s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;
        pp_enable_i = 1;

        #20 rst_n = 1;
        #20;
        $display("[TB_GPIO] Starting unit tests...");

        // 1. Write OUT register = 0xAA
        axi_write(5'h00, 32'hFF); // DIR = all output
        axi_write(5'h04, 32'hAA); // OUT = 0xAA
        #10;
        if (gpio_out !== 8'hAA) $fatal(1, "gpio_out mismatch: expected 0xAA, got 0x%02h", gpio_out);

        // 2. Configure edge detection on bit 7 (rising edge)
        axi_write(5'h00, 32'h00); // DIR = all input
        axi_write(5'h0C, 32'h00); // INTCFG = rising edge
        axi_write(5'h10, 32'h80); // INTEN = enable bit 7

        // Stimulate rising edge on bit 7
        #20;
        gpio_in = 8'h80;
        wait (pp_wake_o === 1'b1);
        $display("[TB_GPIO] Wake event detected on rising edge of gpio_in[7]!");

        axi_read(5'h14, rd_val); // INTSTAT
        if ((rd_val & 32'h80) !== 32'h80) $fatal(1, "INTSTAT bit 7 not set!");

        $display("[PASS] tb_gpio unit verification completed successfully.");
        $finish;
    end

endmodule
`default_nettype wire
