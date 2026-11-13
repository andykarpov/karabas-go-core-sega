`timescale 1ns / 1ps
`default_nettype wire

/*
 Sega Mega Drive / Genesis core for Karabas Mini rev.G (HDMI, PCM5102): fpgagen of MiST
 (fpgagen_sdram_top: fpgagen + its SDRAM controller sdram.sv) with the board glue of
 karabas-go-modules.

 Clocks: one PLL, VCO 650 MHz (50 * 13):
   pll_clk<5> MCLK 54.17 MHz (/12): the Genesis (MiST 54, a real console 53.69 / 53.20), the mcu link,
              the loader, the pads, the frame buffer writes and the SRAM
   pll_clk<4> 108.3 MHz (/6): the SDRAM controller (twice MCLK, rising edges together)
   pll_clk<3> 108.3 MHz (/6, 330 degrees = -0.77 ns): SDR_CLK through an ODDR2: the chip a little ahead
              of the controller, as the -772 ps of MiST that the capture points of sdram.sv expect
   pll_clk<0> 65.0 MHz (/10): the video out (1024 x 768 at 60 Hz), the OSD, HDMI; FT_CLK_OUT 8.125 MHz
              (/8 of it, karabas-go-notes ft-clk-out-required)
   pll_clk<1>, <2> 325 MHz (/2, 0 and 180 degrees): the HDMI serialiser
 MCLK and the SDRAM clock are related (FROM-TO in the ucf); clk_65 is crossed with synchronisers,
 a toggle handshake and the line buffer of sega_fb (TIG).

 Memory: ROM (up to 32 MB), 68K RAM, VRAM and save RAM in the SDRAM (sdram.sv, as MiST); the SRAM
 holds the frame buffer of sega_fb.

 The cartridge: the file of the core (type fileloader: .bin, .gen, .md in the sega folder) through the file loader
 of kg_mcu into the boot interface of fpgagen (sega_loader); the region of its header for Auto.

 Save RAM: the save RAM of the header ("RA" at 1B0) in a .sav file next to the game (the saves dir of
 the core folder) through kg_bk_ram on img slot 0: loaded before the CPU starts, saved after writes.

 Soft switches (core.json osd order):
   0 Region (Auto / JP / US / EU)   1 Pad (6 button / 3 button)   2 Swap joysticks   3 Border
   4 Reset
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign TAPE_OUT = 1'b0;
assign ESP32_SPI_CS_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;
assign MIDI_TX = 1'b1;

assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

// ------------------------------------------------------------------ clocks

wire clk_65, clk_ser, clk_ser_n, clk_sdr_out, clk_sdr, mclk;
wire locked;
wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(13),
	.CLKOUT0_DIVIDE(10),
	.CLKOUT1_DIVIDE(2),
	.CLKOUT2_DIVIDE(2), .CLKOUT2_PHASE(180.0),
	.CLKOUT3_DIVIDE(6), .CLKOUT3_PHASE(330.0),
	.CLKOUT4_DIVIDE(6),
	.CLKOUT5_DIVIDE(12),
	.BUFG_MASK(6'b111111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_65 = pll_clk[0];
assign clk_ser = pll_clk[1];
assign clk_ser_n = pll_clk[2];
assign clk_sdr_out = pll_clk[3];
assign clk_sdr = pll_clk[4];
assign mclk = pll_clk[5];
wire areset = ~locked;

// the clock of the FT812 (it must always have one): 65 / 8 = 8.125 MHz
reg [1:0] ft_div = 2'd0;
reg ft_q = 1'b0;
always @(posedge clk_65) begin
	ft_div <= ft_div + 2'd1;
	if (ft_div == 2'd3) ft_q <= ~ft_q;
end
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_65), .C1(~clk_65), .CE(1'b1), .D0(ft_q), .D1(ft_q), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK on a global buffer (as tsconf and the menu: on local routing the flip-flops of the SPI
// receiver had several ns of clock skew); the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

// MCU link v2 (karabas-go-firmware docs/link_v2.md, kg_mcu2); INT on IO1
wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [55:0] hid_kbd;
wire [7:0] kb_dat0 = hid_kbd[15:8], kb_dat1 = hid_kbd[23:16], kb_dat2 = hid_kbd[31:24],
	kb_dat3 = hid_kbd[39:32], kb_dat4 = hid_kbd[47:40], kb_dat5 = hid_kbd[55:48];
wire [15:0] joy_l16, joy_r16;
wire [12:0] joy_l = joy_l16[12:0], joy_r = joy_r16[12:0];
wire [1:0] ld_kind;
wire [7:0] ld_data;
wire [31:0] ld_addr;
wire ld_active, ld_wr;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [5*8-1:0] sw;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
// the .sav file of kg_bk_ram (slot 0) on the mounter of kg_mcu2
wire [7:0] img_flush, sdc_img_mounted, sdc_rd, sdc_wr, sdc_byte_in_data, sdc_byte_out_data;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector, bk_size;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire bk_mount, bk_flushed;
wire [7:0] bk_kind, bk_result;

kg_mcu2 #(
	.CAPS(16'h0002),     // backup RAM: the firmware flushes the .sav before a new game
	.SW_N(5),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),      // the file mounter: the .sav file of kg_bk_ram
	.IMG_OUT_LATENCY(2), // the sector buffer of kg_bk_ram
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(mclk),
	.N_RESET(~areset),

	.MCU_SCK(mcu_sck),
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SS(MCU_CS_N),
	.MCU_INT(mcu_int),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.SW(sw), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(dvi_only), .CORE_BUILD(), .FW_BUILD(),
	.BUSY(mcu_busy), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),

	.KBD(hid_kbd), .KBD_WR(), .PS2_CODE(), .PS2_KIND(), .PS2_WR(),
	.MS_X(), .MS_Y(), .MS_Z(), .MS_B(), .MS_WR(),
	.JOY_L(joy_l16), .JOY_R(joy_r16), .JOY_WR(),
	.PS2_CMD(16'h0000), .PS2_CMD_WR(1'b0),

	.LD_KIND(ld_kind), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(ld_active), .LD_END(),
	.LD_ADDR(ld_addr), .LD_DATA(ld_data), .LD_WR(ld_wr), .LD_READY(1'b1),

	.OSD_WR(osd_wr), .OSD_WADDR(osd_waddr), .OSD_WDATA(osd_wdata), .OSD_EN(osd_en),
	.OSD_FG(osd_fg), .OSD_BG(osd_bg), .OSD_ALPHA(osd_alpha), .OSD_PX(osd_px), .OSD_PY(osd_py),
	.OSD_PW(osd_pw), .OSD_PH(osd_ph), .OSD_PLACE(osd_place), .OSD_ZOOM(osd_zoom),

	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size),
	.SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
	.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data), .SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(), .IMG_FLUSH(img_flush), .FDD_CHNG_WR(), .FDD_CHNG(),
	.FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0),
	.BK_MOUNT(bk_mount), .BK_FLUSHED(bk_flushed), .BK_SLOT(3'd0), .BK_SIZE(bk_size),
	.BK_KIND(bk_kind), .BK_RESULT(bk_result),
	.IMG_ACTIVE(),

	.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'b1111), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
	.PORT_CFG(128'd0), .PORT_IN_FULL(), .PORT_STAT(), .PORT_STAT_WR(),
	.RTC_A(8'd0), .RTC_DI(8'd0), .RTC_CS(1'b0), .RTC_WR_N(1'b1), .RTC_DO(),
	.MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),

	.FT_SPI_ON(ft_spi_on), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(ft_mosi), .FT_MISO(FT_SPI_MISO),
	.FT_CS_N(ft_cs_n),
	.SD2_SCK(), .SD2_MOSI(sd2_mosi), .SD2_MISO(SD_DO), .SD2_CS_N(sd2_cs_n)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// the cartridge: the file loader (LD kind 1)
wire file_active = ld_active && ld_kind == 2'd1;
wire file_wr = ld_wr && ld_kind == 2'd1;
wire [31:0] file_addr = ld_addr;
wire [7:0] file_data = ld_data;

// ------------------------------------------------------------------ soft switches (the SW registers of kg_mcu2)

wire [1:0] sw_region = sw[0*8 +: 2];   // 0 Auto, 1 JP, 2 US, 3 EU
wire sw_3button = sw[1*8];
wire sw_swap = sw[2*8];
wire sw_border = sw[3*8];
wire sw_reset = sw[4*8];

// ------------------------------------------------------------------ cartridge loader

wire ext_reset_n, ext_bootdone, ext_data_ack, ext_data_req;
wire [15:0] ext_data;
wire [2:0] hdr_region;   // { EU, US, JP } of the header
wire [6:0] sav_sectors;  // the save RAM of the header
sega_loader loader (
	.clk(mclk),
	.file_active(file_active),
	.file_wr(file_wr),
	.file_addr(file_addr),
	.file_data(file_data),
	.ext_reset_n(ext_reset_n),
	.ext_bootdone(ext_bootdone),
	.ext_data(ext_data),
	.ext_data_ack(ext_data_ack),
	.ext_data_req(ext_data_req),
	.hdr_region(hdr_region),
	.sav_sectors(sav_sectors),
	.loading()
);

// the region: Auto takes US, else EU, else JP of the header (Genesis_MiSTer's default priority)
reg rg_export = 1'b1, pal = 1'b0;
always @(posedge mclk)
	case (sw_region)
		2'd1: begin rg_export <= 1'b0; pal <= 1'b0; end
		2'd2: begin rg_export <= 1'b1; pal <= 1'b0; end
		2'd3: begin rg_export <= 1'b1; pal <= 1'b1; end
		default:
			if (hdr_region[1])      begin rg_export <= 1'b1; pal <= 1'b0; end
			else if (hdr_region[2]) begin rg_export <= 1'b1; pal <= 1'b1; end
			else                    begin rg_export <= 1'b0; pal <= 1'b0; end
	endcase

// ext_sw of fpgagen: 3 PSG off, 4 FM off, 5 export, 6 PAL, 9 VRAM speed emulation (MiST default on),
// 10 fake EEPROM, 13 HiFi PCM, 14 CPU turbo, 15 border, 0 CRAM dots
wire [15:0] ext_sw = { sw_border, 5'b00000, 1'b1, 2'b00, pal, rg_export, 5'b00000 };

// ------------------------------------------------------------------ save RAM (.sav)

// kg_bk_ram on img slot 0: started when a cartridge is in (ext_bootdone rises) with the save RAM size
// of its header; the CPU is held in reset until the .sav file is in the save RAM. A new file resets it
// (the firmware flushes the old one before it loads another game).
reg file_active_d = 1'b0, bootdone_d = 1'b1, bk_reset = 1'b0, bk_start = 1'b0;
always @(posedge mclk) begin
	file_active_d <= file_active;
	bootdone_d <= ext_bootdone;
	bk_reset <= file_active && !file_active_d;
	bk_start <= ext_bootdone && !bootdone_d;
end

wire bk_busy, bk_mem_req, bk_mem_we, bk_mem_ack;
wire [14:0] bk_mem_addr;
wire [7:0] bk_mem_din, bk_mem_dout;
wire sav_wr;
wire [15:1] sav_a;
kg_bk_ram #(
	.SLOT(3'd0),
	.IDLE_CLOCKS(27'd54000000),    // ~1 s at 54 MHz: save after the last write
	.MAX_CLOCKS(27'd108000000),    // ~2 s: at the latest after the first write
	.MOUNT_CLOCKS(27'd54000000),   // ~1 s: no answer to CMD_BK_MOUNT, go on without a save
	.GRACE_CLOCKS(27'd540000),     // ~10 ms: no file
	.TIMEOUT(24'd10800000),        // img_sdc: ~200 ms (LINK 1)
	.LINK(2)                       // on the mounter of kg_mcu2, the mount / flush answer as IMG events
) bk_ram (
	.clk(mclk),
	.reset(bk_reset),
	.start(bk_start),
	.size(sav_sectors),
	.kind(8'h00),
	.busy(bk_busy),
	.mounted(),
	.saving(),
	.save_error(),
	.wr(sav_wr),
	.wr_addr(sav_a),
	.mem_req(bk_mem_req),
	.mem_we(bk_mem_we),
	.mem_addr(bk_mem_addr),
	.mem_din(bk_mem_din),
	.mem_ack(bk_mem_ack),
	.mem_dout(bk_mem_dout),
	.img_mounted(8'd0),
	.img_size(64'd0),
	.img_data_wr(1'b0),
	.img_data_addr(9'd0),
	.img_data(8'd0),
	.img_result_wr(1'b0),
	.img_result(8'd0),
	.img_sum(16'd0),
	.img_flush(img_flush),
	.img_q_wr(),
	.img_q_di(),
	.img_q_ack(1'b0),
	.sdc_img_mounted_i(sdc_img_mounted), .sdc_img_size_i(sdc_img_size), .sdc_rd_o(sdc_rd),
	.sdc_wr_o(sdc_wr), .sdc_sector_o(sdc_sector), .sdc_busy_i(sdc_busy), .sdc_done_i(sdc_done),
	.sdc_error_i(sdc_error), .sdc_slot_i(sdc_slot), .sdc_byte_in_strobe_i(sdc_byte_in_strobe),
	.sdc_byte_addr_i(sdc_byte_addr), .sdc_byte_in_data_i(sdc_byte_in_data),
	.sdc_byte_out_data_o(sdc_byte_out_data),
	.bk_mount(bk_mount), .bk_flushed(bk_flushed), .bk_size(bk_size), .bk_kind(bk_kind),
	.bk_result(bk_result)
);

wire bk_req, bk_ack, bk_we;
wire [15:1] bk_a;
wire [7:0] bk_d;
wire [15:0] bk_q;
sega_bk bk (
	.clk(mclk),
	.mem_req(bk_mem_req), .mem_we(bk_mem_we), .mem_addr(bk_mem_addr), .mem_din(bk_mem_din),
	.mem_ack(bk_mem_ack), .mem_dout(bk_mem_dout),
	.bk_req(bk_req), .bk_ack(bk_ack), .bk_we(bk_we), .bk_a(bk_a), .bk_d(bk_d), .bk_q(bk_q)
);

// reset: the PLL, the Reset item, the load of the .sav file (the boot FSM of fpgagen holds the CPU
// while a cartridge loads)
reg [7:0] rst_cnt = 8'd0;
reg gen_reset_n = 1'b0;
always @(posedge mclk) begin
	if (areset || sw_reset || bk_busy)
		rst_cnt <= 8'd0;
	else if (rst_cnt != 8'hFF)
		rst_cnt <= rst_cnt + 8'd1;
	gen_reset_n <= rst_cnt == 8'hFF;
end

// ------------------------------------------------------------------ pads

// mcu JOY_L / JOY_R: [0] connected, [1] up, [2] down, [3] left, [4] right, [5] start, [6] A, [7] B,
// [8] C, [9] X, [10] Y, [11] Z, [12] mode (1 = pressed), ORed with the keyboard (sega_kbd: arrows,
// Z X C / A S D, Enter, Space; I J K L, U O P / 7 8 9, M, N); gen_ctrl wants them active low
wire [12:0] kb_l, kb_r;
sega_kbd kbd (
	.clk(mclk),
	.kb_dat0(kb_dat0), .kb_dat1(kb_dat1), .kb_dat2(kb_dat2),
	.kb_dat3(kb_dat3), .kb_dat4(kb_dat4), .kb_dat5(kb_dat5),
	.kb_l(kb_l), .kb_r(kb_r)
);
wire [12:0] pad1 = sw_swap ? (joy_r | kb_r) : (joy_l | kb_l);
wire [12:0] pad2 = sw_swap ? (joy_l | kb_l) : (joy_r | kb_r);
wire [7:0] douta, oea, dina, doutb, oeb, dinb;

gen_ctrl ctrl_a (
	.RST_N(gen_reset_n), .CLK(mclk),
	.DAT(douta), .DOUT(dina), .CTL(oea),
	.J3BUT(sw_3button), .SWAP_Y(1'b0), .TEAMPLAY(1'b0),
	.UP(~pad1[1]), .DOWN(~pad1[2]), .LEFT(~pad1[3]), .RIGHT(~pad1[4]),
	.A(~pad1[6]), .B(~pad1[7]), .C(~pad1[8]), .START(~pad1[5]),
	.MODE(~pad1[12]), .X(~pad1[9]), .Y(~pad1[10]), .Z(~pad1[11])
);
gen_ctrl ctrl_b (
	.RST_N(gen_reset_n), .CLK(mclk),
	.DAT(doutb), .DOUT(dinb), .CTL(oeb),
	.J3BUT(sw_3button), .SWAP_Y(1'b0), .TEAMPLAY(1'b0),
	.UP(~pad2[1]), .DOWN(~pad2[2]), .LEFT(~pad2[3]), .RIGHT(~pad2[4]),
	.A(~pad2[6]), .B(~pad2[7]), .C(~pad2[8]), .START(~pad2[5]),
	.MODE(~pad2[12]), .X(~pad2[9]), .Y(~pad2[10]), .Z(~pad2[11])
);

// ------------------------------------------------------------------ Genesis

wire [3:0] vdp_r, vdp_g, vdp_b;
wire vdp_hbl, vdp_vbl, vdp_ce;
wire [15:0] snd_l, snd_r;
wire sdr_ba0, sdr_ba1, sdr_cs_n, sdr_ldqm, sdr_udqm;

fpgagen_sdram_top gen (   // USE_SVP false by default (karabas)
	.reset_n(gen_reset_n),
	.MCLK(mclk),
	.SDR_CLK(clk_sdr),
	.DL_CLK(mclk),
	.FPGA_INIT_N(locked),

	.DRAM_ADDR(SDR_A),
	.DRAM_BA_0(sdr_ba0),
	.DRAM_BA_1(sdr_ba1),
	.DRAM_CAS_N(SDR_CAS_N),
	.DRAM_CKE(),
	.DRAM_CS_N(sdr_cs_n),
	.DRAM_DQ(SDR_DQ),
	.DRAM_LDQM(sdr_ldqm),
	.DRAM_RAS_N(SDR_RAS_N),
	.DRAM_UDQM(sdr_udqm),
	.DRAM_WE_N(SDR_WE_N),

	.DAC_LDATA(snd_l),
	.DAC_RDATA(snd_r),

	.RED(vdp_r),
	.GREEN(vdp_g),
	.BLUE(vdp_b),
	.VS(),
	.HS(),
	.HBL(vdp_hbl),
	.VBL(vdp_vbl),
	.IN_BORDER(),
	.CE_PIX(vdp_ce),
	.LED(),

	.DINA(dina),
	.DOUTA(douta),
	.OEA(oea),
	.DINB(dinb),
	.DOUTB(doutb),
	.OEB(oeb),

	.JCART_EN(1'b0),
	.JCART_TH(),
	.JCART_DO(16'hFFFF),

	.saveram_addr(15'd0),
	.saveram_we(1'b0),
	.saveram_din(8'd0),
	.saveram_rd(1'b0),
	.saveram_dout(),

	.ext_reset_n(ext_reset_n),
	.ext_bootdone(ext_bootdone),
	.ext_data(ext_data),
	.ext_data_req(ext_data_req),
	.ext_data_ack(ext_data_ack),
	.ext_sw(ext_sw),

	.bk_req(bk_req),
	.bk_ack(bk_ack),
	.bk_we(bk_we),
	.bk_a(bk_a),
	.bk_d(bk_d),
	.bk_q(bk_q),
	.sav_wr(sav_wr),
	.sav_a(sav_a)
);
assign SDR_BA = { sdr_ba1, sdr_ba0 };
assign SDR_DQM = { sdr_udqm, sdr_ldqm };
// FLASH_CS_N (T3) is the SDRAM /CS of Mini G2 (rev G: tied low on the board); fpgagen drives 0
assign FLASH_CS_N = sdr_cs_n;
ODDR2 oddr_sdr_clk (.Q(SDR_CLK), .C0(clk_sdr_out), .C1(~clk_sdr_out), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ video

wire [23:0] vid_rgb;
wire vid_hs, vid_vs, vid_de;
sega_fb fb (
	.clk(mclk),
	.r(vdp_r),
	.g(vdp_g),
	.b(vdp_b),
	.hbl(vdp_hbl),
	.vbl(vdp_vbl),
	.ce_pix(vdp_ce),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N),
	.MRD_N(MRD_N),
	.clk_65(clk_65),
	.rgb(vid_rgb),
	.hs(vid_hs),
	.vs(vid_vs),
	.de(vid_de)
);

// the bitmap OSD of link v2 (kg_l2_osd_overlay): written in mclk, drawn in clk_65, centred in de, the
// scale from its size, 2 clocks of latency with its syncs and de
wire [23:0] osd_rgb;
wire osd_hs, osd_vs, osd_de;
kg_l2_osd_overlay osd (
	.wclk(mclk),
	.osd_wr(osd_wr), .osd_waddr(osd_waddr), .osd_wdata(osd_wdata), .osd_en(osd_en),
	.osd_fg(osd_fg), .osd_bg(osd_bg), .osd_alpha(osd_alpha), .osd_px(osd_px), .osd_py(osd_py),
	.osd_pw(osd_pw), .osd_ph(osd_ph), .osd_place(osd_place), .osd_zoom(osd_zoom),
	.icon_on(8'd0), .icon_act(8'd0),
	.clk(clk_65),
	.rgb_i(vid_rgb), .hs_i(vid_hs), .vs_i(vid_vs), .de_i(vid_de),
	.rgb_o(osd_rgb), .hs_o(osd_hs), .vs_o(osd_vs), .de_o(osd_de)
);

// ------------------------------------------------------------------ audio

// the mixer output of fpgagen (FM + PSG, signed 16 bits, changing at MCLK) taken at 48 kHz of MCLK:
// 54.1667 MHz = 650 / 12 MHz, 48 kHz / MCLK = 72 / 81250 exactly
reg [16:0] aud_acc = 17'd0;
reg [15:0] aud_l = 16'd0, aud_r = 16'd0;
reg aud_t = 1'b0;
always @(posedge mclk) begin
	if (aud_acc >= 17'd81250 - 17'd72) begin
		aud_acc <= aud_acc + 17'd72 - 17'd81250;
		aud_l <= snd_l;
		aud_r <= snd_r;
		aud_t <= ~aud_t;
	end
	else
		aud_acc <= aud_acc + 17'd72;
end

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck 3.39 MHz, 105.8 kHz
	.clk(mclk),
	.reset(areset),
	.left(aud_l),
	.right(aud_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// into clk_65 for HDMI: the toggle of a new sample (the samples hold for 1128 MCLK)
reg [2:0] aud_ts = 3'd0;
reg aud_stb = 1'b0;
reg [23:0] hdmi_l = 24'd0, hdmi_r = 24'd0;
always @(posedge clk_65) begin
	aud_ts <= { aud_ts[1:0], aud_t };
	aud_stb <= aud_ts[2] != aud_ts[1];
	if (aud_ts[2] != aud_ts[1]) begin
		hdmi_l <= { aud_l, 8'd0 };
		hdmi_r <= { aud_r, 8'd0 };
	end
end

// ------------------------------------------------------------------ HDMI

wire dvi_only_65;
kg_sync #(.W(1), .STAGES(3)) sync_dvi (.clk(clk_65), .d(dvi_only), .q(dvi_only_65));

// the output of the overlay is registered once more before the TMDS encoders (on Mini, 99 % slices, the
// overlay mux into the encoders did not fit 65 MHz: -2.7 ns), its syncs and de with it
reg hdmi_hs = 1'b1, hdmi_vs = 1'b1, hdmi_de = 1'b0;
reg [23:0] hdmi_rgb = 24'd0;
always @(posedge clk_65) begin
	hdmi_hs <= ~osd_hs;   // 1024 x 768 at 60 Hz: negative syncs (VESA)
	hdmi_vs <= ~osd_vs;
	hdmi_de <= osd_de;
	hdmi_rgb <= osd_rgb;
end

hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_65),
	.sclk(clk_ser),
	.sclk_n(clk_ser_n),
	.reset(areset),
	.rgb(hdmi_rgb),
	.vsync(hdmi_vs),
	.hsync(hdmi_hs),
	.de(hdmi_de),
	.audio_en(~dvi_only_65),
	.audio_l(hdmi_l),
	.audio_r(hdmi_r),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
