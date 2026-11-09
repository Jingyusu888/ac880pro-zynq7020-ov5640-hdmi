`timescale 1ns / 1ps

module serializer_10to1 (
    input  wire       pixel_clk,
    input  wire       serial_clk_5x,
    input  wire       pixel_reset,

    input  wire [9:0] data_in,

    output wire       serial_out
);

    // 从单元到主单元的专用级联连接。
    wire shift1;
    wire shift2;

    // 主单元：接收低 8 位，输出串行数据。
    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("MASTER"),

        .INIT_OQ        (1'b0),
        .SRVAL_OQ       (1'b0),
        .INIT_TQ        (1'b0),
        .SRVAL_TQ       (1'b0),

        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .TRISTATE_WIDTH (1)
    ) u_oserdes_master (
        .OQ        (serial_out),
        .OFB       (),
        .TQ        (),
        .TFB       (),
        .TBYTEOUT  (),
        .SHIFTOUT1 (),
        .SHIFTOUT2 (),

        .CLK       (serial_clk_5x),
        .CLKDIV    (pixel_clk),
        .OCE       (1'b1),
        .RST       (pixel_reset),

        .D1        (data_in[0]),
        .D2        (data_in[1]),
        .D3        (data_in[2]),
        .D4        (data_in[3]),
        .D5        (data_in[4]),
        .D6        (data_in[5]),
        .D7        (data_in[6]),
        .D8        (data_in[7]),

        .SHIFTIN1  (shift1),
        .SHIFTIN2  (shift2),

        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TCE       (1'b0),
        .TBYTEIN   (1'b0)
    );

    // 从单元：通过 D3、D4 接收高 2 位。
    OSERDESE2 #(
        .DATA_RATE_OQ   ("DDR"),
        .DATA_RATE_TQ   ("SDR"),
        .DATA_WIDTH     (10),
        .SERDES_MODE    ("SLAVE"),

        .INIT_OQ        (1'b0),
        .SRVAL_OQ       (1'b0),
        .INIT_TQ        (1'b0),
        .SRVAL_TQ       (1'b0),

        .TBYTE_CTL      ("FALSE"),
        .TBYTE_SRC      ("FALSE"),
        .TRISTATE_WIDTH (1)
    ) u_oserdes_slave (
        .OQ        (),
        .OFB       (),
        .TQ        (),
        .TFB       (),
        .TBYTEOUT  (),
        .SHIFTOUT1 (shift1),
        .SHIFTOUT2 (shift2),

        .CLK       (serial_clk_5x),
        .CLKDIV    (pixel_clk),
        .OCE       (1'b1),
        .RST       (pixel_reset),

        .D1        (1'b0),
        .D2        (1'b0),
        .D3        (data_in[8]),
        .D4        (data_in[9]),
        .D5        (1'b0),
        .D6        (1'b0),
        .D7        (1'b0),
        .D8        (1'b0),

        .SHIFTIN1  (1'b0),
        .SHIFTIN2  (1'b0),

        .T1        (1'b0),
        .T2        (1'b0),
        .T3        (1'b0),
        .T4        (1'b0),
        .TCE       (1'b0),
        .TBYTEIN   (1'b0)
    );

endmodule