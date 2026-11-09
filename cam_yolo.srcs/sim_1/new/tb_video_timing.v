`timescale 1ns / 1ps

module tb_video_timing;

    reg pixel_clk;
    reg pixel_reset;

    wire hsync;
    wire vsync;
    wire de;
    wire [10:0] pixel_x;
    wire [9:0]  pixel_y;

    // 测试期望值，独立定义在 TB 中。
    localparam H_ACTIVE = 1280;
    localparam H_FRONT  = 110;
    localparam H_SYNC   = 40;
    localparam H_BACK   = 220;
    localparam H_TOTAL = H_ACTIVE + H_FRONT + H_SYNC + H_BACK;

    localparam V_ACTIVE = 720;
    localparam V_FRONT  = 5;
    localparam V_SYNC   = 5;
    localparam V_BACK   = 20;
    localparam V_TOTAL = V_ACTIVE + V_FRONT + V_SYNC + V_BACK;

    integer expected_h;
    integer expected_v;
    integer active_pixel_count;
    integer frame_count;

    reg expected_hsync;
    reg expected_vsync;
    reg expected_de;

    video_timing dut (
        .pixel_clk   (pixel_clk),
        .pixel_reset (pixel_reset),
        .hsync       (hsync),
        .vsync       (vsync),
        .de          (de),
        .pixel_x     (pixel_x),
        .pixel_y     (pixel_y)
    );

    // 近似模拟 74.21875 MHz 像素时钟。
    initial begin
        pixel_clk = 1'b0;
    end

    always #6.737 pixel_clk = ~pixel_clk;

    // 产生复位，运行完整一帧，再多观察两行。
    initial begin
        pixel_reset = 1'b1;

        repeat (5) @(negedge pixel_clk);

        // 与下降沿上的检查过程错开，避免竞争。
        #0.001;
        pixel_reset = 1'b0;

        repeat (H_TOTAL * (V_TOTAL + 2))
            @(negedge pixel_clk);

        // 等本次下降沿上的检查执行完毕。
        #0.001;

        if (frame_count < 1)
            $fatal(1, "FAIL: No complete frame was checked.");

        $display("PASS: Video timing checks completed.");
        $display("Complete frames checked: %0d", frame_count);
        $finish;
    end

    initial begin
        expected_h = 0;
        expected_v = 0;
        active_pixel_count = 0;
        frame_count = 0;
        expected_hsync = 1'b0;
        expected_vsync = 1'b0;
        expected_de = 1'b0;
    end

    // 在下降沿检查：DUT 已在前一个上升沿完成更新，
    // 组合输出也已稳定。
    always @(negedge pixel_clk) begin
        if (pixel_reset) begin
            expected_h = 0;
            expected_v = 0;
            active_pixel_count = 0;
            frame_count = 0;

            // Allow asynchronous reset NBA updates at time zero.
            #0.001;
            if ((dut.h_count !== 11'd0) ||
                (dut.v_count !== 10'd0))
                $fatal(1, "FAIL: Counters not zero during reset.");

            if (de !== 1'b0)
                $fatal(1, "FAIL: DE must be zero during reset.");
        end
        else begin
            // 参考模型：每拍横向加一，每行结束纵向加一。
            if (expected_h == H_TOTAL - 1) begin
                expected_h = 0;

                if (expected_v == V_TOTAL - 1)
                    expected_v = 0;
                else
                    expected_v = expected_v + 1;
            end
            else begin
                expected_h = expected_h + 1;
            end

            // 检查实际计数器。
            if ((dut.h_count !== expected_h[10:0]) ||
                (dut.v_count !== expected_v[9:0]))
                $fatal(1,
                    "FAIL: Counter mismatch. Expected (%0d,%0d), got (%0d,%0d)",
                    expected_h, expected_v,
                    dut.h_count, dut.v_count);

            // 正极性同步，计数从有效区开始。
            expected_hsync =
                (expected_h >= H_ACTIVE + H_FRONT) &&
                (expected_h < H_ACTIVE + H_FRONT + H_SYNC);

            expected_vsync =
                (expected_v >= V_ACTIVE + V_FRONT) &&
                (expected_v < V_ACTIVE + V_FRONT + V_SYNC);

            expected_de =
                (expected_h < H_ACTIVE) &&
                (expected_v < V_ACTIVE);

            if (hsync !== expected_hsync)
                $fatal(1,
                    "FAIL: HSYNC mismatch at (%0d,%0d)",
                    expected_h, expected_v);

            if (vsync !== expected_vsync)
                $fatal(1,
                    "FAIL: VSYNC mismatch at (%0d,%0d)",
                    expected_h, expected_v);

            if (de !== expected_de)
                $fatal(1,
                    "FAIL: DE mismatch at (%0d,%0d)",
                    expected_h, expected_v);

            // 检查有效区坐标，消隐区坐标应为零。
            if (expected_de) begin
                if ((pixel_x !== expected_h[10:0]) ||
                    (pixel_y !== expected_v[9:0]))
                    $fatal(1,
                        "FAIL: Pixel coordinate mismatch at (%0d,%0d)",
                        expected_h, expected_v);
            end
            else begin
                if ((pixel_x !== 11'd0) ||
                    (pixel_y !== 10'd0))
                    $fatal(1,
                        "FAIL: Coordinates must be zero outside active video.");
            end
        end
    end

    // 在上升沿统计当前像素周期。
    // 此时读取的是 DUT 本次非阻塞赋值更新前的状态。
    always @(posedge pixel_clk) begin
        if (pixel_reset) begin
            active_pixel_count = 0;
            frame_count = 0;
        end
        else begin
            if (de)
                active_pixel_count = active_pixel_count + 1;

            if ((dut.h_count == H_TOTAL - 1) &&
                (dut.v_count == V_TOTAL - 1)) begin

                if (active_pixel_count != H_ACTIVE * V_ACTIVE)
                    $fatal(1,
                        "FAIL: Wrong active pixel count: %0d",
                        active_pixel_count);

                frame_count = frame_count + 1;

                $display(
                    "Frame %0d: active pixel count correct (%0d)",
                    frame_count, active_pixel_count);

                active_pixel_count = 0;
            end
        end
    end

    // 超时保护：正常测试约 16.72 ms，保护上限为 20 ms。
    initial begin
        #20000000;
        $fatal(1, "FAIL: Simulation timeout.");
    end

endmodule