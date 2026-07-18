// RV32I Phase-1 integration tests for the single-cycle CPU
#include <cstdio>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>
#include "Vcpu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

// ---- Encoders ---------------------------------------------------------------

static uint32_t enc_i(uint32_t opc, uint32_t f3, uint32_t rd, uint32_t rs1, int32_t imm) {
    return ((uint32_t)(imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc;
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
static uint32_t enc_u(uint32_t opc, uint32_t rd, uint32_t imm20) {
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc;
}
static uint32_t enc_j(uint32_t rd, int32_t off) {
    uint32_t u = (uint32_t)(off & 0x1FFFFF);
    return ((u >> 20) << 31) | (((u >> 1) & 0x3FF) << 21) | (((u >> 11) & 1) << 20)
         | (((u >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F;
}

static uint32_t addi (uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x0, rd, rs1, i); }
static uint32_t andi (uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x7, rd, rs1, i); }
static uint32_t ori  (uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x6, rd, rs1, i); }
static uint32_t xori (uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x4, rd, rs1, i); }
static uint32_t slti (uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x2, rd, rs1, i); }
static uint32_t sltiu(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x3, rd, rs1, i); }
static uint32_t slli (uint32_t rd, uint32_t rs1, uint32_t sh){ return enc_i(0x13, 0x1, rd, rs1, (int32_t)(sh & 0x1F)); }
static uint32_t srli (uint32_t rd, uint32_t rs1, uint32_t sh){ return enc_i(0x13, 0x5, rd, rs1, (int32_t)(sh & 0x1F)); }
static uint32_t srai (uint32_t rd, uint32_t rs1, uint32_t sh){ return enc_i(0x13, 0x5, rd, rs1, (int32_t)(0x400 | (sh & 0x1F))); }

static uint32_t add_ (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x0, rd); }
static uint32_t sub  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x20, rs2, rs1, 0x0, rd); }
static uint32_t and_ (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x7, rd); }
static uint32_t or_  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x6, rd); }
static uint32_t xor_ (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x4, rd); }
static uint32_t sll  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x1, rd); }
static uint32_t srl  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x5, rd); }
static uint32_t sra  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x20, rs2, rs1, 0x5, rd); }
static uint32_t slt  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x2, rd); }
static uint32_t sltu (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x00, rs2, rs1, 0x3, rd); }

static uint32_t lb  (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x0, rd, rs1, i); }
static uint32_t lh  (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x1, rd, rs1, i); }
static uint32_t lw  (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x2, rd, rs1, i); }
static uint32_t lbu (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x4, rd, rs1, i); }
static uint32_t lhu (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x5, rd, rs1, i); }
static uint32_t sb  (uint32_t rs2, int32_t i, uint32_t rs1){ return enc_s(0x0, rs2, rs1, i); }
static uint32_t sh  (uint32_t rs2, int32_t i, uint32_t rs1){ return enc_s(0x1, rs2, rs1, i); }
static uint32_t sw  (uint32_t rs2, int32_t i, uint32_t rs1){ return enc_s(0x2, rs2, rs1, i); }

static uint32_t beq (uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x0, rs1, rs2, o); }
static uint32_t bne (uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x1, rs1, rs2, o); }
static uint32_t blt (uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x4, rs1, rs2, o); }
static uint32_t bge (uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x5, rs1, rs2, o); }
static uint32_t bltu(uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x6, rs1, rs2, o); }
static uint32_t bgeu(uint32_t rs1, uint32_t rs2, int32_t o){ return enc_b(0x7, rs1, rs2, o); }

static uint32_t jal (uint32_t rd, int32_t o){ return enc_j(rd, o); }
static uint32_t jalr(uint32_t rd, uint32_t rs1, int32_t i){ return enc_i(0x67, 0x0, rd, rs1, i); }
static uint32_t lui  (uint32_t rd, uint32_t imm20){ return enc_u(0x37, rd, imm20); }
static uint32_t auipc(uint32_t rd, uint32_t imm20){ return enc_u(0x17, rd, imm20); }

// RV32M
static uint32_t mul   (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x0, rd); }
static uint32_t mulh  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x1, rd); }
static uint32_t mulhsu(uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x2, rd); }
static uint32_t mulhu (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x3, rd); }
static uint32_t div_  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x4, rd); }
static uint32_t divu  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x5, rd); }
static uint32_t rem   (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x6, rd); }
static uint32_t remu  (uint32_t rd, uint32_t rs1, uint32_t rs2){ return enc_r(0x01, rs2, rs1, 0x7, rd); }

