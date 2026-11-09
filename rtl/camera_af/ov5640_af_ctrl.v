`timescale 1ns/1ps
// Single AF transaction owner. Sequence follows the pinned Espressif driver.
// af_success means firmware status 0x10, NOT a measurement of optical focus.
module ov5640_af_ctrl #(
 parameter CLK_FREQ_HZ=50000000,
 parameter FW_BYTES=4077,
 parameter BUS_TIMEOUT_MS=10,
 parameter FW_TIMEOUT_MS=2000,
 parameter FOCUS_TIMEOUT_MS=5000,
 parameter POLL_MS=5,
 parameter SETTLE_MS=200,
 parameter AUTO_START=1
)(
 input wire clk,reset,image_ready,focus_start,
 output wire [11:0] firmware_addr,input wire [7:0] firmware_data,
 output reg bus_reset,bus_start,bus_read,
 output reg [15:0] bus_addr,output reg [7:0] bus_write_data,
 input wire [7:0] bus_read_data,input wire bus_busy,bus_done,bus_nack_error,
 output reg af_ready,af_busy,af_done,af_success,af_error,
 output reg [2:0] error_code,output reg [7:0] fw_status
);
 localparam BUS_CYCLES=(CLK_FREQ_HZ/1000)*BUS_TIMEOUT_MS;
 localparam FW_CYCLES=(CLK_FREQ_HZ/1000)*FW_TIMEOUT_MS;
 localparam FOCUS_CYCLES=(CLK_FREQ_HZ/1000)*FOCUS_TIMEOUT_MS;
 localparam POLL_CYCLES=(CLK_FREQ_HZ/1000)*POLL_MS;
 localparam SETTLE_CYCLES=(CLK_FREQ_HZ/1000)*SETTLE_MS;
 localparam WAIT_IMAGE=0,ROM_WAIT=1,PLAN=2,REQUEST=3,BUS_WAIT=4,
            POLL_WAIT=5,SETTLE=6,READY=7,FAILED=8;
 reg [3:0] state;
 reg [3:0] step;
 reg [11:0] byte_index;
 reg [2:0] clear_index;
 reg [31:0] bus_count,phase_count,delay_count;
 reg focus_d;
 wire focus_edge=focus_start&&!focus_d;
 assign firmware_addr=byte_index;

 // Errors: 1 NACK, 2 bus timeout, 3 firmware not idle,
 //         4 command ACK timeout, 5 no focused status before deadline.
 task fail;
  input [2:0] code;
  begin
   af_error<=1;error_code<=code;af_busy<=0;af_done<=1;
   af_success<=0;state<=FAILED;
   if(code==2) bus_reset<=1;
  end
 endtask

 always @(posedge clk) begin
  if(reset) begin
   state<=WAIT_IMAGE;step<=0;byte_index<=0;clear_index<=0;
   bus_reset<=1;bus_start<=0;bus_read<=0;bus_addr<=0;bus_write_data<=0;
   bus_count<=0;phase_count<=0;delay_count<=0;focus_d<=0;
   af_ready<=0;af_busy<=0;af_done<=0;af_success<=0;af_error<=0;
   error_code<=0;fw_status<=0;
  end else begin
   bus_start<=0;af_done<=0;focus_d<=focus_start;
   if(step==5||step==8||step==11||step==12)
    phase_count<=phase_count+1'b1;
   else phase_count<=0;
   case(state)
    WAIT_IMAGE: if(image_ready) begin
     bus_reset<=0;af_busy<=1;step<=0;state<=ROM_WAIT;
    end
    // A full clock between index changes and PLAN accounts for synchronous ROM.
    ROM_WAIT: state<=PLAN;
    PLAN: begin
     bus_read<=0;bus_write_data<=0;bus_count<=0;
     case(step)
      0: begin bus_addr<=16'h3000;bus_write_data<=8'h20;end
      1: begin bus_addr<=16'h8000+{4'd0,byte_index};bus_write_data<=firmware_data;end
      2: begin bus_addr<=16'h3022+{13'd0,clear_index};bus_write_data<=0;end
      3: begin bus_addr<=16'h3029;bus_write_data<=8'h7f;end
      4: begin bus_addr<=16'h3000;bus_write_data<=0;end
      5: begin bus_addr<=16'h3029;bus_read<=1;end
      6: begin bus_addr<=16'h3022;bus_write_data<=8'h01;end
      7: begin bus_addr<=16'h3022;bus_write_data<=8'h08;end
      8: begin bus_addr<=16'h3023;bus_read<=1;end
      9: begin bus_addr<=16'h3023;bus_write_data<=8'h01;end
      10: begin bus_addr<=16'h3022;bus_write_data<=8'h03;end
      11: begin bus_addr<=16'h3023;bus_read<=1;end
      12: begin bus_addr<=16'h3029;bus_read<=1;end
      default: begin bus_addr<=0;bus_write_data<=0;end
     endcase
     state<=REQUEST;
    end
    REQUEST: begin
     if(!bus_busy) begin bus_start<=1;bus_count<=0;state<=BUS_WAIT;end
     else if(bus_count>=BUS_CYCLES-1) fail(2);
     else bus_count<=bus_count+1'b1;
    end
    BUS_WAIT: begin
     if(bus_done) begin
      bus_count<=0;delay_count<=0;state<=ROM_WAIT;
      if(bus_nack_error) fail(1);
      else case(step)
       0: step<=1;
       1: if(byte_index==FW_BYTES-1) begin step<=2;clear_index<=0;end
          else byte_index<=byte_index+1'b1;
       2: if(clear_index==6) step<=3;else clear_index<=clear_index+1'b1;
       3: step<=4;
       4: step<=5;
       5: begin
        fw_status<=bus_read_data;
        if(bus_read_data==8'h70) begin
         af_ready<=1;step<=6;
         if(AUTO_START) state<=SETTLE;
         else begin state<=READY;af_busy<=0;end
        end else if(phase_count>=FW_CYCLES-1) fail(3);
        else state<=POLL_WAIT;
       end
       6: step<=7;
       7: step<=8;
       8,11: begin
        if(bus_read_data==0) step<=step+1'b1;
        else if(phase_count>=FOCUS_CYCLES-1) fail(4);
        else state<=POLL_WAIT;
       end
       9: step<=10;
       10: step<=11;
       12: begin
        fw_status<=bus_read_data;
        if(bus_read_data==8'h10) begin
         af_success<=1;af_done<=1;af_busy<=0;state<=READY;
        end else if(phase_count>=FOCUS_CYCLES-1) fail(5);
        else state<=POLL_WAIT;
       end
       default: state<=FAILED;
      endcase
     end else if(bus_count>=BUS_CYCLES-1) fail(2);
     else bus_count<=bus_count+1'b1;
    end
    POLL_WAIT: if(delay_count>=POLL_CYCLES-1) begin delay_count<=0;state<=ROM_WAIT;end
               else delay_count<=delay_count+1'b1;
    SETTLE: if(delay_count>=SETTLE_CYCLES-1) begin delay_count<=0;state<=ROM_WAIT;end
            else delay_count<=delay_count+1'b1;
    READY: if(focus_edge) begin
     af_busy<=1;af_success<=0;af_error<=0;error_code<=0;step<=6;state<=ROM_WAIT;
    end
    FAILED: begin end // Diagnostic retained; no automatic retry loop.
    default: state<=WAIT_IMAGE;
   endcase
  end
 end
endmodule
