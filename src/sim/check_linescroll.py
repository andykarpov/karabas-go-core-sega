#!/usr/bin/env python3
"""Checks a frame of the --linescroll test ROM (mkrom.py): line y of the 320 x 224 frame has exactly
one red pixel, at x = (7 y) mod 300. usage: check_linescroll.py frame.ppm"""
import sys
d = open(sys.argv[1], 'rb').read()
parts = d.split(b'\n', 3)
w, h = map(int, parts[1].split())
px = parts[3]
bad = 0
for y in range(h):
    reds = [x for x in range(w) if px[(y * w + x) * 3] > 128 and px[(y * w + x) * 3 + 1] < 64]
    want = (7 * y) % 300
    if reds != [want]:
        if bad < 10:
            print('FAIL: line %d red at %s, expected [%d]' % (y, reds[:8], want))
        bad += 1
print('check_linescroll: %d x %d, %d bad lines' % (w, h, bad))
print('FAIL' if bad or h != 224 else 'PASS')
sys.exit(1 if bad or h != 224 else 0)
