// Simple RISC-V SoC: pipelined CPU + ROM + RAM + UART + timer
//
// Memory map (data bus):
//   0x0000_0000  ROM    (readable; code + rodata)
//   0x1000_0000  RAM    (4 KiB)
//   0x1001_0000  UART   TXDATA@+0, TXSTATUS@+4
//   0x1002_0000  TIMER  mtime@+0, mtimecmp@+4
// Instruction fetch always comes from ROM.
module soc (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        rom_we,
    input  logic [31:0] rom_waddr,
    input  logic [31:0] rom_wdata,

    output logic [7:0]  uart_tx_byte,
    output logic        uart_tx_valid,

    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_mepc,
    output logic [31:0] dbg_mcause
);

    localparam logic [31:0]
        RAM_BASE   = 32'h1000_0000,
        UART_BASE  = 32'h1001_0000,
        TIMER_BASE = 32'h1002_0000;

    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we, dmem_re;
    logic [2:0]  dmem_funct3;
    logic        timer_irq;

    /* verilator lint_off UNUSEDSIGNAL */
    logic [31:0] dbg_mtvec, dbg_mstatus;
    logic [31:0] dbg_pc_id, dbg_pc_ex, dbg_pc_mem, dbg_pc_wb;
    logic        dbg_stall, dbg_valid_wb;
    /* verilator lint_on UNUSEDSIGNAL */

    cpu_core_pipe u_cpu (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .timer_irq(timer_irq),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_mepc(dbg_mepc), .dbg_mcause(dbg_mcause),
        .dbg_mtvec(dbg_mtvec), .dbg_mstatus(dbg_mstatus),
        .dbg_pc_id(dbg_pc_id), .dbg_pc_ex(dbg_pc_ex),
        .dbg_pc_mem(dbg_pc_mem), .dbg_pc_wb(dbg_pc_wb),
        .dbg_stall(dbg_stall), .dbg_valid_wb(dbg_valid_wb)
    );

    logic [31:0] rom_dword;

    rom #(
        .DEPTH(1024)
    ) u_rom (
        .clk(clk),
        .i_addr(imem_addr),
        .i_rdata(imem_rdata),
        .d_addr(dmem_addr),
        .d_rdata(rom_dword),
        .we(rom_we),
        .waddr(rom_waddr),
        .wdata(rom_wdata)
    );

    logic [7:0]  rom_byte;
    logic [15:0] rom_half;
    logic [31:0] rom_rdata;

    always_comb begin
        unique case (dmem_addr[1:0])
            2'b00: rom_byte = rom_dword[7:0];
            2'b01: rom_byte = rom_dword[15:8];
            2'b10: rom_byte = rom_dword[23:16];
            2'b11: rom_byte = rom_dword[31:24];
        endcase
        rom_half = dmem_addr[1] ? rom_dword[31:16] : rom_dword[15:0];
    end

    always_comb begin
        unique case (dmem_funct3)
            3'b000:  rom_rdata = {{24{rom_byte[7]}}, rom_byte};
            3'b001:  rom_rdata = {{16{rom_half[15]}}, rom_half};
            3'b010:  rom_rdata = rom_dword;
            3'b100:  rom_rdata = {24'b0, rom_byte};
            3'b101:  rom_rdata = {16'b0, rom_half};
            default: rom_rdata = rom_dword;
        endcase
    end

    logic sel_rom, sel_ram, sel_uart, sel_timer;
    assign sel_rom   = (dmem_addr[31:28] == 4'h0);
    assign sel_ram   = (dmem_addr[31:16] == RAM_BASE[31:16]);
    assign sel_uart  = (dmem_addr[31:16] == UART_BASE[31:16]);
    assign sel_timer = (dmem_addr[31:16] == TIMER_BASE[31:16]);

    logic [31:0] ram_rdata, uart_rdata, timer_rdata;
    logic        ram_we, uart_we, uart_re, timer_we, timer_re;

    assign ram_we    = dmem_we & sel_ram;
    assign uart_we   = dmem_we & sel_uart;
    assign uart_re   = dmem_re & sel_uart;
    assign timer_we  = dmem_we & sel_timer;
    assign timer_re  = dmem_re & sel_timer;

    ram #(
        .DEPTH(1024)
    ) u_ram (
        .clk(clk),
        .addr({16'h0, dmem_addr[15:0]}),
        .wdata(dmem_wdata),
        .we(ram_we),
        .funct3(dmem_funct3),
        .rdata(ram_rdata)
    );

    uart u_uart (
        .clk(clk),
        .rst_n(rst_n),
        .addr({28'h0, dmem_addr[3:0]}),
        .wdata(dmem_wdata),
        .we(uart_we),
        .re(uart_re),
        .rdata(uart_rdata),
        .tx_byte(uart_tx_byte),
        .tx_valid(uart_tx_valid)
    );

    timer u_timer (
        .clk(clk),
        .rst_n(rst_n),
        .addr({28'h0, dmem_addr[3:0]}),
        .wdata(dmem_wdata),
        .we(timer_we),
        .re(timer_re),
        .rdata(timer_rdata),
        .irq(timer_irq)
    );

    always_comb begin
        unique case (1'b1)
            sel_ram:   dmem_rdata = ram_rdata;
            sel_uart:  dmem_rdata = uart_rdata;
            sel_timer: dmem_rdata = timer_rdata;
            sel_rom:   dmem_rdata = rom_rdata;
            default:   dmem_rdata = 32'h0;
        endcase
    end

endmodule
