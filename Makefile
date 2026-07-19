# RISC-V CPU - Verilator simulation Makefile
# Run from the MSYS2 UCRT64 shell, or via scripts/run.ps1 from PowerShell.
#
# Usage:
#   make                  - build and run (default TOP=cpu)
#   make TOP=alu sim      - unit-test one module
#   make waves            - run and open GTKWave
#   make clean

TOP ?= cpu

RTL_DIR   := rtl
TB_DIR    := tb
WAVE_DIR  := waves
OBJ_DIR   := obj_dir

# Full CPU / SoC / pipelined CPU need every RTL file; unit tests only need one module.
ifeq ($(filter $(TOP),cpu soc cpu_pipe),$(TOP))
RTL_SRCS := $(wildcard $(RTL_DIR)/*.sv)
else
RTL_SRCS := $(RTL_DIR)/$(TOP).sv
endif

TB_SRC := $(TB_DIR)/tb_$(TOP).cpp

export CXX := clang++
VERILATOR       ?= verilator
VERILATOR_FLAGS := -Wall --trace --cc --exe --build -j 0 \
                   -CFLAGS "-std=c++17" \
                   --top-module $(TOP) \
                   -Mdir $(OBJ_DIR)

SIM_BIN := $(OBJ_DIR)/V$(TOP)

.PHONY: all sim waves clean

all: sim

sim: $(SIM_BIN)
	@mkdir -p $(WAVE_DIR)
	./$(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(TB_SRC)
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRC)

waves: sim
	gtkwave $(WAVE_DIR)/$(TOP).vcd &

clean:
	rm -rf $(OBJ_DIR) $(WAVE_DIR)
