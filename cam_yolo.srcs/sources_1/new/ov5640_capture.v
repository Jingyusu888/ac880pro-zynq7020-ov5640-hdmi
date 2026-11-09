`timescale 1ns / 1ps

module ov5640_capture #(
    // VSYNC 有效电平：
    // 1：高有效，在下降沿后开始接收新帧
    // 0：低有效，在上升沿后开始接收新帧
    parameter VSYNC_ACTIVE_HIGH = 1'b1,

    // RGB565 字节顺序：
    // 1：先收到高字节，再收到低字节
    // 0：先收到低字节，再收到高字节
    parameter FIRST_BYTE_IS_HIGH = 1'b1
)(
    // 摄像头输入时钟域
    input  wire        camera_pclk,
    input  wire        capture_reset,

    // 摄像头 DVP 输入
    input  wire        camera_vsync,
    input  wire        camera_href,
    input  wire [7:0]  camera_data,

    // 采集结果，均属于 camera_pclk 时钟域
    output wire        frame_start,
    output reg         pixel_valid,
    output reg  [15:0] pixel_data
);

    // ============================================================
    // 1. 复位同步
    //
    // capture_reset：高有效
    // 异步进入复位，在 camera_pclk 域同步退出
    // ============================================================

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] reset_sync;

    wire pclk_reset;

    always @(posedge camera_pclk or posedge capture_reset) begin
        if (capture_reset)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end

    assign pclk_reset = reset_sync[1];


    // ============================================================
    // 2. 帧同步检测
    //
    // 将 VSYNC 转换成统一含义：
    // vsync_active = 1，表示处于帧同步有效期间
    //
    // 检测有效期间结束，生成新帧脉冲。
    // 复位后必须先观察到有效 VSYNC，才接受帧边界。
    // ============================================================

    wire vsync_active;

    reg  vsync_active_d;
    reg  vsync_seen;
    reg  frame_start_reg;

    wire frame_boundary;

    assign vsync_active =
        VSYNC_ACTIVE_HIGH ? camera_vsync : ~camera_vsync;

    assign frame_boundary =
        vsync_seen &&
        vsync_active_d &&
        !vsync_active;

    assign frame_start = frame_start_reg;

    always @(posedge camera_pclk or posedge pclk_reset) begin
        if (pclk_reset) begin
            vsync_active_d <= 1'b0;
            vsync_seen     <= 1'b0;
            frame_start_reg <= 1'b0;
        end
        else begin
            vsync_active_d <= vsync_active;

            if (vsync_active)
                vsync_seen <= 1'b1;

            frame_start_reg <= frame_boundary;
        end
    end


    // ============================================================
    // 3. RGB565 字节拼接
    //
    // capture_enabled：
    //   复位后为 0，等待第一个完整帧边界后变为 1。
    //
    // byte_pending：
    //   0：等待一个像素的第一个字节。
    //   1：已保存第一个字节，等待第二个字节。
    //
    // pixel_valid：
    //   每拼好一个像素，拉高一个 camera_pclk 周期。
    // ============================================================

    reg       capture_enabled;
    reg       byte_pending;
    reg [7:0] first_byte;

    always @(posedge camera_pclk or posedge pclk_reset) begin
        if (pclk_reset) begin
            capture_enabled <= 1'b0;
            byte_pending    <= 1'b0;
            first_byte      <= 8'h00;

            pixel_valid     <= 1'b0;
            pixel_data      <= 16'h0000;
        end
        else begin
            // 默认本拍不输出新像素
            pixel_valid <= 1'b0;

            if (vsync_active) begin
                // 帧同步期间不接收数据
                // 清除未完成的半个像素
                byte_pending <= 1'b0;
            end
            else if (frame_boundary) begin
                // 帧同步结束，允许接收新帧
                capture_enabled <= 1'b1;

                // 通常此时 HREF 为低。
                // 若第一字节恰好与帧边界同拍，也保存它。
                if (camera_href) begin
                    first_byte   <= camera_data;
                    byte_pending <= 1'b1;
                end
                else begin
                    byte_pending <= 1'b0;
                end
            end
            else if (!capture_enabled) begin
                // 尚未观察到新帧，忽略输入
                byte_pending <= 1'b0;
            end
            else if (!camera_href) begin
                // 行间隔期间清除字节配对状态
                // 不允许把两行的数据拼成一个像素
                byte_pending <= 1'b0;
            end
            else if (!byte_pending) begin
                // 收到第一个字节：先保存
                first_byte   <= camera_data;
                byte_pending <= 1'b1;
            end
            else begin
                // 收到第二个字节：组成一个完整像素
                if (FIRST_BYTE_IS_HIGH)
                    pixel_data <= {first_byte, camera_data};
                else
                    pixel_data <= {camera_data, first_byte};

                pixel_valid  <= 1'b1;
                byte_pending <= 1'b0;
            end
        end
    end

endmodule