`timescale 1ns/1ps
module tb_sccb;
 reg clk=0,reset=1,start=0,read_enable=0;always #125 clk=~clk;
 reg[15:0] addr=16'h3008;reg[7:0] wd=8'h82;
 wire[7:0] rd;wire busy,done,nack,scl;tri1 sda;
 reg slave_low=0;
 assign sda=slave_low?1'b0:1'bz;
 sccb_master #(.CLK_FREQ_HZ(4000000),.SCL_FREQ_HZ(100000)) dut(
 .clk(clk),.reset(reset),.start(start),.read_enable(read_enable),.reg_addr(addr),
 .write_data(wd),.read_data(rd),.busy(busy),.done(done),.nack_error(nack),.scl(scl),.sda(sda));
 reg[7:0] b,hi,lo;integer writes=0,reads=0,i;
 task receive_byte;
 output[7:0] value;
 integer n;
 begin
  value=0;
  for(n=7;n>=0;n=n-1) begin @(posedge scl);value[n]=sda;end
  @(negedge scl);slave_low=1;
  @(posedge scl);@(negedge scl);slave_low=0;
 end
 endtask
 task wait_start;
 begin
  @(negedge sda);
  while(scl!==1'b1) @(negedge sda);
 end endtask
 initial begin
  wait(!reset);
  forever begin
   wait_start;receive_byte(b);
   if(b!==8'h78)$fatal(1,"SCCB device address %h",b);
   receive_byte(hi);receive_byte(lo);
   if({hi,lo}==16'h3008) begin
    receive_byte(b);if(b!==8'h82)$fatal(1,"SCCB write data");writes=writes+1;
   end else if({hi,lo}==16'h300a) begin
    wait_start;receive_byte(b);
    if(b!==8'h79)$fatal(1,"SCCB repeated start address");
    b=8'h56;
    for(i=7;i>=0;i=i-1) begin slave_low=!b[i];@(posedge scl);@(negedge scl);end
    slave_low=0;@(posedge scl);if(sda!==1'b1)$fatal(1,"missing read NACK");
    reads=reads+1;
   end else $fatal(1,"SCCB register address");
   @(posedge sda);
  end
 end
 task launch;
 begin @(negedge clk);start=1;@(negedge clk);start=0;wait(done);#1;
  if(nack)$fatal(1,"unexpected NACK");
 end endtask
 initial begin
  #2000;@(negedge clk);reset=0;launch;
  repeat(4)@(negedge clk);addr=16'h300a;read_enable=1;launch;
  if(rd!==8'h56||writes!=1||reads!=1)$fatal(1,"SCCB readback %h",rd);
  $display("PASS SCCB physical SDA/SCL: 16-bit write, repeated-start read, ACK/NACK");$finish;
 end
 initial begin #3000000;$fatal(1,"SCCB timeout");end
endmodule
