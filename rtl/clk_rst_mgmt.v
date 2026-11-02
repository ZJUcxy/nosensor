`timescale 1ns / 1ps
// 100 MHz 控制时钟取自输入缓冲。19.2 MHz 由 MMCM 产生（VCO=960 MHz）。
// MMCM 无法同时精确输出 100.000 MHz 与 19.2 MHz，控制时基保持 10 ns，
// 以保证 4000 个时钟等于 40 µs。
module clk_rst_mgmt (
    input  wire        clk_in_i,
    input  wire        rst_hw_n_i,
    input  wire        sw_reset_i,
    output wire        clk_100m_o,
    output wire        clk_19m2_o,
    output wire        rst_n_100_o,
    output wire        rst_n_19_o,
    output wire        pwm_tick_o,
    output wire [10:0] carrier_cnt_o,
    output wire [15:0] valley_cnt_o,
    output wire        mmcm_locked_o
);
    wire locked;
    wire logic_reset = ~rst_hw_n_i | sw_reset_i | ~locked;

    reg [2:0] rst_ff_100;
    reg [2:0] rst_ff_19;
    reg [11:0] phase_cnt;
    reg [15:0] valley_cnt;
    reg        pwm_tick;

    assign pwm_tick_o    = pwm_tick;
    assign valley_cnt_o  = valley_cnt;
    assign mmcm_locked_o = locked;
    assign carrier_cnt_o = (phase_cnt < 12'd2000) ? phase_cnt[10:0]
                                                  : (12'd3999 - phase_cnt);

`ifndef SYNTHESIS
    reg        clk19_beh;
    reg [15:0] acc19;
    reg [4:0]  lock_cnt;
    assign clk_100m_o = clk_in_i;
    assign clk_19m2_o = clk19_beh;
    assign locked     = lock_cnt[4];

    initial begin
        clk19_beh = 1'b0;
        acc19     = 16'd0;
        lock_cnt  = 5'd0;
    end

    always @(posedge clk_in_i or negedge rst_hw_n_i) begin
        if (!rst_hw_n_i) begin
            acc19    <= 16'd0;
            clk19_beh <= 1'b0;
            lock_cnt <= 5'd0;
        end else begin
            if (!lock_cnt[4])
                lock_cnt <= lock_cnt + 5'd1;
            if (acc19 + 16'd384 >= 16'd1000) begin
                acc19     <= acc19 + 16'd384 - 16'd1000;
                clk19_beh <= ~clk19_beh;
            end else begin
                acc19 <= acc19 + 16'd384;
            end
        end
    end
`else
    wire clkfb;
    wire clkfb_buf;
    wire clk19_mmcm;
    wire clk100_buf;
    wire mmcm_rst = ~rst_hw_n_i;

    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(48.0),
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(10.0),
        .CLKOUT0_DIVIDE_F(50.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(5),
        .REF_JITTER1(0.010),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKOUT0(clk19_mmcm),
        .CLKOUT0B(),
        .CLKOUT1(),
        .CLKOUT1B(),
        .CLKOUT2(),
        .CLKOUT2B(),
        .CLKOUT3(),
        .CLKOUT3B(),
        .CLKOUT4(),
        .CLKOUT5(),
        .CLKOUT6(),
        .CLKFBOUT(clkfb),
        .CLKFBOUTB(),
        .LOCKED(locked),
        .CLKIN1(clk_in_i),
        .PWRDWN(1'b0),
        .RST(mmcm_rst),
        .CLKFBIN(clkfb_buf)
    );

    BUFG u_fb   (.I(clkfb),      .O(clkfb_buf));
    BUFG u_19   (.I(clk19_mmcm), .O(clk_19m2_o));
    BUFG u_100  (.I(clk_in_i),   .O(clk100_buf));
    assign clk_100m_o = clk100_buf;
`endif

    always @(posedge clk_100m_o or posedge logic_reset) begin
        if (logic_reset) begin
            rst_ff_100 <= 3'b000;
            phase_cnt  <= 12'd0;
            valley_cnt <= 16'd0;
            pwm_tick   <= 1'b0;
        end else begin
            rst_ff_100 <= {rst_ff_100[1:0], 1'b1};
            if (rst_ff_100[2]) begin
                if (phase_cnt == 12'd3999) begin
                    phase_cnt <= 12'd0;
                    pwm_tick  <= 1'b1;
                end else begin
                    phase_cnt <= phase_cnt + 12'd1;
                    pwm_tick  <= 1'b0;
                end
                // 消费沿看到的仍是加 1 前的序号
                if (pwm_tick)
                    valley_cnt <= valley_cnt + 16'd1;
            end else begin
                pwm_tick <= 1'b0;
            end
        end
    end

    always @(posedge clk_19m2_o or posedge logic_reset) begin
        if (logic_reset)
            rst_ff_19 <= 3'b000;
        else
            rst_ff_19 <= {rst_ff_19[1:0], 1'b1};
    end

    assign rst_n_100_o = rst_ff_100[2];
    assign rst_n_19_o  = rst_ff_19[2];
endmodule
