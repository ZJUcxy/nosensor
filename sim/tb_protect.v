`timescale 1ns / 1ps
module tb_protect;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, fo = 1, fail = 0, ovf = 0, tick = 0, clr = 0;
    reg signed [31:0] ia, ib, ic, iq, w, octh, phth, wst, ist;
    reg [15:0] age, ocn, phn, linkto, mask;
    reg [3:0] state;
    reg [31:0] stif, strun;
    wire [15:0] fault, pri;
    wire block;
    protect dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .ia_i(ia), .ib_i(ib), .ic_i(ic),
        .iq_ref_i(iq), .omega_step_i(w), .ipm_fo_i(fo), .link_age_i(age), .state_i(state),
        .switch_fail_i(fail), .sinc_ovf_i(ovf), .pwm_tick_i(tick),
        .oc_th_i(octh), .oc_n_i(ocn), .ph_th_i(phth), .ph_n_i(phn),
        .stall_t_if_i(stif), .stall_t_run_i(strun), .w_stall_i(wst), .i_stall_i(ist),
        .link_to_i(linkto), .fault_mask_i(mask), .fault_clr_i(clr),
        .fault_o(fault), .block_o(block), .pri_o(pri)
    );
    initial begin
        ia = 0; ib = 0; ic = 0; iq = 0; w = 0; octh = 100; phth = 32'h7fffffff;
        ocn = 2; phn = 10; stif = 32'hfffffff; strun = 32'hfffffff;
        wst = 0; ist = 32'h7fffffff; age = 0; linkto = 15; mask = 16'h020e;
        state = 4'd5;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); ia = 1000; tick = 1;
        @(negedge clk); tick = 0;
        @(posedge clk);
        if (fault[0]) $fatal(1, "early oc");
        @(negedge clk); tick = 1;
        @(negedge clk); tick = 0;
        @(posedge clk); @(posedge clk);
        if (!fault[0] || !block || pri != 0) $fatal(1, "oc %h pri %d", fault, pri);
        @(negedge clk); fo = 0;
        repeat (8) @(posedge clk);
        if (!fault[6] || pri != 6) $fatal(1, "fo %h pri %d", fault, pri);
        $display("PASS tb_protect");
        $finish;
    end
endmodule
