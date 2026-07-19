# Guide: Turning This Project into a 5-Stage Pipelined RISC-V CPU

This guide is written for **this** repository: a working **single-cycle** RV32IM_Zicsr core (`rtl/cpu_core.sv`) plus a teaching SoC (`rtl/soc.sv`). It explains how to evolve the core into a classic **5-stage pipeline** without throwing away the ISA, tests, or memory map.

Keep the single-cycle core working until the pipeline passes the same (or a staged subset of) tests. Prefer a branch such as `pipeline` so `main` stays the known-good 1-cycle CPU.

---

## 1. Goal

| Today | Target |
|-------|--------|
| 1 instruction / long cycle | Up to 5 instructions overlapping |
| All work in one combinational path | IF → ID → EX → MEM → WB |
| No hazards | Forwarding + load-use stall + branch/trap flush |

**Same ISA** (eventually RV32IM_Zicsr). **Different microarchitecture.**

The SoC memory map can stay:

| Region | Base |
|--------|------|
| ROM (fetch) | `0x0000_0000` |
| RAM | `0x1000_0000` |
| UART | `0x1001_0000` |

---

## 2. What you already have (reuse checklist)

| Block | File | Pipeline home |
|-------|------|----------------|
| PC | `pc.sv` | IF (plus hazard stalls / redirects) |
| Instruction memory / ROM | `imem.sv` / `rom.sv` | IF |
| Decode / control | `control.sv` | ID |
| Immediate | `imm_gen.sv` | ID |
| Register file | `regfile.sv` | ID read / WB write |
| ALU | `alu.sv` | EX |
| MDU | `mdu.sv` | EX (Phase 3; may stay combinational at first) |
| Data memory / RAM / UART | `dmem.sv` / `ram.sv` / `uart.sv` | MEM |
| CSR file | `csr_file.sv` | Phase 4 (late EX / MEM / WB — decide one policy) |

**New RTL you will add:**

- Pipeline register modules (or one `pipe_reg_*.sv` per boundary)
- `hazard_unit.sv` — stall + flush controls
- `forward_unit.sv` — EX/MEM and MEM/WB bypass mux selects

**Recommended layout:**

```text
rtl/
  cpu_core.sv          # rewrite as pipelined top (or cpu_core_pipe.sv first)
  pipe_if_id.sv
  pipe_id_ex.sv
  pipe_ex_mem.sv
  pipe_mem_wb.sv
  forward_unit.sv
  hazard_unit.sv
  ... existing modules unchanged where possible ...
```

Keep `cpu.sv` as “core + local imem/dmem” so `tb_cpu` still has a top to bind to.

---

## 3. The five stages (mapped to your signals)

### IF — Instruction Fetch

**Combines:** `pc`, `imem_addr`, `imem_rdata`, `pc_plus4`.

**Each cycle:**

1. Present `pc` to instruction memory.
2. Latch into IF/ID: `{pc, pc_plus4, instr}` (and later a `valid` bit).
3. Default next PC = `pc + 4`, unless redirected (branch, jal, jalr, trap, mret) or stalled.

**Stall:** when load-use hazard fires, freeze PC and freeze IF/ID (or rewrite IF/ID with the same instruction).

**Flush:** when a taken branch/jump/trap resolves, clear IF/ID (insert bubble / NOP).

### ID — Decode & register read

**Combines:** field extract, `control`, `imm_gen`, regfile **reads**.

Latch into ID/EX roughly:

| Field | Source |
|-------|--------|
| `pc`, `pc_plus4` | IF/ID |
| `rs1_data`, `rs2_data` | regfile |
| `imm` | `imm_gen` |
| `rs1`, `rs2`, `rd` | instruction fields |
| Control | `reg_write`, `alu_src_*`, `alu_op`, `use_mdu`, `mem_read`, `mem_write`, `result_src`, `branch`, `jump`, `jalr`, `funct3`, … |

**WB write** to the regfile happens in the same cycle as ID reads (your regfile is sync-write, async-read). Prefer either:

- **Forwarding** covering MEM/WB → EX (required anyway), and/or
- Optional **ID bypass**: if `MEM/WB.rd == ID.rs*` and `reg_write`, feed WB data into the ID/EX operand path.

