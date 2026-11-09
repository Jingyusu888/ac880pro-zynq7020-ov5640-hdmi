`timescale 1ns / 1ps

module camera_clock_reset (
    input  wire sys_clk,
    input  wire sys_reset,

    output wire camera_xclk,
    output wire camera_clk_ready
);

    wire camera_clk_locked;
    wire ready_reset;

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] ready_sync;

    // 产生摄像头工作时钟
    camera_clk u_camera_clk (
        .clk_in1  (sys_clk),
        .reset    (sys_reset),

        .clk_out1 (camera_xclk),
        .locked   (camera_clk_locked)
    );

    // 系统复位或者时钟未锁定时，撤销就绪状态
    assign ready_reset = sys_reset | ~camera_clk_locked;

    // 就绪状态：异步撤销，同步建立
    always @(posedge sys_clk or posedge ready_reset) begin
        if (ready_reset)
            ready_sync <= 2'b00;
        else
            ready_sync <= {ready_sync[0], 1'b1};
    end

    assign camera_clk_ready = ready_sync[1];

endmodule