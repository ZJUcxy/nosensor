`timescale 1ns / 1ps
module tb_amc1306_if;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    reg bit_i;
    wire c100, c19, r100, r19, tick, lock, mck, ovf, pulse;
    wire [10:0] car; wire [15:0] val;
    wire signed [31:0] ia, ib, ic;
    clk_rst_mgmt u_clk (
        .clk_in_i(clk), .rst_hw_n_i(rst_n), .sw_reset_i(1'b0),
        .clk_100m_o(c100), .clk_19m2_o(c19), .rst_n_100_o(r100), .rst_n_19_o(r19),
        .pwm_tick_o(tick), .carrier_cnt_o(car), .valley_cnt_o(val), .mmcm_locked_o(lock)
    );
    amc1306_if dut (
        .clk_100m_i(c100), .clk_19m2_i(c19), .rst_n_100_i(r100), .rst_n_19_i(r19),
        .data_a_i(bit_i), .data_b_i(1'b0), .data_c_i(1'b0),
        .data_inv_i(3'b000), .scale_i(32'h00004000), .dec_phase_i(8'd0),
        .pwm_tick_i(tick), .mck_o(mck), .ia_o(ia), .ib_o(ib), .ic_o(ic),
        .sinc_ovf_o(ovf), .s0_pulse_o(pulse)
    );
    integer n;
    initial begin
        bit_i = 1;
        repeat (8) @(posedge clk); rst_n = 1;
        for (n = 0; n < 40000; n = n + 1) begin
            @(posedge clk);
            if (ia === 32'h20000000 && ib === 32'hE0000000 && ic === 32'hE0000000) begin
                $display("PASS tb_amc1306_if");
                $finish;
            end
        end
        $fatal(1, "dc ia=%h ib=%h ic=%h", ia, ib, ic);
    end
endmodule
