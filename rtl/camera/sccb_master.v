`timescale 1ns / 1ps

module sccb_master #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter SCL_FREQ_HZ = 100_000,
    parameter [6:0] DEVICE_ADDR = 7'h3C
)(
    input  wire        clk,
    input  wire        reset,

    input  wire        start,
    input  wire        read_enable,
    input  wire [15:0] reg_addr,
    input  wire [7:0]  write_data,

    output reg  [7:0]  read_data,
    output reg         busy,
    output reg         done,
    output reg         nack_error,

    output wire        scl,
    inout  wire        sda
);

    // ============================================================
    // 1. �Ľ׶ν��ķ�����
    // ============================================================

    localparam TICK_CYCLES =
        CLK_FREQ_HZ / (SCL_FREQ_HZ * 4);

    localparam TICK_COUNT_WIDTH =
        (TICK_CYCLES <= 1) ? 1 : $clog2(TICK_CYCLES);

    reg [TICK_COUNT_WIDTH-1:0] tick_count;

    wire sccb_tick;

    always @(posedge clk or posedge reset) begin
        if (reset)
            tick_count <= 0;
        else if (tick_count == TICK_CYCLES - 1)
            tick_count <= 0;
        else
            tick_count <= tick_count + 1'b1;
    end

    assign sccb_tick =
        !reset && (tick_count == TICK_CYCLES - 1);

    // ============================================================
    // 2. �������
    //
    // SDA Ϊ��©��ʽ��
    // sda_drive_low = 1������͵�ƽ��
    // sda_drive_low = 0���ͷ���·�����ⲿ�����������ߡ�
    // ============================================================

    reg scl_out;
    reg sda_drive_low;

    (* ASYNC_REG="TRUE" *) reg [1:0] sda_sync;
    always @(posedge clk or posedge reset)
        if (reset) sda_sync <= 2'b11;
        else sda_sync <= {sda_sync[0], sda};
    assign scl = scl_out;
    assign sda = sda_drive_low ? 1'b0 : 1'bz;

    // ============================================================
    // 3. ״̬������Ĵ���
    // ============================================================

    localparam [3:0]
        ST_IDLE       = 4'd0,
        ST_START      = 4'd1,
        ST_SEND       = 4'd2,
        ST_ACK        = 4'd3,
        ST_RESTART    = 4'd4,
        ST_READ       = 4'd5,
        ST_READ_NACK  = 4'd6,
        ST_STOP       = 4'd7;

    reg [3:0] state;
    reg [1:0] phase;

    // ���汾��������������⴫���ڼ����ⲿ����仯Ӱ�졣
    reg        read_latched;
    reg [15:0] addr_latched;
    reg [7:0]  write_latched;

    reg [7:0] tx_shift;
    reg [7:0] rx_shift;

    reg [2:0] bit_index;

    // ��ǰ���͵��ֽ����ͣ�
    // 0���豸��ַ + дλ
    // 1���Ĵ�����ַ���ֽ�
    // 2���Ĵ�����ַ���ֽ�
    // 3���豸��ַ + ��λ
    // 4��д������
    reg [2:0] byte_index;

    reg ack_failed;

    // ============================================================
    // 4. ����״̬��
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state          <= ST_IDLE;
            phase          <= 2'd0;

            scl_out        <= 1'b1;
            sda_drive_low  <= 1'b0;

            read_latched   <= 1'b0;
            addr_latched   <= 16'd0;
            write_latched  <= 8'd0;

            tx_shift       <= 8'd0;
            rx_shift       <= 8'd0;
            bit_index      <= 3'd7;
            byte_index     <= 3'd0;

            ack_failed     <= 1'b0;

            read_data      <= 8'd0;
            busy           <= 1'b0;
            done           <= 1'b0;
            nack_error     <= 1'b0;
        end
        else begin
            // done Ĭ�����ͣ�ֻ���������ʱ����һ��ϵͳ���ڡ�
            done <= 1'b0;

            if (state == ST_IDLE) begin
                scl_out       <= 1'b1;
                sda_drive_low <= 1'b0;
                busy          <= 1'b0;
                phase         <= 2'd0;

                if (start) begin
                    read_latched  <= read_enable;
                    addr_latched  <= reg_addr;
                    write_latched <= write_data;

                    tx_shift      <= {DEVICE_ADDR, 1'b0};
                    rx_shift      <= 8'd0;
                    bit_index     <= 3'd7;
                    byte_index    <= 3'd0;

                    ack_failed    <= 1'b0;
                    nack_error    <= 1'b0;

                    busy          <= 1'b1;
                    state         <= ST_START;
                end
            end
            else if (sccb_tick) begin
                phase <= phase + 1'b1;

                case (state)

                    // ------------------------------------------------
                    // ��ʼ������SCL Ϊ��ʱ��SDA �Ӹ߱�͡�
                    // ------------------------------------------------
                    ST_START: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b1;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1:
                                sda_drive_low <= 1'b1;

                            2'd2: begin
                                // ���ֿ�ʼ������
                            end

                            2'd3: begin
                                scl_out <= 1'b0;
                                state   <= ST_SEND;
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // ����һ���ֽڣ����λ�ȷ��͡�
                    // ------------------------------------------------
                    ST_SEND: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= ~tx_shift[7];
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2: begin
                                // SCL �ߵ�ƽ�ڼ䱣�����ݡ�
                            end

                            2'd3: begin
                                scl_out <= 1'b0;

                                if (bit_index == 0) begin
                                    state <= ST_ACK;
                                end
                                else begin
                                    bit_index <= bit_index - 1'b1;
                                    tx_shift  <= {tx_shift[6:0], 1'b0};
                                end
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // �ھŸ�ʱ�ӣ��ͷ� SDA����������ͷӦ��
                    // ACK = 0��NACK = 1��
                    // ------------------------------------------------
                    ST_ACK: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2: begin
                                ack_failed <= sda_sync[1];

                                if (sda_sync[1])
                                    nack_error <= 1'b1;
                            end

                            2'd3: begin
                                scl_out <= 1'b0;

                                if (ack_failed) begin
                                    state <= ST_STOP;
                                end
                                else begin
                                    bit_index <= 3'd7;

                                    case (byte_index)
                                        3'd0: begin
                                            tx_shift   <= addr_latched[15:8];
                                            byte_index <= 3'd1;
                                            state      <= ST_SEND;
                                        end

                                        3'd1: begin
                                            tx_shift   <= addr_latched[7:0];
                                            byte_index <= 3'd2;
                                            state      <= ST_SEND;
                                        end

                                        3'd2: begin
                                            if (read_latched) begin
                                                state <= ST_RESTART;
                                            end
                                            else begin
                                                tx_shift   <= write_latched;
                                                byte_index <= 3'd4;
                                                state      <= ST_SEND;
                                            end
                                        end

                                        3'd3: begin
                                            rx_shift <= 8'd0;
                                            state    <= ST_READ;
                                        end

                                        3'd4:
                                            state <= ST_STOP;

                                        default:
                                            state <= ST_STOP;
                                    endcase
                                end
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // �����񣺷����ظ���ʼ������
                    // Ȼ�����豸��ַ + ��λ��
                    // ------------------------------------------------
                    ST_RESTART: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2:
                                sda_drive_low <= 1'b1;

                            2'd3: begin
                                scl_out   <= 1'b0;
                                tx_shift  <= {DEVICE_ADDR, 1'b1};
                                bit_index <= 3'd7;
                                byte_index <= 3'd3;
                                state     <= ST_SEND;
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // ��ȡһ���ֽڣ����λ�Ƚ��ա�
                    // ------------------------------------------------
                    ST_READ: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2:
                                rx_shift <= {rx_shift[6:0], sda_sync[1]};

                            2'd3: begin
                                scl_out <= 1'b0;

                                if (bit_index == 0) begin
                                    read_data <= rx_shift;
                                    state     <= ST_READ_NACK;
                                end
                                else begin
                                    bit_index <= bit_index - 1'b1;
                                end
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // ֻ��ȡһ���ֽڣ�
                    // �������� NACK����ʾ���ټ�����ȡ��
                    // ����� NACK ������������������ nack_error��
                    // ------------------------------------------------
                    ST_READ_NACK: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= 1'b0;
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2: begin
                                // �ͷ� SDA������ NACK��
                            end

                            2'd3: begin
                                scl_out <= 1'b0;
                                state   <= ST_STOP;
                            end
                        endcase
                    end

                    // ------------------------------------------------
                    // ֹͣ������SCL Ϊ��ʱ��SDA �ӵͱ�ߡ�
                    // ------------------------------------------------
                    ST_STOP: begin
                        case (phase)
                            2'd0: begin
                                scl_out       <= 1'b0;
                                sda_drive_low <= 1'b1;
                            end

                            2'd1:
                                scl_out <= 1'b1;

                            2'd2:
                                sda_drive_low <= 1'b0;

                            2'd3: begin
                                busy  <= 1'b0;
                                done  <= 1'b1;
                                state <= ST_IDLE;
                            end
                        endcase
                    end

                    default: begin
                        scl_out       <= 1'b1;
                        sda_drive_low <= 1'b0;
                        busy          <= 1'b0;
                        state         <= ST_IDLE;
                        phase         <= 2'd0;
                    end

                endcase
            end
        end
    end

endmodule