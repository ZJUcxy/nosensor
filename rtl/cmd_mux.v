`timescale 1ns / 1ps
// 角度选择是组合逻辑。电流矢量超限时复用 vlim 的开方和除法，结果保持到输入再次变化。
module cmd_mux (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire [1:0]         mode_i,
    input  wire [31:0]        theta_if_i,
    input  wire [31:0]        theta_park_i,
    input  wire signed [31:0] id_if_i,
    input  wire signed [31:0] iq_if_i,
    input  wire signed [31:0] id_reg_i,
    input  wire signed [31:0] iq_reg_i,
    input  wire signed [31:0] i_cmd_max_i,
    output wire [31:0]        theta_o,
    output wire signed [31:0] id_ref_o,
    output wire signed [31:0] iq_ref_o
);
    wire signed [31:0] id_sel = (mode_i == 2'd1) ? id_if_i :
                                (mode_i == 2'd2) ? id_reg_i : 32'sd0;
    wire signed [31:0] iq_sel = (mode_i == 2'd1) ? iq_if_i :
                                (mode_i == 2'd2) ? iq_reg_i : 32'sd0;

    assign theta_o = (mode_i == 2'd1) ? theta_if_i : theta_park_i;

    reg signed [31:0] id_cap, iq_cap, max_cap;
    reg [1:0]         mode_cap;
    reg               start;
    reg               hold;
    reg signed [31:0] id_h, iq_h;

    wire signed [31:0] id_v, iq_v;
    wire               limited, done;
    wire               changed = (id_sel != id_cap) || (iq_sel != iq_cap) ||
                                 (i_cmd_max_i != max_cap) || (mode_i != mode_cap);

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            id_cap <= 0;
            iq_cap <= 0;
            max_cap <= 0;
            mode_cap <= 0;
            start <= 1'b0;
            hold <= 1'b0;
            id_h <= 0;
            iq_h <= 0;
        end else begin
            start <= 1'b0;
            if (changed) begin
                id_cap <= id_sel;
                iq_cap <= iq_sel;
                max_cap <= i_cmd_max_i;
                mode_cap <= mode_i;
                hold <= 1'b0;
                start <= 1'b1;
            end
            if (done) begin
                hold <= limited;
                id_h <= id_v;
                iq_h <= iq_v;
            end
        end
    end

    assign id_ref_o = hold ? id_h : id_sel;
    assign iq_ref_o = hold ? iq_h : iq_sel;

    vlim u_ilim (
        .clk_100m_i(clk_100m_i),
        .rst_n_i(rst_n_i),
        .start_i(start),
        .ud_i(id_sel),
        .uq_i(iq_sel),
        .umax_i(i_cmd_max_i),
        .ud_o(id_v),
        .uq_o(iq_v),
        .limited_o(limited),
        .done_o(done)
    );
endmodule
