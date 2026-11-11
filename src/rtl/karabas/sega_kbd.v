`timescale 1ns / 1ps
`default_nettype wire

/*
 sega_kbd.v

 The USB keyboard as two Genesis pads, as snes_kbd.v of karabas-go-core-snes: the 6 keys of the HID
 report (KB_DAT0..5 of kg_mcu, usage codes) to the bits of the kg_mcu joysticks (1 up, 2 down,
 3 left, 4 right, 5 start, 6 A, 7 B, 8 C, 9 X, 10 Y, 11 Z, 12 mode, 1 = pressed), ORed with them by
 the top. The keys:

   pad 1: arrows, Z = A, X = B, C = C, A = X, S = Y, D = Z, Enter = Start, Space = Mode
   pad 2: I J K L, U = A, O = B, P = C, 7 = X, 8 = Y, 9 = Z, M = Start, N = Mode
*/

module sega_kbd (
	input wire clk,
	input wire [7:0] kb_dat0,
	input wire [7:0] kb_dat1,
	input wire [7:0] kb_dat2,
	input wire [7:0] kb_dat3,
	input wire [7:0] kb_dat4,
	input wire [7:0] kb_dat5,
	output reg [12:0] kb_l = 13'd0,
	output reg [12:0] kb_r = 13'd0
);

// a key of the report as the bits of the pads ({pad 2, pad 1})
function [25:0] key;
	input [7:0] k;
	begin
		key = 26'd0;
		case (k)
		8'h52: key[1] = 1'b1;          // up
		8'h51: key[2] = 1'b1;          // down
		8'h50: key[3] = 1'b1;          // left
		8'h4F: key[4] = 1'b1;          // right
		8'h28: key[5] = 1'b1;          // Enter: Start
		8'h1D: key[6] = 1'b1;          // Z: A
		8'h1B: key[7] = 1'b1;          // X: B
		8'h06: key[8] = 1'b1;          // C: C
		8'h04: key[9] = 1'b1;          // A: X
		8'h16: key[10] = 1'b1;         // S: Y
		8'h07: key[11] = 1'b1;         // D: Z
		8'h2C: key[12] = 1'b1;         // Space: Mode
		8'h0C: key[13 + 1] = 1'b1;     // I: up
		8'h0E: key[13 + 2] = 1'b1;     // K: down
		8'h0D: key[13 + 3] = 1'b1;     // J: left
		8'h0F: key[13 + 4] = 1'b1;     // L: right
		8'h10: key[13 + 5] = 1'b1;     // M: Start
		8'h18: key[13 + 6] = 1'b1;     // U: A
		8'h12: key[13 + 7] = 1'b1;     // O: B
		8'h13: key[13 + 8] = 1'b1;     // P: C
		8'h24: key[13 + 9] = 1'b1;     // 7: X
		8'h25: key[13 + 10] = 1'b1;    // 8: Y
		8'h26: key[13 + 11] = 1'b1;    // 9: Z
		8'h11: key[13 + 12] = 1'b1;    // N: Mode
		default: ;
		endcase
	end
endfunction

wire [25:0] keys = key(kb_dat0) | key(kb_dat1) | key(kb_dat2) | key(kb_dat3) | key(kb_dat4) | key(kb_dat5);

always @(posedge clk) begin
	kb_l <= keys[12:0];
	kb_r <= keys[25:13];
end

endmodule
