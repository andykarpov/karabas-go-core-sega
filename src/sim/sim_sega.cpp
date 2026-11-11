// sim_sega.cpp - harness of sim_top.v (the Genesis on the SDRAM model).
//
// Clocks: one MCLK period = 4 steps (clk_sdr 1 0 1 0, mclk 1 1 0 0): clk_sdr = 2 x MCLK, rising
// together with MCLK, as two outputs of one PLL. Inputs change on the falling edge of MCLK; the video
// outputs are sampled there too (they are registers of MCLK, valid for the CE_PIX cycle).
//
// The ROM goes through the boot interface of fpgagen like the MiST top does it: ext_reset_n low for
// a few clocks, then each 16 bit word (big endian: the first byte of the file is the high byte) on
// ext_data with a one clock ext_data_ack when ext_data_req is high, then ext_bootdone stays high.
//
// usage: Vsim_top --rom FILE [--frames N] [--ppm PREFIX] [--ppm-every K] [--wav FILE] [--sw HEX]
//                 [--expect-pixel F,X,Y,RGB]... [--expect-size F,W,H] [--expect-audio]
//   --frames N        run N frames after the boot (default 3)
//   --ppm PREFIX      write PREFIX_NNN.ppm of the frames (every K-th with --ppm-every)
//   --wav FILE        the audio (DAC_LDATA / DAC_RDATA) at 48 kHz
//   --sw HEX          ext_sw of fpgagen (default 0220: export, VRAM speed emulation)
//   --expect-pixel    the pixel X,Y of frame F (0 = the first after the boot) is RGB (12 bit hex)
//   --expect-size     frame F is W x H active pixels
//   --expect-audio    the audio is not silent
//   --trace-cpu N     print the first N bus cycles of the 68000 after the boot (address, data)
//   --expect-sav HEX,HEX,...  after the frames: the save RAM bytes 0, 1, ... read through the backup RAM
//                     port (sega_bk, as kg_bk_ram does), then a byte written and read back through it, and
//                     as many save RAM writes of the 68000 (sav_wr) as bytes given
// Prints one line per frame (size, checksum) and "PASS" / "FAIL: ..." at the end; exit 1 on FAIL.

#include "Vsim_top.h"
#include "verilated.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>

struct ExpPix { int f, x, y; unsigned rgb; };
struct ExpSize { int f, w, h; };

static Vsim_top *top;
static uint64_t mclk_count = 0;

static void step(int sdr, int m) {
	top->clk_sdr = sdr;
	top->mclk = m;
	top->eval();
}

// one MCLK period; between the rising and the falling edge `fall` is called (inputs change there,
// outputs are sampled there)
template <class F> static void mclk_cycle(F fall) {
	step(1, 1);
	step(0, 1);
	fall();
	step(1, 0);
	step(0, 0);
	mclk_count++;
}

