//==============================================================================
// tb_if_drag.v —— I/f 强拖模块自校验测试平台
//==============================================================================
// 仿真（Icarus 示例）：
//   iverilog -o tb.out ../rtl/if_drag.v tb_if_drag.v
//   vvp tb.out          // 期望最后一行 "SIM PASS"
//
// 说明：CLK_DIV 参数在 TB 中改为 8 以加速仿真（每 8 个时钟一个载波节拍，
//       各算术常数的"每拍"语义不变）。期望值表由 Python 按 RTL 公式预计算：
//       slope_in=4268288(Q8.8≈16673Hz/s) → 每拍 +43705 Q0.16
//       target 1000rpm/4对极 → f_tgt=4369000 Q0.16（66.666 Hz），第 100 拍到达
//       电角度期望：tick 1/50/99/100/101/150/200 → 1000/1278/2081/2103/2125/3195/4288
//==============================================================================
`timescale 1ns / 1ps

module tb_if_drag;

    reg clk = 1'b0;
    always #1.953125 clk = ~clk;          // 256 MHz

    reg        rst_n = 1'b0;
    reg        enable = 1'b0;
    reg [31:0] theta_start = 32'd1000;
    reg [31:0] slope_in    = 32'd4268288; // Q8.8 ≈ 16673 Hz/s
    reg [31:0] target_rpm  = 32'd256000;  // Q8.8 = 1000 rpm

    wire [31:0] theta_out, i_out;
    wire        done, reached;

    if_drag #(
        .CLK_DIV(8), .P_POLE_PAIRS(4), .P_I_F_Q8(32'd2560)
    ) u_dut (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .theta_start(theta_start), .slope_in(slope_in), .target_rpm(target_rpm),
        .theta_out(theta_out), .i_out(i_out), .done(done), .reached(reached)
    );

    integer errs = 0;

    // ---------------- 节拍镜像（与 DUT 同相位） ----------------
    reg [13:0] m_cnt = 14'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     m_cnt <= 14'd0;
        else if (m_cnt == 14'd7) m_cnt <= 14'd0;
        else            m_cnt <= m_cnt + 14'd1;
    end
    wire m_tick = (m_cnt == 14'd7);

    // ---------------- 期望模型（与 RTL 同公式，64 位不舍尾） ----------------
    reg        m_run = 1'b0, m_reach = 1'b0;
    reg [31:0] m_f = 32'd0, m_theta = 32'd0, m_i = 32'd0;
    reg [63:0] m_acc = 64'd0;
    reg [31:0] m_tickcnt = 32'd0;

    always @(posedge clk) begin
        if (!rst_n) begin
            m_run=0; m_f=0; m_acc=0; m_theta=0; m_i=0; m_reach=0; m_tickcnt=0;
        end else if (!enable) begin
            m_run = 1'b0; m_i = 32'd0; m_reach = 1'b0;
        end else if (!m_run) begin
            m_run = 1'b1;
            m_f   = 32'd0;
            m_acc = {19'd0, theta_start[12:0], 32'd0};
            m_theta = {19'd0, theta_start[12:0]};
            m_i     = 32'd2560;
            m_reach = 1'b0;
            m_tickcnt = 32'd0;                  // 重新使能：节拍计数清零
        end else if (m_tick) begin : tick_update
            reg [63:0] p1, p2, p3;
            reg [31:0] si, ft, fr, fnext;
            reg        clamp;
            m_tickcnt = m_tickcnt + 1;
            p1  = {32'd0, slope_in} * 32'd10737;   si = p1[51:20];
            p2  = {32'd0, target_rpm} * 32'd4369;  ft = p2[39:8];
            fr  = m_f + si;
            clamp = (fr >= ft) || (ft == 32'd0);
            fnext = clamp ? ft : fr;
            m_f  = fnext;
            p3   = {32'd0, fnext} * 32'd21475;
            m_acc   = m_acc + p3;
            m_theta = m_acc[44:32];
            m_reach = clamp;
        end
    end

    // ---------------- 逐拍比对（negedge 时输出已稳定） ----------------
    always @(negedge clk) begin
        if (theta_out !== m_theta) begin
            errs = errs + 1;
            $display("FAIL t=%0t theta: got=%0d expect=%0d", $time, theta_out, m_theta);
        end
        if (i_out !== m_i) begin
            errs = errs + 1;
            $display("FAIL t=%0t i_out: got=%0d expect=%0d", $time, i_out, m_i);
        end
        if (reached !== m_reach) begin
            errs = errs + 1;
            $display("FAIL t=%0t reached: got=%0b expect=%0b", $time, reached, m_reach);
        end
    end

    // done 脉宽恒为 1 clk
    reg done_prev = 1'b0;
    always @(posedge clk) begin
        if (done && done_prev) begin
            errs = errs + 1;
            $display("FAIL t=%0t done pulse width > 1 clk", $time);
        end
        done_prev <= done;
    end

    // ---------------- 辅助任务 ----------------
    task wait_tick;
        begin
            @(posedge done);
        end
    endtask

    task chk;
        input integer tk;
        input integer exp_th;
        begin
            if (m_tickcnt !== tk[31:0]) begin
                errs = errs + 1;
                $display("FAIL tickcnt=%0d expect %0d", m_tickcnt, tk);
            end
            if (theta_out < exp_th - 1 || theta_out > exp_th + 1) begin
                errs = errs + 1;
                $display("FAIL tick%0d theta=%0d expect~%0d", tk, theta_out, exp_th);
            end
        end
    endtask

    // ---------------- 激励 ----------------
    initial begin
        #100;
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
        repeat (20) @(posedge clk);

        // 空闲期：输出为 0（done 节拍仍输出）
        if (theta_out !== 32'd0 || i_out !== 32'd0 || reached !== 1'b0) begin
            errs = errs + 1; $display("FAIL idle outputs");
        end

        // 使能与节拍对齐：在 tick 之后 2 拍使能，保证首个 done 对应第 1 个外推节拍
        while (m_cnt != 14'd7) @(posedge clk);
        @(posedge clk); @(posedge clk);      // 现在 m_cnt == 2

        // ---- 场景1：拖动到目标（1000 rpm） ----
        enable = 1'b1;
        wait_tick;          chk(1,   1000);
        repeat (49) wait_tick; chk(50,  1278);
        repeat (49) wait_tick; chk(99,  2081);
        wait_tick;          chk(100, 2103);
        wait_tick;          chk(101, 2125);
        if (reached !== 1'b1) begin
            errs = errs + 1; $display("FAIL reached not set at tick100");
        end
        repeat (49) wait_tick; chk(150, 3195);
        repeat (50) wait_tick; chk(200, 4288);

        // ---- 场景2：停拖：电流清零、到达标志清零、角度保持 ----
        enable = 1'b0;
        repeat (10) @(posedge clk);
        if (i_out !== 32'd0 || reached !== 1'b0) begin
            errs = errs + 1; $display("FAIL disable: i_out=%0d reached=%0b", i_out, reached);
        end
        repeat (16) @(posedge clk);          // 跨两个 tick：角度必须保持
        if (theta_out < 4287 || theta_out > 4289) begin
            errs = errs + 1; $display("FAIL disable: theta hold (got %0d)", theta_out);
        end

        // ---- 场景3：重新使能 → 从启动角重拖 ----
        enable = 1'b1;
        wait_tick; chk(1, 1000);

        // ---- 场景4：斜率为 0 → 频率恒 0、角度保持、reached=0 ----
        enable = 1'b0;
        repeat (10) @(posedge clk);
        slope_in = 32'd0;
        enable = 1'b1;
        wait_tick;
        repeat (10) wait_tick;
        if (theta_out !== 32'd1000) begin
            errs = errs + 1; $display("FAIL slope=0 hold (got %0d)", theta_out);
        end
        if (reached !== 1'b0) begin
            errs = errs + 1; $display("FAIL slope=0 reached");
        end

        // ---- 场景5：运行中复位 ----
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        if (theta_out !== 32'd0 || i_out !== 32'd0 || done !== 1'b0) begin
            errs = errs + 1; $display("FAIL reset outputs");
        end
        rst_n = 1'b1;

        if (errs == 0) $display("SIM PASS");
        else           $display("SIM FAIL: %0d errors", errs);
        $finish;
    end

endmodule
