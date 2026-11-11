# План ядра Sega Mega Drive / Genesis для Karabas Go / Mini / Mini G

Цель: Sega Mega Drive / Genesis (68000 7,67 МГц, Z80 3,58 МГц, VDP 315-5313, YM2612 + SN76489, картриджи до 4 МБ и больше с маппером SSF2, save RAM / EEPROM, пады на 3 и 6 кнопок) на платах Karabas (XC6SLX25, ISE 14.7). Основа — [fpgagen](https://github.com/mist-devel/fpgagen) MiST (Gregory Estrade, Gyorgy Szombathelyi). Ядро делаем с нуля; из попытки deepseek (`~/Downloads/Telegram Desktop/karabas-go-core-sega.zip`) берём только уроки. Файлы идут через прошивку (OSD, `FL`, `kg_bk_ram`): загрузчика и soft-CPU в ядре нет. Имя `sega` (`sega.kg`, папка `/sega`), репозиторий `andykarpov/karabas-go-core-sega`, публичный.

## Что изучено (2026-11-11)

| Проект | Состояние | Что берём |
|---|---|---|
| [mist-devel/fpgagen](https://github.com/mist-devel/fpgagen) a51ca7d (2026-03) | основа: VHDL, самый свежий VDP (правки по Nuked-MD 2023-12, «better blanks» 2023-12), работает на MiST (EP3C25 — ближе всего к LX25), save RAM / EEPROM, J-Cart, маппер SSF2, SVP | `src/` целиком; сабмодули fx68k 9fd1c83, T80 7126b13, jt12 7e66c41, jt89 5050cfc |
| [MiSTer-devel/Genesis_MiSTer](https://github.com/MiSTer-devel/Genesis_MiSTer) adc0c42 (2023-02, архив) | классический MiSTer: тот же VDP, но версии 2021; мультитапы, мышь, читы, фильтры звука | донор опций (Ф5), сверка |
| [nand2mario/mdtang](https://github.com/nand2mario/mdtang) 903d30c (2025-05) | Genesis_MiSTer, переведённый на Verilog, для Tang Mega 60K / 138K: VRAM в BRAM, Z80 на половине MCLK, кадровый буфер в 720p, симуляция в Verilator | идеи для кадрового буфера (масштаб 256 / 320 → 960 счётчиком Брезенхэма) и харнесса Verilator |
| [MiSTer-devel/MegaDrive_MiSTer](https://github.com/MiSTer-devel/MegaDrive_MiSTer) 8f2716f | теперь Nuked-MD, модель по вентилям | для LX25 слишком большое, не берём |
| deepseek (архив, 2026-11-07..11) | fpgagen, только Mini G, PAL Earthworm Jim показывает картинку; dual-mode не сошёлся по таймингу (score 686520); NTSC не работает | только уроки, см. ниже |

### Уроки попытки deepseek

- `ext_reset_n` fpgagen сбрасывает его загрузочный автомат: если держать его в 0 всю загрузку, ROM не пишется (первое слово ROM случайное). Нужен короткий импульс в начале, а CPU держит в сбросе сам загрузчик fpgagen до `ext_bootdone`.
- Порядок приоритетов как в MiST: VRAM > VRAM32 > save RAM. При VRAM32 впереди DMA fill не завершается.
- 68K RAM у них жила по `0x400000`, а это пересекается с ROM 4 МБ. Берём карту SDRAM MiST, где банки разнесены.
- VRAM в SRAM с доступом в 3 такта на 53,6 МГц, SDRAM на 53 МГц вместо 108, line buffer с самодельным genlock под 576p / 600p и цепочка PLL → PLL → DCM → BUFGMUX дали дрожание, артефакт в 4 пикселя слева и неработающий NTSC. Мы так не делаем: память как в MiST, видео через кадровый буфер, один PLL.
- Отладочные порты внутри VDP и сотни `.kg` / `.bin` в git — тоже нет: диагностика в симуляции, а в git только исходники и релизные `.bin`.
- Без симуляции они неделями ловили ошибки по снимкам HDMI. У нас Verilator-харнесс с Ф1.

### Ресурсы (оценка)

Цифры из замеров deepseek (XST 14.7, xc6slx25-2): `fpgagen_top` целиком 14 078 LUT (93 %), 10 RAMB16 + 13 RAMB8, 1 DSP48; без SVP около 11,8 тыс. LUT. С обвязкой платы — 12 035 LUT (80 %) и 98 % слайсов. По модулям: fx68k 3735 LUT, VDP 2321, T80 2240, jt12 1091. Значит, SVP не влезает, а запас по слайсам очень мал. Это проверяет Ф0.

## Решения

Пользователь (2026-11-11): основа fpgagen MiST, ядро с нуля (из deepseek — только уроки и то, что подойдёт); **память как в MiST, SRAM под кадровый буфер**; **видео 1024 × 768 @ 60**; имя `sega`, публичный репозиторий (создал пользователь).

1. **Основа** — `src/` fpgagen как есть: `src/rtl/fpgagen/`, сабмодули копиями в `src/rtl/fx68k`, `src/rtl/T80`, `src/rtl/jt12`, `src/rtl/jt89`. SystemVerilog (fx68k, `sdram.sv`) через `sv2v` в `src/rtl/sv2v/`, как в atarist. Правки для XST — с пометкой `-- karabas:` / `// karabas:`. Без SVP (`USE_SVP` / generate, как сделали в deepseek).
2. **Память — как в MiST.** ROM (до 32 МБ, SSF2), 68K RAM 64 КБ, VRAM 64 КБ (+ чтение VRAM32) и save RAM лежат в SDRAM. Контроллер — родной `sdram.sv` fpgagen на 108 МГц. На всех трёх платах SDRAM 16-битная, как у MiST. Z80 RAM, CRAM, VSRAM и кэш спрайтов — в BRAM, как в upstream.
3. **Клоки** — один `kg_pll` от 50 МГц с VCO 650 МГц: MCLK = 650 / 12 = 54,17 МГц (у MiST 54, у настоящей приставки 53,69 / 53,20: +0,9 %, тон звука выше на 0,9 %), SDRAM = 650 / 6 = 108,3 МГц, видео 650 / 10 = 65 МГц, TMDS 650 / 2 = 325 МГц. PAL и NTSC, как в MiST, работают на одном MCLK. Если отклонение в 0,9 % окажется заметным — второй PLL под видео, а MCLK ближе к 53,69.
4. **Видео: кадровый буфер в SRAM 4 МБ.** Пиксели VDP (RGB444, `CE_PIX`) пишутся в SRAM на клоке ядра; вывод — **1024 × 768 @ 60 Гц (65 МГц)** со строковым буфером в BRAM. По вертикали ×3: 224 → 672, 240 (V30, PAL) → 720. По горизонтали H40 (320) ×3 = 960, H32 (256) растягивается до тех же 960 (×3,75 счётчиком Брезенхэма, как в mdtang), так что ширина картинки в обоих режимах одинаковая, как на телевизоре. Тройная буферизация убирает разрывы; кадр 50 / 59,9 Гц на выходе 60 Гц — с повтором или пропуском кадра. Растр стандартный, синхроимпульсы есть всегда (монитор пользователя другое не принимает). Interlace (Sonic 2 в режиме двух игроков) — Ф3. Go — VGA тем же растром.
5. **Звук** — `jt12` (FM) + `jt89` (PSG) и микшер fpgagen; 48 кГц в HDMI (как в macplus), PCM5102 / сигма-дельта.
6. **Ввод** — пады платы и USB-геймпады из `kg_mcu` (биты джойстика) → два `gen_ctrl` (3 / 6 кнопок); клавиатура как два пада, как в SNES / NES.
7. **Картриджи** — `FL` `/sega/*.bin|.gen|.md`. Байты `kg_mcu_loader` собираются в слова и идут в загрузчик fpgagen (`ext_data` / `ext_data_req` / `ext_bootdone`), как `data_io` у MiST. Регион Auto (по заголовку ROM) / JP / US / EU — опция OSD. Save RAM / EEPROM → `.sav` через `kg_bk_ram` (как в NES).
8. **Свой верх платы**, общий код через modules (`kg_mcu`, OSD, HDMI, PCM5102, `kg_bk_ram`), Makefile. Первой делаем Mini G, затем Go и Mini. Mini G2: T3 = 0 (SDRAM ~CS).

## Архитектура

```
 fpgagen_top ├── fx68k (MCLK/7 по CE) ─┐
             ├── T80 (MCLK/15 по CE) ──┼── шина / арбитр ── sdram.sv 108 МГц ── ROM, 68K RAM, save RAM
             ├── VDP ── VRAM / VRAM32 ─┘                                     └── VRAM
             │    └── пиксель RGB444 ── кадровый буфер SRAM ── вывод 1024×768@60 (×3) ── OSD ── HDMI / VGA
             ├── jt12 + jt89 ── микшер ──────────────────────────────── HDMI / PCM5102 / сигма-дельта
             ├── gen_io ── gen_ctrl × 2 ── kg_mcu (пады, USB, клавиатура)
             └── загрузчик ext_data ← sega_loader ← kg_mcu_loader (FL)
                 save RAM / EEPROM ↔ kg_bk_ram (.sav)
```

## Фазы

Ветка и один PR на фазу, слияние в конце фазы.

- **Ф0. Импорт и fit.** fpgagen a51ca7d и сабмодули без правок, `src/tools/sv2v.sh`, правки XST (пакеты VHDL с именами модулей Verilog, `entity work.`, `others` в case, `USE_SVP`), Makefile, черновик `core.json`. `make sega-xst` — ядро отдельно (`fpgagen_sdram_top` с `sdram.sv`): LUT / FF / слайсы / RAMB16 / частота на 54 и 108 МГц. Решение по запасу: что ужать, если не влезает.
  **Итог Ф0 (2026-11-11):** `fpgagen_sdram_top` с `sdram.sv`, без SVP — **11 824 LUT (78 %)**, 6963 FF (23 %), 16 RAMB16 (30 %), XST 2 мин. Оценка XST по клокам: SDR_CLK 119,8 МГц (нужно 108,3) — с запасом; MCLK 50,4 МГц (нужно 54,17), худший путь внутри T80 (`t80/u0/IR` → `F`, 19 уровней). Ядро T80 (`u0`) защёлкивается по `CEN` раз в 15 тактов MCLK (`ZCLK_ENA` на счёте 0, `ZCLK_nENA` на 8), поэтому пути u0 → u0 многотактовые: в Ф2 — `FROM:TO` на 2 периода MCLK в ucf и проверка trce после PAR; если не хватит, Z80 на половине MCLK, как в mdtang. На обвязку платы (kg_mcu, OSD, HDMI, кадровый буфер) остаётся около 3,2 тыс. LUT; ожидаем 88–92 % LUT, слайсы покажет map в Ф2.
  Правки для XST (все с пометкой `karabas:`): пути `.mem` в fx68k; `sdram.sv` — `inout wire` вместо `inout reg` (sv2v превращал его в `always`, который XST не берёт); пакеты `sdram_pkg` / `jt12_pkg` / `jt89_pkg`; `cs_n` в компоненте `jt89`; `entity work.` у `fpgagen_top` и `SVP`; `others` в case маппера SSF2; `obj_cache` — выводимая RAM вместо altsyncram; внутренняя VRAM (altsyncram) убрана, `INTERNAL_VRAM` должен быть false; generic `USE_SVP` (false: SVP не строится, `svp_en` = 0; файлы SVP в prj только для разбора — XST читает и ложный generate). ghdl (для Ф1) ещё ругается на `to_slv` в `gen_cart.vhd` и преобразование типов на `inout` DQ в `fpgagen_sdram_top.vhd` — разобрать в Ф1.
- **Ф1. Симуляция.** VHDL переводим в Verilog через `ghdl --synth` (только для симуляции, синтез XST — с VHDL), дальше Verilator: модель SDRAM, загрузка ROM через `ext_data`, кадры в PPM, звук в WAV. Проверки на секунды: тестовый ROM рисует экран и выдаёт звук. Длинные прогоны игр — только с согласия.
- **Ф2. Mini G.** PLL, `sdram.sv`, загрузчик `FL`, кадровый буфер в SRAM и вывод 1024 × 768, HDMI со звуком, пады и клавиатура, OSD (регион, 3 / 6 кнопок, сброс). Первый запуск на плате: заставка SEGA и игра.
- **Ф3. Сохранения и режимы.** Save RAM / EEPROM в `.sav`, interlace, рамка, CRAM dots, переключение региона на лету.
- **Ф4. Другие платы и релиз.** Верхи Go и Mini, README / GUIDE, релиз в karabas-go.
- **Ф5. Дополнения.** J-Cart, мышь Sega и световой пистолет (`gen_lightgun`), мультитап (Genesis_MiSTer); SVP — только если останется место (вряд ли).
