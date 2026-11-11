`timescale 1ns / 1ps
`default_nettype wire

/*
 sega_loader.v

 The cartridge file from the file loader of kg_mcu (FILE_CMDS 1, FILE_WR_EACH 1: one file_wr per
 byte with its offset while file_active) into the boot interface of fpgagen, the protocol of the MiST
 top (Guest_Toplevel.vhd):
   - a new file (file_active rises): ext_reset_n low for a few clocks (it resets the boot FSM of
     fpgagen to BOOT_READ_1 with ext_data_req high; the CPU stays in reset through the boot FSM
     until BOOT_DONE), ext_bootdone low;
   - the bytes in pairs (even offset = the high byte, as the 68000 reads the cartridge) into a FIFO,
     each word to ext_data with a one clock ext_data_ack while ext_data_req is high (the FSM drops
     the request on the ack and raises it again when the word is in the SDRAM);
   - the end (file_active falls): an odd last byte is padded with FF, and when the FIFO is empty
     ext_bootdone goes high and stays (the FSM then clears the 68K RAM and starts the CPU).
 Before the first file ext_bootdone is high, as on MiST (the boot ROM of fpgagen runs with no cart).

 The FIFO evens out the bursts of the mcu link against the SDRAM writes (~12 MCLK per word through
 the boot FSM; the link brings a word every ~27 MCLK at 32 MHz SPI): 16 words.

 The save RAM of the header (1B0 "RA", 1B4..1B7 its start, 1B8..1BB its end, as 68000 addresses of
 its bytes, every other one): sav_sectors = the sectors of 512 bytes of the .sav file (its bytes in
 the order of the addresses), 0 without "RA"; at most 64 (32 KB, the save RAM window of fpgagen).

 The region of the header (bytes 1F0..1F2): the letters J / U / E, or one hex digit of the newer
 form (bit 0 Japan, bit 2 USA, bit 3 Europe); hdr_region = { e, u, j } of the last file. A copier
 header (.smd, 512 bytes) is not handled: plain .bin / .gen / .md files.
*/

module sega_loader (
	input  wire        clk,

	input  wire        file_active,
	input  wire        file_wr,
	input  wire [31:0] file_addr,
	input  wire [7:0]  file_data,

	output reg         ext_reset_n = 1'b1,
	output reg         ext_bootdone = 1'b1,
	output reg  [15:0] ext_data = 16'd0,
	output reg         ext_data_ack = 1'b0,
	input  wire        ext_data_req,

	output reg  [2:0]  hdr_region = 3'b010,   // { EU, US, JP } (US until a file says otherwise)
	output reg  [6:0]  sav_sectors = 7'd0,    // the save RAM of the header in sectors (0: none)
	output wire        loading
);

assign loading = !ext_bootdone;

reg active_d = 1'b0;
reg [3:0] rst_cnt = 4'd0;
reg [7:0] hi = 8'd0;
reg hi_valid = 1'b0;
reg ending = 1'b0;

// FIFO of 16 words
reg [15:0] fifo [0:15];
reg [4:0] wp = 5'd0, rp = 5'd0;
wire empty = wp == rp;
reg ack_wait = 1'b0;

reg push;
reg [15:0] push_d;

// header save RAM: 1B0..1BB
reg [7:0] h_r = 8'd0, h_a = 8'd0;
reg [31:0] h_start = 32'd0, h_end = 32'd0;
wire [31:0] h_len = ((h_end - h_start) >> 1) + 32'd1;        // its bytes (every other address)
wire [31:0] h_sec = (h_len + 32'd511) >> 9;

// header region
reg [2:0] reg_new = 3'b000;
function [2:0] region_of;   // { e, u, j } of one header byte
	input [7:0] c;
	reg [7:0] v;
	begin
		v = (c >= "A") ? c - 8'd55 : c - 8'd48;   // the value of a hex digit
		case (c)
			"J": region_of = 3'b001;
			"U": region_of = 3'b010;
			"E": region_of = 3'b100;
			default:
				if ((c >= "0" && c <= "9") || (c >= "A" && c <= "F")) region_of = { v[3], v[2], v[0] };
				else                                                region_of = 3'b000;
		endcase
	end
endfunction

always @(posedge clk) begin
	active_d <= file_active;
	push = 1'b0;
	push_d = 16'd0;
	ext_data_ack <= 1'b0;

	if (file_active && !active_d) begin
		// a new file
		rst_cnt <= 4'd8;
		ext_bootdone <= 1'b0;
		wp <= 5'd0;
		rp <= 5'd0;
		hi_valid <= 1'b0;
		ending <= 1'b0;
		ack_wait <= 1'b0;
		reg_new <= 3'b000;
		h_r <= 8'd0;
		h_a <= 8'd0;
	end
	else begin
		if (rst_cnt != 4'd0) rst_cnt <= rst_cnt - 4'd1;
		ext_reset_n <= rst_cnt == 4'd0;

		if (file_active && file_wr) begin
			if (!file_addr[0]) begin
				hi <= file_data;
				hi_valid <= 1'b1;
			end
			else begin
				push = 1'b1;
				push_d = { hi, file_data };
				hi_valid <= 1'b0;
			end
			case (file_addr)
				32'h1B0: h_r <= file_data;
				32'h1B1: h_a <= file_data;
				32'h1B4: h_start[31:24] <= file_data;
				32'h1B5: h_start[23:16] <= file_data;
				32'h1B6: h_start[15:8] <= file_data;
				32'h1B7: h_start[7:0] <= file_data;
				32'h1B8: h_end[31:24] <= file_data;
				32'h1B9: h_end[23:16] <= file_data;
				32'h1BA: h_end[15:8] <= file_data;
				32'h1BB: h_end[7:0] <= file_data;
				default: ;
			endcase
			if (file_addr[31:2] == 30'h7C)     // 1F0..1F3
				if (file_addr[1:0] != 2'd3)
					reg_new <= reg_new | region_of(file_data);
		end

		if (!file_active && active_d && !ext_bootdone) begin
			ending <= 1'b1;
			if (hi_valid) begin
				push = 1'b1;
				push_d = { hi, 8'hFF };
				hi_valid <= 1'b0;
			end
			hdr_region <= reg_new == 3'b000 ? 3'b010 : reg_new;
			if (h_r != "R" || h_a != "A" || h_end < h_start)
				sav_sectors <= 7'd0;
			else
				sav_sectors <= h_sec > 32'd64 ? 7'd64 : h_sec[6:0];
		end

		if (push) begin
			fifo[wp[3:0]] <= push_d;
			wp <= wp + 5'd1;
		end

		// to the boot FSM: the request drops on the ack, wait for it to come back
		if (ack_wait)
			ack_wait <= 1'b0;
		else if (ext_reset_n && ext_data_req && !empty && !ext_data_ack) begin
			ext_data <= fifo[rp[3:0]];
			ext_data_ack <= 1'b1;
			rp <= rp + 5'd1;
			ack_wait <= 1'b1;
		end

		if (ending && empty && !push && !ext_data_ack && !ack_wait) begin
			ext_bootdone <= 1'b1;
			ending <= 1'b0;
		end
	end
end

endmodule
