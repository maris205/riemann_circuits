`timescale 1ns / 1ps
// ============================================================
// Lab 4: 带冷却的 Hénon 引擎 + 轨迹导出
//
// 完整实现非自治冷却: a(n) 从查找表读取
// PS 端 (或 Python 脚本) 预计算 LUT 内容
// 长轨迹输出到文件，供 Markov/DMD 分析
//
// 这是最终实验: 从 FPGA 混沌输出中提取黎曼零点！
// ============================================================

module chaos_with_cooling #(
    parameter DW = 32,
    parameter FW = 28,
    parameter LUT_DEPTH = 65536
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire [1:0]              map_sel,    // 0=Logistic, 1=Henon
    input  wire signed [DW-1:0]    b_param,
    input  wire signed [DW-1:0]    x_init,
    input  wire signed [DW-1:0]    y_init,
    input  wire [31:0]             n_steps,

    // 冷却 LUT 写接口 (仿真中通过 testbench 填写)
    input  wire [15:0]             lut_waddr,
    input  wire [DW-1:0]           lut_wdata,
    input  wire                    lut_wen,

    output reg  signed [DW-1:0]    x_out,
    output reg  signed [DW-1:0]    y_out,
    output reg                     valid,
    output reg                     done
);

    localparam signed [DW-1:0] ONE = (1 <<< FW);

    // 冷却 LUT
    (* ram_style = "block" *)
    reg [DW-1:0] cooling_lut [0:LUT_DEPTH-1];
    reg [DW-1:0] a_current;

    // LUT 写入
    always @(posedge clk) begin
        if (lut_wen)
            cooling_lut[lut_waddr] <= lut_wdata;
    end

    // 状态机
    reg [1:0] state;
    localparam S_IDLE=0, S_RUN=1, S_DONE=2;
    reg signed [DW-1:0] x_reg, y_reg;
    reg [31:0] count;
    reg signed [2*DW-1:0] mult_tmp;
    reg signed [DW-1:0] x_sq, a_xsq, b_x;
    reg [2:0] pipe;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=S_IDLE; valid<=0; done<=0; count<=0; pipe<=0;
        end else begin
            valid <= 0;
            case (state)
                S_IDLE: begin
                    done <= 0;
                    if (start) begin
                        x_reg<=x_init; y_reg<=y_init;
                        count<=0; pipe<=0; state<=S_RUN;
                    end
                end
                S_RUN: begin
                    case (pipe)
                        3'd0: begin
                            // 读 LUT 获取 a(n)
                            a_current <= cooling_lut[count[15:0]];
                            mult_tmp = x_reg * x_reg;
                            x_sq <= mult_tmp[DW+FW-1:FW];
                            pipe <= 3'd1;
                        end
                        3'd1: begin
                            mult_tmp = a_current * x_sq;
                            a_xsq <= mult_tmp[DW+FW-1:FW];
                            mult_tmp = b_param * x_reg;
                            b_x <= mult_tmp[DW+FW-1:FW];
                            pipe <= 3'd2;
                        end
                        3'd2: begin
                            if (map_sel == 0) begin
                                // Logistic
                                x_reg <= ONE - a_xsq;
                                x_out <= ONE - a_xsq;
                                y_out <= 0;
                            end else begin
                                // Henon
                                x_reg <= ONE - a_xsq + y_reg;
                                y_reg <= b_x;
                                x_out <= ONE - a_xsq + y_reg;
                                y_out <= b_x;
                            end
                            valid <= 1;
                            count <= count + 1;
                            pipe <= 3'd0;
                            if (count >= n_steps - 1) state <= S_DONE;
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
