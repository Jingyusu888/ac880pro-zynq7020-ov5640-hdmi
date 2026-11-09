`timescale 1ns/1ps
module tb_reader;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg toggle=0;wire req,cr,fr,push;wire[127:0] data;
 reg cv=0;reg [27:0] base=28'hff0;reg full=0;
 wire[27:0] araddr;wire[7:0] arlen;wire av,rr,err;
 reg arready=0,rv=0,rl=0;reg[127:0] rd=0;
 integer cycle=0,left=0,nextdata=0,got=0,transactions=0;
 axi_display_reader #(.FRAME_BEATS(10)) dut(
 .clk(clk),.reset(reset),.ddr_ready(1'b1),.request_toggle(toggle),
 .config_request(req),.config_request_ready(1'b1),.config_valid(cv),
 .config_has_frame(1'b1),.config_base(base),.config_ready(cr),
 .fifo_reset(fr),.fifo_push(push),.fifo_full(full),.fifo_data(data),
 .araddr(araddr),.arlen(arlen),.arvalid(av),.arready(arready),
 .rdata(rd),.rresp(2'b00),.rlast(rl),.rvalid(rv),.rready(rr),.read_error(err));
 always @(posedge clk) begin
  if(reset) cv<=0;
  else begin
   if(req) cv<=1;
   if(cv&&cr) cv<=0;
   if(av&&arready) begin
    if(left!=0) $fatal(1,"multiple outstanding reads");
    if(araddr[11:0]+(arlen+1)*16>4096) $fatal(1,"reader cross4k");
    left=arlen+1;nextdata=(araddr-28'hff0)/16;transactions=transactions+1;
   end
   if(rv&&rr) begin left=left-1;nextdata=nextdata+1;end
   if(push) begin
    if(data!==got) $fatal(1,"reader payload got %d expected %d",data,got);
    got=got+1;
   end
  end
 end
 always @(negedge clk) begin
  cycle=cycle+1;arready=cycle%3!=0;full=cycle%7==0;
  rv=left>0&&cycle%4!=0;rd=nextdata;rl=left==1;
 end
 initial begin
  #100;@(negedge clk);reset=0;
  wait(got==10);#20;if(err||transactions!=2) $fatal(1,"reader final");
  $display("PASS reader 4KiB split, prefetch/backpressure, ordered data");$finish;
 end
 initial begin #100000;$fatal(1,"reader timeout");end
endmodule
