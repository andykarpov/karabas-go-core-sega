# Sega Mega Drive / Genesis core for Karabas Go / Mini / Mini G

A port of [fpgagen](https://github.com/mist-devel/fpgagen) (MiST) to the Karabas
boards (Xilinx Spartan-6 XC6SLX25). Work in progress: see `docs/PLAN.md` (in Russian).

## Credits

- fpgagen: Gregory Estrade (Torlus), Gyorgy Szombathelyi and the MiST contributors.
- fx68k: Jorge Cwik. T80: Daniel Wallner. jt12 / jt89: Jose Tejada (jotego).
- Port to Karabas: Andy Karpov, 2026.
- xdemax made the first attempt at a Mega Drive core for Karabas (with DeepSeek); this core is
  written anew, but the lessons of that attempt (the boot interface of fpgagen, the VRAM / DMA
  priorities, the video path) went into its plan.

## License

GNU GPL v3 (`LICENSE`); the imported sources keep their own headers.
