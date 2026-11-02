`timescale 1ns / 1ps
module tb_svpwm;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, done = 0, tick = 0, en = 0, blk = 0, pol = 0;
    reg signed [31:0] ua, ub;
    reg [10:0] car;
    reg [8:0] dead;
    wire uh, ul, vh, vl, wh, wl;
    svpwm dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .ualpha_i(ua), .ubeta_i(ub),
        .calc_done_i(done), .pwm_tick_i(tick), .carrier_cnt_i(car),
        .dead_ticks_i(dead), .enable_i(en), .block_i(blk), .pol_inv_i(pol),
        .pwm_uh_o(uh), .pwm_ul_o(ul), .pwm_vh_o(vh), .pwm_vl_o(vl), .pwm_wh_o(wh), .pwm_wl_o(wl)
    );
    task pump;
        begin
            @(negedge clk); done = 1; @(negedge clk); done = 0;
            @(negedge clk); tick = 1; @(negedge clk); tick = 0;
            @(posedge clk);
        end
    endtask
    initial begin
        ua = 0; ub = 0; car = 0; dead = 0;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); en = 1;
        pump();
        car = 0; @(posedge clk); @(posedge clk);
        if ({uh,ul,vh,vl,wh,wl} !== 6'b101010) $fatal(1, "zero %b", {uh,ul,vh,vl,wh,wl});
        ua = 32'sd1859775393; ub = 32'h40000000;
        pump();
        car = 0; @(posedge clk); @(posedge clk);
        if ({uh,vh,wh} !== 3'b110) $fatal(1, "vec hi %b", {uh,vh,wh});
        car = 11'd1500; @(posedge clk); @(posedge clk);
        if ({uh,ul,vh,vl,wh,wl} !== 6'b100101) $fatal(1, "mid %b", {uh,ul,vh,vl,wh,wl});
        @(negedge clk); en = 0;
        @(posedge clk);
        if ({uh,ul,vh,vl,wh,wl} !== 6'b000000) $fatal(1, "safe");
        @(negedge clk); en = 1; dead = 9'd5; car = 0;
        @(posedge clk); @(posedge clk);
        if (uh & ul) $fatal(1, "interlock");
        $display("PASS tb_svpwm");
        $finish;
    end
endmodule
