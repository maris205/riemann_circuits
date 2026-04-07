`timescale 1ns / 1ps
// ============================================================
// Lab 3: Hénon 映射 — 二维混沌迭代器
//
// x' = 1 - a·x² + y
// y' = b·x
//
// 学生任务:
//   1. 在 Lab 2 基础上扩展为双通道
//   2. 理解交叉耦合 (x→y, y→x)
//   3. 实现非自治冷却: a(n) 随步数变化
//   4. 导出 x-y 相图数据，画奇异吸引子
// ============================================================

module henon_iter #(
    parameter DW = 32,
    parameter FW = 28
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [DW-1:0]    a_param,  // a 参数 (或从 LUT 读取)
    input  wire signed [DW-1:0]    b_param,  // b = 0.3
    input  wire signed [DW-1:0]    x_init,
    input  wire signed [DW-1:0]    y_init,
    input  wire [15:0]             n_steps,

    output reg  signed [DW-1:0]    x_out,
    output reg  signed [DW-1:0]    y_out,
    output reg                     valid,
    output reg                     done
);

    localparam signed [DW-1:0] ONE = (1 <<< FW);

    reg [1:0] state;
    localparam S_IDLE = 0, S_ITER = 1, S_DONE = 2;

    reg signed [DW-1:0] x_reg, y_reg;
    reg [15:0] count;
    reg signed [2*DW-1:0] mult_tmp;
    reg signed [DW-1:0] x_sq, a_xsq, b_x;
    reg [2:0] pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; x_reg <= 0; y_reg <= 0;
            valid <= 0; done <= 0; count <= 0; pipe <= 0;
        end else begin
            valid <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= x_init;
                        y_reg <= y_init;
                        count <= 0; pipe <= 0;
                        state <= S_ITER;
                    end
                end

                S_ITER: begin
                    case (pipe)
                        3'd0: begin
                            // x²
                            mult_tmp = x_reg * x_reg;
                            x_sq <= mult_tmp[DW+FW-1:FW];
                            pipe <= 3'd1;
                        end
                        3'd1: begin
                            // a · x²
                            mult_tmp = a_param * x_sq;
                            a_xsq <= mult_tmp[DW+FW-1:FW];
                            // b · x (并行计算)
                            mult_tmp = b_param * x_reg;
                            b_x <= mult_tmp[DW+FW-1:FW];
                            pipe <= 3'd2;
                        end
                        3'd2: begin
                            // x' = 1 - a·x² + y
                            x_reg <= ONE - a_xsq + y_reg;
                            // y' = b·x
                            y_reg <= b_x;

                            x_out <= ONE - a_xsq + y_reg;
                            y_out <= b_x;
                            valid <= 1;
                            count <= count + 1;
                            pipe <= 3'd0;

                            if (count >= n_steps - 1)
                                state <= S_DONE;
                        end
                    endcase
                end

                S_DONE: begin
                    done <= 1;
                    if (start) state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
