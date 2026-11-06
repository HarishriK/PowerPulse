// -----------------------------------------------------------------------------
// pp_sim_status_dev
//
// Simulation-only AXI4-Lite slave that lets a *software* test report its own
// verdict, so every test is self-checking without a human reading a waveform
// (PROJECT_CONTEXT.md section 4, test taxonomy "Software").
//
// It is deliberately **not** synthesizable and lives in tb/, not rtl/.  The SoC
// top instantiates it only when the build defines PP_SIM; without that define
// the same slot is answered by the decode-error stub, so no simulation-only
// behaviour reaches a synthesis netlist.
//
// Register map (offsets are relative to the slot base in
// config/soc_config.yaml; the C header pp_memmap.h provides PP_STATUS_BASE)
// -----------------------------------------------------------------------------
//   0x00  STATUS   RO   bit0 DONE      a verdict has been reported
//                            bit1 PASS    1 = pass, 0 = fail
//                            bit2 HASCODE a non-zero exit code was written
//   0x04  CODE     WO   bits[7:0]      exit / diagnostic code
//   0x08  DONE     WO   bit0 PASS      write 1 with PASS=1 to report pass,
//                                        write 1 with PASS=0 to report fail
//
// Convention used by every software test (see sw/common/pp_status.h):
//   pp_status_begin(TEST_ID)   -- optional, records a test id in CODE
//   pp_status_pass() / pp_status_fail(n)
// Both end the simulation: the device prints a single machine-readable line
//
//   PP_RESULT: <test> PASS|FAIL ...
//
// which is what tools/regress.py parses.  The exact command is recorded in the
// run folder as well, so a result can always be traced back.
// -----------------------------------------------------------------------------

`default_nettype none

module pp_sim_status_dev #(
    parameter integer ADDR_WIDTH = 5,
    parameter integer DATA_WIDTH = 32,
    parameter integer STRB_WIDTH = DATA_WIDTH / 8,
    parameter integer ID_WIDTH   = 12
) (
    input  wire                       clk,
    input  wire                       rst_n,

    input  wire [ID_WIDTH-1:0]        s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_araddr,
    input  wire                       s_axi_arvalid,
    output wire                       s_axi_arready,

    output wire [ID_WIDTH-1:0]        s_axi_rid,
    output wire [DATA_WIDTH-1:0]      s_axi_rdata,
    output wire [1:0]                 s_axi_rresp,
    output wire                       s_axi_rvalid,
    input  wire                       s_axi_rready,

    input  wire [ID_WIDTH-1:0]        s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  wire                       s_axi_awvalid,
    output wire                       s_axi_awready,

    input  wire [DATA_WIDTH-1:0]      s_axi_wdata,
    input  wire [STRB_WIDTH-1:0]      s_axi_wstrb,
    input  wire                       s_axi_wvalid,
    output wire                       s_axi_wready,

    output wire [ID_WIDTH-1:0]        s_axi_bid,
    output wire [1:0]                 s_axi_bresp,
    output wire                       s_axi_bvalid,
    input  wire                       s_axi_bready
);

    localparam [1:0] RESP_OKAY = 2'b00;

    localparam [2:0] REG_STATUS = 3'd0;
    localparam [2:0] REG_CODE   = 3'd1;
    localparam [2:0] REG_DONE   = 3'd2;

    reg [31:0] code_reg;
    reg        done_reg;
    reg        pass_reg;
    reg        reported;

    // ------------------------------------------------------------------
    // read mux
    // ------------------------------------------------------------------
    reg [31:0] rdata_mux;
    always @(*) begin
        case (s_axi_araddr[2:0])
            REG_STATUS: rdata_mux = {29'd0, (code_reg != 32'd0), pass_reg, done_reg};
            REG_CODE:   rdata_mux = code_reg;
            REG_DONE:   rdata_mux = {31'd0, pass_reg};
            default:    rdata_mux = 32'hDEAD_C0DE;
        endcase
    end

    assign s_axi_arready = 1'b1;
    assign s_axi_awready = 1'b1;
    assign s_axi_wready  = 1'b1;

    reg                 r_pending;
    reg [ID_WIDTH-1:0]  r_id;
    reg                 r_done;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_pending <= 1'b0;
            r_id      <= {ID_WIDTH{1'b0}};
            r_done    <= 1'b0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                r_pending <= 1'b1;
                r_id      <= s_axi_arid;
            end else if (s_axi_rvalid && s_axi_rready) begin
                r_pending <= 1'b0;
            end
            if (s_axi_rvalid && s_axi_rready) r_done <= 1'b0;
        end
    end

    assign s_axi_rid    = r_id;
    assign s_axi_rdata  = rdata_mux;
    assign s_axi_rresp  = RESP_OKAY;
    assign s_axi_rvalid = r_pending;

    // ------------------------------------------------------------------
    // write handling
    // ------------------------------------------------------------------
    reg                 w_pending;
    reg [ID_WIDTH-1:0]  w_id;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_pending <= 1'b0;
            w_id      <= {ID_WIDTH{1'b0}};
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                w_pending <= 1'b1;
                w_id      <= s_axi_awid;
            end else if (s_axi_bvalid && s_axi_bready) begin
                w_pending <= 1'b0;
            end
        end
    end

    assign s_axi_bid    = w_id;
    assign s_axi_bresp  = RESP_OKAY;
    assign s_axi_bvalid = w_pending;

    // A write is complete when W has been accepted after the address.
    wire w_beat = w_pending && s_axi_wvalid && s_axi_wready;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            code_reg <= 32'd0;
            done_reg <= 1'b0;
            pass_reg <= 1'b0;
        end else if (w_beat) begin
            case (s_axi_awaddr[2:0])
                REG_CODE: begin
                    if (s_axi_wstrb[0]) code_reg[7:0] <= s_axi_wdata[7:0];
                end
                REG_DONE: begin
                    if (s_axi_wstrb[0]) begin
                        done_reg <= 1'b1;
                        pass_reg <= s_axi_wdata[0];
                    end
                end
                default: begin
                    // STATUS is read-only
                end
            endcase
        end
    end

    // ------------------------------------------------------------------
    // reporting: one machine-readable line, then stop
    // ------------------------------------------------------------------
    reg report_armed;
    initial begin
        report_armed = 1'b0;
    end

    always @(posedge clk) begin
        if (rst_n && done_reg && !reported) begin
            reported <= 1'b1;
            if (pass_reg) begin
                $display("PP_RESULT: PASS code=%0d", code_reg);
            end else begin
                $display("PP_RESULT: FAIL code=%0d", code_reg);
            end
            $finish;
        end
    end

    wire _unused_ok = &{1'b0, r_done, report_armed};

endmodule

`default_nettype wire
