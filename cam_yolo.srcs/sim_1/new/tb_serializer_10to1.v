`timescale 1ns / 1ps

module tb_serializer_10to1;

    reg pixel_clk;
    reg serial_clk_5x;
    reg pixel_reset;

    reg [9:0] data_in;

    wire serial_out;

    serializer_10to1 dut (
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset),
        .data_in       (data_in),
        .serial_out    (serial_out)
    );

    // 两路测试时钟保持严格的 1:5 关系。
    initial begin
        pixel_clk = 1'b0;
        serial_clk_5x = 1'b0;
    end

    // 高速时钟周期：2.694 ns。
    always #1.347 serial_clk_5x = ~serial_clk_5x;

    // 像素时钟周期：13.470 ns。
    always #6.735 pixel_clk = ~pixel_clk;

    initial begin
        pixel_reset = 1'b1;
        data_in = 10'b0000000000;

        // 留出原语仿真模型的全局启动时间。
        #200;

        // 在像素时钟下降沿之后解除复位。
        @(negedge pixel_clk);
        #0.001;
        pixel_reset = 1'b0;

        // 先让原语运行几个周期。
        repeat (8) @(negedge pixel_clk);

        // 第一组：只有最低位为 1。
        #0.001;
        data_in = 10'b0000000001;

        repeat (8) @(negedge pixel_clk);

        // 第二组：只有最高位为 1。
        #0.001;
        data_in = 10'b1000000000;

        repeat (8) @(negedge pixel_clk);

        // 第三组：检查主单元和从单元的数据连接。
        #0.001;
        data_in = 10'b1101000101;

        repeat (8) @(negedge pixel_clk);

        $display("Serializer stimulus completed. Inspect waveform.");
        $finish;
    end

    initial begin
        #2000;
        $fatal(1, "FAIL: Simulation timeout.");
    end

endmodule