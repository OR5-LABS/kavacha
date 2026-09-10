###############################################################################
# bench/Makefile — Kavacha benchmark suite (CoreMark + EMBench-IoT)
#
# ---- Kavacha targets --------------------------------------------------------
#   make verilator-kavacha    — build Kavacha Verilator model
#   make run-kavacha          — run all benchmarks on Kavacha
#   make coremark             — compile CoreMark
#   make embench              — compile all 19 EMBench-IoT benchmarks
#   make report               — generate benchmark report
#   make all                  — build & run everything
#
# Variables:
#   RISCV_GCC, ITERATIONS, SCALE, VERILATOR, CXX
###############################################################################

SHELL := /bin/bash
.DEFAULT_GOAL := all

# ---- Directories ------------------------------------------------------------
BENCH_DIR   := .
ROOT_DIR    := ..
RTL_DIR     := $(ROOT_DIR)/rtl
RTL_COMMON  := $(RTL_DIR)/common

BUILD_DIR   := $(BENCH_DIR)/build
V_BUILD_DIR := /tmp/kavacha_sim_$(USER)
WORKSPACE_LINK := /tmp/kavacha_workspace
SIM_DIR     := $(ROOT_DIR)/sim
RESULTS_DIR := $(BENCH_DIR)/results

COREMARK_SRC := $(BENCH_DIR)/coremark/upstream
EMBENCH_SRC  := $(BENCH_DIR)/embench/upstream

# ---- Toolchain detection ----------------------------------------------------
VERILATOR ?= verilator
CXX       ?= g++

# Try to find a RISC-V GCC
ifeq ($(RISCV_GCC),)
  RISCV_GCC := $(firstword \
    $(wildcard $(RISCV_TC)/riscv-none-elf-gcc) \
    $(shell command -v riscv64-unknown-elf-gcc 2>/dev/null) \
    $(shell command -v riscv32-unknown-elf-gcc 2>/dev/null) \
    $(shell command -v riscv64-elf-gcc         2>/dev/null) \
    $(shell command -v riscv32-elf-gcc         2>/dev/null) \
    $(shell command -v riscv-none-elf-gcc      2>/dev/null) \
    $(wildcard /home/yash/toolchains/xpack-riscv-none-elf-gcc-13.2.0-2/bin/riscv-none-elf-gcc) \
    NOTFOUND)
endif

ifneq ($(filter-out NOTFOUND,$(RISCV_GCC)),)
  GCC_PREFIX := $(patsubst %gcc,%,$(RISCV_GCC))
  OBJCOPY    := $(GCC_PREFIX)objcopy
  OBJDUMP    := $(GCC_PREFIX)objdump
  SIZE       := $(GCC_PREFIX)size
else
  $(error No RISC-V GCC found. Set RISCV_GCC= or add riscv64-unknown-elf-gcc to PATH)
endif

# ---- Compiler flags ---------------------------------------------------------
ARCH_FLAGS  := -march=rv32imc_zicsr -mabi=ilp32
COMMON_CFLAGS := $(ARCH_FLAGS) \
                 -O2 \
                 -ffreestanding \
                 -ffunction-sections \
                 -fdata-sections \
                 -fno-builtin \
                 -fno-common \
                 -Wall \
                 -nostdlib \
                 -nostartfiles

LDFLAGS     := -T $(BENCH_DIR)/common/bench.ld \
               -Wl,--gc-sections \
               -Wl,-Map=$(@:.elf=.map)

COMMON_SRCS := $(BENCH_DIR)/common/syscalls.c \
               $(BENCH_DIR)/common/printf.c

COMMON_INC  := -I$(BENCH_DIR)/common

# Default startup file
CRT0 := $(BENCH_DIR)/common/crt0.S

ITERATIONS  ?= 1000
SCALE       ?= 100

# ---- Benchmark iteration counts (EMBench benchmarks that need tuning) ------
SCALE_picojpeg    := 10
SCALE_nsichneu    := 10
SCALE_qrduino     := 10
SCALE_wikisort    := 2
SCALE_huffbench   := 2

# wikisort uses bool/true/false without #include <stdbool.h>.
# Force-include it to fix the build without patching upstream source.
EXTRA_CFLAGS_wikisort := -include stdbool.h

scale_for = $(if $(SCALE_$(1)),$(SCALE_$(1)),$(SCALE))

