`timescale 1ns / 1ps
// ============================================================
// logistic_engine.v — Logistic 混沌迭代引擎 (上板版)
//
// 目标: ALINX AX7020 (Zynq-7020) + AN108 DA
// 功能: x[n+1] = 1 - μ(n)·x[n]², 带冷却 LUT
//
// 验证结果 (Vivado 仿真):
//   Config A: 3 zeros, MAE=0.076 (bins=300, eps=0.03)
//   Config B: 8 zeros, MAE=1.38  (bins=800, eps=0.015)
// ============================================================

module logistic_engine #(
    parameter DW = 32,
    parameter FW = 28,
    parameter LUT_DEPTH = 65536,
    parameter TRAJ_DEPTH = 4096
)(
    input  wire            clk,
    input  wire            rst_n,

    input  wire            start,
    input  wire            stop,
    input  wire [31:0]     n_steps,
    input  wire [7:0]      clk_div,

    // 冷却 LUT 写接口
    input  wire [15:0]     lut_waddr,
    input  wire [DW-1:0]   lut_wdata,
    input  wire            lut_wen,

    // 轨迹读接口
    input  wire [11:0]     traj_raddr,
    output reg  [DW-1:0]   traj_rdata,

    // DAC
    output reg  [7:0]      DA_DATA,
    output wire            DA_CLK,
    output wire            DA_WRT,

    // 状态
    output wire            busy,
    output wire            done,
    output reg  [31:0]     iter_count,

    output wire            led_busy,
    output wire            led_done
);

    localparam signed [DW-1:0] ONE     = 32'sh10000000;
    localparam signed [DW-1:0] SAT_POS = 32'sh20000000;
    localparam signed [DW-1:0] SAT_NEG = 32'shE0000000;

    // ========================================
    // 时钟分频
    // ========================================
    reg [7:0] div_cnt;
    reg       iter_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt <= 0; iter_tick <= 0;
        end else begin
            if (div_cnt >= clk_div) begin
                div_cnt <= 0; iter_tick <= 1;
            end else begin
                div_cnt <= div_cnt + 1; iter_tick <= 0;
            end
        end
    end

    // ========================================
    // 冷却 LUT — 独立 BRAM 读写
    // ========================================
    (* ram_style = "block" *)
    reg [DW-1:0] mu_lut [0:LUT_DEPTH-1];
    reg [DW-1:0] mu_rd;

    always @(posedge clk) begin
        if (lut_wen)
            mu_lut[lut_waddr] <= lut_wdata;
        mu_rd <= mu_lut[iter_count[15:0]];
    end

    // ========================================
    // 轨迹 BRAM — 独立读写 (Vivado BRAM 推断友好)
    // ========================================
    (* ram_style = "block" *)
    reg [DW-1:0] traj_mem [0:TRAJ_DEPTH-1];
    reg          traj_wen;
    reg [11:0]   traj_waddr;
    reg [DW-1:0] traj_wdata;

    // 写端口
    always @(posedge clk) begin
        if (traj_wen)
            traj_mem[traj_waddr] <= traj_wdata;
    end

    // 读端口
    always @(posedge clk) begin
        traj_rdata <= traj_mem[traj_raddr];
    end

    // ========================================
    // 状态机
    // ========================================
    reg [2:0] state;
    localparam S_IDLE = 0, S_READ_LUT = 1, S_CALC_XSQ = 2,
               S_CALC_MUXSQ = 3, S_UPDATE = 4, S_DONE = 5;

    reg signed [DW-1:0] x_reg;
    reg signed [DW-1:0] mu_val;
    reg signed [DW-1:0] x_sq;
    reg signed [DW-1:0] mu_xsq;
    reg signed [DW-1:0] x_sat;       // 饱和后的值
    reg signed [63:0] mul64;

    assign busy = (state != S_IDLE) && (state != S_DONE);
    assign done = (state == S_DONE);
    assign led_busy = busy;
    assign led_done = (state == S_DONE);
    assign DA_CLK = clk;
    assign DA_WRT = clk;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            x_reg <= 32'sh08000000;
            iter_count <= 0;
            DA_DATA <= 8'd128;
            traj_wen <= 0;
        end else begin
            traj_wen <= 0;  // 默认不写

            case (state)
                S_IDLE: begin
                    if (start) begin
                        x_reg <= 32'sh08000000;
                        iter_count <= 0;
                        state <= S_READ_LUT;
                    end
                end

                // mu_rd 在独立 always 块中已经用 iter_count 读出
                S_READ_LUT: begin
                    if (iter_tick) begin
                        mu_val <= mu_rd;
                        state <= S_CALC_XSQ;
                    end
                end

                S_CALC_XSQ: begin
                    mul64 = x_reg * x_reg;
                    x_sq <= mul64[59:28];
                    state <= S_CALC_MUXSQ;
                end

                S_CALC_MUXSQ: begin
                    mul64 = mu_val * x_sq;
                    mu_xsq <= mul64[59:28];
                    state <= S_UPDATE;
                end

                S_UPDATE: begin
                    // x_new = 1 - μ·x², saturate
                    x_sat = ONE - mu_xsq;
                    if (x_sat > SAT_POS) x_sat = SAT_POS;
                    if (x_sat < SAT_NEG) x_sat = SAT_NEG;

                    x_reg <= x_sat;

                    // 写轨迹 BRAM
                    traj_wen   <= 1;
                    traj_waddr <= iter_count[11:0];
                    traj_wdata <= x_sat;

                    // DAC: [-2,+2] → [0,255]
                    DA_DATA <= (x_sat + SAT_POS) >> (FW - 6);

                    iter_count <= iter_count + 1;

                    if (iter_count >= n_steps - 1 || stop)
                        state <= S_DONE;
                    else
                        state <= S_READ_LUT;
                end

                S_DONE: begin
                    if (start) state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
