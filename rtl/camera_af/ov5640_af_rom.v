`timescale 1ns/1ps
// Byte-addressed firmware at sensor address 0x8000; see third_party/ov5640_af.
module ov5640_af_rom #(parameter INIT_FILE="ov5640_af_firmware.mem")(
 input wire clk,input wire [11:0] addr,output reg [7:0] data
);
 (* rom_style="block" *) reg [7:0] rom[0:4095];
 initial $readmemh(INIT_FILE,rom);
 always @(posedge clk) data<=rom[addr];
endmodule
