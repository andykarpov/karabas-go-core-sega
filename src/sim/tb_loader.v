`timescale 1ns / 1ps
`default_nettype wire

/*
 tb_loader.v - sega_loader with a model of the boot FSM of fpgagen (BOOT_READ_1 / BOOT_WRITE_1:
 ext_data_req high in READ_1; on ext_data_ack the word is taken, the request drops and comes back
 after a write of W clocks; ext_reset_n low resets it to READ_1 with the request high).
 Files of N bytes come as kg_mcu sends them (one file_wr per byte, a byte every B clocks while
 file_active). Checked: every word in order (first byte high), an odd last byte padded with FF, the
 word count, ext_bootdone low during the load and high after it, the region of the header.

 iverilog -o build/tb_loader tb_loader.v ../rtl/karabas/sega_loader.v && vvp -n build/tb_loader
*/

module tb_loader;

reg clk = 0;
always #9 clk = ~clk;

reg file_active = 0, file_wr = 0;
reg [31:0] file_addr = 0;
reg [7:0] file_data = 0;
wire ext_reset_n, ext_bootdone, ext_data_ack, loading;
wire [15:0] ext_data;
wire [2:0] hdr_region;
reg ext_data_req = 1;

sega_loader dut (
	.clk(clk), .file_active(file_active), .file_wr(file_wr), .file_addr(file_addr),
	.file_data(file_data), .ext_reset_n(ext_reset_n), .ext_bootdone(ext_bootdone),
	.ext_data(ext_data), .ext_data_ack(ext_data_ack), .ext_data_req(ext_data_req),
	.hdr_region(hdr_region), .loading(loading)
);

// the file
reg [7:0] rom [0:4095];
integer n_bytes, wbusy;

// boot FSM model
integer got = 0, errors = 0, wr_cnt = 0, write_clocks = 12;
reg [15:0] expw;
always @(posedge clk) begin
	if (!ext_reset_n) begin
		ext_data_req <= 1;
		got = 0;
		wr_cnt = 0;
	end
	else if (ext_data_req && ext_data_ack) begin
		expw = { rom[2 * got], (2 * got + 1 < n_bytes) ? rom[2 * got + 1] : 8'hFF };
		if (ext_data != expw) begin
			if (errors < 10) $display("FAIL: word %0d = %04x, expected %04x", got, ext_data, expw);
			errors = errors + 1;
		end
		got = got + 1;
		ext_data_req <= 0;
		wr_cnt = write_clocks;
	end
	else if (!ext_data_req) begin
		if (wr_cnt > 0) wr_cnt = wr_cnt - 1;
		if (wr_cnt == 0) ext_data_req <= 1;
	end
end

task load;
	input integer nb, byte_clocks;
	input [23:0] region;    // three bytes at 1F0
	integer i, k;
	begin
		n_bytes = nb;
		for (i = 0; i < nb; i = i + 1) rom[i] = (i * 7 + 3) & 8'hFF;
		if (nb > 16'h1F2) begin rom[16'h1F0] = region[23:16]; rom[16'h1F1] = region[15:8]; rom[16'h1F2] = region[7:0]; end
		@(posedge clk) file_active <= 1;
		repeat (20) @(posedge clk);
		for (i = 0; i < nb; i = i + 1) begin
			@(posedge clk) begin file_addr <= i; file_data <= rom[i]; file_wr <= 1; end
			@(posedge clk) file_wr <= 0;
			for (k = 2; k < byte_clocks; k = k + 1) @(posedge clk);
			if (ext_bootdone) begin $display("FAIL: bootdone during the load"); errors = errors + 1; end
		end
		@(posedge clk) file_active <= 0;
		repeat (400) @(posedge clk);
		if (!ext_bootdone) begin $display("FAIL: no bootdone after %0d bytes", nb); errors = errors + 1; end
		if (got != (nb + 1) / 2) begin $display("FAIL: %0d words, expected %0d", got, (nb + 1) / 2); errors = errors + 1; end
	end
endtask

initial begin
	repeat (10) @(posedge clk);
	if (!ext_bootdone) begin $display("FAIL: bootdone low before the first file"); errors = errors + 1; end
	load(1024, 14, "JUE");          // fast bytes (14 clocks: faster than the writes, the FIFO fills)
	if (hdr_region != 3'b111) begin $display("FAIL: region %b for JUE", hdr_region); errors = errors + 1; end
	load(1001, 30, "E  ");          // odd size, slow bytes
	if (hdr_region != 3'b100) begin $display("FAIL: region %b for E", hdr_region); errors = errors + 1; end
	load(600, 20, "4  ");           // new style digit: 4 = USA
	if (hdr_region != 3'b010) begin $display("FAIL: region %b for 4", hdr_region); errors = errors + 1; end
	load(600, 20, "A  ");           // A = 1010: bit 3 Europe, bit 0 (Japan) clear
	if (hdr_region != 3'b100) begin $display("FAIL: region %b for A", hdr_region); errors = errors + 1; end
	load(100, 20, "???");           // too short for a header: US
	if (hdr_region != 3'b010) begin $display("FAIL: region %b for no header", hdr_region); errors = errors + 1; end
	$display("tb_loader: %0d errors", errors);
	if (errors) $display("FAIL"); else $display("PASS");
	$finish;
end

endmodule
