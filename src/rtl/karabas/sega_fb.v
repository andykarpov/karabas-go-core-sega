`timescale 1ns / 1ps
`default_nettype wire

/*
 sega_fb.v

 The picture of the VDP through a frame buffer in the SRAM of the board, out as 1024 x 768 at
 60 Hz (VESA, 65 MHz): every source line 3 output lines, the source width (320 in H40, 256 in H32)
 scaled to 960 output pixels (a DDA: the source pixel advances W / 960 per output pixel, 3 in H40,
 3.75 in H32), the picture in the middle (32 pixels left and right, (768 - 3 h) / 2 lines above).
 The output does not follow the 50 / 59.9 Hz of the VDP: three buffers, the reader shows the last
 complete frame (repeated or skipped as the rates differ), so no frame is torn.

 Write side (clk = MCLK of fpgagen): the pixels the VDP gives on CE_PIX outside HBL / VBL, RGB 4:4:4,
 one SRAM word each at { buffer (2 bits), line (9), pixel (9) }. A line ends on HBL, a frame on VBL;
 a frame that had lines becomes the last complete one with its width and height, and the next
 buffer is the one that is neither that nor the one the reader shows.

 SRAM (two 2M x 8 chips = 2M x 16, 10 ns, asynchronous) on clk (54.17 MHz, 18.5 ns): a read holds
 the address two clocks (37 ns) and takes MD at the second edge, back to back every two clocks; a
 write is four clocks: /OE off with the address, MD driven and /WE low, /WE high, MD released. A
 pixel comes at most every 8 clocks (H40), so the writes take half the time at most and the line
 reads the rest: 320 words in less than 20 us.

 Read side (clk_65): the VESA timing 1344 x 806 (1024 + 24 + 136 + 160, 768 + 3 + 6 + 29); at the
 start of every frame the reader takes the last complete buffer with its size. A source line is
 read from the SRAM into a line buffer (block RAM, two lines, the two clocks) while the line before
 is shown: line 0 three output lines before the picture, line n+1 at the first output line of n.
 The requests cross to clk with a toggle (the line, the buffers held stable meanwhile); the buffer
 numbers and sizes cross both ways as two agreeing samples (they change once a frame).

 hs / vs / de are positive (the top inverts the syncs), rgb is 8:8:8 (4 bits doubled).
*/

module sega_fb (
	input  wire        clk,
	input  wire [3:0]  r,
	input  wire [3:0]  g,
	input  wire [3:0]  b,
	input  wire        hbl,
	input  wire        vbl,
	input  wire        ce_pix,

	output reg  [20:0] MA = 21'd0,
	inout  wire [15:0] MD,
	output reg  [1:0]  MWR_N = 2'b11,
	output reg  [1:0]  MRD_N = 2'b11,

	input  wire        clk_65,
	output reg  [23:0] rgb = 24'd0,
	output reg         hs = 1'b0,
	output reg         vs = 1'b0,
	output reg         de = 1'b0
);

// ================================================================== write side (clk)

reg hbl_d = 1'b1, vbl_d = 1'b1;
reg [8:0] wx = 9'd0, wy = 9'd0, wwidth = 9'd0;
reg [1:0] wbuf = 2'd0;
reg [1:0] last = 2'd0;
reg       have = 1'b0;                 // a complete frame exists
reg [8:0] last_w = 9'd320, last_h = 9'd224;

// the reader's buffer, from clk_65 (two agreeing samples)
reg [1:0] rd_s1 = 2'd0, rd_s2 = 2'd0, rd_cur = 2'd0;
wire [1:0] rbuf_65;

// line requests from clk_65 (the toggle and the line / buffers it asks for)
wire       req_t_65;
wire [8:0] req_line_65;
wire       req_lbuf_65;
wire [1:0] req_fbuf_65;

// pending pixel
reg        pw = 1'b0;
reg [19:0] pw_addr = 20'd0;
reg [11:0] pw_data = 12'd0;

// the SRAM controller (below)
localparam S_IDLE = 3'd0, S_W1 = 3'd1, S_W2 = 3'd2, S_W3 = 3'd3, S_R1 = 3'd4;
reg [2:0]  st = S_IDLE;
reg        md_oe = 1'b0;
reg [15:0] md_out = 16'd0;
assign MD = md_oe ? md_out : 16'bzzzzzzzzzzzzzzzz;
wire sram_wr_take = st == S_IDLE && pw;

