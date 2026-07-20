# Build bare-metal C hello for the SoC (crt0 + UART + main).

ROOT      := ../..
SW_DIR    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
OUT       := $(SW_DIR)

XPACK_BIN := $(firstword $(wildcard $(ROOT)/tools/xpack-riscv-none-elf-gcc-*/bin))
ifeq ($(XPACK_BIN),)
PREFIX    ?= riscv-none-elf-
else
PREFIX    := $(XPACK_BIN)/riscv-none-elf-
endif

CC        := $(PREFIX)gcc
OBJCOPY   := $(PREFIX)objcopy
OBJDUMP   := $(PREFIX)objdump
PYTHON    ?= python3
# MSYS UCRT64 often has python only on PATH when the shell was started via run.ps1
ifeq ($(shell command -v $(PYTHON) 2>/dev/null),)
  PYTHON  := /ucrt64/bin/python3
endif

CFLAGS    := -march=rv32im -mabi=ilp32 -O2 -nostdlib -ffreestanding \
             -fno-builtin -Wall -Wextra
LDFLAGS   := -T link.ld -nostdlib -Wl,-Map=$(OUT)/hello_c.map

SRCS      := crt0.S uart.c main.c
OBJS      := $(OUT)/crt0.o $(OUT)/uart.o $(OUT)/main.o

.PHONY: all clean dump

all: $(OUT)/hello_c.hex $(OUT)/hello_c.elf

$(OUT)/crt0.o: crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/uart.o: uart.c uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/main.o: main.c uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/hello_c.elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

$(OUT)/hello_c.hex: $(OUT)/hello_c.elf
	$(PYTHON) $(ROOT)/scripts/elf2hex.py $< $@

dump: $(OUT)/hello_c.elf
	$(OBJDUMP) -d -s $<

clean:
	rm -f $(OUT)/*.o $(OUT)/hello_c.elf $(OUT)/hello_c.hex $(OUT)/hello_c.map
