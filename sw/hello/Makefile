# Build bare-metal hello for the SoC and emit a Verilog-style hex image.
# Prefers tools/xpack-riscv-none-elf-gcc-*/bin if present.

ROOT      := ../..
SW_DIR    := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
OUT       := $(SW_DIR)

# Locate toolchain (xPack extract or PATH)
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
ifeq ($(shell command -v $(PYTHON) 2>/dev/null),)
  PYTHON  := /ucrt64/bin/python3
endif

CFLAGS    := -march=rv32im -mabi=ilp32 -O2 -nostdlib -ffreestanding \
             -Wall -Wextra
LDFLAGS   := -T link.ld -nostdlib -Wl,-Map=$(OUT)/hello.map

.PHONY: all clean dump

all: $(OUT)/hello.hex $(OUT)/hello.elf

$(OUT)/hello.elf: hello.S link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ hello.S

$(OUT)/hello.bin: $(OUT)/hello.elf
	$(OBJCOPY) -O binary $< $@

$(OUT)/hello.hex: $(OUT)/hello.bin
	$(PYTHON) $(ROOT)/scripts/bin2hex.py $< $@

dump: $(OUT)/hello.elf
	$(OBJDUMP) -d -s $<

clean:
	rm -f $(OUT)/hello.elf $(OUT)/hello.bin $(OUT)/hello.hex $(OUT)/hello.map
