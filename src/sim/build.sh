#!/bin/bash
# Builds the verilator model of sim_top.v: the VHDL of sega.prj through ghdl --synth --out=verilog
# (USE_SVP false), the Verilog of sega.prj (sv2v, jt12, jt89), sdram_model.v, sim_top.v and the
# harness sim_sega.cpp. Output in src/sim/build/ (obj/Vsim_top). Rebuilds only when a source is newer.
set -e
cd "$(dirname "$0")"
SRC=..
B=build
HERE=$PWD
mkdir -p $B/vhd
VHDL=$(sed -n 's/^vhdl work "\(.*\)"/\1/p' $SRC/sega.prj)
VLOG=$(sed -n 's/^verilog work "\(.*\)"/\1/p' $SRC/sega.prj)
OWN="sim/sdram_model.v sim/sim_top.v"
GEN=$B/fpgagen.v
newer() { [ ! -e "$1" ] || [ -n "$(cd $SRC && find $2 -newer sim/$1 2>/dev/null)" ]; }

if newer $GEN "$VHDL sim/build.sh sim/ghdl_relabel.py sim/ghdl_fixup.py"; then
	echo "JOB-STAGE: ghdl"
	rm -f $B/vhd/*
	L=""
	for f in $VHDL; do o=$B/vhd/$(basename $f); python3 -I ghdl_relabel.py $SRC/$f $o; L="$L $o"; done
	(cd $B && ghdl --synth --out=verilog --std=08 -frelaxed -fsynopsys -Wno-shared -Wno-hide -Wno-binding \
		-gUSE_SVP=false ${L//$B\//} -e fpgagen_sdram_top 2> ghdl.log) > $GEN.tmp
	grep -q error $B/ghdl.log && { grep error $B/ghdl.log | head; exit 1; }
	python3 -I ghdl_fixup.py $GEN.tmp $GEN
	rm -f $GEN.tmp
	rm -f $B/*.cf
fi

EXE=$B/obj/Vsim_top
if newer $EXE "$VLOG $OWN sim/$GEN sim/sim_sega.cpp sim/build.sh"; then
	echo "JOB-STAGE: verilator"
	(cd $SRC && verilator -O3 --x-assign fast --x-initial fast --default-language 1364-2005 \
		-Wno-fatal -Wno-lint -Wno-style -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-WIDTH \
		-Wno-CASEINCOMPLETE --no-timing --top-module sim_top -Mdir sim/$B/obj --cc sim/$GEN $VLOG $OWN \
		--exe $HERE/sim_sega.cpp -o Vsim_top > sim/$B/verilator.log 2>&1) || { grep -E '%Error' $B/verilator.log | head -20; exit 1; }
	echo "JOB-STAGE: c++"
	make -s -j8 -C $B/obj -f Vsim_top.mk OPT_FAST=-O2 > $B/make.log 2>&1 || { tail -30 $B/make.log; exit 1; }
fi
