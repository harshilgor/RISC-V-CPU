// Pipelined CPU wrapper: cpu_core_pipe + local IMEM/DMEM (Phase 1+)
module cpu_pipe (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        imem_we,
    input  logic [31:0] imem_waddr,
    input  logic [31:0] imem_wdata,

    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_mepc,
    output logic [31:0] dbg_mcause,
    output logic [31:0] dbg_mtvec,
    output logic [31:0] dbg_mstatus,

    output logic [31:0] dbg_pc_id,
    output logic [31:0] dbg_pc_ex,
    output logic [31:0] dbg_pc_mem,
    output logic [31:0] dbg_pc_wb,
    output logic        dbg_stall,
    output logic        dbg_valid_wb
);

    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we, dmem_re;
    logic [2:0]  dmem_funct3;

    cpu_core_pipe u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .timer_irq(1'b0),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_mepc(dbg_mepc), .dbg_mcause(dbg_mcause),
        .dbg_mtvec(dbg_mtvec), .dbg_mstatus(dbg_mstatus),
        .dbg_pc_id(dbg_pc_id), .dbg_pc_ex(dbg_pc_ex),
        .dbg_pc_mem(dbg_pc_mem), .dbg_pc_wb(dbg_pc_wb),
        .dbg_stall(dbg_stall), .dbg_valid_wb(dbg_valid_wb)
    );

    imem u_imem (
        .clk(clk),
        .addr(imem_addr),
        .instr(imem_rdata),
        .we(imem_we),
        .waddr(imem_waddr),
        .wdata(imem_wdata)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_re;
    assign unused_re = dmem_re;
    /* verilator lint_on UNUSEDSIGNAL */

    dmem u_dmem (
        .clk(clk),
        .addr(dmem_addr),
        .wdata(dmem_wdata),
        .we(dmem_we),
        .funct3(dmem_funct3),
        .rdata(dmem_rdata)
    );

endmodule
