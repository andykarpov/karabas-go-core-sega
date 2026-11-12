# Ядро Sega Mega Drive / Genesis для Karabas Go / Mini / Mini G

[English version](README.md)

Sega Mega Drive / Genesis для плат семейства Karabas Go (Xilinx Spartan-6 XC6SLX25). Порт
[fpgagen](https://github.com/mist-devel/fpgagen) с MiST.

| Плата | Файл ядра | Видео | Звук |
|---|---|---|---|
| Karabas Go | `sega.kg` | VGA | I2S ЦАП (PCM5102) |
| Karabas Mini | `sega.kg` | HDMI | HDMI, аналоговый выход (сигма-дельта) |
| Karabas Mini G | `sega.kg` | HDMI | HDMI, I2S ЦАП |

Файл ядра лежит в `src/`. Игр в комплекте нет: положите свои файлы картриджей на SD-карту.

Состояние: проверено на Mini G. Сборки для Go и Mini на плате ещё не запускались.

## Возможности

- **Процессоры:** 68000 (fx68k) и Z80 (T80) на частотах приставки (MCLK 54,17 МГц, у настоящей 53,69 / 53,20).
- **Видео:** VDP из fpgagen (H32 / H40, shadow / highlight, построчный скролл, DMA), вывод 1024 × 768 @ 60 Гц:
  224 или 240 строк, каждая три раза, обе ширины растянуты до одних и тех же 960 точек. Игра на 50 Гц иногда
  повторяет кадр.
- **Звук:** YM2612 (jt12) и SN76489 (jt89).
- **Картриджи:** до 32 МБ в SDRAM, маппер SSF2 (Super Street Fighter II).
- **Сохранения:** save RAM картриджа с батарейкой (как её описывает заголовок, до 32 КБ) хранится в файле `.sav`:
  `/sega/saves/<игра>.sav`. Он читается до старта игры и записывается через секунду-две после того, как игра
  сохранилась.
- **Регион:** Auto (по заголовку картриджа: США, иначе Европа, иначе Япония) или JP / US / EU в OSD.
- **Управление:** два пада на 3 или 6 кнопок — разъёмы джойстиков платы и USB-геймпады; USB-клавиатура как два пада.

## Файлы

Картриджи кладутся в папку `sega` на SD-карте: `.bin`, `.gen` или `.md` (чистые образы ROM; файлы `.smd` с
заголовком копировщика не поддерживаются). Выбираются в файловом браузере OSD (Menu+Esc).

## Клавиатура

| | Пад 1 | Пад 2 |
|---|---|---|
| Крестовина | стрелки | I J K L |
| A B C | Z X C | U O P |
| X Y Z | A S D | 7 8 9 |
| Start | Enter | M |
| Mode | пробел | N |

## OSD

| Пункт | Клавиши | |
|---|---|---|
| Region | Menu+R | Auto / JP / US / EU |
| Pad | Menu+P | 6 кнопок / 3 кнопки (некоторым старым играм нужен 3-кнопочный пад) |
| Swap joysticks | Menu+J | пады 1 и 2 меняются местами |
| Border | Menu+B | вся картинка VDP с рамкой, мельче (2 × 2) |
| Reset | F12 | |

## Не поддерживается

SVP (Virtua Racing), сохранения в EEPROM у части картриджей, режимы interlace (выводятся как обычные кадры), J-Cart,
мышь, световые пистолеты и мультитап; Mega CD и 32X.

## Сборка

ISE 14.7: `make -C src` (все платы) или `make -C src minig` (одна плата). Верхи Go и Mini делаются из верха Mini G
скриптом `src/tools/mktops.py`. Симуляция на Verilator — в `src/sim` (`run_checks.sh`). Подробности — `CLAUDE.md` и
`docs/PLAN.md`.

## Авторы

- fpgagen: Gregory Estrade (Torlus), Gyorgy Szombathelyi и участники MiST.
- fx68k: Jorge Cwik. T80: Daniel Wallner. jt12 / jt89: Jose Tejada (jotego).
- Порт на Karabas: Andy Karpov, 2026.
- xdemax первым попробовал сделать ядро Mega Drive для Karabas (с DeepSeek); это ядро написано заново, но уроки
  той попытки (загрузочный интерфейс fpgagen, приоритеты VRAM / DMA, видеотракт) вошли в его план.

## Лицензия

GNU GPL v3 (`LICENSE`); импортированные исходники сохраняют свои заголовки.
