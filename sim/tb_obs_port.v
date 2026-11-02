`timescale 1ns / 1ps
module tb_obs_port;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, tick = 0, pend = 0;
    reg [15:0] valley, seq;
    reg signed [31:0] ia, ib, ua, ub, speed;
    reg [31:0] thin;
    wire [15:0] sseq; wire signed [31:0] sua, sub, sia, sib, w;
    wire acc, drop; wire [31:0] tuse; wire [4:0] n;
    obs_port dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .pwm_tick_i(tick), .valley_cnt_i(valley),
        .ialpha_i(ia), .ibeta_i(ib), .ualpha_i(ua), .ubeta_i(ub),
        .pend_i(pend), .theta_in_i(thin), .speed_in_i(speed), .seq_echo_i(seq),
        .snap_seq_o(sseq), .snap_ua_o(sua), .snap_ub_o(sub), .snap_ia_o(sia), .snap_ib_o(sib),
        .accept_o(acc), .drop_o(drop), .theta_use_o(tuse), .omega_step_o(w), .n_o(n)
    );
    initial begin
        ia = 1; ib = 2; ua = 3; ub = 4; thin = 32'h55; speed = 32'sd65536000;
        valley = 16'd5; seq = 16'd0; pend = 1;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); tick = 1; #1;
        if (!acc || drop || n !== 5) $fatal(1, "accept %b %b %d", acc, drop, n);
        if (w !== 32'sd27342611) $fatal(1, "omega %d", w);
        @(negedge clk); tick = 0;
        if (sseq !== 16'd5 || sia !== 1 || sua !== 3) $fatal(1, "snap");
        @(negedge clk); valley = 16'd30; seq = 16'd0; tick = 1; #1;
        if (!drop || acc) $fatal(1, "drop");
        $display("PASS tb_obs_port");
        $finish;
    end
endmodule
