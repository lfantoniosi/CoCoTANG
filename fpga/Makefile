ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECT := $(ROOT)/CoCoTANG.gprj
BUILD_TCL := $(ROOT)/scripts/build.tcl
OUTPUT := $(ROOT)/impl/pnr/CoCoTANG.fs

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
.PHONY: build rebuild test timing program reprogram rom check-tools

build: $(OUTPUT)

rebuild: check-tools
	$(call run-gowin,CoCoTANG.gprj,top_coco3,CoCoTANG)

# Inspect the last routed build without programming the board or rebuilding.
timing:
	python3 scripts/check_timing.py impl/pnr/CoCoTANG_tr_content.html

test:
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
	iverilog -g2012 -o /private/tmp/cocotang_tb_startup_test tests/tb_coco_sdram_startup_test.v src/memory/coco_sdram_startup_test.v
	vvp /private/tmp/cocotang_tb_startup_test
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_arbiter tests/tb_cpu_sdram_arbiter.v src/memory/cpu_sdram_arbiter.v
	vvp /private/tmp/cocotang_tb_cpu_arbiter
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_bus_logger tests/tb_cpu_bus_logger.v src/debug/cpu_bus_logger.v
	vvp /private/tmp/cocotang_tb_cpu_bus_logger
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_mode tests/tb_gime_mode_debug.v src/coco3/gime_mode_debug.v
	vvp /private/tmp/cocotang_tb_gime_mode
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_timing tests/tb_gime_timing.v src/coco3/gime_timing.v
	vvp /private/tmp/cocotang_tb_gime_timing
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_native_video tests/tb_gime_native_video.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_native_video
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
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_decode tests/tb_ntsc_artifact_decode.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_artifact_decode
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

rom: roms/coco3.rom
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$<"

check-tools:
	@test -x "$(GW_SH)" || (echo "Gowin shell not found: $(GW_SH)"; exit 1)

define run-gowin
	@cd "$(ROOT)" && env $(GOWIN_ENV) COCOTANG_FPGA_ROOT="$(ROOT)" \
	 COCOTANG_PROJECT="$(1)" COCOTANG_TOP="$(2)" COCOTANG_OUTPUT="$(3)" \
	 "$(GW_SH)" "$(BUILD_TCL)"
endef

$(OUTPUT): $(PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG.gprj,top_coco3,CoCoTANG)
