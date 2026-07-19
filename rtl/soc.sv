// Simple RISC-V SoC: pipelined CPU + ROM + RAM + UART
//
// Memory map (data bus):
//   0x1000_0000  RAM   (4 KiB)
//   0x1001_0000  UART  TXDATA@+0, TXSTATUS@+4
// Instruction fetch always comes from ROM at 0x0000_0000.
// Phase 6: cpu_core_pipe (5-stage RV32IM_Zicsr).
module soc (
    input  logic        clk,
    input  logic        rst_n,

    // ROM preload (testbench)
    input  logic        rom_we,
    input  logic [31:0] rom_waddr,
    input  logic [31:0] rom_wdata,

    // UART sideband
    output logic [7:0]  uart_tx_byte,
    output logic        uart_tx_valid,

    // Debug
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_mepc,
    output logic [31:0] dbg_mcause
);

    localparam logic [31:0]
        RAM_BASE  = 32'h1000_0000,
        UART_BASE = 32'h1001_0000;

    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we, dmem_re;
    logic [2:0]  dmem_funct3;

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
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_mepc(dbg_mepc), .dbg_mcause(dbg_mcause),
        .dbg_mtvec(dbg_mtvec), .dbg_mstatus(dbg_mstatus),
        .dbg_pc_id(dbg_pc_id), .dbg_pc_ex(dbg_pc_ex),
        .dbg_pc_mem(dbg_pc_mem), .dbg_pc_wb(dbg_pc_wb),
        .dbg_stall(dbg_stall), .dbg_valid_wb(dbg_valid_wb)
    );

    // ---- Instruction ROM ----------------------------------------------------
    rom #(
        .DEPTH(1024)
    ) u_rom (
        .clk(clk),
        .addr(imem_addr),
        .rdata(imem_rdata),
        .we(rom_we),
        .waddr(rom_waddr),
        .wdata(rom_wdata)
    );

    // ---- Address decode -----------------------------------------------------
    logic sel_ram, sel_uart;
    assign sel_ram  = (dmem_addr[31:16] == RAM_BASE[31:16]);
    assign sel_uart = (dmem_addr[31:16] == UART_BASE[31:16]);

    logic [31:0] ram_rdata, uart_rdata;
    logic        ram_we, uart_we, uart_re;

    assign ram_we  = dmem_we & sel_ram;
    assign uart_we = dmem_we & sel_uart;
    assign uart_re = dmem_re & sel_uart;

    ram #(
        .DEPTH(1024)
    ) u_ram (
        .clk(clk),
        .addr({16'h0, dmem_addr[15:0]}),  // local offset
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

    always_comb begin
        unique case (1'b1)
            sel_ram:  dmem_rdata = ram_rdata;
            sel_uart: dmem_rdata = uart_rdata;
            default:  dmem_rdata = 32'h0;
        endcase
    end

endmodule
