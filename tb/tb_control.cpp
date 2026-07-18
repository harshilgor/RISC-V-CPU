// Control-unit smoke tests (RV32IM + traps)
#include <cstdio>
#include <cstdint>
#include "Vcontrol.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);
    Vcontrol* dut = new Vcontrol;
    Verilated::traceEverOn(true);
    VerilatedVcdC* tr = new VerilatedVcdC;
    dut->trace(tr, 5);
    tr->open("waves/control.vcd");

    int fails = 0;
    vluint64_t t = 0;

    auto set = [&](uint8_t opc, uint8_t f3, uint8_t f7, uint16_t f12) {
        dut->opcode  = opc;
        dut->funct3  = f3;
        dut->funct7  = f7;
        dut->funct12 = f12;
        dut->eval();
        tr->dump(t++);
    };

    auto expect = [&](const char* name, bool cond) {
        if (!cond) {
            printf("FAIL: %s\n", name);
            fails++;
        } else {
            printf("PASS: %s\n", name);
        }
    };

    // ADD
    set(0b0110011, 0, 0, 0);
    expect("ADD reg_write", dut->reg_write && !dut->use_mdu && dut->alu_op == 0);

    // MUL
    set(0b0110011, 0, 0b0000001, 0);
    expect("MUL use_mdu", dut->reg_write && dut->use_mdu);

    // FENCE = NOP
    set(0b0001111, 0, 0, 0);
    expect("FENCE nop", !dut->reg_write && !dut->mem_write && !dut->branch);

    // ECALL
    set(0b1110011, 0, 0, 0x000);
    expect("ECALL", dut->trap_ecall && !dut->reg_write);

    // EBREAK
    set(0b1110011, 0, 0, 0x001);
    expect("EBREAK", dut->trap_ebreak);

    // MRET
    set(0b1110011, 0, 0, 0x302);
    expect("MRET", dut->mret);

    // LW
    set(0b0000011, 0b010, 0, 0);
    expect("LW", dut->reg_write && dut->mem_read && dut->result_src == 1);

    tr->close();
    delete tr;
    delete dut;
    if (fails == 0) {
        printf("PASS: control smoke passed\n");
        return 0;
    }
    printf("FAIL: %d\n", fails);
    return 1;
}
