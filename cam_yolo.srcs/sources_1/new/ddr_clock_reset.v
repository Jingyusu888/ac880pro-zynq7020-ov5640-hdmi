`timescale 1ns / 1ps

module ddr_clock_reset (
    input  wire sys_clk,
    input  wire sys_reset,

    // 送到 MIG 的 sys_clk_i
    output wire ddr_sys_clk,

    // 送到 MIG 的 sys_rst，高有效
    output wire mig_sys_reset
);

    wire ddr_clk_locked;
    wire reset_request;

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] reset_sync;

    // 在同步复位解除后，再保持若干个200 MHz周期
    reg [4:0] reset_hold_count;
    reg       reset_hold;


    // ============================================================
    // 1. 产生200 MHz时钟
    //
    // ddr_clk IP：
    // 输入50 MHz，输出200 MHz
    // ============================================================

    ddr_clk u_ddr_clk (
        .clk_in1  (sys_clk),
        .reset    (sys_reset),

        .clk_out1 (ddr_sys_clk),
        .locked   (ddr_clk_locked)
    );


    // ============================================================
    // 2. 复位请求
    //
    // 外部复位或者时钟失锁，均要求MIG复位。
    // ============================================================

    assign reset_request =
        sys_reset || !ddr_clk_locked;


    // ============================================================
    // 3. 在200 MHz域同步释放复位
    // ============================================================

    always @(posedge ddr_sys_clk or posedge reset_request) begin
        if (reset_request)
            reset_sync <= 2'b11;
        else
            reset_sync <= {reset_sync[0], 1'b0};
    end


    // ============================================================
    // 4. 延长复位保持时间
    //
    // reset_sync解除后，再计数32个200 MHz周期。
    // 32 × 5 ns = 160 ns
    // ============================================================

    always @(posedge ddr_sys_clk or posedge reset_sync[1]) begin
        if (reset_sync[1]) begin
            reset_hold_count <= 5'd0;
            reset_hold       <= 1'b1;
        end
        else if (reset_hold) begin
            if (reset_hold_count == 5'd31) begin
                reset_hold <= 1'b0;
            end
            else begin
                reset_hold_count <= reset_hold_count + 1'b1;
            end
        end
    end

    assign mig_sys_reset = reset_hold;

endmodule