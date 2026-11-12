#!/bin/bash
# Converts the SystemVerilog of the upstream (fx68k, the sdram controller of fpgagen) to Verilog-2001
# for XST with sv2v (/opt/sv2v/sv2v): one file per module in rtl/sv2v/. Tops: fx68k, sdram.
# rtl/sv2v/ is generated and in git; change the sources (with a "karabas:" comment), then run this.
set -e
cd "$(dirname "$0")/../rtl"
SV2V=${SV2V:-/opt/sv2v/sv2v}
SRC="fx68k/fx68k.sv fx68k/fx68kAlu.sv fx68k/uaddrPla.sv fpgagen/sdram.sv"
rm -rf sv2v && mkdir sv2v
$SV2V --top=fx68k --top=sdram $SRC -w sv2v 2>&1 | grep -v -E '^\s*$|Warning: Number literal|^ *[0-9]* \||^\s*\|' || true
ls sv2v | wc -l
# sega.prj: the Genesis alone (fpgagen_sdram_top, make sega-xst) and the source list of the simulations.
# VHDL packages first. The SVP is parsed (XST reads a false generate too) but not built (USE_SVP false).
JT12="jt12.v jt12_top.v jt12_acc.v jt12_single_acc.v jt12_eg.v jt12_eg_cnt.v jt12_eg_comb.v jt12_eg_step.v
 jt12_eg_pure.v jt12_eg_final.v jt12_eg_ctrl.v jt12_exprom.v jt12_kon.v jt12_lfo.v jt12_div.v jt12_mod.v
 jt12_op.v jt12_csr.v jt12_pg.v jt12_pg_inc.v jt12_pg_dt.v jt12_pg_sum.v jt12_pg_comb.v jt12_pm.v
 jt12_logsin.v jt12_reg.v jt12_sh.v jt12_sh_rst.v jt12_sh24.v jt12_sumch.v jt12_timers.v
 jt12_pcm_interpol.v jt12_mmr.v jt12_dout.v jt12_rst.v adpcm/jt10_adpcm_div.v mixer/jt12_genmix.v
 mixer/jt12_decim.v mixer/jt12_interpol.v mixer/jt12_comb.v mixer/jt12_fm_uprate.v"
JT89="jt89.v jt89_noise.v jt89_vol.v jt89_mixer.v jt89_tone.v"
VHDL="fpgagen/sdram.vhd jt12/hdl/jt12.vhd jt89/hdl/jt89.vhd fpgagen/vdp_common.vhd
 T80/T80_Pack.vhd T80/T80_ALU.vhd T80/T80_MCode.vhd T80/T80_Reg.vhd T80/T80.vhd T80/T80pa.vhd
 fpgagen/DualPortRAM.vhd fpgagen/SinglePortRAM.vhd fpgagen/obj_cache.vhd fpgagen/vdp.vhd
 fpgagen/gen_io.vhd fpgagen/gen_cart.vhd fpgagen/os_rom.vhd
 fpgagen/SVP/SSP160x_PKG.vhd fpgagen/SVP/dpram_dclk.vhd fpgagen/SVP/SSP160x.vhd fpgagen/SVP/SVP.vhd
 fpgagen/fpgagen_top.vhd
 fpgagen/fpgagen_sdram_top.vhd"
{ for f in sv2v/*.v; do echo "verilog work \"rtl/$f\""; done
  for f in $JT12; do echo "verilog work \"rtl/jt12/hdl/$f\""; done
  for f in $JT89; do echo "verilog work \"rtl/jt89/hdl/$f\""; done
  for f in $VHDL; do echo "vhdl work \"rtl/$f\""; done; } > ../sega.prj
# karabas_minig.prj: the board modules (as core-macplus), the Genesis, the glue of the board
MODS="mem/kg_spram.v mem/kg_tdpram.v mem/kg_sdpram.v mem/kg_fifo.v mem/kg_async_fifo.v
 ctl/kg_soft_switches.v ctl/kg_sync.v mcu/kg_spi_slave.v mcu/kg_burst_rx.v mcu/kg_mcu_link.v
 mcu/kg_mcu_ctl.v mcu/kg_mcu_hid.v mcu/kg_mcu_loader.v mcu/kg_mcu_rtc.v mcu/kg_mcu_uart.v
 mcu/kg_mcu_img.v mcu/kg_mcu_debug.v mcu/kg_mcu_esp.v mcu/img_sdc.v mcu/kg_bk_ram.v mcu/kg_mcu.v clk/kg_pll.v
 clk/kg_dcm.v audio/kg_pcm5102.v video/osd/kg_pix_doubler.v video/osd/kg_osd_overlay.v"
HDMI="zhdmi_tmds_encoder zhdmi_signaling zhdmi_island_encoder zhdmi_audio_packetizer zhdmi_packet_gen
 zhdmi_tmds_serializer_spartan6 dvi_encoder dvi zhdmi_tx"
{ for f in $MODS; do echo "verilog work \"../modules/rtl/$f\""; done
  for f in $HDMI; do echo "vhdl work \"../modules/rtl/video/hdmi/$f.vhd\""; done
  cat ../sega.prj
  echo 'vhdl work "rtl/fpgagen/gen_ctrl.vhd"'
  for f in karabas/sega_loader.v karabas/sega_fb.v karabas/sega_bk.v karabas/sega_kbd.v karabas_minig_top.v; do echo "verilog work \"rtl/$f\""; done
} > ../karabas_minig.prj
# the Go and Mini tops, ucf timing parts, prj / xst / ut from the Mini G ones
python3 "$(dirname "$0")/mktops.py"
