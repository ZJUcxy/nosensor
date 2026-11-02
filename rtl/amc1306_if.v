`timescale 1ns / 1ps
module amc1306_if (
    input  wire               clk_100m_i,
    input  wire               clk_19m2_i,
    input  wire               rst_n_100_i,
    input  wire               rst_n_19_i,
    input  wire               data_a_i,
    input  wire               data_b_i,
    input  wire               data_c_i,
    input  wire [2:0]         data_inv_i,
    input  wire signed [31:0] scale_i,
    input  wire [7:0]         dec_phase_i,
    input  wire               pwm_tick_i,
    output wire               mck_o,
    output wire signed [31:0] ia_o,
    output wire signed [31:0] ib_o,
    output wire signed [31:0] ic_o,
    output wire               sinc_ovf_o,
    output wire               s0_pulse_o
);
`include "fxp_pkg.vh"
    assign mck_o = clk_19m2_i;

    wire signed [1:0] xa = (data_a_i ^ data_inv_i[0]) ? 2'sd1 : -2'sd1;
    wire signed [1:0] xb = (data_b_i ^ data_inv_i[1]) ? 2'sd1 : -2'sd1;
    wire signed [1:0] xc = (data_c_i ^ data_inv_i[2]) ? 2'sd1 : -2'sd1;

    reg signed [31:0] i1_a, i2_a, i3_a;
    reg signed [31:0] i1_b, i2_b, i3_b;
    reg signed [31:0] i1_c, i2_c, i3_c;
    reg signed [31:0] z1_a, z2_a, z3_a;
    reg signed [31:0] z1_b, z2_b, z3_b;
    reg signed [31:0] z1_c, z2_c, z3_c;
    reg [7:0]         osr_cnt;
    reg [1:0]         win_cnt;
    reg               arm;
    reg               s0_toggle;
    reg signed [31:0] cap_a, cap_b, cap_c;
    reg               cap_ovf;

    wire signed [31:0] n1_a = i1_a + xa;
    wire signed [31:0] n2_a = i2_a + n1_a;
    wire signed [31:0] n3_a = i3_a + n2_a;
    wire signed [31:0] n1_b = i1_b + xb;
    wire signed [31:0] n2_b = i2_b + n1_b;
    wire signed [31:0] n3_b = i3_b + n2_b;
    wire signed [31:0] n1_c = i1_c + xc;
    wire signed [31:0] n2_c = i2_c + n1_c;
    wire signed [31:0] n3_c = i3_c + n2_c;

    wire signed [31:0] c1_a = n3_a - z1_a;
    wire signed [31:0] c2_a = c1_a - z2_a;
    wire signed [31:0] c3_a = c2_a - z3_a;
    wire signed [31:0] c1_b = n3_b - z1_b;
    wire signed [31:0] c2_b = c1_b - z2_b;
    wire signed [31:0] c3_b = c2_b - z3_b;
    wire signed [31:0] c1_c = n3_c - z1_c;
    wire signed [31:0] c2_c = c1_c - z2_c;
    wire signed [31:0] c3_c = c2_c - z3_c;

    wire [7:0] dump_at = 8'hff - dec_phase_i;
    wire       dump    = (osr_cnt == dump_at);

    function signed [31:0] scale_norm;
        input signed [31:0] comb;
        input signed [31:0] scale;
        reg signed [31:0] norm;
        reg signed [63:0] prod;
        begin
            norm = comb >>> 24;
            prod = norm * scale;
            scale_norm = sat_s64(prod <<< 15);
        end
    endfunction

    function ovf_norm;
        input signed [31:0] comb;
        input signed [31:0] scale;
        reg signed [31:0] norm;
        reg signed [63:0] sh;
        begin
            norm = comb >>> 24;
            sh   = (norm * scale) <<< 15;
            ovf_norm = (sh > 64'sd2147483647) || (sh < -64'sd2147483648);
        end
    endfunction

    always @(posedge clk_19m2_i or negedge rst_n_19_i) begin
        if (!rst_n_19_i) begin
            i1_a <= 0; i2_a <= 0; i3_a <= 0;
            i1_b <= 0; i2_b <= 0; i3_b <= 0;
            i1_c <= 0; i2_c <= 0; i3_c <= 0;
            z1_a <= 0; z2_a <= 0; z3_a <= 0;
            z1_b <= 0; z2_b <= 0; z3_b <= 0;
            z1_c <= 0; z2_c <= 0; z3_c <= 0;
            osr_cnt <= 8'd0;
            win_cnt <= 2'd0;
            arm <= 1'b0;
            s0_toggle <= 1'b0;
            cap_a <= 0; cap_b <= 0; cap_c <= 0;
            cap_ovf <= 1'b0;
        end else begin
            i1_a <= n1_a; i2_a <= n2_a; i3_a <= n3_a;
            i1_b <= n1_b; i2_b <= n2_b; i3_b <= n3_b;
            i1_c <= n1_c; i2_c <= n2_c; i3_c <= n3_c;
            if (arm) begin
                s0_toggle <= ~s0_toggle;
                arm <= 1'b0;
            end
            if (dump) begin
                z1_a <= n3_a; z2_a <= c1_a; z3_a <= c2_a;
                z1_b <= n3_b; z2_b <= c1_b; z3_b <= c2_b;
                z1_c <= n3_c; z2_c <= c1_c; z3_c <= c2_c;
                if (win_cnt == 2'd0) begin
                    cap_a <= scale_norm(c3_a, scale_i);
                    cap_b <= scale_norm(c3_b, scale_i);
                    cap_c <= scale_norm(c3_c, scale_i);
                    cap_ovf <= ovf_norm(c3_a, scale_i) | ovf_norm(c3_b, scale_i) | ovf_norm(c3_c, scale_i);
                    arm <= 1'b1;
                end
                win_cnt <= (win_cnt == 2'd2) ? 2'd0 : win_cnt + 2'd1;
            end
            if (osr_cnt == 8'hff)
                osr_cnt <= 8'd0;
            else
                osr_cnt <= osr_cnt + 8'd1;
        end
    end

    (* ASYNC_REG = "TRUE" *) reg [2:0] cdc_s0_ff;
    reg signed [31:0] ia_hold, ib_hold, ic_hold;
    reg ovf_hold;
    reg [15:0] phase_delta;
    reg [15:0] phase_cnt;
    reg        s0_pulse;

    wire s0_edge = cdc_s0_ff[2] ^ cdc_s0_ff[1];

    always @(posedge clk_100m_i or negedge rst_n_100_i) begin
        if (!rst_n_100_i) begin
            cdc_s0_ff <= 3'b000;
            ia_hold <= 0; ib_hold <= 0; ic_hold <= 0;
            ovf_hold <= 1'b0;
            phase_delta <= 16'd0;
            phase_cnt <= 16'd0;
            s0_pulse <= 1'b0;
        end else begin
            cdc_s0_ff <= {cdc_s0_ff[1:0], s0_toggle};
            s0_pulse <= s0_edge;
            if (s0_edge) begin
                ia_hold <= cap_a;
                ib_hold <= cap_b;
                ic_hold <= cap_c;
                ovf_hold <= cap_ovf;
                phase_delta <= pwm_tick_i ? 16'd0 : phase_cnt;
            end
            if (pwm_tick_i)
                phase_cnt <= 16'd0;
            else if (!s0_edge && phase_cnt != 16'hffff)
                phase_cnt <= phase_cnt + 16'd1;
        end
    end

    assign ia_o = ia_hold;
    assign ib_o = ib_hold;
    assign ic_o = ic_hold;
    assign sinc_ovf_o = ovf_hold;
    assign s0_pulse_o = s0_pulse;
endmodule
