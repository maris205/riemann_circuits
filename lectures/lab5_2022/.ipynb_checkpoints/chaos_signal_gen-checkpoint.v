`timescale 1ns / 1ps
// ============================================================
// Lab 5: 2022 全国大学生电子设计竞赛 — 混沌信号发生器
//
// 题目简化版: 利用 FPGA 实现混沌信号源
// 要求: Logistic 映射产生混沌信号，DAC 输出到示波器
//
// 核心公式: x_{n+1} = 1 - μ · x_n²
//
// 学生任务:
//   1. 选择不同的 μ 参数，观察输出波形变化
//   2. 找到周期-1、周期-2、周期-4、混沌的 μ 值
//   3. 截图对比不同 μ 下的示波器波形
//   4. (加分) 找到 Feigenbaum 临界点 μ_c ≈ 1.5437
//
// μ 参数候选 (取消注释你想测试的那个):
//   μ = 0.8   → 稳定不动点 (周期-1)
//   μ = 1.1   → 周期-2 振荡
//   μ = 1.3   → 周期-4
//   μ = 1.40  → 周期-8 (窄窗口)
//   μ = 1.5437 → Feigenbaum 临界点 (混沌边缘)
//   μ = 1.7   → 完全混沌
//   μ = 1.85  → 混沌中的周期-3 窗口
//   μ = 2.0   → 强混沌
//
// 实验平台: ALINX AX7020 + AN108 DA 模块
// 也可纯 Vivado 仿真 (不需要板子)
// ============================================================

module chaos_signal_gen #(
    parameter DW = 32,
    parameter FW = 28
)(
    input  wire            clk,        // 100MHz 系统时钟
    input  wire            rst_n,      // 复位 (active low)

    // DAC 输出 (AN108, 8bit 并行)
    output reg  [7:0]      DA_DATA,
    output wire            DA_CLK,
    output wire            DA_WRT,

    // LED 状态指示
    output wire            led_running
);

    // ======================================================
    // ★★★ 学生修改区: 选择 μ 参数 ★★★
    // 取消注释你想测试的那一行，其余保持注释
    // ======================================================

    // --- 周期行为 ---
    //localparam signed [DW-1:0] MU = 32'h0CCCCCCD;  // μ = 0.80 → 不动点
    //localparam signed [DW-1:0] MU = 32'h119999A0;  // μ = 1.10 → 周期-2
    //localparam signed [DW-1:0] MU = 32'h14CCCCCD;  // μ = 1.30 → 周期-4
    //localparam signed [DW-1:0] MU = 32'h16666666;  // μ = 1.40 → 周期-8

    // --- 混沌边缘 (Feigenbaum 临界点) ---
    localparam signed [DW-1:0] MU = 32'h18B9A340;    // μ = 1.5437 → 混沌边缘 ★

    // --- 完全混沌 ---
    //localparam signed [DW-1:0] MU = 32'h1B333333;  // μ = 1.70 → 混沌
    //localparam signed [DW-1:0] MU = 32'h1D99999A;  // μ = 1.85 → 周期-3 窗口
    //localparam signed [DW-1:0] MU = 32'h20000000;  // μ = 2.00 → 强混沌

    // 初始值 x_0 = 0.5
    localparam signed [DW-1:0] X_INIT = 32'h08000000;

    // 1.0 in Q4.28
    localparam signed [DW-1:0] ONE = (1 <<< FW);

    // ======================================================
    // 时钟分频: 100MHz → 1MHz 迭代速率
    // (示波器上看到 ~500kHz 信号)
    // ======================================================
    reg [6:0] div_cnt;
    reg       iter_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 0;
            iter_tick <= 0;
        end else begin
            if (div_cnt >= 99) begin  // 100 分频
                div_cnt <= 0;
                iter_tick <= 1;
            end else begin
                div_cnt <= div_cnt + 1;
                iter_tick <= 0;
            end
        end
    end

    // ======================================================
    // Logistic 映射迭代器
    // x_{n+1} = 1 - μ · x_n²
    //
    // 流水线:
    //   Stage 0: x² = x * x
    //   Stage 1: μ·x² = μ * x²
    //   Stage 2: x_new = 1 - μ·x², 输出到 DAC
    // ======================================================
    reg signed [DW-1:0]     x_reg;        // 当前 x
    reg signed [2*DW-1:0]   mult_tmp;     // 64位乘法中间值
    reg signed [DW-1:0]     x_squared;    // x²
    reg signed [DW-1:0]     mu_x_sq;      // μ·x²
    reg [1:0]               pipe;         // 流水线阶段
    reg                     running;

    assign led_running = running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x_reg     <= X_INIT;
            pipe      <= 0;
            running   <= 0;
            DA_DATA   <= 8'd128;  // DAC 中间值
        end else if (iter_tick) begin
            running <= 1;

            case (pipe)
                2'd0: begin
                    // Stage 0: x²
                    mult_tmp <= x_reg * x_reg;
                    pipe <= 2'd1;
                end

                2'd1: begin
                    // Stage 1: μ · x²
                    x_squared <= mult_tmp[DW+FW-1:FW];
                    mult_tmp <= MU * mult_tmp[DW+FW-1:FW];
                    pipe <= 2'd2;
                end

                2'd2: begin
                    // Stage 2: x_new = 1 - μ·x²
                    mu_x_sq <= mult_tmp[DW+FW-1:FW];
                    x_reg <= ONE - mult_tmp[DW+FW-1:FW];

                    // ========================================
                    // DAC 输出映射
                    // x ∈ [-1, +1] → DAC ∈ [0, 255]
                    // dac = (x + 1) * 127.5
                    // 简化: 取 x 的高 8 位 + 128 偏置
                    // ========================================
                    DA_DATA <= (ONE - mult_tmp[DW+FW-1:FW]) >>> (FW - 7)
                               + 8'd128;

                    pipe <= 2'd0;
                end
            endcase
        end
    end

    // DAC 时钟 = 系统时钟 (AN108 要求)
    assign DA_CLK = clk;
    assign DA_WRT = clk;

endmodule

// ============================================================
// 实验步骤:
//
// 【纯仿真 (无需板子)】
//   1. Vivado → New Project → 添加 chaos_signal_gen.v + tb_chaos.v
//   2. Run Simulation
//   3. 观察 DA_DATA 波形
//   4. 修改 MU 参数，重新仿真，对比波形差异
//
// 【上板 (AX7020 + AN108)】
//   1. 综合 → 实现 → 生成 bitstream
//   2. 下载到板子
//   3. AN108 DA 输出接示波器
//   4. 观察混沌波形!
//   5. 修改 MU → 重新综合 → 观察不同状态
//
// 实验报告要求:
//   1. 截图: μ=0.8, 1.1, 1.3, 1.5437, 1.7, 2.0 六个状态的波形
//   2. 标注: 哪些是周期的？哪些是混沌的？
//   3. 思考: 为什么 μ=1.85 虽然在混沌区间却出现了周期行为？
//   4. (加分) 画出你自己实验的分岔图
// ============================================================
