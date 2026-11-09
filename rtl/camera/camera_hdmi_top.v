`timescale 1ns/1ps
// AC880PRO: native 1280x720 RGB565 fills the established 720p HDMI2 timing.
module camera_hdmi_top(
 input wire sys_clk,reset_n,
 input wire camera_pclk,camera_vsync,camera_href,
 input wire [7:0] camera_data,
 output wire camera_xclk,camera_scl,inout wire camera_sda,
 output wire [3:0] led,
 output wire [2:0] tmds_data_p,tmds_data_n,
 output wire tmds_clk_p,tmds_clk_n,
 inout wire [15:0] ddr3_dq,
 inout wire [1:0] ddr3_dqs_p,
 inout wire [1:0] ddr3_dqs_n,
 output wire [13:0] ddr3_addr,
 output wire [2:0] ddr3_ba,
 output wire  ddr3_ras_n,
 output wire  ddr3_cas_n,
 output wire  ddr3_we_n,
 output wire  ddr3_reset_n,
 output wire [0:0] ddr3_ck_p,
 output wire [0:0] ddr3_ck_n,
 output wire [0:0] ddr3_cke,
 output wire [0:0] ddr3_cs_n,
 output wire [1:0] ddr3_dm,
 output wire [0:0] ddr3_odt
);

// Single definition for sensor, ingress, packer and AXI frame size.
localparam IMAGE_WIDTH = 1280;
localparam IMAGE_HEIGHT = 720;
localparam FRAME_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT;
localparam FRAME_BEATS = FRAME_PIXELS / 8;
localparam PIXEL_COUNT_BITS = $clog2(FRAME_PIXELS + 1);

wire sys_clk50;
BUFG system_clock_buf(.I(sys_clk),.O(sys_clk50));
(* ASYNC_REG="TRUE" *) reg [2:0] system_reset_sync;
always @(posedge sys_clk50 or negedge reset_n)
 if(!reset_n) system_reset_sync<=3'b111;
 else system_reset_sync<={system_reset_sync[1:0],1'b0};
wire sys_reset=system_reset_sync[2];
wire ui_clk,ui_reset,init_calib_complete;
wire camera_done,camera_error;wire [2:0] camera_error_code;wire [15:0] chip_id;
wire pixel_clk,serial_clk_5x,pixel_reset;
wire cam_rst_unused,cam_pwdn_unused,camera_clk24;
ODDR #(.DDR_CLK_EDGE("SAME_EDGE")) camera_clock_out(
 .C(camera_clk24),.CE(1'b1),.D1(1'b1),.D2(1'b0),.R(1'b0),.S(1'b0),.Q(camera_xclk));
// Board camera header does not expose RST/PWDN to PL. Software reset in ROM
// is used; never assign the legacy N20 pin, which is not this board's reset.
ov5640_control #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) cam(.sys_clk(sys_clk50),.sys_reset(sys_reset),
 .camera_xclk(camera_clk24),.camera_rst_n(cam_rst_unused),.camera_pwdn(cam_pwdn_unused),
 .camera_scl(camera_scl),.camera_sda(camera_sda),.init_done(camera_done),
 .init_error(camera_error),.error_code(camera_error_code),.chip_id(chip_id));
wire pclk;
BUFG pclk_buf(.I(camera_pclk),.O(pclk));
wire cam_capture_reset=sys_reset||!camera_done;
wire sof,pv;wire [15:0] pd;
ov5640_capture capture(.camera_pclk(pclk),.capture_reset(cam_capture_reset),
 .camera_vsync(camera_vsync),.camera_href(camera_href),.camera_data(camera_data),
 .frame_start(sof),.pixel_valid(pv),.pixel_data(pd));
wire [16:0] cq_data;wire cq_empty,cq_pop,overflow_seen;
camera_ingress ingress(.pclk(pclk),.reset(cam_capture_reset||ui_reset),
 .frame_start(sof),.pixel_valid(pv),.pixel_data(pd),.ui_clk(ui_clk),
 .pop(cq_pop),.data(cq_data),.empty(cq_empty),.overflow_seen(overflow_seen));

wire cap_req,cap_ack,wstart,wstart_ready,wdone,werror;
wire [27:0] wbase;
wire disp_req,disp_req_ready,disp_cfg,disp_cfg_ready,disp_has;
wire [27:0] disp_base;
wire [31:0] frames_good,frames_bad;
frame_buffer_manager #(
 .BUFFER0_BASE(28'h0000000),.BUFFER1_BASE(28'h0200000),.BUFFER2_BASE(28'h0400000)
) manager(.clk(ui_clk),.reset(ui_reset),.ddr_ready(init_calib_complete),
 .capture_request_valid(cap_req),.capture_request_ready(cap_ack),
 .writer_start_valid(wstart),.writer_start_ready(wstart_ready),.writer_base_addr(wbase),
 .writer_done(wdone),.writer_error(werror),
 .display_request_valid(disp_req),.display_request_ready(disp_req_ready),
 .display_config_valid(disp_cfg),.display_config_ready(disp_cfg_ready),
 .display_base_addr(disp_base),.display_has_frame(disp_has),.capture_busy(),
 .completed_frame_count(frames_good),.failed_frame_count(frames_bad));

// Seek a queued SOF, reserve a free buffer, wait for writer acceptance, then
// deliver exactly one frame. A premature SOF aborts only the current frame.
localparam SEEK=0,COMMAND=1,STREAM=2,DRAIN=3;
reg [1:0] ingress_state;
reg [PIXEL_COUNT_BITS-1:0] input_pixels;
wire pack_ready,pack_valid,pack_start,pack_last,pack_out_ready,pack_error;
wire [127:0] pack_data;wire [15:0] pack_strb;
wire premature_sof=ingress_state==STREAM&&input_pixels!=0&&!cq_empty&&cq_data[16];
wire pack_reset=ui_reset||ingress_state!=STREAM||premature_sof;
wire feed=ingress_state==STREAM&&input_pixels<FRAME_PIXELS&&!premature_sof;
assign cap_req=ingress_state==SEEK&&!cq_empty&&cq_data[16];
assign cq_pop=(ingress_state==SEEK&&!cq_empty&&!cq_data[16]) ||
              (feed&&!cq_empty&&pack_ready);
always @(posedge ui_clk or posedge ui_reset) begin
 if(ui_reset) begin ingress_state<=SEEK;input_pixels<=0;end
 else case(ingress_state)
 SEEK: if(cap_req&&cap_ack) begin ingress_state<=COMMAND;input_pixels<=0;end
 COMMAND: if(wstart&&wstart_ready) ingress_state<=STREAM;
 STREAM: begin
  if(cq_pop) input_pixels<=input_pixels+1'b1;
  if(premature_sof) ingress_state<=DRAIN;
  if(wdone) ingress_state<=SEEK;
 end
 DRAIN: if(wdone) ingress_state<=SEEK;
 default: ingress_state<=SEEK;
 endcase
end
rgb565_packer #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) packer(.clk(ui_clk),.reset(pack_reset),.in_pixel(cq_data[15:0]),
 .in_frame_start(cq_data[16]),.in_valid(feed&&!cq_empty),.in_ready(pack_ready),
 .out_data(pack_data),.out_strb(pack_strb),.out_frame_start(pack_start),
 .out_frame_last(pack_last),.out_valid(pack_valid),.out_ready(pack_out_ready),
 .frame_error(pack_error));
wire [3:0] s_axi_awid;
wire [27:0] s_axi_awaddr;
wire [7:0] s_axi_awlen;
wire [2:0] s_axi_awsize;
wire [1:0] s_axi_awburst;
wire [0:0] s_axi_awlock;
wire [3:0] s_axi_awcache;
wire [2:0] s_axi_awprot;
wire [3:0] s_axi_awqos;
wire  s_axi_awvalid;
wire  s_axi_awready;
wire [127:0] s_axi_wdata;
wire [15:0] s_axi_wstrb;
wire  s_axi_wlast;
wire  s_axi_wvalid;
wire  s_axi_wready;
wire [3:0] s_axi_bid;
wire [1:0] s_axi_bresp;
wire  s_axi_bvalid;
wire  s_axi_bready;
wire [3:0] s_axi_arid;
wire [27:0] s_axi_araddr;
wire [7:0] s_axi_arlen;
wire [2:0] s_axi_arsize;
wire [1:0] s_axi_arburst;
wire [0:0] s_axi_arlock;
wire [3:0] s_axi_arcache;
wire [2:0] s_axi_arprot;
wire [3:0] s_axi_arqos;
wire  s_axi_arvalid;
wire  s_axi_arready;
wire [3:0] s_axi_rid;
wire [127:0] s_axi_rdata;
wire [1:0] s_axi_rresp;
wire  s_axi_rlast;
wire  s_axi_rvalid;
wire  s_axi_rready;
ddr_controller  ddr (
 .sys_clk(sys_clk50),
 .sys_reset(sys_reset),
 .ui_clk(ui_clk),
 .ui_reset(ui_reset),
 .init_calib_complete(init_calib_complete),
 .ddr3_dq(ddr3_dq),
 .ddr3_dqs_p(ddr3_dqs_p),
 .ddr3_dqs_n(ddr3_dqs_n),
 .ddr3_addr(ddr3_addr),
 .ddr3_ba(ddr3_ba),
 .ddr3_ras_n(ddr3_ras_n),
 .ddr3_cas_n(ddr3_cas_n),
 .ddr3_we_n(ddr3_we_n),
 .ddr3_reset_n(ddr3_reset_n),
 .ddr3_ck_p(ddr3_ck_p),
 .ddr3_ck_n(ddr3_ck_n),
 .ddr3_cke(ddr3_cke),
 .ddr3_cs_n(ddr3_cs_n),
 .ddr3_dm(ddr3_dm),
 .ddr3_odt(ddr3_odt),
 .s_axi_awid(s_axi_awid),
 .s_axi_awaddr(s_axi_awaddr),
 .s_axi_awlen(s_axi_awlen),
 .s_axi_awsize(s_axi_awsize),
 .s_axi_awburst(s_axi_awburst),
 .s_axi_awlock(s_axi_awlock),
 .s_axi_awcache(s_axi_awcache),
 .s_axi_awprot(s_axi_awprot),
 .s_axi_awqos(s_axi_awqos),
 .s_axi_awvalid(s_axi_awvalid),
 .s_axi_awready(s_axi_awready),
 .s_axi_wdata(s_axi_wdata),
 .s_axi_wstrb(s_axi_wstrb),
 .s_axi_wlast(s_axi_wlast),
 .s_axi_wvalid(s_axi_wvalid),
 .s_axi_wready(s_axi_wready),
 .s_axi_bid(s_axi_bid),
 .s_axi_bresp(s_axi_bresp),
 .s_axi_bvalid(s_axi_bvalid),
 .s_axi_bready(s_axi_bready),
 .s_axi_arid(s_axi_arid),
 .s_axi_araddr(s_axi_araddr),
 .s_axi_arlen(s_axi_arlen),
 .s_axi_arsize(s_axi_arsize),
 .s_axi_arburst(s_axi_arburst),
 .s_axi_arlock(s_axi_arlock),
 .s_axi_arcache(s_axi_arcache),
 .s_axi_arprot(s_axi_arprot),
 .s_axi_arqos(s_axi_arqos),
 .s_axi_arvalid(s_axi_arvalid),
 .s_axi_arready(s_axi_arready),
 .s_axi_rid(s_axi_rid),
 .s_axi_rdata(s_axi_rdata),
 .s_axi_rresp(s_axi_rresp),
 .s_axi_rlast(s_axi_rlast),
 .s_axi_rvalid(s_axi_rvalid),
 .s_axi_rready(s_axi_rready)
);
axi_frame_writer #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT)) writer (
 .m_axi_awid(s_axi_awid),
 .m_axi_awaddr(s_axi_awaddr),
 .m_axi_awlen(s_axi_awlen),
 .m_axi_awsize(s_axi_awsize),
 .m_axi_awburst(s_axi_awburst),
 .m_axi_awlock(s_axi_awlock),
 .m_axi_awcache(s_axi_awcache),
 .m_axi_awprot(s_axi_awprot),
 .m_axi_awqos(s_axi_awqos),
 .m_axi_awvalid(s_axi_awvalid),
 .m_axi_awready(s_axi_awready),
 .m_axi_wdata(s_axi_wdata),
 .m_axi_wstrb(s_axi_wstrb),
 .m_axi_wlast(s_axi_wlast),
 .m_axi_wvalid(s_axi_wvalid),
 .m_axi_wready(s_axi_wready),
 .m_axi_bid(s_axi_bid),
 .m_axi_bresp(s_axi_bresp),
 .m_axi_bvalid(s_axi_bvalid),
 .m_axi_bready(s_axi_bready),
 .clk(ui_clk),
 .reset(ui_reset),
 .ddr_ready(init_calib_complete),
 .frame_start_valid(wstart),
 .frame_start_ready(wstart_ready),
 .frame_base_addr(wbase),
 .busy(),
 .frame_done(wdone),
 .frame_error(werror),
 .in_data(pack_data),
 .in_strb(pack_strb),
 .in_frame_start(pack_start),
 .in_frame_last(pack_last),
 .in_valid(pack_valid),
 .in_ready(pack_out_ready),
 .abort_frame(premature_sof)
);

// Display request crosses as a persistent toggle, not a one-clock pulse.
wire hs,vs,de;wire [10:0] x;wire [9:0] y;
video_clock_reset video_clock(.sys_clk(sys_clk50),.sys_reset(sys_reset),
 .pixel_clk(pixel_clk),.serial_clk_5x(serial_clk_5x),.pixel_reset(pixel_reset));
video_timing timing(.pixel_clk(pixel_clk),.pixel_reset(pixel_reset),
 .hsync(hs),.vsync(vs),.de(de),.pixel_x(x),.pixel_y(y));
reg vs_d,display_toggle;
always @(posedge pixel_clk or posedge pixel_reset)
 if(pixel_reset) begin vs_d<=0;display_toggle<=0;end
 else begin vs_d<=vs;if(vs&&!vs_d) display_toggle<=!display_toggle;end
wire display_fifo_reset,display_fifo_full,display_fifo_empty,display_fifo_push;
wire [127:0] display_fifo_din,display_fifo_dout;
wire reader_error;
axi_display_reader #(.FRAME_BEATS(FRAME_BEATS)) reader(.clk(ui_clk),.reset(ui_reset),.ddr_ready(init_calib_complete),
 .request_toggle(display_toggle),.config_request(disp_req),.config_request_ready(disp_req_ready),
 .config_valid(disp_cfg),.config_has_frame(disp_has),.config_base(disp_base),.config_ready(disp_cfg_ready),
 .fifo_reset(display_fifo_reset),.fifo_push(display_fifo_push),.fifo_full(display_fifo_full),
 .fifo_data(display_fifo_din),.araddr(s_axi_araddr),.arlen(s_axi_arlen),
 .arvalid(s_axi_arvalid),.arready(s_axi_arready),.rdata(s_axi_rdata),.rresp(s_axi_rresp),
 .rlast(s_axi_rlast),.rvalid(s_axi_rvalid),.rready(s_axi_rready),.read_error(reader_error));
assign s_axi_arid=0;
assign s_axi_arsize=4;
assign s_axi_arburst=1;
assign s_axi_arlock=0;
assign s_axi_arcache=0;
assign s_axi_arprot=0;
assign s_axi_arqos=0;
wire dq_reset=ui_reset||display_fifo_reset||pixel_reset;
(* ASYNC_REG="TRUE" *) reg [2:0] display_reset_sync;
always @(posedge pixel_clk or posedge dq_reset)
 if(dq_reset) display_reset_sync<=3'b111;
 else display_reset_sync<={display_reset_sync[1:0],1'b0};
wire display_pixel_reset=display_reset_sync[2];
wire window=de;
reg [2:0] lane;
reg display_bad;
wire consume=window&&!display_bad&&!display_fifo_empty;
wire display_pop=consume&&lane==7;
stream_async_fifo #(.WIDTH(128),.ADDR_BITS(9)) display_q(
 .reset(dq_reset),.wr_clk(ui_clk),.din(display_fifo_din),.wr_en(display_fifo_push),
 .full(display_fifo_full),.rd_clk(pixel_clk),.rd_en(display_pop),
 .dout(display_fifo_dout),.empty(display_fifo_empty));
wire [15:0] color565=display_fifo_dout[lane*16+:16];
reg [7:0] red,green,blue;
reg hs_reg,vs_reg,de_reg;
always @(posedge pixel_clk or posedge display_pixel_reset) begin
 if(display_pixel_reset) begin lane<=0;display_bad<=0;end
 else if(vs&&!vs_d) begin lane<=0;display_bad<=0;end
 else if(window) begin
  if(display_fifo_empty) display_bad<=1;
  else if(!display_bad) lane<=lane+1'b1;
 end
end
always @(posedge pixel_clk or posedge pixel_reset) begin
 if(pixel_reset) begin red<=0;green<=0;blue<=0;hs_reg<=0;vs_reg<=0;de_reg<=0;end
 else begin
  hs_reg<=hs;vs_reg<=vs;de_reg<=de;
  if(consume&&!display_pixel_reset) begin
   red<={color565[15:11],color565[15:13]};
   green<={color565[10:5],color565[10:9]};
   blue<={color565[4:0],color565[4:2]};
  end else begin red<=0;green<=0;blue<=0;end
 end
end
dvi_tx hdmi(.pixel_clk(pixel_clk),.serial_clk_5x(serial_clk_5x),.pixel_reset(pixel_reset),
 .red(red),.green(green),.blue(blue),.hsync(hs_reg),.vsync(vs_reg),.de(de_reg),
 .tmds_data_p(tmds_data_p),.tmds_data_n(tmds_data_n),.tmds_clk_p(tmds_clk_p),.tmds_clk_n(tmds_clk_n));
// ===== 临时 DVP 探针（调试版，验证后恢复原 LED 状态指示）=====
// led[0] = camera_vsync 实时电平 : 亮=平时为高（模组输出低有效脉冲）
// led[1] = camera_pclk 活动      : 闪=PCLK 有跳变，常亮/常灭=没有 PCLK
// led[2] = sof 曾经出现          : 亮=检测到帧边界
// led[3] = pv 曾经出现           : 亮=拼出过像素
reg [23:0] pclk_tog;
always @(posedge pclk or posedge cam_capture_reset)
 if(cam_capture_reset) pclk_tog<=24'd0; else pclk_tog<=pclk_tog+24'd1;

reg pv_seen,sof_seen;
always @(posedge pclk or posedge cam_capture_reset)
 if(cam_capture_reset) begin pv_seen<=0;sof_seen<=0;end
 else begin if(pv) pv_seen<=1; if(sof) sof_seen<=1; end

(* ASYNC_REG="TRUE" *) reg [3:0] dbg1,dbg2;
always @(posedge sys_clk50 or posedge sys_reset)
 if(sys_reset) begin dbg1<=0;dbg2<=0;end
 else begin dbg1<={pv_seen,sof_seen,pclk_tog[22],camera_vsync};dbg2<=dbg1;end
assign led=dbg2;

endmodule
