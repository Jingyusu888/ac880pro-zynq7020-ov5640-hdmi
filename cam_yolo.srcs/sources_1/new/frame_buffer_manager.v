`timescale 1ns / 1ps

module frame_buffer_manager #(
    // 三块独立缓存，每块预留1 MiB。
    // 当前640x480 RGB565一帧614400字节，可以放下。
    parameter [27:0] BUFFER0_BASE = 28'h0000000,
    parameter [27:0] BUFFER1_BASE = 28'h0100000,
    parameter [27:0] BUFFER2_BASE = 28'h0200000
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        ddr_ready,

    // ============================================================
    // 1. 采集侧申请
    //
    // valid && ready：接受一帧采集任务。
    // 未握手前，不能向写入器交付这帧的数据。
    // ============================================================

    input  wire        capture_request_valid,
    output wire        capture_request_ready,

    // ============================================================
    // 2. 连接axi_frame_writer的任务接口
    // ============================================================

    output reg         writer_start_valid,
    input  wire        writer_start_ready,
    output reg  [27:0] writer_base_addr,

    input  wire        writer_done,
    input  wire        writer_error,

    // ============================================================
    // 3. 显示侧请求下一帧
    //
    // 请求前必须停止旧帧读取，并完成旧帧在途事务及引用。
    // 请求握手后，等待display_config_valid返回。
    // ============================================================

    input  wire        display_request_valid,
    output wire        display_request_ready,

    // 显示配置响应
    // config_valid && config_ready：正式采用此显示配置
    output reg         display_config_valid,
    input  wire        display_config_ready,

    output reg  [27:0] display_base_addr,

    // 0：还没有完整画面，显示侧应输出黑色/测试图
    // 1：display_base_addr指向有效完整帧
    output reg         display_has_frame,

    // ============================================================
    // 4. 状态统计
    // ============================================================

    output wire        capture_busy,

    // 统计写入器报告的成功/失败帧任务。
    // 没有获准开始的摄像头帧，不包含在这两个计数中。
    output reg  [31:0] completed_frame_count,
    output reg  [31:0] failed_frame_count
);

    // ============================================================
    // 缓存归属状态
    // ============================================================

    localparam [2:0] BUF_FREE    = 3'd0;
    localparam [2:0] BUF_WRITING = 3'd1;
    localparam [2:0] BUF_READY   = 3'd2;
    localparam [2:0] BUF_DISPLAY = 3'd3;
    localparam [2:0] BUF_PENDING = 3'd4;

    reg [2:0] buffer_state [0:2];

    // 正在准备或执行写入的缓存编号
    reg [1:0] write_buffer_id;
    reg       writer_active;

    // 当前显示缓存
    reg [1:0] current_display_id;
    reg       current_display_valid;

    // 等待显示侧确认的新缓存
    reg [1:0] pending_display_id;
    reg       pending_switch;

    // 最近完成的缓存编号，用于优先选择最新完整帧
    reg [1:0] latest_ready_id;

    reg       free_found;
    reg [1:0] free_id;

    reg       ready_found;
    reg [1:0] ready_id;

    integer i;
    integer j;


    // ============================================================
    // 将缓存编号转换成DDR字节地址
    // ============================================================

    function [27:0] buffer_base;
        input [1:0] buffer_id;
        begin
            case (buffer_id)
                2'd0: buffer_base = BUFFER0_BASE;
                2'd1: buffer_base = BUFFER1_BASE;
                2'd2: buffer_base = BUFFER2_BASE;
                default: buffer_base = BUFFER0_BASE;
            endcase
        end
    endfunction


    // ============================================================
    // 选择空闲缓存及可显示缓存
    //
    // 空闲缓存：只能选择BUF_FREE。
    // 完整缓存：优先选择最近完成的一帧。
    // ============================================================

    always @(*) begin
        free_found = 1'b0;
        free_id    = 2'd0;

        ready_found = 1'b0;
        ready_id    = 2'd0;

        for (i = 0; i < 3; i = i + 1) begin
            if (!free_found &&
                buffer_state[i] == BUF_FREE) begin
                free_found = 1'b1;
                free_id    = i;
            end

            if (!ready_found &&
                buffer_state[i] == BUF_READY) begin
                ready_found = 1'b1;
                ready_id    = i;
            end
        end

        if (buffer_state[latest_ready_id] == BUF_READY) begin
            ready_found = 1'b1;
            ready_id    = latest_ready_id;
        end
    end


    // ============================================================
    // 请求接受条件
    // ============================================================

    assign capture_busy =
        writer_start_valid || writer_active;

    assign capture_request_ready =
        !reset &&
        ddr_ready &&
        !capture_busy &&
        free_found;

    assign display_request_ready =
        !reset &&
        ddr_ready &&
        !display_config_valid;


    // ============================================================
    // 缓存管理
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (j = 0; j < 3; j = j + 1)
                buffer_state[j] <= BUF_FREE;

            write_buffer_id      <= 2'd0;
            writer_active        <= 1'b0;
            writer_start_valid   <= 1'b0;
            writer_base_addr     <= BUFFER0_BASE;

            current_display_id    <= 2'd0;
            current_display_valid <= 1'b0;

            pending_display_id <= 2'd0;
            pending_switch     <= 1'b0;
            latest_ready_id    <= 2'd0;

            display_config_valid <= 1'b0;
            display_base_addr    <= BUFFER0_BASE;
            display_has_frame    <= 1'b0;

            completed_frame_count <= 32'd0;
            failed_frame_count    <= 32'd0;
        end
        else begin

            // ----------------------------------------------------
            // A. 写入器接收任务
            // ----------------------------------------------------

            if (writer_start_valid && writer_start_ready) begin
                writer_start_valid <= 1'b0;
                writer_active      <= 1'b1;
            end

            // ----------------------------------------------------
            // B. 写入任务结束
            //
            // 失败：缓存直接释放，不能显示。
            // 成功：缓存成为完整帧。
            //
            // 新完整帧到达时，淘汰尚未被显示侧选中的旧完整帧。
            // 正在显示和待确认的缓存不受影响。
            // ----------------------------------------------------

            if (writer_done && writer_active) begin
                writer_active <= 1'b0;

                if (writer_error) begin
                    buffer_state[write_buffer_id] <= BUF_FREE;

                    failed_frame_count <=
                        failed_frame_count + 1'b1;
                end
                else begin
                    for (j = 0; j < 3; j = j + 1) begin
                        if (buffer_state[j] == BUF_READY)
                            buffer_state[j] <= BUF_FREE;
                    end

                    buffer_state[write_buffer_id] <= BUF_READY;
                    latest_ready_id <= write_buffer_id;

                    completed_frame_count <=
                        completed_frame_count + 1'b1;
                end
            end

            // ----------------------------------------------------
            // C. 接受一帧采集申请
            //
            // 先占用缓存，再向写入器提交任务。
            // 地址保持到writer握手完成。
            // ----------------------------------------------------

            if (capture_request_valid &&
                capture_request_ready) begin

                buffer_state[free_id] <= BUF_WRITING;
                write_buffer_id       <= free_id;

                writer_base_addr   <= buffer_base(free_id);
                writer_start_valid <= 1'b1;
            end

            // ----------------------------------------------------
            // D. 显示侧申请下一帧
            //
            // 有新完整帧：预留它，等待显示侧确认。
            // 没有新帧：继续使用当前显示帧。
            // 尚无任何显示帧：返回has_frame=0。
            //
            // 同拍刚写完的新帧，最早下一次请求才会被选中。
            // ----------------------------------------------------

            if (display_request_valid &&
                display_request_ready) begin

                display_config_valid <= 1'b1;

                if (ready_found) begin
                    buffer_state[ready_id] <= BUF_PENDING;

                    pending_display_id <= ready_id;
                    pending_switch     <= 1'b1;

                    display_base_addr <= buffer_base(ready_id);
                    display_has_frame <= 1'b1;
                end
                else begin
                    pending_switch <= 1'b0;

                    display_base_addr <=
                        buffer_base(current_display_id);

                    display_has_frame <= current_display_valid;
                end
            end

            // ----------------------------------------------------
            // E. 显示侧确认采用配置
            //
            // 请求方已保证旧帧不再有在途读取及预取引用，
            // 所以此时才能释放旧显示缓存。
            // ----------------------------------------------------

            if (display_config_valid &&
                display_config_ready) begin

                display_config_valid <= 1'b0;

                if (pending_switch) begin
                    if (current_display_valid)
                        buffer_state[current_display_id] <= BUF_FREE;

                    buffer_state[pending_display_id] <= BUF_DISPLAY;

                    current_display_id    <= pending_display_id;
                    current_display_valid <= 1'b1;

                    pending_switch <= 1'b0;
                end
            end
        end
    end

endmodule