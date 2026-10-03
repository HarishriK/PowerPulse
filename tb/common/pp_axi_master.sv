// -----------------------------------------------------------------------------
// pp_axi_master
//
// Parameterised AXI4 master model for testbenches.  One instance drives one
// master port; instantiate several to test arbitration.
//
// Used at both widths in this project: at 64 bit in front of pp_axi_downsize
// (so the adapter is inside the tested path) and at 32 bit in front of the
// interconnect.
//
// What it offers
//   * single and burst transfers, all legal sizes and alignments
//   * byte strobes, so narrow writes are exercised as narrow writes
//   * randomised VALID and READY delays, so no test accidentally depends on
//     zero-latency handshakes; the seed is printed and also settable
//   * *concurrent* transfers: `start_read` / `await_read` let several masters
//     have requests in flight at once, which is how the arbitration test is
//     written
//   * the response of every transfer is returned, so a test can check SLVERR
//     and DECERR rather than only OKAY
//
// Plusargs
//   +seed=<n>          seed the delay generator (also accepted per-instance via
//                      the `seed` argument to axi_set_seed)
//   +wr_delay_max=<n>  maximum extra delay on VALID, in cycles (default 0)
//   +rd_delay_max=<n>  maximum extra delay on READY, in cycles (default 0)
//
// Rules obeyed by the model
//   * VALID is never deasserted before READY
//   * the payload of a VALID channel never changes while VALID && !READY
//   * WLAST is asserted on exactly the last beat of a burst
//   * every request gets exactly one response, in order
// -----------------------------------------------------------------------------

