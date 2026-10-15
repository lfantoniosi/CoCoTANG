ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECT := $(ROOT)/CoCoTANG.gprj
PAL_PROJECT := $(ROOT)/CoCoTANG-pal.gprj
BUILD_TCL := $(ROOT)/scripts/build.tcl
OUTPUT := $(ROOT)/impl/pnr/CoCoTANG.fs
PAL_OUTPUT := $(ROOT)/impl/pnr/CoCoTANG-pal.fs
ORCHESTRA90_OUTPUT := $(ROOT)/impl/pnr/CoCoTANG-orchestra90.fs
NTSC_SVIDEO_OUTPUT := $(ROOT)/impl/pnr/CoCoTANG-ntsc-svideo.fs
PAL_ROM ?= /Users/felipe/src/retro/coco_roms/coco3p.rom
RAM8M_DISK := $(ROOT)/results/RAM8M.DSK
RAM8M_BIN := $(ROOT)/results/RAM8M.BIN
PALETTE_BRIDGE_DISK := $(ROOT)/results/PALBRDG.DSK
PALETTE_BRIDGE_BIN := $(ROOT)/results/PALROT.BIN
CONTRAS_PALETTE_TEST_DISK := $(ROOT)/results/CONTPAL.DSK
CONTRAS_PALETTE_TEST_BIN := $(ROOT)/results/CONTPAL.BIN
CONTRAS_PALETTE_SYNC_DISK := $(ROOT)/results/CONTPAS.DSK
CONTRAS_PALETTE_SYNC_BIN := $(ROOT)/results/CONTPAS.BIN
CONTRAS_EXACT_TEST_DISK := $(ROOT)/results/CONTRAX.DSK
CONTRAS_EXACT_TEST_BIN := $(ROOT)/results/CONTRAX.BIN
FLOPPY_DIAG_DISK := $(ROOT)/results/FLOPTEST.DSK
FLOPPY_WRITE_BIN := $(ROOT)/results/FLOPWRIT.BIN
CONTRAS_IRQ_DISK := $(ROOT)/results/CONIRQ.DSK
CONTRAS_IRQ_BIN := $(ROOT)/results/CONIRQ.BIN
CONTRAS_IRQ_DATA_BIN := $(ROOT)/results/IRQDATA.BIN

ifeq ($(shell uname -s),Darwin)
GOWIN_IDE ?= /Applications/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE
GOWIN_ENV := QT_QPA_PLATFORM_PLUGIN_PATH="$(GOWIN_IDE)/plugins/qt/platforms" \
 DYLD_LIBRARY_PATH="$(GOWIN_IDE)/lib" DYLD_FRAMEWORK_PATH="$(GOWIN_IDE)/lib"
else
GOWIN_IDE ?= /opt/Gowin/IDE
GOWIN_ENV :=
endif
GW_SH ?= $(GOWIN_IDE)/bin/gw_sh
OPENFPGALOADER ?= openFPGALoader
PROGRAMMER_BOARD ?= tangnano20k
ROM_OFFSET ?= 1048576

.DEFAULT_GOAL := build
.PHONY: ram8m-dsk orchestra90-build orchestra90-rebuild orchestra90-timing orchestra90-program orchestra90-reprogram build rebuild contras-debug-build contras-debug-rebuild pal-build pal-rebuild ntsc-svideo-build \
 ntsc-svideo-rebuild test timing pal-timing ntsc-svideo-timing program \
 reprogram pal-program pal-reprogram ntsc-svideo-program \
 ntsc-svideo-reprogram rom pal-rom palette-bridge-dsk contras-palette-test-dsk \
 contras-palette-sync-dsk contras-exact-dsk floppy-diag-dsk contras-irq-dsk check-tools

build: $(OUTPUT)

rebuild: check-tools
	$(call run-gowin,CoCoTANG.gprj,top_coco3,CoCoTANG)

orchestra90-build: $(ORCHESTRA90_OUTPUT)

orchestra90-rebuild: check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_orchestra90,CoCoTANG-orchestra90)

