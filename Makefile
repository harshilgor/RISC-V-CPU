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

.PHONY: all sim waves clean hello hello-c timer-irq demo

all: sim

sim: $(SIM_BIN)
	@mkdir -p $(WAVE_DIR)
	./$(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(TB_SRC)
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SRCS) $(TB_SRC)

# Build bare-metal hello.S with RISC-V GCC, then run it on the pipelined SoC.
hello:
	$(MAKE) -C sw/hello
	$(VERILATOR) -Wall --trace --cc --exe --build -j 0 \
		-CFLAGS "-std=c++17" --top-module soc -Mdir $(OBJ_DIR) \
		$(wildcard $(RTL_DIR)/*.sv) $(TB_DIR)/tb_hello.cpp
	@mkdir -p $(WAVE_DIR)
	./$(OBJ_DIR)/Vsoc sw/hello/hello.hex

# C hello: crt0 (stack + .data/.bss) + UART putchar + main()
hello-c:
	$(MAKE) -C sw/hello_c
	$(VERILATOR) -Wall --trace --cc --exe --build -j 0 \
		-CFLAGS "-std=c++17" --top-module soc -Mdir $(OBJ_DIR) \
		$(wildcard $(RTL_DIR)/*.sv) $(TB_DIR)/tb_hello.cpp
	@mkdir -p $(WAVE_DIR)
	./$(OBJ_DIR)/Vsoc sw/hello_c/hello_c.hex "Hello from C on RISC-V!\nmagic=42 local=43\n"

# Timer interrupt demo (3x '!' from handler)
timer-irq:
	$(MAKE) -C sw/timer_irq
	$(VERILATOR) -Wall --trace --cc --exe --build -j 0 \
		-CFLAGS "-std=c++17" --top-module soc -Mdir $(OBJ_DIR) \
		$(wildcard $(RTL_DIR)/*.sv) $(TB_DIR)/tb_hello.cpp
	@mkdir -p $(WAVE_DIR)
	./$(OBJ_DIR)/Vsoc sw/timer_irq/timer_irq.hex "timer irq demo\n!!!\ndone\n"

# Bigger C demo: fibonacci, sum, squares, bubble-sort
demo:
	$(MAKE) -C sw/demo
	$(VERILATOR) -Wall --trace --cc --exe --build -j 0 \
		-CFLAGS "-std=c++17" --top-module soc -Mdir $(OBJ_DIR) \
		$(wildcard $(RTL_DIR)/*.sv) $(TB_DIR)/tb_hello.cpp
	@mkdir -p $(WAVE_DIR)
	./$(OBJ_DIR)/Vsoc sw/demo/demo.hex "=== RISC-V SoC demo ===\nfib: 0 1 1 2 3 5 8 13 21 34 55 89 144\nsum(1..20)=210\nsquares: 1 4 9 16 25 36 49 64 81 100\nsorted: 1 2 3 4 5 7 8 9\n=== done ===\n"

waves: sim
	gtkwave $(WAVE_DIR)/$(TOP).vcd &

clean:
	rm -rf $(OBJ_DIR) $(WAVE_DIR)
	$(MAKE) -C sw/hello clean
	$(MAKE) -C sw/hello_c clean
	$(MAKE) -C sw/timer_irq clean
	$(MAKE) -C sw/demo clean
