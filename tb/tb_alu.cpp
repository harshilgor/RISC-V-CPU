// Verilator testbench for the RV32I ALU
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Valu.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

enum AluOp : uint8_t {
    ALU_ADD  = 0b0000,
    ALU_SUB  = 0b0001,
    ALU_AND  = 0b0010,
    ALU_OR   = 0b0011,
    ALU_XOR  = 0b0100,
    ALU_SLL  = 0b0101,
    ALU_SRL  = 0b0110,
    ALU_SRA  = 0b0111,
    ALU_SLT  = 0b1000,
    ALU_SLTU = 0b1001,
};

struct TestCase {
    const char* name;
    uint32_t a;
    uint32_t b;
    uint8_t  op;
    uint32_t expected;
};

static uint32_t ref_alu(uint32_t a, uint32_t b, uint8_t op) {
    switch (op) {
        case ALU_ADD:  return a + b;
        case ALU_SUB:  return a - b;
        case ALU_AND:  return a & b;
        case ALU_OR:   return a | b;
        case ALU_XOR:  return a ^ b;
        case ALU_SLL:  return a << (b & 0x1F);
        case ALU_SRL:  return a >> (b & 0x1F);
        case ALU_SRA:  return (uint32_t)((int32_t)a >> (b & 0x1F));
        case ALU_SLT:  return ((int32_t)a < (int32_t)b) ? 1u : 0u;
        case ALU_SLTU: return (a < b) ? 1u : 0u;
        default:       return 0;
    }
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Valu* dut = new Valu;

    Verilated::traceEverOn(true);
    VerilatedVcdC* trace = new VerilatedVcdC;
    dut->trace(trace, 5);
    trace->open("waves/alu.vcd");

    const TestCase tests[] = {
        {"ADD basic",     10,          20,         ALU_ADD,  30},
        {"ADD overflow",  0xFFFFFFFFu, 1,          ALU_ADD,  0},
        {"SUB basic",     20,          7,          ALU_SUB,  13},
        {"SUB neg",       5,           8,          ALU_SUB,  0xFFFFFFFDu},
        {"AND",           0xF0F0F0F0u, 0xFF00FF00u,ALU_AND,  0xF000F000u},
        {"OR",            0xF0F0F0F0u, 0x0F0F0F0Fu,ALU_OR,   0xFFFFFFFFu},
        {"XOR",           0xAAAAu,     0xFFFFu,    ALU_XOR,  0x5555u},
        {"SLL",           1,           4,          ALU_SLL,  16},
        {"SRL",           0x80000000u, 4,          ALU_SRL,  0x08000000u},
        {"SRA neg",       0xF0000000u, 4,          ALU_SRA,  0xFF000000u},
        {"SRA pos",       0x70000000u, 4,          ALU_SRA,  0x07000000u},
        {"SLT true",      0xFFFFFFFFu, 1,          ALU_SLT,  1},   // -1 < 1
        {"SLT false",     5,           3,          ALU_SLT,  0},
        {"SLTU true",     1,           0xFFFFFFFFu,ALU_SLTU, 1},   // 1 < big unsigned
        {"SLTU false",    0xFFFFFFFFu, 1,          ALU_SLTU, 0},
        {"zero flag",     7,           7,          ALU_SUB,  0},
    };

    int fails = 0;
    vluint64_t t = 0;

    for (const auto& tc : tests) {
        dut->a  = tc.a;
        dut->b  = tc.b;
        dut->op = tc.op;
        dut->eval();
        trace->dump(t++);

        uint32_t got = dut->result;
        uint32_t exp = tc.expected;
        int zero_ok = (dut->zero == (got == 0));

        if (got != exp || !zero_ok) {
            printf("FAIL: %-12s a=0x%08X b=0x%08X op=%u  got=0x%08X exp=0x%08X zero=%d\n",
                   tc.name, tc.a, tc.b, tc.op, got, exp, (int)dut->zero);
            fails++;
        } else {
            printf("PASS: %-12s -> 0x%08X\n", tc.name, got);
        }

        // Also cross-check against the C++ reference model
        uint32_t ref = ref_alu(tc.a, tc.b, tc.op);
        if (got != ref) {
            printf("  REF mismatch: hardware=0x%08X  ref=0x%08X\n", got, ref);
            fails++;
        }
    }

    // A few random directed checks against the reference model
    for (int i = 0; i < 200; i++) {
        uint32_t a  = (uint32_t)rand() ^ ((uint32_t)rand() << 16);
        uint32_t b  = (uint32_t)rand() ^ ((uint32_t)rand() << 16);
        uint8_t  op = (uint8_t)(rand() % 10);

        dut->a  = a;
        dut->b  = b;
        dut->op = op;
        dut->eval();
        trace->dump(t++);

        uint32_t got = dut->result;
        uint32_t ref = ref_alu(a, b, op);
        if (got != ref || dut->zero != (got == 0)) {
            printf("FAIL random: a=0x%08X b=0x%08X op=%u got=0x%08X ref=0x%08X\n",
                   a, b, op, got, ref);
            fails++;
            break;
        }
    }

    trace->close();
    delete trace;
    delete dut;

    if (fails == 0) {
        printf("PASS: ALU all tests passed\n");
        return 0;
    }
    printf("FAIL: %d test(s) failed\n", fails);
    return 1;
}
