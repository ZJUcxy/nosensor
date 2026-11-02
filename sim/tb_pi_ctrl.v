`timescale 1ns / 1ps
module tb_pi_ctrl;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, step = 0, en = 0, fr = 0;
    reg signed [31:0] ref, fb, kp, ki;
    wire signed [31:0] y;
    pi_ctrl dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .step_i(step),
        .ref_i(ref), .fb_i(fb), .kp_i(kp), .ki_i(ki),
        .enable_i(en), .freeze_i(fr), .out_o(y)
    );
    integer held;
    initial begin
        ref = 1000; fb = 0; kp = 32'h00010000; ki = 32'h00010000;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); en = 1; step = 1;
        @(posedge clk);
        @(negedge clk); step = 0;
        if (y <= 0) $fatal(1, "prop %d", y);
        held = y;
        @(negedge clk); fr = 1; step = 1;
        @(posedge clk);
        @(negedge clk); step = 0;
        if (y !== held) $fatal(1, "freeze changed %d %d", y, held);
        @(negedge clk); fr = 0; en = 0;
        @(posedge clk);
        if (y !== 0) $fatal(1, "disable");
        $display("PASS tb_pi_ctrl");
        $finish;
    end
endmodule
