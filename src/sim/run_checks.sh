#!/bin/bash
# The checks of the simulation (about 1.5 min after the build):
# tb_loader (sega_loader against a model of the boot FSM of fpgagen, < 1 s), tb_fb (sega_fb on an SRAM
# model with a synthetic VDP, H40 and H32 at once, ~1 min: every pixel of a 1024 x 768 frame), then the
# test ROM of mkrom.py on the whole Genesis through the boot interface of fpgagen, 3 frames:
#   - frame 2 is 320 x 224 (H40, V28: the VDP registers were written)
#   - the four bands have their colours (CRAM, tiles, plane A, 68000 through the os_rom of fpgagen
#     into the cartridge)
#   - the PSG tone is on the audio output (the Z80 reset released, jt89 + jt12_genmix)
#   - no SDRAM protocol error (sdram_model.v)
# and the line scroll ROM (mkrom.py --linescroll, check_linescroll.py): each line at its own offset
set -e -o pipefail
cd "$(dirname "$0")"
mkdir -p build
echo "JOB-STAGE: tb"
iverilog -g2005 -o build/tb_loader tb_loader.v ../rtl/karabas/sega_loader.v
vvp -n build/tb_loader | grep -E 'FAIL|PASS|errors' | tee build/tb_loader.log
iverilog -g2005 -o build/tb_fb tb_fb.v ../rtl/karabas/sega_fb.v ../../modules/rtl/mem/kg_sdpram.v
vvp -n build/tb_fb > build/tb_fb_h40.log & vvp -n build/tb_fb +h32 > build/tb_fb_h32.log &
wait
grep -hE 'FAIL|tb_fb' build/tb_fb_h40.log build/tb_fb_h32.log
if grep -q FAIL build/tb_loader.log build/tb_fb_h40.log build/tb_fb_h32.log; then echo FAIL; exit 1; fi
./build.sh
python3 -I mkrom.py build/test.bin
echo "JOB-STAGE: sim"
cd ..
sim/build/obj/Vsim_top --rom sim/build/test.bin --frames 3 --ppm sim/build/check --wav sim/build/check.wav \
	--expect-size 2,320,224 \
	--expect-pixel 2,100,10,e00 --expect-pixel 2,100,60,0e0 --expect-pixel 2,100,120,00e \
	--expect-pixel 2,100,200,eee --expect-pixel 2,0,0,e00 --expect-pixel 2,319,223,eee \
	--expect-audio | grep -vE '^\[[0-9]+\] MRST'
# the line scroll (HSCROLL mode 3, one entry per line): every line of frame 2 shifted by its own value
python3 -I sim/mkrom.py sim/build/ls.bin --linescroll
sim/build/obj/Vsim_top --rom sim/build/ls.bin --frames 3 --ppm sim/build/ls | grep -E '^(FAIL|PASS)'
python3 -I sim/check_linescroll.py sim/build/ls_002.ppm
