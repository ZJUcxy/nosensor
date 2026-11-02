`timescale 1ns / 1ps

module cordic_sincos (
    input  wire               clk_100m_i,
    input  wire               rst_n_i,
    input  wire [31:0]        theta_i,
    input  wire               start_i,
    output reg  signed [31:0] sin_o,
    output reg  signed [31:0] cos_o,
    output reg                done_o
);
    localparam signed [31:0] X0 = 32'sd1304065748;

    function [31:0] atan_tab;
        input [3:0] idx;
        begin
            case (idx)
                4'd0:  atan_tab = 32'h20000000;
                4'd1:  atan_tab = 32'h12E4051E;
                4'd2:  atan_tab = 32'h09FB385B;
                4'd3:  atan_tab = 32'h051111D4;
                4'd4:  atan_tab = 32'h028B0D43;
                4'd5:  atan_tab = 32'h0145D7E1;
                4'd6:  atan_tab = 32'h00A2F61E;
                4'd7:  atan_tab = 32'h00517C55;
                4'd8:  atan_tab = 32'h0028BE53;
                4'd9:  atan_tab = 32'h00145F2F;
                4'd10: atan_tab = 32'h000A2F98;
                4'd11: atan_tab = 32'h000517CC;
                4'd12: atan_tab = 32'h00028BE6;
                4'd13: atan_tab = 32'h000145F3;
                4'd14: atan_tab = 32'h0000A2FA;
                default: atan_tab = 32'h0000517D;
            endcase
        end
    endfunction

    reg [1:0]         quad;
    reg signed [31:0] x_r, y_r, z_r;
    reg [4:0]         stage;
    reg               busy;

    wire signed [31:0] x_shift = x_r >>> stage[3:0];
    wire signed [31:0] y_shift = y_r >>> stage[3:0];
    wire signed [31:0] ang     = atan_tab(stage[3:0]);

    always @(posedge clk_100m_i or negedge rst_n_i) begin
        if (!rst_n_i) begin
            quad  <= 2'b00;
            x_r   <= 32'sd0;
            y_r   <= 32'sd0;
            z_r   <= 32'sd0;
            stage <= 5'd0;
            busy  <= 1'b0;
            sin_o <= 32'sd0;
            cos_o <= 32'sd0;
            done_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (!busy) begin
                if (start_i) begin
                    quad  <= theta_i[31:30];
                    x_r   <= X0;
                    y_r   <= 32'sd0;
                    z_r   <= {2'b00, theta_i[29:0]};
                    stage <= 5'd0;
                    busy  <= 1'b1;
                end
            end else if (z_r[31]) begin
                x_r   <= x_r + y_shift;
                y_r   <= y_r - x_shift;
                z_r   <= z_r + ang;
                stage <= stage + 5'd1;
                if (stage == 5'd15) begin
                    busy <= 1'b0;
                    done_o <= 1'b1;
                    case (quad)
                        2'b00: begin sin_o <= y_r - x_shift; cos_o <= x_r + y_shift; end
                        2'b01: begin sin_o <= x_r + y_shift; cos_o <= -(y_r - x_shift); end
                        2'b10: begin sin_o <= -(y_r - x_shift); cos_o <= -(x_r + y_shift); end
                        default: begin sin_o <= -(x_r + y_shift); cos_o <= y_r - x_shift; end
                    endcase
                end
            end else begin
                x_r   <= x_r - y_shift;
                y_r   <= y_r + x_shift;
                z_r   <= z_r - ang;
                stage <= stage + 5'd1;
                if (stage == 5'd15) begin
                    busy <= 1'b0;
                    done_o <= 1'b1;
                    case (quad)
                        2'b00: begin sin_o <= y_r + x_shift; cos_o <= x_r - y_shift; end
                        2'b01: begin sin_o <= x_r - y_shift; cos_o <= -(y_r + x_shift); end
                        2'b10: begin sin_o <= -(y_r + x_shift); cos_o <= -(x_r - y_shift); end
                        default: begin sin_o <= -(x_r - y_shift); cos_o <= y_r + x_shift; end
                    endcase
                end
            end
        end
    end
endmodule
