`timescale 1ns / 1ps
// I-F：电流闭环、角度开环。频率积分对应参考模型 if_freq_step，角度积分对应 if_theta_step。
// 切换计数的是连续成功提交，两次提交之间不因空谷点清零。
module if_startup (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire               run_i,
    input  wire               dir_i,
    input  wire               pwm_tick_i,
    input  wire [31:0]        theta_now_i,
    input  wire signed [31:0] omega_step_i,
    input  wire               obs_new_i,
    input  wire               drop_i,
    input  wire signed [31:0] i_start_i,
    input  wire signed [31:0] dfdt_i,
    input  wire [31:0]        t_align_i,
    input  wire [31:0]        i_slew_n_i,
    input  wire signed [31:0] w_switch_i,
    input  wire [31:0]        theta_win_i,
    input  wire [15:0]        switch_n_i,
    input  wire [15:0]        blend_n_i,
    input  wire [31:0]        theta_abort_i,
    input  wire signed [31:0] id_reg_i,
    input  wire signed [31:0] iq_reg_i,
    output reg  signed [31:0] id_ref_o,
    output reg  signed [31:0] iq_ref_o,
    output reg  [31:0]        theta_o,
    output reg  [1:0]         phase_o,
    output reg                switch_req_o,
    output reg                switch_fail_o
);
`include "fxp_pkg.vh"
    reg [1:0]         phase;
    reg [31:0]        slew_cnt, align_cnt, blend_cnt;
    reg [15:0]        match_cnt;
    reg signed [31:0] iq_cmd, freq, freq_rem, theta_rem;
    reg [31:0]        theta_if;
    reg signed [31:0] dtheta_lat, iq_lat;
    reg               seen_acc, seen_drop, fail_lock;

    wire signed [31:0] i_mag = i_start_i[31] ? -i_start_i : i_start_i;
    wire signed [31:0] i_tgt = dir_i ? -i_mag : i_mag;
    wire signed [31:0] df_mag = dfdt_i[31] ? -dfdt_i : dfdt_i;
    wire signed [31:0] df_s = dir_i ? -df_mag : df_mag;
    wire [15:0] nreq = (switch_n_i == 16'd0) ? 16'd1 : switch_n_i;

    function signed [31:0] q_div;
        input signed [63:0] n;
        input [31:0] den;
        reg [63:0] mag;
        reg [63:0] q;
        reg sign;
        begin
            if (den == 0) begin
                q_div = n[31:0];
            end else begin
                sign = n[63];
                mag = sign ? -n : n;
                q = mag / den;
                if (sign) begin
                    if (q > 64'h0000_0000_7fff_ffff)
                        q_div = 32'h80000000;
                    else
                        q_div = -$signed(q[31:0]);
                end else if (q > 64'h0000_0000_7fff_ffff) begin
                    q_div = 32'h7fffffff;
                end else begin
                    q_div = $signed(q[31:0]);
                end
            end
        end
    endfunction

    function signed [31:0] r_div;
        input signed [63:0] n;
        input [31:0] den;
        reg [63:0] mag;
        reg [31:0] r;
        reg sign;
        begin
            if (den == 0)
                r_div = 32'sd0;
            else begin
                sign = n[63];
                mag = sign ? -n : n;
                r = mag % den;
                r_div = sign ? -$signed(r) : $signed({1'b0, r});
            end
        end
    endfunction

    wire signed [63:0] sum_f = {{32{freq_rem[31]}}, freq_rem} + {{32{df_s[31]}}, df_s};
    wire signed [31:0] df_q = q_div(sum_f, 32'd25000);
    wire signed [31:0] freq_next = freq + df_q;
    wire signed [63:0] th_num = {{15{freq_next[31]}}, freq_next, 16'd0} + {{32{theta_rem[31]}}, theta_rem};
    wire signed [31:0] dth = q_div(th_num, 32'd25000);
    wire [31:0] theta_if_next = theta_if + dth;

    wire signed [31:0] slew_iq = (i_slew_n_i == 0 || slew_cnt >= i_slew_n_i) ? i_tgt :
                                 q_div(i_tgt * $signed({1'b0, slew_cnt}), i_slew_n_i);
    wire [31:0] blend_den = (blend_n_i == 0) ? 32'd1 : {16'd0, blend_n_i};
    wire signed [63:0] dprod = dtheta_lat * $signed({1'b0, blend_cnt});
    wire signed [63:0] iprod = (iq_reg_i - iq_lat) * $signed({1'b0, blend_cnt});
    wire signed [63:0] dprod_id = (id_reg_i) * $signed({1'b0, blend_cnt});
    wire [31:0] theta_blend = theta_if + q_div(dprod, blend_den);
    wire signed [31:0] iq_blend = iq_lat + q_div(iprod, blend_den);
    wire signed [31:0] id_blend = q_div(dprod_id, blend_den);

    wire signed [31:0] err_now = $signed(theta_now_i - theta_o);
    wire [31:0] abs_err = abs32(err_now);
    wire [31:0] abs_w = abs32(omega_step_i);
    wire [31:0] wth = abs32(w_switch_i);

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i || !run_i) begin
            phase <= 2'd0;
            slew_cnt <= 0;
            align_cnt <= 0;
            blend_cnt <= 0;
            match_cnt <= 0;
            iq_cmd <= 0;
            freq <= 0;
            freq_rem <= 0;
            theta_rem <= 0;
            theta_if <= 0;
            dtheta_lat <= 0;
            iq_lat <= 0;
            seen_acc <= 0;
            seen_drop <= 0;
            fail_lock <= 0;
            id_ref_o <= 0;
            iq_ref_o <= 0;
            theta_o <= 0;
            phase_o <= 0;
            switch_req_o <= 0;
            switch_fail_o <= 0;
        end else begin
            seen_acc <= obs_new_i;
            seen_drop <= drop_i;
            switch_fail_o <= 1'b0;
            if (phase == 2'd2 && !fail_lock && abs_err > theta_abort_i) begin
                switch_fail_o <= 1'b1;
                fail_lock <= 1'b1;
            end
            if (seen_drop && phase == 2'd1)
                match_cnt <= 16'd0;
            if (seen_acc && phase == 2'd1) begin
                if (abs_w >= wth && abs_err <= theta_win_i) begin
                    if (match_cnt + 16'd1 >= nreq) begin
                        match_cnt <= nreq;
                        phase <= 2'd2;
                        dtheta_lat <= err_now;
                        iq_lat <= iq_ref_o;
                        blend_cnt <= 32'd0;
                        switch_req_o <= 1'b1;
                        fail_lock <= 1'b0;
                    end else begin
                        match_cnt <= match_cnt + 16'd1;
                    end
                end else begin
                    match_cnt <= 16'd0;
                end
            end
            if (pwm_tick_i) begin
                if (slew_cnt < i_slew_n_i && i_slew_n_i != 0)
                    slew_cnt <= slew_cnt + 32'd1;
                iq_cmd <= slew_iq;
                if (phase == 2'd0 && t_align_i != 0 && align_cnt < t_align_i) begin
                    theta_if <= 32'd0;
                    theta_o <= 32'd0;
                    id_ref_o <= 32'sd0;
                    iq_ref_o <= slew_iq;
                    align_cnt <= align_cnt + 32'd1;
                    if (align_cnt + 32'd1 >= t_align_i)
                        phase <= 2'd1;
                end else begin
                    if (phase == 2'd0)
                        phase <= 2'd1;
                    freq <= freq_next;
                    freq_rem <= r_div(sum_f, 32'd25000);
                    theta_rem <= r_div(th_num, 32'd25000);
                    theta_if <= theta_if_next;
                    if (phase == 2'd2 || (seen_acc && phase == 2'd1 && abs_w >= wth && abs_err <= theta_win_i && (match_cnt + 16'd1 >= nreq))) begin
                        if (blend_cnt >= {16'd0, blend_n_i}) begin
                            phase <= 2'd3;
                            theta_o <= theta_if_next + dtheta_lat;
                            id_ref_o <= id_reg_i;
                            iq_ref_o <= iq_reg_i;
                        end else begin
                            theta_o <= theta_if_next + q_div(dtheta_lat * $signed({1'b0, blend_cnt}), blend_den);
                            id_ref_o <= q_div(id_reg_i * $signed({1'b0, blend_cnt}), blend_den);
                            iq_ref_o <= iq_lat + q_div((iq_reg_i - iq_lat) * $signed({1'b0, blend_cnt}), blend_den);
                            blend_cnt <= blend_cnt + 32'd1;
                        end
                    end else begin
                        theta_o <= theta_if_next;
                        id_ref_o <= 32'sd0;
                        iq_ref_o <= slew_iq;
                    end
                end
            end
            phase_o <= phase;
        end
    end
endmodule
