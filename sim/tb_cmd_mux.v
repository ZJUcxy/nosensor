`timescale 1ns / 1ps
module tb_cmd_mux;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0;
    reg [1:0] mode;
    reg [31:0] tif, tpk;
    reg signed [31:0] idif, iqif, idr, iqr, imax;
    wire [31:0] t; wire signed [31:0] id, iq;
    cmd_mux dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .mode_i(mode),
        .theta_if_i(tif), .theta_park_i(tpk),
        .id_if_i(idif), .iq_if_i(iqif), .id_reg_i(idr), .iq_reg_i(iqr),
        .i_cmd_max_i(imax), .theta_o(t), .id_ref_o(id), .iq_ref_o(iq)
    );
    initial begin
        mode = 0; tif = 1; tpk = 2; idif = 9; iqif = 8; idr = 7; iqr = 6; imax = 32'h7fffffff;
        repeat (3) @(posedge clk); rst_n = 1;
        #1;
        if (id !== 0 || iq !== 0 || t !== 2) $fatal(1, "mode0");
        mode = 1; #1;
        if (id !== 9 || iq !== 8 || t !== 1) $fatal(1, "mode1");
        mode = 2; #1;
        if (id !== 7 || iq !== 6 || t !== 2) $fatal(1, "mode2");
        $display("PASS tb_cmd_mux");
        $finish;
    end
endmodule
