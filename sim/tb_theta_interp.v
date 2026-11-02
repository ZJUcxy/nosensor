`timescale 1ns / 1ps
module tb_theta_interp;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, tick = 0, acc = 0;
    reg [31:0] thin; reg signed [31:0] step; reg [4:0] n; reg signed [7:0] lead;
    wire [31:0] now, park; wire signed [31:0] w; wire [15:0] age;
    theta_interp dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .pwm_tick_i(tick), .accept_i(acc),
        .theta_in_i(thin), .omega_step_i(step), .n_i(n), .angle_lead_i(lead),
        .theta_now_o(now), .theta_park_o(park), .omega_step_o(w), .link_age_o(age)
    );
    initial begin
        thin = 32'h10; step = 32'sd100; n = 0; lead = 8'sd2;
        repeat (3) @(posedge clk); rst_n = 1;
        @(posedge clk);
        if (age !== 16'hffff) $fatal(1, "age reset");
        @(negedge clk); acc = 1; tick = 1;
        @(negedge clk); acc = 0; tick = 0;
        if (now !== 32'h10 || age !== 0 || park !== (32'h10 + 32'd200))
            $fatal(1, "accept %h %h %d", now, park, age);
        @(negedge clk); tick = 1; @(negedge clk); tick = 0;
        if (now !== 32'h10 + 32'd100 || age !== 1) $fatal(1, "extrap %h %d", now, age);
        $display("PASS tb_theta_interp");
        $finish;
    end
endmodule
