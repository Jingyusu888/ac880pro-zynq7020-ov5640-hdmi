`timescale 1ns / 1ps

module tb_video_clock_reset;

    // 测试模块产生的输入。
    reg sys_clk;
    reg sys_reset;

    // 接收被测试模块的输出。
    wire pixel_clk;
    wire serial_clk_5x;
    wire pixel_reset;

    // 被测试模块。
    video_clock_reset dut (
        .sys_clk       (sys_clk),
        .sys_reset     (sys_reset),
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset)
    );

    // 产生 50 MHz 参考时钟：周期 20 ns。
    initial begin
        sys_clk = 1'b0;
    end

    always #10 sys_clk = ~sys_clk;

    // 测试上电复位，以及运行期间再次复位。
    initial begin
        sys_reset = 1'b1;

        // 保持复位 100 ns。
        #100;
        sys_reset = 1'b0;

        // 等待时钟锁定后，像素复位完成释放。
        wait (pixel_reset === 1'b0);

        // 正常运行 200 个像素时钟周期。
        repeat (200) @(posedge pixel_clk);

        // 选在参考时钟下降沿重新请求复位。
        @(negedge sys_clk);
        sys_reset = 1'b1;

        #100;
        sys_reset = 1'b0;

        // 等待第二次启动完成。
        wait (pixel_reset === 1'b0);

        repeat (200) @(posedge pixel_clk);

        $display("Test stimulus completed at %0t", $time);
        $finish;
    end

    // 超时保护：避免异常时一直卡在 wait。
    initial begin
        #100000;
        $fatal(1, "Timeout: clock/reset startup did not complete.");
    end

endmodule