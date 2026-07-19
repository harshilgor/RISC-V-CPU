# RISC-V CPU (RV32IM_Zicsr)

A from-scratch **single-cycle RISC-V CPU** written in SystemVerilog, simulated with [Verilator](https://verilator.org/), and debugged with [GTKWave](https://gtkwave.sourceforge.net/).

This project implements a teaching-oriented **RV32IM_Zicsr** core: RV32I, the M extension, CSR instructions, and machine-mode traps (`ecall` / `ebreak` / `mret`).

**GitHub:** [harshilgor/RISC-V-CPU](https://github.com/harshilgor/RISC-V-CPU)

---

## What this is

RISC-V is an open instruction-set architecture. **RV32I** is the 32-bit base integer set; **M** adds hardware multiply and divide. Together, **RV32IM** is a common target for small embedded and educational processors.

This CPU is **single-cycle**: in one clock period it fetches an instruction, decodes it, reads registers, executes (ALU or MDU), optionally accesses data memory, writes back a result, and updates the program counter.

That design is slower in silicon than a pipeline, but it makes the datapath easy to understand, simulate, and verify. A step-by-step plan to evolve it into a **5-stage pipeline** is in [PIPELINE.md](PIPELINE.md).

```text
                    clk / rst
                        |
                        v
 +-----------------------------------------------------+
 |                      cpu (top)                      |
 |                                                     |
 |  PC --> IMEM --> instruction                        |
 |             |                                       |
 |             +--> control --> mux / we / mem / trap  |
 |             +--> imm_gen --> immediate              |
 |             +--> regfile <-- writeback              |
 |                    |                                |
 |             rs1/rs2 v                               |
 |             +--------------+                        |
 |             |  ALU  / MDU  | --> address / result   |
 |             +--------------+          |             |
 |                                       v             |
 |                                    DMEM             |
 |                                       |             |
 |                               writeback mux         |
 |                                       |             |
 |                         next PC (seq/br/j/trap)     |
 +-----------------------------------------------------+
```

---

## Features

### Implemented

| Area | Details |
|------|---------|
| **Architecture** | RV32IM, single-cycle |
| **Registers** | 32 x 32-bit (`x0`-`x31`); `x0` hardwired to 0 |
| **ALU** | ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU |
| **Immediates** | I, S, B, U, J formats |
| **Branches** | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| **Jumps** | JAL, JALR, LUI, AUIPC |
| **Memory** | LB, LH, LW, LBU, LHU, SB, SH, SW |
| **M extension** | MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU |
| **Zicsr** | CSRRW, CSRRS, CSRRC + CSRRWI/SI/CI |
| **CSRs** | `mstatus`, `mtvec`, `mepc`, `mcause` |
| **System** | FENCE (NOP), ECALL, EBREAK, MRET |
| **Traps** | `mepc` = faulting PC; handler advances `mepc` then `mret` |
| **Simulation** | Verilator C++ testbenches + VCD waves for GTKWave |

### Not implemented (yet)

- Interrupts / timers / richer privileged ISA
- C (compressed), F/D (float), A (atomics)
- Pipelining, caches, MMU
- FPGA synthesis flow
- Assembler / GCC toolchain integration (programs are hand-encoded in the testbench today)

---

## Repository layout

```text
RISC-V-CPU/
|-- README.md
|-- Makefile                 # Verilator build / run / waves / clean
|-- .gitignore
|-- rtl/                     # SystemVerilog RTL
|   |-- cpu_core.sv          # Core with external I/D buses
|   |-- cpu.sv               # Legacy wrapper: core + local imem/dmem
|   |-- soc.sv               # Teaching SoC: core + ROM + RAM + UART
|   |-- rom.sv / ram.sv      # Boot ROM and data RAM
|   |-- uart.sv              # Memory-mapped UART TX
|   |-- pc.sv, imem.sv, dmem.sv, regfile.sv, ...
|   `-- csr_file.sv          # Machine CSRs (Zicsr)
|-- tb/                      # Verilator C++ testbenches
|   |-- tb_cpu.cpp           # Full-core integration tests
|   |-- tb_soc.cpp           # SoC: ROM boot, RAM, UART hello
|   |-- tb_alu.cpp
|   |-- tb_regfile.cpp
|   |-- tb_imm_gen.cpp
|   `-- tb_control.cpp
`-- scripts/
    `-- run.ps1              # Windows helper (MSYS2 + R: path map)
```

Generated at build time (gitignored): `obj_dir/`, `waves/*.vcd`.

---

## Datapath overview

### 1. Fetch

The **PC** holds the current instruction address. **IMEM** returns a 32-bit instruction. After reset, execution starts at address `0`.

### 2. Decode

The instruction is split into `opcode`, `rd`, `rs1`, `rs2`, `funct3`, `funct7` / `funct12`. The **control unit** produces enables and mux selects. The **immediate generator** rebuilds the correct immediate format (I/S/B/U/J).

### 3. Execute

- **ALU** handles RV32I arithmetic, logic, shifts, and compares.
- **MDU** handles RV32M mul/div/rem (combinational in this teaching design).
- Operand muxes choose ALU inputs: `rs1` / `PC` / `0` and `rs2` / immediate.

### 4. Memory

**DMEM** supports word, halfword, and byte accesses using `funct3`, with sign/zero extension on loads.

### 5. Writeback

A mux selects what is written to the register file:

- ALU/MDU result
- Load data from DMEM
- `PC+4` (link value for `jal` / `jalr`)

### 6. Next PC

Priority (highest first):

1. Trap -> `mtvec` (`0x100`)
2. `mret` -> `mepc`
3. `jalr` -> `(rs1 + imm)` with LSB cleared
4. Taken branch / `jal` -> `PC + imm`
5. Otherwise -> `PC + 4`

---

## Module reference

| Module | File | Role |
|--------|------|------|
| `cpu_core` | `rtl/cpu_core.sv` | RV32IM_Zicsr core with external buses |
| `cpu` | `rtl/cpu.sv` | Wrapper: core + local IMEM/DMEM (legacy TB) |
| `soc` | `rtl/soc.sv` | SoC: core + ROM + RAM + UART |
| `rom` / `ram` | `rtl/rom.sv`, `rtl/ram.sv` | Boot ROM / data RAM |
| `uart` | `rtl/uart.sv` | MMIO TX (`TXDATA` / `TXSTATUS`) |
| `pc` | `rtl/pc.sv` | Clocked program counter |
| `imem` | `rtl/imem.sv` | Instruction memory + testbench write port |
| `dmem` | `rtl/dmem.sv` | Data memory with byte/half/word access |
| `regfile` | `rtl/regfile.sv` | 32 registers, 2 read ports, 1 write port |
| `imm_gen` | `rtl/imm_gen.sv` | Immediate assemble + sign-extend |
| `control` | `rtl/control.sv` | Opcode/funct decode to control signals |
| `alu` | `rtl/alu.sv` | Combinational integer ALU |
| `mdu` | `rtl/mdu.sv` | Combinational multiply/divide unit |
| `csr_file` | `rtl/csr_file.sv` | `mstatus` / `mtvec` / `mepc` / `mcause` |

---

## Teaching SoC

`soc` maps a simple memory map onto the core's data bus:

| Region | Base | Device |
|--------|------|--------|
| ROM (fetch) | `0x0000_0000` | Boot / instruction ROM |
| RAM | `0x1000_0000` | 4 KiB data RAM |
| UART | `0x1001_0000` | `TXDATA` @ +0, `TXSTATUS` @ +4 |

Instruction fetch always comes from ROM. Loads/stores decode to RAM or UART. The UART drives a `uart_tx_byte` / `uart_tx_valid` sideband so the testbench can capture printed characters.

---

## Trap model

| Event | Behavior |
|-------|----------|
| `ecall` | Jump to `mtvec`, set `mcause = 11`, `mepc =` faulting PC |
| `ebreak` | Jump to `mtvec`, set `mcause = 3`, `mepc =` faulting PC |
| `mret` | Jump to `mepc` |

Handlers use **Zicsr** to bump `mepc` by 4 before `mret` (standard software pattern).

---

## Toolchain requirements (Windows)

Developed and tested with **MSYS2 UCRT64**:

| Tool | Purpose |
|------|---------|
| Verilator | RTL to C++ model + simulation |
| g++ / clang++ | Compile generated + testbench C++ |
| make | Build orchestration |
| GTKWave | View `.vcd` waveforms |

On Windows, use `scripts/run.ps1`. It launches MSYS2 and maps the project folder to the `R:` drive so Verilator never sees a path with spaces (`RISC-V cpu`).

---

## How to build and run

### Full CPU tests (recommended)

From PowerShell in the project root:

```powershell
.\scripts\run.ps1          # build + run all CPU tests
.\scripts\run.ps1 waves    # also open GTKWave on waves/cpu.vcd
.\scripts\run.ps1 clean    # remove obj_dir/ and waves/
```

### SoC tests (ROM + RAM + UART)

```powershell
.\scripts\run.ps1 "TOP=soc sim"
```

### Pipelined CPU / SoC (Phases 1–6 complete)

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"   # core ISA tests
.\scripts\run.ps1 "TOP=soc sim"        # pipelined SoC: ROM + RAM + UART
```

See [PIPELINE.md](PIPELINE.md). Default `TOP=cpu` is still the single-cycle wrapper for comparison.

### Real program: UART hello

Assembles `sw/hello/hello.S` with a RISC-V GCC (xPack under `tools/` if present), loads the hex into ROM, and checks UART output:

```powershell
.\scripts\run.ps1 "hello"
```

Expected: `PASS: hello program printed expected string`

### Unit-test one module

```powershell
.\scripts\run.ps1 "TOP=alu sim"
.\scripts\run.ps1 "TOP=regfile sim"
.\scripts\run.ps1 "TOP=imm_gen sim"
.\scripts\run.ps1 "TOP=control sim"
```

### From an MSYS2 UCRT64 shell

```bash
# Prefer a path without spaces, or use the R: mapping
make                 # TOP=cpu by default
make TOP=soc sim
make TOP=alu sim
make waves
make clean
```

A successful full CPU run ends with:

```text
PASS: RV32IM_Zicsr all tests passed
```

A successful SoC run ends with:

```text
PASS: SoC all tests passed
```
---

## What the integration tests cover

`tb/tb_cpu.cpp` loads small machine-code programs into instruction memory and checks register (and trap) results:

1. **ALU / immediates** -- sub, and/or/xor, shifts, slt, immediate ALU ops
2. **Branches** -- beq, bne, blt, bge, bltu, bgeu
3. **Jumps** -- jal, jalr, auipc link/target behavior
4. **Memory** -- sb/sh/sw and lb/lh/lbu/lhu/lw
5. **RV32M** -- mul/mulh/mulhu, div/rem (signed/unsigned), divide-by-zero, fence
6. **Traps + Zicsr** -- ecall, handler does `csrr`/`addi`/`csrw` on `mepc`, then `mret`
7. **CSR ops** -- CSRRW / CSRRS / CSRRC / CSRRWI on `mstatus` / `mtvec` / `mcause`

Waveforms go to `waves/cpu.vcd`. Useful signals in GTKWave: `clk`, `dbg_pc`, `dbg_instr`, `dbg_reg_data`, `dbg_mepc`, `dbg_mcause`.

---

## Design notes

- **Separate I/D memories in simulation** -- classic teaching Harvard-style split (`imem` / `dmem`).
- **IMEM load port** -- the testbench writes program words before releasing reset.
- **Debug peek ports** -- register file and trap CSRs can be observed without a full CSR ISA.
- **Combinational MDU** -- correct for learning and Verilator; a production core would usually multi-cycle or pipeline mul/div.
- **No ELF loader yet** -- instructions are built with small encoder helpers in C++.

---

## Roadmap

- [x] Teaching SoC: ROM + RAM + memory-mapped UART
- [x] [5-stage pipeline](PIPELINE.md) Phases 1–6 complete (pipelined SoC)
- [ ] Interrupts (`mie` / `mip`) and more CSRs
- [ ] Assembler / `riscv32-unknown-elf-gcc` to `.hex` load flow
- [ ] FPGA synthesis (timing / Fmax)

---

## License

Personal / educational project. Feel free to fork and experiment.
