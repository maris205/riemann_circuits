`timescale 1ns / 1ps
// ============================================================
// logistic_top.v — 极简上板版，永不停止
// 上电即跑，固定 μ=1.5437，DAC 持续输出混沌波形
// ============================================================

module logistic_top (
    input  wire        sys_clk,

    output reg  [7:0]  DA_DATA,
    output wire        DA_CLK,
    output wire        DA_WRT
);

    localparam signed [31:0] ONE     = 32'sh10000000;  // 1.0
    localparam signed [31:0] MU      = 32'sh18B9A340;  // 1.5437
    localparam signed [31:0] SAT_POS = 32'sh20000000;  // +2.0
    localparam signed [31:0] SAT_NEG = 32'shE0000000;  // -2.0

    assign DA_CLK = sys_clk;
    assign DA_WRT = sys_clk;

    // 上电复位
    reg [15:0] rst_cnt = 0;
    wire rst_done = (rst_cnt == 16'hFFFF);
    always @(posedge sys_clk)
        if (!rst_done) rst_cnt <= rst_cnt + 1;

    // ========================================
    // 分频: 50MHz / 3 ≈ 16.7MHz 迭代率
    // 3 拍完成一次迭代 (每拍一个阶段)
    // 示波器 25MHz 采样 50000 点 = 2ms
    // → 2ms × 16.7MHz = ~33000 个迭代点
    // ========================================
    reg [1:0] div_cnt = 0;

    always @(posedge sys_clk) begin
        if (!rst_done)
            div_cnt <= 0;
        else if (div_cnt >= 2)
            div_cnt <= 0;
        else
            div_cnt <= div_cnt + 1;
    end

    // ========================================
    // Logistic 迭代: x[n+1] = 1 - μ·x[n]²
    // 每 3 个时钟一次迭代
    // div_cnt=0: x²
    // div_cnt=1: μ·x²
    // div_cnt=2: 更新 + DAC
    // ========================================
    reg signed [31:0] x_reg;
    reg signed [31:0] x_sq;
    reg signed [31:0] mu_xsq;
    reg signed [31:0] x_sat;
    reg signed [63:0] mul64;

    always @(posedge sys_clk) begin
        if (!rst_done) begin
            x_reg <= 32'sh08000000;  // 0.5
            DA_DATA <= 8'd128;
        end else begin
            case (div_cnt)
                2'd0: begin
                    // Stage 0: x²
                    mul64 = x_reg * x_reg;
                    x_sq <= mul64[59:28];
                end

                2'd1: begin
                    // Stage 1: μ·x²
                    mul64 = MU * x_sq;
                    mu_xsq <= mul64[59:28];
                end

                2'd2: begin
                    // Stage 2: 1 - μ·x², 饱和, 更新, DAC 输出
                    x_sat = ONE - mu_xsq;
                    if (x_sat > SAT_POS) x_sat = SAT_POS;
                    if (x_sat < SAT_NEG) x_sat = SAT_NEG;
                    x_reg <= x_sat;

                    // DAC: [-2,+2] → [0,255]
                    DA_DATA <= (x_sat + SAT_POS) >> 22;
                end
            endcase
        end
    end

endmodule
