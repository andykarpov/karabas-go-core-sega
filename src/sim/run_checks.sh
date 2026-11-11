#!/bin/bash
# The quick checks of the simulation (about 30 s after the build): the test ROM of mkrom.py through
# the boot interface of fpgagen, 3 frames.
#   - frame 2 is 320 x 224 (H40, V28: the VDP registers were written)
#   - the four bands have their colours (CRAM, tiles, plane A, 68000 through the os_rom of fpgagen
#     into the cartridge)
#   - the PSG tone is on the audio output (the Z80 reset released, jt89 + jt12_genmix)
#   - no SDRAM protocol error (sdram_model.v)
set -e -o pipefail
cd "$(dirname "$0")"
./build.sh
python3 -I mkrom.py build/test.bin
echo "JOB-STAGE: sim"
cd ..
sim/build/obj/Vsim_top --rom sim/build/test.bin --frames 3 --ppm sim/build/check --wav sim/build/check.wav \
	--expect-size 2,320,224 \
	--expect-pixel 2,100,10,e00 --expect-pixel 2,100,60,0e0 --expect-pixel 2,100,120,00e \
	--expect-pixel 2,100,200,eee --expect-pixel 2,0,0,e00 --expect-pixel 2,319,223,eee \
	--expect-audio | grep -vE '^\[[0-9]+\] MRST'