static uint32_t ecall () { return 0x00000073u; }
static uint32_t ebreak() { return 0x00100073u; }
static uint32_t mret  () { return 0x30200073u; }
static uint32_t fence () { return 0x0000000fu; }

static uint32_t halt() { return jal(0, 0); }

// ---- Sim helpers ------------------------------------------------------------

static void tick(Vcpu* dut, VerilatedVcdC* tr, vluint64_t& t) {
    dut->clk = 0; dut->eval(); tr->dump(t++);
    dut->clk = 1; dut->eval(); tr->dump(t++);
}

static void load_program(Vcpu* dut, VerilatedVcdC* tr, vluint64_t& t,
                         const std::vector<uint32_t>& prog) {
    dut->imem_we = 1;
    for (size_t i = 0; i < prog.size(); i++) {
        dut->imem_waddr = (uint32_t)(i * 4);
        dut->imem_wdata = prog[i];
        tick(dut, tr, t);
    }
    dut->imem_we = 0;
    dut->imem_waddr = 0;
    dut->imem_wdata = 0;
}

static void load_at(Vcpu* dut, VerilatedVcdC* tr, vluint64_t& t,
                    uint32_t addr, uint32_t word) {
    dut->imem_we    = 1;
    dut->imem_waddr = addr;
    dut->imem_wdata = word;
    tick(dut, tr, t);
    dut->imem_we = 0;
}

static uint32_t read_reg(Vcpu* dut, uint8_t n) {
    dut->dbg_reg_addr = n;
    dut->eval();
    return dut->dbg_reg_data;
}

struct Expect {
    uint8_t  reg;
    uint32_t value;
    const char* label;
};

