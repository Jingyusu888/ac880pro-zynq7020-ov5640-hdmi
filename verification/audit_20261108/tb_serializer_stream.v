`timescale 1ns/1ps
module tb_serializer_stream;
reg pc=0, fc=0, rst=1;
reg [9:0] d=0;
wire q;
integer fd,k;
serializer_10to1 dut(pc,fc,rst,d,q);
always #6.735 pc=~pc;
always #1.347 fc=~fc;
initial fd=$fopen("serializer_stream.txt","w");
always @(posedge pc) if (!rst) $fdisplay(fd,"L %0t %b",$time,d);
always @(posedge fc or negedge fc) begin
 #0.100;
 if (!rst) $fdisplay(fd,"S %0t %b",$time,q);
end
initial begin
 #200; @(negedge pc); #0.001; rst=0;
 for(k=0;k<80;k=k+1) begin
  @(negedge pc); #0.001;
  d=((k*173) ^ (k<<3) ^ 10'h2d3);
 end
 repeat(8) @(negedge pc);
 #1; $fclose(fd); $display("STIMULUS_DONE"); $finish;
end
initial begin #5000; $fatal(1,"TIMEOUT");end
endmodule
