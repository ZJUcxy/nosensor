`timescale 1ns / 1ps
module tb_clk_rst_mgmt;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, sw = 0;
    wire c100, c19, r100, r19, tick, lock;
    wire [10:0] car;
    wire [15:0] val;
    clk_rst_mgmt dut (
        .clk_in_i(clk), .rst_hw_n_i(rst_n), .sw_reset_i(sw),
        .clk_100m_o(c100), .clk_19m2_o(c19), .rst_n_100_o(r100), .rst_n_19_o(r19),
        .pwm_tick_o(tick), .carrier_cnt_o(car), .valley_cnt_o(val), .mmcm_locked_o(lock)
    );
    integer ntick, gap, seen;
    reg tick_d;
    initial begin
        repeat (5) @(posedge clk); rst_n = 1;
        wait (lock && r100);
        ntick = 0; gap = 0; seen = 0; tick_d = 0;
        repeat (9000) begin
            @(posedge clk);
            if (tick && !tick_d) begin
                if (car !== 0) $fatal(1, "carrier %d", car);
                if (ntick == 0 && val !== 0) $fatal(1, "valley0 %d", val);
                if (ntick == 1 && val !== 1) $fatal(1, "valley1 %d", val);
                if (seen != 0 && gap != 4000) $fatal(1, "period %d", gap);
                ntick = ntick + 1;
                gap = 0;
                seen = 1;
            end
            gap = gap + 1;
            tick_d = tick;
        end
        if (ntick < 2) $fatal(1, "ticks %d", ntick);
        $display("PASS tb_clk_rst_mgmt");
        $finish;
    end
endmodule
