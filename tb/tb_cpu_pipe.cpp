// Phase 1–5 pipeline tests: RV32IM_Zicsr through the 5-stage pipe
#include <cstdio>
#include <cstdint>
#include <vector>
#include "Vcpu_pipe.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

static uint32_t enc_i(uint32_t opc, uint32_t f3, uint32_t rd, uint32_t rs1, int32_t imm) {
    return ((uint32_t)(imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc;
}
static uint32_t enc_u(uint32_t opc, uint32_t rd, uint32_t imm20) {
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc;
}
static uint32_t enc_r(uint32_t f7, uint32_t rs2, uint32_t rs1, uint32_t f3, uint32_t rd) {
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | 0x33;
}
static uint32_t enc_s(uint32_t f3, uint32_t rs2, uint32_t rs1, int32_t imm) {
    uint32_t u = (uint32_t)(imm & 0xFFF);
    return ((u >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((u & 0x1F) << 7) | 0x23;
}
static uint32_t enc_b(uint32_t f3, uint32_t rs1, uint32_t rs2, int32_t off) {
    uint32_t u = (uint32_t)(off & 0x1FFF);
    return ((u >> 12) << 31) | (((u >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15)
         | (f3 << 12) | (((u >> 1) & 0xF) << 8) | (((u >> 11) & 1) << 7) | 0x63;
}
static uint32_t enc_j(uint32_t rd, int32_t off) {
    uint32_t u = (uint32_t)(off & 0x1FFFFF);
    return ((u >> 20) << 31) | (((u >> 1) & 0x3FF) << 21) | (((u >> 11) & 1) << 20)
         | (((u >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F;
}

static uint32_t addi(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x0, rd, rs1, i); }
static uint32_t xori(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x4, rd, rs1, i); }
static uint32_t andi(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x7, rd, rs1, i); }
static uint32_t lui (uint32_t rd, uint32_t imm20) { return enc_u(0x37, rd, imm20); }
static uint32_t auipc(uint32_t rd, uint32_t imm20) { return enc_u(0x17, rd, imm20); }
static uint32_t add_(uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x00, rs2, rs1, 0x0, rd); }
static uint32_t sub (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x20, rs2, rs1, 0x0, rd); }
static uint32_t lw  (uint32_t rd, int32_t i, uint32_t rs1) { return enc_i(0x03, 0x2, rd, rs1, i); }
static uint32_t lb  (uint32_t rd, int32_t i, uint32_t rs1) { return enc_i(0x03, 0x0, rd, rs1, i); }
static uint32_t lbu (uint32_t rd, int32_t i, uint32_t rs1) { return enc_i(0x03, 0x4, rd, rs1, i); }
static uint32_t sw  (uint32_t rs2, int32_t i, uint32_t rs1) { return enc_s(0x2, rs2, rs1, i); }
static uint32_t sb  (uint32_t rs2, int32_t i, uint32_t rs1) { return enc_s(0x0, rs2, rs1, i); }
static uint32_t beq (uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x0, rs1, rs2, o); }
static uint32_t bne (uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x1, rs1, rs2, o); }
static uint32_t blt (uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x4, rs1, rs2, o); }
static uint32_t bge (uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x5, rs1, rs2, o); }
static uint32_t bltu(uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x6, rs1, rs2, o); }
static uint32_t bgeu(uint32_t rs1, uint32_t rs2, int32_t o) { return enc_b(0x7, rs1, rs2, o); }
static uint32_t jal (uint32_t rd, int32_t o) { return enc_j(rd, o); }
static uint32_t jalr(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x67, 0x0, rd, rs1, i); }

static uint32_t mul   (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x0, rd); }
static uint32_t mulh  (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x1, rd); }
static uint32_t mulhu (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x3, rd); }
static uint32_t div_  (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x4, rd); }
static uint32_t divu  (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x5, rd); }
static uint32_t rem   (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x6, rd); }
static uint32_t remu  (uint32_t rd, uint32_t rs1, uint32_t rs2) { return enc_r(0x01, rs2, rs1, 0x7, rd); }

