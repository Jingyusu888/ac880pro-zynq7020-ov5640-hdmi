`timescale 1ns/1ps
// One outstanding INCR read burst. A new display request drains an accepted
// transaction before releasing the old buffer. Never withdraw ARVALID.
module axi_display_reader #(parameter FRAME_BEATS=38400)(
 input wire clk,reset,ddr_ready,request_toggle,
 output wire config_request,input wire config_request_ready,
 input wire config_valid,config_has_frame,input wire [27:0] config_base,
 output wire config_ready,
 output reg fifo_reset,output wire fifo_push,input wire fifo_full,
 output wire [127:0] fifo_data,
 output wire [27:0] araddr,output wire [7:0] arlen,
 output wire arvalid,input wire arready,
 input wire [127:0] rdata,input wire [1:0] rresp,
 input wire rlast,rvalid,output wire rready,
 output reg read_error
);
 localparam WAIT=0,FLUSH=1,REQ=2,CFG=3,PREP=4,AR=5,R=6;
 reg [2:0] state;
 (* ASYNC_REG="TRUE" *) reg [2:0] req_sync;
 reg seen,pending;
 reg [4:0] hold_count;
 reg [27:0] address;
 reg [31:0] remaining;
 reg [4:0] burst,received;
 wire event_req=req_sync[2]!=seen;
 wire aborting=pending||event_req;
 wire [12:0] boundary_bytes=13'd4096-{1'b0,address[11:0]};
 wire [8:0] boundary_beats=boundary_bytes[12:4];
 reg [4:0] next_burst;
 always @* begin
  next_burst=16;
  if(remaining<16) next_burst=remaining[4:0];
  if(boundary_beats<next_burst) next_burst=boundary_beats[4:0];
 end
 assign config_request=state==REQ&&ddr_ready;
 assign config_ready=state==CFG;
 assign araddr=address;
 assign arlen={3'b0,burst}-1'b1;
 assign arvalid=state==AR&&!reset;
 assign rready=state==R&&!reset&&(aborting||!fifo_full);
 assign fifo_push=state==R&&rvalid&&rready&&!aborting&&(rresp==0)&&!read_error;
 assign fifo_data=rdata;
 always @(posedge clk or posedge reset) begin
  if(reset) req_sync<=0;else req_sync<={req_sync[1:0],request_toggle};
 end
 always @(posedge clk or posedge reset) begin
  if(reset) begin state<=WAIT;seen<=0;pending<=1;hold_count<=0;
   address<=0;remaining<=0;burst<=1;received<=0;fifo_reset<=1;read_error<=0;end
  else begin
   if(event_req) begin pending<=1;seen<=req_sync[2];end
   case(state)
    WAIT: if(aborting&&ddr_ready) begin
      pending<=0;fifo_reset<=1;hold_count<=0;state<=FLUSH;end
    FLUSH: if(hold_count==15) begin state<=REQ;end
      else hold_count<=hold_count+1'b1;
    REQ: if(config_request&&config_request_ready) state<=CFG;
    CFG: if(config_valid) begin
      address<=config_base;remaining<=FRAME_BEATS;read_error<=0;
      fifo_reset<=0;hold_count<=0;
      if(config_has_frame) state<=PREP;else state<=WAIT;
    end
    PREP: if(aborting) state<=WAIT;
      else if(hold_count<15) hold_count<=hold_count+1'b1;
      else if(!fifo_full) begin burst<=next_burst;state<=AR;end
    AR: if(arready) begin received<=0;state<=R;end
    R: if(rvalid&&rready) begin
      if(rresp!=0 || rlast!=(received==burst-1'b1)) read_error<=1;
      received<=received+1'b1;
      if(rlast) begin
       if(aborting||read_error||rresp!=0||received!=burst-1'b1) state<=WAIT;
       else if(remaining==burst) state<=WAIT;
       else begin remaining<=remaining-burst;
        address<=address+{19'd0,burst,4'd0};state<=PREP;end
      end
    end
    default: state<=WAIT;
   endcase
  end
 end
endmodule
