// 5-stage pipelined RV32IM_Zicsr core (Phase 4–5)
//
// Decisions (see PIPELINE.md):
//   - IF | ID | EX | MEM | WB
//   - Forwarding + load-use stall + EX control-flow flush
//   - MDU combinational in EX (results forward like ALU)
//   - CSR RMW in EX; traps/mret redirect in EX (precise vs younger instrs)
module cpu_core_pipe (
    input  logic        clk,
    input  logic        rst_n,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_rdata,

    output logic [31:0] dmem_addr,
    output logic [31:0] dmem_wdata,
    input  logic [31:0] dmem_rdata,
    output logic        dmem_we,
    output logic        dmem_re,
    output logic [2:0]  dmem_funct3,

    // External interrupt pendings (level)
    input  logic        timer_irq,

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

    // -------------------------------------------------------------------------
    // IF
    // -------------------------------------------------------------------------
    logic [31:0] pc, pc_next, pc_plus4;
    logic        stall, flush_if_id;
    logic        pc_redirect;
    logic [31:0] pc_redirect_target;

    pc u_pc (
        .clk(clk), .rst_n(rst_n),
        .pc_next(pc_next),
        .pc(pc)
    );

    assign pc_plus4  = pc + 32'd4;
    assign imem_addr = pc;
    assign dbg_pc    = pc;
    assign dbg_stall = stall;

    always_comb begin
        if (pc_redirect)
            pc_next = pc_redirect_target;
        else if (stall)
            pc_next = pc;
        else
            pc_next = pc_plus4;
    end

    logic        if_id_valid;
    logic [31:0] if_id_pc, if_id_pc4, if_id_instr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_valid <= 1'b0;
            if_id_pc    <= 32'h0;
            if_id_pc4   <= 32'h0;
            if_id_instr <= 32'h00000013;
        end else if (flush_if_id) begin
            if_id_valid <= 1'b0;
            if_id_instr <= 32'h00000013;
            if_id_pc    <= 32'h0;
            if_id_pc4   <= 32'h0;
        end else if (!stall) begin
            if_id_valid <= 1'b1;
            if_id_pc    <= pc;
            if_id_pc4   <= pc_plus4;
            if_id_instr <= imem_rdata;
        end
    end

    assign dbg_instr = if_id_instr;
    assign dbg_pc_id = if_id_pc;

    // -------------------------------------------------------------------------
    // ID
    // -------------------------------------------------------------------------
    logic [6:0]  opcode;
    logic [4:0]  rd, rs1, rs2;
    logic [2:0]  funct3;
    logic [6:0]  funct7;
    logic [11:0] funct12;

    assign opcode  = if_id_instr[6:0];
    assign rd      = if_id_instr[11:7];
    assign funct3  = if_id_instr[14:12];
    assign rs1     = if_id_instr[19:15];
    assign rs2     = if_id_instr[24:20];
    assign funct7  = if_id_instr[31:25];
    assign funct12 = if_id_instr[31:20];

    logic       reg_write;
    logic [2:0] imm_src;
    logic [1:0] alu_src_a;
    logic       alu_src_b;
    logic [3:0] alu_op;
    logic       use_mdu;
    logic       mem_read, mem_write;
    logic [1:0] result_src;
    logic       branch, jump, jalr;
    logic       trap_ecall, trap_ebreak, mret;
    logic       csr_op, csr_use_imm;

    control u_control (
        .opcode(opcode), .funct3(funct3), .funct7(funct7), .funct12(funct12),
        .reg_write(reg_write), .imm_src(imm_src),
        .alu_src_a(alu_src_a), .alu_src_b(alu_src_b), .alu_op(alu_op),
        .use_mdu(use_mdu), .mem_read(mem_read), .mem_write(mem_write),
        .result_src(result_src), .branch(branch), .jump(jump), .jalr(jalr),
        .trap_ecall(trap_ecall), .trap_ebreak(trap_ebreak), .mret(mret),
        .csr_op(csr_op), .csr_use_imm(csr_use_imm)
    );

    logic [31:0] imm, rs1_data, rs2_data, wb_rd_data;
    logic        wb_reg_write;
    logic [4:0]  wb_rd;

    imm_gen u_imm_gen (
        .instr(if_id_instr), .imm_src(imm_src), .imm(imm)
    );

    regfile u_regfile (
        .clk(clk), .rst_n(rst_n),
        .we(wb_reg_write),
        .rs1_addr(rs1), .rs2_addr(rs2),
        .rd_addr(wb_rd), .rd_data(wb_rd_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .dbg_addr(dbg_reg_addr), .dbg_data(dbg_reg_data)
    );

    logic [31:0] rs1_data_v, rs2_data_v;
    always_comb begin
        rs1_data_v = rs1_data;
        rs2_data_v = rs2_data;
        if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == rs1))
            rs1_data_v = wb_rd_data;
        if (wb_reg_write && (wb_rd != 5'd0) && (wb_rd == rs2))
            rs2_data_v = wb_rd_data;
    end

    logic if_id_use_rs1, if_id_use_rs2;
    always_comb begin
        unique case (opcode)
            7'b0110111, // LUI
            7'b0010111, // AUIPC
            7'b1101111: // JAL
                begin
                    if_id_use_rs1 = 1'b0;
                    if_id_use_rs2 = 1'b0;
                end
            7'b1100111, // JALR
            7'b0000011, // LOAD
            7'b0010011: // OP-IMM
                begin
                    if_id_use_rs1 = 1'b1;
                    if_id_use_rs2 = 1'b0;
                end
            7'b1100011, // BRANCH
            7'b0100011, // STORE
            7'b0110011: // OP (includes M)
                begin
                    if_id_use_rs1 = 1'b1;
                    if_id_use_rs2 = 1'b1;
                end
            7'b1110011: // SYSTEM — rs1 only for non-immediate CSR
                begin
                    if_id_use_rs1 = csr_op && !csr_use_imm;
                    if_id_use_rs2 = 1'b0;
                end
            default: begin
                if_id_use_rs1 = 1'b0;
                if_id_use_rs2 = 1'b0;
            end
        endcase
    end

    logic        id_ex_valid;
    logic [31:0] id_ex_pc, id_ex_pc4, id_ex_rs1_data, id_ex_rs2_data, id_ex_imm;
    logic [4:0]  id_ex_rs1, id_ex_rs2, id_ex_rd;
    logic [2:0]  id_ex_funct3;
    logic [11:0] id_ex_csr_addr;
    logic        id_ex_reg_write, id_ex_mem_read, id_ex_mem_write, id_ex_alu_src_b;
    logic        id_ex_use_mdu, id_ex_branch, id_ex_jump, id_ex_jalr;
    logic        id_ex_csr_op, id_ex_csr_use_imm;
    logic        id_ex_trap_ecall, id_ex_trap_ebreak, id_ex_mret;
    logic [1:0]  id_ex_alu_src_a, id_ex_result_src;
    logic [3:0]  id_ex_alu_op;

    hazard_unit u_hazard (
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd(id_ex_rd),
        .if_id_rs1(rs1),
        .if_id_rs2(rs2),
        .if_id_use_rs1(if_id_use_rs1),
        .if_id_use_rs2(if_id_use_rs2),
        .pc_redirect(pc_redirect),
        .stall(stall),
        .flush_if_id(flush_if_id)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_valid         <= 1'b0;
            id_ex_reg_write     <= 1'b0;
            id_ex_mem_read      <= 1'b0;
            id_ex_mem_write     <= 1'b0;
            id_ex_branch        <= 1'b0;
            id_ex_jump          <= 1'b0;
            id_ex_jalr          <= 1'b0;
            id_ex_csr_op        <= 1'b0;
            id_ex_csr_use_imm   <= 1'b0;
            id_ex_trap_ecall    <= 1'b0;
            id_ex_trap_ebreak   <= 1'b0;
            id_ex_mret          <= 1'b0;
            id_ex_use_mdu       <= 1'b0;
            id_ex_pc            <= 32'h0;
            id_ex_pc4           <= 32'h0;
            id_ex_rs1_data      <= 32'h0;
            id_ex_rs2_data      <= 32'h0;
            id_ex_imm           <= 32'h0;
            id_ex_rs1           <= 5'h0;
            id_ex_rs2           <= 5'h0;
            id_ex_rd            <= 5'h0;
            id_ex_funct3        <= 3'h0;
            id_ex_csr_addr      <= 12'h0;
            id_ex_alu_src_a     <= 2'h0;
            id_ex_alu_src_b     <= 1'b0;
            id_ex_alu_op        <= 4'h0;
            id_ex_result_src    <= 2'h0;
        end else if (stall || flush_if_id) begin
            // Stall: insert bubble while holding IF/ID.
            // Flush: also squash the IF/ID instruction so it cannot enter EX
            // (otherwise a taken jump's fall-through becomes a second redirect).
            id_ex_valid       <= 1'b0;
            id_ex_reg_write   <= 1'b0;
            id_ex_mem_read    <= 1'b0;
            id_ex_mem_write   <= 1'b0;
            id_ex_branch      <= 1'b0;
            id_ex_jump        <= 1'b0;
            id_ex_jalr        <= 1'b0;
            id_ex_csr_op      <= 1'b0;
            id_ex_trap_ecall  <= 1'b0;
            id_ex_trap_ebreak <= 1'b0;
            id_ex_mret        <= 1'b0;
            id_ex_use_mdu     <= 1'b0;
        end else begin
            id_ex_valid         <= if_id_valid;
            id_ex_pc            <= if_id_pc;
            id_ex_pc4           <= if_id_pc4;
            id_ex_rs1_data      <= rs1_data_v;
            id_ex_rs2_data      <= rs2_data_v;
            id_ex_imm           <= imm;
            id_ex_rs1           <= rs1;
            id_ex_rs2           <= rs2;
            id_ex_rd            <= rd;
            id_ex_funct3        <= funct3;
            id_ex_csr_addr      <= funct12;
            id_ex_alu_src_a     <= alu_src_a;
            id_ex_alu_src_b     <= alu_src_b;
            id_ex_alu_op        <= alu_op;
            id_ex_use_mdu       <= if_id_valid & use_mdu;
            id_ex_result_src    <= result_src;
            id_ex_reg_write     <= if_id_valid & reg_write;
            id_ex_mem_read      <= if_id_valid & mem_read;
            id_ex_mem_write     <= if_id_valid & mem_write;
            id_ex_branch        <= if_id_valid & branch;
            id_ex_jump          <= if_id_valid & jump;
            id_ex_jalr          <= if_id_valid & jalr;
            id_ex_csr_op        <= if_id_valid & csr_op;
            id_ex_csr_use_imm   <= csr_use_imm;
            id_ex_trap_ecall    <= if_id_valid & trap_ecall;
            id_ex_trap_ebreak   <= if_id_valid & trap_ebreak;
            id_ex_mret          <= if_id_valid & mret;
        end
    end

    assign dbg_pc_ex = id_ex_pc;

    // -------------------------------------------------------------------------
    // EX
    // -------------------------------------------------------------------------
    logic [1:0]  forward_a, forward_b;
    logic [31:0] ex_mem_alu_result;
    logic        ex_mem_reg_write;
    logic [4:0]  ex_mem_rd;
    logic [31:0] mem_wb_alu_result, mem_wb_mem_rdata, mem_wb_pc4;
    logic [1:0]  mem_wb_result_src;

    forward_unit u_forward (
        .ex_mem_reg_write(ex_mem_reg_write),
        .ex_mem_rd(ex_mem_rd),
        .mem_wb_reg_write(wb_reg_write),
        .mem_wb_rd(wb_rd),
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .forward_a(forward_a),
        .forward_b(forward_b)
    );

    logic [31:0] fwd_rs1, fwd_rs2;

    assign wb_rd_data = (mem_wb_result_src == 2'b01) ? mem_wb_mem_rdata :
                        (mem_wb_result_src == 2'b10) ? mem_wb_pc4 :
                                                       mem_wb_alu_result;

    always_comb begin
        unique case (forward_a)
            2'b10:   fwd_rs1 = ex_mem_alu_result;
            2'b01:   fwd_rs1 = wb_rd_data;
            default: fwd_rs1 = id_ex_rs1_data;
        endcase
        unique case (forward_b)
            2'b10:   fwd_rs2 = ex_mem_alu_result;
            2'b01:   fwd_rs2 = wb_rd_data;
            default: fwd_rs2 = id_ex_rs2_data;
        endcase
    end

    logic [31:0] alu_a, alu_b, alu_result, mdu_result, exec_result;
    logic        alu_zero;

    always_comb begin
        unique case (id_ex_alu_src_a)
            2'b00:   alu_a = fwd_rs1;
            2'b01:   alu_a = id_ex_pc;
            2'b10:   alu_a = 32'h0;
            default: alu_a = fwd_rs1;
        endcase
    end

    assign alu_b = id_ex_alu_src_b ? id_ex_imm : fwd_rs2;

    alu u_alu (
        .a(alu_a), .b(alu_b), .op(id_ex_alu_op),
        .result(alu_result), .zero(alu_zero)
    );

    mdu u_mdu (
        .a(fwd_rs1), .b(fwd_rs2), .funct3(id_ex_funct3), .result(mdu_result)
    );

    assign exec_result = id_ex_use_mdu ? mdu_result : alu_result;

    // ---- CSR / traps / interrupts (EX) --------------------------------------
    logic        trap_exception, irq_take, trap_ex;
    logic [31:0] trap_cause;
    logic [31:0] csr_rdata, csr_wdata, csr_src;
    logic        csr_we;
    logic [31:0] mtvec, mepc, mcause, mstatus, mie, mip;
    logic        irq_timer;
    logic        mret_ex;

    assign trap_exception = id_ex_valid && (id_ex_trap_ecall || id_ex_trap_ebreak);
    assign mret_ex        = id_ex_valid && id_ex_mret;
    // Take timer IRQ on a valid EX instruction (re-execute it after mret).
    // Exceptions and mret win over interrupts.
    assign irq_take = id_ex_valid && irq_timer && !trap_exception && !mret_ex;
    assign trap_ex  = trap_exception || irq_take;

    always_comb begin
        if (id_ex_trap_ebreak)
            trap_cause = 32'd3;
        else if (id_ex_trap_ecall)
            trap_cause = 32'd11;
        else
            trap_cause = 32'h8000_0007;  // Machine timer interrupt
    end

    assign csr_src = id_ex_csr_use_imm ? {27'b0, id_ex_rs1} : fwd_rs1;

    always_comb begin
        unique case (id_ex_funct3[1:0])
            2'b01:   csr_wdata = csr_src;
            2'b10:   csr_wdata = csr_rdata | csr_src;
            2'b11:   csr_wdata = csr_rdata & ~csr_src;
            default: csr_wdata = csr_src;
        endcase
    end

    always_comb begin
        csr_we = 1'b0;
        if (id_ex_valid && id_ex_csr_op && !trap_ex) begin
            unique case (id_ex_funct3[1:0])
                2'b01:   csr_we = 1'b1;
                2'b10,
                2'b11:   csr_we = (csr_src != 32'h0);
                default: csr_we = 1'b0;
            endcase
        end
    end

    csr_file u_csr (
        .clk(clk), .rst_n(rst_n),
        .addr(id_ex_csr_addr),
        .wdata(csr_wdata),
        .we(csr_we),
        .rdata(csr_rdata),
        .trap(trap_ex),
        .trap_cause(trap_cause),
        .trap_pc(id_ex_pc),
        .mret(mret_ex),
        .ext_mtip(timer_irq),
        .mtvec(mtvec), .mepc(mepc), .mcause(mcause), .mstatus(mstatus),
        .mie(mie), .mip(mip), .irq_timer(irq_timer)
    );

    /* verilator lint_off UNUSEDSIGNAL */
    logic unused_mie_mip;
    assign unused_mie_mip = |{mie, mip};
    /* verilator lint_on UNUSEDSIGNAL */

    assign dbg_mepc    = mepc;
    assign dbg_mcause  = mcause;
    assign dbg_mtvec   = mtvec;
    assign dbg_mstatus = mstatus;

    // Value to pipe forward / writeback (ALU, MDU, or CSR old value)
    logic [31:0] ex_wb_data;
    assign ex_wb_data = (id_ex_result_src == 2'b11) ? csr_rdata : exec_result;

    logic take_branch;
    always_comb begin
        take_branch = 1'b0;
        if (id_ex_branch) begin
            unique case (id_ex_funct3)
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

    logic [31:0] pc_target, pc_jalr;
    assign pc_target = id_ex_pc + id_ex_imm;
    assign pc_jalr   = {alu_result[31:1], 1'b0};

    always_comb begin
        pc_redirect = 1'b0;
        pc_redirect_target = pc_plus4;
        if (trap_ex) begin
            pc_redirect        = 1'b1;
            pc_redirect_target = mtvec;
        end else if (mret_ex) begin
            pc_redirect        = 1'b1;
            pc_redirect_target = mepc;
        end else if (id_ex_valid && id_ex_jalr) begin
            pc_redirect        = 1'b1;
            pc_redirect_target = pc_jalr;
        end else if (id_ex_valid && (id_ex_jump || take_branch)) begin
            pc_redirect        = 1'b1;
            pc_redirect_target = pc_target;
        end
    end

    // EX/MEM — kill reg/mem write on trap/interrupt
    logic        ex_mem_valid;
    logic [31:0] ex_mem_pc, ex_mem_pc4, ex_mem_rs2_data;
    logic [2:0]  ex_mem_funct3;
    logic        ex_mem_mem_read, ex_mem_mem_write;
    logic [1:0]  ex_mem_result_src;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_valid      <= 1'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
            ex_mem_pc         <= 32'h0;
            ex_mem_pc4        <= 32'h0;
            ex_mem_alu_result <= 32'h0;
            ex_mem_rs2_data   <= 32'h0;
            ex_mem_rd         <= 5'h0;
            ex_mem_funct3     <= 3'h0;
            ex_mem_result_src <= 2'h0;
        end else begin
            ex_mem_valid      <= id_ex_valid && !trap_ex;
            ex_mem_pc         <= id_ex_pc;
            ex_mem_pc4        <= id_ex_pc4;
            ex_mem_alu_result <= ex_wb_data;
            ex_mem_rs2_data   <= fwd_rs2;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_funct3     <= id_ex_funct3;
            ex_mem_result_src <= id_ex_result_src;
            ex_mem_reg_write  <= id_ex_reg_write && !trap_ex;
            ex_mem_mem_read   <= id_ex_mem_read && !trap_ex;
            ex_mem_mem_write  <= id_ex_mem_write && !trap_ex;
        end
    end

    assign dbg_pc_mem = ex_mem_pc;

    // -------------------------------------------------------------------------
    // MEM
    // -------------------------------------------------------------------------
    assign dmem_addr   = ex_mem_alu_result;
    assign dmem_wdata  = ex_mem_rs2_data;
    assign dmem_we     = ex_mem_mem_write;
    assign dmem_re     = ex_mem_mem_read;
    assign dmem_funct3 = ex_mem_funct3;

    logic        mem_wb_valid;
    logic [31:0] mem_wb_pc;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_valid      <= 1'b0;
            wb_reg_write      <= 1'b0;
            mem_wb_pc         <= 32'h0;
            mem_wb_pc4        <= 32'h0;
            mem_wb_alu_result <= 32'h0;
            mem_wb_mem_rdata  <= 32'h0;
            wb_rd             <= 5'h0;
            mem_wb_result_src <= 2'h0;
        end else begin
            mem_wb_valid      <= ex_mem_valid;
            mem_wb_pc         <= ex_mem_pc;
            mem_wb_pc4        <= ex_mem_pc4;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_rdata  <= dmem_rdata;
            wb_rd             <= ex_mem_rd;
            mem_wb_result_src <= ex_mem_result_src;
            wb_reg_write      <= ex_mem_reg_write;
        end
    end

    assign dbg_pc_wb    = mem_wb_pc;
    assign dbg_valid_wb = mem_wb_valid;

endmodule
