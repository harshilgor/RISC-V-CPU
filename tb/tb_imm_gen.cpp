// Verilator testbench for the RV32I immediate generator
#include <cstdio>
#include <cstdint>
#include "Vimm_gen.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

enum ImmSrc : uint8_t {
    IMM_I = 0b000,
    IMM_S = 0b001,
    IMM_B = 0b010,
    IMM_U = 0b011,
    IMM_J = 0b100,
};

// Pack helper: build a 32-bit instr with only the bits that matter for imm.
// Other fields (opcode/rd/rs) can be zero for these unit tests.

static uint32_t pack_i(int32_t imm12) {
    // imm in [31:20]
    return ((uint32_t)(imm12 & 0xFFF)) << 20;
}

static uint32_t pack_s(int32_t imm12) {
    // {imm[11:5] -> [31:25], imm[4:0] -> [11:7]}
    uint32_t u = (uint32_t)(imm12 & 0xFFF);
    return ((u >> 5) << 25) | ((u & 0x1F) << 7);
}

static uint32_t pack_b(int32_t imm13) {
    // imm is 13-bit signed, bit0 must be 0. Encoding:
    // [31]=imm[12], [7]=imm[11], [30:25]=imm[10:5], [11:8]=imm[4:1], [0] implied 0
    uint32_t u = (uint32_t)(imm13 & 0x1FFF);
    return ((u >> 12) << 31)
         | (((u >> 11) & 1) << 7)
         | (((u >> 5) & 0x3F) << 25)
         | (((u >> 1) & 0xF) << 8);
}

static uint32_t pack_u(uint32_t imm20) {
    // upper 20 bits in [31:12]
    return (imm20 & 0xFFFFFu) << 12;
}

static uint32_t pack_j(int32_t imm21) {
    // imm is 21-bit signed, bit0 must be 0. Encoding:
    // [31]=imm[20], [19:12]=imm[19:12], [20]=imm[11], [30:21]=imm[10:1]
    uint32_t u = (uint32_t)(imm21 & 0x1FFFFF);
    return ((u >> 20) << 31)
         | (((u >> 12) & 0xFF) << 12)
         | (((u >> 11) & 1) << 20)
         | (((u >> 1) & 0x3FF) << 21);
}

struct TestCase {
    const char* name;
    uint32_t instr;
    uint8_t  imm_src;
    uint32_t expected;
};

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vimm_gen* dut = new Vimm_gen;
    Verilated::traceEverOn(true);
    VerilatedVcdC* trace = new VerilatedVcdC;
    dut->trace(trace, 5);
    trace->open("waves/imm_gen.vcd");

    const TestCase tests[] = {
        // I-type
        {"I +1",        pack_i(1),           IMM_I, 1},
        {"I +2047",     pack_i(2047),        IMM_I, 2047},
        {"I -1",        pack_i(-1),          IMM_I, 0xFFFFFFFFu},
        {"I -2048",     pack_i(-2048),       IMM_I, 0xFFFFF800u},
        {"I 0",         pack_i(0),           IMM_I, 0},

        // S-type
        {"S +8",        pack_s(8),           IMM_S, 8},
        {"S +2047",     pack_s(2047),        IMM_S, 2047},
        {"S -4",        pack_s(-4),          IMM_S, 0xFFFFFFFCu},
        {"S -2048",     pack_s(-2048),       IMM_S, 0xFFFFF800u},

        // B-type (offsets are multiples of 2)
        {"B +8",        pack_b(8),           IMM_B, 8},
        {"B +4094",     pack_b(4094),        IMM_B, 4094},
        {"B -2",        pack_b(-2),          IMM_B, 0xFFFFFFFEu},
        {"B -4096",     pack_b(-4096),       IMM_B, 0xFFFFF000u},

        // U-type
        {"U 0x12345",   pack_u(0x12345),     IMM_U, 0x12345000u},
        {"U 0xABCDE",   pack_u(0xABCDE),     IMM_U, 0xABCDE000u},
        {"U 0",         pack_u(0),           IMM_U, 0},

        // J-type (offsets are multiples of 2)
        {"J +16",       pack_j(16),          IMM_J, 16},
        {"J +1048574",  pack_j(1048574),     IMM_J, 1048574},
        {"J -2",        pack_j(-2),          IMM_J, 0xFFFFFFFEu},
        {"J -1048576",  pack_j(-1048576),    IMM_J, 0xFFF00000u},
    };

    int fails = 0;
    vluint64_t t = 0;

    for (const auto& tc : tests) {
        dut->instr   = tc.instr;
        dut->imm_src = tc.imm_src;
        dut->eval();
        trace->dump(t++);

        uint32_t got = dut->imm;
        if (got != tc.expected) {
            printf("FAIL: %-14s instr=0x%08X src=%u got=0x%08X exp=0x%08X\n",
                   tc.name, tc.instr, tc.imm_src, got, tc.expected);
            fails++;
        } else {
            printf("PASS: %-14s -> 0x%08X\n", tc.name, got);
        }
    }

    trace->close();
    delete trace;
    delete dut;

    if (fails == 0) {
        printf("PASS: imm_gen all tests passed\n");
        return 0;
    }
    printf("FAIL: %d test(s) failed\n", fails);
    return 1;
}
