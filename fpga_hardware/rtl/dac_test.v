`timescale 1ns / 1ps
// ============================================================
// dac_test.v — DAC 测试，超慢方波
// 0.5 秒高 + 0.5 秒低 = 1Hz 方波
// 示波器设置: 时基 500ms/div, 幅度 1V/div, DC 耦合
// ============================================================

module dac_test (
    input  wire        sys_clk,      // 50MHz

    output reg  [7:0]  DA_DATA,
    output wire        DA_CLK,
    output wire        DA_WRT
);

    assign DA_CLK = sys_clk;
    assign DA_WRT = sys_clk;

    // 50MHz / 50000000 = 1Hz
    reg [25:0] cnt = 0;

    always @(posedge sys_clk) begin
        if (cnt >= 26'd49_999_999)
            cnt <= 0;
        else
            cnt <= cnt + 1;

        if (cnt < 26'd25_000_000)
            DA_DATA <= 8'd255;    // 高电平 0.5 秒
        else
            DA_DATA <= 8'd0;      // 低电平 0.5 秒
    end

endmodule