always @(posedge clk) begin
	rd_s1 <= rbuf_65;
	rd_s2 <= rd_s1;
	if (rd_s1 == rd_s2) rd_cur <= rd_s2;

	if (sram_wr_take) pw <= 1'b0;
	hbl_d <= hbl;
	vbl_d <= vbl;
	if (ce_pix && !hbl && !vbl) begin
		if (wx < 9'd320 && wy < 9'd240) begin
			pw <= 1'b1;
			pw_addr <= { wbuf, wy, wx };
			pw_data <= { r, g, b };
		end
		wx <= wx + 9'd1;
	end
	if (hbl && !hbl_d) begin
		if (wx != 9'd0) begin
			if (wy != 9'd511) wy <= wy + 9'd1;
			if (wx > wwidth) wwidth <= wx > 9'd320 ? 9'd320 : wx;
		end
		wx <= 9'd0;
	end
	if (vbl && !vbl_d) begin
		if (wy != 9'd0) begin
			last <= wbuf;
			have <= 1'b1;
			last_w <= wwidth;
			last_h <= wy > 9'd240 ? 9'd240 : wy;
			// the next buffer: not the one just completed, not the one the reader shows
			if (wbuf != rd_cur)
				wbuf <= 2'd3 - wbuf - rd_cur;
			else
				wbuf <= wbuf == 2'd2 ? 2'd0 : wbuf + 2'd1;
		end
		wx <= 9'd0;
		wy <= 9'd0;
		wwidth <= 9'd0;
	end
end

// ------------------------------------------------------------------ line requests, SRAM

reg [2:0]  req_s = 3'd0;
reg        job = 1'b0;
reg [8:0]  job_line = 9'd0, job_x = 9'd0;
reg        job_lbuf = 1'b0;
reg [1:0]  job_fbuf = 2'd0;


// line buffer write port
reg        lb_we = 1'b0;
reg [9:0]  lb_wa = 10'd0;
reg [11:0] lb_wd = 12'd0;
reg [8:0]  rd_x = 9'd0;         // the pixel of the read in progress
reg        rd_lbuf = 1'b0;
reg        lb_rd_pend = 1'b0;
reg [8:0]  rd_x_d = 9'd0;
reg        rd_lbuf_d = 1'b0;

always @(posedge clk) begin
	req_s <= { req_s[1:0], req_t_65 };
	if (req_s[2] != req_s[1]) begin
		job <= 1'b1;
		job_line <= req_line_65;
		job_lbuf <= req_lbuf_65;
		job_fbuf <= req_fbuf_65;
		job_x <= 9'd0;
	end

	lb_we <= 1'b0;
	case (st)
	S_IDLE:
		if (pw) begin
			MRD_N <= 2'b11;
			MA <= { 1'b0, pw_addr };
			md_out <= { 4'd0, pw_data };
			st <= S_W1;
		end
		else if (job) begin
			MRD_N <= 2'b00;
			MA <= { 1'b0, job_fbuf, job_line, job_x };
			rd_x <= job_x;
			rd_lbuf <= job_lbuf;
			if (job_x == 9'd319) job <= 1'b0;
			job_x <= job_x + 9'd1;
			st <= S_R1;
		end
		else
			MRD_N <= 2'b11;
	S_W1: begin
		md_oe <= 1'b1;
		MWR_N <= 2'b00;
		st <= S_W2;
	end
	S_W2: begin
		MWR_N <= 2'b11;
		st <= S_W3;
	end
	S_W3: begin
		md_oe <= 1'b0;
		st <= S_IDLE;
	end
	S_R1: begin
		// the second clock of the read: MD is taken at the next edge (in S_IDLE's place below)
		st <= S_IDLE;
	end
	default: st <= S_IDLE;
	endcase

	// the read data: the address was set two edges ago (S_IDLE -> S_R1 -> here)
	if (st == S_R1) begin
		lb_rd_pend <= 1'b1;
	end
	else
		lb_rd_pend <= 1'b0;
	if (lb_rd_pend) begin
		lb_we <= 1'b1;
		lb_wa <= { rd_lbuf_d, rd_x_d };
		lb_wd <= MD[11:0];
	end
	rd_x_d <= rd_x;
	rd_lbuf_d <= rd_lbuf;
end

// ================================================================== line buffer

wire [11:0] lb_q;
reg  [9:0]  lb_ra = 10'd0;
kg_sdpram #(.DW(12), .AW(10)) line_buf (
	.clka(clk),
	.wea(lb_we),
	.addra(lb_wa),
	.dina(lb_wd),
	.clkb(clk_65),
	.enb(1'b1),
	.addrb(lb_ra),
	.doutb(lb_q)
);

// ================================================================== read side (clk_65)

localparam H_TOTAL = 11'd1344, H_SYNC0 = 11'd1048, H_SYNC1 = 11'd1184;
localparam V_TOTAL = 10'd806,  V_SYNC0 = 10'd771,  V_SYNC1 = 10'd777;
localparam X0 = 11'd32, XW = 11'd960;

reg [10:0] hc = 11'd0;
reg [9:0]  vc = 10'd0;

// the frame of the writer, two agreeing samples
wire [20:0] pub = { have, last, last_w, last_h };
reg  [20:0] pub_s1 = 21'd0, pub_s2 = 21'd0, pub_cur = 21'd0;
reg  [1:0]  rbuf = 2'd0;
reg         rhave = 1'b0;
reg  [8:0]  rw = 9'd320, rh = 9'd224;
reg  [9:0]  y0 = 10'd48;
assign rbuf_65 = rbuf;

// line requests
reg        req_t = 1'b0;
reg [8:0]  req_line = 9'd0;
reg        req_lbuf = 1'b0;
assign req_t_65 = req_t;
assign req_line_65 = req_line;
assign req_lbuf_65 = req_lbuf;
assign req_fbuf_65 = rbuf;

// vertical position in the picture
reg        in_img = 1'b0;
reg [8:0]  sy = 9'd0;
reg [1:0]  sub = 2'd0;

// horizontal DDA
reg [10:0] acc = 11'd0;        // < 960 + W: 11 bits
reg [8:0]  sx = 9'd0;

// pipeline: stage 1 = the line buffer address, stage 2 = its data
reg p1_de = 1'b0, p1_hs = 1'b0, p1_vs = 1'b0, p1_pic = 1'b0;
reg p2_de = 1'b0, p2_hs = 1'b0, p2_vs = 1'b0, p2_pic = 1'b0;

always @(posedge clk_65) begin
	pub_s1 <= pub;
	pub_s2 <= pub_s1;
	if (pub_s1 == pub_s2) pub_cur <= pub_s2;

	// counters
	if (hc == H_TOTAL - 11'd1) begin
		hc <= 11'd0;
		vc <= vc == V_TOTAL - 10'd1 ? 10'd0 : vc + 10'd1;
	end
	else
		hc <= hc + 11'd1;

	// the start of a frame: the last complete buffer
	if (hc == 11'd0 && vc == V_SYNC1) begin
		rhave <= pub_cur[20];
		rbuf  <= pub_cur[19:18];
		rw    <= pub_cur[17:9] == 9'd0 ? 9'd320 : pub_cur[17:9];
		rh    <= pub_cur[8:0] == 9'd0 ? 9'd224 : pub_cur[8:0];
		y0    <= (10'd768 - (pub_cur[8:0] == 9'd0 ? 10'd672 : { 1'b0, pub_cur[8:0] } * 10'd3)) >> 1;
	end

	// lines: at the end of the line before (hc = H_SYNC0, the picture of the line is out)
	if (hc == H_SYNC0) begin
		if (vc + 10'd3 == y0) begin
			// three lines ahead: source line 0
			req_line <= 9'd0;
			req_lbuf <= 1'b0;
			req_t <= ~req_t;
		end
		if (vc + 10'd1 == y0) begin
			// the next line is the first of the picture; line 1 into the other buffer
			in_img <= 1'b1;
			sy <= 9'd0;
			sub <= 2'd0;
			if (rh > 9'd1) begin
				req_line <= 9'd1;
				req_lbuf <= 1'b1;
				req_t <= ~req_t;
			end
		end
		else if (in_img) begin
			if (sub == 2'd2) begin
				sub <= 2'd0;
				if (sy + 9'd1 == rh)
					in_img <= 1'b0;
				else begin
					sy <= sy + 9'd1;
					if (sy + 9'd2 < rh) begin
						req_line <= sy + 9'd2;
						req_lbuf <= sy[0];       // = (sy + 2) & 1
						req_t <= ~req_t;
					end
				end
			end
			else
				sub <= sub + 2'd1;
		end
		if (vc == V_TOTAL - 10'd1)
			in_img <= 1'b0;
	end

	// stage 1: the address of the source pixel
	if (hc == X0 - 11'd1) begin
		acc <= 11'd0;
		sx <= 9'd0;
	end
	else if (hc >= X0 && hc < X0 + XW) begin
		if (acc + { 2'b0, rw } >= 11'd960) begin
			acc <= acc + { 2'b0, rw } - 11'd960;
			sx <= sx + 9'd1;
		end
		else
			acc <= acc + { 2'b0, rw };
	end
	lb_ra <= { sy[0], sx };
	p1_de <= hc < 11'd1024 && vc < 10'd768;
	p1_hs <= hc >= H_SYNC0 && hc < H_SYNC1;
	p1_vs <= vc >= V_SYNC0 && vc < V_SYNC1;
	p1_pic <= rhave && in_img && hc >= X0 && hc < X0 + XW;

	// stage 2: the pixel (lb_q is the data of lb_ra of the clock before)
	p2_de <= p1_de;
	p2_hs <= p1_hs;
	p2_vs <= p1_vs;
	p2_pic <= p1_pic;

	de <= p2_de;
	hs <= p2_hs;
	vs <= p2_vs;
	rgb <= p2_pic ? { lb_q[11:8], lb_q[11:8], lb_q[7:4], lb_q[7:4], lb_q[3:0], lb_q[3:0] } : 24'd0;
end

endmodule