Do not rely on “write then read same cycle” without an explicit policy — pick one and test it.

### EX — Execute

**Combines:** ALU/MDU operand muxes (now with **forwarding**), `alu`, `mdu`, branch compare, effective address, jalr target.

Latch into EX/MEM:

- `alu_result` / `exec_result`
- `rs2_data` (for stores; may also be forwarded)
- `rd`, `funct3`
- Control: `reg_write`, `mem_read`, `mem_write`, `result_src`, …
- Branch decision + target (or resolve branch here and send redirect to IF)

**Classic teaching choice:** resolve branches in EX; flush IF/ID (and often a bubble in ID/EX) on taken branch/jump.

### MEM — Memory

**Combines:** your data bus (`dmem_*`) → RAM/UART in the SoC.

Latch into MEM/WB:

- `mem_rdata` (loads)
- `alu_result` (pass-through for non-loads)
- `rd`, `reg_write`, `result_src`, …

### WB — Writeback

**Combines:** `result_src` mux → `rd_data` → regfile `we`.

Same mux idea as today in `cpu_core.sv`:

- `00` ALU/MDU
- `01` memory
- `10` `pc+4` (jal/jalr link)
- `11` CSR (Phase 4)

---

## 4. Pipeline registers (minimum fields)

Use a `valid` (or `bubble`) bit in every stage. A flush clears `valid`; a stall holds the register.

### IF/ID

```text
valid, pc, pc_plus4, instr
```

### ID/EX

```text
valid, pc, pc_plus4,
rs1_data, rs2_data, imm,
rs1, rs2, rd, funct3, funct7,  // as needed
reg_write, mem_read, mem_write, result_src,
alu_src_a, alu_src_b, alu_op, use_mdu,
branch, jump, jalr
# Phase 4: csr_op, csr_addr, csr_use_imm, trap bits, mret, ...
```

### EX/MEM

```text
valid,
alu_result, rs2_data,  // store data
rd, funct3,
reg_write, mem_read, mem_write, result_src
# optional: pc_plus4 if link resolved late
```

### MEM/WB

```text
valid,
alu_result, mem_rdata, pc_plus4 (if needed),
rd, reg_write, result_src
```

---

## 5. Hazards (implement in this order)

### 5.1 Data hazard → forwarding

Example:

```asm
addi x1, x0, 5
add  x2, x1, x1
```

`add` needs `x1` in EX before `addi` reaches WB.

**Forward unit** (combinational), typical priority:

1. If `EX/MEM.reg_write && EX/MEM.rd != 0 && EX/MEM.rd == ID/EX.rs1` → forward `EX/MEM.alu_result` to ALU A  
2. Else if `MEM/WB.reg_write && MEM/WB.rd != 0 && MEM/WB.rd == ID/EX.rs1` → forward WB mux result to ALU A  
3. Same for `rs2`  
4. Else use ID/EX register values  

Wire these selects into the EX operand muxes (extend today’s `alu_a` / `alu_b` logic).

### 5.2 Load-use → stall + forward

```asm
lw   x1, 0(x2)
addi x3, x1, 1
```

Detect in **ID** (looking at ID/EX load):

```text
stall if ID/EX.mem_read
     && ID/EX.rd != 0
     && (ID/EX.rd == IF/ID.rs1 || ID/EX.rd == IF/ID.rs2)
```

On stall:

- Freeze PC  
- Freeze IF/ID  
- Insert bubble into ID/EX (`valid=0` / clear control so no write/mem)  

Next cycle, forwarding from MEM/WB supplies the load data.

### 5.3 Control hazard → flush

When EX decides `take_branch | jump | jalr` (and later trap/mret):

- Set PC to target  
- Clear IF/ID (`valid=0`)  
- Optionally clear ID/EX if the branch was already past ID  

No predictor in v1: **always assume not-taken** (fetch `pc+4`), pay a flush penalty when taken.

### 5.4 Traps / CSR (Phase 4 only)

Treat like a redirect + flush when the trapping instruction reaches a chosen stage (often EX or MEM). Set `mepc` to that instruction’s PC (you already use faulting PC in the 1-cycle core — keep that architectural rule). Flush younger instructions so they never write registers or memory.

