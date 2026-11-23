`timescale 1ns / 1ps
module tb_if_drag;
    reg clk = 0;
    always #1.953125 clk = ~clk;

    reg               rst_n = 0;
    reg               enable = 0;
    reg [31:0]        theta_start = 0;
    reg [31:0]        slope = 0;
    reg signed [31:0] spd_tgt = 0;
    reg signed [31:0] i_ref = 0;
    wire [31:0]       theta_o;
    wire signed [31:0] i_out;
    wire              calc_en;

    if_drag dut (
        .clk_256m_i(clk),
        .rst_n_i(rst_n),
        .enable_i(enable),
        .theta_start_i(theta_start),
        .slope_i(slope),
        .spd_tgt_i(spd_tgt),
        .i_ref_i(i_ref),
        .theta_o(theta_o),
        .i_ref_o(i_out),
        .calc_en_o(calc_en)
    );

    task wait_calc;
        begin
            @(posedge calc_en);
            #1;
        end
    endtask

    task check;
        input [31:0] exp_theta;
        input signed [31:0] exp_i;
        input signed [31:0] exp_spd;
        begin
            if (theta_o !== exp_theta)
                $fatal(1, "theta %0d exp %0d", theta_o, exp_theta);
            if (i_out !== exp_i)
                $fatal(1, "i %0d exp %0d", i_out, exp_i);
            if (dut.spd !== exp_spd)
                $fatal(1, "spd %0d exp %0d", dut.spd, exp_spd);
            if (theta_o > 32'd8191)
                $fatal(1, "theta range %0d", theta_o);
        end
    endtask

    initial begin
        theta_start = 32'd100;
        slope       = 32'd0;
        spd_tgt     = 32'sd1000;
        i_ref       = 32'sd80;
        enable      = 1'b0;
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;

        wait_calc();
        check(32'd100, 32'sd0, 32'sd0);
        // 脉冲本拍为高，随后 10239 拍为低，第 10240 拍再次为高。
        repeat (10239) begin
            @(posedge clk);
            #1;
            if (calc_en !== 1'b0)
                $fatal(1, "calc_en high early");
        end
        @(posedge clk);
        #1;
        if (calc_en !== 1'b1)
            $fatal(1, "carrier period");
        check(32'd100, 32'sd0, 32'sd0);

        // 斜率为 0：停在启动电角度，只给拖动电流
        enable      = 1'b1;
        theta_start = 32'd400;
        slope       = 32'd0;
        spd_tgt     = 32'sd1000;
        i_ref       = 32'sd80;
        wait_calc();
        check(32'd400, 32'sd80, 32'sd0);
        wait_calc();
        check(32'd400, 32'sd80, 32'sd0);

        // 一个载波周期升到 1000 r/min。步距 21，再之后是 22。
        slope       = 32'd25000000;
        i_ref       = 32'sd500;
        theta_start = 32'd400;
        wait_calc();
        check(32'd421, 32'sd500, 32'sd1000);
        if (dut.frac !== 32'd79250)
            $fatal(1, "frac1 %0d", dut.frac);
        wait_calc();
        check(32'd443, 32'sd500, 32'sd1000);
        if (dut.frac !== 32'd64750)
            $fatal(1, "frac2 %0d", dut.frac);
        wait_calc();
        check(32'd465, 32'sd500, 32'sd1000);

        // 载波中间改电流，要等下一次采样才生效
        @(posedge clk);
        #1;
        i_ref = 32'sd999;
        wait_calc();
        check(32'd487, 32'sd500, 32'sd1000);
        wait_calc();
        check(32'd509, 32'sd999, 32'sd1000);

        // 重新从启动角定位后再拖。8180 + 21 折回 9。
        enable = 1'b0;
        wait_calc();
        check(32'd400, 32'sd0, 32'sd0);
        enable      = 1'b1;
        theta_start = 32'd8180;
        slope       = 32'd25000000;
        spd_tgt     = 32'sd1000;
        i_ref       = 32'sd500;
        wait_calc();
        check(32'd9, 32'sd500, 32'sd1000);

        // 反向 1000 r/min：10 - 21 折回 8181
        enable = 1'b0;
        wait_calc();
        check(32'd8180, 32'sd0, 32'sd0);
        enable      = 1'b1;
        theta_start = 32'd10;
        spd_tgt     = -32'sd1000;
        i_ref       = -32'sd500;
        wait_calc();
        check(32'd8181, -32'sd500, -32'sd1000);

        // 斜率 25000 表示每个载波 +1 r/min，目标 3 r/min 后保持
        enable = 1'b0;
        wait_calc();
        check(32'd10, 32'sd0, 32'sd0);
        enable      = 1'b1;
        theta_start = 32'd50;
        slope       = 32'd25000;
        spd_tgt     = 32'sd3;
        i_ref       = 32'sd20;
        wait_calc();
        check(32'd50, 32'sd20, 32'sd1);
        if (dut.frac !== 32'd2048)
            $fatal(1, "frac slow1 %0d", dut.frac);
        wait_calc();
        check(32'd50, 32'sd20, 32'sd2);
        if (dut.frac !== 32'd6144)
            $fatal(1, "frac slow2 %0d", dut.frac);
        wait_calc();
        check(32'd50, 32'sd20, 32'sd3);
        if (dut.frac !== 32'd12288)
            $fatal(1, "frac slow3 %0d", dut.frac);
        wait_calc();
        check(32'd50, 32'sd20, 32'sd3);
        if (dut.frac !== 32'd18432)
            $fatal(1, "frac slow4 %0d", dut.frac);

        $display("PASS tb_if_drag");
        $finish;
    end
endmodule
