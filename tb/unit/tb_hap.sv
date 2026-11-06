// =============================================================================
// tb_hap.sv -- Standalone unit testbench for pp_hap (Hardware Activity Profiler)
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_hap;

    localparam int NUM_PERIPHS = 3;
    localparam int ADDR_WIDTH  = 5;
    localparam int DATA_WIDTH  = 32;
    localparam int ID_WIDTH    = 12;

    reg clk, rst_n;
    always #5 clk = ~clk;

    reg  [NUM_PERIPHS-1:0] periph_activity_i;
    wire [NUM_PERIPHS-1:0] hap_idle_o;

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

    pp_hap #(
        .NUM_PERIPHS(NUM_PERIPHS), .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .periph_activity_i(periph_activity_i), .hap_idle_o(hap_idle_o),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready)
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
        periph_activity_i = 3'b000;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0;
        s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;

        #20 rst_n = 1;
        #20;
        $display("[TB_HAP] Starting unit tests...");

        // 1. Program threshold = 10 cycles
        axi_write(5'h08, 32'd10);
        axi_write(5'h04, 32'h07); // monitor all 3 periphs
        axi_write(5'h00, 32'h01); // enable HAP

        // 2. Keep activity alive for 5 cycles
        repeat (5) begin
            @(posedge clk);
            periph_activity_i[0] = 1'b1;
        end
        periph_activity_i = 3'b000;

        // 3. Wait 12 cycles without activity
        repeat (12) @(posedge clk);

        // 4. Check that hap_idle is asserted
        if (hap_idle_o[0] !== 1'b1) $fatal(1, "hap_idle_o[0] not asserted after threshold!");
        $display("[TB_HAP] hap_idle_o correctly asserted after inactivity threshold.");

        // 5. Activity pulse clears idle
        @(posedge clk);
        periph_activity_i[0] = 1'b1;
        @(posedge clk);
        periph_activity_i[0] = 1'b0;
        @(posedge clk);
        if (hap_idle_o[0] !== 1'b0) $fatal(1, "hap_idle_o[0] not cleared on activity!");

        $display("[PASS] tb_hap unit verification completed successfully.");
        $finish;
    end

endmodule
`default_nettype wire
