`timescale 1ns / 1ps
// ============================================================
// Lab 3b: Testbench — Hénon Riemann Zero Extraction
//
// a_c = 1.02, delta_a = 0.015, b = 0.3
// 200k steps for better spectral resolution
// Outputs x trajectory to henon_trajectory.txt
// ============================================================

module tb_henon_zeros;

    parameter DW = 32;
    parameter FW = 28;

    reg            clk, rst_n, start;
    reg  [31:0]    n_steps;
    reg  signed [DW-1:0] b_param;
    reg  [15:0]    lut_waddr;
    reg  [DW-1:0]  lut_wdata;
    reg            lut_wen;
    wire signed [DW-1:0] x_out, y_out;
    wire           valid, done;

    henon_zeros #(.DW(DW), .FW(FW)) uut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .n_steps(n_steps), .b_param(b_param),
        .lut_waddr(lut_waddr), .lut_wdata(lut_wdata), .lut_wen(lut_wen),
        .x_out(x_out), .y_out(y_out), .valid(valid), .done(done)
    );

    // 100MHz clock
    initial clk = 0;
    always #5 clk = ~clk;

    // Cooling parameters
    real a_c, delta_a, c_offset, b_val;
    real t_start_r, t_end_r, k_opt, a_dyna;
    real t_n, a_n;
    integer total_steps;
    integer fd_x, fd_xy, cnt, i;
    reg signed [DW-1:0] a_q428;

    initial begin
        $display("============================================");
        $display("Lab 3b: Henon Riemann Zero Extraction");
        $display("============================================");

        rst_n = 0; start = 0; lut_wen = 0;
        lut_waddr = 0; lut_wdata = 0;

        // Parameters
        total_steps = 200000;
        n_steps = total_steps;
        b_val = 0.3;
        b_param = $rtoi(b_val * 268435456.0);  // 0.3 in Q4.28

        // Cooling
        a_c = 1.02;
        delta_a = 0.015;
        c_offset = 10.0;

        // Reset
        #100;
        rst_n = 1;
        #20;

        // ==============================
        // Step 1: Compute cooling params
        // ==============================
        t_start_r = 1.0 / ($ln(1.0 + c_offset) * $ln(1.0 + c_offset));
        t_end_r = 1.0 / ($ln(total_steps + c_offset) * $ln(total_steps + c_offset));
        k_opt = delta_a / (t_start_r - t_end_r);
        a_dyna = a_c - k_opt * t_end_r;

        $display("Henon cooling parameters:");
        $display("  a_c = %f, delta_a = %f, b = %f", a_c, delta_a, b_val);
        $display("  k_opt = %f, a_dyna = %f", k_opt, a_dyna);
        $display("  a(1) = %f (target %f)", a_dyna + k_opt * t_start_r, a_c + delta_a);
        $display("  a(N) = %f (target %f)", a_dyna + k_opt * t_end_r, a_c);

        // ==============================
        // Step 2: Fill cooling LUT
        // ==============================
        $display("Writing LUT (%0d entries)...", total_steps);
        for (i = 0; i < total_steps && i < 65536; i = i + 1) begin
            t_n = 1.0 / ($ln(i + 1.0 + c_offset) * $ln(i + 1.0 + c_offset));
            a_n = a_dyna + k_opt * t_n;
            a_q428 = $rtoi(a_n * 268435456.0);

            @(posedge clk);
            lut_waddr <= i[15:0];
            lut_wdata <= a_q428;
            lut_wen <= 1;
            @(posedge clk);
            lut_wen <= 0;
        end
        $display("  LUT loaded.");

        repeat(10) @(posedge clk);

        // ==============================
        // Step 3: Run iteration
        // ==============================
        $display("Running %0d iterations...", total_steps);
        fd_x = $fopen("henon_trajectory.txt", "w");
        fd_xy = $fopen("henon_attractor.txt", "w");

        @(posedge clk);
        start <= 1;
        @(posedge clk);
        start <= 0;

        cnt = 0;
        while (!done) begin
            @(posedge clk);
            if (valid) begin
                cnt = cnt + 1;
                // x trajectory for zero extraction
                $fwrite(fd_x, "%f\n", $itor(x_out) / 268435456.0);
                // x,y for attractor plot
                $fwrite(fd_xy, "%f %f\n",
                        $itor(x_out) / 268435456.0,
                        $itor(y_out) / 268435456.0);
                if (cnt % 50000 == 0)
                    $display("  %0d / %0d (x=%f, y=%f)", cnt, total_steps,
                             $itor(x_out) / 268435456.0,
                             $itor(y_out) / 268435456.0);
            end
        end
        $fclose(fd_x);
        $fclose(fd_xy);

        $display("");
        $display("============================================");
        $display("DONE! %0d points saved", cnt);
        $display("Files:");
        $display("  henon_trajectory.txt  (x only, for zero extraction)");
        $display("  henon_attractor.txt   (x,y for attractor plot)");
        $display("Next: python analyze_henon_zeros.py");
        $display("============================================");
        $finish;
    end

endmodule
