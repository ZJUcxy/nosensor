`timescale 1ns / 1ps
// 把各模块按谷点沿和计算相接起来。CORDIC 在谷点的下一拍启动，电压限幅等电流缩放做完后再开始。
module motor_ctrl_core (
    input  wire        clk_in_i,
    input  wire        rst_hw_n_i,
    input  wire        amc_data_a_i,
    input  wire        amc_data_b_i,
    input  wire        amc_data_c_i,
    output wire        amc_mck_o,
    output wire        pwm_uh_o,
    output wire        pwm_ul_o,
    output wire        pwm_vh_o,
    output wire        pwm_vl_o,
    output wire        pwm_wh_o,
    output wire        pwm_wl_o,
    input  wire        ipm_fo_i,
    output wire [3:0]  led_o,
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output wire        s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output wire [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready
);
    wire clk_100m, clk_19m2, rst_n_100, rst_n_19, pwm_tick, mmcm_locked;
    wire [10:0] carrier;
    wire [15:0] valley_cnt;
    wire soft_reset;

    clk_rst_mgmt u_clk (
        .clk_in_i(clk_in_i),
        .rst_hw_n_i(rst_hw_n_i),
        .sw_reset_i(soft_reset),
        .clk_100m_o(clk_100m),
        .clk_19m2_o(clk_19m2),
        .rst_n_100_o(rst_n_100),
        .rst_n_19_o(rst_n_19),
        .pwm_tick_o(pwm_tick),
        .carrier_cnt_o(carrier),
        .valley_cnt_o(valley_cnt),
        .mmcm_locked_o(mmcm_locked)
    );

    reg [2:0] hw_ff;
    always @(posedge clk_100m or negedge rst_hw_n_i) begin
        if (!rst_hw_n_i)
            hw_ff <= 3'b000;
        else
            hw_ff <= {hw_ff[1:0], 1'b1};
    end
    wire rst_cfg_n = hw_ff[2];

    wire signed [31:0] scale_i, ia, ib, ic;
    wire [2:0] data_inv;
    wire [7:0] dec_phase;
    wire sinc_ovf, s0_pulse;

    amc1306_if u_amc (
        .clk_100m_i(clk_100m), .clk_19m2_i(clk_19m2),
        .rst_n_100_i(rst_n_100), .rst_n_19_i(rst_n_19),
        .data_a_i(amc_data_a_i), .data_b_i(amc_data_b_i), .data_c_i(amc_data_c_i),
        .data_inv_i(data_inv), .scale_i(scale_i), .dec_phase_i(dec_phase),
        .pwm_tick_i(pwm_tick), .mck_o(amc_mck_o),
        .ia_o(ia), .ib_o(ib), .ic_o(ic), .sinc_ovf_o(sinc_ovf), .s0_pulse_o(s0_pulse)
    );

    wire signed [31:0] ialpha_c, ibeta_c;
    clarke u_clarke (.ia_i(ia), .ib_i(ib), .ialpha_o(ialpha_c), .ibeta_o(ibeta_c));

    reg signed [31:0] i_alpha_r, i_beta_r, u_alpha_r, u_beta_r, id_r, iq_r;
    reg [1:0] s0_cnt;
    reg [8:0] calc_cnt;
    reg calc_on, cordic_start, cordic_done_h, vlim_start, led3;
    wire sinc_ready = (s0_cnt == 2'd3);

    wire [3:0] state;
    wire pwm_enable, run_if;
    wire [1:0] mode;
    wire [15:0] fault, pri, age, fault_mask;
    wire enable, dir, fault_clr, param_ok, link_ok, pend, obs_en, accept, drop;
    wire [31:0] theta_in, theta_now, theta_park, theta_if, theta_use;
    wire signed [31:0] speed_in, omega_cmd, omega_hold;
    wire [15:0] seq_echo;
    wire [4:0] n_obs;
    wire signed [31:0] id_if, iq_if, id_ref, iq_ref, id_reg, iq_reg;
    wire [1:0] phase;
    wire switch_req, switch_fail;
    wire signed [7:0] angle_lead;
    wire [31:0] t_align, theta_win, theta_abort, stall_t_if, stall_t_run, i_slew_n;
    wire signed [31:0] i_start, dfdt, w_switch, w_stall, i_stall, kp_d, ki_d, kp_q, ki_q, u_max, i_cmd_max, oc_th, ph_th;
    wire [15:0] oc_n, ph_n, switch_n, blend_n, link_to, snap_seq;
    wire [8:0] dead_ticks;
    wire pol_inv;
    wire limited;
    wire signed [31:0] snap_ua, snap_ub, snap_ia, snap_ib;

    wire pend_g = pend & obs_en;
    assign link_ok = (age <= link_to);

    axi_regs u_axi (
        .clk_100m_i(clk_100m), .rst_n_i(rst_cfg_n),
        .s_axi_awaddr(s_axi_awaddr), .s_axi_awvalid(s_axi_awvalid), .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata), .s_axi_wstrb(s_axi_wstrb), .s_axi_wvalid(s_axi_wvalid), .s_axi_wready(s_axi_wready),
        .s_axi_bresp(s_axi_bresp), .s_axi_bvalid(s_axi_bvalid), .s_axi_bready(s_axi_bready),
        .s_axi_araddr(s_axi_araddr), .s_axi_arvalid(s_axi_arvalid), .s_axi_arready(s_axi_arready),
        .s_axi_rdata(s_axi_rdata), .s_axi_rresp(s_axi_rresp), .s_axi_rvalid(s_axi_rvalid), .s_axi_rready(s_axi_rready),
        .pwm_tick_i(pwm_tick), .accept_i(accept), .drop_i(drop),
        .snap_seq_i(snap_seq), .snap_ua_i(snap_ua), .snap_ub_i(snap_ub), .snap_ia_i(snap_ia), .snap_ib_i(snap_ib),
        .ia_i(ia), .ib_i(ib), .ic_i(ic), .ialpha_i(i_alpha_r), .ibeta_i(i_beta_r),
        .id_i(id_r), .iq_i(iq_r), .ualpha_i(u_alpha_r), .ubeta_i(u_beta_r),
        .theta_park_i(theta_park), .theta_now_i(theta_now), .omega_step_i(omega_hold),
        .valley_cnt_i(valley_cnt), .state_i(state), .pwm_enable_i(pwm_enable),
        .link_ok_i(link_ok), .limited_i(limited), .sinc_ovf_i(sinc_ovf),
        .fault_i(fault), .pri_i(pri), .age_i(age),
        .id_ref_o(id_reg), .iq_ref_o(iq_reg), .kp_d_o(kp_d), .ki_d_o(ki_d), .kp_q_o(kp_q), .ki_q_o(ki_q),
        .u_max_o(u_max), .i_cmd_max_o(i_cmd_max), .scale_i_o(scale_i), .data_inv_o(data_inv), .dec_phase_o(dec_phase),
        .oc_th_o(oc_th), .oc_n_o(oc_n), .ph_th_o(ph_th), .ph_n_o(ph_n),
        .i_start_o(i_start), .i_slew_n_o(i_slew_n), .dfdt_o(dfdt), .t_align_o(t_align),
        .w_switch_o(w_switch), .theta_win_o(theta_win), .switch_n_o(switch_n), .blend_n_o(blend_n),
        .theta_abort_o(theta_abort), .stall_t_if_o(stall_t_if), .stall_t_run_o(stall_t_run),
        .w_stall_o(w_stall), .i_stall_o(i_stall), .link_to_o(link_to), .angle_lead_o(angle_lead),
        .dead_ticks_o(dead_ticks), .pol_inv_o(pol_inv), .fault_mask_o(fault_mask), .obs_en_o(obs_en),
        .enable_o(enable), .dir_o(dir), .soft_reset_o(soft_reset), .fault_clr_o(fault_clr),
        .param_ok_o(param_ok), .pend_o(pend), .theta_in_o(theta_in), .speed_in_o(speed_in), .seq_echo_o(seq_echo)
    );

    obs_port u_obs (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .pwm_tick_i(pwm_tick), .valley_cnt_i(valley_cnt),
        .ialpha_i(ialpha_c), .ibeta_i(ibeta_c), .ualpha_i(u_alpha_r), .ubeta_i(u_beta_r),
        .pend_i(pend_g), .theta_in_i(theta_in), .speed_in_i(speed_in), .seq_echo_i(seq_echo),
        .snap_seq_o(snap_seq), .snap_ua_o(snap_ua), .snap_ub_o(snap_ub), .snap_ia_o(snap_ia), .snap_ib_o(snap_ib),
        .accept_o(accept), .drop_o(drop), .theta_use_o(theta_use), .omega_step_o(omega_cmd), .n_o(n_obs)
    );

    theta_interp u_theta (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .pwm_tick_i(pwm_tick), .accept_i(accept),
        .theta_in_i(theta_use), .omega_step_i(omega_cmd), .n_i(n_obs), .angle_lead_i(angle_lead),
        .theta_now_o(theta_now), .theta_park_o(theta_park), .omega_step_o(omega_hold), .link_age_o(age)
    );

    if_startup u_if (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .run_i(run_if), .dir_i(dir), .pwm_tick_i(pwm_tick),
        .theta_now_i(theta_now), .omega_step_i(omega_hold), .obs_new_i(accept), .drop_i(drop),
        .i_start_i(i_start), .dfdt_i(dfdt), .t_align_i(t_align), .i_slew_n_i(i_slew_n),
        .w_switch_i(w_switch), .theta_win_i(theta_win), .switch_n_i(switch_n),
        .blend_n_i(blend_n), .theta_abort_i(theta_abort),
        .id_reg_i(id_reg), .iq_reg_i(iq_reg),
        .id_ref_o(id_if), .iq_ref_o(iq_if), .theta_o(theta_if),
        .phase_o(phase), .switch_req_o(switch_req), .switch_fail_o(switch_fail)
    );

    sys_fsm u_fsm (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .enable_i(enable), .param_ok_i(param_ok),
        .mmcm_locked_i(mmcm_locked), .sinc_ready_i(sinc_ready),
        .fault_i(fault), .fault_clr_i(fault_clr),
        .switch_req_i(switch_req), .phase_i(phase),
        .pwm_tick_i(pwm_tick), .t_align_i(t_align),
        .state_o(state), .pwm_enable_o(pwm_enable), .mode_o(mode), .run_if_o(run_if)
    );

    wire [31:0] theta_cmd;
    cmd_mux u_cmd (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .mode_i(mode), .theta_if_i(theta_if), .theta_park_i(theta_park),
        .id_if_i(id_if), .iq_if_i(iq_if), .id_reg_i(id_reg), .iq_reg_i(iq_reg),
        .i_cmd_max_i(i_cmd_max), .theta_o(theta_cmd), .id_ref_o(id_ref), .iq_ref_o(iq_ref)
    );

    wire signed [31:0] sin_th, cos_th, id_c, iq_c, ud_pi, uq_pi, ud_lim, uq_lim, ualpha_c, ubeta_c;
    wire cordic_done, vlim_done;
    wire block;

    cordic_sincos u_cordic (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .theta_i(theta_cmd), .start_i(cordic_start),
        .sin_o(sin_th), .cos_o(cos_th), .done_o(cordic_done)
    );

    park_ipark u_park (
        .ialpha_i(i_alpha_r), .ibeta_i(i_beta_r),
        .ud_i(ud_lim), .uq_i(uq_lim), .sin_i(sin_th), .cos_i(cos_th),
        .id_o(id_c), .iq_o(iq_c), .ualpha_o(ualpha_c), .ubeta_o(ubeta_c)
    );

    pi_ctrl u_pi_d (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100), .step_i(vlim_done),
        .ref_i(id_ref), .fb_i(id_c), .kp_i(kp_d), .ki_i(ki_d),
        .enable_i(pwm_enable), .freeze_i(limited), .out_o(ud_pi)
    );
    pi_ctrl u_pi_q (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100), .step_i(vlim_done),
        .ref_i(iq_ref), .fb_i(iq_c), .kp_i(kp_q), .ki_i(ki_q),
        .enable_i(pwm_enable), .freeze_i(limited), .out_o(uq_pi)
    );

    vlim u_vlim (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100), .start_i(vlim_start),
        .ud_i(ud_pi), .uq_i(uq_pi), .umax_i(u_max),
        .ud_o(ud_lim), .uq_o(uq_lim), .limited_o(limited), .done_o(vlim_done)
    );

    svpwm u_svpwm (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .ualpha_i(ualpha_c), .ubeta_i(ubeta_c), .calc_done_i(vlim_done),
        .pwm_tick_i(pwm_tick), .carrier_cnt_i(carrier), .dead_ticks_i(dead_ticks),
        .enable_i(pwm_enable), .block_i(block), .pol_inv_i(pol_inv),
        .pwm_uh_o(pwm_uh_o), .pwm_ul_o(pwm_ul_o), .pwm_vh_o(pwm_vh_o),
        .pwm_vl_o(pwm_vl_o), .pwm_wh_o(pwm_wh_o), .pwm_wl_o(pwm_wl_o)
    );

    protect u_prot (
        .clk_100m_i(clk_100m), .rst_n_i(rst_n_100),
        .ia_i(ia), .ib_i(ib), .ic_i(ic), .iq_ref_i(iq_ref), .omega_step_i(omega_hold),
        .ipm_fo_i(ipm_fo_i), .link_age_i(age), .state_i(state),
        .switch_fail_i(switch_fail), .sinc_ovf_i(sinc_ovf), .pwm_tick_i(pwm_tick),
        .oc_th_i(oc_th), .oc_n_i(oc_n), .ph_th_i(ph_th), .ph_n_i(ph_n),
        .stall_t_if_i(stall_t_if), .stall_t_run_i(stall_t_run),
        .w_stall_i(w_stall), .i_stall_i(i_stall), .link_to_i(link_to),
        .fault_mask_i(fault_mask), .fault_clr_i(fault_clr),
        .fault_o(fault), .block_o(block), .pri_o(pri)
    );

    always @(posedge clk_100m or negedge rst_n_100) begin
        if (!rst_n_100) begin
            i_alpha_r <= 0; i_beta_r <= 0; u_alpha_r <= 0; u_beta_r <= 0; id_r <= 0; iq_r <= 0;
            s0_cnt <= 0; calc_cnt <= 0; calc_on <= 0;
            cordic_start <= 0; cordic_done_h <= 0; vlim_start <= 0; led3 <= 0;
        end else begin
            cordic_start <= 1'b0;
            vlim_start <= 1'b0;
            if (s0_pulse && s0_cnt != 2'd3)
                s0_cnt <= s0_cnt + 2'd1;
            if (accept)
                led3 <= ~led3;
            if (pwm_tick) begin
                i_alpha_r <= ialpha_c;
                i_beta_r <= ibeta_c;
                calc_on <= 1'b1;
                calc_cnt <= 9'd0;
                cordic_done_h <= 1'b0;
                cordic_start <= 1'b1;
            end else if (calc_on) begin
                if (cordic_done)
                    cordic_done_h <= 1'b1;
                if ((calc_cnt >= 9'd300) && (cordic_done_h || cordic_done)) begin
                    vlim_start <= 1'b1;
                    calc_on <= 1'b0;
                end else
                    calc_cnt <= calc_cnt + 9'd1;
            end
            if (vlim_done) begin
                u_alpha_r <= ualpha_c;
                u_beta_r <= ubeta_c;
                id_r <= id_c;
                iq_r <= iq_c;
            end
        end
    end

    assign led_o = {led3, (state == 4'd6), (state == 4'd5), pwm_enable};
endmodule
