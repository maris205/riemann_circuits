`timescale 1ns / 1ps
// ============================================================
// Lab 1: 定点数乘法器 (Q4.28 格式)
//
// Q4.28: 4 位整数 + 28 位小数
//   范围: -8.0 ~ +7.9999999963
//   精度: 2^-28 ≈ 3.7 × 10^-9
//
// 示例: 1.5 × 1.5 = 2.25
//   1.5 in Q4.28 = 32'h18000000
//   2.25 in Q4.28 = 32'h24000000
//
// 学生任务:
//   1. 理解 Q4.28 表示法
//   2. 实现带符号定点乘法
//   3. 处理结果截位 (64位→32位)
//   4. 用 testbench 验证
// ============================================================

module fixed_mult #(
    parameter DW = 32,     // 数据宽度
    parameter FW = 28      // 小数位数
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [DW-1:0]    a,       // 被乘数 (Q4.28)
    input  wire signed [DW-1:0]    b,       // 乘数 (Q4.28)
    input  wire                    valid_in,// 输入有效
    output reg  signed [DW-1:0]    result,  // 乘积 (Q4.28)
    output reg                     valid_out// 输出有效
);

    // ==============================
    // 核心: 带符号定点乘法
    //
    // a × b 的完整结果是 64 位 (Q8.56)
    // 我们需要截取中间 32 位得到 Q4.28
    //
    // 具体: result = (a * b) >>> FW
    //   即右移 28 位 (丢弃低 28 位小数)
    // ==============================

    reg signed [2*DW-1:0] mult_full;  // 64 位完整乘积

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 0;
            valid_out <= 0;
        end else begin
            valid_out <= valid_in;
            if (valid_in) begin
                // Step 1: 完整 64 位乘法
                mult_full = a * b;    // Q4.28 × Q4.28 = Q8.56

                // Step 2: 算术右移 FW 位，截取 Q4.28
                result <= mult_full[DW+FW-1:FW];  // 取 [59:28]
            end
        end
    end

endmodule

// ============================================================
// 思考题:
//   1. 为什么用算术右移 (>>>) 而不是逻辑右移 (>>)?
//   2. 如果两个接近 8.0 的数相乘，会发生什么？如何检测溢出？
//   3. Q4.28 的精度 3.7×10^-9 和 AD633 的 0.4% 误差相比如何？
// ============================================================