static constexpr uint32_t CSR_MSTATUS = 0x300;
static constexpr uint32_t CSR_MTVEC   = 0x305;
static constexpr uint32_t CSR_MEPC    = 0x341;
static constexpr uint32_t CSR_MCAUSE  = 0x342;

static uint32_t csrrw(uint32_t rd, uint32_t csr, uint32_t rs1) {
    return (csr << 20) | (rs1 << 15) | (0x1 << 12) | (rd << 7) | 0x73;
}
static uint32_t csrrs(uint32_t rd, uint32_t csr, uint32_t rs1) {
    return (csr << 20) | (rs1 << 15) | (0x2 << 12) | (rd << 7) | 0x73;
}
static uint32_t csrrc(uint32_t rd, uint32_t csr, uint32_t rs1) {
    return (csr << 20) | (rs1 << 15) | (0x3 << 12) | (rd << 7) | 0x73;
}
static uint32_t csrrwi(uint32_t rd, uint32_t csr, uint32_t uimm) {
    return (csr << 20) | ((uimm & 0x1F) << 15) | (0x5 << 12) | (rd << 7) | 0x73;
}
static uint32_t csrr(uint32_t rd, uint32_t csr) { return csrrs(rd, csr, 0); }
static uint32_t csrw(uint32_t csr, uint32_t rs1) { return csrrw(0, csr, rs1); }
static uint32_t csrc(uint32_t csr, uint32_t rs1) { return csrrc(0, csr, rs1); }
static uint32_t csrs(uint32_t csr, uint32_t rs1) { return csrrs(0, csr, rs1); }

static uint32_t ecall()  { return 0x00000073u; }
static uint32_t ebreak() { return 0x00100073u; }
static uint32_t mret()   { return 0x30200073u; }
static uint32_t nop()    { return addi(0, 0, 0); }
static uint32_t halt()   { return jal(0, 0); }

struct Sim {
    Vcpu_pipe* top;
    VerilatedVcdC* tfp;
    vluint64_t time_ps;

    Sim() : top(new Vcpu_pipe), tfp(nullptr), time_ps(0) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("waves/cpu_pipe.vcd");
        top->clk = 0;
        top->rst_n = 0;
        top->imem_we = 0;
        top->dbg_reg_addr = 0;
    }

    ~Sim() {
        if (tfp) { tfp->close(); delete tfp; }
        delete top;
    }

    void tick() {
        top->clk = 0;
        top->eval();
        if (tfp) tfp->dump(time_ps);
        time_ps += 5;
        top->clk = 1;
        top->eval();
        if (tfp) tfp->dump(time_ps);
        time_ps += 5;
    }

    void reset(int n = 4) {
        top->rst_n = 0;
        for (int i = 0; i < n; ++i) tick();
        top->rst_n = 1;
        tick();
    }

    void poke_imem(uint32_t addr, uint32_t word) {
        top->imem_we = 1;
        top->imem_waddr = addr;
        top->imem_wdata = word;
        tick();
        top->imem_we = 0;
    }

    void load(const std::vector<uint32_t>& words) {
        top->rst_n = 0;
        top->imem_we = 1;
        for (size_t i = 0; i < words.size(); ++i) {
            top->imem_waddr = static_cast<uint32_t>(i * 4);
            top->imem_wdata = words[i];
            tick();
        }
        for (size_t i = words.size(); i < words.size() + 16; ++i) {
            top->imem_waddr = static_cast<uint32_t>(i * 4);
            top->imem_wdata = nop();
            tick();
        }
        top->imem_we = 0;
    }

    void load_at(uint32_t addr, uint32_t word) {
        top->rst_n = 0;
        poke_imem(addr, word);
    }

    uint32_t reg_x(uint32_t n) {
        top->dbg_reg_addr = n & 0x1F;
        top->eval();
        return top->dbg_reg_data;
    }

    void run_cycles(int n) {
        for (int i = 0; i < n; ++i) tick();
    }

    void run_until_halt(int max_cycles = 120) {
        int seen = 0;
        for (int i = 0; i < max_cycles; ++i) {
            tick();
            if (top->dbg_instr == halt()) {
                if (++seen >= 3) break;
            } else {
                seen = 0;
            }
        }
        run_cycles(8);
    }
};

