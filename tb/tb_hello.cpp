// Load sw/hello/hello.hex into SoC ROM and capture UART output
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include "Vsoc.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

double sc_time_stamp() { return 0; }

static uint32_t halt_enc() {
    // jal x0, 0
    return 0x0000006Fu;
}

struct Sim {
    Vsoc* top;
    VerilatedVcdC* tfp;
    vluint64_t time_ps;
    std::string uart_out;

    Sim() : top(new Vsoc), tfp(nullptr), time_ps(0) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedVcdC;
        top->trace(tfp, 99);
        tfp->open("waves/hello.vcd");
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

    void reset(int n = 4) {
        top->rst_n = 0;
        for (int i = 0; i < n; ++i) tick();
        top->rst_n = 1;
        tick();
    }

    bool load_hex(const char* path) {
        std::ifstream in(path);
        if (!in) {
            std::fprintf(stderr, "Cannot open hex file: %s\n", path);
            return false;
        }
        top->rst_n = 0;
        top->rom_we = 1;
        uint32_t addr = 0;
        std::string line;
        while (std::getline(in, line)) {
            // trim
            while (!line.empty() && (line.back() == '\r' || line.back() == ' '))
                line.pop_back();
            if (line.empty() || line[0] == '/' || line[0] == '#')
                continue;
            if (line[0] == '@') {
                addr = static_cast<uint32_t>(std::stoul(line.substr(1), nullptr, 16));
                continue;
            }
            uint32_t word = static_cast<uint32_t>(std::stoul(line, nullptr, 16));
            top->rom_waddr = addr;
            top->rom_wdata = word;
            tick();
            addr += 4;
        }
        top->rom_we = 0;
        return true;
    }

    void run_until_idle(int max_cycles = 100000) {
        // Run until the program hits its halt spin (`j .` / jal x0,0), not on
        // the first newline — C demos may print multiple lines.
        int halt_pc_seen = 0;
        int idle = 0;
        size_t last_len = 0;
        for (int i = 0; i < max_cycles; ++i) {
            tick();
            if (top->dbg_instr == halt_enc()) {
                if (++halt_pc_seen > 64) {
                    for (int k = 0; k < 16; ++k) tick();
                    return;
                }
            } else {
                halt_pc_seen = 0;
            }
            if (uart_out.size() != last_len) {
                last_len = uart_out.size();
                idle = 0;
            } else if (!uart_out.empty() && ++idle > 2000) {
                return;
            }
        }
    }
};

static std::string find_hex() {
    const char* candidates[] = {
        "sw/hello_c/hello_c.hex",
        "sw/hello/hello.hex",
        "../sw/hello_c/hello_c.hex",
        "../sw/hello/hello.hex",
        "hello.hex",
    };
    for (const char* c : candidates) {
        std::ifstream in(c);
        if (in.good())
            return c;
    }
    return {};
}

int main(int argc, char** argv) {
    Verilated::commandArgs(argc, argv);

    std::string hex = (argc > 1) ? argv[1] : find_hex();
    if (hex.empty()) {
        std::fprintf(stderr,
            "Usage: Vsoc <image.hex> [expected_uart_text]\n"
            "Build first:  make -C sw/hello   or   make -C sw/hello_c\n");
        return 2;
    }

    // Optional expected string (argv[2]). Default matches asm hello.
    std::string expect = (argc > 2) ? argv[2] : "Hello from RISC-V!\n";
    // Allow "\\n" in shell-passed expectations
    for (size_t pos = 0; (pos = expect.find("\\n", pos)) != std::string::npos;)
        expect.replace(pos, 2, "\n");

    Sim s;
    std::printf("Loading %s\n", hex.c_str());
    if (!s.load_hex(hex.c_str()))
        return 1;

    s.reset();
    s.run_until_idle(100000);

    std::printf("UART output (%zu bytes):\n", s.uart_out.size());
    std::fwrite(s.uart_out.data(), 1, s.uart_out.size(), stdout);
    if (s.uart_out.empty() || s.uart_out.back() != '\n')
        std::printf("\n");

    if (s.uart_out == expect) {
        std::printf("PASS: hello program printed expected string\n");
        return 0;
    }
    std::printf("FAIL: expected \"%s\"\n", expect.c_str());
    return 1;
}
