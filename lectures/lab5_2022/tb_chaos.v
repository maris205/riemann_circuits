`timescale 1ns / 1ps
// ============================================================
// Lab 5: Testbench — 混沌信号发生器
// 仿真 2000 个迭代周期，导出 DAC 输出到文件
// ============================================================

module tb_chaos;

    parameter DW = 32, FW = 28;

    reg         clk, rst_n;
    wire [7:0]  DA_DATA;
    wire        DA_CLK, DA_WRT;
    wire        led_running;

    chaos_signal_gen #(.DW(DW), .FW(FW)) uut (
        .clk(clk), .rst_n(rst_n),
        .DA_DATA(DA_DATA), .DA_CLK(DA_CLK), .DA_WRT(DA_WRT),
        .led_running(led_running)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz

    integer fd, cnt;

    initial begin
        fd = $fopen("chaos_waveform.txt", "w");
        $display("===========================================");
        $display("Lab 5: Chaos Signal Generator (2022 Contest)");
        $display("===========================================");

        rst_n = 0;
        #50 rst_n = 1;

        cnt = 0;

        // 等待 2000 个迭代周期 (每周期 100 个时钟)
        repeat (200000) begin
            @(posedge clk);
            // 每 100 个时钟 (= 1 个迭代) 记录一次 DAC 值
            if (cnt % 100 == 50) begin  // 取中间时刻
                $fwrite(fd, "%d\n", DA_DATA);
            end
            cnt = cnt + 1;
        end

        $fclose(fd);
        $display("Done! 2000 samples saved to chaos_waveform.txt");
        $display("Run: python plot_chaos.py");
        $finish;
    end

    // VCD 波形
    initial begin
        $dumpfile("tb_chaos.vcd");
        $dumpvars(0, tb_chaos);
    end

endmodule
