`timescale 1ns / 1ps
`default_nettype wire

/*
 sim_top.v - the Genesis (fpgagen_sdram_top: fpgagen + the sdram.sv controller) on the SDRAM model,
 for verilator. The harness (sim_sega.cpp) drives both clocks (MCLK = clk_sdr / 2, rising together
 with every second edge of clk_sdr, as from one PLL), feeds the ROM through the boot interface of
 fpgagen (ext_reset_n / ext_data_req / ext_data_ack / ext_bootdone, the protocol of the MiST top)
 and reads the video and audio outputs.

 The VHDL part comes from ghdl --synth (build.sh); fx68k, jt12, jt89 and sdram are the Verilog of
 sega.prj.
*/

module sim_top (
	input  wire        clk_sdr,
	input  wire        mclk,
	input  wire        reset_n,
	input  wire        init_n,

	input  wire        ext_reset_n,
	input  wire        ext_bootdone,
	input  wire [15:0] ext_data,
	input  wire        ext_data_ack,
	output wire        ext_data_req,
	input  wire [15:0] ext_sw,

	input  wire [7:0]  pad_a,        // the pins of the pad ports (1 = released)
	input  wire [7:0]  pad_b,

	output wire [3:0]  red,
	output wire [3:0]  green,
	output wire [3:0]  blue,
	output wire        hs,
	output wire        vs,
	output wire        hbl,
	output wire        vbl,
	output wire        ce_pix,
	output wire [15:0] audio_l,
	output wire [15:0] audio_r,
	output wire [31:0] sdram_errors,

	// probes for the harness (--trace-cpu): the 68000 bus and the boot state of fpgagen
	output wire [23:1] cpu_a,
	output wire        cpu_as_n,
	output wire        cpu_rw_n,
	output wire        cpu_dtack_n,
	output wire [15:0] cpu_dout,
	output wire [15:0] cpu_din,
	output wire        cpu_halted_n,
	output wire        mrst_n,

	// the backup RAM port as kg_bk_ram drives it (through sega_bk), and the save RAM writes of the 68000
	input  wire        mem_req,
	input  wire        mem_we,
	input  wire [14:0] mem_addr,
	input  wire [7:0]  mem_din,
	output wire        mem_ack,
	output wire [7:0]  mem_dout,
	output wire        sav_wr,
	output wire [15:1] sav_a
);

wire bk_req, bk_ack, bk_we;
wire [15:1] bk_a;
wire [7:0] bk_d;
wire [15:0] bk_q;
sega_bk bk (
	.clk(mclk),
	.mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_din(mem_din),
	.mem_ack(mem_ack), .mem_dout(mem_dout),
	.bk_req(bk_req), .bk_ack(bk_ack), .bk_we(bk_we), .bk_a(bk_a), .bk_d(bk_d), .bk_q(bk_q)
);

assign cpu_a        = gen.fpgagen_i.fx68k_inst_i.eab;
assign cpu_as_n     = gen.fpgagen_i.fx68k_inst_i.ASn;
assign cpu_rw_n     = gen.fpgagen_i.fx68k_inst_i.eRWn;
assign cpu_dtack_n  = gen.fpgagen_i.fx68k_inst_i.DTACKn;
assign cpu_dout     = gen.fpgagen_i.fx68k_inst_i.oEdb;
assign cpu_din      = gen.fpgagen_i.fx68k_inst_i.iEdb;
assign cpu_halted_n = gen.fpgagen_i.fx68k_inst_i.oHALTEDn;
assign mrst_n       = gen.fpgagen_i.mrst_n;

wire [15:0] dq;
wire [12:0] a;
wire        ba0, ba1, cas_n, ras_n, we_n, cs_n, ldqm, udqm, cke;

fpgagen_sdram_top gen (
	.reset_n      (reset_n),
	.MCLK         (mclk),
	.SDR_CLK      (clk_sdr),
	.DL_CLK       (mclk),
	.FPGA_INIT_N  (init_n),

	.DRAM_ADDR    (a),
	.DRAM_BA_0    (ba0),
	.DRAM_BA_1    (ba1),
	.DRAM_CAS_N   (cas_n),
	.DRAM_CKE     (cke),
	.DRAM_CS_N    (cs_n),
	.DRAM_DQ      (dq),
	.DRAM_LDQM    (ldqm),
	.DRAM_RAS_N   (ras_n),
	.DRAM_UDQM    (udqm),
	.DRAM_WE_N    (we_n),

	.DAC_LDATA    (audio_l),
	.DAC_RDATA    (audio_r),

	.RED          (red),
	.GREEN        (green),
	.BLUE         (blue),
	.VS           (vs),
	.HS           (hs),
	.HBL          (hbl),
	.VBL          (vbl),
	.IN_BORDER    (),
	.CE_PIX       (ce_pix),
	.LED          (),

	.DINA         (pad_a),
	.DOUTA        (),
	.OEA          (),
	.DINB         (pad_b),
	.DOUTB        (),
	.OEB          (),

	.JCART_EN     (1'b0),
	.JCART_TH     (),
	.JCART_DO     (16'hffff),

	.saveram_addr (15'd0),
	.saveram_we   (1'b0),
	.saveram_din  (8'd0),
	.saveram_rd   (1'b0),
	.saveram_dout (),

	.ext_reset_n  (ext_reset_n),
	.ext_bootdone (ext_bootdone),
	.ext_data     (ext_data),
	.ext_data_req (ext_data_req),
	.ext_data_ack (ext_data_ack),
	.ext_sw       (ext_sw),

	.bk_req       (bk_req),
	.bk_ack       (bk_ack),
	.bk_we        (bk_we),
	.bk_a         (bk_a),
	.bk_d         (bk_d),
	.bk_q         (bk_q),
	.sav_wr       (sav_wr),
	.sav_a        (sav_a)
);

sdram_model sdram (
	.clk    (clk_sdr),
	.dq     (dq),
	.a      (a),
	.ba     ({ ba1, ba0 }),
	.cs_n   (cs_n),
	.ras_n  (ras_n),
	.cas_n  (cas_n),
	.we_n   (we_n),
	.dqml   (ldqm),
	.dqmh   (udqm),
	.errors (sdram_errors)
);

endmodule
