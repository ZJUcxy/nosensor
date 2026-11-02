`timescale 1ns / 1ps
// AXI4-Lite 从机。控制参数写影子，谷点装入生效值。OBS_COMMIT 锁存提交缓冲。
module axi_regs (
    input  wire        clk_100m_i,
    input  wire        rst_n_i,
    input  wire [31:0] s_axi_awaddr,
    input  wire        s_axi_awvalid,
    output reg         s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output reg         s_axi_wready,
    output reg  [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [31:0] s_axi_araddr,
    input  wire        s_axi_arvalid,
    output reg         s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output reg  [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    input  wire        pwm_tick_i,
    input  wire        accept_i,
    input  wire        drop_i,
    input  wire [15:0] snap_seq_i,
    input  wire signed [31:0] snap_ua_i,
    input  wire signed [31:0] snap_ub_i,
    input  wire signed [31:0] snap_ia_i,
    input  wire signed [31:0] snap_ib_i,
    input  wire signed [31:0] ia_i,
    input  wire signed [31:0] ib_i,
    input  wire signed [31:0] ic_i,
    input  wire signed [31:0] ialpha_i,
    input  wire signed [31:0] ibeta_i,
    input  wire signed [31:0] id_i,
    input  wire signed [31:0] iq_i,
    input  wire signed [31:0] ualpha_i,
    input  wire signed [31:0] ubeta_i,
    input  wire [31:0] theta_park_i,
    input  wire [31:0] theta_now_i,
    input  wire signed [31:0] omega_step_i,
    input  wire [15:0] valley_cnt_i,
    input  wire [3:0]  state_i,
    input  wire        pwm_enable_i,
    input  wire        link_ok_i,
    input  wire        limited_i,
    input  wire        sinc_ovf_i,
    input  wire [15:0] fault_i,
    input  wire [15:0] pri_i,
    input  wire [15:0] age_i,

    output wire signed [31:0] id_ref_o,
    output wire signed [31:0] iq_ref_o,
    output wire signed [31:0] kp_d_o,
    output wire signed [31:0] ki_d_o,
    output wire signed [31:0] kp_q_o,
    output wire signed [31:0] ki_q_o,
    output wire signed [31:0] u_max_o,
    output wire signed [31:0] i_cmd_max_o,
    output wire signed [31:0] scale_i_o,
    output wire [2:0]  data_inv_o,
    output wire [7:0]  dec_phase_o,
    output wire signed [31:0] oc_th_o,
    output wire [15:0] oc_n_o,
    output wire signed [31:0] ph_th_o,
    output wire [15:0] ph_n_o,
    output wire signed [31:0] i_start_o,
    output wire [31:0] i_slew_n_o,
    output wire signed [31:0] dfdt_o,
    output wire [31:0] t_align_o,
    output wire signed [31:0] w_switch_o,
    output wire [31:0] theta_win_o,
    output wire [15:0] switch_n_o,
    output wire [15:0] blend_n_o,
    output wire [31:0] theta_abort_o,
    output wire [31:0] stall_t_if_o,
    output wire [31:0] stall_t_run_o,
    output wire signed [31:0] w_stall_o,
    output wire signed [31:0] i_stall_o,
    output wire [15:0] link_to_o,
    output wire signed [7:0] angle_lead_o,
    output wire [8:0]  dead_ticks_o,
    output wire        pol_inv_o,
    output wire [15:0] fault_mask_o,
    output wire        obs_en_o,
    output wire        enable_o,
    output wire        dir_o,
    output wire        soft_reset_o,
    output wire        fault_clr_o,
    output wire        param_ok_o,
    output wire        pend_o,
    output wire [31:0] theta_in_o,
    output wire signed [31:0] speed_in_o,
    output wire [15:0] seq_echo_o
);
    reg aw_cap, w_cap, ar_cap;
    reg [11:0] aw_addr, ar_addr;
    reg [31:0] w_data;
    reg [3:0]  w_strb;
    reg [2:0]  clr_cnt;

    reg        ctrl_en, ctrl_rst, ctrl_dir;
    reg [31:0] sh_id, sh_iq, sh_kpd, sh_kid, sh_kpq, sh_kiq;
    reg [31:0] sh_umax, sh_imax, sh_scale, sh_inv, sh_dec;
    reg [31:0] sh_octh, sh_ocn, sh_phth, sh_phn, sh_istart, sh_islew, sh_dfdt, sh_talign;
    reg [31:0] sh_wsw, sh_twin, sh_swn, sh_blend, sh_abort, sh_stif, sh_strun;
    reg [31:0] sh_wstall, sh_istall, sh_link, sh_lead, sh_dead, sh_pwmcfg, sh_mask, sh_obscfg;
    reg [31:0] sh_vdc, sh_ibase, sh_ov, sh_uv, sh_ot;
    reg [31:0] ac_id, ac_iq, ac_kpd, ac_kid, ac_kpq, ac_kiq;
    reg [31:0] ac_umax, ac_imax, ac_scale, ac_inv, ac_dec;
    reg [31:0] ac_octh, ac_ocn, ac_phth, ac_phn, ac_istart, ac_islew, ac_dfdt, ac_talign;
    reg [31:0] ac_wsw, ac_twin, ac_swn, ac_blend, ac_abort, ac_stif, ac_strun;
    reg [31:0] ac_wstall, ac_istall, ac_link, ac_lead, ac_dead, ac_pwmcfg, ac_mask, ac_obscfg;
    reg [31:0] ac_vdc, ac_ibase, ac_ov, ac_uv, ac_ot;
    reg [31:0] theta_in, speed_in;
    reg [15:0] seq_echo, drop_cnt;
    reg [31:0] pend_theta, pend_speed;
    reg [15:0] pend_seq;
    reg        pend;

    function [31:0] merge32;
        input [31:0] oldv;
        input [31:0] newv;
        input [3:0] stb;
        reg [31:0] r;
        begin
            r = oldv;
            if (stb[0]) r[7:0] = newv[7:0];
            if (stb[1]) r[15:8] = newv[15:8];
            if (stb[2]) r[23:16] = newv[23:16];
            if (stb[3]) r[31:24] = newv[31:24];
            merge32 = r;
        end
    endfunction

    wire [31:0] status = {pri_i, 6'd0, sinc_ovf_i, ctrl_dir, limited_i, param_ok_o, link_ok_i, pwm_enable_i, state_i};

    assign id_ref_o = ac_id;
    assign iq_ref_o = ac_iq;
    assign kp_d_o = ac_kpd;
    assign ki_d_o = ac_kid;
    assign kp_q_o = ac_kpq;
    assign ki_q_o = ac_kiq;
    assign u_max_o = ac_umax;
    assign i_cmd_max_o = ac_imax;
    assign scale_i_o = ac_scale;
    assign data_inv_o = ac_inv[2:0];
    assign dec_phase_o = ac_dec[7:0];
    assign oc_th_o = ac_octh;
    assign oc_n_o = ac_ocn[15:0];
    assign ph_th_o = ac_phth;
    assign ph_n_o = ac_phn[15:0];
    assign i_start_o = ac_istart;
    assign i_slew_n_o = ac_islew;
    assign dfdt_o = ac_dfdt;
    assign t_align_o = ac_talign;
    assign w_switch_o = ac_wsw;
    assign theta_win_o = ac_twin;
    assign switch_n_o = ac_swn[15:0];
    assign blend_n_o = ac_blend[15:0];
    assign theta_abort_o = ac_abort;
    assign stall_t_if_o = ac_stif;
    assign stall_t_run_o = ac_strun;
    assign w_stall_o = ac_wstall;
    assign i_stall_o = ac_istall;
    assign link_to_o = ac_link[15:0];
    assign angle_lead_o = ac_lead[7:0];
    assign dead_ticks_o = ac_dead[12:0] / 13'd10;
    assign pol_inv_o = ac_pwmcfg[0];
    assign fault_mask_o = ac_mask[15:0];
    assign obs_en_o = ac_obscfg[0];
    assign enable_o = ctrl_en;
    assign dir_o = ctrl_dir;
    assign soft_reset_o = ctrl_rst;
    assign fault_clr_o = (clr_cnt != 0);
    assign param_ok_o = (ac_kpd != 0) && (ac_kpq != 0) && (ac_istart != 0);
    assign pend_o = pend;
    assign theta_in_o = pend_theta;
    assign speed_in_o = pend_speed;
    assign seq_echo_o = pend_seq;

    wire [31:0] ctrl_merged = merge32({27'd0, ctrl_dir, 1'b0, 1'b0, ctrl_rst, ctrl_en}, w_data, w_strb);
    wire [31:0] commit_merged = merge32({31'd0, pend}, w_data, w_strb);

    function [31:0] rd_word;
        input [11:0] a;
        begin
            case (a)
                12'h000: rd_word = 32'h464F4331;
                12'h004: rd_word = 32'h00010000;
                12'h008: rd_word = {27'd0, ctrl_dir, (clr_cnt != 0), 1'b0, ctrl_rst, ctrl_en};
                12'h00C: rd_word = status;
                12'h010: rd_word = {16'd0, fault_i};
                12'h014: rd_word = ac_mask;
                12'h018: rd_word = ac_pwmcfg;
                12'h01C: rd_word = 32'd2000;
                12'h020: rd_word = ac_dead;
                12'h024: rd_word = ac_id;
                12'h028: rd_word = ac_iq;
                12'h02C: rd_word = ac_kpd;
                12'h030: rd_word = ac_kid;
                12'h034: rd_word = ac_kpq;
                12'h038: rd_word = ac_kiq;
                12'h03C: rd_word = ac_umax;
                12'h040: rd_word = ac_imax;
                12'h044: rd_word = ac_scale;
                12'h048: rd_word = ac_inv;
                12'h04C: rd_word = ac_dec;
                12'h050: rd_word = ac_octh;
                12'h054: rd_word = ac_ocn;
                12'h058: rd_word = ac_phth;
                12'h05C: rd_word = ac_phn;
                12'h060: rd_word = ac_istart;
                12'h064: rd_word = ac_islew;
                12'h068: rd_word = ac_dfdt;
                12'h06C: rd_word = ac_talign;
                12'h070: rd_word = ac_wsw;
                12'h074: rd_word = ac_twin;
                12'h078: rd_word = ac_swn;
                12'h07C: rd_word = ac_blend;
                12'h080: rd_word = ac_abort;
                12'h084: rd_word = ac_stif;
                12'h088: rd_word = ac_strun;
                12'h08C: rd_word = ac_wstall;
                12'h090: rd_word = ac_istall;
                12'h094: rd_word = ac_link;
                12'h098: rd_word = ac_lead;
                12'h09C: rd_word = ac_vdc;
                12'h0A0: rd_word = ac_ibase;
                12'h0A4: rd_word = ac_ov;
                12'h0A8: rd_word = ac_uv;
                12'h0AC: rd_word = ac_ot;
                12'h0B0: rd_word = ac_obscfg;
                12'h0B4: rd_word = {16'd0, age_i};
                12'h0C0: rd_word = ia_i;
                12'h0C4: rd_word = ib_i;
                12'h0C8: rd_word = ic_i;
                12'h0CC: rd_word = ialpha_i;
                12'h0D0: rd_word = ibeta_i;
                12'h0D4: rd_word = id_i;
                12'h0D8: rd_word = iq_i;
                12'h0DC: rd_word = ualpha_i;
                12'h0E0: rd_word = ubeta_i;
                12'h0E4: rd_word = theta_park_i;
                12'h0E8: rd_word = theta_now_i;
                12'h0EC: rd_word = omega_step_i;
                12'h0F0: rd_word = {16'd0, valley_cnt_i};
                12'h100: rd_word = {16'd0, snap_seq_i};
                12'h104: rd_word = snap_ua_i;
                12'h108: rd_word = snap_ub_i;
                12'h10C: rd_word = snap_ia_i;
                12'h110: rd_word = snap_ib_i;
                12'h114: rd_word = theta_in;
                12'h118: rd_word = speed_in;
                12'h11C: rd_word = {16'd0, seq_echo};
                12'h120: rd_word = {31'd0, pend};
                12'h124: rd_word = {16'd0, drop_cnt};
                default: rd_word = 32'd0;
            endcase
        end
    endfunction

    task load_active;
        begin
            ac_id <= sh_id; ac_iq <= sh_iq;
            ac_kpd <= sh_kpd; ac_kid <= sh_kid; ac_kpq <= sh_kpq; ac_kiq <= sh_kiq;
            ac_umax <= sh_umax; ac_imax <= sh_imax; ac_scale <= sh_scale;
            ac_inv <= sh_inv; ac_dec <= {24'd0, sh_dec[7:0]};
            ac_octh <= sh_octh; ac_ocn <= sh_ocn; ac_phth <= sh_phth; ac_phn <= sh_phn;
            ac_istart <= sh_istart; ac_islew <= sh_islew; ac_dfdt <= sh_dfdt; ac_talign <= sh_talign;
            ac_wsw <= sh_wsw; ac_twin <= sh_twin; ac_swn <= sh_swn; ac_blend <= sh_blend;
            ac_abort <= sh_abort; ac_stif <= sh_stif; ac_strun <= sh_strun;
            ac_wstall <= sh_wstall; ac_istall <= sh_istall; ac_link <= sh_link;
            ac_lead <= {{24{sh_lead[7]}}, sh_lead[7:0]};
            if (sh_dead < 32'd500) ac_dead <= 32'd500;
            else if (sh_dead > 32'd5000) ac_dead <= 32'd5000;
            else ac_dead <= sh_dead;
            ac_pwmcfg <= sh_pwmcfg; ac_mask <= sh_mask; ac_obscfg <= sh_obscfg;
            ac_vdc <= sh_vdc; ac_ibase <= sh_ibase; ac_ov <= sh_ov; ac_uv <= sh_uv; ac_ot <= sh_ot;
        end
    endtask

    task reset_cfg;
        begin
            ctrl_en <= 0; ctrl_rst <= 0; ctrl_dir <= 0; clr_cnt <= 0;
            sh_id <= 0; sh_iq <= 0; sh_kpd <= 0; sh_kid <= 0; sh_kpq <= 0; sh_kiq <= 0;
            sh_umax <= 32'h7fffffff; sh_imax <= 32'h73333333; sh_scale <= 32'h00010000;
            sh_inv <= 0; sh_dec <= 0;
            sh_octh <= 32'h79999999; sh_ocn <= 32'd2; sh_phth <= 32'h0ccccccd; sh_phn <= 32'd10;
            sh_istart <= 32'h26666666; sh_islew <= 32'd2500; sh_dfdt <= 0; sh_talign <= 32'd12500;
            sh_wsw <= 32'd1717987; sh_twin <= 32'd85899346; sh_swn <= 32'd10; sh_blend <= 32'd200;
            sh_abort <= 32'd644245094; sh_stif <= 32'd125000; sh_strun <= 32'd12500;
            sh_wstall <= 32'd171799; sh_istall <= 32'h1999999a; sh_link <= 32'd15; sh_lead <= 32'd2;
            sh_dead <= 32'd2000; sh_pwmcfg <= 0; sh_mask <= 32'h0000020e; sh_obscfg <= 32'd1;
            sh_vdc <= 32'h01360000; sh_ibase <= 32'h00140000; sh_ov <= 0; sh_uv <= 0; sh_ot <= 0;
            ac_id <= 0; ac_iq <= 0; ac_kpd <= 0; ac_kid <= 0; ac_kpq <= 0; ac_kiq <= 0;
            ac_umax <= 32'h7fffffff; ac_imax <= 32'h73333333; ac_scale <= 32'h00010000;
            ac_inv <= 0; ac_dec <= 0;
            ac_octh <= 32'h79999999; ac_ocn <= 32'd2; ac_phth <= 32'h0ccccccd; ac_phn <= 32'd10;
            ac_istart <= 32'h26666666; ac_islew <= 32'd2500; ac_dfdt <= 0; ac_talign <= 32'd12500;
            ac_wsw <= 32'd1717987; ac_twin <= 32'd85899346; ac_swn <= 32'd10; ac_blend <= 32'd200;
            ac_abort <= 32'd644245094; ac_stif <= 32'd125000; ac_strun <= 32'd12500;
            ac_wstall <= 32'd171799; ac_istall <= 32'h1999999a; ac_link <= 32'd15; ac_lead <= 32'd2;
            ac_dead <= 32'd2000; ac_pwmcfg <= 0; ac_mask <= 32'h0000020e; ac_obscfg <= 32'd1;
            ac_vdc <= 32'h01360000; ac_ibase <= 32'h00140000; ac_ov <= 0; ac_uv <= 0; ac_ot <= 0;
            theta_in <= 0; speed_in <= 0; seq_echo <= 0; drop_cnt <= 0;
            pend_theta <= 0; pend_speed <= 0; pend_seq <= 0; pend <= 0;
        end
    endtask

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            s_axi_awready <= 0; s_axi_wready <= 0; s_axi_bvalid <= 0; s_axi_bresp <= 0;
            s_axi_arready <= 0; s_axi_rvalid <= 0; s_axi_rresp <= 0; s_axi_rdata <= 0;
            aw_cap <= 0; w_cap <= 0; ar_cap <= 0;
            aw_addr <= 0; ar_addr <= 0; w_data <= 0; w_strb <= 0;
            reset_cfg();
        end else begin
            s_axi_awready <= 1'b0;
            s_axi_wready <= 1'b0;
            s_axi_arready <= 1'b0;
            if (s_axi_bvalid && s_axi_bready) s_axi_bvalid <= 1'b0;
            if (s_axi_rvalid && s_axi_rready) s_axi_rvalid <= 1'b0;
            if (clr_cnt != 0) clr_cnt <= clr_cnt - 3'd1;

            if (!aw_cap && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
                aw_cap <= 1'b1;
                aw_addr <= {s_axi_awaddr[11:2], 2'b00};
            end
            if (!w_cap && s_axi_wvalid) begin
                s_axi_wready <= 1'b1;
                w_cap <= 1'b1;
                w_data <= s_axi_wdata;
                w_strb <= s_axi_wstrb;
            end
            if (!ar_cap && s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                ar_cap <= 1'b1;
                ar_addr <= {s_axi_araddr[11:2], 2'b00};
            end
            if (ar_cap && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp <= 2'b00;
                s_axi_rdata <= rd_word(ar_addr);
                ar_cap <= 1'b0;
            end

            if (accept_i || drop_i)
                pend <= 1'b0;
            if (drop_i && !accept_i && drop_cnt != 16'hffff)
                drop_cnt <= drop_cnt + 16'd1;
            if (pwm_tick_i)
                load_active();

            if (aw_cap && w_cap && !s_axi_bvalid) begin
                aw_cap <= 1'b0;
                w_cap <= 1'b0;
                s_axi_bvalid <= 1'b1;
                s_axi_bresp <= 2'b00;
                case (aw_addr)
                    12'h008: begin
                        ctrl_en <= ctrl_merged[0];
                        ctrl_rst <= ctrl_merged[2];
                        ctrl_dir <= ctrl_merged[4];
                        if (ctrl_merged[3])
                            clr_cnt <= 3'd3;
                    end
                    12'h014: sh_mask <= merge32(sh_mask, w_data, w_strb);
                    12'h018: sh_pwmcfg <= merge32(sh_pwmcfg, w_data, w_strb);
                    12'h020: sh_dead <= merge32(sh_dead, w_data, w_strb);
                    12'h024: sh_id <= merge32(sh_id, w_data, w_strb);
                    12'h028: sh_iq <= merge32(sh_iq, w_data, w_strb);
                    12'h02C: sh_kpd <= merge32(sh_kpd, w_data, w_strb);
                    12'h030: sh_kid <= merge32(sh_kid, w_data, w_strb);
                    12'h034: sh_kpq <= merge32(sh_kpq, w_data, w_strb);
                    12'h038: sh_kiq <= merge32(sh_kiq, w_data, w_strb);
                    12'h03C: sh_umax <= merge32(sh_umax, w_data, w_strb);
                    12'h040: sh_imax <= merge32(sh_imax, w_data, w_strb);
                    12'h044: sh_scale <= merge32(sh_scale, w_data, w_strb);
                    12'h048: sh_inv <= merge32(sh_inv, w_data, w_strb);
                    12'h04C: sh_dec <= merge32(sh_dec, w_data, w_strb);
                    12'h050: sh_octh <= merge32(sh_octh, w_data, w_strb);
                    12'h054: sh_ocn <= merge32(sh_ocn, w_data, w_strb);
                    12'h058: sh_phth <= merge32(sh_phth, w_data, w_strb);
                    12'h05C: sh_phn <= merge32(sh_phn, w_data, w_strb);
                    12'h060: sh_istart <= merge32(sh_istart, w_data, w_strb);
                    12'h064: sh_islew <= merge32(sh_islew, w_data, w_strb);
                    12'h068: sh_dfdt <= merge32(sh_dfdt, w_data, w_strb);
                    12'h06C: sh_talign <= merge32(sh_talign, w_data, w_strb);
                    12'h070: sh_wsw <= merge32(sh_wsw, w_data, w_strb);
                    12'h074: sh_twin <= merge32(sh_twin, w_data, w_strb);
                    12'h078: sh_swn <= merge32(sh_swn, w_data, w_strb);
                    12'h07C: sh_blend <= merge32(sh_blend, w_data, w_strb);
                    12'h080: sh_abort <= merge32(sh_abort, w_data, w_strb);
                    12'h084: sh_stif <= merge32(sh_stif, w_data, w_strb);
                    12'h088: sh_strun <= merge32(sh_strun, w_data, w_strb);
                    12'h08C: sh_wstall <= merge32(sh_wstall, w_data, w_strb);
                    12'h090: sh_istall <= merge32(sh_istall, w_data, w_strb);
                    12'h094: sh_link <= merge32(sh_link, w_data, w_strb);
                    12'h098: sh_lead <= merge32(sh_lead, w_data, w_strb);
                    12'h09C: sh_vdc <= merge32(sh_vdc, w_data, w_strb);
                    12'h0A0: sh_ibase <= merge32(sh_ibase, w_data, w_strb);
                    12'h0A4: sh_ov <= merge32(sh_ov, w_data, w_strb);
                    12'h0A8: sh_uv <= merge32(sh_uv, w_data, w_strb);
                    12'h0AC: sh_ot <= merge32(sh_ot, w_data, w_strb);
                    12'h0B0: sh_obscfg <= merge32(sh_obscfg, w_data, w_strb);
                    12'h114: theta_in <= merge32(theta_in, w_data, w_strb);
                    12'h118: speed_in <= merge32(speed_in, w_data, w_strb);
                    12'h11C: seq_echo <= merge32({16'd0, seq_echo}, w_data, w_strb);
                    12'h120: begin
                        if (commit_merged[0]) begin
                            pend <= 1'b1;
                            pend_theta <= theta_in;
                            pend_speed <= speed_in;
                            pend_seq <= seq_echo;
                        end
                    end
                    default: begin end
                endcase
            end
        end
    end
endmodule
