`timescale 1ns/1ps
// Independent-clock FIFO, registered FWFT output. Depth=2**ADDR_BITS.
// Gray pointers cross domains; output prefetch register adds one queue slot.
module stream_async_fifo #(parameter WIDTH=17, ADDR_BITS=10)(
 input wire reset, wr_clk, input wire [WIDTH-1:0] din,
 input wire wr_en, output reg full,
 input wire rd_clk, rd_en, output wire [WIDTH-1:0] dout,
 output wire empty
);
 localparam P=ADDR_BITS+1;
 (* ram_style="block" *) reg [WIDTH-1:0] mem[0:(1<<ADDR_BITS)-1];
 reg [P-1:0] wb,wg,rb,rg;
 (* ASYNC_REG="TRUE" *) reg [P-1:0] rg1,rg2,wg1,wg2;
 (* ASYNC_REG="TRUE" *) reg [2:0] wrs,rrs;
 reg [WIDTH-1:0] data_out;
 reg valid;
 wire [P-1:0] wn=wb+((wr_en&&!full&&!wrs[2])?1'b1:1'b0);
 wire [P-1:0] gn=(wn>>1)^wn;
 wire ram_empty=(rg==wg2);
 assign dout=data_out;
 assign empty=!valid || rrs[2];
 always @(posedge wr_clk or posedge reset)
   if(reset) wrs<=3'b111; else wrs<={wrs[1:0],1'b0};
 always @(posedge rd_clk or posedge reset)
   if(reset) rrs<=3'b111; else rrs<={rrs[1:0],1'b0};
 always @(posedge wr_clk or posedge wrs[2]) begin
   if(wrs[2]) begin wb<=0;wg<=0;rg1<=0;rg2<=0;full<=1; end
   else begin
     rg1<=rg;rg2<=rg1; wb<=wn;wg<=gn;
     full <= gn=={~rg2[P-1:P-2],rg2[P-3:0]};
   end
 end
 always @(posedge wr_clk)
   if(!wrs[2]&&wr_en&&!full) mem[wb[ADDR_BITS-1:0]]<=din;
 always @(posedge rd_clk or posedge rrs[2]) begin
   if(rrs[2]) begin rb<=0;rg<=0;wg1<=0;wg2<=0;valid<=0; end
   else begin
     wg1<=wg;wg2<=wg1;
     if(!valid||rd_en) begin
       valid<=!ram_empty;
       if(!ram_empty) begin rb<=rb+1'b1;rg<=((rb+1'b1)>>1)^(rb+1'b1);end
     end
   end
 end
 // Synchronous RAM read permits inference of true dual-port block RAM.
 always @(posedge rd_clk)
   if(!rrs[2]&&(!valid||rd_en)&&!ram_empty)
     data_out<=mem[rb[ADDR_BITS-1:0]];
endmodule
