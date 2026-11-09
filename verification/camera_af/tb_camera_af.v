`timescale 1ns/1ps
module camera_clock_reset(input wire sys_clk,sys_reset,
 output wire camera_xclk,camera_clk_ready);
 assign camera_xclk=sys_clk;assign camera_clk_ready=!sys_reset;
endmodule

module tb_camera_af;
 reg clk=0,reset=1;always #125 clk=~clk;
 tri1 sda;wire scl,image_done,image_error,ready,busy,done,success,error;
 wire [2:0] ic,ac;wire [15:0] id;wire [7:0] status;
 reg slave_low=0;assign sda=slave_low?0:1'bz;
 ov5640_af_camera #(.CLK_FREQ_HZ(4000000),.SCL_FREQ_HZ(100000),
  .RESET_HOLD_MS(0),.STARTUP_WAIT_MS(0),.SOFT_RESET_WAIT_MS(0),.WRITE_GAP_US(0),
  .AF_POLL_MS(1),.AF_SETTLE_MS(1),.AF_FW_TIMEOUT_MS(20),.AF_FOCUS_TIMEOUT_MS(20)) dut(
  .sys_clk(clk),.sys_reset(reset),.focus_start(1'b0),.camera_scl(scl),.camera_sda(sda),
  .init_done(image_done),.init_error(image_error),.error_code(ic),.chip_id(id),
  .af_ready(ready),.af_busy(busy),.af_done(done),.af_success(success),
  .af_error(error),.af_error_code(ac),.af_status(status));
 reg [7:0] firmware[0:4095];
 initial $readmemh("ov5640_af_firmware.mem",firmware);
 reg [7:0] golden_addr=0;wire [23:0] golden;
 ov5640_init_table_rgb #(.IMAGE_WIDTH(1280),.IMAGE_HEIGHT(720)) golden_rom(
  .clk(clk),.addr(golden_addr),.q(golden));
 integer writes=0,fw_writes=0,reads=0,phase=0,ack_pending=0;
 integer fw_polls=0,focus_polls=0,focus_commands=0,tail;
 reg mcu_running=0,focus_running=0;
 reg [7:0] device_byte,hi,lo,value,reply;
 reg [23:0] expected;
 reg reject_byte;
 task receive_byte;
  output [7:0] b;input ack;integer j;
  begin
   b=0;
   for(j=7;j>=0;j=j-1) begin @(posedge scl);b[j]=sda;end
   @(negedge scl);slave_low=ack;@(posedge scl);@(negedge scl);slave_low=0;
  end
 endtask
 task wait_start;
  begin @(negedge sda);while(scl!==1) @(negedge sda);end
 endtask
 task send_byte;
  input [7:0] b;integer j;
  begin
   for(j=7;j>=0;j=j-1) begin slave_low=!b[j];@(posedge scl);@(negedge scl);end
   slave_low=0;@(posedge scl);
   if(sda!==1) $fatal(1,"SCCB read must end with master NACK");
  end
 endtask
 initial begin
  wait(!reset);
  forever begin
   wait_start;
   receive_byte(device_byte,1);if(device_byte!==8'h78) $fatal(1,"wrong SCCB device");
   receive_byte(hi,1);receive_byte(lo,1);
   if(dut.shared_master.read_latched) begin
    wait_start;receive_byte(device_byte,1);
    if(device_byte!==8'h79) $fatal(1,"wrong SCCB read device");
    case({hi,lo})
     16'h300a: reply=8'h56;
     16'h300b: reply=8'h40;
     16'h3023: begin reply=(ack_pending>0)?1:0;if(ack_pending>0)ack_pending=ack_pending-1;end
     16'h3029: begin
      if(!focus_running) begin reply=(fw_polls<2)?8'h7e:8'h70;fw_polls=fw_polls+1;end
      else begin reply=(focus_polls<2)?0:8'h10;focus_polls=focus_polls+1;end
     end
     default: $fatal(1,"unexpected SCCB register read");
    endcase
    send_byte(reply);reads=reads+1;
   end else begin
    reject_byte=phase==1&&{hi,lo}==16'h8000;
    receive_byte(value,!reject_byte);
    if(!reject_byte) begin
     if(writes<252) expected=golden;
     else if(writes==252) expected=24'h300020;
     else if(writes<4330) expected={16'h8000+fw_writes[15:0],firmware[fw_writes]};
     else begin
      tail=writes-4330;
      if(tail<7) expected={16'h3022+tail[15:0],8'h00};
      else case(tail)
       7: expected=24'h30297f;
       8: expected=24'h300000;
       9: expected=24'h302201;
       10: expected=24'h302208;
       11: expected=24'h302301;
       12: expected=24'h302203;
       default: $fatal(1,"unexpected extra AF write");
      endcase
     end
     if({hi,lo,value}!==expected)
      $fatal(1,"write %d got %h expected %h",writes,{hi,lo,value},expected);
     if(writes>=253&&writes<4330) fw_writes=fw_writes+1;
     if(writes==4338) mcu_running=1;
     if(writes==4340||writes==4341) ack_pending=2;
     if(writes==4342) begin focus_running=1;focus_commands=focus_commands+1;end
     writes=writes+1;if(writes<252)golden_addr=writes;
    end
   end
   @(posedge sda);
  end
 end
 initial begin
  #2000;@(negedge clk);reset=0;
  wait(done||error);#1;
  if(error||!success||!ready||!image_done||image_error||id!==16'h5640||
     fw_writes!=4077||writes!=4343||focus_commands!=1||status!==8'h10)
   $fatal(1,"AF success case failed: image=%b ready=%b err=%b code=%d fw=%d writes=%d",image_done,ready,error,ac,fw_writes,writes);
  $display("PASS AF: 252 image writes, 4077 exact firmware bytes, MCU start, busy polling and single focus status 0x10");
  repeat(30) @(posedge clk);
  @(negedge clk);reset=1;phase=1;writes=0;fw_writes=0;golden_addr=0;
  mcu_running=0;focus_running=0;ack_pending=0;fw_polls=0;focus_polls=0;focus_commands=0;
  repeat(10) @(negedge clk);reset=0;
  wait(error);#1;
  if(ac!=1||success||!image_done||image_error||busy)
   $fatal(1,"firmware NACK must flag AF error without resetting image initialization");
  $display("PASS AF NACK: AF error reported while image_done remains high");
  $finish;
 end
 initial begin #3000000000.0;$fatal(1,"AF simulation timeout");end
endmodule
