`timescale 1ns / 1ps

module rgb565_packer #(
    parameter IMAGE_WIDTH  = 640,
    parameter IMAGE_HEIGHT = 480
)(
    input  wire         clk,
    input  wire         reset,

    // 输入：来自摄像头异步FIFO的读取侧
    // in_valid && in_ready：接收一个像素
    input  wire [15:0]  in_pixel,
    input  wire         in_frame_start,
    input  wire         in_valid,
    output wire         in_ready,

    // 输出：交给后续DDR写入模块
    // out_valid && out_ready：交接一份打包数据
    output reg  [127:0] out_data,
    output reg  [15:0]  out_strb,
    output reg          out_frame_start,
    output reg          out_frame_last,
    output reg          out_valid,
    input  wire         out_ready,

    // 提前遇到下一帧时，输出一拍错误通知
    // 属于clk时钟域
    output reg          frame_error
);

    // ============================================================
    // 1. 常量和内部状态
    //
    // IMAGE_WIDTH、IMAGE_HEIGHT必须为正整数，
    // 且必须与实际输入图像一致。
    // ============================================================

    localparam FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;

    localparam PIXEL_COUNT_WIDTH =
        (FRAME_PIXELS <= 1) ? 1 : $clog2(FRAME_PIXELS);

    // 是否正在接收一帧
    reg frame_active;

    // 当前输入像素在本帧中的序号
    reg [PIXEL_COUNT_WIDTH-1:0] pixel_count;

    // 下一个像素放到128位数据中的哪个16位位置
    reg [2:0] lane_count;

    // 尚未凑满8个像素的暂存数据
    reg [127:0] pack_data;
    reg [15:0]  pack_strb;

    // 当前暂存块是否包含本帧第一个像素
    reg pack_frame_start;

    wire input_transfer;

    // 本次接收像素后，形成的数据
    reg [127:0] merged_data;
    reg [15:0]  merged_strb;
    reg         merged_frame_start;
    reg         current_frame_last;


    // ============================================================
    // 2. 输入背压
    //
    // 输出没有待发送数据，或者旧输出本拍可以被取走，
    // 才允许接收输入。
    //
    // 输出阻塞时暂停输入，保证out_*保持稳定。
    // ============================================================

    assign in_ready =
        !reset &&
        (!out_valid || out_ready);

    assign input_transfer =
        in_valid && in_ready;


    // ============================================================
    // 3. 拼接本次输入像素
    //
    // 第一个像素放在最低16位：
    // pixel0 -> [15:0]
    // pixel1 -> [31:16]
    // ...
    // pixel7 -> [127:112]
    //
    // 每个像素占两个字节，对应两个WSTRB位。
    // ============================================================

    always @(*) begin
        merged_data        = pack_data;
        merged_strb        = pack_strb;
        merged_frame_start = pack_frame_start;
        current_frame_last = 1'b0;

        if (in_frame_start) begin
            // 新帧必须从一个新的128位块开始
            merged_data        = 128'd0;
            merged_strb        = 16'd0;
            merged_frame_start = 1'b1;

            merged_data[15:0] = in_pixel;
            merged_strb[1:0] = 2'b11;

            current_frame_last = (FRAME_PIXELS == 1);
        end
        else begin
            merged_data[lane_count * 16 +: 16] = in_pixel;
            merged_strb[lane_count * 2 +: 2]   = 2'b11;

            current_frame_last =
                (pixel_count == FRAME_PIXELS - 1);
        end
    end


    // ============================================================
    // 4. 像素计数、打包与输出
    // ============================================================

    always @(posedge clk) begin
        if (reset) begin
            frame_active     <= 1'b0;
            pixel_count      <= 0;
            lane_count       <= 3'd0;

            pack_data        <= 128'd0;
            pack_strb        <= 16'd0;
            pack_frame_start <= 1'b0;

            out_data         <= 128'd0;
            out_strb         <= 16'd0;
            out_frame_start  <= 1'b0;
            out_frame_last   <= 1'b0;
            out_valid        <= 1'b0;

            frame_error      <= 1'b0;
        end
        else begin
            // 错误通知默认只保持一拍
            frame_error <= 1'b0;

            // 旧输出被下游接收
            if (out_valid && out_ready)
                out_valid <= 1'b0;

            if (input_transfer) begin

                if (in_frame_start || frame_active) begin

                    // 尚未收满一帧，却遇到下一帧
                    if (in_frame_start && frame_active)
                        frame_error <= 1'b1;

                    // 更新帧内像素序号
                    if (current_frame_last) begin
                        frame_active <= 1'b0;
                        pixel_count  <= 0;
                    end
                    else begin
                        frame_active <= 1'b1;

                        if (in_frame_start)
                            pixel_count <= 1;
                        else
                            pixel_count <= pixel_count + 1'b1;
                    end

                    // 满8个像素，或者已经到达本帧最后像素
                    if ((!in_frame_start &&
                         lane_count == 3'd7) ||
                        current_frame_last) begin

                        out_data        <= merged_data;
                        out_strb        <= merged_strb;
                        out_frame_start <= merged_frame_start;
                        out_frame_last  <= current_frame_last;
                        out_valid       <= 1'b1;

                        // 准备收集下一个128位块
                        pack_data        <= 128'd0;
                        pack_strb        <= 16'd0;
                        pack_frame_start <= 1'b0;
                        lane_count       <= 3'd0;
                    end
                    else begin
                        // 保存尚未凑满的数据
                        pack_data        <= merged_data;
                        pack_strb        <= merged_strb;
                        pack_frame_start <= merged_frame_start;

                        if (in_frame_start)
                            lane_count <= 3'd1;
                        else
                            lane_count <= lane_count + 1'b1;
                    end
                end

                // 未观察到帧首时，输入像素被取走但不打包。
                // 收满预定像素后，也等待下一帧首标志。
            end
        end
    end

endmodule