contras-debug-build: $(ROOT)/impl/pnr/CoCoTANG-contras-debug.fs

contras-debug-rebuild: check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_contras_debug,CoCoTANG-contras-debug)

pal-build: $(PAL_OUTPUT)

pal-rebuild: check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_pal,CoCoTANG-pal)

ntsc-svideo-build: $(NTSC_SVIDEO_OUTPUT)

ntsc-svideo-rebuild: check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_ntsc_svideo,CoCoTANG-ntsc-svideo)

# Inspect the last routed build without programming the board or rebuilding.
timing:
	python3 scripts/check_timing.py impl/pnr/CoCoTANG_tr_content.html

orchestra90-timing:
	python3 scripts/check_timing.py impl/pnr/CoCoTANG-orchestra90_tr_content.html

pal-timing:
	python3 scripts/check_timing.py impl/pnr/CoCoTANG-pal_tr_content.html

ntsc-svideo-timing:
	python3 scripts/check_timing.py impl/pnr/CoCoTANG-ntsc-svideo_tr_content.html

test:
	iverilog -g2012 -s tb_coco_orchestra90 -o /private/tmp/cocotang_tb_orchestra90 tests/tb_coco_orchestra90.sv tests/tb_coco3_hdmi_border_handoff.sv src/audio/coco_orchestra90.v src/video/sigma_delta_dac.v src/video/coco3_hdmi.sv src/video/artifact_mode_osd.sv src/video/hdmi/audio_sample_packet.sv
	vvp /private/tmp/cocotang_tb_orchestra90
	iverilog -g2012 -o /private/tmp/cocotang_tb_sd_spi tests/tb_sd_spi_block.v src/storage/sd_spi_block.v
	vvp /private/tmp/cocotang_tb_sd_spi
	iverilog -g2012 -o /private/tmp/cocotang_tb_glenside tests/tb_glenside_ata.v src/storage/glenside_ata.v src/storage/glenside_sector_buffer.v
	vvp /private/tmp/cocotang_tb_glenside
	iverilog -g2012 -o /private/tmp/cocotang_tb_pia1_dac tests/tb_coco_pia1_dac.v src/audio/coco_pia1_dac.v
	vvp /private/tmp/cocotang_tb_pia1_dac
	iverilog -g2012 -o /private/tmp/cocotang_tb_mux tests/tb_coco_bus_mux.v src/bus/coco_bus_mux.v
	vvp /private/tmp/cocotang_tb_mux
	iverilog -g2012 -o /private/tmp/cocotang_tb_cvbs tests/tb_coco_cvbs_ntsc.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs
	iverilog -g2012 -o /private/tmp/cocotang_tb_pal_cvbs tests/tb_coco_cvbs_pal.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_pal_cvbs
	iverilog -g2012 -o /private/tmp/cocotang_tb_ntsc_svideo tests/tb_coco_cvbs_ntsc_svideo.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_ntsc_svideo
	iverilog -g2012 -o /private/tmp/cocotang_tb_startup_test tests/tb_coco_sdram_startup_test.v src/memory/coco_sdram_startup_test.v
	vvp /private/tmp/cocotang_tb_startup_test
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_arbiter tests/tb_cpu_sdram_arbiter.v src/memory/cpu_sdram_arbiter.v
	vvp /private/tmp/cocotang_tb_cpu_arbiter
	iverilog -g2012 -s tb_coco3_memory_write_queue -o /private/tmp/cocotang_tb_memory_write_queue tests/tb_coco3_memory_write_queue.v src/memory/coco3_memory.v src/memory/cpu_sdram_arbiter.v src/memory/coco_sdram_startup_test.v src/memory/coco_flash_loader.v src/memory/spi_flash_reader.v
	vvp /private/tmp/cocotang_tb_memory_write_queue
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_bus_logger tests/tb_cpu_bus_logger.v src/debug/cpu_bus_logger.v
	vvp /private/tmp/cocotang_tb_cpu_bus_logger
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_mode tests/tb_gime_mode_debug.v src/coco3/gime_mode_debug.v
	vvp /private/tmp/cocotang_tb_gime_mode
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_timing tests/tb_gime_timing.v src/coco3/gime_timing.v
	vvp /private/tmp/cocotang_tb_gime_timing
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_native_video tests/tb_gime_native_video.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_native_video
	iverilog -g2012 -s tb_gime_vborder -o /private/tmp/cocotang_tb_gime_vborder tests/tb_gime_vborder.v src/coco3/gime_native_video.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_vborder
	iverilog -g2012 -s tb_coco3_vborder_startup -o /private/tmp/cocotang_tb_vborder_startup tests/tb_coco3_vborder_startup.sv src/coco3/coco3.v src/coco3/gime_timing.v src/coco3/gime_registers.v src/coco3/gime_mode_debug.v src/coco3/gime_native_video.v src/coco3/gime_scanline_buffer.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v src/video/coco3_hdmi.sv src/video/artifact_mode_osd.sv src/video/hdmi/hdmi.sv src/video/hdmi/tmds_channel.sv
	vvp /private/tmp/cocotang_tb_vborder_startup
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_50_to_60_resync tests/tb_gime_50_to_60_resync.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_50_to_60_resync
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_50_to_60_field_wrap tests/tb_gime_50_to_60_field_wrap.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_50_to_60_field_wrap
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_compat_video tests/tb_gime_compat_video.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_compat_video
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_registers tests/tb_gime_registers.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_registers
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_disto tests/tb_gime_disto.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_disto
	iverilog -g2012 -s tb_gime_nocan3 -o /private/tmp/cocotang_tb_gime_nocan3 tests/tb_gime_nocan3.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_nocan3
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_decode tests/tb_ntsc_artifact_decode.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_artifact_decode
	iverilog -g2012 -o /private/tmp/cocotang_tb_rgb_phase tests/tb_rgb_scanline_dac_phase.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_rgb_phase
	iverilog -g2012 -o /private/tmp/cocotang_tb_cvbs_svideo_phase tests/tb_cvbs_svideo_scanline_dac_phase.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs_svideo_phase
	iverilog -g2012 -o /private/tmp/cocotang_tb_cvbs_luma_filter tests/tb_cvbs_luma_filter.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs_luma_filter
	iverilog -g2012 -s tb_cvbs_luma_notch -o /private/tmp/cocotang_tb_cvbs_luma_notch tests/tb_cvbs_luma_notch.sv src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs_luma_notch
	iverilog -g2012 -s tb_cvbs_chroma_filter -o /private/tmp/cocotang_tb_cvbs_chroma_filter tests/tb_cvbs_chroma_filter.sv src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs_chroma_filter
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_control tests/tb_artifact_mode_control.v src/video/artifact_mode_control.v
	vvp /private/tmp/cocotang_tb_artifact_control
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_osd tests/tb_artifact_mode_osd.sv src/video/artifact_mode_osd.sv
	vvp /private/tmp/cocotang_tb_artifact_osd
	iverilog -g2012 -o /private/tmp/cocotang_tb_hdmi_standard tests/tb_hdmi_video_standard.sv src/video/hdmi/hdmi.sv src/video/hdmi/tmds_channel.sv
	vvp /private/tmp/cocotang_tb_hdmi_standard
	iverilog -g2012 -s tb_coco3_hdmi_border_handoff -o /private/tmp/cocotang_tb_hdmi_border tests/tb_coco3_hdmi_border_handoff.sv src/video/coco3_hdmi.sv src/video/artifact_mode_osd.sv
	vvp /private/tmp/cocotang_tb_hdmi_border
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_scanline tests/tb_gime_scanline_buffer.v src/coco3/gime_scanline_buffer.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_gime_scanline
	iverilog -g2012 -s tb_gime_cached_scanline -o /private/tmp/cocotang_tb_cached_scanline tests/tb_gime_cached_scanline.v src/coco3/gime_scanline_buffer.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_cached_scanline
	iverilog -g2012 -s tb_gime_handover_cache_trace -o /private/tmp/cocotang_tb_gime_handover_cache_trace tests/tb_gime_handover_cache_trace.v src/coco3/gime_scanline_buffer.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_gime_handover_cache_trace
	iverilog -g2012 -o /private/tmp/cocotang_tb_coco3_video_mux tests/tb_coco3_video_mux.v src/coco3/coco3.v src/coco3/gime_timing.v src/coco3/gime_registers.v src/coco3/gime_mode_debug.v src/coco3/gime_scanline_buffer.v src/coco3/gime_native_video.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_coco3_video_mux
	iverilog -g2012 -o /private/tmp/cocotang_tb_hdmi_debug tests/tb_hdmi_debug_overlay.sv src/video/hdmi_debug_overlay.sv
	vvp /private/tmp/cocotang_tb_hdmi_debug
	iverilog -g2012 -s tb_gime_field_trace -o /private/tmp/cocotang_tb_gime_field_trace tests/tb_gime_field_trace.sv src/video/hdmi_debug_overlay.sv
	vvp /private/tmp/cocotang_tb_gime_field_trace

