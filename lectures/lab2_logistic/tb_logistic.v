`timescale 1ns / 1ps
// ============================================================
// Lab 2: Testbench — Logistic 映射分岔图
//
// 扫描 μ 从 0.5 到 2.0，每个 μ 迭代 500 步，
// 输出最后 100 步的 x 值到文件，用 Python 画分岔图。
//
// Vivado 仿真时间较长 (约 5-10 分钟)，请耐心等待。
// ============================================================

module tb_logistic;

    parameter DW = 32;
    parameter FW = 28;

    reg                    clk;
    reg                    rst_n;
    reg                    start;
    reg  signed [DW-1:0]   mu;
    reg  signed [DW-1:0]   x_init;
    reg  [15:0]            n_steps;
    wire signed [DW-1:0]   x_out;
    wire                   valid;
    wire                   done;

    logistic_iter #(.DW(DW), .FW(FW)) uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .mu(mu), .x_init(x_init), .n_steps(n_steps),
        .x_out(x_out), .valid(valid), .done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;  // 100MHz

    // Q4.28 转换
    function signed [DW-1:0] to_q428;
        input real val;
        to_q428 = $rtoi(val * (2.0**FW));
    endfunction

    function real from_q428;
        input signed [DW-1:0] val;
        from_q428 = $itor(val) / (2.0**FW);
    endfunction

    // 输出文件
    integer fd;
    integer step_count;
    real mu_real;

    initial begin
        fd = $fopen("bifurcation_data.txt", "w");
        $display("Starting bifurcation sweep...");

        rst_n = 0; start = 0;
        x_init = to_q428(0.5);
        n_steps = 500;
        #20 rst_n = 1;

        // 扫描 μ: 50 个值 (仿真中用少一些，实际可增加)
        for (mu_real = 0.5; mu_real <= 2.0; mu_real = mu_real + 0.03) begin
            mu = to_q428(mu_real);
            step_count = 0;

            // 启动迭代
            #10 start = 1;
            #10 start = 0;

            // 等待完成，记录后 100 步
            while (!done) begin
                @(posedge clk);
                if (valid) begin
                    step_count = step_count + 1;
                    if (step_count > 400) begin
                        // 记录最后 100 步 (吸引子)
                        $fwrite(fd, "%f %f\n", mu_real, from_q428(x_out));
                    end
                end
            end

            if (mu_real > 0.5 && $rtoi((mu_real-0.5)/0.3) * 3 == $rtoi(mu_real*10-5))
                $display("  mu = %f done", mu_real);
        end

        $fclose(fd);
        $display("Bifurcation sweep complete!");
        $display("Run: python plot_bifurcation.py");
        $finish;
    end

endmodule
