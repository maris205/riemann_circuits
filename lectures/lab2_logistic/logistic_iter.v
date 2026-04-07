`timescale 1ns / 1ps
// ============================================================
// Lab 2: Logistic 映射迭代器
//
// 实现: x_{n+1} = 1 - μ · x_n²
//
// 学生需要完成:
//   1. 理解 3 步流水线 (x² → μx² → 1-μx²)
//   2. 观察不同 μ 值下的轨迹行为
//   3. 用 Python 画分岔图
// ============================================================

module logistic_iter #(
    parameter DW = 32,
    parameter FW = 28
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,    // 开始迭代
    input  wire signed [DW-1:0]    mu,       // 参数 μ (Q4.28)
    input  wire signed [DW-1:0]    x_init,   // 初始值
    input  wire [15:0]             n_steps,  // 迭代步数

    output reg  signed [DW-1:0]    x_out,    // 当前 x 值
    output reg                     valid,    // 每步输出一次
    output reg                     done      // 全部完成
);

    localparam signed [DW-1:0] ONE = (1 <<< FW);  // 1.0

    // 状态
    reg [1:0] state;
    localparam S_IDLE = 0, S_ITER = 1, S_DONE = 2;

    // 迭代变量
    reg signed [DW-1:0] x_reg;
    reg [15:0] count;

    // 乘法中间结果
    reg signed [2*DW-1:0] mult_tmp;
    reg signed [DW-1:0] x_squared;   // x²
    reg signed [DW-1:0] mu_x_sq;     // μ·x²
    reg [1:0] pipe;                   // 流水线阶段

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x_reg <= 0;
            x_out <= 0;
            valid <= 0;
            done  <= 0;
            count <= 0;
            pipe  <= 0;
        end else begin
            valid <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= x_init;
                        count <= 0;
                        pipe  <= 0;
                        state <= S_ITER;
                    end
                end

                S_ITER: begin
                    case (pipe)
                        2'd0: begin
                            // Step 1: 计算 x²
                            mult_tmp = x_reg * x_reg;
                            x_squared <= mult_tmp[DW+FW-1:FW];
                            pipe <= 2'd1;
                        end
                        2'd1: begin
                            // Step 2: 计算 μ · x²
                            mult_tmp = mu * x_squared;
                            mu_x_sq <= mult_tmp[DW+FW-1:FW];
                            pipe <= 2'd2;
                        end
                        2'd2: begin
                            // Step 3: 计算 1 - μ·x²
                            x_reg <= ONE - mu_x_sq;
                            x_out <= ONE - mu_x_sq;
                            valid <= 1;
                            count <= count + 1;
                            pipe <= 2'd0;

                            if (count >= n_steps - 1)
                                state <= S_DONE;
                        end
                    endcase
                end

                S_DONE: begin
                    done <= 1;
                    if (start) begin
                        state <= S_IDLE;
                        done  <= 0;
                    end
                end
            endcase
        end
    end

endmodule
