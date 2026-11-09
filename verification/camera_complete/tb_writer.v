`timescale 1ns/1ps
module tb_writer;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg start=0,abort_frame=0;wire start_ready,done,error,busy;
 reg [127:0] din;reg[15:0] strb=16'hffff;reg sof=0,eof=0,iv=0;wire ir;
 wire[27:0] awaddr;wire[7:0] awlen;wire awvalid,wvalid,wlast,bready;
 wire[127:0] wdata;wire[15:0] wstrb;
 reg awready=0,wready=0,bvalid=0;reg[1:0] bresp=0;
 integer cycles=0,index=0,aw_count=0,beat_count=0,expected_len;
 reg[27:0] expected_addr=28'hff0;
 axi_frame_writer #(.IMAGE_WIDTH(80),.IMAGE_HEIGHT(1)) dut(
 .clk(clk),.reset(reset),.ddr_ready(1'b1),.abort_frame(abort_frame),
 .frame_start_valid(start),.frame_start_ready(start_ready),.frame_base_addr(28'hff0),
 .busy(busy),.frame_done(done),.frame_error(error),
 .in_data(din),.in_strb(strb),.in_frame_start(sof),.in_frame_last(eof),.in_valid(iv),.in_ready(ir),
 .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awvalid(awvalid),.m_axi_awready(awready),
 .m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(wready),
 .m_axi_bid(4'd0),.m_axi_bresp(bresp),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
 always @(negedge clk) begin
  cycles=cycles+1;awready=cycles%3!=0;wready=cycles%4!=0;
 end
 always @(posedge clk) if(!reset) begin
  if(awvalid&&awready) begin
   if(awaddr!==expected_addr) $fatal(1,"AW address");
   expected_len=(aw_count==0)?1:9;
   if(awlen!==expected_len-1) $fatal(1,"AWLEN boundary split");
   if(({1'b0,awaddr[11:0]}+(awlen+1)*16)>4096) $fatal(1,"cross 4K");
   expected_addr=expected_addr+(awlen+1)*16;aw_count=aw_count+1;beat_count=0;
  end
  if(wvalid&&wready) begin
   if(wdata!==index || wstrb!==16'hffff) $fatal(1,"write payload");
   if(wlast!==(beat_count==expected_len-1)) $fatal(1,"WLAST");
   index=index+1;beat_count=beat_count+1;
   if(wlast) bvalid<=1;
  end
  if(bvalid&&bready) bvalid<=0;
 end
 task send;
 input integer n;
 begin
  @(negedge clk);din=n;sof=n==0;eof=n==9;iv=1;
  @(posedge clk);while(!ir) @(posedge clk);
  @(negedge clk);iv=0;
 end endtask
 integer k;
 initial begin
  din=0;#100;@(negedge clk);reset=0;start=1;
  @(posedge clk);while(!start_ready) @(posedge clk);
  @(negedge clk);start=0;
  for(k=0;k<10;k=k+1) send(k);
  wait(done);#1;if(error||index!=10||aw_count!=2) $fatal(1,"writer final");
  $display("PASS writer data/backpressure/4KiB split/response");$finish;
 end
 initial begin #100000;$fatal(1,"writer timeout");end
endmodule
