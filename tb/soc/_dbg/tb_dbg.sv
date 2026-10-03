`default_nettype none
`include "pp_test_lib.svh"
module tb_dbg;
    import pp_soc_cfg_pkg::*;
    logic clk, rst_n;
    pp_clk_rst #(.CLK_PERIOD_PS(PP_CLK_PERIOD_PS), .RESET_CYCLES(PP_RESET_CYCLES))
    u_clk_rst (.clk(clk), .rst_n(rst_n));
    pp_bus_harness u_h (.clk(clk), .rst_n(rst_n));

    task automatic try(input int unsigned size, input logic [63:0] data,
                       input logic [7:0] strb);
        logic [1:0] wresp, rresp;
        logic [63:0] rdata;
        u_h.m0.write_single(3'd1, PP_DMEM_BASE + 32'h200, size[2:0], data, strb, wresp);
        u_h.m0.read_single(3'd1, PP_DMEM_BASE + 32'h200, size[2:0], rdata, rresp);
        $display("[dbg] size=%0d wrote 0x%016h/0x%02h -> wresp=%0b read 0x%016h rresp=%0b %s",
                 size, data, strb, wresp, rdata, rresp,
                 (rdata === data && wresp == 0 && rresp == 0) ? "OK" : "MISMATCH");
    endtask

    initial begin
        logic [1:0] wresp, rresp;
        logic [63:0] rdata;
        wait (rst_n === 1'b1);
        repeat (4) @(posedge clk);
        try(2, 64'h00000000_CAFE0001, 8'h0F);
        try(3, 64'hDEADBEEF_CAFE0001, 8'hFF);
        try(0, 64'h00000000_000000A5, 8'h01);
        try(1, 64'h00000000_0000BEEF, 8'hF0);
        $finish;
    end
endmodule
`default_nettype wire