---

## 6. Suggested implementation phases

Do **not** pipeline everything on day one. Gate each phase with tests.

### Phase 0 — Prep (½–1 day)

1. Branch from known-good single-cycle.  
2. Add `dbg` visibility per stage if helpful: `dbg_pc_if`, `dbg_pc_id`, …  
3. Decide: rewrite `cpu_core.sv` in place, or add `cpu_core_pipe.sv` and switch `cpu.sv` / `soc.sv` when ready.  
4. Keep `tb_cpu.cpp` encoders; you will **change expectations about cycle counts** (see §7).

### Phase 1 — Skeleton pipeline, no hazards (ALU immediates only) ✅

**Status: implemented** (`rtl/cpu_core_pipe.sv`, `rtl/cpu_pipe.sv`, `tb/tb_cpu_pipe.cpp`)

**Goal:** `addi` / `lui` / `auipc` through five stages with **no dependent pairs**.

1. Insert IF/ID, ID/EX, EX/MEM, MEM/WB.  
2. Move logic into stages; WB writes regfile.  
3. PC always `+4` (no branches yet).  
4. Test programs with **independent** registers only.

**Run:**

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"
```

**Exit criteria:** Independent ALU/imm ops match single-cycle results after enough cycles. ✅

Stubs ready for later phases: `rtl/forward_unit.sv`, `rtl/hazard_unit.sv` (currently no-ops).

The single-cycle core (`cpu_core` / `TOP=cpu`) is unchanged and remains the default.

### Phase 2 — Forwarding + load-use stall ✅

**Status: implemented** (`forward_unit.sv`, `hazard_unit.sv`, tests in `tb_cpu_pipe.cpp`)

1. `forward_unit` — EX/MEM (prio) then MEM/WB; never forward `x0`.  
2. `hazard_unit` — load-use stall when ID/EX load’s `rd` matches IF/ID `rs1`/`rs2` (only if that instr uses the source).  
3. Loads/stores through MEM with store-data forwarding via `fwd_rs2`.  
4. **WB→ID bypass** on regfile reads (sync write not visible same cycle).  

**Run:**

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"
```

**Exit criteria:** Dependent ALU and load-use programs match architectural results. ✅

### Phase 3 — Branches and jumps ✅

**Status: implemented** (resolve in EX, PC redirect, flush IF/ID **and** bubble ID/EX so fall-through cannot execute)

1. `beq`/`bne`/`blt`/`bge`/`bltu`/`bgeu`, `jal`, `jalr` resolved in **EX** (with forwarding).  
2. On redirect: `pc_next = target`, `flush_if_id` squashes the fall-through instr.  
3. Predict **not-taken** (always fetch `PC+4` until EX decides).  
4. `jal`/`jalr` link value is that instruction’s `pc+4` via `id_ex_pc4` → WB.  

