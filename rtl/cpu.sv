// Backward-compatible CPU wrapper: core + local IMEM/DMEM (unit / legacy tests)
module cpu (
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
    output logic [31:0] dbg_mstatus
);

    logic [31:0] imem_addr, imem_rdata;
    logic [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    logic        dmem_we, dmem_re;
    logic [2:0]  dmem_funct3;

    cpu_core u_core (
        .clk(clk), .rst_n(rst_n),
        .imem_addr(imem_addr), .imem_rdata(imem_rdata),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata),
        .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_funct3(dmem_funct3),
        .timer_irq(1'b0),
        .dbg_reg_addr(dbg_reg_addr), .dbg_reg_data(dbg_reg_data),
        .dbg_pc(dbg_pc), .dbg_instr(dbg_instr),
        .dbg_mepc(dbg_mepc), .dbg_mcause(dbg_mcause),
        .dbg_mtvec(dbg_mtvec), .dbg_mstatus(dbg_mstatus)
    );

    imem u_imem (
        .clk(clk),
        .addr(imem_addr),
        .instr(imem_rdata),
        .we(imem_we),
        .waddr(imem_waddr),
        .wdata(imem_wdata)
    );

    // dmem_re unused here (combinational read always available)
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