static int fails = 0;

static void expect_eq(const char* name, uint32_t got, uint32_t exp) {
    if (got != exp) {
        std::printf("FAIL %s: got 0x%08x expected 0x%08x\n", name, got, exp);
        ++fails;
    } else {
        std::printf("PASS %s\n", name);
    }
}

static void drain(Sim& s, int n_instr) {
    s.run_cycles(n_instr + 20);
}

// ---- Phase 1–3 (smoke) ------------------------------------------------------

static void test_smoke_alu_mem_br(Sim& s) {
    std::vector<uint32_t> prog = {
        addi(1, 0, 5), addi(2, 1, 7), addi(3, 2, 1),
        addi(4, 0, 64), addi(5, 0, 0x2A), sw(5, 0, 4), lw(6, 0, 4), addi(7, 6, 1),
        addi(8, 0, 1), addi(9, 0, 1), beq(8, 9, 8), addi(10, 0, 99), addi(10, 0, 42),
        halt(),
    };
    s.load(prog); s.reset(); s.run_until_halt();
    expect_eq("smoke x3", s.reg_x(3), 13);
    expect_eq("smoke load-use x7", s.reg_x(7), 0x2B);
    expect_eq("smoke beq x10", s.reg_x(10), 42);
}

// ---- Phase 4: RV32M ---------------------------------------------------------

static void test_mul_div(Sim& s) {
    std::vector<uint32_t> prog = {
        addi(1, 0, 6),
        addi(2, 0, 7),
        mul(3, 1, 2),            // 42
        addi(4, 0, -4),
        addi(5, 0, 3),
        mul(6, 4, 5),            // -12
        mulh(7, 4, 5),           // -1
        addi(8, 0, -1),
        mulhu(9, 8, 8),          // 0xFFFFFFFE
        addi(10, 0, 20),
        addi(11, 0, 6),
        div_(12, 10, 11),        // 3
        rem(13, 10, 11),         // 2
        addi(14, 0, -20),
        div_(15, 14, 11),        // -3
        rem(16, 14, 11),         // -2
        divu(17, 8, 11),         // 0xFFFFFFFF / 6
        remu(18, 8, 11),         // 3
        addi(19, 0, 5),
        addi(20, 0, 0),
        div_(21, 19, 20),        // div0 → -1
        rem(22, 19, 20),         // rem0 → 5
        halt(),
    };
    s.load(prog); s.reset(); s.run_until_halt();
    expect_eq("mul", s.reg_x(3), 42);
    expect_eq("mul neg", s.reg_x(6), 0xFFFFFFF4u);
    expect_eq("mulh", s.reg_x(7), 0xFFFFFFFFu);
    expect_eq("mulhu", s.reg_x(9), 0xFFFFFFFEu);
    expect_eq("div", s.reg_x(12), 3);
    expect_eq("rem", s.reg_x(13), 2);
    expect_eq("div neg", s.reg_x(15), 0xFFFFFFFDu);
    expect_eq("rem neg", s.reg_x(16), 0xFFFFFFFEu);
    expect_eq("divu", s.reg_x(17), 0x2AAAAAAAu);
    expect_eq("remu", s.reg_x(18), 3);
    expect_eq("div0", s.reg_x(21), 0xFFFFFFFFu);
    expect_eq("rem0", s.reg_x(22), 5);
}

