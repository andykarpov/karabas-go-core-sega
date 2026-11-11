`timescale 1ns / 1ps
`default_nettype wire

/*
 sdram_model.v - a zero-delay model of the 16 bit SDRAM (4 banks x 8192 rows x 512 columns = 32 MB)
 for the verilator simulation, as far as fpgagen's sdram.sv uses it: LOAD MODE (CAS latency 2 / 3,
 burst length 1 / 2 / 4 / 8, sequential), ACTIVE, READ / WRITE with or without auto precharge,
 PRECHARGE, AUTO REFRESH, DQM with the latencies of the chip.

 Timing in edges of clk (the clock of the controller; the real chip runs on a phase shifted copy,
 which the capture points of the controller allow for): a command that the controller sets at edge
 e is "registered" by the chip at edge e+1 (sampled here at the next posedge, before the controller
 changes it). A READ registered at r gives the words that the controller samples at r+CL, r+CL+1,
 ...: word n is driven here (non-blocking) at edge r+CL-1+n, so the controller's input register sees
 it one edge later, like the real output after tAC. DQM registered at m masks the read word that
 the controller samples at m+2 (read DQM latency 2) and the write word of edge m (latency 0).

 Errors (READ / WRITE to a bank without an open row, ACTIVE on an open bank) are counted in
 `errors` and printed.
*/

module sdram_model (
	input  wire        clk,
	inout  wire [15:0] dq,
	input  wire [12:0] a,
	input  wire [1:0]  ba,
	input  wire        cs_n,
	input  wire        ras_n,
	input  wire        cas_n,
	input  wire        we_n,
	input  wire        dqml,
	input  wire        dqmh,
	output reg  [31:0] errors = 0
);

reg [15:0] mem [0:(1 << 24) - 1];

integer i;
initial for (i = 0; i < (1 << 24); i = i + 1) mem[i] = 16'h0000;

reg [2:0] cl = 3'd3;
reg [3:0] bl = 4'd2;

reg [12:0] row [0:3];
reg [3:0]  open = 4'b0000;

// read pipeline: an entry in slot j is driven j edges from now (slot 0 is driven at this edge)
localparam PIPE = 12;
reg [PIPE-1:0] rd_v = 0;
reg [23:0]     rd_a [0:PIPE-1];
reg [1:0]      dqm_r = 2'b11;  // DQM registered at the previous edge

// write burst: the words after the first
reg [8:0]  w_col;
reg [3:0]  w_n = 0, w_len = 0;
reg [1:0]  w_ba;
reg [12:0] w_row;

reg [15:0] dq_out;
reg        dq_oe = 1'b0;
assign dq = dq_oe ? dq_out : 16'bzzzzzzzzzzzzzzzz;

wire [3:0] cmd = { cs_n, ras_n, cas_n, we_n };
localparam CMD_ACTIVE = 4'b0011, CMD_READ = 4'b0101, CMD_WRITE = 4'b0100,
           CMD_PRECHARGE = 4'b0010, CMD_MODE = 4'b0000;

// the column of burst word n (sequential, wraps inside the burst)
function [8:0] bcol;
	input [8:0] col;
	input [3:0] n;
	input [3:0] len;
	begin
		case (len)
			4'd1: bcol = col;
			4'd2: bcol = { col[8:1], col[0] ^ n[0] };
			4'd4: bcol = { col[8:2], col[1:0] + n[1:0] };
			default: bcol = { col[8:3], col[2:0] + n[2:0] };
		endcase
	end
endfunction

integer k;
reg [23:0] wa;
always @(posedge clk) begin
	// drive the read word of slot 0; DQM registered at the previous edge masks it
	dq_oe <= rd_v[0] & ~(&dqm_r);
	if (rd_v[0]) dq_out <= mem[rd_a[0]];
	for (k = 0; k < PIPE - 1; k = k + 1) begin
		rd_v[k] <= rd_v[k + 1];
		rd_a[k] <= rd_a[k + 1];
	end
	rd_v[PIPE - 1] <= 1'b0;
	dqm_r <= { dqmh, dqml };

	// the following words of a write burst
	if (w_n != 0) begin
		wa = { w_ba, w_row, bcol(w_col, w_n, w_len) };
		if (!dqml) mem[wa][7:0]  <= dq[7:0];
		if (!dqmh) mem[wa][15:8] <= dq[15:8];
		w_n <= (w_n + 4'd1 < w_len) ? w_n + 4'd1 : 4'd0;
	end

	case (cmd)
		CMD_MODE: begin
			cl <= a[6:4];
			case (a[2:0])
				3'b000: bl <= 4'd1;
				3'b001: bl <= 4'd2;
				3'b010: bl <= 4'd4;
				default: bl <= 4'd8;
			endcase
		end
		CMD_ACTIVE: begin
			if (open[ba]) begin
				errors <= errors + 1;
				$display("sdram_model: ACTIVE on open bank %0d", ba);
			end
			row[ba] <= a;
			open[ba] <= 1'b1;
		end
		CMD_PRECHARGE: begin
			if (a[10]) open <= 4'b0000; else open[ba] <= 1'b0;
		end
		CMD_READ: begin
			if (!open[ba]) begin
				errors <= errors + 1;
				$display("sdram_model: READ on closed bank %0d", ba);
			end
			// this edge is r: word n is driven at r + cl - 1 + n, i.e. from slot cl - 2 + n after the
			// shift of this edge (slot j of the next edge = j + 1 edges from now)
			for (k = 0; k < 8; k = k + 1)
				if (k < bl) begin
					rd_v[cl - 2 + k] <= 1'b1;
					rd_a[cl - 2 + k] <= { ba, row[ba], bcol(a[8:0], k[3:0], bl) };
				end
			if (a[10]) open[ba] <= 1'b0;
		end
		CMD_WRITE: begin
			if (!open[ba]) begin
				errors <= errors + 1;
				$display("sdram_model: WRITE on closed bank %0d", ba);
			end
			wa = { ba, row[ba], a[8:0] };
			if (!dqml) mem[wa][7:0]  <= dq[7:0];
			if (!dqmh) mem[wa][15:8] <= dq[15:8];
			w_col <= a[8:0]; w_ba <= ba; w_row <= row[ba]; w_len <= bl;
			w_n <= (bl > 1) ? 4'd1 : 4'd0;
			if (a[10]) open[ba] <= 1'b0;
		end
		default: ;
	endcase
end

endmodule
