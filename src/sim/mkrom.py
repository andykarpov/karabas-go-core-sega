#!/usr/bin/env python3
"""Makes the test ROM of the simulation (no assembler needed: the few 68000 instructions it uses are
encoded here). The program sets the VDP up (mode 5, H40, V28, plane A at C000), writes a palette and
four tiles of one colour each, fills plane A with four horizontal bands of 7 cell rows (56 lines):
colour 1 red, 2 green, 3 blue, 4 white, releases the Z80 reset, sets PSG tone channel 0 to about
440 Hz at full volume and loops. A frame is then 320 x 224 with the bands at lines 0, 56, 112, 168.

usage: mkrom.py out.bin
"""
import struct, sys

code = bytearray()

def w(*words):
    for x in words:
        code.extend(struct.pack('>H', x & 0xffff))

def l(x):
    code.extend(struct.pack('>I', x & 0xffffffff))

VDP_DATA, VDP_CTRL, PSG = 0xC00000, 0xC00004, 0xC00011

def lea_a0(addr): w(0x41F9); l(addr)
def lea_a1(addr): w(0x43F9); l(addr)
def vdp_reg(r, v): w(0x32BC, 0x8000 | (r << 8) | v)             # move.w #$8rvv,(a1)
def ctrl_l(x): w(0x22BC); l(x)                                   # move.l #x,(a1)
def data_w(x): w(0x30BC, x)                                      # move.w #x,(a0)
def move_w_d0(n): w(0x303C, n)                                   # move.w #n,d0
def psg(b): w(0x13FC, b); l(PSG)                                 # move.b #b,PSG

def fill(value, count):
    """move.w #count-1,d0 ; loop: move.w #value,(a0) ; dbra d0,loop"""
    move_w_d0(count - 1)
    data_w(value)
    w(0x51C8, 0xFFFA)                                            # dbra d0,*-4

def vram_write(addr):
    return 0x40000000 | ((addr & 0x3FFF) << 16) | (addr >> 14)

w(0x46FC, 0x2700)                                                # move.w #$2700,sr
lea_a0(VDP_DATA)
lea_a1(VDP_CTRL)
for r, v in [(0, 0x04), (1, 0x44), (2, 0x30), (3, 0x00), (4, 0x07), (5, 0x00), (7, 0x00),
             (10, 0xFF), (11, 0x00), (12, 0x81), (13, 0x3F), (15, 0x02), (16, 0x01), (17, 0x00), (18, 0x00)]:
    vdp_reg(r, v)
# palette 0: black, red, green, blue, white (CRAM: 0000 BBB0 GGG0 RRR0)
ctrl_l(0xC0000000)
for c in [0x000, 0x00E, 0x0E0, 0xE00, 0xEEE]:
    data_w(c)
# tiles 1..4: every pixel colour n (8 x 8 x 4 bit = 16 words)
ctrl_l(vram_write(0x0020))
for n in range(1, 5):
    fill(0x1111 * n, 16)
# plane A at C000, 64 x 32 cells: bands of 7 rows of tiles 1..4
ctrl_l(vram_write(0xC000))
for n in range(1, 5):
    fill(n, 64 * 7)
# horizontal and vertical scroll 0 (VRAM FC00, VSRAM 0)
ctrl_l(vram_write(0xFC00))
fill(0, 448)
ctrl_l(0x40000010)                                               # VSRAM write 0
fill(0, 40)
# release the Z80 reset (A11200 = 0100): the sound mixer of fpgagen (jt12_genmix, PSG included) is
# held in reset with the Z80; the Z80 then runs the zeros of its RAM (NOPs)
w(0x33FC, 0x0100); l(0xA11200)                                   # move.w #$0100,$A11200
# PSG tone 0: n = 0xFE (3.58 MHz / 32 / 254 = 440 Hz), attenuation 0
psg(0x80 | 0x0E)
psg(0x0F)
psg(0x90)
w(0x60FE)                                                        # bra.s *

rom = bytearray(b'\xff' * 0x10000)
struct.pack_into('>II', rom, 0, 0x00FFFE00, 0x00000200)          # SSP, PC
for v in range(2, 64):
    struct.pack_into('>I', rom, v * 4, 0x00000200)
hdr = (b'SEGA MEGA DRIVE ' + b'(C)KRBS 2026.NOV' + b'KARABAS SIM TEST'.ljust(48) +
       b'KARABAS SIM TEST'.ljust(48) + b'GM 00000000-00' + b'\0\0' + b'J'.ljust(16) +
       struct.pack('>IIII', 0, 0xFFFF, 0xFF0000, 0xFFFFFF))
rom[0x100:0x100 + len(hdr)] = hdr
rom[0x1F0:0x1F3] = b'JUE'
rom[0x200:0x200 + len(code)] = code
open(sys.argv[1], 'wb').write(rom)
