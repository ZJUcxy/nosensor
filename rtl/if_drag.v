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
    localparam integer CLK_HZ       = 256_000_000;
    localparam integer CARRIER_HZ   = 25_000;
    localparam integer POLE_PAIRS   = 4;
    localparam integer THETA_MOD    = 8192;
    localparam integer CLK_DIV      = CLK_HZ / CARRIER_HZ;
    localparam [13:0]  DIV_LAST     = CLK_DIV - 1;
    localparam integer SLOPE_DEN    = CARRIER_HZ;
    localparam integer ANGLE_NUM_RAW = POLE_PAIRS * THETA_MOD;
    localparam integer ANGLE_DEN_RAW = 60 * CARRIER_HZ;
    localparam integer ANGLE_GCD    = 16;
    localparam integer ANGLE_NUM    = ANGLE_NUM_RAW / ANGLE_GCD;
    localparam integer ANGLE_DEN    = ANGLE_DEN_RAW / ANGLE_GCD;

    localparam [1:0] PH_READY = 2'd0;
    localparam [1:0] PH_DIV_S = 2'd1;
    localparam [1:0] PH_DIV_A = 2'd2;

    reg [13:0]        cnt;
    reg [1:0]         phase;
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

    wire [32:0] rem_shift = {div_rem, div_num[63]};
    wire [32:0] den_ext   = {1'b0, div_den};
    wire        div_ge    = rem_shift >= den_ext;
    wire [32:0] rem_sub   = rem_shift - den_ext;

    function signed [31:0] approach;
        input signed [31:0] cur;
        input signed [31:0] tgt;
        input [31:0]        inc;
        reg signed [32:0] moved;
        begin
            if (cur < tgt) begin
                moved = {cur[31], cur} + {1'b0, inc};
                if (moved > {tgt[31], tgt})
                    approach = tgt;
                else
                    approach = moved[31:0];
            end else if (cur > tgt) begin
                moved = {cur[31], cur} - {1'b0, inc};
                if (moved < {tgt[31], tgt})
                    approach = tgt;
                else
                    approach = moved[31:0];
            end else begin
                approach = cur;
            end
        end
    endfunction

    function [31:0] wrap_theta;
        input [31:0] base;
        input [12:0] step;
        input        add;
        reg [13:0] sum;
        begin
            if (add) begin
                sum = {1'b0, base[12:0]} + {1'b0, step};
                wrap_theta = {19'd0, sum[12:0]};
            end else if (base[12:0] >= step) begin
                wrap_theta = {19'd0, base[12:0] - step};
            end else begin
                sum = (14'd8192 - {1'b0, step}) + {1'b0, base[12:0]};
                wrap_theta = {19'd0, sum[12:0]};
            end
        end
    endfunction

    function [31:0] fold_theta;
        input [31:0] raw;
        begin
            fold_theta = {19'd0, raw[12:0]};
        end
    endfunction

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
            theta_o        <= 32'd0;
            i_ref_o        <= 32'sd0;
            calc_en_o      <= 1'b0;
        end else begin
            if (cnt == DIV_LAST) begin
                cnt        <= 14'd0;
                calc_en_o  <= 1'b1;
                spd        <= spd_next;
                slope_rem  <= slope_rem_next;
                frac       <= frac_next;
                theta_o    <= theta_next;
                i_ref_o    <= i_next;
            end else begin
                cnt       <= cnt + 14'd1;
                calc_en_o <= 1'b0;
            end

            if (cnt == 14'd0 && phase == PH_READY) begin
                en_d <= enable_i;
                if (!enable_i) begin
                    spd_next       <= 32'sd0;
                    slope_rem_next <= 32'd0;
                    frac_next      <= 32'd0;
                    theta_next     <= fold_theta(theta_start_i);
                    i_next         <= 32'sd0;
                    phase          <= PH_READY;
                end else begin
                    if (!en_d)
                        theta_work <= fold_theta(theta_start_i);
                    else
                        theta_work <= theta_o;
                    i_cap    <= i_ref_i;
                    tgt_q    <= spd_tgt_i;
                    div_num  <= {32'd0, slope_rem} + {32'd0, slope_i};
                    div_den  <= SLOPE_DEN;
                    div_rem  <= 32'd0;
                    div_quo  <= 64'd0;
                    div_left <= 7'd64;
                    phase    <= PH_DIV_S;
                end
            end else if (phase == PH_DIV_S) begin
                if (div_left == 7'd0) begin : slope_done
                    reg signed [31:0] spd_calc;
                    reg [31:0]        spd_mag;
                    spd_calc        = approach(spd, tgt_q, div_quo[31:0]);
                    spd_next       <= spd_calc;
                    slope_rem_next <= div_rem;
                    spd_mag         = spd_calc[31] ? -$signed(spd_calc) : spd_calc;
                    div_num        <= {32'd0, frac} + ({32'd0, spd_mag} * ANGLE_NUM);
                    div_den        <= ANGLE_DEN;
                    div_rem        <= 32'd0;
                    div_quo        <= 64'd0;
                    div_left       <= 7'd64;
                    phase          <= PH_DIV_A;
                end else begin
                    div_left <= div_left - 7'd1;
                    div_num  <= {div_num[62:0], 1'b0};
                    div_quo  <= {div_quo[62:0], div_ge};
                    div_rem  <= div_ge ? rem_sub[31:0] : rem_shift[31:0];
                end
            end else if (phase == PH_DIV_A && div_left == 7'd0) begin
                frac_next  <= div_rem;
                theta_next <= wrap_theta(theta_work, div_quo[12:0], ~spd_next[31]);
                i_next     <= i_cap;
                phase      <= PH_READY;
            end else if (phase == PH_DIV_A) begin
                div_left <= div_left - 7'd1;
                div_num  <= {div_num[62:0], 1'b0};
                div_quo  <= {div_quo[62:0], div_ge};
                div_rem  <= div_ge ? rem_sub[31:0] : rem_shift[31:0];
            end
        end
    end
endmodule
