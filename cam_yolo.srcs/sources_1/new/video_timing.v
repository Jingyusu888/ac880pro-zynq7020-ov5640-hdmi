`timescale 1ns / 1ps
module video_timing (
    input  wire        pixel_clk,
    input  wire        pixel_reset,

    output wire        hsync,
    output wire        vsync,
    output wire        de,

    output wire [10:0] pixel_x,
    output wire [9:0]  pixel_y
);

    // 接下来依次添加显示参数、计数器和输出逻辑。
    // 横向参数，单位：像素时钟周期。
    localparam H_SYNC   = 40;
    localparam H_BACK   = 220;
    localparam H_ACTIVE = 1280;
    localparam H_FRONT  = 110;
    
    localparam H_TOTAL =
        H_SYNC + H_BACK + H_ACTIVE + H_FRONT;
    
        reg [10:0] h_count;
//横向参数计数
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset)
            h_count <= 11'd0;
        else if (h_count == H_TOTAL - 1)
            h_count <= 11'd0;
        else
            h_count <= h_count + 11'd1;
    end
    
    
        // 纵向参数，单位：行。
    localparam V_ACTIVE = 720;
    localparam V_FRONT  = 5;
    localparam V_SYNC   = 5;
    localparam V_BACK   = 20;

    localparam V_TOTAL =
        V_ACTIVE + V_FRONT + V_SYNC + V_BACK;
    reg [9:0] v_count;
        
    always @(posedge pixel_clk or posedge pixel_reset) begin
        if (pixel_reset)
            v_count <= 10'd0;
        else if (h_count == H_TOTAL - 1) begin
            if (v_count == V_TOTAL - 1)
                v_count <= 10'd0;
            else
                v_count <= v_count + 10'd1;
        end
    end
    //横向的有效信号
    assign hsync =
    (h_count >= H_ACTIVE + H_FRONT) &&
    (h_count <  H_ACTIVE + H_FRONT + H_SYNC);
    //场同步有效信号
    assign vsync =
    (v_count >= V_ACTIVE + V_FRONT) &&
    (v_count <  V_ACTIVE + V_FRONT + V_SYNC);
    //有效画面信号（使能）
    assign de = !pixel_reset &&
            (h_count < H_ACTIVE) &&
            (v_count < V_ACTIVE);
            
    //我们从有效区间作为0开始计数的，所有x和y坐标可以用总的count
    assign pixel_x = de ? h_count : 11'd0;
    assign pixel_y = de ? v_count : 10'd0;
    
    
    
endmodule