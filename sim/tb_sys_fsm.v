`timescale 1ns / 1ps
module tb_sys_fsm;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, en = 0, pok = 0, lock = 0, sinc = 0, clr = 0, req = 0, tick = 0;
    reg [15:0] fault; reg [1:0] phase; reg [31:0] talign;
    wire [3:0] st; wire pwm, run; wire [1:0] mode;
    sys_fsm dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .enable_i(en), .param_ok_i(pok),
        .mmcm_locked_i(lock), .sinc_ready_i(sinc), .fault_i(fault), .fault_clr_i(clr),
        .switch_req_i(req), .phase_i(phase), .pwm_tick_i(tick), .t_align_i(talign),
        .state_o(st), .pwm_enable_o(pwm), .mode_o(mode), .run_if_o(run)
    );
    initial begin
        fault = 0; phase = 0; talign = 0;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); lock = 1; sinc = 1;
        @(posedge clk); #1;
        if (st !== 1) $fatal(1, "ready %d", st);
        @(negedge clk); en = 1; pok = 1; tick = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        if (st !== 3) $fatal(1, "ramp %d", st);
        if (!pwm || mode !== 1) $fatal(1, "mode");
        @(negedge clk); en = 0; tick = 0;
        @(posedge clk); #1;
        if (st !== 1 || pwm) $fatal(1, "stop %d", st);
        @(negedge clk); fault = 1;
        @(posedge clk); #1;
        if (st !== 6) $fatal(1, "fault %d", st);
        @(negedge clk); clr = 1;
        @(posedge clk); #1;
        if (st !== 6) $fatal(1, "clr while fault");
        @(negedge clk); fault = 0; en = 0; clr = 1;
        @(posedge clk); #1;
        if (st !== 1) $fatal(1, "cleared %d", st);
        $display("PASS tb_sys_fsm");
        $finish;
    end
endmodule
