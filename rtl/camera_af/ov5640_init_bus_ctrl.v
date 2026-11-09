`timescale 1ns / 1ps

module ov5640_init_bus_ctrl #(
    parameter CLK_FREQ_HZ       = 50_000_000,
    parameter SCL_FREQ_HZ       = 100_000,
    parameter CONFIG_COUNT      = 252,

    // 启动等待参数，可在仿真时缩短。
    parameter RESET_HOLD_MS      = 5,
    parameter STARTUP_WAIT_MS    = 20,
    parameter SOFT_RESET_WAIT_MS = 5,
    parameter WRITE_GAP_US       = 100,
    parameter BUS_TIMEOUT_MS     = 10
)(
    input  wire        clk,
    input  wire        reset,

    // 必须表示摄像头 XCLK 已经稳定。
    input  wire        camera_clk_ready,

    // 摄像头硬件控制。
    output reg         camera_rst_n,
    output wire        camera_pwdn,

    // 初始化配置表接口。
    output reg  [7:0]  cfg_addr,
    input  wire [23:0] cfg_data,

    // SCCB 总线。
    output reg         bus_reset,
    output reg         bus_start,
    output reg         bus_read,
    output reg [15:0]  bus_addr,
    output reg [7:0]   bus_write_data,
    input wire [7:0]   bus_read_data,
    input wire         bus_busy,
    input wire         bus_done,
    input wire         bus_nack_error,

    // 状态输出。
    output reg         init_done,
    output reg         init_error,
    output reg  [2:0]  error_code,
    output reg  [15:0] chip_id
);

    // ============================================================
    // 1. 等待时间，单位转换成系统时钟周期
    // ============================================================

    localparam RESET_CYCLES =
        (CLK_FREQ_HZ / 1000) * RESET_HOLD_MS;

    localparam STARTUP_CYCLES =
        (CLK_FREQ_HZ / 1000) * STARTUP_WAIT_MS;

    localparam SOFT_RESET_CYCLES =
        (CLK_FREQ_HZ / 1000) * SOFT_RESET_WAIT_MS;

    localparam WRITE_GAP_CYCLES =
        (CLK_FREQ_HZ / 1_000_000) * WRITE_GAP_US;

    localparam TIMEOUT_CYCLES =
        (CLK_FREQ_HZ / 1000) * BUS_TIMEOUT_MS;

    // PWDN 高有效，正常工作时保持为 0。
    assign camera_pwdn = 1'b0;

    // ============================================================
    // 2. SCCB 主机接口
    // ============================================================

    // ============================================================
    // 3. 状态及事务类型
    // ============================================================

    localparam [3:0]
        ST_WAIT_CLOCK    = 4'd0,
        ST_HARD_RESET    = 4'd1,
        ST_STARTUP_WAIT  = 4'd2,
        ST_REQUEST       = 4'd3,
        ST_WAIT_BUS      = 4'd4,
        ST_ROM_WAIT_1    = 4'd5,
        ST_ROM_WAIT_2    = 4'd6,
        ST_PREPARE_WRITE = 4'd7,
        ST_WRITE_DELAY  = 4'd8,
        ST_DONE         = 4'd9,
        ST_ERROR        = 4'd10;

    localparam [1:0]
        JOB_ID_HIGH = 2'd0,
        JOB_ID_LOW  = 2'd1,
        JOB_CONFIG  = 2'd2;

    // error_code：
    // 0：无错误
    // 1：SCCB 未应答
    // 2：芯片 ID 不匹配
    // 3：事务等待超时

    reg [3:0] state;
    reg [1:0] job;

    reg [31:0] delay_count;
    reg [31:0] timeout_count;
    reg [31:0] write_delay_cycles;

    // ============================================================
    // 4. 初始化控制状态机
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state              <= ST_WAIT_CLOCK;
            job                <= JOB_ID_HIGH;

            camera_rst_n       <= 1'b0;

            cfg_addr           <= 8'd0;

            bus_reset          <= 1'b1;
            bus_start          <= 1'b0;
            bus_read           <= 1'b0;
            bus_addr           <= 16'd0;
            bus_write_data     <= 8'd0;

            delay_count        <= 32'd0;
            timeout_count      <= 32'd0;
            write_delay_cycles <= 32'd0;

            init_done          <= 1'b0;
            init_error         <= 1'b0;
            error_code         <= 3'd0;
            chip_id            <= 16'd0;
        end
        else begin
            // 请求只保持一个系统时钟周期。
            bus_start <= 1'b0;

            if (!camera_clk_ready) begin
                // 摄像头时钟未准备好或失锁时，
                // 保持摄像头及 SCCB 主机复位。
                state          <= ST_WAIT_CLOCK;
                job            <= JOB_ID_HIGH;

                camera_rst_n   <= 1'b0;
                bus_reset      <= 1'b1;

                cfg_addr       <= 8'd0;
                delay_count    <= 32'd0;
                timeout_count  <= 32'd0;

                init_done      <= 1'b0;
                init_error     <= 1'b0;
                error_code     <= 3'd0;
                chip_id        <= 16'd0;
            end
            else begin
                case (state)

                    // --------------------------------------------
                    // 时钟准备好，开始计算硬件复位保持时间。
                    // --------------------------------------------
                    ST_WAIT_CLOCK: begin
                        camera_rst_n <= 1'b0;
                        bus_reset    <= 1'b1;
                        delay_count  <= 32'd0;

                        init_done    <= 1'b0;
                        init_error   <= 1'b0;
                        error_code   <= 3'd0;
                        chip_id      <= 16'd0;

                        state <= ST_HARD_RESET;
                    end

                    // --------------------------------------------
                    // 摄像头复位保持。
                    // --------------------------------------------
                    ST_HARD_RESET: begin
                        if ((RESET_CYCLES <= 1) ||
                            (delay_count >= RESET_CYCLES - 1)) begin

                            camera_rst_n <= 1'b1;
                            delay_count  <= 32'd0;
                            state        <= ST_STARTUP_WAIT;
                        end
                        else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    // --------------------------------------------
                    // 释放摄像头复位后，等待内部启动。
                    // --------------------------------------------
                    ST_STARTUP_WAIT: begin
                        if ((STARTUP_CYCLES <= 1) ||
                            (delay_count >= STARTUP_CYCLES - 1)) begin

                            bus_reset     <= 1'b0;

                            // 首先读取芯片 ID 高字节。
                            bus_read      <= 1'b1;
                            bus_addr      <= 16'h300A;
                            job           <= JOB_ID_HIGH;

                            timeout_count <= 32'd0;
                            state         <= ST_REQUEST;
                        end
                        else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    // --------------------------------------------
                    // 等待主机空闲，再发出单周期 start。
                    // 地址、方向和数据已经在前一状态准备好。
                    // --------------------------------------------
                    ST_REQUEST: begin
                        if (!bus_busy) begin
                            bus_start     <= 1'b1;
                            timeout_count <= 32'd0;
                            state         <= ST_WAIT_BUS;
                        end
                        else if ((TIMEOUT_CYCLES <= 1) ||
                                 (timeout_count >= TIMEOUT_CYCLES - 1)) begin

                            init_error <= 1'b1;
                            error_code <= 3'd3;
                            bus_reset  <= 1'b1;
                            state      <= ST_ERROR;
                        end
                        else begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                    end

                    // --------------------------------------------
                    // 等待本次寄存器事务结束。
                    // --------------------------------------------
                    ST_WAIT_BUS: begin
                        if (bus_done) begin
                            timeout_count <= 32'd0;

                            if (bus_nack_error) begin
                                init_error <= 1'b1;
                                error_code <= 3'd1;
                                bus_reset  <= 1'b1;
                                state      <= ST_ERROR;
                            end
                            else begin
                                case (job)

                                    JOB_ID_HIGH: begin
                                        chip_id[15:8] <= bus_read_data;

                                        // 接着读取 ID 低字节。
                                        bus_read <= 1'b1;
                                        bus_addr <= 16'h300B;
                                        job      <= JOB_ID_LOW;
                                        state    <= ST_REQUEST;
                                    end

                                    JOB_ID_LOW: begin
                                        chip_id[7:0] <= bus_read_data;

                                        if ({chip_id[15:8],
                                             bus_read_data} == 16'h5640) begin

                                            cfg_addr <= 8'd0;
                                            state    <= ST_ROM_WAIT_1;
                                        end
                                        else begin
                                            init_error <= 1'b1;
                                            error_code <= 3'd2;
                                            bus_reset  <= 1'b1;
                                            state      <= ST_ERROR;
                                        end
                                    end

                                    JOB_CONFIG: begin
                                        delay_count <= 32'd0;

                                        // 写软件复位寄存器后，
                                        // 需要等待摄像头内部恢复。
                                        if ((bus_addr == 16'h3008) &&
                                            bus_write_data[7]) begin

                                            write_delay_cycles
                                                <= SOFT_RESET_CYCLES;
                                        end
                                        else begin
                                            write_delay_cycles
                                                <= WRITE_GAP_CYCLES;
                                        end

                                        state <= ST_WRITE_DELAY;
                                    end

                                    default: begin
                                        init_error <= 1'b1;
                                        error_code <= 3'd3;
                                        bus_reset  <= 1'b1;
                                        state      <= ST_ERROR;
                                    end

                                endcase
                            end
                        end
                        else if ((TIMEOUT_CYCLES <= 1) ||
                                 (timeout_count >= TIMEOUT_CYCLES - 1)) begin

                            init_error <= 1'b1;
                            error_code <= 3'd3;
                            bus_reset  <= 1'b1;
                            state      <= ST_ERROR;
                        end
                        else begin
                            timeout_count <= timeout_count + 1'b1;
                        end
                    end

                    // --------------------------------------------
                    // 等待同步 ROM 输出稳定。
                    // --------------------------------------------
                    ST_ROM_WAIT_1: begin
                        state <= ST_ROM_WAIT_2;
                    end

                    ST_ROM_WAIT_2: begin
                        state <= ST_PREPARE_WRITE;
                    end

                    // --------------------------------------------
                    // 读取本项配置，准备一次写事务。
                    // cfg_data[23:8]：寄存器地址
                    // cfg_data[7:0] ：写入数据
                    // --------------------------------------------
                    ST_PREPARE_WRITE: begin
                        bus_read       <= 1'b0;
                        bus_addr       <= cfg_data[23:8];
                        bus_write_data <= cfg_data[7:0];

                        job            <= JOB_CONFIG;
                        timeout_count  <= 32'd0;

                        state <= ST_REQUEST;
                    end

                    // --------------------------------------------
                    // 每项写入后的等待。
                    // 最后一项完成后才置位 init_done。
                    // --------------------------------------------
                    ST_WRITE_DELAY: begin
                        if ((write_delay_cycles <= 1) ||
                            (delay_count >= write_delay_cycles - 1)) begin

                            delay_count <= 32'd0;

                            if (cfg_addr == CONFIG_COUNT - 1) begin
                                init_done <= 1'b1;
                                state     <= ST_DONE;
                            end
                            else begin
                                cfg_addr <= cfg_addr + 1'b1;
                                state    <= ST_ROM_WAIT_1;
                            end
                        end
                        else begin
                            delay_count <= delay_count + 1'b1;
                        end
                    end

                    // --------------------------------------------
                    // 完成状态：保持，直到复位或时钟失锁。
                    // --------------------------------------------
                    ST_DONE: begin
                        init_done <= 1'b1;
                    end

                    // --------------------------------------------
                    // 错误状态：停止事务，保留错误信息。
                    // 系统复位后重新执行。
                    // --------------------------------------------
                    ST_ERROR: begin
                        bus_reset <= 1'b1;
                        init_done <= 1'b0;
                    end

                    default: begin
                        init_error <= 1'b1;
                        error_code <= 3'd3;
                        bus_reset  <= 1'b1;
                        state      <= ST_ERROR;
                    end

                endcase
            end
        end
    end

endmodule