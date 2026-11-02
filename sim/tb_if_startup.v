`timescale 1ns / 1ps
module tb_if_startup;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, run = 0, dir = 0, tick = 0, obs = 0, drop = 0;
    reg [31:0] thnow, twin, tabort, talign, slewn;
    reg signed [31:0] step, istart, dfdt, wsw, idr, iqr;
    reg [15:0] swn, blend;
    wire signed [31:0] id, iq;
    wire [31:0] th;
    wire [1:0] phase;
    wire req, fail;
    if_startup dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .run_i(run), .dir_i(dir), .pwm_tick_i(tick),
        .theta_now_i(thnow), .omega_step_i(step), .obs_new_i(obs), .drop_i(drop),
        .i_start_i(istart), .dfdt_i(dfdt), .t_align_i(talign), .i_slew_n_i(slewn),
        .w_switch_i(wsw), .theta_win_i(twin), .switch_n_i(swn), .blend_n_i(blend),
        .theta_abort_i(tabort), .id_reg_i(idr), .iq_reg_i(iqr),
        .id_ref_o(id), .iq_ref_o(iq), .theta_o(th), .phase_o(phase),
        .switch_req_o(req), .switch_fail_o(fail)
    );
    integer k;
    initial begin
        thnow = 0; step = 1000; istart = 1000; dfdt = 0; talign = 0; slewn = 0;
        wsw = 0; twin = 32'h20000000; swn = 1; blend = 1; tabort = 32'h7fffffff;
        idr = 0; iqr = 0;
        repeat (3) @(posedge clk); rst_n = 1;
        @(negedge clk); run = 1; tick = 1;
        @(negedge clk); tick = 0;
        repeat (3) @(posedge clk);
        if (phase != 2'd1) $fatal(1, "align skip %d", phase);
        @(negedge clk); thnow = 32'hE6666666; obs = 1;
        @(negedge clk); obs = 0;
        repeat (4) @(posedge clk);
        if (!req || phase != 2'd2) $fatal(1, "switch p=%d req=%b th=%h", phase, req, th);
        @(negedge clk); thnow = 32'h40000000; tabort = 32'd1000;
        begin : abort_watch
            reg saw;
            saw = 0;
            repeat (6) begin
                @(posedge clk);
                if (fail) saw = 1;
            end
            if (!saw) $fatal(1, "abort");
        end
        $display("PASS tb_if_startup");
        $finish;
    end
endmodule
