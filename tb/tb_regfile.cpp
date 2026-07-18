// Verilator testbench for the RV32I register file
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include "Vregfile.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

static void tick(Vregfile* dut, VerilatedVcdC* trace, vluint64_t& t) {
    dut->clk = 0;
    dut->eval();
    trace->dump(t++);
    dut->clk = 1;
    dut->eval();
    trace->dump(t++);
}

static void write_reg(Vregfile* dut, VerilatedVcdC* trace, vluint64_t& t,
                      uint8_t rd, uint32_t data) {
    dut->we      = 1;
    dut->rd_addr = rd;
    dut->rd_data = data;
    tick(dut, trace, t);
    dut->we = 0;
}

static uint32_t read_rs1(Vregfile* dut, uint8_t rs1) {
    dut->rs1_addr = rs1;
    dut->eval();
    return dut->rs1_data;
}

static uint32_t read_rs2(Vregfile* dut, uint8_t rs2) {
    dut->rs2_addr = rs2;
    dut->eval();
    return dut->rs2_data;
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    Vregfile* dut = new Vregfile;
    Verilated::traceEverOn(true);
    VerilatedVcdC* trace = new VerilatedVcdC;
    dut->trace(trace, 5);
    trace->open("waves/regfile.vcd");

    vluint64_t t = 0;
    int fails = 0;

    // Reset
    dut->rst_n    = 0;
    dut->we       = 0;
    dut->rs1_addr = 0;
    dut->rs2_addr = 0;
    dut->rd_addr  = 0;
    dut->rd_data  = 0;
    dut->dbg_addr = 0;
    tick(dut, trace, t);
    tick(dut, trace, t);
    dut->rst_n = 1;
    tick(dut, trace, t);

    auto expect = [&](const char* name, uint32_t got, uint32_t exp) {
        if (got != exp) {
            printf("FAIL: %-28s got=0x%08X exp=0x%08X\n", name, got, exp);
            fails++;
        } else {
            printf("PASS: %-28s -> 0x%08X\n", name, got);
        }
    };

    // After reset, all regs (including via both ports) should be 0
    expect("reset x0",  read_rs1(dut, 0),  0);
    expect("reset x1",  read_rs1(dut, 1),  0);
    expect("reset x31", read_rs2(dut, 31), 0);

    // Write x1..x31 with distinct values and read back
    for (int i = 1; i < 32; i++) {
        write_reg(dut, trace, t, (uint8_t)i, 0x1000u + (uint32_t)i);
    }
    for (int i = 1; i < 32; i++) {
        char name[64];
        snprintf(name, sizeof(name), "write/read x%d", i);
        expect(name, read_rs1(dut, (uint8_t)i), 0x1000u + (uint32_t)i);
    }

    // x0 stays 0 even if we try to write it
    write_reg(dut, trace, t, 0, 0xDEADBEEFu);
    expect("x0 ignore write", read_rs1(dut, 0), 0);

    // Dual-port read of two different registers at once
    dut->rs1_addr = 1;
    dut->rs2_addr = 2;
    dut->eval();
    expect("dual rs1=x1", dut->rs1_data, 0x1001u);
    expect("dual rs2=x2", dut->rs2_data, 0x1002u);

    // Same register on both read ports
    dut->rs1_addr = 5;
    dut->rs2_addr = 5;
    dut->eval();
    expect("same reg both ports", dut->rs1_data, dut->rs2_data);
    expect("same reg value",      dut->rs1_data, 0x1005u);

    // we=0 must not write
    dut->we      = 0;
    dut->rd_addr = 3;
    dut->rd_data = 0x12345678u;
    tick(dut, trace, t);
    expect("we=0 no write", read_rs1(dut, 3), 0x1003u);

    // Overwrite an existing register
    write_reg(dut, trace, t, 7, 0xCAFEBABEu);
    expect("overwrite x7", read_rs2(dut, 7), 0xCAFEBABEu);

    trace->close();
    delete trace;
    delete dut;

    if (fails == 0) {
        printf("PASS: regfile all tests passed\n");
        return 0;
    }
    printf("FAIL: %d test(s) failed\n", fails);
    return 1;
}
