// CPU core with external instruction + data buses (no on-core memories)
module cpu_core (
    input  logic        clk,
    input  logic        rst_n,

    // Instruction bus (combinational read)
    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    // Data bus
    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    output logic        dmem_we,
    output logic        dmem_re,
    output logic [2:0]  dmem_funct3,

    // Debug
    input  logic [4:0]  dbg_reg_addr,
    output logic [31:0] dbg_reg_data,
    output logic [31:0] dbg_pc,
    output logic [31:0] dbg_instr,
    output logic [31:0] dbg_mepc,
    output logic [31:0] dbg_mcause,
    output logic [31:0] dbg_mtvec,
    output logic [31:0] dbg_mstatus
);

    logic [31:0] pc, pc_next, pc_plus4;
    logic [31:0] instr;

    pc u_pc (
        .clk    (clk),
        .rst_n  (rst_n),
        .pc_next(pc_next),
        .pc     (pc)
    );

    assign imem_addr = pc;
    assign instr     = imem_rdata;
    assign pc_plus4  = pc + 32'd4;
    assign dbg_pc    = pc;
    assign dbg_instr = instr;

    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [11:0] funct12;
    logic [11:0] csr_addr;
    logic [4:0]  csr_uimm;

    assign opcode   = instr[6:0];
    assign rd       = instr[11:7];
    assign funct3   = instr[14:12];
    assign rs1      = instr[19:15];
    assign rs2      = instr[24:20];
    assign funct7   = instr[31:25];
    assign funct12  = instr[31:20];
    assign csr_addr = instr[31:20];
    assign csr_uimm = instr[19:15];

    logic       reg_write;
    logic [2:0] imm_src;
    logic [1:0] alu_src_a;
    logic       alu_src_b;
    logic [3:0] alu_op;
    logic       use_mdu;
    logic       mem_read;
    logic       mem_write;
    logic [1:0] result_src;
    logic       branch, jump, jalr;
    logic       trap_ecall, trap_ebreak, mret;
    logic       csr_op, csr_use_imm;

    control u_control (
        .opcode      (opcode),
        .funct3      (funct3),
        .funct7      (funct7),
        .funct12     (funct12),
        .reg_write   (reg_write),
        .imm_src     (imm_src),
        .alu_src_a   (alu_src_a),
        .alu_src_b   (alu_src_b),
        .alu_op      (alu_op),
        .use_mdu     (use_mdu),
        .mem_read    (mem_read),
        .mem_write   (mem_write),
        .result_src  (result_src),
        .branch      (branch),
        .jump        (jump),
        .jalr        (jalr),
        .trap_ecall  (trap_ecall),
        .trap_ebreak (trap_ebreak),
        .mret        (mret),
        .csr_op      (csr_op),
        .csr_use_imm (csr_use_imm)
    );

    logic trap;
    assign trap = trap_ecall | trap_ebreak;

    logic [31:0] imm, rs1_data, rs2_data, rd_data;

    imm_gen u_imm_gen (
        .instr  (instr),
        .imm_src(imm_src),
        .imm    (imm)
    );

    regfile u_regfile (
        .clk      (clk),
        .rst_n    (rst_n),
        .we       (reg_write & ~trap),
        .rs1_addr (rs1),
        .rs2_addr (rs2),
        .rd_addr  (rd),
        .rd_data  (rd_data),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .dbg_addr (dbg_reg_addr),
        .dbg_data (dbg_reg_data)
    );

    logic [31:0] alu_a, alu_b, alu_result, mdu_result, exec_result;
    logic        alu_zero;

    always_comb begin
        unique case (alu_src_a)
            2'b00:   alu_a = rs1_data;
            2'b01:   alu_a = pc;
            2'b10:   alu_a = 32'h0;
            default: alu_a = rs1_data;
        endcase
    end

    assign alu_b = alu_src_b ? imm : rs2_data;

    alu u_alu (
        .a(alu_a), .b(alu_b), .op(alu_op),
        .result(alu_result), .zero(alu_zero)
    );

    mdu u_mdu (
        .a(rs1_data), .b(rs2_data), .funct3(funct3), .result(mdu_result)
    );

    assign exec_result = use_mdu ? mdu_result : alu_result;

    // External data bus
    assign dmem_addr   = alu_result;
    assign dmem_wdata  = rs2_data;
    assign dmem_we     = mem_write & ~trap;
    assign dmem_re     = mem_read & ~trap;
    assign dmem_funct3 = funct3;

    logic [31:0] csr_rdata, csr_wdata, csr_src;
    logic        csr_we;
    logic [31:0] mtvec, mepc, mcause, mstatus;

    assign csr_src = csr_use_imm ? {27'b0, csr_uimm} : rs1_data;

    always_comb begin
        unique case (funct3[1:0])
            2'b01:   csr_wdata = csr_src;
            2'b10:   csr_wdata = csr_rdata | csr_src;
            2'b11:   csr_wdata = csr_rdata & ~csr_src;
            default: csr_wdata = csr_src;
        endcase
    end

    always_comb begin
        csr_we = 1'b0;
        if (csr_op && !trap) begin
            unique case (funct3[1:0])
                2'b01:   csr_we = 1'b1;
                2'b10,
                2'b11:   csr_we = (csr_src != 32'h0);
                default: csr_we = 1'b0;
            endcase
        end
    end

    csr_file u_csr (
        .clk(clk), .rst_n(rst_n),
        .addr(csr_addr), .wdata(csr_wdata), .we(csr_we), .rdata(csr_rdata),
        .trap(trap), .trap_ebreak(trap_ebreak), .trap_pc(pc),
        .mtvec(mtvec), .mepc(mepc), .mcause(mcause), .mstatus(mstatus)
    );

    assign dbg_mepc    = mepc;
    assign dbg_mcause  = mcause;
    assign dbg_mtvec   = mtvec;
    assign dbg_mstatus = mstatus;

    always_comb begin
        unique case (result_src)
            2'b00:   rd_data = exec_result;
            2'b01:   rd_data = mem_read ? dmem_rdata : 32'h0;
            2'b10:   rd_data = pc_plus4;
            2'b11:   rd_data = csr_rdata;
            default: rd_data = exec_result;
        endcase
    end

    logic take_branch;
    logic [31:0] pc_target, pc_jalr;

    always_comb begin
        take_branch = 1'b0;
        if (branch) begin
            unique case (funct3)
                3'b000: take_branch =  alu_zero;
                3'b001: take_branch = !alu_zero;
                3'b100: take_branch = !alu_zero;
                3'b101: take_branch =  alu_zero;
                3'b110: take_branch = !alu_zero;
                3'b111: take_branch =  alu_zero;
                default: take_branch = 1'b0;
            endcase
        end
    end

    assign pc_target = pc + imm;
    assign pc_jalr   = {alu_result[31:1], 1'b0};

    always_comb begin
        if (trap)                         pc_next = mtvec;
        else if (mret)                    pc_next = mepc;
        else if (jalr)                    pc_next = pc_jalr;
        else if (jump || take_branch)     pc_next = pc_target;
        else                              pc_next = pc_plus4;
    end

endmodule
