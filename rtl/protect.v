`timescale 1ns / 1ps
// 故障锁存。屏蔽位不锁存。清除脉冲只放掉当前已经消失的故障源。
module protect (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire signed [31:0] ia_i,
    input  wire signed [31:0] ib_i,
    input  wire signed [31:0] ic_i,
    input  wire signed [31:0] iq_ref_i,
    input  wire signed [31:0] omega_step_i,
    input  wire               ipm_fo_i,
    input  wire [15:0]        link_age_i,
    input  wire [3:0]         state_i,
    input  wire               switch_fail_i,
    input  wire               sinc_ovf_i,
    input  wire               pwm_tick_i,
    input  wire signed [31:0] oc_th_i,
    input  wire [15:0]        oc_n_i,
    input  wire signed [31:0] ph_th_i,
    input  wire [15:0]        ph_n_i,
    input  wire [31:0]        stall_t_if_i,
    input  wire [31:0]        stall_t_run_i,
    input  wire signed [31:0] w_stall_i,
    input  wire signed [31:0] i_stall_i,
    input  wire [15:0]        link_to_i,
    input  wire [15:0]        fault_mask_i,
    input  wire               fault_clr_i,
    output reg  [15:0]        fault_o,
    output wire               block_o,
    output wire [15:0]        pri_o
);
`include "fxp_pkg.vh"
    (* ASYNC_REG = "TRUE" *) reg [2:0] fo_ff;
    reg        fo_hot;
    reg [15:0] oc_cnt, ph_cnt;
    reg [31:0] stall_cnt;

    wire pwm_on = (state_i == 4'd2) || (state_i == 4'd3) || (state_i == 4'd4) || (state_i == 4'd5);
    wire startup = (state_i == 4'd2) || (state_i == 4'd3) || (state_i == 4'd4);
    wire [2:0] fo_n = {fo_ff[1:0], ipm_fo_i};

    wire over_i = (abs32(ia_i) > abs32(oc_th_i)) || (abs32(ib_i) > abs32(oc_th_i)) || (abs32(ic_i) > abs32(oc_th_i));
    wire signed [33:0] sum_abc = {{2{ia_i[31]}}, ia_i} + {{2{ib_i[31]}}, ib_i} + {{2{ic_i[31]}}, ic_i};
    wire [33:0] abs_sum = sum_abc[33] ? -sum_abc : sum_abc;
    wire over_ph = abs_sum > {2'b0, abs32(ph_th_i)};
    wire [15:0] oc_need = (oc_n_i == 0) ? 16'd1 : oc_n_i;
    wire [15:0] ph_need = (ph_n_i == 0) ? 16'd1 : ph_n_i;
    wire run_stall = (state_i == 4'd5) && (abs32(omega_step_i) < abs32(w_stall_i)) && (abs32(iq_ref_i) > abs32(i_stall_i));
    wire link_hit = ((state_i == 4'd4) || (state_i == 4'd5)) && (link_age_i > link_to_i);

    wire src_oc = over_i;
    wire src_fo = fo_hot;
    wire src_ph = pwm_on && over_ph;
    wire src_stall = startup || run_stall;
    wire src_link = link_hit;
    wire src_sinc = pwm_on && sinc_ovf_i;

    function [15:0] priority16;
        input [15:0] f;
        begin
            if (f[6]) priority16 = 16'd6;
            else if (f[0]) priority16 = 16'd0;
            else if (f[7]) priority16 = 16'd7;
            else if (f[8]) priority16 = 16'd8;
            else if (f[5]) priority16 = 16'd5;
            else if (f[4]) priority16 = 16'd4;
            else if (f[1]) priority16 = 16'd1;
            else if (f[2]) priority16 = 16'd2;
            else if (f[3]) priority16 = 16'd3;
            else if (f[9]) priority16 = 16'd9;
            else priority16 = 16'hffff;
        end
    endfunction

    assign block_o = |fault_o;
    assign pri_o = priority16(fault_o);

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            fo_ff <= 3'b111;
            fo_hot <= 1'b0;
            oc_cnt <= 0;
            ph_cnt <= 0;
            stall_cnt <= 0;
            fault_o <= 16'd0;
        end else begin
            fo_ff <= fo_n;
            if (fo_n == 3'b000)
                fo_hot <= 1'b1;
            else if (fo_n == 3'b111)
                fo_hot <= 1'b0;

            if (pwm_tick_i) begin
                if (over_i) begin
                    if (oc_cnt + 16'd1 >= oc_need)
                        oc_cnt <= oc_need;
                    else
                        oc_cnt <= oc_cnt + 16'd1;
                end else
                    oc_cnt <= 16'd0;

                if (pwm_on && over_ph) begin
                    if (ph_cnt + 16'd1 >= ph_need)
                        ph_cnt <= ph_need;
                    else
                        ph_cnt <= ph_cnt + 16'd1;
                end else
                    ph_cnt <= 16'd0;

                if (startup) begin
                    if (stall_cnt != 32'hffffffff)
                        stall_cnt <= stall_cnt + 32'd1;
                end else if (run_stall) begin
                    if (stall_cnt != 32'hffffffff)
                        stall_cnt <= stall_cnt + 32'd1;
                end else
                    stall_cnt <= 32'd0;
            end

            fault_o[1] <= 1'b0;
            fault_o[2] <= 1'b0;
            fault_o[3] <= 1'b0;
            if (fault_mask_i[0])
                fault_o[0] <= 1'b0;
            else if (fault_clr_i && !src_oc)
                fault_o[0] <= 1'b0;
            else if (oc_cnt >= oc_need && over_i)
                fault_o[0] <= 1'b1;

            if (fault_mask_i[4])
                fault_o[4] <= 1'b0;
            else if (fault_clr_i && !src_stall)
                fault_o[4] <= 1'b0;
            else if ((startup && stall_cnt >= stall_t_if_i) || (state_i == 4'd5 && stall_cnt >= stall_t_run_i && run_stall))
                fault_o[4] <= 1'b1;

            if (fault_mask_i[5])
                fault_o[5] <= 1'b0;
            else if (fault_clr_i && !src_ph)
                fault_o[5] <= 1'b0;
            else if (ph_cnt >= ph_need && src_ph)
                fault_o[5] <= 1'b1;

            if (fault_mask_i[6])
                fault_o[6] <= 1'b0;
            else if (fault_clr_i && !src_fo)
                fault_o[6] <= 1'b0;
            else if (fo_hot)
                fault_o[6] <= 1'b1;

            if (fault_mask_i[7])
                fault_o[7] <= 1'b0;
            else if (fault_clr_i && !src_link)
                fault_o[7] <= 1'b0;
            else if (link_hit)
                fault_o[7] <= 1'b1;

            if (fault_mask_i[8])
                fault_o[8] <= 1'b0;
            else if (fault_clr_i)
                fault_o[8] <= 1'b0;
            else if (switch_fail_i)
                fault_o[8] <= 1'b1;

            if (fault_mask_i[9])
                fault_o[9] <= 1'b0;
            else if (fault_clr_i && !src_sinc)
                fault_o[9] <= 1'b0;
            else if (src_sinc)
                fault_o[9] <= 1'b1;
        end
    end
endmodule