# ---- EMBench benchmark list (19 from embench-iot) ----------------------
EMBENCH_BENCHMARKS := \
    aha-mont64   crc32      depthconv  edn        huffbench  \
    matmult-int  md5sum     nettle-aes nettle-sha256 nsichneu \
    picojpeg     qrduino    sglib-combined slre   statemate \
    tarfind      ud         wikisort   xgboost

###############################################################################
# fetch — clone upstream sources
###############################################################################
.PHONY: fetch fetch-coremark fetch-embench
fetch: fetch-coremark fetch-embench

fetch-coremark: $(COREMARK_SRC)/.git

$(COREMARK_SRC)/.git:
	@if [ ! -d "$(COREMARK_SRC)" ] || [ -z "$$(ls -A $(COREMARK_SRC))" ]; then \
		echo "[FETCH] Cloning CoreMark..."; \
		git clone --depth=1 https://github.com/eembc/coremark $(COREMARK_SRC); \
	else \
		echo "[FETCH] CoreMark directory $(COREMARK_SRC) already exists, skipping clone."; \
	fi

fetch-embench: $(EMBENCH_SRC)/.git

$(EMBENCH_SRC)/.git:
	@if [ ! -d "$(EMBENCH_SRC)" ] || [ -z "$$(ls -A $(EMBENCH_SRC))" ]; then \
		echo "[FETCH] Cloning EMBench-IoT..."; \
		git clone --depth=1 https://github.com/embench/embench-iot $(EMBENCH_SRC); \
	else \
		echo "[FETCH] EMBench directory $(EMBENCH_SRC) already exists, skipping clone."; \
	fi

###############################################################################
# verilator — build Kavacha simulation model
###############################################################################
VERILATOR_SV := \
    rtl/common/kavacha_pkg.sv \
    rtl/common/kavacha_alu.sv \
    rtl/common/kavacha_regfile.sv \
    rtl/common/kavacha_muldiv.sv \
    rtl/common/kavacha_csr.sv \
    rtl/common/kavacha_rvc.sv \
    rtl/common/kavacha_immgen.sv \
    rtl/common/kavacha_branch.sv \
    rtl/common/kavacha_decode.sv \
    rtl/common/kavacha_pmp.sv \
    rtl/kavacha_core.sv \
    rtl/kavacha_debug.sv \
    bench/verilator/bench_top.sv

VERILATOR_CPP := bench/verilator/main.cpp

SIM_BIN := $(V_BUILD_DIR)/Vbench_obj/Vbench_top

.PHONY: verilator verilator-kavacha
verilator: $(SIM_BIN)
verilator-kavacha: $(SIM_BIN)

$(SIM_BIN): $(VERILATOR_SV:%=$(ROOT_DIR)/%) $(ROOT_DIR)/$(VERILATOR_CPP) | $(SIM_DIR)
	@echo "[VERILATOR] Creating workspace symlink to bypass space-in-path limits..."
	ln -sfn "$(realpath $(ROOT_DIR))" $(WORKSPACE_LINK)
	@echo "[VERILATOR] Building Kavacha simulation model in safe temp directory..."
	mkdir -p $(V_BUILD_DIR)/Vbench_obj
	$(VERILATOR) --Mdir "$(V_BUILD_DIR)/Vbench_obj" -o Vbench_top \
	    -f $(WORKSPACE_LINK)/bench/verilator/kavacha.f \
	    $(VERILATOR_SV:%=$(WORKSPACE_LINK)/%) \
	    $(WORKSPACE_LINK)/$(VERILATOR_CPP)
	@echo "[VERILATOR] Kavacha build complete: $@"

$(SIM_DIR):
	mkdir -p $@

###############################################################################
# coremark — compile CoreMark
###############################################################################
COREMARK_HEX := $(BUILD_DIR)/coremark.hex
COREMARK_ELF := $(BUILD_DIR)/coremark.elf

COREMARK_SRCS_UPSTREAM := \
    $(COREMARK_SRC)/core_list_join.c \
    $(COREMARK_SRC)/core_main.c \
    $(COREMARK_SRC)/core_matrix.c \
    $(COREMARK_SRC)/core_state.c \
    $(COREMARK_SRC)/core_util.c

COREMARK_PORT := \
    $(BENCH_DIR)/coremark/port/core_portme.c

