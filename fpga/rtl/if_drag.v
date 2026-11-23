//==============================================================================
// if_drag.v —— I/f 强拖模块（FPGA 侧，25 kHz 载波逐周期输出）
//==============================================================================
// 功能：使能后从"启动电角度"出发，电频率按给定斜率从 0 斜坡升到目标转速对应
//       的电频率（4 对极、1000 rpm → 66.67 Hz），每个 25 kHz 载波周期输出：
//         theta_out : 电角度（8192/周，0~8191，与 SVPWM 输入一致）
//         i_out     : 电流幅值给定（给电流环 PI 做参考，PI 输出接 SVPWM 幅值）
//         done      : 25 kHz 计算完成脉冲（1 clk，角度/电流在此沿有效）
//         reached   : 已到达目标频率（供上层/DSP 做闭环切换判断）
//
// 数据格式：
//   theta_start : 32bit，启动电角度 0~8191（8192 细分/电周期）
//   slope_in    : 32bit Q8.8，电频率斜率 [Hz/s]
//                 （例：0.7 s 升到 66.7 Hz → 95.2 Hz/s → 95.2*256 = 24373）
//   target_rpm  : 32bit Q8.8，机械目标转速 [rpm]（1000 → 256000）
//   i_out       : 32bit Q0.8，电流幅值 [A]（默认 10A → 2560，需与电流反馈定标一致）
//
// 实现要点：
//   1) 25 kHz 节拍 = 256 MHz 分频（CLK_DIV=10240，整除无抖动）；
//   2) 电频率累加器 Q0.16 [Hz]：每拍 f += slope/25000
//      （斜率常数：slope_q88 * 10737 >> 20 = slope/25000 * 65536）；
//   3) 角度累加器 Q13.32：每拍 theta_acc += f_q16 * 21475
//      （f_q16*21475 = Δθ*2^32，全积不舍尾 → 分数位自然累积，无截断误差）；
//      64 位累加器按 2^64 = 2^19*2^45 自然回绕，整数位 [44:32] 永不受损；
//   4) enable 拉低：电流给定清零、角度保持、done 节拍继续（PI 闭环不停）；
//      重新使能：从 theta_start 重新开始拖动；
//   5) slope=0 时频率恒为 0，等效"定位保持"模式。
//
// 边界与约束：
//   - slope 建议 ≤ 800 Hz/s（Q8.8 ≤ 204800），超出时频率增量仍正确但不保证；
//   - theta_start ≥ 8192 时按低 13 位归一；
//   - 本模块只负责 I/f 强拖阶段；到达目标后由上层依据 reached 切到
//     DSP 观测器角度（无扰切换），不属于本模块范围。
//==============================================================================

module if_drag #(
    parameter integer P_POLE_PAIRS = 4,           // 极对数
    parameter integer CLK_DIV       = 10240,      // 256MHz / 25kHz
    parameter [31:0] P_I_F_Q8       = 32'd2560,   // I/f 电流给定 Q0.8 [A]（10A）
    parameter [31:0] P_SLOPE_K      = 32'd10737,  // slope_q88*K>>20 = slope/25000*65536
    parameter [31:0] P_THETA_K      = 32'd21475   // f_q16*K = Δθ·2^32
)(
    input  wire        clk,          // 256 MHz
    input  wire        rst_n,        // 复位，低有效
    input  wire        enable,       // 使能（高有效，重新使能则重新拖动）
    input  wire [31:0] theta_start,  // 启动电角度 0~8191
    input  wire [31:0] slope_in,     // 拖动斜率 Q8.8 [Hz/s]
    input  wire [31:0] target_rpm,   // 目标转速 Q8.8 [rpm]
    output reg  [31:0] theta_out,    // 电角度 0~8191（每载波周期更新）
    output reg  [31:0] i_out,        // 电流给定 Q0.8 [A]
    output reg         done,         // 25 kHz 计算完成脉冲（1 clk）
    output reg         reached       // 到达目标频率标志（供切换）
);

    // 目标电频率换算常数：f_q16 = rpm_q88 * F_TARGET_K >> 8
    localparam [31:0] F_TARGET_K = (P_POLE_PAIRS * 65536 + 30) / 60;

    // ------------------------------------------------------------------
    // 25 kHz 节拍产生
    // ------------------------------------------------------------------
    localparam [13:0] CLK_DIV_M1 = CLK_DIV - 1;
    reg [13:0] cnt;
    wire tick = (cnt == CLK_DIV_M1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)     cnt <= 14'd0;
        else if (tick)  cnt <= 14'd0;
        else            cnt <= cnt + 14'd1;
    end

    // ------------------------------------------------------------------
    // 组合计算：目标频率、每拍斜率增量、频率斜坡、角度外推
    // ------------------------------------------------------------------
    reg        running;      // 拖动进行中
    reg [31:0] f_q16;        // 当前电频率 Q0.16 [Hz]
    reg [63:0] theta_acc;    // 电角度累加器 Q13.32（整数位 [44:32]）

    wire [63:0] f_target_prod = {32'd0, target_rpm} * F_TARGET_K;
    wire [31:0] f_target_q16  = f_target_prod[39:8];         // >>8

    wire [63:0] slope_prod = {32'd0, slope_in} * P_SLOPE_K;
    wire [31:0] slope_inc  = slope_prod[51:20];              // >>20

    wire [31:0] f_base   = running ? f_q16 : 32'd0;
    wire [31:0] f_ramped = f_base + slope_inc;
    wire        f_clamp  = (f_ramped >= f_target_q16) || (f_target_q16 == 32'd0);
    wire [31:0] f_next   = f_clamp ? f_target_q16 : f_ramped;

    // Δθ·2^32 = f_q16 * 21475（全 64 位积，不舍尾）
    wire [63:0] theta_prod = {32'd0, f_next} * P_THETA_K;
    wire [63:0] theta_base = running ? theta_acc : {19'd0, theta_start[12:0], 32'd0};
    wire [63:0] theta_next = theta_base + theta_prod;

    // ------------------------------------------------------------------
    // 主时序逻辑
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running   <= 1'b0;
            f_q16     <= 32'd0;
            theta_acc <= 64'd0;
            theta_out <= 32'd0;
            i_out     <= 32'd0;
            done      <= 1'b0;
            reached   <= 1'b0;
        end else if (!enable) begin
            running <= 1'b0;          // 停拖：电流清零、角度保持
            i_out   <= 32'd0;
            reached <= 1'b0;
            done    <= tick;          // 载波节拍继续（电流环保持同步）
        end else if (!running) begin
            running   <= 1'b1;        // 使能边沿：装载启动角，频率从 0 起步
            f_q16     <= 32'd0;
            theta_acc <= {19'd0, theta_start[12:0], 32'd0};
            theta_out <= {19'd0, theta_start[12:0]};
            i_out     <= P_I_F_Q8;
            reached   <= 1'b0;
            done      <= tick;        // 使能与载波同拍时本拍直接输出启动角
        end else begin
            if (tick) begin
                f_q16     <= f_next;
                theta_acc <= theta_next;
                theta_out <= {19'd0, theta_next[44:32]};
                i_out     <= P_I_F_Q8;
                done      <= 1'b1;
                reached   <= f_clamp;
            end else begin
                done <= 1'b0;
            end
        end
    end

endmodule
