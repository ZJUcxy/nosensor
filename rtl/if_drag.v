`timescale 1ns / 1ps
// I/F 拖动：电流闭环、电角度开环，把 PMSM 拖到设定机械转速。
// 256 MHz 分频出 25 kHz 计算使能。每个载波周期把转速按斜率靠向目标，
// 再把该转速积分成电角度。使能期间输出拖动电流，作为电流环 PI 的 Iq 给定；Id 给定取 0。
//
// 电机为 4 对极。SVPWM 电角度一圈 8192 个细分，1000 线编码器不参与无感积分。
//   Δθ = n_rpm * 4 * 8192 / (60 * 25000) = n_rpm * 2048 / 93750
// 1000 r/min 的平均步距是 21.8453。余数保留，长期转速不累计截断误差。
//
// 目标转速单位 r/min，拖到 1000 r/min 时 spd_tgt_i = 1000（反向为负）。
// 斜率单位 (r/min)/s，只表示变化快慢。斜率为 0 时角度停在启动电角度，只输出电流，用于定位。
// 控制量在每个载波周期开头采样，角度、电流和 calc_en_o 在该周期最后一个时钟同时更新。
// 下游在下一个时钟沿看到 calc_en_o 为 1 时，theta_o / i_ref_o 已是本拍新值。
//
// 256 MHz 下每拍只保留一条进位链。除法先比较、下一拍才移入 div_quo。
// 两个除数都小于 2^17，恢复余数用 18 位，不再做 33 位比较。
module if_drag (
    input  wire               clk_256m_i,
    input  wire               rst_n_i,
    input  wire               enable_i,
    input  wire [31:0]        theta_start_i,
    input  wire [31:0]        slope_i,
    input  wire signed [31:0] spd_tgt_i,
    input  wire signed [31:0] i_ref_i,
    output reg  [31:0]        theta_o,
    output reg  signed [31:0] i_ref_o,
    output reg                calc_en_o
);
    localparam integer CLK_HZ        = 256_000_000;
    localparam integer CARRIER_HZ    = 25_000;
    localparam integer POLE_PAIRS    = 4;
    localparam integer THETA_MOD     = 8192;
    localparam integer CLK_DIV       = CLK_HZ / CARRIER_HZ;
    localparam [13:0]  DIV_LAST      = CLK_DIV - 1;
    localparam integer SLOPE_DEN     = CARRIER_HZ;
    localparam integer ANGLE_NUM_RAW = POLE_PAIRS * THETA_MOD;
    localparam integer ANGLE_DEN_RAW = 60 * CARRIER_HZ;
    localparam integer ANGLE_GCD     = 16;
    localparam integer ANGLE_NUM     = ANGLE_NUM_RAW / ANGLE_GCD;
    localparam integer ANGLE_DEN     = ANGLE_DEN_RAW / ANGLE_GCD;

    localparam [3:0] PH_READY   = 4'd0;
    localparam [3:0] PH_DIV_S_C = 4'd1;
    localparam [3:0] PH_DIV_S_S = 4'd2;
    localparam [3:0] PH_APP_AS  = 4'd3;
    localparam [3:0] PH_APP_MUX = 4'd4;
    localparam [3:0] PH_APP_ABS = 4'd5;
    localparam [3:0] PH_ANG_LD  = 4'd6;
    localparam [3:0] PH_DIV_A_C = 4'd7;
    localparam [3:0] PH_DIV_A_S = 4'd8;
    localparam [3:0] PH_WRAP_A  = 4'd9;
    localparam [3:0] PH_WRAP_M  = 4'd10;

    reg [13:0]        cnt;
    reg [3:0]         phase;
    reg               en_d;
    reg signed [31:0] spd;
    reg signed [31:0] spd_next;
    reg signed [31:0] tgt_q;
    reg [31:0]        slope_rem;
    reg [31:0]        slope_rem_next;
    reg [31:0]        frac;
    reg [31:0]        frac_next;
    reg [31:0]        theta_work;
    reg [31:0]        theta_next;
    reg signed [31:0] i_cap;
    reg signed [31:0] i_next;

    reg [63:0] div_num;
    reg [31:0] div_den;
    reg [31:0] div_rem;
    reg [63:0] div_quo;
    reg [6:0]  div_left;

    // 比较和减法的结果。div_quo 只使用上一拍已经对齐的 ge_r。
    reg        ge_r;
    reg [16:0] sub_r;
    reg [16:0] keep_r;

    reg signed [32:0] sum33;
    reg signed [32:0] diff33;
    reg [31:0]        spd_mag;
    reg               dir_add;
    reg [13:0]        add_v;
    reg [13:0]        sub_v;
    reg [13:0]        bias;
    reg               ge_b;

    wire [17:0] den18 = div_den[17:0];
    wire [17:0] rem_s = {div_rem[16:0], div_num[63]};
    wire [17:0] sub_c = rem_s - den18;
    wire [13:0] wrap_u = bias + {1'b0, theta_work[12:0]};

`ifndef SYNTHESIS
    initial begin
        if (CLK_DIV != 10240)
            $error("carrier divider is not 10240");
        if ((ANGLE_NUM_RAW / ANGLE_NUM) != (ANGLE_DEN_RAW / ANGLE_DEN))
            $error("electrical angle scale reduced incorrectly");
        if (ANGLE_NUM != 2048 || ANGLE_DEN != 93750)
            $error("unexpected angle fraction");
    end
