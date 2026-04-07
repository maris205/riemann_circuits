`timescale 1ns / 1ps
// ============================================================
// Lab 3b: Non-Autonomous Hénon — Riemann Zero Extraction
//
// x' = 1 - a(n)·x² + y
// y' = b·x
//
// 冷却: a(n) = a_dyna + k_opt / ln(n + c_offset)²
// 约束: a(1) = a_c + δa = 1.035,  a(N) ≈ a_c = 1.02
//
// 参数 (论文最优):
//   a_c = 1.02, δa = 0.015, b = 0.3, N = 200000, c_offset = 10
//
// 对应 SPICE: experiments/henon_nonautonomous.cir
// ============================================================

module henon_zeros #(
    parameter DW = 32,
    parameter FW = 28,
    parameter LUT_DEPTH = 65536
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,
    input  wire [31:0]     n_steps,
    input  wire signed [DW-1:0] b_param,  // b = 0.3 in Q4.28

    // 冷却 LUT
    input  wire [15:0]     lut_waddr,
    input  wire [DW-1:0]   lut_wdata,
    input  wire            lut_wen,

    output reg signed [DW-1:0] x_out,
    output reg signed [DW-1:0] y_out,
    output reg             valid,
    output reg             done
);

    // Q4.28 constants
    localparam signed [DW-1:0] ONE     = 32'sh10000000;  // 1.0
    localparam signed [DW-1:0] SAT_POS = 32'sh20000000;  // +2.0
    localparam signed [DW-1:0] SAT_NEG = 32'shE0000000;  // -2.0

    // 冷却 LUT
    reg [DW-1:0] a_lut [0:LUT_DEPTH-1];

    always @(posedge clk) begin
        if (lut_wen)
            a_lut[lut_waddr] <= lut_wdata;
    end

    // 状态机
    reg [2:0] state;
    localparam S_IDLE = 0, S_READ_LUT = 1, S_CALC_XSQ = 2,
               S_CALC_AXSQ = 3, S_CALC_BY = 4, S_UPDATE = 5, S_DONE = 6;

    reg signed [DW-1:0] x_reg, y_reg;
    reg signed [DW-1:0] a_val;        // a(n) from LUT
    reg signed [DW-1:0] x_sq;         // x²
    reg signed [DW-1:0] a_xsq;        // a·x²
    reg signed [DW-1:0] b_x;          // b·x
    reg signed [DW-1:0] x_new, y_new;
    reg [31:0] count;
    reg signed [63:0] mul64;

    // Saturation
    function signed [DW-1:0] sat;
        input signed [DW-1:0] val;
        sat = (val > SAT_POS) ? SAT_POS :
              (val < SAT_NEG) ? SAT_NEG : val;
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x_reg <= 0; y_reg <= 0;
            x_out <= 0; y_out <= 0;
            valid <= 0; done <= 0;
            count <= 0;
        end else begin
            valid <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= 32'sh01999999;  // 0.1
                        y_reg <= 32'sh01999999;  // 0.1
                        count <= 0;
                        state <= S_READ_LUT;
                    end
                end

                // Stage 1: read a(n) from LUT
                S_READ_LUT: begin
                    a_val <= a_lut[count[15:0]];
                    state <= S_CALC_XSQ;
                end

                // Stage 2: x² = x * x
                S_CALC_XSQ: begin
                    mul64 = x_reg * x_reg;
                    x_sq <= mul64[59:28];
                    state <= S_CALC_AXSQ;
                end

                // Stage 3: a·x²
                S_CALC_AXSQ: begin
                    mul64 = a_val * x_sq;
                    a_xsq <= mul64[59:28];
                    state <= S_CALC_BY;
                end

                // Stage 4: b·x (parallel with computing x_new)
                S_CALC_BY: begin
                    mul64 = b_param * x_reg;
                    b_x <= mul64[59:28];
                    // x_new = 1 - a·x² + y
                    x_new = ONE - a_xsq + y_reg;
                    state <= S_UPDATE;
                end

                // Stage 5: update and output
                S_UPDATE: begin
                    x_reg <= sat(x_new);
                    y_reg <= sat(b_x);
                    x_out <= sat(x_new);
                    y_out <= sat(b_x);
                    valid <= 1;
                    count <= count + 1;

                    if (count >= n_steps - 1)
                        state <= S_DONE;
                    else
                        state <= S_READ_LUT;
                end

                S_DONE: begin
                    done <= 1;
                    if (start) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
