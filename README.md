# Sega Mega Drive / Genesis core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

Sega Mega Drive / Genesis for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25). A port of
[fpgagen](https://github.com/mist-devel/fpgagen) of MiST.

| Board | Core file | Video | Sound |
|---|---|---|---|
| Karabas Go | `sega.kg` | VGA | I2S DAC (PCM5102) |
| Karabas Mini | `sega.kg` | HDMI | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `sega.kg` | HDMI | HDMI, I2S DAC |

The core file is in `src/`. No games are included: put your own cartridge files on the SD card.

Status: checked on Mini G. The Go and Mini builds have not been run on a board yet.

## Features

- **CPUs:** 68000 (fx68k) and Z80 (T80) at the clocks of the console (MCLK 54.17 MHz, a real console has 53.69 / 53.20).
- **Video:** the VDP of fpgagen (H32 / H40, shadow / highlight, line scroll, DMA), shown as 1024 x 768 at 60 Hz:
  224 or 240 lines three times, both widths stretched to the same 960 pixels. A 50 Hz game repeats a frame now and then.
- **Sound:** YM2612 (jt12) and SN76489 (jt89).
- **Cartridges:** up to 32 MB in the SDRAM, the SSF2 mapper (Super Street Fighter II).
- **Saves:** the battery-backed save RAM of a cartridge (as its header declares it, up to 32 KB) is kept in a `.sav`
  file: `/sega/saves/<game>.sav`. It is loaded before the game starts and written back a second or two after the
  game saves.
- **Region:** Auto (from the cartridge header: USA, else Europe, else Japan), or JP / US / EU in the OSD.
- **Input:** two 3 or 6 button pads from the board's joystick ports and USB pads; the USB keyboard as two pads.

## Files

Put the cartridges in the `sega` folder of the SD card: `.bin`, `.gen` or `.md` (plain ROM images; `.smd` files with
a copier header are not supported). Pick one in the file browser of the OSD (Menu+Esc).

## Keyboard

| | Pad 1 | Pad 2 |
|---|---|---|
| D-pad | arrows | I J K L |
| A B C | Z X C | U O P |
| X Y Z | A S D | 7 8 9 |
| Start | Enter | M |
| Mode | Space | N |

## OSD

| Item | Hotkey | |
|---|---|---|
| Region | Menu+R | Auto / JP / US / EU |
| Pad | Menu+P | 6 button / 3 button (some old games need 3 button pads) |
| Swap joysticks | Menu+J | pad 1 and pad 2 swapped |
| Border | Menu+B | the whole picture of the VDP with its border, smaller (2 x 2) |
| Reset | F12 | |

## Not supported

SVP (Virtua Racing), the EEPROM saves of some cartridges, interlaced modes (shown as normal frames), J-Cart, the
mouse, the light guns and the multitap; the Mega CD and the 32X.

## Building

ISE 14.7: `make -C src` (all boards) or `make -C src minig` (one board). The Go and Mini tops are made from the Mini G
one by `src/tools/mktops.py`. A Verilator simulation is in `src/sim` (`run_checks.sh`). See `CLAUDE.md` and
`docs/PLAN.md` (in Russian).

## Credits

- fpgagen: Gregory Estrade (Torlus), Gyorgy Szombathelyi and the MiST contributors.
- fx68k: Jorge Cwik. T80: Daniel Wallner. jt12 / jt89: Jose Tejada (jotego).
- Port to Karabas: Andy Karpov, 2026.
- xdemax made the first attempt at a Mega Drive core for Karabas (with DeepSeek); this core is
  written anew, but the lessons of that attempt (the boot interface of fpgagen, the VRAM / DMA
  priorities, the video path) went into its plan.

## License

GNU GPL v3 (`LICENSE`); the imported sources keep their own headers.
