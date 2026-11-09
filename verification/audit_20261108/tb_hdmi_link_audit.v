`timescale 1ns/1ps
module tb_hdmi_link_audit;
reg sys_clk=0, reset_n=0;
wire [2:0] dp,dn;
wire cp,cn;
integer fd; reg capture=0;
hdmi_test_top dut(sys_clk,reset_n,dp,dn,cp,cn);
always #10 sys_clk=~sys_clk;
initial fd=$fopen("hdmi_link_stream.txt","w");
always @(posedge dut.pixel_clk) if(capture)
 $fdisplay(fd,"L %0t %b %b %b",$time,dut.u_dvi_tx.red_code,dut.u_dvi_tx.green_code,dut.u_dvi_tx.blue_code);
always @(posedge dut.serial_clk_5x or negedge dut.serial_clk_5x) begin
 #0.100;
 if(capture) begin
  if ((dp !== ~dn) || (cp !== ~cn)) $fatal(1,"Differential outputs not complementary");
  $fdisplay(fd,"S %0t %b %b %b %b",$time,dp[2],dp[1],dp[0],cp);
 end
end
initial begin
 #200; @(negedge sys_clk); #1; reset_n=1;
 wait(dut.pixel_reset===0);
 repeat(100) @(negedge dut.pixel_clk);
 #0.001;capture=1;
 repeat(1650*3) @(negedge dut.pixel_clk);
 #0.001;capture=0;$fclose(fd);
 $display("TOP_CAPTURE_DONE");$finish;
end
initial begin #200000;$fatal(1,"TOP_TIMEOUT");end
endmodule
