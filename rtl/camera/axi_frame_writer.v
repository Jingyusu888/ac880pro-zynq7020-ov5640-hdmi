`timescale 1ns / 1ps

module axi_frame_writer #(
    parameter IMAGE_WIDTH  = 640,
    parameter IMAGE_HEIGHT = 480
)(
    input  wire         clk,
    input  wire         reset,
    input  wire         ddr_ready,
    input wire abort_frame,

    // ============================================================
    // ֡����ӿ�
    // ��ʼ��ַ����16�ֽڶ��룬��ָ������д���֡���档
    // ���ֺ󣬹������������޸Ļ��øû��棬ֱ�����������
    // ============================================================

    input  wire         frame_start_valid,
    output wire         frame_start_ready,
    input  wire [27:0]  frame_base_addr,

    output wire         busy,
    output reg          frame_done,
    output reg          frame_error,

    // ============================================================
    // ���룺����rgb565_packer
    // ============================================================

    input  wire [127:0] in_data,
    input  wire [15:0]  in_strb,
    input  wire         in_frame_start,
    input  wire         in_frame_last,
    input  wire         in_valid,
    output wire         in_ready,

    // ============================================================
    // AXIд��ַͨ��
    // ============================================================

    output wire [3:0]   m_axi_awid,
    output wire [27:0]  m_axi_awaddr,
    output wire [7:0]   m_axi_awlen,
    output wire [2:0]   m_axi_awsize,
    output wire [1:0]   m_axi_awburst,
    output wire [0:0]   m_axi_awlock,
    output wire [3:0]   m_axi_awcache,
    output wire [2:0]   m_axi_awprot,
    output wire [3:0]   m_axi_awqos,
    output wire         m_axi_awvalid,
    input  wire         m_axi_awready,

    // ============================================================
    // AXIд����ͨ��
    // ============================================================

    output wire [127:0] m_axi_wdata,
    output wire [15:0]  m_axi_wstrb,
    output wire         m_axi_wlast,
    output wire         m_axi_wvalid,
    input  wire         m_axi_wready,

    // ============================================================
    // AXIд��Ӧͨ��
    // ============================================================

    input  wire [3:0]   m_axi_bid,
    input  wire [1:0]   m_axi_bresp,
    input  wire         m_axi_bvalid,
    output wire         m_axi_bready
);

    // ͼ��RGB565�洢��ÿ������2�ֽ�
    localparam FRAME_BYTES = IMAGE_WIDTH * IMAGE_HEIGHT * 2;

    // ÿ��AXI������16�ֽڣ�����һ�ĵ�֡β��WSTRB����
    localparam FRAME_BEATS = (FRAME_BYTES + 15) / 16;

    localparam LAST_BYTES = FRAME_BYTES % 16;

    localparam [15:0] LAST_STRB =
        (LAST_BYTES == 0) ?
        16'hFFFF :
        (16'hFFFF >> (16 - LAST_BYTES));

    localparam [2:0] ST_IDLE    = 3'd0;
    localparam [2:0] ST_PREPARE = 3'd1;
    localparam [2:0] ST_COLLECT = 3'd2;
    localparam [2:0] ST_AW      = 3'd3;
    localparam [2:0] ST_W       = 3'd4;
    localparam [2:0] ST_B       = 3'd5;

    reg [2:0] state;

    // һ����໺��16�ģ�ÿ��128λ
    reg [127:0] data_buffer [0:15];
    reg [15:0]  strb_buffer [0:15];

    reg [27:0] write_addr;

    // ����ͻ��������1��16
    reg [4:0] burst_beats;

    // �ռ�������������0��15
    reg [3:0] collect_index;
    reg [3:0] send_index;

    // ��֡ʣ������������������δ�ύ�ĵ�ǰͻ��
    reg [31:0] beats_remaining;

    reg first_word;
    reg cancel_frame;
    reg burst_is_last;

    // ============================================================
    // 1. ���㱾��ͻ������
    //
    // ͬʱ���㣺
    // - ������16��
    // - ��������֡ʣ������
    // - ����Խ4 KiB�߽�
    // ============================================================

    wire [12:0] bytes_to_4k;
    wire [8:0]  beats_to_4k;

    reg [4:0] next_burst_beats;

    assign bytes_to_4k =
        13'd4096 - {1'b0, write_addr[11:0]};

    assign beats_to_4k = bytes_to_4k[12:4];

    always @(*) begin
        next_burst_beats = 5'd16;

        if (beats_remaining < 32'd16)
            next_burst_beats = beats_remaining[4:0];

        if (beats_to_4k < next_burst_beats)
            next_burst_beats = beats_to_4k[4:0];
    end

    // ��29λ�������֡�����Ƿ񳬳�28λ��ַ�ռ�
    wire [28:0] frame_end_exclusive;

    assign frame_end_exclusive =
        {1'b0, frame_base_addr} + FRAME_BEATS * 16;

    wire frame_address_valid;

    assign frame_address_valid =
        (frame_base_addr[3:0] == 4'd0) &&
        (frame_end_exclusive <= 29'h10000000);

    // ============================================================
    // 2. �������ݼ��
    //
    // ֡����λ���ɷֱ��ʼ��㣬ͬʱ���packer�ṩ�ı�־��
    // ============================================================

    wire current_word_is_last;
    wire [15:0] expected_strb;
    wire input_format_error;

    assign current_word_is_last =
        burst_is_last &&
        ({1'b0, collect_index} == burst_beats - 1'b1);

    assign expected_strb =
        current_word_is_last ? LAST_STRB : 16'hFFFF;

    assign input_format_error =
        (in_frame_start != first_word) ||
        (in_frame_last != current_word_is_last) ||
        (in_strb != expected_strb);

    // ============================================================
    // 3. ֡���������������
    // ============================================================

    assign frame_start_ready =
        !reset &&
        ddr_ready &&
        (state == ST_IDLE);

    assign busy = (state != ST_IDLE);

    assign in_ready =
        !reset &&
        (state == ST_COLLECT);

    // ============================================================
    // 4. AXI���
    //
    // �̶�ID 0��ÿ��16�ֽڡ���ַ��������ͨ���ʡ�
    // VALIDֻ��״̬�͸�λ���ƣ����������READY��
    // ============================================================

    assign m_axi_awid    = 4'd0;
    assign m_axi_awaddr  = write_addr;
    assign m_axi_awlen   = {3'd0, burst_beats} - 8'd1;
    assign m_axi_awsize  = 3'd4;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0000;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;

    assign m_axi_awvalid =
        !reset && (state == ST_AW);

    assign m_axi_wdata = data_buffer[send_index];
    assign m_axi_wstrb = strb_buffer[send_index];

    assign m_axi_wlast =
        ({1'b0, send_index} == burst_beats - 1'b1);

    assign m_axi_wvalid =
        !reset && (state == ST_W);

    assign m_axi_bready =
        !reset && (state == ST_B);

    // ============================================================
    // 5. ����״̬��
    // ============================================================

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state           <= ST_IDLE;

            write_addr      <= 28'd0;
            burst_beats     <= 5'd1;
            collect_index   <= 4'd0;
            send_index      <= 4'd0;
            beats_remaining <= 32'd0;

            first_word      <= 1'b1;
            burst_is_last   <= 1'b0;

            cancel_frame <= 1'b0;
            frame_done      <= 1'b0;
            frame_error     <= 1'b0;
        end
        else begin
            if (abort_frame) cancel_frame <= 1'b1;
            // frame_doneÿ���������ʱֻ����һ��
            frame_done <= 1'b0;

            case (state)

                ST_IDLE: begin
                    if (frame_start_valid && frame_start_ready) begin
                        frame_error <= 1'b0;
                        cancel_frame <= 1'b0;

                        if (!frame_address_valid) begin
                            // ��ַ���󣬲�����AXI����
                            frame_done  <= 1'b1;
                            frame_error <= 1'b1;
                        end
                        else begin
                            write_addr      <= frame_base_addr;
                            beats_remaining <= FRAME_BEATS;
                            first_word      <= 1'b1;
                            state           <= ST_PREPARE;
                        end
                    end
                end

                ST_PREPARE: begin
                    burst_beats <= next_burst_beats;

                    burst_is_last <=
                        (beats_remaining ==
                         {27'd0, next_burst_beats});

                    collect_index <= 4'd0;
                    send_index    <= 4'd0;

                    state <= ST_COLLECT;
                end

                ST_COLLECT: begin
                    if (abort_frame || cancel_frame) begin
                        frame_done <= 1'b1; frame_error <= 1'b1; state <= ST_IDLE;
                    end else if (in_valid && in_ready) begin
                        if (input_format_error) begin
                            // ��ǰͻ����δ�ύ��ֱ�ӷ�����
                            // ֮ǰ�ɹ�д������������DDR�У�
                            // ֡���������뽫��֡��Ϊ��Ч��
                            frame_error <= 1'b1;
                            frame_done  <= 1'b1;
                            state       <= ST_IDLE;
                        end
                        else begin
                            data_buffer[collect_index] <= in_data;
                            strb_buffer[collect_index] <= in_strb;

                            first_word <= 1'b0;

                            if ({1'b0, collect_index} ==
                                burst_beats - 1'b1) begin
                                state <= ST_AW;
                            end
                            else begin
                                collect_index <=
                                    collect_index + 1'b1;
                            end
                        end
                    end
                end

                ST_AW: begin
                    // ��ַ�Ͳ������֣�ֱ������
                    if (m_axi_awvalid && m_axi_awready) begin
                        send_index <= 4'd0;
                        state      <= ST_W;
                    end
                end

                ST_W: begin
                    // ����һ�����ݱ����պ���ƽ�����
                    if (m_axi_wvalid && m_axi_wready) begin
                        if (m_axi_wlast) begin
                            state <= ST_B;
                        end
                        else begin
                            send_index <= send_index + 1'b1;
                        end
                    end
                end

                ST_B: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        if (cancel_frame || abort_frame || (m_axi_bresp != 2'b00) ||
                            (m_axi_bid != 4'd0)) begin
                            // ��Ӧ�Ѿ����գ����������ѽ�����
                            // ���汾֡ʧ�ܣ��ȴ���������������
                            frame_error <= 1'b1;
                            frame_done  <= 1'b1;
                            state       <= ST_IDLE;
                        end
                        else if (burst_is_last) begin
                            frame_error <= 1'b0;
                            frame_done  <= 1'b1;
                            state       <= ST_IDLE;
                        end
                        else begin
                            // ÿ��16�ֽڣ��ƽ�����һ����ַ
                            write_addr <= write_addr +
                                {19'd0, burst_beats, 4'b0000};

                            beats_remaining <= beats_remaining -
                                {27'd0, burst_beats};

                            state <= ST_PREPARE;
                        end
                    end
                end

                default: begin
                    // ״̬�쳣��ҪϵͳЭ����λ��
                    // ��������ٶ�δ֪����;AXI�����ѽ�����
                    frame_error <= 1'b1;
                end

            endcase
        end
    end

endmodule