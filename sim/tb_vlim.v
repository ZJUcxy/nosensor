`timescale 1ns / 1ps
module tb_vlim;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, start = 0;
    reg signed [31:0] ud, uq, umax;
    wire signed [31:0] o_d, o_q;
    wire lim, done;
    vlim dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .start_i(start),
        .ud_i(ud), .uq_i(uq), .umax_i(umax),
        .ud_o(o_d), .uq_o(o_q), .limited_o(lim), .done_o(done)
    );
    initial begin
        ud = 32'h10000000; uq = 32'h10000000; umax = 32'h7fffffff;
        repeat (4) @(posedge clk); rst_n = 1;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait (done); @(posedge clk);
        if (lim !== 0 || o_d !== ud || o_q !== uq) $fatal(1, "pass %d %d %b", o_d, o_q, lim);
        @(negedge clk); ud = 32'h60000000; uq = 32'h60000000; umax = 32'h20000000;
        @(negedge clk); start = 1; @(negedge clk); start = 0;
        wait (done); @(posedge clk);
        if (lim !== 1) $fatal(1, "expected limit");
        if (o_d < 0 || o_q < 0) $fatal(1, "sign");
        if (o_d > umax || o_q > umax) $fatal(1, "mag %d %d", o_d, o_q);
        $display("PASS tb_vlim %d %d", o_d, o_q);
        $finish;
    end
endmodule
