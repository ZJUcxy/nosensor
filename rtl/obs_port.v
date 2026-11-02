`timescale 1ns / 1ps
// 谷点写快照。accept/drop 与 pwm_tick 组合对齐，供同一沿的角度模块使用。
// ω_step 对应参考模型 omega_step_from_speed。
module obs_port (
    input  wire               pwm_tick_i,
    input  wire [15:0]        valley_cnt_i,
    input  wire signed [31:0] ialpha_i,
    input  wire signed [31:0] ibeta_i,
    input  wire signed [31:0] ualpha_i,
    input  wire signed [31:0] ubeta_i,
    input  wire               pend_i,
    input  wire [31:0]        theta_in_i,
    input  wire signed [31:0] speed_in_i,
    input  wire [15:0]        seq_echo_i,
    output reg  [15:0]        snap_seq_o,
    output reg  signed [31:0] snap_ua_o,
    output reg  signed [31:0] snap_ub_o,
    output reg  signed [31:0] snap_ia_o,
    output reg  signed [31:0] snap_ib_o,
    output wire               accept_o,
    output wire               drop_o,
    output wire [31:0]        theta_use_o,
    output wire signed [31:0] omega_step_o,
    output wire [4:0]         n_o,
    input  wire               clk_100m_i,
    input  wire               rst_n_i
);
    localparam signed [31:0] SPEED_K = 32'sd1791925356;

    wire [15:0] n_now = valley_cnt_i - seq_echo_i;
    wire signed [63:0] wprod = speed_in_i * SPEED_K;

    assign accept_o     = pwm_tick_i & pend_i & (n_now <= 16'd20);
    assign drop_o       = pwm_tick_i & pend_i & (n_now > 16'd20);
    assign theta_use_o  = theta_in_i;
    assign omega_step_o = wprod[63:32];
    assign n_o          = n_now[4:0];

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            snap_seq_o <= 16'd0;
            snap_ua_o  <= 32'sd0;
            snap_ub_o  <= 32'sd0;
            snap_ia_o  <= 32'sd0;
            snap_ib_o  <= 32'sd0;
        end else if (pwm_tick_i) begin
            snap_seq_o <= valley_cnt_i;
            snap_ua_o  <= ualpha_i;
            snap_ub_o  <= ubeta_i;
            snap_ia_o  <= ialpha_i;
            snap_ib_o  <= ibeta_i;
        end
    end
endmodule