program: $(OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

orchestra90-program: $(ORCHESTRA90_OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(ORCHESTRA90_OUTPUT)"

orchestra90-reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(ORCHESTRA90_OUTPUT)"

pal-program: $(PAL_OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(PAL_OUTPUT)"

pal-reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(PAL_OUTPUT)"

ntsc-svideo-program: $(NTSC_SVIDEO_OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(NTSC_SVIDEO_OUTPUT)"

ntsc-svideo-reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(NTSC_SVIDEO_OUTPUT)"

rom: roms/coco3.rom
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$<"

$(RAM8M_BIN): tests/ram8m/RAM8M.asm
	@mkdir -p "$(ROOT)/results"
	lwasm --6809 --decb --list=$(ROOT)/results/RAM8M.lst -o "$@" "$<"

$(RAM8M_DISK): tests/ram8m/RAM8M.BAS $(RAM8M_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,RAM8M.BAS"
	decb copy -2 -b "$(RAM8M_BIN)" "$@,RAM8M.BIN"

ram8m-dsk: $(RAM8M_DISK)

$(PALETTE_BRIDGE_BIN): tests/palette_bridge/palrot.asm
	lwasm --6809 --decb --list=$(ROOT)/results/PALROT.lst -o "$@" "$<"

$(PALETTE_BRIDGE_DISK): tests/palette_bridge/PALBARS.BAS $(PALETTE_BRIDGE_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,PALBARS.BAS"
	decb copy -2 -b "$(PALETTE_BRIDGE_BIN)" "$@,PALROT.BIN"

palette-bridge-dsk: $(PALETTE_BRIDGE_DISK)

$(CONTRAS_PALETTE_TEST_BIN): tests/contras_palette/contras_palette.asm
	lwasm --6809 --decb --list=$(ROOT)/results/CONTPAL.lst -o "$@" "$<"

$(CONTRAS_PALETTE_TEST_DISK): tests/contras_palette/CONTPAL.BAS $(CONTRAS_PALETTE_TEST_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,CONTPAL.BAS"
	decb copy -2 -b "$(CONTRAS_PALETTE_TEST_BIN)" "$@,CONTPAL.BIN"

contras-palette-test-dsk: $(CONTRAS_PALETTE_TEST_DISK)

$(CONTRAS_PALETTE_SYNC_BIN): tests/contras_palette/contras_palette.asm
	lwasm --6809 -D SYNC_VARIANT=1 --decb --list=$(ROOT)/results/CONTPAS.lst -o "$@" "$<"

$(CONTRAS_PALETTE_SYNC_DISK): tests/contras_palette/CONTPAS.BAS $(CONTRAS_PALETTE_SYNC_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,CONTPAS.BAS"
	decb copy -2 -b "$(CONTRAS_PALETTE_SYNC_BIN)" "$@,CONTPAS.BIN"

contras-palette-sync-dsk: $(CONTRAS_PALETTE_SYNC_DISK)

$(CONTRAS_EXACT_TEST_BIN): tests/contras_palette/contras_exact.asm
	lwasm --6809 --decb --list=$(ROOT)/results/CONTRAX.lst -o "$@" "$<"

$(CONTRAS_EXACT_TEST_DISK): tests/contras_palette/CONTRAX.BAS $(CONTRAS_EXACT_TEST_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,CONTRAX.BAS"
	decb copy -2 -b "$(CONTRAS_EXACT_TEST_BIN)" "$@,CONTRAX.BIN"

contras-exact-dsk: $(CONTRAS_EXACT_TEST_DISK)

$(FLOPPY_WRITE_BIN): tests/floppy_diag/FLOPWRIT.asm
	lwasm --6809 --decb --list=$(ROOT)/results/FLOPWRIT.lst -o "$@" "$<"

$(FLOPPY_DIAG_DISK): tests/floppy_diag/FLOPSET.BAS tests/floppy_diag/FLOPCHK.BAS tests/floppy_diag/FLOPWRIT.BAS tests/floppy_diag/IDE2FDC.BAS $(FLOPPY_WRITE_BIN)
	decb dskini "$@"
	decb copy -0 -a -l tests/floppy_diag/FLOPSET.BAS "$@,FLOPSET.BAS"
	decb copy -0 -a -l tests/floppy_diag/FLOPCHK.BAS "$@,FLOPCHK.BAS"
	decb copy -0 -a -l tests/floppy_diag/FLOPWRIT.BAS "$@,FLOPWRIT.BAS"
	decb copy -0 -a -l tests/floppy_diag/IDE2FDC.BAS "$@,IDE2FDC.BAS"
	decb copy -2 -b "$(FLOPPY_WRITE_BIN)" "$@,FLOPWRIT.BIN"

floppy-diag-dsk: $(FLOPPY_DIAG_DISK)

$(CONTRAS_IRQ_BIN): tests/contras_irq/CONIRQ.asm
	lwasm --6809 --decb --list=$(ROOT)/results/CONIRQ.lst -o "$@" "$<"

$(CONTRAS_IRQ_DATA_BIN): tests/contras_irq/IRQDATA.asm
	lwasm --6809 --decb --list=$(ROOT)/results/IRQDATA.lst -o "$@" "$<"

$(CONTRAS_IRQ_DISK): tests/contras_irq/CONIRQ.BAS $(CONTRAS_IRQ_BIN) $(CONTRAS_IRQ_DATA_BIN)
	decb dskini "$@"
	decb copy -0 -a -l "$<" "$@,CONIRQ.BAS"
	decb copy -2 -b "$(CONTRAS_IRQ_BIN)" "$@,CONIRQ.BIN"
	decb copy -2 -b "$(CONTRAS_IRQ_DATA_BIN)" "$@,IRQDATA.BIN"

contras-irq-dsk: $(CONTRAS_IRQ_DISK)

pal-rom:
	@test -f "$(PAL_ROM)" || (echo "PAL ROM not found: $(PAL_ROM)"; exit 1)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$(PAL_ROM)"

check-tools:
	@test -x "$(GW_SH)" || (echo "Gowin shell not found: $(GW_SH)"; exit 1)

define run-gowin
	@cd "$(ROOT)" && env $(GOWIN_ENV) COCOTANG_FPGA_ROOT="$(ROOT)" \
	 COCOTANG_PROJECT="$(1)" COCOTANG_TOP="$(2)" COCOTANG_OUTPUT="$(3)" \
	 "$(GW_SH)" "$(BUILD_TCL)"
endef

$(OUTPUT): $(PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG.gprj,top_coco3,CoCoTANG)

$(ROOT)/impl/pnr/CoCoTANG-contras-debug.fs: $(PAL_PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_contras_debug,CoCoTANG-contras-debug)

$(PAL_OUTPUT): $(PAL_PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_pal,CoCoTANG-pal)

$(NTSC_SVIDEO_OUTPUT): $(PAL_PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_ntsc_svideo,CoCoTANG-ntsc-svideo)

$(ORCHESTRA90_OUTPUT): $(PAL_PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG-pal.gprj,top_coco3_orchestra90,CoCoTANG-orchestra90)
