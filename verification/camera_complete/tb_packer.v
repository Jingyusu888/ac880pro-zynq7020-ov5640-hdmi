`timescale 1ns/1ps
module tb_packer;
 reg clk=0,reset=1;always #5 clk=~clk;
 reg [15:0] pixel=0;reg sof=0,iv=0;wire ir;
 wire[127:0] data;wire[15:0] strb;wire os,ol,ov,err;reg ready=0;
 integer cycle=0,received=0,sent=0,k,lane;
 rgb565_packer #(.IMAGE_WIDTH(19),.IMAGE_HEIGHT(1)) dut(clk,reset,pixel,sof,iv,ir,data,strb,os,ol,ov,ready,err);
 always @(negedge clk) begin cycle=cycle+1;ready=cycle%4!=0;end
 always @(posedge clk) if(!reset&&ov&&ready) begin
  for(lane=0;lane<8;lane=lane+1) if(received*8+lane<19)
   if(data[lane*16+:16]!==received*8+lane+1) $fatal(1,"packer order");
  if(strb!==((received==2)?16'h003f:16'hffff)) $fatal(1,"packer strobe");
  if(os!==(received==0)||ol!==(received==2)) $fatal(1,"packer frame markers");
  received=received+1;
 end
 initial begin
  #100;@(negedge clk);reset=0;
  for(k=0;k<19;k=k+1) begin
   @(negedge clk);pixel=k+1;sof=k==0;iv=1;
   @(posedge clk);while(!ir) @(posedge clk);
   @(negedge clk);iv=0;
  end
  wait(received==3);#20;if(err) $fatal(1,"packer unexpected error");
  $display("PASS packer 19 pixels, partial tail, SOF/EOF, downstream stalls");$finish;
 end
 initial begin #100000;$fatal(1,"packer timeout");end
endmodule
