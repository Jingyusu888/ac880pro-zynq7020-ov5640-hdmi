`timescale 1ns / 1ps

module tb_tmds_encode_rgb;

    reg pixel_clk;
    reg pixel_reset;

    reg [7:0] red;
    reg [7:0] green;
    reg [7:0] blue;

    reg hsync;
    reg vsync;
    reg de;

    wire [9:0] red_code;
    wire [9:0] green_code;
    wire [9:0] blue_code;

    integer check_count;

    tmds_encode_rgb dut (
        .pixel_clk   (pixel_clk),
        .pixel_reset (pixel_reset),

        .red         (red),
        .green       (green),
        .blue        (blue),

        .hsync       (hsync),
        .vsync       (vsync),
        .de          (de),

        .red_code    (red_code),
        .green_code  (green_code),
        .blue_code   (blue_code)
    );

    initial pixel_clk = 1'b0;
    always #6.737 pixel_clk = ~pixel_clk;

    // 提供一组输入，检查三个通道输出。
    task check_rgb;
        input        test_de;
        input        test_hsync;
        input        test_vsync;
        input [23:0] test_rgb;

        input [9:0] expected_red;
        input [9:0] expected_green;
        input [9:0] expected_blue;

        begin
            @(negedge pixel_clk);

            de = test_de;
            hsync = test_hsync;
            vsync = test_vsync;
            {red, green, blue} = test_rgb;

            @(posedge pixel_clk);
            #1;

            if ((red_code   !== expected_red) ||
                (green_code !== expected_green) ||
                (blue_code  !== expected_blue))
                $fatal(1,
                    "FAIL: RGB=%h DE=%b HS=%b VS=%b R=%b G=%b B=%b",
                    test_rgb, test_de, test_hsync, test_vsync,
                    red_code, green_code, blue_code);

            check_count = check_count + 1;
            $display("Check %0d OK", check_count);
        end
    endtask

    initial begin
        pixel_reset = 1'b1;
        red = 8'h00;
        green = 8'h00;
        blue = 8'h00;
        hsync = 1'b0;
        vsync = 1'b0;
        de = 1'b0;
        check_count = 0;

        repeat (5) @(negedge pixel_clk);
        #1;
        pixel_reset = 1'b0;

        // 检查消隐期间的四种 HS、VS 组合。
        // 红、绿控制位始终为 00。
        check_rgb(
            1'b0, 1'b0, 1'b0, 24'h000000,
            10'b1101010100,
            10'b1101010100,
            10'b1101010100
        );

        check_rgb(
            1'b0, 1'b1, 1'b0, 24'h000000,
            10'b1101010100,
            10'b1101010100,
            10'b0010101011
        );

        check_rgb(
            1'b0, 1'b0, 1'b1, 24'h000000,
            10'b1101010100,
            10'b1101010100,
            10'b0101010100
        );

        check_rgb(
            1'b0, 1'b1, 1'b1, 24'h000000,
            10'b1101010100,
            10'b1101010100,
            10'b1010101011
        );

        // 从累计值为零开始，发送纯红色 FF0000。
        check_rgb(
            1'b1, 1'b0, 1'b0, 24'hFF0000,
            10'b1000000000,
            10'b0100000000,
            10'b0100000000
        );

        // 插入消隐，清零三个编码器的累计状态。
        check_rgb(
            1'b0, 1'b0, 1'b0, 24'hFFFFFF,
            10'b1101010100,
            10'b1101010100,
            10'b1101010100
        );

        // 发送纯绿色 00FF00。
        check_rgb(
            1'b1, 1'b0, 1'b0, 24'h00FF00,
            10'b0100000000,
            10'b1000000000,
            10'b0100000000
        );

        check_rgb(
            1'b0, 1'b0, 1'b0, 24'hFFFFFF,
            10'b1101010100,
            10'b1101010100,
            10'b1101010100
        );

        // 发送纯蓝色 0000FF。
        check_rgb(
            1'b1, 1'b0, 1'b0, 24'h0000FF,
            10'b0100000000,
            10'b0100000000,
            10'b1000000000
        );

        $display("PASS: All %0d RGB checks passed.", check_count);
        $finish;
    end

    initial begin
        #10000;
        $fatal(1, "FAIL: Simulation timeout.");
    end

endmodule