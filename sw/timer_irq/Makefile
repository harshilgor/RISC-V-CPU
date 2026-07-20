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
OBJDUMP   := $(PREFIX)objdump
PYTHON    ?= python3
ifeq ($(shell command -v $(PYTHON) 2>/dev/null),)
  PYTHON  := /ucrt64/bin/python3
endif

CFLAGS    := -march=rv32im_zicsr -mabi=ilp32 -O2 -nostdlib -ffreestanding \
             -fno-builtin -Wall -Wextra
LDFLAGS   := -T link.ld -nostdlib -Wl,-Map=$(OUT)/timer_irq.map

OBJS      := $(OUT)/crt0.o $(OUT)/uart.o $(OUT)/main.o

.PHONY: all clean dump

all: $(OUT)/timer_irq.hex $(OUT)/timer_irq.elf

$(OUT)/crt0.o: crt0.S
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/uart.o: uart.c uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/main.o: main.c uart.h
	$(CC) $(CFLAGS) -c -o $@ $<

$(OUT)/timer_irq.elf: $(OBJS) link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(OBJS)

$(OUT)/timer_irq.hex: $(OUT)/timer_irq.elf
	$(PYTHON) $(ROOT)/scripts/elf2hex.py $< $@

dump: $(OUT)/timer_irq.elf
	$(OBJDUMP) -d -s $<

clean:
	rm -f $(OUT)/*.o $(OUT)/timer_irq.elf $(OUT)/timer_irq.hex $(OUT)/timer_irq.map
