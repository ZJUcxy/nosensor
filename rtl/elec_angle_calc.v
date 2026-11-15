`timescale 1ns / 1ps
// 在 25 kHz 触发上升沿更新电角度。5 kHz 同步上升沿锁存当时的电角度、角速度和方向，
// 并由随后的第一个触发沿把输出重载为该电角度（n = 0）。
// 再往后的四个触发沿输出 θ ± ((ω * n) >> 8)，n = 1..4。
// 方向 1 为加、0 为减。结果保持在 0..8192：大于 8192 减 8192，小于 0 加 8192。
// 8192 与 0 是同一电角度，同步重载时原样保留输入里的 8192。
// clk 为 256 MHz 采样时钟。sync / trig 需与 clk 同步，高电平至少一个时钟。
module elec_angle_calc (
    input  wire        clk_256m_i,
    input  wire        rst_n_i,
    input  wire [31:0] theta_i,
    input  wire [31:0] omega_i,
    input  wire        sync_5k_i,
    input  wire        trig_25k_i,
    input  wire        dir_i,
    output reg  [31:0] theta_o
);
    localparam [31:0] THETA_MAX = 32'd8192;
    localparam [2:0]  N_MAX     = 3'd4;

    reg        sync_d;
    reg        trig_d;
    reg        sync_pend;
    reg        synced;
    reg [2:0]  n_hold;
    reg [31:0] theta_cap;
    reg [31:0] omega_cap;
    reg        dir_cap;
    reg [31:0] theta_base;
    reg [31:0] omega_base;
    reg        dir_base;

    wire sync_rise = sync_5k_i & ~sync_d;
    wire trig_rise = trig_25k_i & ~trig_d;
    wire [2:0] n_next = (n_hold >= N_MAX) ? N_MAX : (n_hold + 3'd1);

    // 同步与触发落在同一沿时用当前输入；否则用同步沿已经锁存的值。
    wire [31:0] theta_ld = sync_rise ? theta_i : theta_cap;
    wire [31:0] omega_ld = sync_rise ? omega_i : omega_cap;
    wire        dir_ld   = sync_rise ? dir_i   : dir_cap;

    function [31:0] fold_in;
        input [31:0] v;
        begin
            if (v > THETA_MAX)
                fold_in = v - THETA_MAX;
            else
                fold_in = v;
        end
    endfunction

    function [31:0] apply_delta;
        input [31:0] theta_b;
        input [31:0] omega_b;
        input [2:0]  n;
        input        dir;
        reg [63:0] prod;
        reg [31:0] delta;
        reg signed [31:0] raw;
        begin
            prod  = {32'd0, omega_b} * {61'd0, n};
            delta = prod[39:8];
            if (dir)
                raw = $signed(theta_b) + $signed(delta);
            else
                raw = $signed(theta_b) - $signed(delta);
            if (raw < 0)
                apply_delta = raw + 32'sd8192;
            else if (raw > 32'sd8192)
                apply_delta = raw - 32'sd8192;
            else
                apply_delta = raw[31:0];
        end
    endfunction

    always @(posedge clk_256m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            sync_d     <= 1'b0;
            trig_d     <= 1'b0;
            sync_pend  <= 1'b0;
            synced     <= 1'b0;
            n_hold     <= 3'd0;
            theta_cap  <= 32'd0;
            omega_cap  <= 32'd0;
            dir_cap    <= 1'b0;
            theta_base <= 32'd0;
            omega_base <= 32'd0;
            dir_base   <= 1'b0;
            theta_o    <= 32'd0;
        end else begin
            sync_d <= sync_5k_i;
            trig_d <= trig_25k_i;

            if (trig_rise && (sync_pend || sync_rise)) begin
                sync_pend  <= 1'b0;
                synced     <= 1'b1;
                n_hold     <= 3'd0;
                theta_base <= fold_in(theta_ld);
                omega_base <= omega_ld;
                dir_base   <= dir_ld;
                theta_o    <= fold_in(theta_ld);
                if (sync_rise) begin
                    theta_cap <= theta_i;
                    omega_cap <= omega_i;
                    dir_cap   <= dir_i;
                end
            end else if (sync_rise) begin
                sync_pend <= 1'b1;
                theta_cap <= theta_i;
                omega_cap <= omega_i;
                dir_cap   <= dir_i;
            end else if (trig_rise && synced) begin
                n_hold  <= n_next;
                theta_o <= apply_delta(theta_base, omega_base, n_next, dir_base);
            end
        end
    end
endmodule
