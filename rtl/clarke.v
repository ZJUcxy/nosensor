`timescale 1ns / 1ps
module clarke (
    input  wire signed [31:0] ia_i,
    input  wire signed [31:0] ib_i,
    output wire signed [31:0] ialpha_o,
    output wire signed [31:0] ibeta_o
);
`include "fxp_pkg.vh"
    localparam signed [31:0] INV_SQRT3 = 32'sd1239850262;
    wire signed [33:0] sum_a_2b = {{2{ia_i[31]}}, ia_i} + ({{2{ib_i[31]}}, ib_i} <<< 1);
    wire signed [65:0] prod_beta = sum_a_2b * INV_SQRT3;
    assign ialpha_o = ia_i;
    assign ibeta_o  = sat_s64(prod_beta >>> 31);
endmodule
