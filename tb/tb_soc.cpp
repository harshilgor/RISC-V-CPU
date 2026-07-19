// SoC integration: ROM boot + RAM + memory-mapped UART
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>
#include "Vsoc.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

static uint32_t enc_i(uint32_t opc, uint32_t f3, uint32_t rd, uint32_t rs1, int32_t imm) {
    return ((uint32_t)(imm & 0xFFF) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | opc;
}
static uint32_t enc_s(uint32_t f3, uint32_t rs2, uint32_t rs1, int32_t imm) {
    uint32_t u = (uint32_t)(imm & 0xFFF);
    return ((u >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((u & 0x1F) << 7) | 0x23;
}
static uint32_t enc_u(uint32_t opc, uint32_t rd, uint32_t imm20) {
    return ((imm20 & 0xFFFFF) << 12) | (rd << 7) | opc;
}
static uint32_t enc_j(uint32_t rd, int32_t off) {
    uint32_t u = (uint32_t)(off & 0x1FFFFF);
    return ((u >> 20) << 31) | (((u >> 1) & 0x3FF) << 21) | (((u >> 11) & 1) << 20)
         | (((u >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F;
}

static uint32_t addi(uint32_t rd, uint32_t rs1, int32_t i) { return enc_i(0x13, 0x0, rd, rs1, i); }
static uint32_t lw  (uint32_t rd, int32_t i, uint32_t rs1){ return enc_i(0x03, 0x2, rd, rs1, i); }
static uint32_t sb  (uint32_t rs2, int32_t i, uint32_t rs1){ return enc_s(0x0, rs2, rs1, i); }
static uint32_t sw  (uint32_t rs2, int32_t i, uint32_t rs1){ return enc_s(0x2, rs2, rs1, i); }
static uint32_t lui (uint32_t rd, uint32_t imm20){ return enc_u(0x37, rd, imm20); }
static uint32_t halt() { return enc_j(0, 0); }

struct Sim {
    Vsoc* top;
    VerilatedVcdC* tfp;
    vluint64_t time_ps;
    std::string uart_out;

    Sim() : top(new Vsoc), tfp(nullptr), time_ps(0) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("waves/soc.vcd");
        top->clk = 0;
        top->rst_n = 0;
        top->rom_we = 0;
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
        if (top->uart_tx_valid)
            uart_out.push_back(static_cast<char>(top->uart_tx_byte & 0xFF));
        if (tfp) tfp->dump(time_ps);
        time_ps += 5;
    }

    void reset(int cycles = 4) {
        top->rst_n = 0;
        for (int i = 0; i < cycles; ++i) tick();
        top->rst_n = 1;
        tick();
    }

    void load_rom(const std::vector<uint32_t>& words) {
        top->rst_n = 0;  // hold CPU while programming ROM
        top->rom_we = 1;
        for (size_t i = 0; i < words.size(); ++i) {
            top->rom_waddr = static_cast<uint32_t>(i * 4);
            top->rom_wdata = words[i];
            tick();
        }
        top->rom_we = 0;
        top->rom_waddr = 0;
        top->rom_wdata = 0;
    }

    uint32_t reg_x(uint32_t n) {
        top->dbg_reg_addr = n & 0x1F;
        top->eval();
        return top->dbg_reg_data;
    }

    void run_until_halt(int max_cycles = 400) {
        int seen = 0;
        for (int i = 0; i < max_cycles; ++i) {
            tick();
            // Halt appears in IF/ID early; wait a few cycles then drain WB/MEM
            if (top->dbg_instr == halt()) {
                if (++seen >= 3)
                    break;
            } else {
                seen = 0;
            }
        }
        for (int i = 0; i < 10; ++i)
            tick();
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

static void expect_str(const char* name, const std::string& got, const char* exp) {
    if (got != exp) {
        std::printf("FAIL %s: got \"%s\" expected \"%s\"\n", name, got.c_str(), exp);
        ++fails;
    } else {
        std::printf("PASS %s\n", name);
    }
}

// Memory map:
//   ROM  @ 0x0000_0000  (fetch)
//   RAM  @ 0x1000_0000
//   UART @ 0x1001_0000  TXDATA=+0, TXSTATUS=+4

static void test_ram_roundtrip(Sim& s) {
    // lui x1, 0x10000        ; RAM base
    // addi x2, x0, 0xABCD
    // sw   x2, 0(x1)
    // lw   x3, 0(x1)
    // halt
    std::vector<uint32_t> prog = {
        lui(1, 0x10000),
        addi(2, 0, 0x123),
        sw(2, 0, 1),
        lw(3, 0, 1),
        halt(),
    };
    s.uart_out.clear();
    s.load_rom(prog);
    s.reset();
    s.run_until_halt();
    expect_eq("ram store/load x3", s.reg_x(3), 0x123);
}

static void test_uart_hello(Sim& s) {
    // Print "Hi\\n" via UART TXDATA (sb)
    // lui  x10, 0x10010      ; UART = 0x10010000
    // addi x1, x0, 'H'
    // sb   x1, 0(x10)
    // addi x1, x0, 'i'
    // sb   x1, 0(x10)
    // addi x1, x0, '\\n'
    // sb   x1, 0(x10)
    // lw   x2, 4(x10)        ; TXSTATUS should be 1
    // halt
    std::vector<uint32_t> prog = {
        lui(10, 0x10010),
        addi(1, 0, 'H'),
        sb(1, 0, 10),
        addi(1, 0, 'i'),
        sb(1, 0, 10),
        addi(1, 0, '\n'),
        sb(1, 0, 10),
        lw(2, 4, 10),
        halt(),
    };
    s.uart_out.clear();
    s.load_rom(prog);
    s.reset();
    s.run_until_halt();
    expect_str("uart hello", s.uart_out, "Hi\n");
    expect_eq("uart txstatus", s.reg_x(2), 1);
}

static void test_boot_pc(Sim& s) {
    // addi x5, x0, 42; halt
    std::vector<uint32_t> prog = {
        addi(5, 0, 42),
        halt(),
    };
    s.uart_out.clear();
    s.load_rom(prog);
    s.reset();
    s.run_until_halt();
    expect_eq("boot addi x5", s.reg_x(5), 42);
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Sim s;

    std::printf("=== SoC tests (pipelined core + ROM + RAM + UART) ===\n");
    test_boot_pc(s);
    test_ram_roundtrip(s);
    test_uart_hello(s);

    if (fails == 0) {
        std::printf("PASS: SoC all tests passed\n");
        return 0;
    }
    std::printf("FAIL: %d SoC check(s) failed\n", fails);
    return 1;
}
