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
.PHONY: build rebuild test program reprogram roms check-tools

build: $(OUTPUT)

rebuild: check-tools
	$(call run-gowin)

test:
	iverilog -g2012 -o /private/tmp/cocotang_tb_sam tests/tb_coco_sam.v src/coco_sam.v
	vvp /private/tmp/cocotang_tb_sam
	iverilog -g2012 -o /private/tmp/cocotang_tb_mux tests/tb_coco_bus_mux.v src/bus/coco_bus_mux.v
	vvp /private/tmp/cocotang_tb_mux
	iverilog -g2012 -o /private/tmp/cocotang_tb_cvbs tests/tb_coco_cvbs_ntsc.v src/video/coco_cvbs_ntsc.v
	vvp /private/tmp/cocotang_tb_cvbs
	iverilog -g2012 -o /private/tmp/cocotang_tb_fill tests/tb_sdram_test_fill.v src/memory/sdram_test_fill.v
	vvp /private/tmp/cocotang_tb_fill
	iverilog -g2012 -o /private/tmp/cocotang_tb_video_mode tests/tb_video_mode_debug.v src/video/video_mode_debug.v
	vvp /private/tmp/cocotang_tb_video_mode

program: $(OUTPUT)
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

reprogram:
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f "$(OUTPUT)"

roms: roms/coco2.rom
	"$(OPENFPGALOADER)" -b "$(PROGRAMMER_BOARD)" -f --external-flash \
	 -o "$(ROM_OFFSET)" "$<"

check-tools:
	@test -x "$(GW_SH)" || (echo "Gowin shell not found: $(GW_SH)"; exit 1)

define run-gowin
	@cd "$(ROOT)" && env $(GOWIN_ENV) COCOTANG_FPGA_ROOT="$(ROOT)" \
	 "$(GW_SH)" "$(BUILD_TCL)"
endef

$(OUTPUT): $(PROJECT) $(BUILD_TCL) $(shell find src -type f) | check-tools
	$(call run-gowin)