`endif

    always @(posedge clk_256m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cnt            <= 14'd0;
            phase          <= PH_READY;
            en_d           <= 1'b0;
            spd            <= 32'sd0;
            spd_next       <= 32'sd0;
            tgt_q          <= 32'sd0;
            slope_rem      <= 32'd0;
            slope_rem_next <= 32'd0;
            frac           <= 32'd0;
            frac_next      <= 32'd0;
            theta_work     <= 32'd0;
            theta_next     <= 32'd0;
            i_cap          <= 32'sd0;
            i_next         <= 32'sd0;
            div_num        <= 64'd0;
            div_den        <= 32'd1;
            div_rem        <= 32'd0;
            div_quo        <= 64'd0;
            div_left       <= 7'd0;
            ge_r           <= 1'b0;
            sub_r          <= 17'd0;
            keep_r         <= 17'd0;
            sum33          <= 33'sd0;
            diff33         <= 33'sd0;
            spd_mag        <= 32'd0;
            dir_add        <= 1'b1;
            add_v          <= 14'd0;
            sub_v          <= 14'd0;
            bias           <= 14'd0;
            ge_b           <= 1'b0;
            theta_o        <= 32'd0;
            i_ref_o        <= 32'sd0;
            calc_en_o      <= 1'b0;
        end else begin
            // 18 位比较 + 18 位减法，结果锁存。不和 div_quo 的移位放在同一拍。
            ge_r   <= (rem_s >= den18);
            sub_r  <= sub_c[16:0];
            keep_r <= rem_s[16:0];

            if (cnt == DIV_LAST) begin
                cnt       <= 14'd0;
                calc_en_o <= 1'b1;
                spd       <= spd_next;
                slope_rem <= slope_rem_next;
                frac      <= frac_next;
                theta_o   <= theta_next;
                i_ref_o   <= i_next;
            end else begin
                cnt       <= cnt + 14'd1;
                calc_en_o <= 1'b0;
            end

            case (phase)
                PH_READY: begin
                    if (cnt == 14'd0) begin
                        en_d <= enable_i;
                        if (!enable_i) begin
                            spd_next       <= 32'sd0;
                            slope_rem_next <= 32'd0;
                            frac_next      <= 32'd0;
                            theta_next     <= {19'd0, theta_start_i[12:0]};
                            i_next         <= 32'sd0;
                        end else begin
                            if (!en_d)
                                theta_work <= {19'd0, theta_start_i[12:0]};
                            else
                                theta_work <= theta_o;
                            i_cap     <= i_ref_i;
                            tgt_q     <= spd_tgt_i;
                            div_num   <= {32'd0, slope_rem} + {32'd0, slope_i};
                            div_den   <= SLOPE_DEN;
                            div_rem   <= 32'd0;
                            div_quo   <= 64'd0;
                            div_left  <= 7'd64;
                            phase     <= PH_DIV_S_C;
                        end
                    end
                end
                PH_DIV_S_C: phase <= PH_DIV_S_S;
                PH_DIV_S_S: begin
                    // div_quo[0] 只来自寄存器 ge_r，移位本身没有算术进位链。
                    div_rem  <= ge_r ? {15'd0, sub_r} : {15'd0, keep_r};
                    div_quo  <= {div_quo[62:0], ge_r};
                    div_num  <= {div_num[62:0], 1'b0};
                    div_left <= div_left - 7'd1;
                    phase    <= (div_left == 7'd1) ? PH_APP_AS : PH_DIV_S_C;
                end
                PH_APP_AS: begin
                    // 加法和减法并行，各一条进位链。不在这一拍做越界比较。
                    sum33          <= {spd[31], spd} + {1'b0, div_quo[31:0]};
                    diff33         <= {spd[31], spd} - {1'b0, div_quo[31:0]};
                    slope_rem_next <= div_rem;
                    phase          <= PH_APP_MUX;
                end
                PH_APP_MUX: begin
                    // 只做比较和选择，输入都是上一拍的和、差。
                    if (spd < tgt_q) begin
                        if (sum33 > {tgt_q[31], tgt_q})
                            spd_next <= tgt_q;
                        else
                            spd_next <= sum33[31:0];
                    end else if (spd > tgt_q) begin
                        if (diff33 < {tgt_q[31], tgt_q})
                            spd_next <= tgt_q;
                        else
                            spd_next <= diff33[31:0];
                    end else begin
                        spd_next <= spd;
                    end
                    phase <= PH_APP_ABS;
                end
                PH_APP_ABS: begin
                    if (spd_next[31])
                        spd_mag <= -$signed(spd_next);
                    else
                        spd_mag <= spd_next;
                    dir_add <= ~spd_next[31];
                    phase   <= PH_ANG_LD;
                end
                PH_ANG_LD: begin
                    // 乘 2048 是左移 11 位，这里只剩一次加法。
                    div_num  <= {32'd0, frac} + {21'd0, spd_mag, 11'd0};
                    div_den  <= ANGLE_DEN;
                    div_rem  <= 32'd0;
                    div_quo  <= 64'd0;
                    div_left <= 7'd64;
                    phase    <= PH_DIV_A_C;
                end
                PH_DIV_A_C: phase <= PH_DIV_A_S;
                PH_DIV_A_S: begin
                    div_rem  <= ge_r ? {15'd0, sub_r} : {15'd0, keep_r};
                    div_quo  <= {div_quo[62:0], ge_r};
                    div_num  <= {div_num[62:0], 1'b0};
                    div_left <= div_left - 7'd1;
                    phase    <= (div_left == 7'd1) ? PH_WRAP_A : PH_DIV_A_C;
                end
                PH_WRAP_A: begin
                    // 三种角度修正并行计算，每种最多一条 14 位进位链。
                    add_v     <= {1'b0, theta_work[12:0]} + {1'b0, div_quo[12:0]};
                    sub_v     <= {1'b0, theta_work[12:0]} - {1'b0, div_quo[12:0]};
                    bias      <= 14'd8192 - {1'b0, div_quo[12:0]};
                    ge_b      <= theta_work[12:0] >= div_quo[12:0];
                    frac_next <= div_rem;
                    phase     <= PH_WRAP_M;
                end
                PH_WRAP_M: begin
                    if (dir_add)
                        theta_next <= {19'd0, add_v[12:0]};
                    else if (ge_b)
                        theta_next <= {19'd0, sub_v[12:0]};
                    else
                        theta_next <= {19'd0, wrap_u[12:0]};
                    i_next <= i_cap;
                    phase  <= PH_READY;
                end
                default: phase <= PH_READY;
            endcase
        end
    end
endmodule
