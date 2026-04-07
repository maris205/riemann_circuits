`timescale 1ns / 1ps
// ============================================================
// Lab 1: Testbench — 验证定点乘法器
//
// 测试用例:
//   1.5 × 1.5 = 2.25
//   -1.0 × 2.0 = -2.0
//   0.5 × 0.5 = 0.25
//   1.5437 × 1.5437 ≈ 2.3830 (Logistic 临界点的平方)
//
// 使用方法:
//   1. Vivado → Create Project → Add Sources
//   2. 添加 fixed_mult.v 和 tb_fixed_mult.v
//   3. Run Simulation → 查看波形
//   4. 对照 $display 输出验证结果
// ============================================================

module tb_fixed_mult;

    parameter DW = 32;
    parameter FW = 28;

    reg                    clk;
    reg                    rst_n;
    reg  signed [DW-1:0]   a, b;
    reg                    valid_in;
    wire signed [DW-1:0]   result;
    wire                   valid_out;

    // 被测模块
    fixed_mult #(.DW(DW), .FW(FW)) uut (
        .clk(clk), .rst_n(rst_n),
        .a(a), .b(b),
        .valid_in(valid_in),
        .result(result),
        .valid_out(valid_out)
    );

    // 时钟: 100MHz
    initial clk = 0;
    always #5 clk = ~clk;

    // ==============================
    // 辅助函数: 浮点 → Q4.28
    // ==============================
    function signed [DW-1:0] float_to_q428;
        input real val;
        begin
            float_to_q428 = $rtoi(val * (2.0**FW));
        end
    endfunction

    // ==============================
    // 辅助函数: Q4.28 → 浮点 (用于显示)
    // ==============================
    function real q428_to_float;
        input signed [DW-1:0] val;
        begin
            q428_to_float = $itor(val) / (2.0**FW);
        end
    endfunction

    // ==============================
    // 测试序列
    // ==============================
    initial begin
        $display("============================================");
        $display("Lab 1: Fixed-Point Multiplier Testbench");
        $display("Format: Q4.28 (4 int + 28 frac bits)");
        $display("============================================");

        rst_n = 0; valid_in = 0; a = 0; b = 0;
        #20 rst_n = 1;

        // Test 1: 1.5 × 1.5 = 2.25
        #10;
        a = float_to_q428(1.5);
        b = float_to_q428(1.5);
        valid_in = 1;
        #10 valid_in = 0;
        #10;
        $display("Test 1: 1.5 * 1.5 = %f (expected 2.25)",
                 q428_to_float(result));

        // Test 2: -1.0 × 2.0 = -2.0
        #10;
        a = float_to_q428(-1.0);
        b = float_to_q428(2.0);
        valid_in = 1;
        #10 valid_in = 0;
        #10;
        $display("Test 2: -1.0 * 2.0 = %f (expected -2.0)",
                 q428_to_float(result));

        // Test 3: 0.5 × 0.5 = 0.25
        #10;
        a = float_to_q428(0.5);
        b = float_to_q428(0.5);
        valid_in = 1;
        #10 valid_in = 0;
        #10;
        $display("Test 3: 0.5 * 0.5 = %f (expected 0.25)",
                 q428_to_float(result));

        // Test 4: 1.5437 × 1.5437 ≈ 2.3830
        #10;
        a = float_to_q428(1.5437);
        b = float_to_q428(1.5437);
        valid_in = 1;
        #10 valid_in = 0;
        #10;
        $display("Test 4: 1.5437 * 1.5437 = %f (expected ~2.383)",
                 q428_to_float(result));

        #20;
        $display("============================================");
        $display("All tests complete!");
        $display("============================================");
        $finish;
    end

    // 波形输出
    initial begin
        $dumpfile("tb_fixed_mult.vcd");
        $dumpvars(0, tb_fixed_mult);
    end

endmodule
