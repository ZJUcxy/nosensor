//==============================================================================
// tb_angle_extrapolator.v —— 电角度外推模块自校验测试平台
//==============================================================================
// 仿真命令（Icarus 示例）：
//   iverilog -o tb.out ../rtl/angle_extrapolator.v tb_angle_extrapolator.v
//   vvp tb.out
// 期望输出：所有检查 OK，最终 "SIM PASS"
//==============================================================================
`timescale 1ns / 1ps

module tb_angle_extrapolator;

    reg         clk    = 1'b0;
    reg         rst_n  = 1'b0;
    reg  [31:0] theta_in;
    reg  [31:0] omega_in;
    reg         sync;
    reg         trig;
    reg         dir;

    wire [31:0] theta_out;

    integer err_cnt = 0;

    angle_extrapolator u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .theta_in (theta_in),
        .omega_in (omega_in),
        .sync     (sync),
        .trig     (trig),
        .dir      (dir),
        .theta_out(theta_out)
    );

    // ---------------- 256 MHz 时钟 ----------------
    always #1.953125 clk = ~clk;

    // ---------------- 脉冲与检查任务 ----------------
    task sync_pulse;
        begin
            sync <= 1'b1;
            repeat (4) @(posedge clk);
            sync <= 1'b0;
        end
    endtask

    task trig_pulse;
        begin
            trig <= 1'b1;
            repeat (4) @(posedge clk);
            trig <= 1'b0;
        end
    endtask

    task check;
        input [31:0] exp;
        input [127:0] label;
        begin
            repeat (20) @(posedge clk);   // 等同步链+寄存器稳定
            if (theta_out !== exp) begin
                err_cnt = err_cnt + 1;
                $display("FAIL [%0s]  got=%0d  want=%0d", label, theta_out, exp);
            end else begin
                $display("OK   [%0s]  =%0d", label, theta_out);
            end
        end
    endtask

    // ---------------- 激励 ----------------
    initial begin
        theta_in = 32'd0; omega_in = 32'd0;
        sync = 1'b0; trig = 1'b0; dir = 1'b1;

        // ---- 复位 ----
        #100;
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
        check(32'd0, "复位后输出为0");

        // ---- 首次 sync 之前触发应被忽略 ----
        trig_pulse;
        check(32'd0, "首次同步前 trig 忽略");

        // ---- 场景1: dir=1, omega=256(Q8=1.0) -> 每拍 +1 ----
        theta_in = 32'd1000; omega_in = 32'd256; dir = 1'b1;
        sync_pulse;
        check(32'd1000, "sync 装载 1000");

        #40000; trig_pulse; check(32'd1001, "外推 n=1 -> 1001");
        #40000; trig_pulse; check(32'd1002, "外推 n=2 -> 1002");
        #40000; trig_pulse; check(32'd1003, "外推 n=3 -> 1003");
        #40000; trig_pulse; check(32'd1004, "外推 n=4 -> 1004");

        // ---- 场景2: trig 与 sync 同时到达，sync 优先 ----
        theta_in = 32'd2000; omega_in = 32'd1024; dir = 1'b1;
        #40000;
        begin
            sync <= 1'b1; trig <= 1'b1;
            repeat (4) @(posedge clk);
            sync <= 1'b0; trig <= 1'b0;
        end
        check(32'd2000, "sync+trig 同拍: sync 优先装载 2000");

        #40000; trig_pulse; check(32'd2004, "n=1 -> 2004");
        #40000; trig_pulse; check(32'd2008, "n=2 -> 2008");
        #40000; trig_pulse; check(32'd2012, "n=3 -> 2012");
        #40000; trig_pulse; check(32'd2016, "n=4 -> 2016");

        // ---- 场景3: 正向回绕 8190 + 20/拍 ----
        theta_in = 32'd8190; omega_in = 32'd5120; dir = 1'b1;
        #40000; sync_pulse; check(32'd8190, "装载 8190");
        #40000; trig_pulse; check(32'd18,   "n=1 回绕 -> 18");
        #40000; trig_pulse; check(32'd38,   "n=2 回绕 -> 38");
        #40000; trig_pulse; check(32'd58,   "n=3 回绕 -> 58");
        #40000; trig_pulse; check(32'd78,   "n=4 回绕 -> 78");

        // ---- 场景4: 反向 dir=0 ----
        theta_in = 32'd10; omega_in = 32'd1024; dir = 1'b0;
        #40000; sync_pulse; check(32'd10,   "装载 10");
        #40000; trig_pulse; check(32'd6,    "n=1 反向 -> 6");
        #40000; trig_pulse; check(32'd2,    "n=2 反向 -> 2");
        #40000; trig_pulse; check(32'd8190, "n=3 反向回绕 -> 8190");
        #40000; trig_pulse; check(32'd8186, "n=4 反向 -> 8186");

        // ---- 场景5: sync 丢失时 n 封顶，角度保持 ----
        trig_pulse;
        check(32'd8186, "sync 丢失: n 封顶保持 8186");

        // ---- 场景6: 运行中复位，恢复后重新装载 ----
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        check(32'd0, "运行中复位 -> 0");
        rst_n = 1'b1;
        trig_pulse;
        check(32'd0, "复位后 trig 忽略");
        theta_in = 32'd5; omega_in = 32'd256; dir = 1'b1;
        sync_pulse;
        check(32'd5, "复位后重新 sync 装载 5");
        #40000; trig_pulse; check(32'd6, "恢复后 n=1 -> 6");

        // ---- 结论 ----
        if (err_cnt == 0)
            $display("SIM PASS");
        else
            $display("SIM FAIL: %0d 项错误", err_cnt);
        $finish;
    end

endmodule
