// =============================================================================
// tb_awec.sv -- Standalone unit testbench for pp_awec
// =============================================================================

`default_nettype none
`timescale 1ns/1ps

module tb_awec;

    localparam int NUM_PERIPHS = 3;
    localparam int ADDR_WIDTH  = 5;
    localparam int DATA_WIDTH  = 32;
    localparam int ID_WIDTH    = 12;

    reg clk, rst_n;
    always #5 clk = ~clk;

    reg  [NUM_PERIPHS-1:0] wake_event_i;
    wire                   wakeup_req_o;
    wire [1:0]             wakeup_source_id_o;

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

    pp_awec #(
        .NUM_PERIPHS(NUM_PERIPHS), .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH), .ID_WIDTH(ID_WIDTH)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .wake_event_i(wake_event_i), .wakeup_req_o(wakeup_req_o),
        .wakeup_source_id_o(wakeup_source_id_o),
        .s_axi_arid(s_axi_arid), .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready), .s_axi_rid(s_axi_rid), .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .s_axi_awid(s_axi_awid), .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready), .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready), .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready)
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

    initial begin
        clk = 0; rst_n = 0;
        wake_event_i = 3'b000;
        s_axi_arid = 0; s_axi_araddr = 0; s_axi_arvalid = 0; s_axi_rready = 0;
        s_axi_awid = 0; s_axi_awaddr = 0; s_axi_awvalid = 0; s_axi_wdata = 0;
        s_axi_wstrb = 4'hF; s_axi_wvalid = 0; s_axi_bready = 0;

        #20 rst_n = 1;
        #20;
        $display("[TB_AWEC] Starting unit tests...");

        // Enable all wake sources
        axi_write(5'h04, 32'h07);
        axi_write(5'h00, 32'h01);

        // Inject rising edge pulse on wake_event_i[0] (UART)
        @(posedge clk);
        wake_event_i[0] = 1'b1;
        @(posedge clk);
        wake_event_i[0] = 1'b0;

        if (wakeup_req_o !== 1'b1) $fatal(1, "wakeup_req_o not asserted!");
        if (wakeup_source_id_o !== 2'd1) $fatal(1, "wakeup_source_id_o mismatch: expected 1, got %0d", wakeup_source_id_o);
        $display("[TB_AWEC] UART wake pulse captured and source identified!");

        // Clear event via ACK
        axi_write(5'h10, 32'h01);
        @(posedge clk);
        if (dut.pending_status[0] !== 1'b0) $fatal(1, "pending_status not cleared by ACK!");

        $display("[PASS] tb_awec unit verification completed successfully.");
        $finish;
    end

endmodule
`default_nettype wire
