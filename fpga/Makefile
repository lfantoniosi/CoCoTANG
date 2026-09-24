ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
PROJECT := $(ROOT)/CoCoTANG.gprj
COCO2_PROJECT := $(ROOT)/CoCoTANG_coco2.gprj
BUILD_TCL := $(ROOT)/scripts/build.tcl
OUTPUT := $(ROOT)/impl/pnr/CoCoTANG.fs
COCO2_OUTPUT := $(ROOT)/impl/pnr/CoCoTANG_coco2.fs
CMPX_STRESS_SOURCE := $(ROOT)/diagnostics/cmpx_stress.asm
CMPX_STRESS_ROM := $(ROOT)/roms/cmpx-stress.rom
CMPX_STRESS_LIST := $(ROOT)/roms/cmpx-stress.lst

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
.PHONY: build rebuild coco2_build coco2_rebuild test program reprogram \
	coco2_program coco2_reprogram coco2_rom coco3_rom cmpx-stress-rom \
	cmpx-stress-program check-tools

build: $(OUTPUT)

rebuild: check-tools
	$(call run-gowin,CoCoTANG.gprj,top_coco3,CoCoTANG)

coco2_build: $(COCO2_OUTPUT)

coco2_rebuild: check-tools
	$(call run-gowin,CoCoTANG_coco2.gprj,top,CoCoTANG_coco2)

test:
	iverilog -g2012 -o /private/tmp/cocotang_tb_pia1_dac tests/tb_coco_pia1_dac.v src/audio/coco_pia1_dac.v
	vvp /private/tmp/cocotang_tb_pia1_dac
	iverilog -g2012 -o /private/tmp/cocotang_tb_sam tests/tb_coco_sam.v src/coco2/coco_sam.v
	vvp /private/tmp/cocotang_tb_sam
	iverilog -g2012 -o /private/tmp/cocotang_tb_mux tests/tb_coco_bus_mux.v src/bus/coco_bus_mux.v
	vvp /private/tmp/cocotang_tb_mux
	iverilog -g2012 -o /private/tmp/cocotang_tb_cvbs tests/tb_coco_cvbs_ntsc.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs
	iverilog -g2012 -o /private/tmp/cocotang_tb_fill tests/tb_sdram_test_fill.v src/memory/sdram_test_fill.v
	vvp /private/tmp/cocotang_tb_fill
	iverilog -g2012 -o /private/tmp/cocotang_tb_startup_test tests/tb_coco_sdram_startup_test.v src/memory/coco_sdram_startup_test.v
	vvp /private/tmp/cocotang_tb_startup_test
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_arbiter tests/tb_cpu_sdram_arbiter.v src/memory/cpu_sdram_arbiter.v
	vvp /private/tmp/cocotang_tb_cpu_arbiter
	iverilog -g2012 -o /private/tmp/cocotang_tb_cpu_bus_logger tests/tb_cpu_bus_logger.v src/debug/cpu_bus_logger.v
	vvp /private/tmp/cocotang_tb_cpu_bus_logger
	iverilog -g2012 -o /private/tmp/cocotang_tb_video_mode tests/tb_video_mode_debug.v src/video/video_mode_debug.v
	vvp /private/tmp/cocotang_tb_video_mode
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_mode tests/tb_gime_mode_debug.v src/coco3/gime_mode_debug.v
	vvp /private/tmp/cocotang_tb_gime_mode
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_timing tests/tb_gime_timing.v src/coco3/gime_timing.v
	vvp /private/tmp/cocotang_tb_gime_timing
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_native_video tests/tb_gime_native_video.v src/coco3/gime_native_video.v
	vvp /private/tmp/cocotang_tb_gime_native_video
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_registers tests/tb_gime_registers.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_registers
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_disto tests/tb_gime_disto.v src/coco3/gime_registers.v
	vvp /private/tmp/cocotang_tb_gime_disto
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_video tests/tb_gime_video.v src/coco3/gime_video.v src/coco2/mc6847_char_rom.v
	vvp /private/tmp/cocotang_tb_gime_video
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_decode tests/tb_ntsc_artifact_decode.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_artifact_decode
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_control tests/tb_artifact_mode_control.v src/video/artifact_mode_control.v
	vvp /private/tmp/cocotang_tb_artifact_control
	iverilog -g2012 -o /private/tmp/cocotang_tb_artifact_osd tests/tb_artifact_mode_osd.sv src/video/artifact_mode_osd.sv
	vvp /private/tmp/cocotang_tb_artifact_osd
	iverilog -g2012 -o /private/tmp/cocotang_tb_gime_scanline tests/tb_gime_scanline_buffer.v src/coco3/gime_scanline_buffer.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_gime_scanline
	iverilog -g2012 -o /private/tmp/cocotang_tb_coco3_video_mux tests/tb_coco3_video_mux.v src/coco3/coco3.v src/coco3/gime_timing.v src/coco3/gime_registers.v src/coco3/gime_mode_debug.v src/coco3/gime_scanline_buffer.v src/coco3/gime_native_video.v src/coco3/coco3_char_rom.v src/video/ntsc_artifact_decode.v
	vvp /private/tmp/cocotang_tb_coco3_video_mux
	iverilog -g2012 -o /private/tmp/cocotang_tb_framebuffer tests/tb_coco_framebuffer.v src/video/coco_framebuffer.v
	vvp /private/tmp/cocotang_tb_framebuffer
	iverilog -g2012 -o /private/tmp/cocotang_tb_hdmi_debug tests/tb_hdmi_debug_overlay.sv src/video/hdmi_debug_overlay.sv
	vvp /private/tmp/cocotang_tb_hdmi_debug

program: $(OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

coco2_program: $(COCO2_OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(COCO2_OUTPUT)"

coco2_reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(COCO2_OUTPUT)"

cmpx-stress-rom: $(CMPX_STRESS_ROM)

$(CMPX_STRESS_ROM): $(CMPX_STRESS_SOURCE)
	lwasm --6809 --format=raw --list="$(CMPX_STRESS_LIST)" \
	 --output="$@" "$<"
	@test "$$(wc -c < "$@")" -eq 16384 || \
	 (echo "CMPX stress ROM is not 16384 bytes"; exit 1)

cmpx-stress-program: $(CMPX_STRESS_ROM)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$<"

coco2_rom: roms/coco2.rom
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$<"

coco3_rom: roms/coco3.rom
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

$(COCO2_OUTPUT): $(COCO2_PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin,CoCoTANG_coco2.gprj,top,CoCoTANG_coco2)
