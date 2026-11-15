`timescale 1ns / 1ps
module tb_elec_angle_calc;
    reg clk = 0;
    // 256 MHz
    always #1.953125 clk = ~clk;

    reg        rst_n = 0;
    reg [31:0] theta = 0;
    reg [31:0] omega = 0;
    reg        sync  = 0;
    reg        trig  = 0;
    reg        dir   = 1;
    wire [31:0] theta_o;

    elec_angle_calc dut (
        .clk_256m_i(clk),
        .rst_n_i(rst_n),
        .theta_i(theta),
        .omega_i(omega),
        .sync_5k_i(sync),
        .trig_25k_i(trig),
        .dir_i(dir),
        .theta_o(theta_o)
    );

    task pulse;
        input do_sync;
        input do_trig;
        begin
            @(negedge clk);
            sync = do_sync;
            trig = do_trig;
            @(negedge clk);
            sync = 1'b0;
            trig = 1'b0;
        end
    endtask

    task check_eq;
        input [31:0] exp;
        begin
            if (theta_o !== exp)
                $fatal(1, "got %0d exp %0d", theta_o, exp);
            if (theta_o > 32'd8192)
                $fatal(1, "out of range %0d", theta_o);
        end
    endtask

    initial begin
        theta = 32'd500;
        omega = 32'd5120;
        dir   = 1'b1;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        @(negedge clk);
        if (theta_o !== 32'd0) $fatal(1, "reset %0d", theta_o);

        // 同步之前的触发不更新
        pulse(0, 1);
        check_eq(32'd0);

        // 同步沿锁存，触发沿才推出。锁存后改输入，不能影响本拍和后续外推。
        theta = 32'd111;
        omega = 32'd5120;
        dir   = 1'b1;
        pulse(1, 0);
        theta = 32'd999;
        omega = 32'd0;
        dir   = 1'b0;
        pulse(0, 1);
        check_eq(32'd111);
        pulse(0, 1);
        check_eq(32'd131);

        // 同一沿重载。ω = 20*256 = 5120，(ω*n)>>8 = 20,40,60,80
        theta = 32'd1000;
        omega = 32'd5120;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd1000);
        theta = 32'd1;
        omega = 32'd1;
        dir   = 1'b0;
        pulse(0, 1);
        check_eq(32'd1020);
        pulse(0, 1);
        check_eq(32'd1040);
        pulse(0, 1);
        check_eq(32'd1060);
        pulse(0, 1);
        check_eq(32'd1080);
        pulse(0, 1);
        check_eq(32'd1080);

        // 先乘后移位：ω = 200 时 n = 1..4 的增量是 0,1,2,3
        theta = 32'd1000;
        omega = 32'd200;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd1000);
        pulse(0, 1);
        check_eq(32'd1000);
        pulse(0, 1);
        check_eq(32'd1001);
        pulse(0, 1);
        check_eq(32'd1002);
        pulse(0, 1);
        check_eq(32'd1003);

        // 反向，并跨过 0
        theta = 32'd50;
        omega = 32'd5120;
        dir   = 1'b0;
        pulse(1, 1);
        check_eq(32'd50);
        pulse(0, 1);
        check_eq(32'd30);
        pulse(0, 1);
        check_eq(32'd10);
        pulse(0, 1);
        check_eq(32'd8182);
        pulse(0, 1);
        check_eq(32'd8162);

        // 正向跨过 8192
        theta = 32'd8170;
        omega = 32'd5120;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd8170);
        pulse(0, 1);
        check_eq(32'd8190);
        pulse(0, 1);
        check_eq(32'd18);
        pulse(0, 1);
        check_eq(32'd38);
        pulse(0, 1);
        check_eq(32'd58);

        // 输入 8192 在同步拍保持，再走一步从整周位置继续
        theta = 32'd8192;
        omega = 32'd0;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd8192);
        pulse(0, 1);
        check_eq(32'd8192);

        theta = 32'd8192;
        omega = 32'd256;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd8192);
        pulse(0, 1);
        check_eq(32'd1);
        pulse(0, 1);
        check_eq(32'd2);

        theta = 32'd0;
        omega = 32'd256;
        dir   = 1'b0;
        pulse(1, 1);
        check_eq(32'd0);
        pulse(0, 1);
        check_eq(32'd8191);
        pulse(0, 1);
        check_eq(32'd8190);

        // 新的同步清掉周期计数，不接着上一拍往上加
        theta = 32'd2000;
        omega = 32'd5120;
        dir   = 1'b1;
        pulse(1, 1);
        check_eq(32'd2000);
        pulse(0, 1);
        check_eq(32'd2020);
        theta = 32'd300;
        pulse(1, 1);
        check_eq(32'd300);
        pulse(0, 1);
        check_eq(32'd320);

        $display("PASS tb_elec_angle_calc");
        $finish;
    end
endmodule