static void wav_header(FILE *f, uint32_t samples) {
	uint32_t data = samples * 4, riff = 36 + data, fmt = 16, rate = 48000, brate = rate * 4;
	uint16_t pcm = 1, ch = 2, align = 4, bits = 16;
	fwrite("RIFF", 1, 4, f); fwrite(&riff, 4, 1, f); fwrite("WAVEfmt ", 1, 8, f);
	fwrite(&fmt, 4, 1, f); fwrite(&pcm, 2, 1, f); fwrite(&ch, 2, 1, f); fwrite(&rate, 4, 1, f);
	fwrite(&brate, 4, 1, f); fwrite(&align, 2, 1, f); fwrite(&bits, 2, 1, f);
	fwrite("data", 1, 4, f); fwrite(&data, 4, 1, f);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	std::string rom_name, ppm, wav_name;
	int frames = 3, ppm_every = 1, trace_cpu = 0;
	unsigned sw = 0x0220;
	bool expect_audio = false;
	std::vector<ExpPix> exp_pix;
	std::vector<ExpSize> exp_size;
	std::vector<unsigned> exp_sav;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() -> const char * { if (i + 1 >= argc) { fprintf(stderr, "%s: value missing\n", a.c_str()); exit(2); } return argv[++i]; };
		if (a == "--rom") rom_name = next();
		else if (a == "--frames") frames = atoi(next());
		else if (a == "--ppm") ppm = next();
		else if (a == "--ppm-every") ppm_every = atoi(next());
		else if (a == "--wav") wav_name = next();
		else if (a == "--sw") sw = strtoul(next(), 0, 16);
		else if (a == "--expect-audio") expect_audio = true;
		else if (a == "--trace-cpu") trace_cpu = atoi(next());
		else if (a == "--expect-sav") { char *q = (char *)next(); for (char *t = strtok(q, ","); t; t = strtok(0, ",")) exp_sav.push_back(strtoul(t, 0, 16)); }
		else if (a == "--expect-pixel") { ExpPix e; if (sscanf(next(), "%d,%d,%d,%x", &e.f, &e.x, &e.y, &e.rgb) != 4) return 2; exp_pix.push_back(e); }
		else if (a == "--expect-size") { ExpSize e; if (sscanf(next(), "%d,%d,%d", &e.f, &e.w, &e.h) != 3) return 2; exp_size.push_back(e); }
		else if (a[0] != '+') { fprintf(stderr, "unknown argument %s\n", a.c_str()); return 2; }
	}
	if (rom_name.empty()) { fprintf(stderr, "--rom FILE needed\n"); return 2; }
	FILE *rf = fopen(rom_name.c_str(), "rb");
	if (!rf) { perror(rom_name.c_str()); return 2; }
	std::vector<uint8_t> rom;
	{ uint8_t buf[65536]; size_t n; while ((n = fread(buf, 1, sizeof buf, rf)) > 0) rom.insert(rom.end(), buf, buf + n); }
	fclose(rf);
	if (rom.size() & 1) rom.push_back(0xff);
	size_t words = rom.size() / 2;

	top = new Vsim_top;
	top->reset_n = 0; top->init_n = 0;
	top->ext_reset_n = 1; top->ext_bootdone = 0; top->ext_data = 0; top->ext_data_ack = 0;
	top->ext_sw = sw; top->pad_a = 0xff; top->pad_b = 0xff;
	top->mem_req = 0; top->mem_we = 0; top->mem_addr = 0; top->mem_din = 0;

	// power up: init_n (PLL lock) after a while, reset after the SDRAM init
	for (int i = 0; i < 64; i++) mclk_cycle([] {});
	top->init_n = 1;
	for (int i = 0; i < 2000; i++) mclk_cycle([] {});
	top->reset_n = 1;

	// boot: ext_reset_n pulse, then the words
	size_t w = 0;
	int st = 0, rst = 4;
	uint64_t t0 = mclk_count;
	while (st != 3) {
		mclk_cycle([&] {
			top->ext_data_ack = 0;
			if (rst > 0) { top->ext_reset_n = 0; rst--; return; }
			top->ext_reset_n = 1;
			switch (st) {
			case 0: // wait for a request
				if (w == words) { top->ext_bootdone = 1; st = 3; break; }
				if (top->ext_data_req) {
					top->ext_data = (rom[2 * w] << 8) | rom[2 * w + 1];
					top->ext_data_ack = 1;
					w++;
					st = 1;
				}
				break;
			case 1: // the request drops on the ack
				st = 0;
				break;
			}
		});
		if (mclk_count - t0 > 64 * words + 100000) { printf("FAIL: the boot interface stalled at word %zu\n", w); return 1; }
	}
	printf("boot: %zu words in %llu MCLK\n", words, (unsigned long long)(mclk_count - t0));

	// video capture
	std::vector<uint16_t> line, frame;
	std::vector<int> line_len;
	int fno = -1, width = 0;
	bool prev_hbl = true, prev_vbl = true, started = false;
	std::vector<std::vector<uint16_t>> kept; // the frames needed by the checks
	std::vector<int> kept_w, kept_h;
	FILE *wf = 0;
	uint32_t wav_samples = 0;
	int16_t amin = 32767, amax = -32768;
	if (!wav_name.empty()) { wf = fopen(wav_name.c_str(), "wb"); wav_header(wf, 0); }
	int max_frame = frames - 1;
	for (auto &e : exp_pix) if (e.f > max_frame) max_frame = e.f;
	for (auto &e : exp_size) if (e.f > max_frame) max_frame = e.f;
	uint64_t frame_limit = mclk_count + (uint64_t)(max_frame + 3) * 1100000;
	uint32_t acc = 0;
	bool done = false;
	static int sav_writes = 0;
	while (!done) {
		mclk_cycle([&] {
			// audio: 48 kHz from MCLK 54 MHz (accumulator)
			acc += 48000;
			if (acc >= 54000000u) {
				acc -= 54000000u;
				int16_t l = (int16_t)top->audio_l, r = (int16_t)top->audio_r;
				if (started) { if (l < amin) amin = l; if (l > amax) amax = l; }
				if (wf) { fwrite(&l, 2, 1, wf); fwrite(&r, 2, 1, wf); wav_samples++; }
			}
			// 68000 bus cycles: printed when DTACK ends one
			static bool prev_dtack = true, prev_rst = false;
			if (top->mrst_n != prev_rst) { printf("[%llu] MRST_N %d, halted_n %d\n", (unsigned long long)mclk_count, top->mrst_n, top->cpu_halted_n); prev_rst = top->mrst_n; }
			if (trace_cpu > 0 && !top->cpu_as_n && !top->cpu_dtack_n && prev_dtack) {
				printf("[%llu] %s %06x = %04x\n", (unsigned long long)mclk_count, top->cpu_rw_n ? "rd" : "WR",
					top->cpu_a << 1, top->cpu_rw_n ? top->cpu_din : top->cpu_dout);
				trace_cpu--;
			}
			prev_dtack = top->cpu_dtack_n || top->cpu_as_n;
			if (top->sav_wr) sav_writes++;
			bool hbl = top->hbl, vbl = top->vbl;
			if (top->ce_pix && !hbl && !vbl && started)
				line.push_back((top->red << 8) | (top->green << 4) | top->blue);
			if (hbl && !prev_hbl && !line.empty()) {
				if ((int)line.size() > width) width = line.size();
				frame.insert(frame.end(), line.begin(), line.end());
				line_len.push_back(line.size());
				line.clear();
			}
			if (vbl && !prev_vbl) {
				if (started) {
					int h = line_len.size();
					uint32_t sum = 0;
					for (auto p : frame) sum = sum * 31 + p;
					fno++;
					printf("frame %d: %d x %d, checksum %08x\n", fno, width, h, sum);
					// pad short lines (should not happen) to the width
					std::vector<uint16_t> img(width * h, 0);
					size_t o = 0;
					for (int y = 0; y < h; y++) { for (int x = 0; x < line_len[y]; x++) img[y * width + x] = frame[o++]; }
					if (!ppm.empty() && fno % ppm_every == 0) {
						char n[512]; snprintf(n, sizeof n, "%s_%03d.ppm", ppm.c_str(), fno);
						FILE *pf = fopen(n, "wb");
						fprintf(pf, "P6\n%d %d\n255\n", width, h);
						for (auto p : img) { uint8_t c[3] = { (uint8_t)(((p >> 8) & 15) * 17), (uint8_t)(((p >> 4) & 15) * 17), (uint8_t)((p & 15) * 17) }; fwrite(c, 1, 3, pf); }
						fclose(pf);
					}
					kept.push_back(img); kept_w.push_back(width); kept_h.push_back(h);
					if (fno >= max_frame) done = true;
				}
				started = true;
				frame.clear(); line_len.clear(); line.clear(); width = 0;
			}
			prev_hbl = hbl; prev_vbl = vbl;
		});
		if (mclk_count > frame_limit) { printf("FAIL: no frame %d (VBL missing?)\n", max_frame); return 1; }
	}
	if (wf) { fseek(wf, 0, SEEK_SET); wav_header(wf, wav_samples); fclose(wf); }

	int fails = 0;
	// the backup RAM port: one access as kg_bk_ram makes it (mem_req held until mem_ack)
	auto bk = [&](bool we, unsigned addr, unsigned d) -> int {
		top->mem_req = 1; top->mem_we = we; top->mem_addr = addr; top->mem_din = d;
		for (int i = 0; i < 2000; i++) {
			bool ack = false; int q = 0;
			mclk_cycle([&] { if (top->mem_ack) { ack = true; q = top->mem_dout; top->mem_req = 0; } });
			if (ack) return q;
		}
		top->mem_req = 0;
		return -1;
	};
	if (!exp_sav.empty()) {
		for (size_t i = 0; i < exp_sav.size(); i++) {
			int q = bk(false, i, 0);
			if (q != (int)exp_sav[i]) { printf("FAIL: save RAM byte %zu = %d, expected %02x\n", i, q, exp_sav[i]); fails++; }
		}
		bk(true, 100, 0x77);
		int q = bk(false, 100, 0);
		if (q != 0x77) { printf("FAIL: save RAM byte 100 written 77 through the backup port, read %d\n", q); fails++; }
		if (sav_writes != (int)exp_sav.size()) { printf("FAIL: %d save RAM writes of the 68000, expected %zu\n", sav_writes, exp_sav.size()); fails++; }
		printf("save RAM: %zu bytes checked, %d writes of the 68000\n", exp_sav.size(), sav_writes);
	}
	if (top->sdram_errors) { printf("FAIL: %u SDRAM protocol errors\n", top->sdram_errors); fails++; }
	for (auto &e : exp_size)
		if (kept_w[e.f] != e.w || kept_h[e.f] != e.h) { printf("FAIL: frame %d is %d x %d, expected %d x %d\n", e.f, kept_w[e.f], kept_h[e.f], e.w, e.h); fails++; }
	for (auto &e : exp_pix) {
		if (e.x >= kept_w[e.f] || e.y >= kept_h[e.f]) { printf("FAIL: pixel %d,%d outside frame %d\n", e.x, e.y, e.f); fails++; continue; }
		unsigned p = kept[e.f][e.y * kept_w[e.f] + e.x];
		if (p != e.rgb) { printf("FAIL: frame %d pixel %d,%d is %03x, expected %03x\n", e.f, e.x, e.y, p, e.rgb); fails++; }
	}
	printf("audio: min %d max %d\n", amin, amax);
	if (expect_audio && amax - amin < 64) { printf("FAIL: the audio is silent\n"); fails++; }
	printf(fails ? "FAIL\n" : "PASS\n");
	delete top;
	return fails ? 1 : 0;
}
