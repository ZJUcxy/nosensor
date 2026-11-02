`timescale 1ns / 1ps
module tb_clarke;
    reg signed [31:0] ia, ib;
    wire signed [31:0] a, b;
    clarke dut (.ia_i(ia), .ib_i(ib), .ialpha_o(a), .ibeta_o(b));
    initial begin
        ia = 0; ib = 0; #1;
        if (a !== 0 || b !== 0) $fatal(1, "zero");
        ia = 32'h40000000; ib = 0; #1;
        if (a !== 32'h40000000) $fatal(1, "alpha");
        if (b !== 32'sd619925131 && b !== 32'sd619925130 && b !== 32'sd619925132)
            $fatal(1, "beta %d", b);
        $display("PASS tb_clarke");
        $finish;
    end
endmodule