**Run:**

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"
```

**Exit criteria:** Branch/jump tests in `tb_cpu_pipe.cpp` pass. ✅

### Phase 4 — RV32M ✅

**Status: implemented** — combinational `mdu` in EX; results enter `ex_wb_data` and forward like ALU.

**Exit criteria:** mul/div/rem (+ forwarding) tests pass. ✅

### Phase 5 — Zicsr + traps ✅

**Status: implemented**

1. CSR RMW in **EX** (old value → `rd` via pipe; write on same EX cycle).  
2. `ecall` / `ebreak`: trap in EX → `mepc` = faulting PC, `mcause` = 11/3, redirect to `mtvec`, flush IF/ID.  
3. `mret`: redirect to `mepc`, flush IF/ID.  
4. Handler software bumps `mepc` by 4 before `mret` (same as single-cycle).  

**Run:**

```powershell
.\scripts\run.ps1 "TOP=cpu_pipe sim"
```

**Exit criteria:** `PASS: Phase 4–5 pipeline tests passed`. ✅

### Phase 6 — SoC ✅

**Status: implemented** — `soc.sv` instantiates `cpu_core_pipe`.

**Run:**

```powershell
.\scripts\run.ps1 "TOP=soc sim"
```

**Exit criteria:** boot / RAM / UART hello still pass on the pipelined core. ✅

---

## 7. Testing strategy

### Architectural vs microarchitectural

Tests should check **register/memory/UART results**, not “finishes in N cycles,” until you add performance tests.

Update the testbench runner:

- After reset, run **more cycles** (pipeline fill + stalls + flush penalties).  
- Halt: still `jal x0, 0`, but detect when that instruction reaches **WB** (or when PC has been spinning on halt for several cycles).  
- Optional: retire counter — increment when `MEM/WB.valid && !bubble`.

### Suggested new / split tests

| Test file idea | Focus |
|----------------|--------|
| Keep `tb_cpu.cpp` | Full ISA once Phase 5 done |
| `tb_pipe_forward.cpp` | addi/add chains, no loads |
| `tb_pipe_loaduse.cpp` | lw then use |
| `tb_pipe_branch.cpp` | taken/not-taken, jalr |
| Existing `tb_soc.cpp` | Phase 6 |

### GTKWave checklist

Useful signals:

- `clk`, `rst_n`  
- Per-stage PC + `valid`  
- `stall`, `flush`  
- Forward selects  
- `dbg_reg_data`  
- `dmem_addr` / `dmem_we` / UART `tx_valid`

---

## 8. Design decisions (pick and document)

Record your choices in a short comment at the top of `cpu_core.sv`:

| Decision | Common teaching choice |
|----------|-------------------------|
| Branch stage | EX |
| Predictor | None (not-taken) |
| Regfile read/write same cycle | Forwarding from WB; no special ID bypass required if EX always gets forwarded data |
| Store data forwarding | Forward to `rs2` path like ALU B |
| Mul/div | Combinational in EX initially |
| CSR write stage | WB (or MEM) — one place only |
| Bubble encoding | `valid=0` clears `reg_write/mem_*` |

---

## 9. Common pitfalls

1. **Forgetting `rd == x0`** — never forward or stall on writes to `x0`.  
2. **Stalling but still writing** — bubble must clear `reg_write` and `mem_write`.  
3. **Flushing too little** — taken branch leaves a wrong instruction in IF/ID.  
4. **Wrong PC for `jal` link** — must be that instruction’s `pc+4`, not the current IF PC.  
5. **Load-use detect using wrong stage** — compare **ID/EX** load’s `rd` to **IF/ID**’s `rs1/rs2`.  
6. **Comparing cycle counts to single-cycle** — results should match; latency will not.  
7. **Pipelining CSR before RV32I is solid** — precise traps on a buggy pipe waste weeks.

---

## 10. Effort sketch (rough)

| Phase | Scope | Rough effort |
|-------|--------|--------------|
| 0–1 | Skeleton + independent ALU | 1–2 days |
| 2 | Forward + load-use | 2–4 days |
| 3 | Branches/jumps | 2–3 days |
| 4 | M extension | 0.5–1 day |
| 5 | Zicsr/traps | 2–4 days |
| 6 | SoC bring-up | 0.5 day |

Depends on prior pipeline experience; debugging hazards dominates wall time.

---

## 11. Definition of done

You can call the port complete when:

1. `make` / `.\scripts\run.ps1` passes full CPU ISA tests on the pipelined core.  
2. `.\scripts\run.ps1 "TOP=soc sim"` passes.  
3. README documents: 5-stage, forwarding, load-use stall, flush-on-branch, no predictor.  
4. Single-cycle core is either removed or kept as `cpu_core_sc.sv` for comparison.

---

## 12. Optional next upgrades (after the classic 5-stage)

- Static branch predictor / BTB  
- Multi-cycle or pipelined MDU  
- Memory wait states (ready/valid bus)  
- Interrupts (`mie`/`mip`)  
- FPGA synthesis and Fmax comparison vs single-cycle  

---

## Quick start (when you begin coding)

1. Create branch `pipeline`.  
2. Copy `cpu_core.sv` → implement Phase 1 skeleton with pipeline regs.  
3. Add a tiny TB program: three independent `addi`s + halt; check `x1..x3`.  
4. Only then add forwarding (Phase 2).  

Do not start with traps or the full `tb_cpu` suite on day one.

When you want to implement a phase in this repo, say which phase (1–6) and we can do it step by step in RTL.
