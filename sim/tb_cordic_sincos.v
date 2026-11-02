`timescale 1ns / 1ps
module tb_cordic_sincos;
    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;
    reg [31:0] theta;
    reg start;
    wire signed [31:0] sin_o, cos_o;
    wire done;
    cordic_sincos dut (
        .clk_100m_i(clk), .rst_n_i(rst_n), .theta_i(theta), .start_i(start),
        .sin_o(sin_o), .cos_o(cos_o), .done_o(done)
    );
    integer k, err;
    reg [31:0] ths [0:7];
    reg signed [31:0] es [0:7];
    reg signed [31:0] ec [0:7];
    initial begin
        ths[0]=32'h00000000; es[0]=0;            ec[0]=2147483647;
        ths[1]=32'h20000000; es[1]=1518500249;   ec[1]=1518500249;
        ths[2]=32'h40000000; es[2]=2147483647;   ec[2]=0;
        ths[3]=32'h60000000; es[3]=1518500249;   ec[3]=-1518500250;
        ths[4]=32'h80000000; es[4]=0;            ec[4]=-2147483648;
        ths[5]=32'hA0000000; es[5]=-1518500250;  ec[5]=-1518500250;
        ths[6]=32'hC0000000; es[6]=-2147483648;  ec[6]=0;
        ths[7]=32'hE0000000; es[7]=-1518500250;  ec[7]=1518500249;
        start = 0; theta = 0;
        repeat (4) @(posedge clk); rst_n = 1;
        for (k = 0; k < 8; k = k + 1) begin
            @(negedge clk); theta = ths[k]; start = 1;
            @(negedge clk); start = 0;
            wait (done);
            @(posedge clk);
            err = sin_o - es[k]; if (err < 0) err = -err;
            if (err > 131072) $fatal(1, "sin %0d got %0d exp %0d", k, sin_o, es[k]);
            err = cos_o - ec[k]; if (err < 0) err = -err;
            if (err > 131072) $fatal(1, "cos %0d got %0d exp %0d", k, cos_o, ec[k]);
        end
        $display("PASS tb_cordic_sincos");
        $finish;
    end
endmodule
