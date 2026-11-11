`timescale 1ns / 1ps
`default_nettype wire

/*
 sega_bk.v

 The memory port of kg_bk_ram (mem_req held with mem_we / mem_addr / mem_din until a one clock
 mem_ack, mem_dout valid with it) onto the backup RAM port of fpgagen_sdram_top (the bk port of
 sdram.sv: bk_req toggles for a request, done when bk_ack equals it, bk_q the word read; the byte of
 the .sav file is the low byte of the word, as the 68000 keeps the save RAM).

 clk is MCLK; the sdram port runs on the SDRAM clock (twice MCLK, rising edges together): bk_ack and
 bk_q change on an SDRAM edge and are taken at the next MCLK edge (the FROM-TO of the ucf), bk_q in the
 same edge as bk_ack.
*/

module sega_bk (
	input  wire        clk,

	input  wire        mem_req,
	input  wire        mem_we,
	input  wire [14:0] mem_addr,
	input  wire [7:0]  mem_din,
	output reg         mem_ack = 1'b0,
	output reg  [7:0]  mem_dout = 8'd0,

	output reg         bk_req = 1'b0,
	input  wire        bk_ack,
	output reg         bk_we = 1'b0,
	output reg  [15:1] bk_a = 15'd0,
	output reg  [7:0]  bk_d = 8'd0,
	input  wire [15:0] bk_q
);

reg busy = 1'b0;

always @(posedge clk) begin
	mem_ack <= 1'b0;
	if (busy) begin
		if (bk_ack == bk_req) begin
			busy <= 1'b0;
			mem_ack <= 1'b1;
			mem_dout <= bk_q[7:0];
		end
	end
	else if (mem_req && !mem_ack) begin
		bk_a <= mem_addr;
		bk_we <= mem_we;
		bk_d <= mem_din;
		bk_req <= ~bk_req;
		busy <= 1'b1;
	end
end

endmodule