static void test_mul_forward(Sim& s) {
    // Dependent mul chain needs forwarding of MDU result
    std::vector<uint32_t> prog = {
        addi(1, 0, 3),
        addi(2, 0, 5),
        mul(3, 1, 2),     // 15
        addi(4, 3, 1),    // 16 via EX/MEM forward
        halt(),
    };
    s.load(prog); s.reset(); s.run_until_halt();
    expect_eq("mul fwd x3", s.reg_x(3), 15);
    expect_eq("mul fwd x4", s.reg_x(4), 16);
}

// ---- Phase 5: Zicsr + traps -------------------------------------------------

static void test_csr_ops(Sim& s) {
    std::vector<uint32_t> prog = {
        addi(1, 0, 0x55),
        csrw(CSR_MSTATUS, 1),
        csrr(2, CSR_MSTATUS),
        addi(3, 0, 0x0F),
        csrw(CSR_MSTATUS, 3),
        addi(4, 0, 0x03),
        csrc(CSR_MSTATUS, 4),
        csrr(5, CSR_MSTATUS),
        addi(6, 0, 0x30),
        csrs(CSR_MSTATUS, 6),
        csrr(7, CSR_MSTATUS),
        csrrwi(8, CSR_MCAUSE, 11),
        csrr(9, CSR_MCAUSE),
        addi(10, 0, 0x200),
        csrw(CSR_MTVEC, 10),
        csrr(11, CSR_MTVEC),
        halt(),
    };
    s.load(prog); s.reset(); s.run_until_halt();
    expect_eq("csrrw read", s.reg_x(2), 0x55);
    expect_eq("csrrc", s.reg_x(5), 0x0C);
    expect_eq("csrrs", s.reg_x(7), 0x3C);
    expect_eq("csrrwi", s.reg_x(9), 11);
    expect_eq("mtvec", s.reg_x(11), 0x200);
}

static void test_ecall_mret(Sim& s) {
    // Main @0, handler @ default mtvec 0x100
    s.load({
        addi(1, 0, 1),
        ecall(),
        addi(2, 0, 2),
        halt(),
    });
    s.load_at(0x100, csrr(5, CSR_MEPC));
    s.load_at(0x104, addi(5, 5, 4));
    s.load_at(0x108, csrw(CSR_MEPC, 5));
    s.load_at(0x10C, addi(31, 0, 77));
    s.load_at(0x110, mret());

    s.reset();
    s.run_cycles(60);

    expect_eq("handler x31", s.reg_x(31), 77);
    expect_eq("after mret", s.reg_x(2), 2);
    expect_eq("mcause", s.top->dbg_mcause, 11);
    expect_eq("mepc after", s.top->dbg_mepc, 0x8);  // bumped to return addr
}

static void test_ebreak(Sim& s) {
    s.load({
        addi(1, 0, 1),
        ebreak(),
        addi(2, 0, 9),
        halt(),
    });
    s.load_at(0x100, csrr(5, CSR_MEPC));
    s.load_at(0x104, addi(5, 5, 4));
    s.load_at(0x108, csrw(CSR_MEPC, 5));
    s.load_at(0x10C, addi(30, 0, 88));
    s.load_at(0x110, mret());

    s.reset();
    s.run_cycles(60);

    expect_eq("ebreak handler x30", s.reg_x(30), 88);
    expect_eq("ebreak after mret", s.reg_x(2), 9);
    expect_eq("ebreak mcause", s.top->dbg_mcause, 3);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Sim s;

    std::printf("=== Phase 4–5 pipeline (RV32IM_Zicsr) ===\n");
    std::printf("-- Smoke --\n");
    test_smoke_alu_mem_br(s);

    std::printf("-- RV32M --\n");
    test_mul_div(s);
    test_mul_forward(s);

    std::printf("-- Zicsr / traps --\n");
    test_csr_ops(s);
    test_ecall_mret(s);
    test_ebreak(s);

    if (fails == 0) {
        std::printf("PASS: Phase 4–5 pipeline tests passed\n");
        return 0;
    }
    std::printf("FAIL: %d Phase 4–5 check(s) failed\n", fails);
    return 1;
}
