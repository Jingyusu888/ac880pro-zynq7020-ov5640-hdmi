`timescale 1ns / 1ps

module tmds_encode_rgb (
    input  wire       pixel_clk,
    input  wire       pixel_reset,

    input  wire [7:0] red,
    input  wire [7:0] green,
    input  wire [7:0] blue,

    input  wire       hsync,
    input  wire       vsync,
    input  wire       de,

    output wire [9:0] red_code,
    output wire [9:0] green_code,
    output wire [9:0] blue_code
);

    // 红色通道。
    tmds_encoder u_encoder_red (
        .pixel_clk   (pixel_clk),
        .pixel_reset (pixel_reset),
        .data_in     (red),
        .de          (de),
        .c0          (1'b0),
        .c1          (1'b0),
        .tmds_out    (red_code)
    );

    // 绿色通道。
    tmds_encoder u_encoder_green (
        .pixel_clk   (pixel_clk),
        .pixel_reset (pixel_reset),
        .data_in     (green),
        .de          (de),
        .c0          (1'b0),
        .c1          (1'b0),
        .tmds_out    (green_code)
    );

    // 蓝色通道：消隐期间承载行、场同步信息。
    tmds_encoder u_encoder_blue (
        .pixel_clk   (pixel_clk),
        .pixel_reset (pixel_reset),
        .data_in     (blue),
        .de          (de),
        .c0          (hsync),
        .c1          (vsync),
        .tmds_out    (blue_code)
    );

endmodule