// =============================================================================
// tb_timer.sv -- Standalone unit testbench for pp_timer
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_timer;

    localparam int ADDR_WIDTH = 5;
    localparam int DATA_WIDTH = 32;
    localparam int ID_WIDTH   = 12;

    reg clk, rst_n;
    always #5 clk = ~clk;

    // AXI4-Lite signals
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

    pp_timer #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
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
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0;
        s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;
        pp_enable_i = 1;

        #20 rst_n = 1;
        #20;
        $display("[TB_TIMER] Starting unit tests...");

        // 1. Program load register = 5
        axi_write(5'h04, 32'd5);
        axi_read(5'h04, rd_val);
        if (rd_val !== 32'd5) $fatal(1, "LOAD mismatch: %0d", rd_val);

        // 2. Enable timer with auto-reload (ctrl = 0x03)
        axi_write(5'h00, 32'h03);

        // 3. Wait for timer countdown and overflow
        wait (pp_wake_o === 1'b1);
        $display("[TB_TIMER] Timer overflow detected via pp_wake_o!");

        axi_read(5'h0C, rd_val);
        if ((rd_val & 32'd1) !== 32'd1) $fatal(1, "STATUS overflow bit not set!");

        // 4. Test gating via pp_enable_i = 0
        pp_enable_i = 0;
        axi_read(5'h08, rd_val);
        #100;
        if (dut.count_val !== rd_val) $fatal(1, "Timer advanced while pp_enable_i=0!");

        $display("[PASS] tb_timer unit verification completed successfully.");
        $finish;
    end

endmodule
`default_nettype wire
