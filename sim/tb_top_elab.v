`timescale 1ns / 1ps
module tb_top_elab;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    wire mck, uh, ul, vh, vl, wh, wl;
    wire [3:0] led;
    wire awready, wready, bvalid, arready, rvalid;
    wire [1:0] bresp, rresp;
    wire [31:0] rdata;
    top_integration dut (
        .clk_in_i(clk), .rst_hw_n_i(rst_n),
        .amc_data_a_i(1'b1), .amc_data_b_i(1'b1), .amc_data_c_i(1'b1),
        .amc_mck_o(mck),
        .pwm_uh_o(uh), .pwm_ul_o(ul), .pwm_vh_o(vh), .pwm_vl_o(vl), .pwm_wh_o(wh), .pwm_wl_o(wl),
        .ipm_fo_i(1'b1), .led_o(led),
        .s_axi_awaddr(32'd0), .s_axi_awvalid(1'b0), .s_axi_awready(awready),
        .s_axi_wdata(32'd0), .s_axi_wstrb(4'hF), .s_axi_wvalid(1'b0), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(32'd0), .s_axi_arvalid(1'b0), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(1'b1)
    );
    initial begin
        repeat (20) @(posedge clk);
        rst_n = 1;
        repeat (200) @(posedge clk);
        if (uh !== 1'b0 || ul !== 1'b0) begin
            $display("FAIL safe pwm %b %b", uh, ul);
            $fatal(1);
        end
        $display("PASS tb_top_elab");
        $finish;
    end
endmodule
