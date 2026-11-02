`timescale 1ns / 1ps
// 谷点外推。受理时对齐到当前谷点并清年龄；否则按旧步长前进。复位年龄为 65535，链路在第一次受理前不算正常。
module theta_interp (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire               pwm_tick_i,
    input  wire               accept_i,
    input  wire [31:0]        theta_in_i,
    input  wire signed [31:0] omega_step_i,
    input  wire [4:0]         n_i,
    input  wire signed [7:0]  angle_lead_i,
    output wire [31:0]        theta_now_o,
    output wire [31:0]        theta_park_o,
    output wire signed [31:0] omega_step_o,
    output wire [15:0]        link_age_o
);
    reg [31:0]        theta_now;
    reg signed [31:0] step_hold;
    reg [15:0]        age;

    wire signed [31:0] n_s    = {27'd0, n_i};
    wire signed [63:0] nprod  = n_s * omega_step_i;
    wire signed [39:0] lprod  = angle_lead_i * step_hold;

    assign theta_now_o  = theta_now;
    assign omega_step_o = step_hold;
    assign link_age_o   = age;
    assign theta_park_o = theta_now + lprod[31:0];

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            theta_now <= 32'd0;
            step_hold <= 32'sd0;
            age       <= 16'hffff;
        end else if (pwm_tick_i && accept_i) begin
            theta_now <= theta_in_i + nprod[31:0];
            step_hold <= omega_step_i;
            age       <= 16'd0;
        end else if (pwm_tick_i) begin
            theta_now <= theta_now + step_hold;
            if (age != 16'hffff)
                age <= age + 16'd1;
        end
    end
endmodule
