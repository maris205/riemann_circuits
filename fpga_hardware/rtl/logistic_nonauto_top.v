`timescale 1ns / 1ps
// ============================================================
// logistic_nonauto_top.v — 非自治版 v2
//
// 修复:
//   1. phase 只在一个 always 块里驱动
//   2. 先用固定 μ 验证迭代工作，再切 LUT
//   3. 迭代率 ~83kHz 适配 250KSa/s 示波器
//
// 切换模式: 改 USE_LUT 参数
//   0 = 固定 μ=1.5437 (调试用)
//   1 = LUT 冷却 (正式用)
// ============================================================

module logistic_nonauto_top (
    input  wire        sys_clk,
    output reg  [7:0]  DA_DATA,
    output wire        DA_CLK,
    output wire        DA_WRT
);

    // ★ 改这里切换模式 ★
    localparam USE_LUT = 1;  // 0=固定mu调试, 1=LUT冷却

    localparam signed [31:0] ONE     = 32'sh10000000;  // 1.0
    localparam signed [31:0] MU_FIX  = 32'sh18B9A340;  // 1.5437 (固定模式用)
    localparam signed [31:0] SAT_POS = 32'sh20000000;  // +2.0
    localparam signed [31:0] SAT_NEG = 32'shE0000000;  // -2.0
    localparam [31:0] N_STEPS = 32'd50000;

    assign DA_CLK = sys_clk;
    assign DA_WRT = sys_clk;

    // 上电复位
    reg [15:0] rst_cnt = 0;
    wire rst_done = (rst_cnt == 16'hFFFF);
    always @(posedge sys_clk)
        if (!rst_done) rst_cnt <= rst_cnt + 1;

    // 冷却 LUT (仅 USE_LUT=1 时使用)
    (* ram_style = "block" *)
    reg [31:0] mu_lut [0:65535];
    initial $readmemh("cooling_lut.hex", mu_lut);

    // ========================================
    // 单一状态机: 分频 + 流水线
    // 每 200 个时钟推进一步
    // phase 0→1→2→0, 3 步 = 1 次迭代
    // 迭代率 = 50MHz / (200×3) = 83kHz
    // ========================================
    reg [10:0] sub_cnt = 0;    // 11 bit, 数到 1999
    reg [1:0]  phase = 0;
    reg signed [31:0] x_reg = 32'sh08000000;  // 0.5
    reg signed [31:0] mu_val;
    reg signed [31:0] x_sq;
    reg signed [31:0] mu_xsq;
    reg signed [31:0] x_sat;
    reg signed [63:0] mul64;
    reg [31:0] iter_count = 0;

    always @(posedge sys_clk) begin
        if (!rst_done) begin
            sub_cnt <= 0;
            phase <= 0;
            x_reg <= 32'sh08000000;
            iter_count <= 0;
            DA_DATA <= 8'd128;
        end else begin
            if (sub_cnt < 1999) begin
                sub_cnt <= sub_cnt + 1;
            end else begin
                // 每 200 个时钟执行一步
                sub_cnt <= 0;

                case (phase)
                    2'd0: begin
                        // Stage 0: 读 μ + 算 x²
                        if (USE_LUT)
                            mu_val <= mu_lut[iter_count[15:0]];
                        else
                            mu_val <= MU_FIX;

                        mul64 = x_reg * x_reg;
                        x_sq <= mul64[59:28];
                        phase <= 2'd1;
                    end

                    2'd1: begin
                        // Stage 1: μ · x²
                        mul64 = mu_val * x_sq;
                        mu_xsq <= mul64[59:28];
                        phase <= 2'd2;
                    end

                    2'd2: begin
                        // Stage 2: 1 - μ·x², 饱和, DAC, 计数
                        x_sat = ONE - mu_xsq;
                        if (x_sat > SAT_POS) x_sat = SAT_POS;
                        if (x_sat < SAT_NEG) x_sat = SAT_NEG;

                        x_reg <= x_sat;
                        DA_DATA <= (x_sat + SAT_POS) >> 22;

                        // 自动重启
                        if (iter_count >= N_STEPS - 1) begin
                            iter_count <= 0;
                            x_reg <= 32'sh08000000;
                        end else begin
                            iter_count <= iter_count + 1;
                        end

                        phase <= 2'd0;
                    end

                    default: phase <= 2'd0;
                endcase
            end
        end
    end

endmodule
