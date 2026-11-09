`timescale 1ns / 1ps

module dvi_tx (
    input  wire       pixel_clk,
    input  wire       serial_clk_5x,
    input  wire       pixel_reset,

    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,

    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,

    output wire [2:0] tmds_data_p,
    output wire [2:0] tmds_data_n,
    output wire       tmds_clk_p,
    output wire       tmds_clk_n
);

    wire [9:0] red_code;
    wire [9:0] green_code;
    wire [9:0] blue_code;

    wire red_serial;
    wire green_serial;
    wire blue_serial;
    wire clock_serial;

    // ------------------------------------------------------------
    // 1. RGB 三通道 TMDS 编码。
    // ------------------------------------------------------------
    tmds_encode_rgb u_tmds_encode_rgb (
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

    // ------------------------------------------------------------
    // 2. 三个数据通道并行转串行。
    // ------------------------------------------------------------
    serializer_10to1 u_serializer_red (
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset),
        .data_in       (red_code),
        .serial_out    (red_serial)
    );

    serializer_10to1 u_serializer_green (
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset),
        .data_in       (green_code),
        .serial_out    (green_serial)
    );

    serializer_10to1 u_serializer_blue (
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset),
        .data_in       (blue_code),
        .serial_out    (blue_serial)
    );

    // ------------------------------------------------------------
    // 3. 时钟通道：固定码字产生像素频率方波。
    // ------------------------------------------------------------
    serializer_10to1 u_serializer_clock (
        .pixel_clk     (pixel_clk),
        .serial_clk_5x (serial_clk_5x),
        .pixel_reset   (pixel_reset),
        .data_in       (10'b1111100000),
        .serial_out    (clock_serial)
    );

    // ------------------------------------------------------------
    // 4. 将串行信号转换为差分输出。
    // 通道 0：蓝色；通道 1：绿色；通道 2：红色。
    // 电压标准及引脚将在核对板卡后通过约束确定。
    // ------------------------------------------------------------
    OBUFDS u_obuf_blue (
        .I  (blue_serial),
        .O  (tmds_data_p[0]),
        .OB (tmds_data_n[0])
    );

    OBUFDS u_obuf_green (
        .I  (green_serial),
        .O  (tmds_data_p[1]),
        .OB (tmds_data_n[1])
    );

    OBUFDS u_obuf_red (
        .I  (red_serial),
        .O  (tmds_data_p[2]),
        .OB (tmds_data_n[2])
    );

    OBUFDS u_obuf_clock (
        .I  (clock_serial),
        .O  (tmds_clk_p),
        .OB (tmds_clk_n)
    );

endmodule