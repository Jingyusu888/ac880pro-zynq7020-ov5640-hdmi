`timescale 1ns / 1ps

module ddr_controller (
    // ============================================================
    // 1. 系统输入与用户侧状态
    // ============================================================

    input  wire         sys_clk,
    input  wire         sys_reset,

    output wire         ui_clk,
    output wire         ui_reset,
    output wire         init_calib_complete,

    // ============================================================
    // 2. DDR物理接口
    // ============================================================

    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_p,
    inout  wire [1:0]   ddr3_dqs_n,

    output wire [13:0]  ddr3_addr,
    output wire [2:0]   ddr3_ba,

    output wire         ddr3_ras_n,
    output wire         ddr3_cas_n,
    output wire         ddr3_we_n,
    output wire         ddr3_reset_n,

    output wire [0:0]   ddr3_ck_p,
    output wire [0:0]   ddr3_ck_n,
    output wire [0:0]   ddr3_cke,
    output wire [0:0]   ddr3_cs_n,
    output wire [1:0]   ddr3_dm,
    output wire [0:0]   ddr3_odt,

    // ============================================================
    // 3. AXI写地址通道 AW
    // 所有AXI信号均属于ui_clk时钟域
    // ============================================================

    input  wire [3:0]   s_axi_awid,
    input  wire [27:0]  s_axi_awaddr,
    input  wire [7:0]   s_axi_awlen,
    input  wire [2:0]   s_axi_awsize,
    input  wire [1:0]   s_axi_awburst,
    input  wire [0:0]   s_axi_awlock,
    input  wire [3:0]   s_axi_awcache,
    input  wire [2:0]   s_axi_awprot,
    input  wire [3:0]   s_axi_awqos,
    input  wire         s_axi_awvalid,
    output wire         s_axi_awready,

    // ============================================================
    // 4. AXI写数据通道 W
    // ============================================================

    input  wire [127:0] s_axi_wdata,
    input  wire [15:0]  s_axi_wstrb,
    input  wire         s_axi_wlast,
    input  wire         s_axi_wvalid,
    output wire         s_axi_wready,

    // ============================================================
    // 5. AXI写响应通道 B
    // ============================================================

    output wire [3:0]   s_axi_bid,
    output wire [1:0]   s_axi_bresp,
    output wire         s_axi_bvalid,
    input  wire         s_axi_bready,

    // ============================================================
    // 6. AXI读地址通道 AR
    // ============================================================

    input  wire [3:0]   s_axi_arid,
    input  wire [27:0]  s_axi_araddr,
    input  wire [7:0]   s_axi_arlen,
    input  wire [2:0]   s_axi_arsize,
    input  wire [1:0]   s_axi_arburst,
    input  wire [0:0]   s_axi_arlock,
    input  wire [3:0]   s_axi_arcache,
    input  wire [2:0]   s_axi_arprot,
    input  wire [3:0]   s_axi_arqos,
    input  wire         s_axi_arvalid,
    output wire         s_axi_arready,

    // ============================================================
    // 7. AXI读数据通道 R
    // ============================================================

    output wire [3:0]   s_axi_rid,
    output wire [127:0] s_axi_rdata,
    output wire [1:0]   s_axi_rresp,
    output wire         s_axi_rlast,
    output wire         s_axi_rvalid,
    input  wire         s_axi_rready
);

    // ============================================================
    // 内部信号
    // ============================================================

    wire ddr_sys_clk;
    wire mig_sys_reset;

    wire mig_ui_reset;
    wire mig_mmcm_locked;

    wire axi_reset_request;
    wire axi_aresetn;

    (* ASYNC_REG = "TRUE" *)
    reg [1:0] axi_reset_sync;


    // ============================================================
    // 8. 产生MIG所需的200 MHz时钟与高有效复位
    // ============================================================

    ddr_clock_reset u_ddr_clock_reset (
        .sys_clk       (sys_clk),
        .sys_reset     (sys_reset),

        .ddr_sys_clk   (ddr_sys_clk),
        .mig_sys_reset (mig_sys_reset)
    );


    // ============================================================
    // 9. AXI接口复位
    //
    // 系统/MIG复位，或者MIG内部时钟未锁定时，保持复位。
    // 在ui_clk域同步释放。
    //
    // 不将init_calib_complete作为MIG复位条件，
    // 避免等待校准与复位之间形成循环。
    // ============================================================

    assign axi_reset_request =
        sys_reset          ||
        mig_sys_reset      ||
        mig_ui_reset       ||
        !mig_mmcm_locked;

    always @(posedge ui_clk or posedge axi_reset_request) begin
        if (axi_reset_request)
            axi_reset_sync <= 2'b11;
        else
            axi_reset_sync <= {axi_reset_sync[0], 1'b0};
    end

    // 高有效，供我们后续编写的用户逻辑使用
    assign ui_reset = axi_reset_sync[1];

    // 低有效，连接MIG内部AXI接口
    assign axi_aresetn = !ui_reset;


    // ============================================================
    // 10. MIG实例化
    //
    // 系统输入：内部200 MHz
    // Reference Clock：Use System Clock
    // sys_rst：ACTIVE HIGH
    // AXI：128位数据、28位地址、4位ID
    // ============================================================

    mig_7series_0 u_mig_7series_0 (
        // DDR物理接口
        .ddr3_dq             (ddr3_dq),
        .ddr3_dqs_n          (ddr3_dqs_n),
        .ddr3_dqs_p          (ddr3_dqs_p),

        .ddr3_addr           (ddr3_addr),
        .ddr3_ba             (ddr3_ba),

        .ddr3_ras_n          (ddr3_ras_n),
        .ddr3_cas_n          (ddr3_cas_n),
        .ddr3_we_n           (ddr3_we_n),
        .ddr3_reset_n        (ddr3_reset_n),

        .ddr3_ck_p           (ddr3_ck_p),
        .ddr3_ck_n           (ddr3_ck_n),
        .ddr3_cke            (ddr3_cke),
        .ddr3_cs_n           (ddr3_cs_n),
        .ddr3_dm             (ddr3_dm),
        .ddr3_odt            (ddr3_odt),

        // 时钟、复位、校准状态
        .sys_clk_i           (ddr_sys_clk),
        .sys_rst             (mig_sys_reset),

        .ui_clk              (ui_clk),
        .ui_clk_sync_rst     (mig_ui_reset),
        .mmcm_locked         (mig_mmcm_locked),
        .aresetn             (axi_aresetn),

        .init_calib_complete (init_calib_complete),

        // 不主动请求自刷新、手动刷新或ZQ校准。
        // 正常自动维护由MIG处理。
        .app_sr_req          (1'b0),
        .app_ref_req         (1'b0),
        .app_zq_req          (1'b0),

        .app_sr_active       (),
        .app_ref_ack         (),
        .app_zq_ack          (),

        // MIG已启用内部XADC；温度输出暂不使用
        .device_temp         (),

        // AXI写地址
        .s_axi_awid          (s_axi_awid),
        .s_axi_awaddr        (s_axi_awaddr),
        .s_axi_awlen         (s_axi_awlen),
        .s_axi_awsize        (s_axi_awsize),
        .s_axi_awburst       (s_axi_awburst),
        .s_axi_awlock        (s_axi_awlock),
        .s_axi_awcache       (s_axi_awcache),
        .s_axi_awprot        (s_axi_awprot),
        .s_axi_awqos         (s_axi_awqos),
        .s_axi_awvalid       (s_axi_awvalid),
        .s_axi_awready       (s_axi_awready),

        // AXI写数据
        .s_axi_wdata         (s_axi_wdata),
        .s_axi_wstrb         (s_axi_wstrb),
        .s_axi_wlast         (s_axi_wlast),
        .s_axi_wvalid        (s_axi_wvalid),
        .s_axi_wready        (s_axi_wready),

        // AXI写响应
        .s_axi_bid           (s_axi_bid),
        .s_axi_bresp         (s_axi_bresp),
        .s_axi_bvalid        (s_axi_bvalid),
        .s_axi_bready        (s_axi_bready),

        // AXI读地址
        .s_axi_arid          (s_axi_arid),
        .s_axi_araddr        (s_axi_araddr),
        .s_axi_arlen         (s_axi_arlen),
        .s_axi_arsize        (s_axi_arsize),
        .s_axi_arburst       (s_axi_arburst),
        .s_axi_arlock        (s_axi_arlock),
        .s_axi_arcache       (s_axi_arcache),
        .s_axi_arprot        (s_axi_arprot),
        .s_axi_arqos         (s_axi_arqos),
        .s_axi_arvalid       (s_axi_arvalid),
        .s_axi_arready       (s_axi_arready),

        // AXI读数据
        .s_axi_rid           (s_axi_rid),
        .s_axi_rdata         (s_axi_rdata),
        .s_axi_rresp         (s_axi_rresp),
        .s_axi_rlast         (s_axi_rlast),
        .s_axi_rvalid        (s_axi_rvalid),
        .s_axi_rready        (s_axi_rready)
    );

endmodule