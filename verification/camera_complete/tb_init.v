`timescale 1ns/1ps
module tb_init;
 reg clk=0,reset=1;always #125 clk=~clk;
 tri1 sda;wire scl,rstn,pwdn,done,err;wire[2:0] ec;wire[15:0] id;
 reg slave_low=0;assign sda=slave_low?0:1'bz;
 ov5640_config #(.CLK_FREQ_HZ(4000000),.SCL_FREQ_HZ(100000),
 .RESET_HOLD_MS(0),.STARTUP_WAIT_MS(0),.SOFT_RESET_WAIT_MS(0),.WRITE_GAP_US(0)) dut(
 .clk(clk),.reset(reset),.camera_clk_ready(1'b1),.camera_rst_n(rstn),.camera_pwdn(pwdn),
 .camera_scl(scl),.camera_sda(sda),.init_done(done),.init_error(err),.error_code(ec),.chip_id(id));
 integer writes=0,reads=0,i;reg[7:0] dev,hi,lo,b;reg[7:0] golden_addr=0;wire[23:0] golden;
 ov5640_init_table_rgb reference_rom(.clk(clk),.addr(golden_addr),.q(golden));
 task receive_byte;output[7:0] value;integer n;
 begin value=0;
  for(n=7;n>=0;n=n-1)begin @(posedge scl);value[n]=sda;end
  @(negedge scl);slave_low=1;@(posedge scl);@(negedge scl);slave_low=0;
 end endtask
 task wait_start;begin @(negedge sda);while(scl!==1'b1)@(negedge sda);end endtask
 initial begin wait(!reset);
 forever begin
  wait_start;receive_byte(dev);if(dev!==8'h78)$fatal(1,"init device");
  receive_byte(hi);receive_byte(lo);
  if(reads<2)begin
   if({hi,lo}!==16'h300a+reads)$fatal(1,"init ID order");
   wait_start;receive_byte(dev);if(dev!==8'h79)$fatal(1,"init read address");
   b=(reads==0)?8'h56:8'h40;
   for(i=7;i>=0;i=i-1)begin slave_low=!b[i];@(posedge scl);@(negedge scl);end
   slave_low=0;@(posedge scl);if(sda!==1)$fatal(1,"init NACK");reads=reads+1;
  end else begin
   receive_byte(b);
   if({hi,lo,b}!==golden)$fatal(1,"config entry %d got %h expected %h",writes,{hi,lo,b},golden);
   writes=writes+1;golden_addr=writes;
  end
  @(posedge sda);
 end end
 initial begin #2000;@(negedge clk);reset=0;wait(done||err);#1;
  if(err||id!==16'h5640||writes!=252||reads!=2)$fatal(1,"init result %h %d %d %d",id,writes,reads,ec);
  $display("PASS initializer ID=5640 and 252 ordered register writes over real SCCB master");$finish;
 end
 initial begin #150000000;$fatal(1,"init timeout");end
endmodule
