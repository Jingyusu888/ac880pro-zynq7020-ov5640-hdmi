`timescale 1ns/1ps
// Initialization and AF share exactly one SCCB master.
// Image init_done is independent of AF success, keeping the video path running.
module ov5640_af_camera #(
 parameter CLK_FREQ_HZ=50000000,SCL_FREQ_HZ=100000,
 parameter IMAGE_WIDTH=1280,IMAGE_HEIGHT=720,
 parameter IMAGE_FLIP_EN=0,IMAGE_MIRROR_EN=0,
 parameter RESET_HOLD_MS=5,STARTUP_WAIT_MS=20,SOFT_RESET_WAIT_MS=5,
 parameter WRITE_GAP_US=100,BUS_TIMEOUT_MS=10,
 parameter AF_FW_TIMEOUT_MS=2000,AF_FOCUS_TIMEOUT_MS=5000,
 parameter AF_POLL_MS=5,AF_SETTLE_MS=200,
 parameter AF_INIT_FILE="ov5640_af_firmware.mem"
)(
 input wire sys_clk,sys_reset,focus_start,
 output wire camera_xclk,camera_rst_n,camera_pwdn,camera_scl,
 inout wire camera_sda,
 output wire init_done,init_error,output wire [2:0] error_code,
 output wire [15:0] chip_id,
 output wire af_ready,af_busy,af_done,af_success,af_error,
 output wire [2:0] af_error_code,output wire [7:0] af_status
);
 wire clock_ready;
 camera_clock_reset u_camera_clock_reset(.sys_clk(sys_clk),.sys_reset(sys_reset),
  .camera_xclk(camera_xclk),.camera_clk_ready(clock_ready));
 wire [7:0] cfg_addr;
 wire [23:0] cfg_data;
 ov5640_init_table_rgb #(.IMAGE_WIDTH(IMAGE_WIDTH),.IMAGE_HEIGHT(IMAGE_HEIGHT),
  .IMAGE_FLIP_EN(IMAGE_FLIP_EN),.IMAGE_MIRROR_EN(IMAGE_MIRROR_EN)) image_rom(
  .clk(sys_clk),.addr(cfg_addr),.q(cfg_data));
 wire ireset,istart,iread;
 wire [15:0] iaddr;wire [7:0] iwdata;
 wire areset,astart,aread;
 wire [15:0] aaddr;wire [7:0] awdata;
 wire [7:0] rdata;wire busy,done,nack;
 reg af_owner;
 wire control_reset=sys_reset||!clock_ready;
 always @(posedge sys_clk or posedge control_reset)
  if(control_reset) af_owner<=0;
  else if(!init_done) af_owner<=0;
  else af_owner<=1;
 ov5640_init_bus_ctrl #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.SCL_FREQ_HZ(SCL_FREQ_HZ),
  .RESET_HOLD_MS(RESET_HOLD_MS),.STARTUP_WAIT_MS(STARTUP_WAIT_MS),
  .SOFT_RESET_WAIT_MS(SOFT_RESET_WAIT_MS),.WRITE_GAP_US(WRITE_GAP_US),
  .BUS_TIMEOUT_MS(BUS_TIMEOUT_MS)) image_init(
  .clk(sys_clk),.reset(sys_reset),.camera_clk_ready(clock_ready),
  .camera_rst_n(camera_rst_n),.camera_pwdn(camera_pwdn),
  .cfg_addr(cfg_addr),.cfg_data(cfg_data),
  .bus_reset(ireset),.bus_start(istart),.bus_read(iread),
  .bus_addr(iaddr),.bus_write_data(iwdata),.bus_read_data(rdata),
  .bus_busy(busy),.bus_done(done&&!af_owner),.bus_nack_error(nack),
  .init_done(init_done),.init_error(init_error),.error_code(error_code),.chip_id(chip_id));
 wire [11:0] fw_addr;wire [7:0] fw_data;
 ov5640_af_rom #(.INIT_FILE(AF_INIT_FILE)) firmware_rom(
  .clk(sys_clk),.addr(fw_addr),.data(fw_data));
 ov5640_af_ctrl #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.BUS_TIMEOUT_MS(BUS_TIMEOUT_MS),
  .FW_TIMEOUT_MS(AF_FW_TIMEOUT_MS),.FOCUS_TIMEOUT_MS(AF_FOCUS_TIMEOUT_MS),
  .POLL_MS(AF_POLL_MS),.SETTLE_MS(AF_SETTLE_MS)) autofocus(
  .clk(sys_clk),.reset(control_reset||!af_owner),.image_ready(init_done),
  .focus_start(focus_start),.firmware_addr(fw_addr),.firmware_data(fw_data),
  .bus_reset(areset),.bus_start(astart),.bus_read(aread),.bus_addr(aaddr),
  .bus_write_data(awdata),.bus_read_data(rdata),.bus_busy(busy),
  .bus_done(done&&af_owner),.bus_nack_error(nack),
  .af_ready(af_ready),.af_busy(af_busy),.af_done(af_done),
  .af_success(af_success),.af_error(af_error),.error_code(af_error_code),.fw_status(af_status));
 sccb_master #(.CLK_FREQ_HZ(CLK_FREQ_HZ),.SCL_FREQ_HZ(SCL_FREQ_HZ)) shared_master(
  .clk(sys_clk),.reset(af_owner?areset:ireset),
  .start(af_owner?astart:istart),.read_enable(af_owner?aread:iread),
  .reg_addr(af_owner?aaddr:iaddr),.write_data(af_owner?awdata:iwdata),
  .read_data(rdata),.busy(busy),.done(done),.nack_error(nack),
  .scl(camera_scl),.sda(camera_sda));
endmodule