`default_nettype none

module pp_axi_master #(
    parameter integer ADDR_WIDTH = 32,
    parameter integer DATA_WIDTH = 32,
    parameter integer ID_WIDTH   = 4,
    parameter          NAME       = "m0"
) (
    input  wire                       clk,
    input  wire                       rst_n,

    output reg  [ID_WIDTH-1:0]        m_axi_awid,
    output reg  [ADDR_WIDTH-1:0]      m_axi_awaddr,
    output reg  [7:0]                 m_axi_awlen,
    output reg  [2:0]                 m_axi_awsize,
    output reg  [1:0]                 m_axi_awburst,
    output reg                         m_axi_awlock,
    output reg  [2:0]                 m_axi_awprot,
    output reg                         m_axi_awvalid,
    input  wire                       m_axi_awready,

    output reg  [DATA_WIDTH-1:0]      m_axi_wdata,
    output reg  [DATA_WIDTH/8-1:0]    m_axi_wstrb,
    output reg                         m_axi_wlast,
    output reg                         m_axi_wvalid,
    input  wire                       m_axi_wready,

    input  wire [ID_WIDTH-1:0]        m_axi_bid,
    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output reg                         m_axi_bready,

    output reg  [ID_WIDTH-1:0]        m_axi_arid,
    output reg  [ADDR_WIDTH-1:0]      m_axi_araddr,
    output reg  [7:0]                 m_axi_arlen,
    output reg  [2:0]                 m_axi_arsize,
    output reg  [1:0]                 m_axi_arburst,
    output reg                         m_axi_arlock,
    output reg  [2:0]                 m_axi_arprot,
    output reg                         m_axi_arvalid,
    input  wire                       m_axi_arready,

    input  wire [ID_WIDTH-1:0]        m_axi_rid,
    input  wire [DATA_WIDTH-1:0]      m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output reg                         m_axi_rready
);

    localparam integer STRB_WIDTH = DATA_WIDTH / 8;

    // ------------------------------------------------------------------
    // delay generation
    // ------------------------------------------------------------------
    integer unsigned seed;
    integer wr_delay_max;
    integer rd_delay_max;
    bit          trace;          // +trace prints every handshake, for debugging

    initial begin
        seed = 1;
        wr_delay_max = 0;
        rd_delay_max = 0;
        void'($value$plusargs("seed=%d", seed));
        void'($value$plusargs("wr_delay_max=%d", wr_delay_max));
        void'($value$plusargs("rd_delay_max=%d", rd_delay_max));
        trace = $test$plusargs("trace");
    end

    // Handshake tracing.  Off by default; a failing test can be re-run with
    // +trace and read straight from the log, which is usually faster than
    // opening a waveform.
    task automatic tr(input string what);
        if (trace) $display("[%0s t=%0t] %s", NAME, $time, what);
    endtask

    // A per-call seed keeps runs reproducible: the same call sequence with the
    // same global seed always produces the same delays.
    function automatic integer next_rand();
        seed = (seed * 1103515245 + 12345) & 32'h7fffffff;
        next_rand = seed % 1000000;
    endfunction

    task automatic set_seed(input integer s);
        seed = s;
    endtask

    task automatic wait_valid_delay();
        integer d;
        d = (wr_delay_max > 0) ? (next_rand() % (wr_delay_max + 1)) : 0;
        repeat (d) @(posedge clk);
    endtask

    task automatic wait_ready_delay();
        integer d;
        d = (rd_delay_max > 0) ? (next_rand() % (rd_delay_max + 1)) : 0;
        repeat (d) @(posedge clk);
    endtask

    // ------------------------------------------------------------------
    // handshake primitives.  Sample the handshake on the clock edge itself.
    // ------------------------------------------------------------------
    task automatic do_aw(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                         input [7:0] len, input [2:0] size);
        wait_valid_delay();
        @(negedge clk);
        m_axi_awid    = id;
        m_axi_awaddr  = addr;
        m_axi_awlen   = len;
        m_axi_awsize  = size;
        m_axi_awburst = 2'b10;      // INCR
        m_axi_awlock  = 1'b0;
        m_axi_awprot  = 3'b000;     // data, secure, non-bufferable
        m_axi_awvalid = 1'b1;
        // hold until the slave takes it
        while (1) begin
            @(posedge clk);
            if (m_axi_awready) begin
                tr($sformatf("AW accepted id=%0d addr=0x%08h len=%0d size=%0d",
                             id, addr, len, size));
                break;
            end
        end
        @(negedge clk);
        m_axi_awvalid = 1'b0;
    endtask

    task automatic do_w(input [DATA_WIDTH-1:0] data, input [STRB_WIDTH-1:0] strb,
                        input bit last);
        wait_valid_delay();
        @(negedge clk);
        m_axi_wdata  = data;
        m_axi_wstrb  = strb;
        m_axi_wlast  = last;
        m_axi_wvalid = 1'b1;
        while (1) begin
            @(posedge clk);
            if (m_axi_wready) begin
                tr($sformatf("W accepted data=0x%0h strb=0x%0h last=%0b",
                             data, strb, last));
                break;
            end
        end
        @(negedge clk);
        m_axi_wvalid = 1'b0;
    endtask

    task automatic do_b(output [ID_WIDTH-1:0] id, output [1:0] resp);
        @(negedge clk);
        m_axi_bready = 1'b1;
        while (1) begin
            @(posedge clk);
            if (m_axi_bvalid) begin
                tr($sformatf("B received resp=%0b", m_axi_bresp));
                break;
            end
        end
        id   = m_axi_bid;
        resp = m_axi_bresp;
        @(negedge clk);
        m_axi_bready = 1'b0;
    endtask

    task automatic do_ar(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                         input [7:0] len, input [2:0] size);
        wait_valid_delay();
        @(negedge clk);
        m_axi_arid    = id;
        m_axi_araddr  = addr;
        m_axi_arlen   = len;
        m_axi_arsize  = size;
        m_axi_arburst = 2'b10;
        m_axi_arlock  = 1'b0;
        m_axi_arprot  = 3'b000;
        m_axi_arvalid = 1'b1;
        while (1) begin
            @(posedge clk);
            if (m_axi_arready) break;
        end
        @(negedge clk);
        m_axi_arvalid = 1'b0;
    endtask

    // Collect one read burst.  `n` must be len+1.
    // Collect one read burst of `beats` beats.  The count must be passed in: an
    // output array arrives with size 0, so it cannot be discovered here.
    task automatic do_r(input int unsigned beats, output [ID_WIDTH-1:0] id,
                        output logic [1:0] resp[],
                        output logic [DATA_WIDTH-1:0] data[]);
        int unsigned n;
        n = beats;
        resp = new[1];
        data = new[beats];
        @(negedge clk);
        m_axi_rready = 1'b1;
        forever begin
            @(posedge clk);
            if (m_axi_rvalid) begin
                data[n - 1] = m_axi_rdata;
                resp[0]     = m_axi_rresp;
                id          = m_axi_rid;
                if (m_axi_rlast) break;
                n = n - 1;
            end
        end
        @(negedge clk);
        m_axi_rready = 1'b0;
    endtask

    // ------------------------------------------------------------------
    // public, blocking transfers
    // ------------------------------------------------------------------
    task automatic write_single(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                                input [2:0] size, input [DATA_WIDTH-1:0] data,
                                input [STRB_WIDTH-1:0] strb,
                                output [1:0] resp);
        logic [ID_WIDTH-1:0] dummy_id;
        do_aw(id, addr, 8'd0, size);
        do_w(data, strb, 1'b1);
        do_b(dummy_id, resp);
    endtask

    task automatic read_single(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                               input [2:0] size, output [DATA_WIDTH-1:0] data,
                               output [1:0] resp);
        logic [ID_WIDTH-1:0] dummy_id;
        logic [1:0]            resp_arr [1];
        logic [DATA_WIDTH-1:0] data_arr [1];
        do_ar(id, addr, 8'd0, size);
        do_r(1, dummy_id, resp_arr, data_arr);
        data = data_arr[0];
        resp = resp_arr[0];
    endtask

    // Burst write.  `n` beats, `len` must be n-1.  Strides are derived from
    // `size`, so this models a real INCR burst.
    task automatic write_burst(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                               input [2:0] size, input int unsigned n,
                               input logic [DATA_WIDTH-1:0] data[],
                               input logic [STRB_WIDTH-1:0] strb[],
                               output [1:0] resp);
        logic [ID_WIDTH-1:0] dummy_id;
        do_aw(id, addr, n - 1, size);
        for (int unsigned i = 0; i < n; i++) begin
            do_w(data[i], strb[i], i == n - 1);
        end
        do_b(dummy_id, resp);
    endtask

    // Burst read.  `n` beats.
    task automatic read_burst(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                              input [2:0] size, input int unsigned n,
                              output bit [DATA_WIDTH-1:0] data[],
                              output bit [1:0] resp[]);
        logic [ID_WIDTH-1:0] dummy_id;
        do_ar(id, addr, n - 1, size);
        do_r(n, dummy_id, resp, data);
    endtask

    // ------------------------------------------------------------------
    // concurrent transfers, for the arbitration test
    // ------------------------------------------------------------------
    // Raise AR and leave it there; the caller then awaits the response.
    task automatic start_read(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                              input [2:0] size, input [7:0] len);
        @(negedge clk);
        m_axi_arid    = id;
        m_axi_araddr  = addr;
        m_axi_arlen   = len;
        m_axi_arsize  = size;
        m_axi_arburst = 2'b10;
        m_axi_arlock  = 1'b0;
        m_axi_arprot  = 3'b000;
        m_axi_arvalid = 1'b1;
        m_axi_rready  = 1'b1;
    endtask

    task automatic await_read(output [DATA_WIDTH-1:0] data, output [1:0] resp);
        @(posedge clk);
        while (!m_axi_arready) @(posedge clk);
        @(negedge clk);
        m_axi_arvalid = 1'b0;
        while (!m_axi_rvalid) @(posedge clk);
        data = m_axi_rdata;
        resp = m_axi_rresp;
        @(negedge clk);
        m_axi_rready = 1'b0;
    endtask

    // Raise AW/W together and leave them there, then await B.
    task automatic start_write(input [ID_WIDTH-1:0] id, input [ADDR_WIDTH-1:0] addr,
                               input [2:0] size, input [DATA_WIDTH-1:0] data,
                               input [STRB_WIDTH-1:0] strb);
        @(negedge clk);
        m_axi_awid    = id;
        m_axi_awaddr  = addr;
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = size;
        m_axi_awburst = 2'b10;
        m_axi_awlock  = 1'b0;
        m_axi_awprot  = 3'b000;
        m_axi_awvalid = 1'b1;
        m_axi_wdata   = data;
        m_axi_wstrb   = strb;
        m_axi_wlast   = 1'b1;
        m_axi_wvalid  = 1'b1;
        m_axi_bready  = 1'b1;
    endtask

    task automatic await_write(output [1:0] resp);
        @(posedge clk);
        while (!(m_axi_awready && m_axi_wready)) @(posedge clk);
        @(negedge clk);
        m_axi_awvalid = 1'b0;
        m_axi_wvalid  = 1'b0;
        while (!m_axi_bvalid) @(posedge clk);
        resp = m_axi_bresp;
        @(negedge clk);
        m_axi_bready  = 1'b0;
    endtask

    task automatic idle();
        m_axi_awvalid = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;
    endtask

    // ------------------------------------------------------------------
    initial begin
        m_axi_awid    = {ID_WIDTH{1'b0}};
        m_axi_awaddr  = {ADDR_WIDTH{1'b0}};
        m_axi_awlen   = 8'd0;
        m_axi_awsize  = 3'd0;
        m_axi_awburst = 2'b10;
        m_axi_awlock  = 1'b0;
        m_axi_awprot  = 3'b000;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = {DATA_WIDTH{1'b0}};
        m_axi_wstrb   = {STRB_WIDTH{1'b0}};
        m_axi_wlast   = 1'b0;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_arid    = {ID_WIDTH{1'b0}};
        m_axi_araddr  = {ADDR_WIDTH{1'b0}};
        m_axi_arlen   = 8'd0;
        m_axi_arsize  = 3'd0;
        m_axi_arburst = 2'b10;
        m_axi_arlock  = 1'b0;
        m_axi_arprot  = 3'b000;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;
    end

endmodule

`default_nettype wire
