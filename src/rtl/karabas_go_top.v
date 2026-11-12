`timescale 1ns / 1ps
`default_nettype wire

/*
 Sega Mega Drive / Genesis core for Karabas Go (VGA, PCM5102). Made by tools/mktops.py from
 karabas_minig_top.v (do not edit: change that one and run it): the same except the pins, the MCU
 link (MCU_SCK not on a clock pin) and the video: 24 bit RGB to the VGA DAC with its pixel clock on
 V_CLK (clk_65), the FT812 off that bus (FT_OE_N = 1). The floppy connector is not used (its
 outputs 0). fpgagen of MiST (fpgagen_sdram_top: fpgagen + its SDRAM controller sdram.sv) with
 the board glue of karabas-go-modules.

 Clocks: one PLL, VCO 650 MHz (50 * 13):
   pll_clk<5> MCLK 54.17 MHz (/12): the Genesis (MiST 54, a real console 53.69 / 53.20), the mcu link,
              the loader, the pads, the frame buffer writes and the SRAM
   pll_clk<4> 108.3 MHz (/6): the SDRAM controller (twice MCLK, rising edges together)
   pll_clk<3> 108.3 MHz (/6, 330 degrees = -0.77 ns): SDR_CLK through an ODDR2: the chip a little ahead
              of the controller, as the -772 ps of MiST that the capture points of sdram.sv expect
   pll_clk<0> 65.0 MHz (/10): the video out (1024 x 768 at 60 Hz, VGA, V_CLK), the OSD
   (pll_clk<1>, <2>, the HDMI serialiser of Mini / Mini G, are not used here)
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

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

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

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] burst ready (firmware IO1, GPIO2), [1] burst cs_n (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

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
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;
assign MIDI_TX = 1'b1;
assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_CLK = 1'b0;      // the SAM2695 synth: held in reset, no use for it here
assign MIDI_RESET_N = 1'b0;

assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign BEEPER = 1'b0;
assign DAC_MUTE = 1'b1;    // soft mute of the PCM5102: 1 = sound on

// the floppy connector is not used: its outputs 0 (the board inverts them: high = active)
assign FDC_DRIVE = 2'b00;
assign FDC_MOTOR = 1'b0;
assign FDC_DIR = 1'b0;
assign FDC_STEP = 1'b0;
assign FDC_WDATA = 1'b0;
assign FDC_WGATE = 1'b0;
assign FDC_SIDE_N = 1'b0;

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

// the pixel clock of the VGA DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_65), .C1(~clk_65), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK is not on a clock pin before rev.G (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;

wire mcu_burst_ready;
assign MCU_SPI_IO[0] = mcu_burst_ready;
assign MCU_SPI_IO[1] = 1'bz;

wire [7:0] kb_status, kb_dat0, kb_dat1, kb_dat2, kb_dat3, kb_dat4, kb_dat5;
wire [12:0] joy_l, joy_r;
wire file_active, file_wr;
wire [7:0] file_data;
wire [31:0] file_addr;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_mounted, img_data, img_result, img_flush;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;

kg_mcu #(
	.BURST_MAX_MHZ(0),   // MCU_SCK is not on a clock pin: bursts at the link clock
	.CS_FILTER(3),
	.ENABLE_RTC(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),      // the file mounter: the .sav file of kg_bk_ram
	.ENABLE_IMG_WP(0),
	.ENABLE_BK(1),       // kg_bk_ram: the save RAM of the cartridge (caps bit 3: flushes before a new game)
	.ENABLE_MIDI(0),
	.ENABLE_FILE(1),     // the cartridge (the file of the fileloader core)
	.FILE_CMDS(1),       // FILELOADER / FILEBANK / FILEDATA, as snes / nes
	.FILE_WR_EACH(1),    // every byte (a new load starts at 0 again)
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(mclk),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),
	.MCU_BURST_CS_N(MCU_SPI_IO[1]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_STATUS(kb_status),
	.KB_DAT0(kb_dat0),
	.KB_DAT1(kb_dat1),
	.KB_DAT2(kb_dat2),
	.KB_DAT3(kb_dat3),
	.KB_DAT4(kb_dat4),
	.KB_DAT5(kb_dat5),
	.KB_SCANCODE(),
	.KB_SCANCODE_UPD(),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	.MS_X(),
	.MS_Y(),
	.MS_Z(),
	.MS_B(),
	.MS_UPD(),

	.ROMLOADER_ACTIVE(),
	.ROMLOAD_ADDR(),
	.ROMLOAD_DATA(),
	.ROMLOAD_WR(),

	.FILELOAD_RESET(),
	.FILELOAD_ACTIVE(file_active),
	.FILELOAD_SIZE(),
	.FILELOAD_ADDR(file_addr),
	.FILELOAD_DATA(file_data),
	.FILELOAD_WR(file_wr),
	.FILELOAD_SLOT(),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	.MIDI_DATA(),
	.MIDI_WR(),
	.MIDI_LOST(),

	// not used by this core
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.RTC_A(8'h00),
	.RTC_DI(8'h00),
	.RTC_DO(),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.UART_RX_DATA(),
	.UART_RX_IDX(),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_WP(),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_FLUSH(img_flush),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),
	.FDD_CHNG_REQ(1'b0),
	.FDD_CHNG_DS(2'd0),
	.PRN_DATA(8'h00),
	.PRN_WR(1'b0),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

wire [5*8-1:0] sw;
kg_soft_switches #(.N(5)) soft_switches (
	.clk(mclk),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
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
	.TIMEOUT(24'd10800000)         // img_sdc: ~200 ms
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
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_flush(img_flush),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack)
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
// the SDRAM /CS is hard wired on Go: sdr_cs_n is not used; FLASH_CS_N is the flash chip
assign FLASH_CS_N = 1'b1;
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

// osd_command into clk_65: taken when two samples agree (it holds for many clocks)
reg [15:0] osd_s1 = 16'd0, osd_s2 = 16'd0, osd_cmd = 16'd0;
always @(posedge clk_65) begin
	osd_s1 <= osd_command;
	osd_s2 <= osd_s1;
	if (osd_s1 == osd_s2)
		osd_cmd <= osd_s2;
end

// as core-macplus / core-bk: 1024 x 768, the counters start at the leading edge of the syncs
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_OFFSET(276), .V_OFFSET(105), .H_DIV4_WIDTH(1400), .V_DIV4_HEIGHT(900)) osd (
	.clk(clk_65),
	.rgb_i(vid_rgb),
	.rgb_o(osd_rgb),
	.hsync_i(vid_hs),
	.vsync_i(vid_vs),
	.v_offset(11'd0),
	.h_offset(11'd0),
	.osd_command(osd_cmd)
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
	.lrck(DAC_LRCK)
);

// ------------------------------------------------------------------ VGA

// osd_rgb is one clock behind the syncs of the overlay's input: the syncs go with it
reg vga_hs = 1'b1, vga_vs = 1'b1;
always @(posedge clk_65) begin
	vga_hs <= ~vid_hs;   // 1024 x 768 at 60 Hz: negative syncs (VESA)
	vga_vs <= ~vid_vs;
end
assign VGA_R = osd_rgb[23:16];
assign VGA_G = osd_rgb[15:8];
assign VGA_B = osd_rgb[7:0];
assign VGA_HS = vga_hs;
assign VGA_VS = vga_vs;

endmodule
