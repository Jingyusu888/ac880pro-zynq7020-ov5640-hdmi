from pathlib import Path
import sys
import re
R=Path(__file__).resolve().parents[2]
S=R/'cam_yolo.srcs/sources_1/new'
text=(S/'ddr_controller.v').read_bytes().decode('utf-8',errors='replace')
ports=re.findall(r'\b(input|output|inout)\s+(?:wire|reg)\s*(\[[^\]]+\])?\s*(\w+)',text.split(');',1)[0])
regouts={'s_axi_awready','s_axi_wready','s_axi_bvalid','s_axi_arready','s_axi_rvalid','s_axi_rlast','s_axi_rdata','ui_clk'}
model='`timescale 1ns/1ps\nmodule ddr_controller(\n'+',\n'.join(d+' '+('reg' if n in regouts else 'wire')+' '+w+' '+n for d,w,n in ports)+'\n);\n'
model+='''
initial ui_clk=0;always #5 ui_clk=~ui_clk;
assign ui_reset=sys_reset;
assign init_calib_complete=!sys_reset;
assign s_axi_bid=0;assign s_axi_bresp=0;assign s_axi_rid=0;assign s_axi_rresp=0;
reg [127:0] memory[0:196607];
integer cyc=0,wa=0,wl=0,ra=0,rl=0;
initial begin s_axi_awready=0;s_axi_wready=0;s_axi_bvalid=0;
 s_axi_arready=0;s_axi_rvalid=0;s_axi_rlast=0;s_axi_rdata=0;end
always @(posedge ui_clk) begin
 if(sys_reset) begin wl=0;rl=0;s_axi_bvalid<=0;end
 else begin
 if(s_axi_awvalid&&s_axi_awready) begin
  if(wl!=0) $fatal(1,"second write outstanding");
  if(s_axi_awsize!=4||s_axi_awburst!=1||s_axi_awaddr[11:0]+(s_axi_awlen+1)*16>4096)
   $fatal(1,"invalid write request");
  wa=s_axi_awaddr/16;wl=s_axi_awlen+1;
 end
 if(s_axi_wvalid&&s_axi_wready) begin
  if(wl<=0||s_axi_wlast!=(wl==1)) $fatal(1,"invalid write data");
  if(s_axi_wstrb!=16'hffff) $fatal(1,"unexpected partial frame");
  memory[wa]=s_axi_wdata;wa=wa+1;wl=wl-1;
  if(wl==0)s_axi_bvalid<=1;
 end
 if(s_axi_bvalid&&s_axi_bready)s_axi_bvalid<=0;
 if(s_axi_arvalid&&s_axi_arready) begin
  if(rl!=0)$fatal(1,"second read outstanding");
  ra=s_axi_araddr/16;rl=s_axi_arlen+1;
 end
 if(s_axi_rvalid&&s_axi_rready) begin ra=ra+1;rl=rl-1;end
 end
end
always @(negedge ui_clk) begin
 cyc=cyc+1;
 s_axi_awready=!sys_reset&&wl==0&&cyc%3!=0;
 s_axi_wready=!sys_reset&&wl>0&&cyc%5!=0;
 s_axi_arready=!sys_reset&&rl==0&&cyc%3!=0;
 // Hold payload and VALID during backpressure, as AXI requires.
 if(!s_axi_rvalid||s_axi_rready) begin
  s_axi_rvalid=!sys_reset&&rl>0&&cyc%4!=0;
  s_axi_rdata=memory[ra];s_axi_rlast=rl==1;
 end
end
endmodule

module BUFG(input wire I,output wire O);assign O=I;endmodule
module ODDR #(parameter DDR_CLK_EDGE="SAME_EDGE")(
 input wire C,CE,D1,D2,R,S,output wire Q);assign Q=C;endmodule
module ov5640_control(input wire sys_clk,sys_reset,output wire camera_xclk,
 output wire camera_rst_n,camera_pwdn,camera_scl,inout wire camera_sda,
 output wire init_done,init_error,output wire[2:0] error_code,output wire[15:0] chip_id);
 assign camera_xclk=sys_clk;assign camera_rst_n=!sys_reset;assign camera_pwdn=0;
 assign camera_scl=1;assign init_done=!sys_reset;assign init_error=0;
 assign error_code=0;assign chip_id=16'h5640;
endmodule
module video_clock_reset(input wire sys_clk,sys_reset,
 output reg pixel_clk=0,output wire serial_clk_5x,pixel_reset);
 always #6.737 pixel_clk=~pixel_clk;
 assign serial_clk_5x=pixel_clk;assign pixel_reset=sys_reset;
endmodule
module dvi_tx(input wire pixel_clk,serial_clk_5x,pixel_reset,
 input wire[7:0] red,green,blue,input wire hsync,vsync,de,
 output wire[2:0] tmds_data_p,tmds_data_n,output wire tmds_clk_p,tmds_clk_n);
 assign tmds_data_p=0;assign tmds_data_n=7;assign tmds_clk_p=pixel_clk;assign tmds_clk_n=!pixel_clk;
endmodule

module tb_pipeline;
 reg sys_clk=0,reset_n=0,pclk=0,vs=0,href=0;reg[7:0] camdata=0;
 always #10 sys_clk=~sys_clk;always #12 pclk=~pclk;
 camera_hdmi_top dut(.sys_clk(sys_clk),.reset_n(reset_n),.camera_pclk(pclk),
 .camera_vsync(vs),.camera_href(href),.camera_data(camdata),.camera_sda());
 integer f,row,col,count=0,complete=0;reg[15:0] pix;
 reg prev_window=0;reg[15:0] frame_pattern=0,expected;
 // Sample the registered RGB one pixel later than the timing generator.
 reg window_d=0;integer index_d=0;
 always @(posedge dut.pixel_clk) begin
  if(!reset_n) begin window_d<=0;index_d<=0;end
  else begin
   window_d<=dut.window;
   if(dut.window) index_d<=(dut.y-120)*640+dut.x-320;
   if(window_d&&dut.manager.current_display_valid&&!dut.display_bad) begin
    if(index_d==0) begin
     frame_pattern={dut.red[7:3],dut.green[7:2],dut.blue[7:3]};count=0;
    end
    expected=index_d ^ frame_pattern;
    if({dut.red[7:3],dut.green[7:2],dut.blue[7:3]}!==expected)
     $fatal(1,"display mismatch at pixel %d got %h expected %h",index_d,
       {dut.red[7:3],dut.green[7:2],dut.blue[7:3]},expected);
    count=count+1;
    if(index_d==307199) begin
     if(count!=307200)$fatal(1,"incomplete display count");
     complete=complete+1;
     $display("Complete coherent display frame %d at %t",complete,$time);
     if(complete==3) begin
      if(dut.frames_good<2)$fatal(1,"no capture progress");
      $display("PASS complete DVP/FIFO/packer/AXI/frame-manager/reader/display pipeline: 921600 pixels");$finish;
     end
    end
   end
  end
 end
 task tick;begin @(negedge pclk);end endtask
 initial begin
  #1000;reset_n=1;
  for(f=0;f<12;f=f+1) begin
   tick;vs=1;href=0;repeat(100)tick;
   vs=0;repeat(32)tick;
   for(row=0;row<480;row=row+1) begin
    for(col=0;col<640;col=col+1) begin
     pix=(row*640+col)^(f*16'h8421);
     href=1;camdata=pix[15:8];tick;
     camdata=pix[7:0];tick;
    end
    href=0;repeat(64)tick;
   end
   repeat(1000)tick;
  end
 end
 initial begin #200000000;$fatal(1,"pipeline timeout");end
endmodule
'''
if '--faults' in sys.argv:
 model=model.replace('wl>0&&cyc%5!=0;', 'wl>0&&cyc%5!=0&&!(cyc>=300000&&cyc<340000);')
 model=model.replace('pix=(row*640+col)', 'if(!(f==2&&row==200&&col==300)) begin\n     pix=(row*640+col)')
 model=model.replace('camdata=pix[7:0];tick;', 'camdata=pix[7:0];tick;\n     end')
 model=model.replace('if(complete==3) begin', 'if(complete==3) begin\n      if(!dut.overflow_seen||dut.frames_bad<1)$fatal(1,"fault recovery not exercised");')
 model=model.replace('PASS complete DVP', 'PASS automatic overflow/truncated-frame recovery AND complete DVP')
Path(__file__).with_name('tb_pipeline.v').write_text(model,encoding='utf-8')
