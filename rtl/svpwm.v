`timescale 1ns / 1ps
// 最小最大零序注入，等价七段中心对齐。死区只推迟上升沿。安全电平在极性取反之前为 0。
module svpwm (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire signed [31:0] ualpha_i,
    input  wire signed [31:0] ubeta_i,
    input  wire               calc_done_i,
    input  wire               pwm_tick_i,
    input  wire [10:0]        carrier_cnt_i,
    input  wire [8:0]         dead_ticks_i,
    input  wire               enable_i,
    input  wire               block_i,
    input  wire               pol_inv_i,
    output wire               pwm_uh_o,
    output wire               pwm_ul_o,
    output wire               pwm_vh_o,
    output wire               pwm_vl_o,
    output wire               pwm_wh_o,
    output wire               pwm_wl_o
);
`include "fxp_pkg.vh"
    localparam signed [31:0] INV_SQRT3 = 32'sd1239850262;
    localparam signed [31:0] SQRT3_2   = 32'sd1859775393;
    localparam signed [31:0] HALF      = 32'sh40000000;

    wire signed [31:0] ua = ualpha_i;
    wire signed [63:0] beta_term = SQRT3_2 * ubeta_i;
    wire signed [31:0] bterm = sat_s64(beta_term >>> 31);
    wire signed [31:0] nh = - (ua >>> 1);
    wire signed [31:0] ub = sat_add32(nh, bterm);
    wire signed [31:0] uc = sat_add32(nh, -bterm);

    function signed [31:0] pick_max;
        input signed [31:0] a, b, c;
        reg signed [31:0] m;
        begin
            m = a;
            if (b > m) m = b;
            if (c > m) m = c;
            pick_max = m;
        end
    endfunction

    function signed [31:0] pick_min;
        input signed [31:0] a, b, c;
        reg signed [31:0] m;
        begin
            m = a;
            if (b < m) m = b;
            if (c < m) m = c;
            pick_min = m;
        end
    endfunction

    wire signed [31:0] vmax = pick_max(ua, ub, uc);
    wire signed [31:0] vmin = pick_min(ua, ub, uc);
    wire signed [32:0] vsum = {vmax[31], vmax} + {vmin[31], vmin};
    wire signed [31:0] uzs = sat_s64(- ({{31{vsum[32]}}, vsum} >>> 1));

    function [11:0] to_cmp;
        input signed [31:0] u;
        input signed [31:0] zs;
        reg signed [32:0] us;
        reg signed [31:0] uu;
        reg signed [63:0] prod;
        reg signed [63:0] add;
        reg [31:0] d;
        reg [63:0] scaled;
        reg [31:0] q;
        begin
            us = {u[31], u} + {zs[31], zs};
            if (us > 33'sd2147483647)
                uu = 32'h7fffffff;
            else if (us < -33'sd2147483648)
                uu = 32'h80000000;
            else
                uu = us[31:0];
            prod = uu * INV_SQRT3;
            add = prod >>> 31;
            add = add + HALF;
            if (add <= 0)
                d = 32'd0;
            else if (add >= 64'sd2147483647)
                d = 32'h7fffffff;
            else
                d = add[31:0];
            scaled = {32'd0, d} * 64'd2000 + 64'h4000_0000;
            q = scaled[42:31];
            if (q > 32'd2000)
                to_cmp = 12'd2000;
            else
                to_cmp = q[11:0];
        end
    endfunction

    wire [11:0] cmp_now_a = to_cmp(ua, uzs);
    wire [11:0] cmp_now_b = to_cmp(ub, uzs);
    wire [11:0] cmp_now_c = to_cmp(uc, uzs);

    reg [11:0] cmp_sh_a, cmp_sh_b, cmp_sh_c;
    reg [11:0] cmp_a, cmp_b, cmp_c;
    reg        gh0, gh1, gh2, gl0, gl1, gl2;
    reg [8:0]  dh0, dh1, dh2, dl0, dl1, dl2;

    wire raw0 = (cmp_a != 12'd0) && ({1'b0, carrier_cnt_i} < cmp_a);
    wire raw1 = (cmp_b != 12'd0) && ({1'b0, carrier_cnt_i} < cmp_b);
    wire raw2 = (cmp_c != 12'd0) && ({1'b0, carrier_cnt_i} < cmp_c);
    wire run = enable_i & ~block_i;

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            cmp_sh_a <= 12'd1000; cmp_sh_b <= 12'd1000; cmp_sh_c <= 12'd1000;
            cmp_a <= 12'd1000; cmp_b <= 12'd1000; cmp_c <= 12'd1000;
            gh0 <= 0; gh1 <= 0; gh2 <= 0;
            gl0 <= 0; gl1 <= 0; gl2 <= 0;
            dh0 <= 0; dh1 <= 0; dh2 <= 0;
            dl0 <= 0; dl1 <= 0; dl2 <= 0;
        end else begin
            if (calc_done_i) begin
                cmp_sh_a <= cmp_now_a;
                cmp_sh_b <= cmp_now_b;
                cmp_sh_c <= cmp_now_c;
            end
            if (pwm_tick_i) begin
                cmp_a <= cmp_sh_a;
                cmp_b <= cmp_sh_b;
                cmp_c <= cmp_sh_c;
            end
            if (!run) begin
                gh0 <= 0; gh1 <= 0; gh2 <= 0;
                gl0 <= 0; gl1 <= 0; gl2 <= 0;
                dh0 <= 0; dh1 <= 0; dh2 <= 0;
                dl0 <= 0; dl1 <= 0; dl2 <= 0;
            end else begin
                if (!raw0) begin gh0 <= 0; dh0 <= 0; end
                else if (!gh0) begin
                    if (dh0 >= dead_ticks_i) gh0 <= 1'b1;
                    else dh0 <= dh0 + 9'd1;
                end
                if (raw0) begin gl0 <= 0; dl0 <= 0; end
                else if (!gl0) begin
                    if (dl0 >= dead_ticks_i) gl0 <= 1'b1;
                    else dl0 <= dl0 + 9'd1;
                end
                if (!raw1) begin gh1 <= 0; dh1 <= 0; end
                else if (!gh1) begin
                    if (dh1 >= dead_ticks_i) gh1 <= 1'b1;
                    else dh1 <= dh1 + 9'd1;
                end
                if (raw1) begin gl1 <= 0; dl1 <= 0; end
                else if (!gl1) begin
                    if (dl1 >= dead_ticks_i) gl1 <= 1'b1;
                    else dl1 <= dl1 + 9'd1;
                end
                if (!raw2) begin gh2 <= 0; dh2 <= 0; end
                else if (!gh2) begin
                    if (dh2 >= dead_ticks_i) gh2 <= 1'b1;
                    else dh2 <= dh2 + 9'd1;
                end
                if (raw2) begin gl2 <= 0; dl2 <= 0; end
                else if (!gl2) begin
                    if (dl2 >= dead_ticks_i) gl2 <= 1'b1;
                    else dl2 <= dl2 + 9'd1;
                end
            end
        end
    end

    wire uh = run & gh0 & ~gl0;
    wire ul = run & gl0 & ~gh0;
    wire vh = run & gh1 & ~gl1;
    wire vl = run & gl1 & ~gh1;
    wire wh = run & gh2 & ~gl2;
    wire wl = run & gl2 & ~gh2;

    assign pwm_uh_o = pol_inv_i ? ~uh : uh;
    assign pwm_ul_o = pol_inv_i ? ~ul : ul;
    assign pwm_vh_o = pol_inv_i ? ~vh : vh;
    assign pwm_vl_o = pol_inv_i ? ~vl : vl;
    assign pwm_wh_o = pol_inv_i ? ~wh : wh;
    assign pwm_wl_o = pol_inv_i ? ~wl : wl;
endmodule
