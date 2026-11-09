`timescale 1ns / 1ps

module tmds_encoder (
    input  wire       pixel_clk,
    input  wire       pixel_reset,

    input  wire [7:0] data_in,
    input  wire       de,
    input  wire       c0,
    input  wire       c1,

    output reg  [9:0] tmds_out
);

    // 第一阶段中间结果：
    // q_m[7:0]：经过 XOR / XNOR 处理的数据。
    // q_m[8]  ：1 表示 XOR，0 表示 XNOR。
    reg [8:0] q_m;

    integer data_ones;
    integer q_ones;
    integer balance;
    integer i;

    // 累计不平衡：
    // 正数表示此前发送的 1 更多，负数表示 0 更多。
    reg signed [5:0] disparity;

    // ============================================================
    // 第一阶段：组合逻辑，减少码字内部的跳变。
    // ============================================================
    always @(*) begin
        data_ones = 0;

        for (i = 0; i < 8; i = i + 1)
            data_ones = data_ones + data_in[i];

        q_m = 9'd0;
        q_m[0] = data_in[0];

        if ((data_ones > 4) ||
            ((data_ones == 4) && (data_in[0] == 1'b0))) begin

            // 使用 XNOR。
            for (i = 1; i < 8; i = i + 1)
                q_m[i] = ~(q_m[i-1] ^ data_in[i]);

            q_m[8] = 1'b0;
        end
        else begin

            // 使用 XOR。
            for (i = 1; i < 8; i = i + 1)
                q_m[i] = q_m[i-1] ^ data_in[i];

            q_m[8] = 1'b1;
        end

        // 统计中间数据低 8 位的不平衡。
        q_ones = 0;

        for (i = 0; i < 8; i = i + 1)
            q_ones = q_ones + q_m[i];

        // 1 的数量减去 0 的数量。
        balance = q_ones * 2 - 8;
    end

    // ============================================================
    // 第二阶段：时序逻辑，控制累计不平衡并输出码字。
    // ============================================================
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset) begin
            tmds_out <= 10'b1101010100;
            disparity <= 6'sd0;
        end
        else if (!de) begin
            // 消隐期间发送控制码，并清零累计状态。
            disparity <= 6'sd0;

            case ({c1, c0})
                2'b00: tmds_out <= 10'b1101010100;
                2'b01: tmds_out <= 10'b0010101011;
                2'b10: tmds_out <= 10'b0101010100;
                2'b11: tmds_out <= 10'b1010101011;
            endcase
        end
        else begin
            // 有效图像期间发送视频编码。
            if ((disparity == 0) || (balance == 0)) begin
                tmds_out[9] <= ~q_m[8];
                tmds_out[8] <=  q_m[8];

                if (q_m[8]) begin
                    tmds_out[7:0] <= q_m[7:0];
                    disparity <= disparity + balance;
                end
                else begin
                    tmds_out[7:0] <= ~q_m[7:0];
                    disparity <= disparity - balance;
                end
            end
            else if (((disparity > 0) && (balance > 0)) ||
                     ((disparity < 0) && (balance < 0))) begin

                // 中间数据会加重已有不平衡，反转低 8 位。
                tmds_out <= {1'b1, q_m[8], ~q_m[7:0]};

                disparity <= disparity - balance
                             + (q_m[8] ? 2 : 0);
            end
            else begin
                // 中间数据有助于抵消已有不平衡，不反转。
                tmds_out <= {1'b0, q_m[8], q_m[7:0]};

                disparity <= disparity + balance
                             - (q_m[8] ? 0 : 2);
            end
        end
    end

endmodule