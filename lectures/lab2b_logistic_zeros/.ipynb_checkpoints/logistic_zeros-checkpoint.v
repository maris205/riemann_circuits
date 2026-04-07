`timescale 1ns / 1ps
// ============================================================
// Lab 2b: Non-Autonomous Logistic — Riemann Zero Extraction
// Fixed version: clean pipeline, no combinational hazards
// ============================================================

module logistic_zeros #(
    parameter DW = 32,
    parameter FW = 28,
    parameter LUT_DEPTH = 65536
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            start,
    input  wire [31:0]     n_steps,

    input  wire [15:0]     lut_waddr,
    input  wire [DW-1:0]   lut_wdata,
    input  wire            lut_wen,

    output reg signed [DW-1:0] x_out,
    output reg             valid,
    output reg             done
);

    localparam signed [DW-1:0] ONE = 32'h10000000;  // 1.0 in Q4.28
    localparam signed [DW-1:0] SAT_POS = 32'h20000000;  // +2.0
    localparam signed [DW-1:0] SAT_NEG = 32'hE0000000;  // -2.0

    // 冷却 LUT
    reg [DW-1:0] mu_lut [0:LUT_DEPTH-1];

    always @(posedge clk) begin
        if (lut_wen)
            mu_lut[lut_waddr] <= lut_wdata;
    end

    // 状态机
    reg [2:0] state;
    localparam S_IDLE = 0, S_READ_LUT = 1, S_CALC_XSQ = 2,
               S_CALC_MUXSQ = 3, S_UPDATE = 4, S_DONE = 5;

    reg signed [DW-1:0] x_reg;
    reg signed [DW-1:0] mu_val;
    reg signed [DW-1:0] x_sq;
    reg signed [DW-1:0] mu_xsq;
    reg signed [DW-1:0] x_new_val;
    reg [31:0] count;

    // 64-bit multiply helper
    reg signed [63:0] mul64;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x_reg <= 0;
            x_out <= 0;
            valid <= 0;
            done  <= 0;
            count <= 0;
        end else begin
            valid <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= 32'h08000000;  // 0.5 in Q4.28
                        count <= 0;
                        state <= S_READ_LUT;
                    end
                end

                // Stage 1: 读 μ(n) from LUT
                S_READ_LUT: begin
                    mu_val <= mu_lut[count[15:0]];
                    state <= S_CALC_XSQ;
                end

                // Stage 2: 计算 x²
                S_CALC_XSQ: begin
                    mul64 = x_reg * x_reg;          // Q4.28 * Q4.28 = Q8.56
                    x_sq <= mul64[59:28];            // 截取 Q4.28
                    state <= S_CALC_MUXSQ;
                end

                // Stage 3: 计算 μ · x²
                S_CALC_MUXSQ: begin
                    mul64 = mu_val * x_sq;           // Q4.28 * Q4.28 = Q8.56
                    mu_xsq <= mul64[59:28];          // 截取 Q4.28
                    state <= S_UPDATE;
                end

                // Stage 4: x_new = 1 - μ·x², 饱和, 输出
                S_UPDATE: begin
                    x_new_val = ONE - mu_xsq;

                    // 饱和限幅
                    if (x_new_val > SAT_POS)
                        x_reg <= SAT_POS;
                    else if (x_new_val < SAT_NEG)
                        x_reg <= SAT_NEG;
                    else
                        x_reg <= x_new_val;

                    // 输出
                    if (x_new_val > SAT_POS)
                        x_out <= SAT_POS;
                    else if (x_new_val < SAT_NEG)
                        x_out <= SAT_NEG;
                    else
                        x_out <= x_new_val;

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