static int run_case(Vcpu* dut, VerilatedVcdC* tr, vluint64_t& t,
                    const char* name, const std::vector<uint32_t>& prog,
                    const std::vector<Expect>& expects, int cycles) {
    printf("-- %s --\n", name);

    dut->rst_n = 0;
    dut->imem_we = 0;
    dut->dbg_reg_addr = 0;
    tick(dut, tr, t);

    load_program(dut, tr, t, prog);

    dut->rst_n = 1;
    tick(dut, tr, t);
    for (int i = 0; i < cycles; i++)
        tick(dut, tr, t);

    int fails = 0;
    for (const auto& e : expects) {
        uint32_t got = read_reg(dut, e.reg);
        if (got != e.value) {
            printf("FAIL: %-16s x%u=0x%08X exp=0x%08X  pc=0x%08X\n",
                   e.label, e.reg, got, e.value, dut->dbg_pc);
            fails++;
        } else {
            printf("PASS: %-16s x%u=0x%08X\n", e.label, e.reg, got);
        }
    }
    return fails;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vcpu* dut = new Vcpu;
    Verilated::traceEverOn(true);
    VerilatedVcdC* tr = new VerilatedVcdC;
    dut->trace(tr, 99);
    tr->open("waves/cpu.vcd");

    vluint64_t t = 0;
    int fails = 0;

    // ---- ALU R-type + I-type ------------------------------------------------
    fails += run_case(dut, tr, t, "ALU ops", {
        addi(1, 0, 10),          // x1 = 10
        addi(2, 0, 3),           // x2 = 3
        sub (3, 1, 2),           // x3 = 7
        and_(4, 1, 2),           // x4 = 2
        or_ (5, 1, 2),           // x5 = 11
        xor_(6, 1, 2),           // x6 = 9
        sll (7, 1, 2),           // x7 = 80
        addi(8, 0, -32),         // x8 = 0xFFFFFFE0
        addi(9, 0, 2),           // x9 = 2
        srl (10, 8, 9),          // x10 = 0x3FFFFFF8
        sra (11, 8, 9),          // x11 = 0xFFFFFFF8
        slt (12, 2, 1),          // x12 = 1 (3 < 10)
        sltu(13, 8, 2),          // x13 = 0 (big unsigned < 3? no)
        andi(14, 1, 12),         // x14 = 8
        ori (15, 1, 1),          // x15 = 11
        xori(16, 1, 1),          // x16 = 11
        slti(17, 2, 10),         // x17 = 1
        sltiu(18, 8, 3),         // x18 = 0
        slli(19, 2, 4),          // x19 = 48
        srli(20, 8, 4),          // x20 = 0x0FFFFFFE
        srai(21, 8, 4),          // x21 = 0xFFFFFFFE
        halt(),
    }, {
        {3,  7,            "sub"},
        {4,  2,            "and"},
        {5,  11,           "or"},
        {6,  9,            "xor"},
        {7,  80,           "sll"},
        {10, 0x3FFFFFF8u,  "srl"},
        {11, 0xFFFFFFF8u,  "sra"},
        {12, 1,            "slt"},
        {13, 0,            "sltu"},
        {14, 8,            "andi"},
        {15, 11,           "ori"},
        {16, 11,           "xori"},
        {17, 1,            "slti"},
        {18, 0,            "sltiu"},
        {19, 48,           "slli"},
        {20, 0x0FFFFFFEu,  "srli"},
        {21, 0xFFFFFFFEu,  "srai"},
    }, 40);

    // ---- Branches -----------------------------------------------------------
    // Each case: set regs, branch over a "poison" addi, land on success addi
    fails += run_case(dut, tr, t, "Branches", {
        // beq taken
        addi(1, 0, 5),
        addi(2, 0, 5),
        beq (1, 2, 8),
        addi(3, 0, 99),
        addi(3, 0, 1),

        // bne taken
        addi(4, 0, 1),
        addi(5, 0, 2),
        bne (4, 5, 8),
        addi(6, 0, 99),
        addi(6, 0, 1),

        // blt taken (-1 < 1)
        addi(7, 0, -1),
        addi(8, 0, 1),
        blt (7, 8, 8),
        addi(9, 0, 99),
        addi(9, 0, 1),

        // bge taken (5 >= 5)
        addi(10, 0, 5),
        addi(11, 0, 5),
        bge (10, 11, 8),
        addi(12, 0, 99),
        addi(12, 0, 1),

        // bltu taken (1 < 0xFFFFFFFF)
        addi(13, 0, 1),
        addi(14, 0, -1),
        bltu(13, 14, 8),
        addi(15, 0, 99),
        addi(15, 0, 1),

        // bgeu taken (0xFFFFFFFF >= 1)
        bgeu(14, 13, 8),
        addi(16, 0, 99),
        addi(16, 0, 1),

        halt(),
    }, {
        {3,  1, "beq"},
        {6,  1, "bne"},
        {9,  1, "blt"},
        {12, 1, "bge"},
        {15, 1, "bltu"},
        {16, 1, "bgeu"},
    }, 50);

    // ---- Jumps: jalr + auipc + jal ------------------------------------------
    // 0x00: auipc x1, 0        -> x1 = 0x00 (PC)
    // 0x04: addi  x1, x1, 16   -> x1 = 0x10  (target of jalr)
    // 0x08: jalr  x2, x1, 0    -> jump to 0x10, x2 = 0x0C
    // 0x0C: addi  x3, x0, 99   -> skipped
    // 0x10: addi  x3, x0, 42
    // 0x14: jal   x4, 8        -> to 0x1C, x4 = 0x18
    // 0x18: addi  x5, x0, 99   -> skipped
    // 0x1C: addi  x5, x0, 7
    // 0x20: halt
    fails += run_case(dut, tr, t, "Jumps", {
        auipc(1, 0),
        addi(1, 1, 16),
        jalr(2, 1, 0),
        addi(3, 0, 99),
        addi(3, 0, 42),
        jal(4, 8),
        addi(5, 0, 99),
        addi(5, 0, 7),
        halt(),
    }, {
        {2, 0x0C, "jalr link"},
        {3, 42,   "jalr target"},
        {4, 0x18, "jal link"},
        {5, 7,    "jal target"},
    }, 20);

    // ---- Memory: sb/sh/sw + lb/lh/lbu/lhu/lw --------------------------------
    // Build word 0xAABBCCDD at addr 32 via bytes, then half/word checks
    fails += run_case(dut, tr, t, "Memory", {
        lui (1, 0xAABBCCDD >> 12),       // rough - better use immediates
        // Put 0xDD, 0xCC, 0xBB, 0xAA via sb at offsets 32..35
        addi(1, 0, 0xDD),
        sb  (1, 32, 0),
        addi(1, 0, 0xCC),
        sb  (1, 33, 0),
        addi(1, 0, 0xBB),
        sb  (1, 34, 0),
        addi(1, 0, 0xAA),
        sb  (1, 35, 0),

        // lb / lbu at byte 35 (0xAA) -> sign extend vs zero extend
        lb  (2, 35, 0),                  // 0xFFFFFFAA
        lbu (3, 35, 0),                  // 0x000000AA

        // sh store 0x1234 at addr 40, then lh/lhu
        // 0x1234 does not fit in a 12-bit addi immediate — build it:
        addi(4, 0, 0x12),
        slli(4, 4, 8),
        addi(4, 4, 0x34),                // x4 = 0x1234
        sh  (4, 40, 0),
        lh  (5, 40, 0),                  // 0x00001234
        // negative half
        addi(6, 0, -2),                  // 0xFFFFFFFE
        sh  (6, 44, 0),
        lh  (7, 44, 0),                  // 0xFFFFFFFE
        lhu (8, 44, 0),                  // 0x0000FFFE

        // word round-trip: 0xA5A5A5A5
        lui (9, 0xA5A5A),
        xori(9, 9, 0x5A5),               // 0xA5A5A000 ^ 0x5A5 = 0xA5A5A5A5
        sw  (9, 48, 0),
        lw  (10, 48, 0),

        halt(),
    }, {
        {2,  0xFFFFFFAAu, "lb"},
        {3,  0x000000AAu, "lbu"},
        {5,  0x00001234u, "lh"},
        {7,  0xFFFFFFFEu, "lh neg"},
        {8,  0x0000FFFEu, "lhu"},
        {10, 0xA5A5A5A5u,"lw"},
    }, 40);

    // ---- Original smoke still covered ---------------------------------------
    fails += run_case(dut, tr, t, "Smoke", {
        addi(1, 0, 5),
        addi(2, 0, 7),
        add_(3, 1, 2),
        sw  (3, 16, 0),
        lw  (4, 16, 0),
        beq (3, 4, 8),
        addi(5, 0, 99),
        addi(5, 0, 42),
        lui (6, 0xABCDE),
        xor_(7, 1, 2),
        halt(),
    }, {
        {3, 12,           "add"},
        {4, 12,           "lw/sw"},
        {5, 42,           "beq"},
        {6, 0xABCDE000u,  "lui"},
        {7, 2,            "xor"},
    }, 20);

    // ---- RV32M --------------------------------------------------------------
    fails += run_case(dut, tr, t, "RV32M", {
        addi(1, 0, 6),
        addi(2, 0, 7),
        mul (3, 1, 2),            // 42
        addi(4, 0, -4),
        addi(5, 0, 3),
        mul (6, 4, 5),            // -12
        mulh(7, 4, 5),            // high of -12 → -1
        addi(8, 0, -1),
        mulhu(9, 8, 8),           // (2^32-1)^2 >> 32 = 2^32-2
        addi(10, 0, 20),
        addi(11, 0, 6),
        div_(12, 10, 11),         // 3
        rem (13, 10, 11),         // 2
        addi(14, 0, -20),
        div_(15, 14, 11),         // -3
        rem (16, 14, 11),         // -2
        divu(17, 8, 11),
        remu(18, 8, 11),
        addi(19, 0, 5),
        addi(20, 0, 0),
        div_(21, 19, 20),         // -1 on div0
        rem (22, 19, 20),         // 5
        fence(),
        halt(),
    }, {
        {3,  42,           "mul"},
        {6,  0xFFFFFFF4u,  "mul neg"},
        {7,  0xFFFFFFFFu,  "mulh"},
        {9,  0xFFFFFFFEu,  "mulhu"},
        {12, 3,            "div"},
        {13, 2,            "rem"},
        {15, 0xFFFFFFFDu,  "div neg"},
        {16, 0xFFFFFFFEu,  "rem neg"},
        {17, 0x2AAAAAAAu,  "divu"},
        {18, 3,            "remu"},
        {21, 0xFFFFFFFFu,  "div0"},
        {22, 5,            "rem0"},
    }, 50);

    // ---- Traps: ecall → handler @0x100 → mret -------------------------------
    {
        printf("-- Traps --\n");
        dut->rst_n = 0;
        dut->imem_we = 0;
        tick(dut, tr, t);

        load_program(dut, tr, t, {
            addi(1, 0, 1),
            ecall(),
            addi(2, 0, 2),
            halt(),
        });
        load_at(dut, tr, t, 0x100, addi(31, 0, 77));
        load_at(dut, tr, t, 0x104, mret());

        dut->rst_n = 1;
        tick(dut, tr, t);
        for (int i = 0; i < 20; i++)
            tick(dut, tr, t);

        auto check = [&](const char* label, uint32_t got, uint32_t exp) {
            if (got != exp) {
                printf("FAIL: %-16s got=0x%08X exp=0x%08X\n", label, got, exp);
                fails++;
            } else {
                printf("PASS: %-16s 0x%08X\n", label, got);
            }
        };
        check("handler x31", read_reg(dut, 31), 77);
        check("after mret",  read_reg(dut, 2),  2);
        check("mcause",      dut->dbg_mcause,   11);
    }

    tr->close();
    delete tr;
    delete dut;

    if (fails == 0) {
        printf("PASS: RV32IM + traps all tests passed\n");
        return 0;
    }
    printf("FAIL: %d check(s) failed\n", fails);
    return 1;
}
