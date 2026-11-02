`timescale 1ns / 1ps
module tb_axi_regs;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, tick = 0, acc = 0, drop = 0;
    reg [31:0] awaddr, wdata, araddr;
    reg awv, wv, arv, bready, rready;
    reg [3:0] wstrb;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    wire signed [31:0] kpd;
    wire pok, en, pend;
    axi_regs dut (
        .clk_100m_i(clk), .rst_n_i(rst_n),
        .s_axi_awaddr(awaddr), .s_axi_awvalid(awv), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wv), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arvalid(arv), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .pwm_tick_i(tick), .accept_i(acc), .drop_i(drop),
        .snap_seq_i(16'd7), .snap_ua_i(0), .snap_ub_i(0), .snap_ia_i(0), .snap_ib_i(0),
        .ia_i(0), .ib_i(0), .ic_i(0), .ialpha_i(0), .ibeta_i(0), .id_i(0), .iq_i(0),
        .ualpha_i(0), .ubeta_i(0), .theta_park_i(0), .theta_now_i(0), .omega_step_i(0),
        .valley_cnt_i(16'd3), .state_i(4'd1), .pwm_enable_i(0), .link_ok_i(0),
        .limited_i(0), .sinc_ovf_i(0), .fault_i(0), .pri_i(16'hffff), .age_i(16'hffff),
        .kp_d_o(kpd), .param_ok_o(pok), .enable_o(en), .pend_o(pend)
    );
    task axi_w;
        input [31:0] a, d;
        begin
            @(negedge clk); awaddr = a; wdata = d; wstrb = 4'hF; awv = 1; wv = 1; bready = 1;
            wait (bvalid); @(negedge clk); awv = 0; wv = 0;
            wait (!bvalid);
        end
    endtask
    task axi_r;
        input [31:0] a;
        begin
            @(negedge clk); araddr = a; arv = 1; rready = 1;
            wait (rvalid); @(negedge clk); arv = 0;
            wait (!rvalid);
        end
    endtask
    initial begin
        awv = 0; wv = 0; arv = 0; bready = 1; rready = 1; wstrb = 4'hF;
        repeat (4) @(posedge clk); rst_n = 1;
        axi_r(32'h0);
        if (rdata !== 32'h464F4331) $fatal(1, "id %h", rdata);
        axi_r(32'h14);
        if (rdata !== 32'h0000020e) $fatal(1, "mask %h", rdata);
        axi_r(32'h200);
        if (rdata !== 0) $fatal(1, "rsvd");
        axi_w(32'h2C, 32'h11);
        axi_r(32'h2C);
        if (rdata !== 0 || kpd !== 0) $fatal(1, "shadow leaked %h", rdata);
        @(negedge clk); tick = 1; @(negedge clk); tick = 0;
        axi_r(32'h2C);
        if (rdata !== 32'h11) $fatal(1, "loaded %h", rdata);
        axi_w(32'h114, 32'hAB);
        axi_w(32'h118, 32'h10);
        axi_w(32'h11C, 32'd4);
        axi_w(32'h120, 32'd1);
        if (!pend) $fatal(1, "pend");
        @(negedge clk); acc = 1; tick = 1; @(negedge clk); acc = 0; tick = 0;
        @(posedge clk);
        if (pend) $fatal(1, "pend clear");
        $display("PASS tb_axi_regs");
        $finish;
    end
endmodule