COREMARK_ALL_SRCS := \
    $(COMMON_SRCS) \
    $(COREMARK_SRCS_UPSTREAM) \
    $(COREMARK_PORT)

COREMARK_CFLAGS := $(COMMON_CFLAGS) \
    $(COMMON_INC) \
    -I$(COREMARK_SRC) \
    -I$(BENCH_DIR)/coremark/port \
    -DITERATIONS=$(ITERATIONS) \
    -DMEM_METHOD=MEM_STATIC \
    -DMULTITHREAD=1 \
    -DUSE_FORK=0 \
    -DUSE_PTHREAD=0 \
    -DHAS_FLOAT=0 \
    -DHAS_TIME_H=0 \
    -DUSE_CLOCK=0 \
    -DHAS_STDIO=0 \
    -DHAS_PRINTF=1 \
    -DCOMPILER_FLAGS='"$(ARCH_FLAGS) -O2"' \
    -DCOMPILER_VERSION='"$(shell $(RISCV_GCC) --version | head -1)"' \
    -DPERFORMANCE_RUN=1

.PHONY: coremark
coremark: fetch-coremark $(COREMARK_HEX)

$(COREMARK_HEX): $(COREMARK_ELF) | $(BUILD_DIR)
	$(OBJCOPY) -O binary $< $(BUILD_DIR)/coremark.bin
	python3 $(ROOT_DIR)/sw/bin2hex.py $(BUILD_DIR)/coremark.bin $@
	$(SIZE) $<
	@echo "[COREMARK] Hex: $@"

$(COREMARK_ELF): $(COREMARK_ALL_SRCS) $(CRT0) | $(BUILD_DIR) $(COREMARK_SRC)/.git
	@echo "[COREMARK] Compiling (ITERATIONS=$(ITERATIONS))...."
	$(RISCV_GCC) $(COREMARK_CFLAGS) $(LDFLAGS) \
	    -Wl,-Map=$(BUILD_DIR)/coremark.map \
	    -o $@ $(filter %.c %.S,$^)

$(BUILD_DIR):
	mkdir -p $@

###############################################################################
# embench — compile all 19 EMBench-IoT benchmarks
###############################################################################
.PHONY: embench
embench: fetch-embench \
    $(foreach b,$(EMBENCH_BENCHMARKS),$(BUILD_DIR)/$(b).hex)

