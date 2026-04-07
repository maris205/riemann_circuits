`timescale 1ns / 1ps
// ============================================================
// Lab 3: Testbench — Hénon 吸引子
// 输出 x, y 到文件，用 Python 画相图
// ============================================================

module tb_henon;
    parameter DW = 32, FW = 28;

    reg clk, rst_n, start;
    reg signed [DW-1:0] a_param, b_param, x_init, y_init;
    reg [15:0] n_steps;
    wire signed [DW-1:0] x_out, y_out;
    wire valid, done;

    henon_iter #(.DW(DW),.FW(FW)) uut (
        .clk(clk),.rst_n(rst_n),.start(start),
        .a_param(a_param),.b_param(b_param),
        .x_init(x_init),.y_init(y_init),.n_steps(n_steps),
        .x_out(x_out),.y_out(y_out),.valid(valid),.done(done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    function signed [DW-1:0] to_q428;
        input real val;
        to_q428 = $rtoi(val * (2.0**FW));
    endfunction

    function real from_q428;
        input signed [DW-1:0] val;
        from_q428 = $itor(val) / (2.0**FW);
    endfunction

    integer fd, cnt;

    initial begin
        fd = $fopen("henon_attractor.txt", "w");
        $display("Henon attractor simulation...");

        rst_n = 0; start = 0;
        a_param = to_q428(1.4);   // 经典 Henon 参数
        b_param = to_q428(0.3);
        x_init  = to_q428(0.1);
        y_init  = to_q428(0.1);
        n_steps = 5000;

        #20 rst_n = 1;
        #10 start = 1;
        #10 start = 0;

        cnt = 0;
        while (!done) begin
            @(posedge clk);
            if (valid) begin
                cnt = cnt + 1;
                if (cnt > 100) // 跳过瞬态
                    $fwrite(fd, "%f %f\n", from_q428(x_out), from_q428(y_out));
            end
        end

        $fclose(fd);
        $display("Done! %0d points", cnt);
        $display("Run: python plot_attractor.py");
        $finish;
    end
endmodule
