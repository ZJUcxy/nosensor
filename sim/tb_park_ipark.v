`timescale 1ns / 1ps
module tb_park_ipark;
    reg signed [31:0] ia, ib, ud, uq, s, c;
    wire signed [31:0] id, iq, ua, ub;
    park_ipark dut (
        .ialpha_i(ia), .ibeta_i(ib), .ud_i(ud), .uq_i(uq),
        .sin_i(s), .cos_i(c), .id_o(id), .iq_o(iq), .ualpha_o(ua), .ubeta_o(ub)
    );
    integer eid, eiq;
    initial begin
        s = 0; c = 32'h7fffffff; ud = 0; uq = 0;
        ia = 32'h20000000; ib = 32'h10000000; #1;
        eid = id - ia; if (eid < 0) eid = -eid;
        eiq = iq - ib; if (eiq < 0) eiq = -eiq;
        if (eid > 4 || eiq > 4) $fatal(1, "park0 %d %d", id, iq);
        ud = 32'h20000000; uq = 32'h10000000; #1;
        eid = ua - ud; if (eid < 0) eid = -eid;
        eiq = ub - uq; if (eiq < 0) eiq = -eiq;
        if (eid > 4 || eiq > 4) $fatal(1, "ipark0 %d %d", ua, ub);
        $display("PASS tb_park_ipark");
        $finish;
    end
endmodule
