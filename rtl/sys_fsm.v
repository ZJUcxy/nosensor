`timescale 1ns / 1ps
// 启动顺序固定。运行中撤使能回到 READY，只有未屏蔽故障进入 FAULT。
module sys_fsm (
    input  wire        clk_100m_i,
    input  wire        rst_n_i,
    input  wire        enable_i,
    input  wire        param_ok_i,
    input  wire        mmcm_locked_i,
    input  wire        sinc_ready_i,
    input  wire [15:0] fault_i,
    input  wire        fault_clr_i,
    input  wire        switch_req_i,
    input  wire [1:0]  phase_i,
    input  wire        pwm_tick_i,
    input  wire [31:0] t_align_i,
    output wire [3:0]  state_o,
    output wire        pwm_enable_o,
    output wire [1:0]  mode_o,
    output wire        run_if_o
);
    localparam S_INIT = 4'd0;
    localparam S_READY = 4'd1;
    localparam S_ALIGN = 4'd2;
    localparam S_RAMP = 4'd3;
    localparam S_SWITCH = 4'd4;
    localparam S_SENS = 4'd5;
    localparam S_FAULT = 4'd6;

    reg [3:0] state;
    wire run_state = (state == S_ALIGN) || (state == S_RAMP) || (state == S_SWITCH) || (state == S_SENS);

    assign state_o = state;
    assign pwm_enable_o = run_state;
    assign run_if_o = (state == S_ALIGN) || (state == S_RAMP) || (state == S_SWITCH);
    assign mode_o = (state == S_SENS) ? 2'd2 : (run_if_o ? 2'd1 : 2'd0);

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i)
            state <= S_INIT;
        else if (state == S_FAULT) begin
            if (fault_clr_i && (fault_i == 16'd0) && !enable_i)
                state <= S_READY;
        end else if ((state != S_INIT) && (fault_i != 16'd0))
            state <= S_FAULT;
        else if (run_state && !enable_i)
            state <= S_READY;
        else begin
            case (state)
                S_INIT: begin
                    if (mmcm_locked_i && sinc_ready_i)
                        state <= (fault_i != 16'd0) ? S_FAULT : S_READY;
                end
                S_READY: begin
                    if (enable_i && param_ok_i)
                        state <= S_ALIGN;
                end
                S_ALIGN: begin
                    if ((phase_i != 2'd0) || (pwm_tick_i && (t_align_i == 32'd0)))
                        state <= S_RAMP;
                end
                S_RAMP: begin
                    if (switch_req_i)
                        state <= S_SWITCH;
                end
                S_SWITCH: begin
                    if (phase_i == 2'd3)
                        state <= S_SENS;
                end
                default: state <= S_READY;
            endcase
        end
    end
endmodule
