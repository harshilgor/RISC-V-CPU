# RISC-V CPU (RV32IM_Zicsr)

A from-scratch **RISC-V CPU** in SystemVerilog, simulated with [Verilator](https://verilator.org/) and [GTKWave](https://gtkwave.sourceforge.net/).

The project includes:

- A **single-cycle** core (`cpu` / `cpu_core`) — easy to read and still fully tested
- A **5-stage pipelined** core (`cpu_pipe` / `cpu_core_pipe`) — forwarding, load-use stall, branch flush
- A **teaching SoC** — ROM + RAM + UART + timer, running real GCC-built C programs

**ISA:** RV32I + M + Zicsr, with machine-mode traps and **timer interrupts**.

**GitHub:** [harshilgor/RISC-V-CPU](https://github.com/harshilgor/RISC-V-CPU)

---

## Quick start (Windows)

Needs [MSYS2 UCRT64](https://www.msys2.org/) with Verilator. From PowerShell in the project root:

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"   # pipelined ISA tests
.\scripts\run.ps1 "TOP=soc sim"        # SoC smoke tests
.\scripts\run.ps1 "demo"               # bigger C program on the SoC (needs RISC-V GCC)
```

`scripts/run.ps1` maps the project to `R:` so Verilator never sees the space in `RISC-V cpu`.

---

## What you get

| Piece | What it is |
|-------|------------|
| **Single-cycle core** | One instruction per long cycle; default `TOP=cpu` |
| **5-stage pipeline** | IF → ID → EX → MEM → WB with forwarding + hazards |
| **SoC** | Pipelined core + dual-port ROM + RAM + UART TX + timer |
| **Software** | Asm hello, C hello, timer IRQ demo, fib/sort demo |

Pipeline design notes: [PIPELINE.md](PIPELINE.md).

```text
  SoC (soc.sv)
  +--------------------------------------------------+
  |  cpu_core_pipe                                   |
  |    IF ID EX MEM WB  + forward/hazard/CSR/IRQ     |
  |         |                |                       |
  |        ROM              data bus                 |
  |                    +-----+-----+-----+           |
  |                   RAM   UART  TIMER              |
  +--------------------------------------------------+
```

---

## Features

### Implemented

| Area | Details |
|------|---------|
| **ISA** | RV32IM_Zicsr |
| **Cores** | Single-cycle **and** 5-stage pipeline |
| **Pipeline** | Forwarding, load-use stall, EX branch/jump flush (IF/ID + ID/EX bubble) |
| **Registers** | 32 × 32-bit; `x0` hardwired to 0 |
| **ALU / MDU** | Full RV32I ALU; combinational mul/div/rem |
| **Memory ops** | LB/LH/LW/LBU/LHU + SB/SH/SW |
| **CSRs** | `mstatus` (MIE/MPIE), `mie`, `mip`, `mtvec`, `mepc`, `mcause` |
| **Traps** | `ecall` / `ebreak` / `mret` |
| **Interrupts** | Machine timer IRQ (`mtime` ≥ `mtimecmp`, `mie.MTIE`, `mstatus.MIE`) |
| **SoC map** | ROM `0x0`, RAM `0x1000_0000`, UART `0x1001_0000`, TIMER `0x1002_0000` |
| **Software** | Bare-metal asm + C via RISC-V GCC → hex → ROM |

### Not implemented (yet)

- C (compressed), F/D (float), A (atomics)
- Caches, MMU, richer privileged ISA
- FPGA synthesis / board bring-up
- Multi-cycle mul/div (MDU is combinational for teaching)

---

## Repository layout

```text
RISC-V-CPU/
|-- README.md
|-- PIPELINE.md              # How the 5-stage core was built
|-- Makefile
|-- rtl/
|   |-- cpu_core.sv          # Single-cycle core (external I/D buses)
|   |-- cpu_core_pipe.sv     # 5-stage pipelined core
|   |-- cpu.sv / cpu_pipe.sv # Wrappers + local imem/dmem for unit tests
|   |-- soc.sv               # Pipelined SoC top
|   |-- forward_unit.sv / hazard_unit.sv
|   |-- rom.sv / ram.sv / uart.sv / timer.sv
|   `-- alu.sv, regfile.sv, csr_file.sv, ...
|-- tb/                      # Verilator C++ testbenches
|   |-- tb_cpu.cpp / tb_cpu_pipe.cpp / tb_soc.cpp
|   `-- tb_hello.cpp         # Load .hex, capture UART
|-- sw/
|   |-- hello/               # Asm UART hello
|   |-- hello_c/             # Minimal C + crt0
|   |-- timer_irq/           # Timer interrupt demo
|   `-- demo/                # Fib / sum / squares / sort
|-- scripts/
|   |-- run.ps1
|   |-- bin2hex.py / elf2hex.py
`-- tools/                   # Optional local xPack RISC-V GCC (gitignored)
```

---

## Memory map (SoC)

| Region | Base | Notes |
|--------|------|-------|
| ROM | `0x0000_0000` | Fetch + `.text` / `.rodata` (dual-port) |
| RAM | `0x1000_0000` | 4 KiB — stack, `.data`, `.bss` |
| UART | `0x1001_0000` | `TXDATA` @ +0, `TXSTATUS` @ +4 |
| TIMER | `0x1002_0000` | `mtime` @ +0, `mtimecmp` @ +4 |

IRQ while `mtime >= mtimecmp`. Software clears it by writing a future `mtimecmp`.

---

## Traps and interrupts

| Event | `mcause` | Behavior |
|-------|----------|----------|
| `ecall` | `11` | Save PC → `mepc`, jump `mtvec`, clear `mstatus.MIE` |
| `ebreak` | `3` | Same |
| Timer IRQ | `0x8000_0007` | Same; taken in EX on a valid instruction |
| `mret` | — | PC ← `mepc`, restore `MIE` from `MPIE` |

Enable path: set `mtvec`, program `mtimecmp`, `csrs mie, MTIE`, `csrs mstatus, MIE`.

---

## How to build and run

### Core / SoC tests

```powershell
.\scripts\run.ps1                    # single-cycle (TOP=cpu)
.\scripts\run.ps1 "TOP=cpu_pipe sim" # pipelined ISA + CSR/trap tests
.\scripts\run.ps1 "TOP=soc sim"      # ROM / RAM / UART smoke
.\scripts\run.ps1 waves              # open GTKWave on last top’s VCD
.\scripts\run.ps1 clean
```

### Real software on the SoC

Needs RISC-V GCC (`tools/xpack-riscv-none-elf-gcc-*` or `riscv-none-elf-gcc` on PATH).

| Target | Program |
|--------|---------|
| `hello` | Asm UART hello |
| `hello-c` | C `main` + stack / `.data` / `.bss` |
| `timer-irq` | C handler prints `!!!` on timer IRQs |
| `demo` | Fib table, sum, squares, bubble sort |

```powershell
.\scripts\run.ps1 "hello"
.\scripts\run.ps1 "hello-c"
.\scripts\run.ps1 "timer-irq"
.\scripts\run.ps1 "demo"
```

Example `demo` UART output:

```text
=== RISC-V SoC demo ===
fib: 0 1 1 2 3 5 8 13 21 34 55 89 144
sum(1..20)=210
squares: 1 4 9 16 25 36 49 64 81 100
sorted: 1 2 3 4 5 7 8 9
=== done ===
```

### Unit-test one module

```powershell
.\scripts\run.ps1 "TOP=alu sim"
.\scripts\run.ps1 "TOP=regfile sim"
```

### From MSYS2 UCRT64

```bash
cd /r    # after run.ps1 subst, or use a path without spaces
make TOP=cpu_pipe sim
make TOP=soc sim
make demo
```

---

## Module reference

| Module | File | Role |
|--------|------|------|
| `cpu_core` | `rtl/cpu_core.sv` | Single-cycle RV32IM_Zicsr |
| `cpu_core_pipe` | `rtl/cpu_core_pipe.sv` | 5-stage pipeline + IRQ |
| `cpu` / `cpu_pipe` | wrappers | Core + local IMEM/DMEM |
| `soc` | `rtl/soc.sv` | Pipelined SoC top |
| `forward_unit` / `hazard_unit` | pipeline helpers | Bypass + stall/flush |
| `timer` | `rtl/timer.sv` | `mtime` / `mtimecmp` |
| `rom` / `ram` / `uart` | SoC peripherals | Boot, data, TX |
| `csr_file` | `rtl/csr_file.sv` | Machine CSRs + IRQ pending |

---

## Design notes

- **Default `TOP=cpu`** stays single-cycle for comparison; the SoC uses the **pipeline**.
- **Combinational MDU** — fine for Verilator/learning; widen for FPGA Fmax later.
- **ELF → hex** — `scripts/elf2hex.py` places PT_LOAD segments by LMA so `.data` in RAM still has a ROM image for crt0 to copy.
- **Interrupt handlers** must save callee-saved regs the C code uses (see `sw/timer_irq/crt0.S`).

---

## Roadmap

- [x] Teaching SoC (ROM + RAM + UART)
- [x] 5-stage pipeline ([PIPELINE.md](PIPELINE.md))
- [x] Timer interrupts (`mie` / `mip` / `mtime`)
- [x] Bare-metal C + larger UART demos
- [ ] FPGA synthesis (timing / Fmax)

---

## License

Personal / educational project. Feel free to fork and experiment.
