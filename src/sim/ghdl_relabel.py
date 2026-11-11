#!/usr/bin/env python3
"""Copies a VHDL file with every instance label X renamed to X_i (a label line followed by a port or
generic map). For the simulation only: ghdl --synth --out=verilog (4.1) lowercases the names and
names the outputs of instance X "x_<port>", which collides with the signals of fpgagen named the
same way (instance t80 + output mreq_n vs. signal T80_MREQ_N). The RTL itself is not changed.

usage: ghdl_relabel.py in.vhd out.vhd
"""
import re, sys
src,dst=sys.argv[1],sys.argv[2]
lines=open(src).read().split('\n')
out=[]
pat=re.compile(r'^(\s*)([A-Za-z]\w*)(\s*:\s*(?:entity\s+)?(?:work\.)?\w+\s*(?:--.*)?)$')
for i,l in enumerate(lines):
    m=pat.match(l)
    nxt=next((x for x in lines[i+1:i+4] if x.strip()),'')
    if m and m.group(2).lower() not in ('signal','variable','constant','begin') and re.match(r'\s*(port|generic)\s+map',nxt,re.I):
        l=m.group(1)+m.group(2)+'_i'+m.group(3)
    out.append(l)
open(dst,'w').write('\n'.join(out))
