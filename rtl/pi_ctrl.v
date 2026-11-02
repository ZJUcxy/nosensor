`timescale 1ns / 1ps
module pi_ctrl (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire               step_i,
    input  wire signed [31:0] ref_i,
    input  wire signed [31:0] fb_i,
    input  wire signed [31:0] kp_i,
    input  wire signed [31:0] ki_i,
    input  wire               enable_i,
    input  wire               freeze_i,
    output wire signed [31:0] out_o
);
`include "fxp_pkg.vh"
    reg signed [31:0] integ;

    wire signed [32:0] err_w = {ref_i[31], ref_i} - {fb_i[31], fb_i};
    wire signed [31:0] err   = sat_s64({{31{err_w[32]}}, err_w});
    wire signed [63:0] prod_p = kp_i * err;
    wire signed [63:0] prod_i = ki_i * err;
    wire signed [31:0] prop   = sat_s64(prod_p >>> 16);
    wire signed [31:0] iadd   = sat_s64(prod_i >>> 16);
    wire signed [31:0] sum    = sat_add32(prop, integ);

    assign out_o = enable_i ? sum : 32'sd0;

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i)
            integ <= 32'sd0;
        else if (!enable_i)
            integ <= 32'sd0;
        else if (step_i && !freeze_i)
            integ <= sat_add32(integ, iadd);
    end
endmodule
