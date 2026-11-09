`timescale 1ns/1ps
// A missing pixel invalidates the rest of the frame. Resume only at next SOF.
// No reset of a live FIFO; queued SOF markers allow the consumer to resync.
module camera_ingress(
 input wire pclk,reset,frame_start,pixel_valid,
 input wire [15:0] pixel_data,
 input wire ui_clk, pop,
 output wire [16:0] data,output wire empty,
 output reg overflow_seen
);
 reg pending,enabled,dropping;
 (* ASYNC_REG="TRUE" *) reg [2:0] reset_sync;
 always @(posedge pclk or posedge reset)
  if(reset) reset_sync<=3'b111;else reset_sync<={reset_sync[1:0],1'b0};
 wire local_reset=reset_sync[2];
 wire full;
 wire push=pixel_valid&&(enabled||frame_start)&&(!dropping||frame_start)&&!full;
 stream_async_fifo #(.WIDTH(17),.ADDR_BITS(11)) q(
 .reset(reset),.wr_clk(pclk),.din({pending||frame_start,pixel_data}),
 .wr_en(push),.full(full),.rd_clk(ui_clk),.rd_en(pop),.dout(data),.empty(empty));
 always @(posedge pclk or posedge local_reset) begin
  if(local_reset) begin pending<=0;enabled<=0;dropping<=0;overflow_seen<=0;end
  else begin
   if(frame_start) begin pending<=1;enabled<=1;dropping<=0;end
   if(push) pending<=0;
   if(pixel_valid&&(enabled||frame_start)&&(!dropping||frame_start)&&full) begin
    dropping<=1;pending<=0;overflow_seen<=1;
   end
  end
 end
endmodule