define EMBENCH_RULE
EMBENCH_SRCS_$(1) := $$(wildcard $$(EMBENCH_SRC)/src/$(1)/*.c)
EMBENCH_ELF_$(1)  := $$(BUILD_DIR)/$(1).elf
EMBENCH_HEX_$(1)  := $$(BUILD_DIR)/$(1).hex

EMBENCH_CFLAGS_$(1) := $$(COMMON_CFLAGS) \
    $$(COMMON_INC) \
    -I$$(BENCH_DIR)/embench/support \
    -I$$(EMBENCH_SRC)/support \
    -I$$(EMBENCH_SRC)/src/$(1) \
    -DLOCAL_SCALE_FACTOR=$$(call scale_for,$(1)) \
    -DGLOBAL_SCALE_FACTOR=1 \
    -DBENCHMARK_NAME='"$(1)"' \
    $$(EXTRA_CFLAGS_$(1))

$$(EMBENCH_ELF_$(1)): $$(COMMON_SRCS) $$(CRT0) \
                       $$(BENCH_DIR)/embench/bench_main.c \
                       $$(BENCH_DIR)/embench/support/support.c \
                       $$(EMBENCH_SRC)/support/beebsc.c \
                       $$(EMBENCH_SRCS_$(1)) \
                       | $$(BUILD_DIR) $$(EMBENCH_SRC)/.git
	@echo "[EMBENCH] Compiling $(1) (scale=$$(call scale_for,$(1)))..."
	$$(RISCV_GCC) $$(EMBENCH_CFLAGS_$(1)) $$(LDFLAGS) \
	    -Wl,-Map=$$(BUILD_DIR)/$(1).map \
	    -o $$@ $$(filter %.c %.S,$$^)

$$(EMBENCH_HEX_$(1)): $$(EMBENCH_ELF_$(1))
	$$(OBJCOPY) -O binary $$< $$(BUILD_DIR)/$(1).bin
	python3 $$(ROOT_DIR)/sw/bin2hex.py $$(BUILD_DIR)/$(1).bin $$@
	@echo "[EMBENCH] Hex: $$@"
endef

$(foreach b,$(EMBENCH_BENCHMARKS),$(eval $(call EMBENCH_RULE,$(b))))

###############################################################################
# run targets
###############################################################################
TIMEOUT_CYCLES ?= 2000000000  # 2 Billion cycles

KAVACHA_RESULTS := $(RESULTS_DIR)/kavacha

.PHONY: run-coremark run-kavacha-coremark
run-coremark: run-kavacha-coremark
run-kavacha-coremark: $(SIM_BIN) $(COREMARK_HEX) | $(KAVACHA_RESULTS) $(RESULTS_DIR)
	@echo "[RUN/Kavacha] CoreMark..."
	$(SIM_BIN) --hex $(COREMARK_HEX) --name coremark \
	    --max-cycles $(TIMEOUT_CYCLES) \
	    | tee $(KAVACHA_RESULTS)/coremark.log

.PHONY: run-embench run-kavacha-embench
run-embench: run-kavacha-embench
run-kavacha-embench: $(SIM_BIN) embench | $(KAVACHA_RESULTS) $(RESULTS_DIR)
	@for b in $(EMBENCH_BENCHMARKS); do \
	    echo "[RUN/Kavacha] $$b..."; \
	    $(SIM_BIN) --hex $(BUILD_DIR)/$$b.hex --name $$b \
	        --max-cycles $(TIMEOUT_CYCLES) \
	        | tee $(KAVACHA_RESULTS)/$$b.log; \
	done

DHRYSTONE_HEX ?= $(ROOT_DIR)/dhrystone/build/dhrystone.hex

.PHONY: run-dhrystone run-kavacha-dhrystone
run-dhrystone: run-kavacha-dhrystone
run-kavacha-dhrystone: $(SIM_BIN) | $(KAVACHA_RESULTS) $(RESULTS_DIR)
	@HEX=$${HEX_FILE:-$(DHRYSTONE_HEX)}; \
	echo "[RUN/Kavacha] Dhrystone ($$HEX)..."; \
	$(SIM_BIN) --hex "$$HEX" --name dhrystone \
	    --max-cycles $(TIMEOUT_CYCLES) \
	    | tee $(KAVACHA_RESULTS)/dhrystone.log


.PHONY: run-kavacha run-all
run-kavacha: run-kavacha-coremark run-kavacha-embench
run-all: run-kavacha

$(RESULTS_DIR):
	mkdir -p $@

$(KAVACHA_RESULTS):
	mkdir -p $@

###############################################################################
# report — benchmark report (Kavacha)
###############################################################################
.PHONY: report
report: run-kavacha | $(RESULTS_DIR)
	python3 $(BENCH_DIR)/run_bench.py \
	    --results-dir $(RESULTS_DIR) \
	    --iterations $(ITERATIONS) \
	    --scale $(SCALE)

###############################################################################
# all
###############################################################################
.PHONY: all
all: fetch verilator-kavacha coremark embench run-kavacha report

###############################################################################
# clean / distclean / help
###############################################################################
.PHONY: clean distclean help
clean:
	rm -rf $(BUILD_DIR) $(RESULTS_DIR)
	rm -rf $(V_BUILD_DIR)/Vbench_obj

distclean: clean
	rm -rf $(COREMARK_SRC) $(EMBENCH_SRC)

help:
	@echo "Kavacha Benchmark Suite (CoreMark + EMBench-IoT)"
	@echo ""
	@echo "  make all              — fetch + build + run + report"
	@echo "  make fetch            — clone CoreMark and EMBench-IoT sources"
	@echo "  make verilator-kavacha — build Kavacha Verilator simulation model"
	@echo "  make coremark         — compile CoreMark (ITERATIONS=$(ITERATIONS))"
	@echo "  make embench          — compile all 19 EMBench-IoT benchmarks"
	@echo "  make run-kavacha      — run CoreMark + EMBench on Kavacha"
	@echo "  make report           — generate results report"
	@echo "  make clean            — remove build/ and results/"
	@echo "  make distclean        — also remove fetched sources"
	@echo ""
	@echo "Key variables:"
	@echo "  RISCV_GCC=$(RISCV_GCC)"
	@echo "  VERILATOR=$(VERILATOR)"
	@echo "  ITERATIONS=$(ITERATIONS)"
	@echo "  SCALE=$(SCALE)"
