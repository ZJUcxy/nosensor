`timescale 1ns / 1ps
module park_ipark (
    input  wire signed [31:0] ialpha_i,
    input  wire signed [31:0] ibeta_i,
    input  wire signed [31:0] ud_i,
    input  wire signed [31:0] uq_i,
    input  wire signed [31:0] sin_i,
    input  wire signed [31:0] cos_i,
    output wire signed [31:0] id_o,
    output wire signed [31:0] iq_o,
    output wire signed [31:0] ualpha_o,
    output wire signed [31:0] ubeta_o
);
`include "fxp_pkg.vh"
    wire signed [63:0] mul_ac = ialpha_i * cos_i;
    wire signed [63:0] mul_bs = ibeta_i  * sin_i;
    wire signed [63:0] mul_as = ialpha_i * sin_i;
    wire signed [63:0] mul_bc = ibeta_i  * cos_i;
    wire signed [63:0] mul_uc = ud_i * cos_i;
    wire signed [63:0] mul_us = uq_i * sin_i;
    wire signed [63:0] mul_vs = ud_i * sin_i;
    wire signed [63:0] mul_vc = uq_i * cos_i;

    wire signed [64:0] sum_id = {mul_ac[63], mul_ac} + {mul_bs[63], mul_bs};
    wire signed [64:0] sum_iq = {mul_bc[63], mul_bc} - {mul_as[63], mul_as};
    wire signed [64:0] sum_ua = {mul_uc[63], mul_uc} - {mul_us[63], mul_us};
    wire signed [64:0] sum_ub = {mul_vs[63], mul_vs} + {mul_vc[63], mul_vc};

    assign id_o     = sat_s64(sum_id >>> 31);
    assign iq_o     = sat_s64(sum_iq >>> 31);
    assign ualpha_o = sat_s64(sum_ua >>> 31);
    assign ubeta_o  = sat_s64(sum_ub >>> 31);
endmodule
