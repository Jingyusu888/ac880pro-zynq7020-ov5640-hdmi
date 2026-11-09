`timescale 1ns/1ps
module tb_stream_fifo;
 reg wc=0,rc=0,reset=1,we=0,re=0;reg[16:0] din;
 wire full,empty;wire[16:0] dout;
 always #5 wc=~wc;always #7 rc=~rc;
 stream_async_fifo #(.WIDTH(17),.ADDR_BITS(4)) dut(reset,wc,din,we,full,rc,re,dout,empty);
 integer sent=0,got=0,cycles=0;
 always @(negedge wc) begin
  if(reset) begin we=0;din=0;end
  else begin we=sent<1000&&!full;din=sent;end
 end
 always @(posedge wc) if(!reset&&we&&!full) sent=sent+1;
 always @(negedge rc) begin
  cycles=cycles+1;
  re=!reset&&!empty&&(cycles%5!=0)&&(cycles>50);
 end
 always @(posedge rc) if(!reset&&re&&!empty) begin
  if(dout!==got) $fatal(1,"FIFO order expected %d got %d",got,dout);
  got=got+1;
  if(got==1000) begin $display("PASS FIFO 1000 asynchronous ordered transfers with full/backpressure");$finish;end
 end
 initial begin #100;reset=0;#100000;$fatal(1,"FIFO timeout");end
endmodule
