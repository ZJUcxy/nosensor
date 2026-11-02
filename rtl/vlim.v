`timescale 1ns / 1ps
// 矢量限幅。未超限时一拍直通。超限时先用整数开方求模，再对两轴做恢复除法。
// 对应参考模型 vlim_scale。
module vlim (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire               start_i,
    input  wire signed [31:0] ud_i,
    input  wire signed [31:0] uq_i,
    input  wire signed [31:0] umax_i,
    output reg  signed [31:0] ud_o,
    output reg  signed [31:0] uq_o,
    output reg                limited_o,
    output reg                done_o
);
`include "fxp_pkg.vh"
    localparam S_IDLE = 2'd0;
    localparam S_SQRT = 2'd1;
    localparam S_DIV  = 2'd2;

    reg [1:0]  st;
    reg [5:0]  step;
    reg        axis;
    reg [63:0] x, c, d;
    reg [63:0] num, rem, quot;
    reg signed [31:0] ud_l, uq_l, umax_l, ud_hold;
    reg        sign_d, sign_q;
    reg [31:0] mag;

    wire signed [31:0] umax_p = (umax_i < 0) ? 32'sd0 : umax_i;
    wire signed [63:0] sq_d = ud_i * ud_i;
    wire signed [63:0] sq_q = uq_i * uq_i;
    wire signed [63:0] sq_m = umax_p * umax_p;
    wire [63:0] mag2 = $unsigned(sq_d) + $unsigned(sq_q);
    wire [63:0] lim2 = $unsigned(sq_m);
    wire [63:0] c_sum = c + d;
    wire [63:0] c_next = (x >= c_sum) ? ((c >> 1) + d) : (c >> 1);
    wire [63:0] rem_sh = {rem[62:0], num[63]};
    wire        ge = (mag != 0) && (rem_sh >= {32'd0, mag});
    wire [63:0] quot_n = {quot[62:0], ge};
    wire [63:0] rem_n = ge ? (rem_sh - {32'd0, mag}) : rem_sh;

    function signed [31:0] apply_quot;
        input        sgn;
        input [63:0] qv;
        reg   [31:0] lo;
        begin
            lo = qv[31:0];
            if (qv[63:31] != 0 && qv[63:31] != {33{1'b0}}) begin
                if (|qv[63:32] || qv[31])
                    apply_quot = sgn ? 32'h80000000 : 32'h7fffffff;
                else
                    apply_quot = sgn ? -lo : lo;
            end else if (sgn) begin
                if (lo == 32'h80000000 || lo[31])
                    apply_quot = 32'h80000000;
                else
                    apply_quot = -$signed({1'b0, lo});
            end else begin
                if (lo[31])
                    apply_quot = 32'h7fffffff;
                else
                    apply_quot = $signed({1'b0, lo});
            end
        end
    endfunction

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            st <= S_IDLE;
            step <= 6'd0;
            axis <= 1'b0;
            x <= 0; c <= 0; d <= 0;
            num <= 0; rem <= 0; quot <= 0;
            ud_l <= 0; uq_l <= 0; umax_l <= 0; ud_hold <= 0;
            sign_d <= 0; sign_q <= 0; mag <= 0;
            ud_o <= 0; uq_o <= 0;
            limited_o <= 1'b0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            case (st)
                S_IDLE: begin
                    if (start_i) begin
                        ud_l   <= ud_i;
                        uq_l   <= uq_i;
                        umax_l <= (umax_i < 0) ? 32'sd0 : umax_i;
                        if (umax_i <= 0) begin
                            ud_o <= 0;
                            uq_o <= 0;
                            limited_o <= 1'b0;
                            done_o <= 1'b1;
                        end else if (mag2 <= lim2) begin
                            ud_o <= ud_i;
                            uq_o <= uq_i;
                            limited_o <= 1'b0;
                            done_o <= 1'b1;
                        end else begin
                            x <= mag2;
                            c <= 64'd0;
                            d <= 64'h4000_0000_0000_0000;
                            step <= 6'd0;
                            st <= S_SQRT;
                        end
                    end
                end
                S_SQRT: begin
                    if (x >= c_sum) begin
                        x <= x - c_sum;
                        c <= (c >> 1) + d;
                    end else begin
                        c <= c >> 1;
                    end
                    d <= d >> 2;
                    if (step == 6'd31) begin
                        mag <= c_next[31:0];
                        sign_d <= ud_l[31];
                        sign_q <= uq_l[31];
                        num <= {32'd0, abs32(ud_l)} * {32'd0, umax_l};
                        rem <= 64'd0;
                        quot <= 64'd0;
                        step <= 6'd0;
                        axis <= 1'b0;
                        st <= S_DIV;
                    end else begin
                        step <= step + 6'd1;
                    end
                end
                S_DIV: begin
                    rem  <= rem_n;
                    quot <= quot_n;
                    num  <= {num[62:0], 1'b0};
                    if (step == 6'd63) begin
                        if (!axis) begin
                            ud_hold <= apply_quot(sign_d, quot_n);
                            num <= {32'd0, abs32(uq_l)} * {32'd0, umax_l};
                            rem <= 64'd0;
                            quot <= 64'd0;
                            step <= 6'd0;
                            axis <= 1'b1;
                        end else begin
                            ud_o <= ud_hold;
                            uq_o <= apply_quot(sign_q, quot_n);
                            limited_o <= 1'b1;
                            done_o <= 1'b1;
                            st <= S_IDLE;
                        end
                    end else begin
                        step <= step + 6'd1;
                    end
                end
                default: st <= S_IDLE;
            endcase
        end
    end
endmodule
