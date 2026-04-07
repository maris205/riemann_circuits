`timescale 1ns / 1ps
// ============================================================
// LFSR 伪随机噪声发生器
// 32-bit Galois LFSR，输出 ±noise_amp 范围的噪声
// 模拟 AD633 的 0.4% 增益误差 + 热噪声
// ============================================================

module lfsr_noise #(
    parameter DW = 32,
    parameter FW = 28
)(
    input  wire            clk,
    input  wire            rst_n,
    input  wire            enable,
    input  wire [31:0]     seed,        // 随机种子
    input  wire [DW-1:0]   noise_amp,   // 噪声幅度 (Q4.28)
    output reg signed [DW-1:0] noise_out // 噪声输出 (Q4.28)
);

    reg [31:0] lfsr;

    // Galois LFSR: x^32 + x^22 + x^2 + x + 1
    wire feedback = lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr <= seed;
            noise_out <= 0;
        end else if (enable) begin
            // LFSR shift
            lfsr <= {lfsr[30:0], feedback};

            // Convert to signed noise:
            // lfsr[15:0] → signed 16-bit → scale by noise_amp
            // noise = noise_amp * (lfsr[15:0] - 32768) / 32768
            // Simplified: use top bits for sign and magnitude
            if (lfsr[31]) begin
                // Positive noise
                noise_out <= {
                    {16{1'b0}},  // extend
                    lfsr[15:0]   // magnitude
                } >> (32 - FW + 15);  // scale down
            end else begin
                // Negative noise
                noise_out <= -{
                    {16{1'b0}},
                    lfsr[15:0]
                } >> (32 - FW + 15);
            end
        end
    end

endmodule
