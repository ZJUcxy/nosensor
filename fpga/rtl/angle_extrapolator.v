//==============================================================================
// angle_extrapolator.v —— 电角度外推模块（FPGA 侧）
//==============================================================================
// 功能：接收 DSP 通过 5 kHz 同步信号下发的电角度/角速度，并在同步之后的
//       25 kHz 触发信号到来时逐周期外推电角度。
//
// 数据格式：
//   theta_in : 32bit 电角度，范围 0~8192，8192 = 360° 电角度（8192 归一为 0）
//   omega_in : 32bit 角速度，无符号 Q0.8，范围 0~20*2^8（即 0~5120）
//   dir      : 运动方向，1 = 电角度增加，0 = 电角度减小
//
// 行为：
//   1) sync(5 kHz) 上升沿：锁存 theta_in / omega_in / dir，
//      theta_out <= theta_in（同步优先，本次触发并入装载），触发周期计数 n 清零；
//   2) sync 之后的每个 trig(25 kHz) 上升沿：n <= n+1（上限 N_MAX），
//      theta_out <= wrap( theta_base + (omega_latch * n) >> 8 )，dir=1 加、dir=0 减；
//   3) wrap：结果对 8192 取模，输出恒在 0~8191；
//   4) 25kHz/5kHz = 5：每个同步周期内第 1 个触发与同步对齐（重新装载），
//      之后 4 个触发各外推一拍（n = 1..4），即"同步后四个周期外推"；
//   5) sync 丢失时 n 封顶在 N_MAX，角度保持最后一次外推值（不漂移），
//      待下一个 sync 重新装载；
//   6) 上电后、首次 sync 之前的 trig 被忽略（synced 标志），输出保持 0。
//
// 约束：
//   - sync/trig 脉冲宽度须 >= 3 个 clk 周期（本模块内部打两拍同步）；
//   - omega_in 有效范围 0~5120，超范围时乘加结果仍按 Q0.8 截位，不回绕出错；
//   - 单次增量 |(omega*n)>>8| <= 80 << 8192，回绕只需一次加减即可完成。
//==============================================================================

module angle_extrapolator #(
    parameter integer ANGLE_MOD  = 8192,  // 电角度模（2^13）
    parameter integer OMEGA_FRAC = 8,     // 角速度小数位（Q0.8）
    parameter integer N_MAX      = 4      // 同步后允许外推的触发周期数
)(
    input  wire        clk,        // 输入时钟 256 MHz
    input  wire        rst_n,      // 复位，低有效
    input  wire [31:0] theta_in,   // 电角度 0~8192
    input  wire [31:0] omega_in,   // 角速度 Q0.8，0~20*2^8
    input  wire        sync,       // 5 kHz 同步信号
    input  wire        trig,       // 25 kHz 触发信号
    input  wire        dir,        // 方向：1=加 0=减
    output reg  [31:0] theta_out   // 计算电角度 0~8191
);

    // ------------------------------------------------------------------
    // 异步控制信号两拍同步 + 上升沿检测
    // ------------------------------------------------------------------
    reg sync_m1, sync_m2;
    reg trig_m1, trig_m2;
    reg dir_m1,  dir_m2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_m1 <= 1'b0; sync_m2 <= 1'b0;
            trig_m1 <= 1'b0; trig_m2 <= 1'b0;
            dir_m1  <= 1'b0; dir_m2  <= 1'b0;
        end else begin
            sync_m1 <= sync;   sync_m2 <= sync_m1;
            trig_m1 <= trig;   trig_m2 <= trig_m1;
            dir_m1  <= dir;    dir_m2  <= dir_m1;
        end
    end

    wire sync_rise = sync_m1 & ~sync_m2;
    wire trig_rise = trig_m1 & ~trig_m2;

    // ------------------------------------------------------------------
    // 状态寄存器
    // ------------------------------------------------------------------
    reg        synced;      // 已收到过 sync（此前忽略 trig）
    reg [31:0] theta_base;  // sync 时刻锁存的电角度
    reg [31:0] omega_latch; // sync 时刻锁存的角速度
    reg        dir_latch;   // sync 时刻锁存的方向
    reg [ 3:0] n_period;    // 自上次 sync 起经过的触发周期数（封顶 N_MAX）

    wire [3:0] n_next = (n_period >= N_MAX[3:0]) ? n_period : (n_period + 4'd1);

    // ------------------------------------------------------------------
    // 外推计算：theta_base ± (omega_latch * n_next) >> OMEGA_FRAC
    // ------------------------------------------------------------------
    wire [31:0] prod    = omega_latch * {28'd0, n_next};
    wire [31:0] inc     = prod >> OMEGA_FRAC;

    reg signed [31:0] sum_s;    // 带符号中间和
    always @(*) begin
        if (dir_latch)
            sum_s = $signed(theta_base) + $signed(inc);
        else
            sum_s = $signed(theta_base) - $signed(inc);
    end

    // 回绕到 [0, 8191]（|增量| < 8192，一次加减即可）
    reg [31:0] theta_wrap;
    always @(*) begin
        if (sum_s < 0)
            theta_wrap = sum_s + ANGLE_MOD;
        else if (sum_s >= ANGLE_MOD)
            theta_wrap = sum_s - ANGLE_MOD;
        else
            theta_wrap = sum_s;
    end

    // ------------------------------------------------------------------
    // 主时序逻辑
    // ------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            synced      <= 1'b0;
            theta_base  <= 32'd0;
            omega_latch <= 32'd0;
            dir_latch   <= 1'b0;
            n_period    <= 4'd0;
            theta_out   <= 32'd0;
        end else begin
            if (sync_rise) begin
                // 同步优先：重新装载，n 清零
                synced      <= 1'b1;
                theta_base  <= {19'd0, theta_in[12:0]};   // 8192 归一为 0
                omega_latch <= omega_in;
                dir_latch   <= dir_m2;
                n_period    <= 4'd0;
                theta_out   <= {19'd0, theta_in[12:0]};
            end else if (trig_rise && synced) begin
                // 触发外推：n = 1..N_MAX
                n_period  <= n_next;
                theta_out <= {19'd0, theta_wrap[12:0]};
            end
        end
    end

endmodule
