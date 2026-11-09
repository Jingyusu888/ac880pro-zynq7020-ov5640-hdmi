`timescale 1ns / 1ps

module video_clock_reset (
    input  wire sys_clk,          // 输入参考时钟：IP 按 50 MHz 配置
    input  wire sys_reset,        // 外部复位请求，高电平有效

    output wire pixel_clk,        // 像素时钟，约 74.21875 MHz
    output wire serial_clk_5x,    // 5 倍像素时钟，约 371.09375 MHz
    output wire pixel_reset       // 像素时钟域复位，高电平有效
);

    wire clk_locked;
    wire reset_request;

    // 标记为同步寄存器链，供 Vivado 综合和布局使用。
    (* ASYNC_REG = "TRUE" *)
    reg [1:0] pixel_reset_sync;

    // 例化已经创建的 Clocking Wizard IP。
    video_clk u_video_clk (
        .clk_in1  (sys_clk),
        .reset    (sys_reset),
        .clk_out1 (pixel_clk),
        .clk_out2 (serial_clk_5x),
        .locked   (clk_locked)
    );

    // 外部要求复位，或者 MMCM 未锁定时，请求复位。
    assign reset_request = sys_reset | ~clk_locked;

    // 异步置位复位，同步释放复位。
    always @(posedge pixel_clk or posedge reset_request) begin
        if (reset_request)
            pixel_reset_sync <= 2'b11;
        else
            pixel_reset_sync <= {pixel_reset_sync[0], 1'b0};
    end

    assign pixel_reset = pixel_reset_sync[1];

endmodule