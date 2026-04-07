`timescale 1ns / 1ps
// ============================================================
// Lab 4: Testbench — 黎曼零点提取
//
// 1. 预计算冷却 LUT (Python 生成, $readmemh 加载)
// 2. 运行 50000 步非自治 Hénon
// 3. 导出轨迹到文件
// 4. 用 Python 做 Markov/DMD 分析提取零点
// ============================================================

module tb_riemann;
    parameter DW = 32, FW = 28;

    reg clk, rst_n, start;
    reg [1:0] map_sel;
    reg signed [DW-1:0] b_param, x_init, y_init;
    reg [31:0] n_steps;
    reg [15:0] lut_waddr;
    reg [DW-1:0] lut_wdata;
    reg lut_wen;
    wire signed [DW-1:0] x_out, y_out;
    wire valid, done;

    chaos_with_cooling #(.DW(DW),.FW(FW)) uut (
        .clk(clk),.rst_n(rst_n),.start(start),.map_sel(map_sel),
        .b_param(b_param),.x_init(x_init),.y_init(y_init),.n_steps(n_steps),
        .lut_waddr(lut_waddr),.lut_wdata(lut_wdata),.lut_wen(lut_wen),
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

    integer fd, cnt, i;

    // 冷却参数 (对应论文最优配置)
    real a_c, delta_a, c_offset;
    real t_start_r, t_end_r, k_opt, a_dyna;
    real t_n, a_n;
    integer total_steps;

    initial begin
        $display("============================================");
        $display("Lab 4: Riemann Zero Extraction from FPGA");
        $display("============================================");

        rst_n = 0; start = 0; lut_wen = 0;
        map_sel = 1;  // Henon
        b_param = to_q428(0.3);
        x_init  = to_q428(0.1);
        y_init  = to_q428(0.1);
        total_steps = 50000;
        n_steps = total_steps;

        // 冷却参数
        a_c = 1.02;
        delta_a = 0.015;
        c_offset = 10.0;

        #20 rst_n = 1;

        // ==============================
        // Step 1: 填写冷却 LUT
        // ==============================
        $display("Step 1: Computing cooling LUT...");
        t_start_r = 1.0 / ($ln(1.0 + c_offset) * $ln(1.0 + c_offset));
        t_end_r = 1.0 / ($ln(total_steps + c_offset) * $ln(total_steps + c_offset));
        k_opt = delta_a / (t_start_r - t_end_r);
        a_dyna = a_c - k_opt * t_end_r;

        $display("  k_opt = %f, a_dyna = %f", k_opt, a_dyna);
        $display("  a(1) = %f (target %f)", a_dyna + k_opt * t_start_r, a_c + delta_a);

        for (i = 0; i < total_steps && i < 65536; i = i + 1) begin
            t_n = 1.0 / ($ln(i + 1.0 + c_offset) * $ln(i + 1.0 + c_offset));
            a_n = a_dyna + k_opt * t_n;
            lut_waddr = i;
            lut_wdata = to_q428(a_n);
            lut_wen = 1;
            @(posedge clk);
        end
        lut_wen = 0;
        $display("  LUT loaded: %0d entries", i);

        // ==============================
        // Step 2: 运行迭代
        // ==============================
        $display("Step 2: Running %0d iterations...", total_steps);
        fd = $fopen("riemann_trajectory.txt", "w");

        #10 start = 1;
        #10 start = 0;

        cnt = 0;
        while (!done) begin
            @(posedge clk);
            if (valid) begin
                cnt = cnt + 1;
                $fwrite(fd, "%f\n", from_q428(x_out));
                if (cnt % 10000 == 0)
                    $display("  %0d / %0d iterations", cnt, total_steps);
            end
        end
        $fclose(fd);

        $display("Step 3: Trajectory saved (%0d points)", cnt);
        $display("Step 4: Run 'python analyze_zeros.py' to extract Riemann zeros!");
        $display("============================================");
        $finish;
    end
endmodule
