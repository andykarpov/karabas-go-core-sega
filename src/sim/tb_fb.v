`timescale 1ps / 1ps
`default_nettype wire

/*
 tb_fb.v - sega_fb on an asynchronous SRAM model (10 ns) with a synthetic VDP: lines of 3420 MCLK,
 W pixels on CE_PIX every 8 (H40, W = 320) or 10 (H32, W = 256) MCLK, H lines of 262 (V28). The
 pixel of (x, y) is { x[3:0], y[3:0], x[7:4] ^ y[7:4] }. Checked in output frame 3 (by then a
 complete frame is shown): every pixel of 1024 x 768 is the source pixel (floor(k W / 960), oy / 3)
 inside the picture (32 + k, y0 + oy) and black outside; the frame is 1024 x 768 with 806 lines.

 iverilog -o build/tb_fb -I. tb_fb.v ../rtl/karabas/sega_fb.v ../../modules/rtl/mem/kg_sdpram.v
 vvp build/tb_fb +h32   (H32 instead of H40)
*/

module tb_fb;

reg clk = 0, clk_65 = 0;
always #9231 clk = ~clk;        // 54.166 MHz
always #7692 clk_65 = ~clk_65;  // 65.0 MHz

integer W, PIXDIV, H;
initial begin
	if ($test$plusargs("h32")) begin W = 256; PIXDIV = 10; end else begin W = 320; PIXDIV = 8; end
	H = 224;
end

// ------------------------------------------------------------------ synthetic VDP
reg [3:0] r = 0, g = 0, b = 0;
reg hbl = 1, vbl = 1, ce_pix = 0;
integer hc = 0, vc = 0, px = 0;
always @(posedge clk) begin
	hc <= hc == 3419 ? 0 : hc + 1;
	if (hc == 3419) vc <= vc == 261 ? 0 : vc + 1;
	ce_pix <= (hc % PIXDIV) == 0;
	// active area: from MCLK 200, W pixels
	hbl <= !(hc >= 200 && hc < 200 + W * PIXDIV);
	vbl <= !(vc >= 10 && vc < 10 + H);
	px = (hc - 200) / PIXDIV;
	{ r, g, b } <= src(px, vc - 10);
end
// the expected pixel of source (x, y)
function [11:0] src;
	input integer x, y;
	reg [7:0] xx, yy;
	begin
		xx = x; yy = y;
		src = { xx[3:0], yy[3:0], xx[7:4] ^ yy[7:4] };
	end
endfunction

// ------------------------------------------------------------------ SRAM model
wire [20:0] MA;
wire [15:0] MD;
wire [1:0] MWR_N, MRD_N;
reg [15:0] mem [0:(1 << 21) - 1];
reg [15:0] rd_q;
always @(MA, MRD_N, MWR_N) rd_q <= #10000 mem[MA];
assign MD = (MRD_N == 2'b00 && MWR_N == 2'b11) ? rd_q : 16'bz;
always @(posedge MWR_N[0]) mem[MA][7:0] <= MD[7:0];
always @(posedge MWR_N[1]) mem[MA][15:8] <= MD[15:8];

// ------------------------------------------------------------------ dut
wire [23:0] rgb;
wire hs, vs, de;
sega_fb dut (
	.clk(clk), .r(r), .g(g), .b(b), .hbl(hbl), .vbl(vbl), .ce_pix(ce_pix),
	.MA(MA), .MD(MD), .MWR_N(MWR_N), .MRD_N(MRD_N),
	.clk_65(clk_65), .rgb(rgb), .hs(hs), .vs(vs), .de(de)
);

// ------------------------------------------------------------------ check
integer oframe = 0, ox = 0, oy = 0, lines = 0, errors = 0, checked = 0, k, sy, y0;
reg vs_d = 0, de_d = 0, hs_d = 0;
reg [11:0] exp_px;
always @(posedge clk_65) begin
	vs_d <= vs; de_d <= de; hs_d <= hs;
	if (vs && !vs_d) begin
		if (oframe == 3) begin
			if (oy != 768) begin $display("FAIL: %0d picture lines", oy); errors = errors + 1; end
			$display("tb_fb: W %0d, %0d pixels checked, %0d errors", W, checked, errors);
			if (errors) $display("FAIL"); else $display("PASS");
			$finish;
		end
		oframe = oframe + 1;
		oy = 0;
	end
	if (de) begin
		if (oframe == 3) begin
			y0 = (768 - 3 * H) / 2;
			k = ox - 32;
			if (oy >= y0 && oy < y0 + 3 * H && k >= 0 && k < 960) begin
				sy = (oy - y0) / 3;
				exp_px = src((k * W) / 960, sy);
				if (rgb != { exp_px[11:8], exp_px[11:8], exp_px[7:4], exp_px[7:4], exp_px[3:0], exp_px[3:0] }) begin
					if (errors < 10) $display("FAIL: out %0d,%0d = %06x, expected source %0d,%0d = %03x", ox, oy, rgb, (k * W) / 960, sy, exp_px);
					errors = errors + 1;
				end
			end
			else if (rgb != 24'd0) begin
				if (errors < 10) $display("FAIL: out %0d,%0d = %06x outside the picture", ox, oy, rgb);
				errors = errors + 1;
			end
			checked = checked + 1;
		end
		ox = ox + 1;
	end
	if (!de && de_d) begin
		if (ox != 1024 && oframe == 3) begin $display("FAIL: line %0d has %0d pixels", oy, ox); errors = errors + 1; end
		ox = 0;
		oy = oy + 1;
	end
end

initial begin
	#200000000000;
	$display("FAIL: timeout"); $finish;
end

endmodule
