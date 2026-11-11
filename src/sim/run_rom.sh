#!/bin/bash
# Runs a ROM (a game, user file: never in the repo) in the simulation and writes frames / audio:
#   ./run_rom.sh FILE [harness options], e.g. ./run_rom.sh ~/Downloads/karabas-sd-sega/sega/game.bin
#     --frames 120 --ppm-every 30 --ppm build/game --wav build/game.wav
# About 4 s of real time per frame (60 frames = 1 s of the Genesis = 4 min): ask before long runs.
set -e
cd "$(dirname "$0")"
./build.sh
ROM=$(realpath "$1"); shift
echo "JOB-STAGE: sim"
cd ..
exec sim/build/obj/Vsim_top --rom "$ROM" "$@"
