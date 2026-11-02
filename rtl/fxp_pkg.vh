function signed [31:0] sat_s64;
    input signed [63:0] v;
    begin
        if (v > 64'sd2147483647)
            sat_s64 = 32'h7fffffff;
        else if (v < -64'sd2147483648)
            sat_s64 = 32'h80000000;
        else
            sat_s64 = v[31:0];
    end
endfunction

function signed [31:0] sat_add32;
    input signed [31:0] a;
    input signed [31:0] b;
    reg signed [32:0] s;
    begin
        s = {a[31], a} + {b[31], b};
        if (s > 33'sd2147483647)
            sat_add32 = 32'h7fffffff;
        else if (s < -33'sd2147483648)
            sat_add32 = 32'h80000000;
        else
            sat_add32 = s[31:0];
    end
endfunction

function [31:0] abs32;
    input signed [31:0] a;
    begin
        if (a == 32'h80000000)
            abs32 = 32'h80000000;
        else if (a[31])
            abs32 = -a;
        else
            abs32 = a;
    end
endfunction
