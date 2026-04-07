`timescale 1ns / 1ps
// ============================================================
// Lab 2b v2: Non-Autonomous Logistic with AD633 Noise Model
//
// 改进: 加入 LFSR 伪随机噪声模拟 AD633 的物理效应
//   1. 增益误差: x² → x² * (1 + 0.004 * noise)  (0.4%)
//   2. 偏移误差: x² → x² + offset               (5mV → ~0.005)
//
// 这让 FPGA 结果从 3 个零点提升到 6+ 个
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
    input  wire [31:0]     lfsr_seed,   // 噪声种子 (非零)
    input  wire            noise_en,    // 噪声使能

    input  wire [15:0]     lut_waddr,
    input  wire [DW-1:0]   lut_wdata,
    input  wire            lut_wen,

    output reg signed [DW-1:0] x_out,
    output reg             valid,
    output reg             done
);

    // Q4.28 常量
    localparam signed [DW-1:0] ONE       = 32'sh10000000;  // 1.0
    localparam signed [DW-1:0] SAT_POS   = 32'sh20000000;  // +2.0
    localparam signed [DW-1:0] SAT_NEG   = 32'shE0000000;  // -2.0
    // AD633 偏移: 0.05 in Q4.28 (对应 SPICE 的 1.004*x²+0.05)
    localparam signed [DW-1:0] AD633_OFF = 32'sh00CCCCCD;  // 0.05

    // ========================================
    // 冷却 LUT
    // ========================================
    reg [DW-1:0] mu_lut [0:LUT_DEPTH-1];

    always @(posedge clk) begin
        if (lut_wen)
            mu_lut[lut_waddr] <= lut_wdata;
    end

    // ========================================
    // LFSR 噪声发生器 (32-bit Galois)
    // ========================================
    reg [31:0] lfsr;
    wire lfsr_fb = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    // ========================================
    // 状态机
    // ========================================
    reg [2:0] state;
    localparam S_IDLE = 0, S_READ_LUT = 1, S_CALC_XSQ = 2,
               S_ADD_NOISE = 3, S_CALC_MUXSQ = 4, S_UPDATE = 5, S_DONE = 6;

    reg signed [DW-1:0] x_reg;
    reg signed [DW-1:0] mu_val;
    reg signed [DW-1:0] x_sq;
    reg signed [DW-1:0] x_sq_noisy;   // x² + 噪声
    reg signed [DW-1:0] mu_xsq;
    reg [31:0] count;
    reg signed [63:0] mul64;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x_reg <= 0;
            x_out <= 0;
            valid <= 0;
            done  <= 0;
            count <= 0;
            lfsr  <= 32'hDEADBEEF;  // 默认种子
        end else begin
            valid <= 0;

            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg <= 32'sh08000000;  // 0.5
                        count <= 0;
                        lfsr  <= (lfsr_seed != 0) ? lfsr_seed : 32'hDEADBEEF;
                        state <= S_READ_LUT;
                    end
                end

                // Stage 1: 读 μ(n)
                S_READ_LUT: begin
                    mu_val <= mu_lut[count[15:0]];
                    state <= S_CALC_XSQ;
                end

                // Stage 2: 计算 x²
                S_CALC_XSQ: begin
                    mul64 = x_reg * x_reg;
                    x_sq <= mul64[59:28];
                    state <= S_ADD_NOISE;
                end

                // Stage 3: 加 AD633 噪声 (模拟真实电路)
                // SPICE 模型: 1.004 * x² + 0.05
                // 这里: x² * (1 ± 1/256) + 0.05
                S_ADD_NOISE: begin
                    // LFSR 步进
                    lfsr <= {lfsr[30:0], lfsr_fb};

                    if (noise_en) begin
                        // 增益抖动 ±0.4%: 每步随机加或减 x²/256
                        // 加固定偏移 0.05 (对应 AD633 offset)
                        if (lfsr[15])
                            x_sq_noisy <= x_sq + (x_sq >>> 8) + AD633_OFF;
                        else
                            x_sq_noisy <= x_sq - (x_sq >>> 8) + AD633_OFF;
                    end else begin
                        x_sq_noisy <= x_sq;
                    end
                    state <= S_CALC_MUXSQ;
                end

                // Stage 4: μ · x²_noisy
                S_CALC_MUXSQ: begin
                    mul64 = mu_val * x_sq_noisy;
                    mu_xsq <= mul64[59:28];
                    state <= S_UPDATE;
                end

                // Stage 5: x_new = 1 - μ·x², 饱和, 输出
                S_UPDATE: begin
                    x_reg <= (ONE - mu_xsq > SAT_POS) ? SAT_POS :
                             (ONE - mu_xsq < SAT_NEG) ? SAT_NEG :
                             ONE - mu_xsq;
                    x_out <= (ONE - mu_xsq > SAT_POS) ? SAT_POS :
                             (ONE - mu_xsq < SAT_NEG) ? SAT_NEG :
                             ONE - mu_xsq;
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
