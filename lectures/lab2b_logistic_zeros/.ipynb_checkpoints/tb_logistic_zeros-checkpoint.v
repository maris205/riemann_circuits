`timescale 1ns / 1ps
// ============================================================
// Lab 2b v2: Testbench — with noise control
//
// 两种模式:
//   noise_en = 0: 纯净模式 → 3 个零点, MAE ≈ 0.23
//   noise_en = 1: AD633 噪声 → 6+ 个零点, MAE ≈ 0.9
//
// 学生实验: 对比两种模式的结果差异
// ============================================================

module tb_logistic_zeros;

    parameter DW = 32;
    parameter FW = 28;

    reg            clk, rst_n, start;
    reg  [31:0]    n_steps;
    reg  [31:0]    lfsr_seed;
    reg            noise_en;
    reg  [15:0]    lut_waddr;
    reg  [DW-1:0]  lut_wdata;
    reg            lut_wen;
    wire signed [DW-1:0] x_out;
    wire           valid, done;

    logistic_zeros #(.DW(DW), .FW(FW)) uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .n_steps(n_steps),
        .lfsr_seed(lfsr_seed), .noise_en(noise_en),
        .lut_waddr(lut_waddr), .lut_wdata(lut_wdata), .lut_wen(lut_wen),
        .x_out(x_out), .valid(valid), .done(done)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // 冷却参数
    real mu_c, delta_mu, c_offset;
    real t_start_r, t_end_r, k_opt, mu_dyna;
    real t_n, mu_n;
    integer total_steps;
    integer fd, cnt, i;
    reg signed [DW-1:0] mu_q428;

    initial begin
        $display("============================================");
        $display("Lab 2b v2: Logistic + AD633 Noise Model");
        $display("============================================");

        rst_n = 0; start = 0; lut_wen = 0;
        lut_waddr = 0; lut_wdata = 0;
        // ★★★ 参数控制 ★★★
        // 步数: 50000 → 3 个零点, 200000 → 更多零点
        total_steps = 200000;
        n_steps = total_steps;

        // 噪声: 模拟 AD633 增益误差
        //   noise_en = 0 → 纯净
        //   noise_en = 1 → 加噪声
        noise_en = 1;
        lfsr_seed = 32'hCAFEBABE;

        // 冷却参数 (论文最优)
        mu_c = 1.5437;
        delta_mu = 0.012;
        c_offset = 10.0;

        // 复位
        #100;
        rst_n = 1;
        #20;

        // ==============================
        // Step 1: 计算冷却参数
        // ==============================
        t_start_r = 1.0 / ($ln(1.0 + c_offset) * $ln(1.0 + c_offset));
        t_end_r = 1.0 / ($ln(total_steps + c_offset) * $ln(total_steps + c_offset));
        k_opt = delta_mu / (t_start_r - t_end_r);
        mu_dyna = mu_c - k_opt * t_end_r;

        $display("Cooling: k_opt=%f, mu_dyna=%f", k_opt, mu_dyna);
        $display("  mu(1)=%f, mu(N)=%f", mu_dyna + k_opt * t_start_r, mu_dyna + k_opt * t_end_r);

        if (noise_en)
            $display("Mode: AD633 noise ENABLED (expect 6+ zeros)");
        else
            $display("Mode: Pure (no noise, expect 3 zeros)");

        // ==============================
        // Step 2: 填写冷却 LUT
        // ==============================
        $display("Writing LUT...");
        for (i = 0; i < total_steps && i < 65536; i = i + 1) begin
            t_n = 1.0 / ($ln(i + 1.0 + c_offset) * $ln(i + 1.0 + c_offset));
            mu_n = mu_dyna + k_opt * t_n;
            mu_q428 = $rtoi(mu_n * 268435456.0);

            @(posedge clk);
            lut_waddr <= i[15:0];
            lut_wdata <= mu_q428;
            lut_wen <= 1;
            @(posedge clk);
            lut_wen <= 0;
        end
        $display("  LUT loaded: %0d entries", i);

        repeat(10) @(posedge clk);

        // ==============================
        // Step 3: 运行迭代
        // ==============================
        $display("Running %0d iterations...", total_steps);
        fd = $fopen("logistic_trajectory.txt", "w");

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        cnt = 0;
        while (!done) begin
            @(posedge clk);
            if (valid) begin
                cnt = cnt + 1;
                $fwrite(fd, "%f\n", $itor(x_out) / 268435456.0);
                if (cnt % 10000 == 0)
                    $display("  %0d / %0d (x=%f)", cnt, total_steps,
                             $itor(x_out) / 268435456.0);
            end
        end
        $fclose(fd);

        $display("");
        $display("============================================");
        $display("DONE! %0d points saved", cnt);
        $display("Noise: %s", noise_en ? "ON (AD633 model)" : "OFF (pure)");
        $display("Next: python analyze_logistic_zeros.py");
        $display("============================================");
        $finish;
    end

endmodule
