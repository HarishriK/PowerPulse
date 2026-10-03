// -----------------------------------------------------------------------------
// pp_bus_harness
//
// Core-less integration harness: the *real* interconnect fabric
// (rtl/top/pp_soc_interconnect.sv) driven by three 64-bit AXI4 master models,
// exactly where the VeeR core's IFU/LSU/SB sit.
//
// Why this exists
//   PROJECT_CONTEXT.md's verification ethos #3 says: bring the bus up without
//   the core first.  Because the fabric is a separate module from the core, this
//   harness and powerpulse_soc drive *the same RTL* -- the Milestone A tests are
//   not testing a copy of the interconnect.
//
// What the harness provides to a test
//   u_h.m0 / u_h.m1 / u_h.m2   the three 64-bit AXI4 master models
//   u_h.uart_model            the UART bus functional model
//   u_h.<slot>_base           the base address of every config slot, as a localparam
//   u_h.uart_drive(byte)      send one byte into the DUT's UART RX
//   u_h.uart_expect(...)      receive from the DUT's UART TX with a timeout
//
// AXI protocol checkers are attached on every master port and are always on.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_bus_harness #(
    parameter integer SEED = 1
) (
    input  wire clk,
    input  wire rst_n
);

    import pp_soc_cfg_pkg::*;

    localparam integer M_ID0 = 3;
    localparam integer M_ID1 = 3;
    localparam integer M_ID2 = 1;

    // Slot base addresses, straight from the generated package.
    localparam logic [31:0] imem_base   = PP_IMEM_BASE;
    localparam logic [31:0] imem_size   = PP_IMEM_SIZE;
    localparam logic [31:0] dmem_base   = PP_DMEM_BASE;
    localparam logic [31:0] dmem_size   = PP_DMEM_SIZE;
    localparam logic [31:0] uart_base   = PP_UART_BASE;
    localparam logic [31:0] timer_base  = PP_TIMER_BASE;
    localparam logic [31:0] gpio_base   = PP_GPIO_BASE;
    localparam logic [31:0] hap_base    = PP_HAP_BASE;
    localparam logic [31:0] ppmc_base   = PP_PPMC_BASE;
    localparam logic [31:0] awec_base   = PP_AWEC_BASE;
    localparam logic [31:0] status_base = PP_STATUS_BASE;

    // =====================================================================
    // nets and bundles, declared before the DUT instance that connects them
    // =====================================================================
    wire        uart_rx;
    wire        uart_tx;
    wire        uart_irq;

    // ---- master m0 bundle ----
    wire [M_ID0-1:0] m0_awid, m0_arid, m0_bid, m0_rid;
    wire [31:0]   m0_awaddr, m0_araddr;
    wire [7:0]    m0_awlen, m0_arlen;
    wire [2:0]    m0_awsize, m0_arsize;
    wire [1:0]    m0_awburst, m0_arburst;
    wire          m0_awlock, m0_arlock;
    wire [2:0]    m0_awprot, m0_arprot;
    wire          m0_awvalid, m0_awready, m0_wvalid, m0_wready;
    wire [63:0]   m0_wdata;
    wire [7:0]    m0_wstrb;
    wire          m0_wlast, m0_bvalid, m0_bready, m0_arvalid, m0_arready;
    wire [1:0]    m0_bresp, m0_rresp;
    wire [63:0]   m0_rdata;
    wire          m0_rlast, m0_rvalid, m0_rready;

    // ---- master m1 bundle ----
    wire [M_ID1-1:0] m1_awid, m1_arid, m1_bid, m1_rid;
    wire [31:0]   m1_awaddr, m1_araddr;
    wire [7:0]    m1_awlen, m1_arlen;
    wire [2:0]    m1_awsize, m1_arsize;
    wire [1:0]    m1_awburst, m1_arburst;
    wire          m1_awlock, m1_arlock;
    wire [2:0]    m1_awprot, m1_arprot;
    wire          m1_awvalid, m1_awready, m1_wvalid, m1_wready;
    wire [63:0]   m1_wdata;
    wire [7:0]    m1_wstrb;
    wire          m1_wlast, m1_bvalid, m1_bready, m1_arvalid, m1_arready;
    wire [1:0]    m1_bresp, m1_rresp;
    wire [63:0]   m1_rdata;
    wire          m1_rlast, m1_rvalid, m1_rready;

    // ---- master m2 bundle ----
    wire [M_ID2-1:0] m2_awid, m2_arid, m2_bid, m2_rid;
    wire [31:0]   m2_awaddr, m2_araddr;
    wire [7:0]    m2_awlen, m2_arlen;
    wire [2:0]    m2_awsize, m2_arsize;
    wire [1:0]    m2_awburst, m2_arburst;
    wire          m2_awlock, m2_arlock;
    wire [2:0]    m2_awprot, m2_arprot;
    wire          m2_awvalid, m2_awready, m2_wvalid, m2_wready;
    wire [63:0]   m2_wdata;
    wire [7:0]    m2_wstrb;
    wire          m2_wlast, m2_bvalid, m2_bready, m2_arvalid, m2_arready;
    wire [1:0]    m2_bresp, m2_rresp;
    wire [63:0]   m2_rdata;
    wire          m2_rlast, m2_rvalid, m2_rready;

    // =====================================================================
    // fabric under test
    // =====================================================================
    pp_soc_interconnect #(
        .M0_ID_WIDTH(M_ID0), .M1_ID_WIDTH(M_ID1), .M2_ID_WIDTH(M_ID2)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .uart_irq(uart_irq),
        .m0_axi_awid(m0_awid),
        .m0_axi_awaddr(m0_awaddr),
        .m0_axi_awlen(m0_awlen),
        .m0_axi_awsize(m0_awsize),
        .m0_axi_awburst(m0_awburst),
        .m0_axi_awlock(m0_awlock),
        .m0_axi_awprot(m0_awprot),
        .m0_axi_awvalid(m0_awvalid),
        .m0_axi_awready(m0_awready),
        .m0_axi_wdata(m0_wdata),
        .m0_axi_wstrb(m0_wstrb),
        .m0_axi_wlast(m0_wlast),
        .m0_axi_wvalid(m0_wvalid),
        .m0_axi_wready(m0_wready),
        .m0_axi_bid(m0_bid),
        .m0_axi_bresp(m0_bresp),
        .m0_axi_bvalid(m0_bvalid),
        .m0_axi_bready(m0_bready),
        .m0_axi_arid(m0_arid),
        .m0_axi_araddr(m0_araddr),
        .m0_axi_arlen(m0_arlen),
        .m0_axi_arsize(m0_arsize),
        .m0_axi_arburst(m0_arburst),
        .m0_axi_arlock(m0_arlock),
        .m0_axi_arprot(m0_arprot),
        .m0_axi_arvalid(m0_arvalid),
        .m0_axi_arready(m0_arready),
        .m0_axi_rid(m0_rid),
        .m0_axi_rdata(m0_rdata),
        .m0_axi_rresp(m0_rresp),
        .m0_axi_rlast(m0_rlast),
        .m0_axi_rvalid(m0_rvalid),
        .m0_axi_rready(m0_rready),
        // ---- master 1 (m1) ----
        .m1_axi_awid(m1_awid),
        .m1_axi_awaddr(m1_awaddr),
        .m1_axi_awlen(m1_awlen),
        .m1_axi_awsize(m1_awsize),
        .m1_axi_awburst(m1_awburst),
        .m1_axi_awlock(m1_awlock),
        .m1_axi_awprot(m1_awprot),
        .m1_axi_awvalid(m1_awvalid),
        .m1_axi_awready(m1_awready),
        .m1_axi_wdata(m1_wdata),
        .m1_axi_wstrb(m1_wstrb),
        .m1_axi_wlast(m1_wlast),
        .m1_axi_wvalid(m1_wvalid),
        .m1_axi_wready(m1_wready),
        .m1_axi_bid(m1_bid),
        .m1_axi_bresp(m1_bresp),
        .m1_axi_bvalid(m1_bvalid),
        .m1_axi_bready(m1_bready),
        .m1_axi_arid(m1_arid),
        .m1_axi_araddr(m1_araddr),
        .m1_axi_arlen(m1_arlen),
        .m1_axi_arsize(m1_arsize),
        .m1_axi_arburst(m1_arburst),
        .m1_axi_arlock(m1_arlock),
        .m1_axi_arprot(m1_arprot),
        .m1_axi_arvalid(m1_arvalid),
        .m1_axi_arready(m1_arready),
        .m1_axi_rid(m1_rid),
        .m1_axi_rdata(m1_rdata),
        .m1_axi_rresp(m1_rresp),
        .m1_axi_rlast(m1_rlast),
        .m1_axi_rvalid(m1_rvalid),
        .m1_axi_rready(m1_rready),
        // ---- master 2 (m2) ----
        .m2_axi_awid(m2_awid),
        .m2_axi_awaddr(m2_awaddr),
        .m2_axi_awlen(m2_awlen),
        .m2_axi_awsize(m2_awsize),
        .m2_axi_awburst(m2_awburst),
        .m2_axi_awlock(m2_awlock),
        .m2_axi_awprot(m2_awprot),
        .m2_axi_awvalid(m2_awvalid),
        .m2_axi_awready(m2_awready),
        .m2_axi_wdata(m2_wdata),
        .m2_axi_wstrb(m2_wstrb),
        .m2_axi_wlast(m2_wlast),
        .m2_axi_wvalid(m2_wvalid),
        .m2_axi_wready(m2_wready),
        .m2_axi_bid(m2_bid),
        .m2_axi_bresp(m2_bresp),
        .m2_axi_bvalid(m2_bvalid),
        .m2_axi_bready(m2_bready),
        .m2_axi_arid(m2_arid),
        .m2_axi_araddr(m2_araddr),
        .m2_axi_arlen(m2_arlen),
        .m2_axi_arsize(m2_arsize),
        .m2_axi_arburst(m2_arburst),
        .m2_axi_arlock(m2_arlock),
        .m2_axi_arprot(m2_arprot),
        .m2_axi_arvalid(m2_arvalid),
        .m2_axi_arready(m2_arready),
        .m2_axi_rid(m2_rid),
        .m2_axi_rdata(m2_rdata),
        .m2_axi_rresp(m2_rresp),
        .m2_axi_rlast(m2_rlast),
        .m2_axi_rvalid(m2_rvalid),
        .m2_axi_rready(m2_rready)
    );

    // =====================================================================
    // AXI4 master models on the three core master ports
    // =====================================================================
    pp_axi_master #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID0), .NAME("m0"))
    m0 (.clk(clk), .rst_n(rst_n),
        .m_axi_awid(m0_awid),
        .m_axi_awaddr(m0_awaddr),
        .m_axi_awlen(m0_awlen),
        .m_axi_awsize(m0_awsize),
        .m_axi_awburst(m0_awburst),
        .m_axi_awlock(m0_awlock),
        .m_axi_awprot(m0_awprot),
        .m_axi_awvalid(m0_awvalid),
        .m_axi_awready(m0_awready),
        .m_axi_wdata(m0_wdata),
        .m_axi_wstrb(m0_wstrb),
        .m_axi_wlast(m0_wlast),
        .m_axi_wvalid(m0_wvalid),
        .m_axi_wready(m0_wready),
        .m_axi_bid(m0_bid),
        .m_axi_bresp(m0_bresp),
        .m_axi_bvalid(m0_bvalid),
        .m_axi_bready(m0_bready),
        .m_axi_arid(m0_arid),
        .m_axi_araddr(m0_araddr),
        .m_axi_arlen(m0_arlen),
        .m_axi_arsize(m0_arsize),
        .m_axi_arburst(m0_arburst),
        .m_axi_arlock(m0_arlock),
        .m_axi_arprot(m0_arprot),
        .m_axi_arvalid(m0_arvalid),
        .m_axi_arready(m0_arready),
        .m_axi_rid(m0_rid),
        .m_axi_rdata(m0_rdata),
        .m_axi_rresp(m0_rresp),
        .m_axi_rlast(m0_rlast),
        .m_axi_rvalid(m0_rvalid),
        .m_axi_rready(m0_rready)
    );

    pp_axi_master #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID1), .NAME("m1"))
    m1 (.clk(clk), .rst_n(rst_n),
        .m_axi_awid(m1_awid),
        .m_axi_awaddr(m1_awaddr),
        .m_axi_awlen(m1_awlen),
        .m_axi_awsize(m1_awsize),
        .m_axi_awburst(m1_awburst),
        .m_axi_awlock(m1_awlock),
        .m_axi_awprot(m1_awprot),
        .m_axi_awvalid(m1_awvalid),
        .m_axi_awready(m1_awready),
        .m_axi_wdata(m1_wdata),
        .m_axi_wstrb(m1_wstrb),
        .m_axi_wlast(m1_wlast),
        .m_axi_wvalid(m1_wvalid),
        .m_axi_wready(m1_wready),
        .m_axi_bid(m1_bid),
        .m_axi_bresp(m1_bresp),
        .m_axi_bvalid(m1_bvalid),
        .m_axi_bready(m1_bready),
        .m_axi_arid(m1_arid),
        .m_axi_araddr(m1_araddr),
        .m_axi_arlen(m1_arlen),
        .m_axi_arsize(m1_arsize),
        .m_axi_arburst(m1_arburst),
        .m_axi_arlock(m1_arlock),
        .m_axi_arprot(m1_arprot),
        .m_axi_arvalid(m1_arvalid),
        .m_axi_arready(m1_arready),
        .m_axi_rid(m1_rid),
        .m_axi_rdata(m1_rdata),
        .m_axi_rresp(m1_rresp),
        .m_axi_rlast(m1_rlast),
        .m_axi_rvalid(m1_rvalid),
        .m_axi_rready(m1_rready)
    );

    pp_axi_master #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID2), .NAME("m2"))
    m2 (.clk(clk), .rst_n(rst_n),
        .m_axi_awid(m2_awid),
        .m_axi_awaddr(m2_awaddr),
        .m_axi_awlen(m2_awlen),
        .m_axi_awsize(m2_awsize),
        .m_axi_awburst(m2_awburst),
        .m_axi_awlock(m2_awlock),
        .m_axi_awprot(m2_awprot),
        .m_axi_awvalid(m2_awvalid),
        .m_axi_awready(m2_awready),
        .m_axi_wdata(m2_wdata),
        .m_axi_wstrb(m2_wstrb),
        .m_axi_wlast(m2_wlast),
        .m_axi_wvalid(m2_wvalid),
        .m_axi_wready(m2_wready),
        .m_axi_bid(m2_bid),
        .m_axi_bresp(m2_bresp),
        .m_axi_bvalid(m2_bvalid),
        .m_axi_bready(m2_bready),
        .m_axi_arid(m2_arid),
        .m_axi_araddr(m2_araddr),
        .m_axi_arlen(m2_arlen),
        .m_axi_arsize(m2_arsize),
        .m_axi_arburst(m2_arburst),
        .m_axi_arlock(m2_arlock),
        .m_axi_arprot(m2_arprot),
        .m_axi_arvalid(m2_arvalid),
        .m_axi_arready(m2_arready),
        .m_axi_rid(m2_rid),
        .m_axi_rdata(m2_rdata),
        .m_axi_rresp(m2_rresp),
        .m_axi_rlast(m2_rlast),
        .m_axi_rvalid(m2_rvalid),
        .m_axi_rready(m2_rready)
    );
    // =====================================================================
    // AXI protocol checkers -- always on, on every master port
    // =====================================================================
    pp_axi_checker #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID0), .NAME("m0"))
    chk_m0 (.clk(clk), .rst_n(rst_n),
        .awid(m0_awid),
        .awaddr(m0_awaddr),
        .awlen(m0_awlen),
        .awsize(m0_awsize),
        .awvalid(m0_awvalid),
        .awready(m0_awready),
        .wdata(m0_wdata),
        .wstrb(m0_wstrb),
        .wlast(m0_wlast),
        .wvalid(m0_wvalid),
        .wready(m0_wready),
        .bid(m0_bid),
        .bresp(m0_bresp),
        .bvalid(m0_bvalid),
        .bready(m0_bready),
        .arid(m0_arid),
        .araddr(m0_araddr),
        .arlen(m0_arlen),
        .arsize(m0_arsize),
        .arvalid(m0_arvalid),
        .arready(m0_arready),
        .rid(m0_rid),
        .rdata(m0_rdata),
        .rresp(m0_rresp),
        .rlast(m0_rlast),
        .rvalid(m0_rvalid),
        .rready(m0_rready)
    );

    pp_axi_checker #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID1), .NAME("m1"))
    chk_m1 (.clk(clk), .rst_n(rst_n),
        .awid(m1_awid),
        .awaddr(m1_awaddr),
        .awlen(m1_awlen),
        .awsize(m1_awsize),
        .awvalid(m1_awvalid),
        .awready(m1_awready),
        .wdata(m1_wdata),
        .wstrb(m1_wstrb),
        .wlast(m1_wlast),
        .wvalid(m1_wvalid),
        .wready(m1_wready),
        .bid(m1_bid),
        .bresp(m1_bresp),
        .bvalid(m1_bvalid),
        .bready(m1_bready),
        .arid(m1_arid),
        .araddr(m1_araddr),
        .arlen(m1_arlen),
        .arsize(m1_arsize),
        .arvalid(m1_arvalid),
        .arready(m1_arready),
        .rid(m1_rid),
        .rdata(m1_rdata),
        .rresp(m1_rresp),
        .rlast(m1_rlast),
        .rvalid(m1_rvalid),
        .rready(m1_rready)
    );

    pp_axi_checker #(.ADDR_WIDTH(32), .DATA_WIDTH(64), .ID_WIDTH(M_ID2), .NAME("m2"))
    chk_m2 (.clk(clk), .rst_n(rst_n),
        .awid(m2_awid),
        .awaddr(m2_awaddr),
        .awlen(m2_awlen),
        .awsize(m2_awsize),
        .awvalid(m2_awvalid),
        .awready(m2_awready),
        .wdata(m2_wdata),
        .wstrb(m2_wstrb),
        .wlast(m2_wlast),
        .wvalid(m2_wvalid),
        .wready(m2_wready),
        .bid(m2_bid),
        .bresp(m2_bresp),
        .bvalid(m2_bvalid),
        .bready(m2_bready),
        .arid(m2_arid),
        .araddr(m2_araddr),
        .arlen(m2_arlen),
        .arsize(m2_arsize),
        .arvalid(m2_arvalid),
        .arready(m2_arready),
        .rid(m2_rid),
        .rdata(m2_rdata),
        .rresp(m2_rresp),
        .rlast(m2_rlast),
        .rvalid(m2_rvalid),
        .rready(m2_rready)
    );

    // ---- bring-up probe ---------------------------------------------------
    integer bq;
    initial bq = 0;
    always @(posedge clk) begin
        if (rst_n && bq < 400) begin
            bq = bq + 1;
            if (dut.u_xbar.m_axi_rready != 3'b000)
                $display({"[bpx] rrdy=%b s1(r_act=%b r_own=%0d ar_sent=%b bufv=%b bufend=%b) ",
                          "s2(r_act=%b r_own=%0d ar_sent=%b bufv=%b) s3(r_act=%b r_own=%0d bufv=%b)"},
                         dut.u_xbar.m_axi_rready,
                         dut.u_xbar.g_slave[1].r_act, dut.u_xbar.g_slave[1].r_own,
                         dut.u_xbar.g_slave[1].r_ar_sent, dut.u_xbar.g_slave[1].r_r_buf_v,
                         dut.u_xbar.g_slave[1].r_r_buf_end,
                         dut.u_xbar.g_slave[2].r_act, dut.u_xbar.g_slave[2].r_own,
                         dut.u_xbar.g_slave[2].r_ar_sent, dut.u_xbar.g_slave[2].r_r_buf_v,
                         dut.u_xbar.g_slave[3].r_act, dut.u_xbar.g_slave[3].r_own,
                         dut.u_xbar.g_slave[3].r_r_buf_v);
        end
    end

    // =====================================================================
    // UART bus functional model
    // =====================================================================
    pp_uart_model #(
        .CLK_FREQ_HZ(PP_CLK_FREQ_HZ), .BAUD(PP_UART_BAUD),
        .DATA_BITS(8), .PARITY(0), .STOP_BITS(1)
    ) uart_model (
        .rx_clk(clk), .rst_n(rst_n), .uart_rx(uart_rx), .uart_tx(uart_tx)
    );

    // ---- convenience wrappers used by the UART tests --------------------
    task automatic uart_drive(input logic [7:0] value);
        uart_model.send_byte_ok(value);
    endtask

    task automatic uart_expect(output logic [7:0] value, input int unsigned max_cycles);
        int unsigned waited;
        waited = 0;
        while (uart_model.num_received() == 0 && waited < max_cycles) begin
            @(posedge clk);
            waited = waited + 1;
        end
        if (uart_model.num_received() == 0) begin
            value = 8'hxx;
        end else begin
            uart_model.get_byte(value);
        end
    endtask

endmodule

`default_nettype wire
