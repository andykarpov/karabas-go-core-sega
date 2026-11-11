#!/usr/bin/env python3
"""Post-processing of the Verilog that ghdl --synth (4.1) writes for fpgagen_sdram_top, for the
simulation only:
- an escaped name with a prefix ("u0_\\reg ") is no legal Verilog: made a plain name (reg_esc);
- the inout DRAM_DQ goes to the Verilog sdram controller (a black box for ghdl), and ghdl makes that
  a one way "assign DRAM_DQ = <controller port>": the controller never sees the read data. The
  controller port is connected to DRAM_DQ itself instead.

usage: ghdl_fixup.py in.v out.v
"""
import re, sys
s = open(sys.argv[1]).read()
s = re.sub(r'([A-Za-z0-9_])\\([A-Za-z0-9_]+) ', r'\1\2_esc ', s)
n = len(re.findall(r'^\s*assign DRAM_DQ = \w+;\n', s, re.M))
assert n == 1, 'assign DRAM_DQ: %d' % n
s = re.sub(r'^\s*assign DRAM_DQ = \w+;\n', '', s, flags=re.M)
assert s.count('.SDRAM_DQ(sdc_i_SDRAM_DQ)') == 1
s = s.replace('.SDRAM_DQ(sdc_i_SDRAM_DQ)', '.SDRAM_DQ(DRAM_DQ)')
open(sys.argv[2], 'w').write(s)
