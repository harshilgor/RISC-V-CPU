// RV32IM control unit — combinational decode
module control (
    input  logic [6:0]  opcode,
    input  logic [2:0]  funct3,
    input  logic [6:0]  funct7,
    input  logic [11:0] funct12,  // instr[31:20] for SYSTEM

    output logic        reg_write,
    output logic [2:0]  imm_src,
    output logic [1:0]  alu_src_a,   // 00=rs1, 01=pc, 10=0
    output logic        alu_src_b,   // 0=rs2, 1=imm
    output logic [3:0]  alu_op,
    output logic        use_mdu,     // 1 = writeback from MDU (RV32M)
    output logic        mem_read,
    output logic        mem_write,
    output logic [1:0]  result_src,  // 00=alu/mdu, 01=mem, 10=pc+4
    output logic        branch,
    output logic        jump,
    output logic        jalr,
    output logic        trap_ecall,
    output logic        trap_ebreak,
    output logic        mret
);

    localparam logic [6:0]
        OP_LOAD     = 7'b0000011,
        OP_MISC_MEM = 7'b0001111,  // FENCE
        OP_OPIMM    = 7'b0010011,
        OP_AUIPC    = 7'b0010111,
        OP_STORE    = 7'b0100011,
        OP_OP       = 7'b0110011,
        OP_LUI      = 7'b0110111,
        OP_BRANCH   = 7'b1100011,
        OP_JALR     = 7'b1100111,
        OP_JAL      = 7'b1101111,
        OP_SYSTEM   = 7'b1110011;

    localparam logic [2:0]
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100;

    localparam logic [3:0]
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLL  = 4'b0101,
        ALU_SRL  = 4'b0110,
        ALU_SRA  = 4'b0111,
        ALU_SLT  = 4'b1000,
        ALU_SLTU = 4'b1001;

    localparam logic [1:0]
        A_RS1  = 2'b00,
        A_PC   = 2'b01,
        A_ZERO = 2'b10;

    localparam logic [1:0]
        RES_ALU = 2'b00,
        RES_MEM = 2'b01,
        RES_PC4 = 2'b10;

    function automatic logic [3:0] alu_from_funct(
        input logic [2:0] f3,
        input logic       f7_5,
        input logic       is_reg
    );
        begin
            unique case (f3)
                3'b000:  alu_from_funct = (is_reg && f7_5) ? ALU_SUB : ALU_ADD;
                3'b001:  alu_from_funct = ALU_SLL;
                3'b010:  alu_from_funct = ALU_SLT;
                3'b011:  alu_from_funct = ALU_SLTU;
                3'b100:  alu_from_funct = ALU_XOR;
                3'b101:  alu_from_funct = f7_5 ? ALU_SRA : ALU_SRL;
                3'b110:  alu_from_funct = ALU_OR;
                3'b111:  alu_from_funct = ALU_AND;
                default: alu_from_funct = ALU_ADD;
            endcase
        end
    endfunction

    function automatic logic [3:0] branch_alu(input logic [2:0] f3);
        begin
            unique case (f3)
                3'b000, 3'b001: branch_alu = ALU_SUB;
                3'b100, 3'b101: branch_alu = ALU_SLT;
                3'b110, 3'b111: branch_alu = ALU_SLTU;
                default:        branch_alu = ALU_SUB;
            endcase
        end
    endfunction

    always_comb begin
        reg_write    = 1'b0;
        imm_src      = IMM_I;
        alu_src_a    = A_RS1;
        alu_src_b    = 1'b0;
        alu_op       = ALU_ADD;
        use_mdu      = 1'b0;
        mem_read     = 1'b0;
        mem_write    = 1'b0;
        result_src   = RES_ALU;
        branch       = 1'b0;
        jump         = 1'b0;
        jalr         = 1'b0;
        trap_ecall   = 1'b0;
        trap_ebreak  = 1'b0;
        mret         = 1'b0;

        unique case (opcode)
            OP_LUI: begin
                reg_write  = 1'b1;
                imm_src    = IMM_U;
                alu_src_a  = A_ZERO;
                alu_src_b  = 1'b1;
                alu_op     = ALU_ADD;
                result_src = RES_ALU;
            end

            OP_AUIPC: begin
                reg_write  = 1'b1;
                imm_src    = IMM_U;
                alu_src_a  = A_PC;
                alu_src_b  = 1'b1;
                alu_op     = ALU_ADD;
                result_src = RES_ALU;
            end

            OP_JAL: begin
                reg_write  = 1'b1;
                imm_src    = IMM_J;
                result_src = RES_PC4;
                jump       = 1'b1;
            end

            OP_JALR: begin
                reg_write  = 1'b1;
                imm_src    = IMM_I;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b1;
                alu_op     = ALU_ADD;
                result_src = RES_PC4;
                jalr       = 1'b1;
            end

            OP_BRANCH: begin
                imm_src    = IMM_B;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b0;
                alu_op     = branch_alu(funct3);
                branch     = 1'b1;
            end

            OP_LOAD: begin
                reg_write  = 1'b1;
                imm_src    = IMM_I;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b1;
                alu_op     = ALU_ADD;
                mem_read   = 1'b1;
                result_src = RES_MEM;
            end

            OP_STORE: begin
                imm_src    = IMM_S;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b1;
                alu_op     = ALU_ADD;
                mem_write  = 1'b1;
            end

            OP_OPIMM: begin
                reg_write  = 1'b1;
                imm_src    = IMM_I;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b1;
                alu_op     = alu_from_funct(funct3, funct7[5], 1'b0);
                result_src = RES_ALU;
            end

            OP_OP: begin
                reg_write  = 1'b1;
                alu_src_a  = A_RS1;
                alu_src_b  = 1'b0;
                result_src = RES_ALU;
                if (funct7 == 7'b0000001) begin
                    // RV32M
                    use_mdu = 1'b1;
                end else begin
                    alu_op = alu_from_funct(funct3, funct7[5], 1'b1);
                end
            end

            OP_MISC_MEM: begin
                // FENCE / FENCE.I — treat as NOP on this core
            end

            OP_SYSTEM: begin
                if (funct3 == 3'b000) begin
                    unique case (funct12)
                        12'h000: trap_ecall  = 1'b1;
                        12'h001: trap_ebreak = 1'b1;
                        12'h302: mret        = 1'b1;
                        default: ;
                    endcase
                end
                // Full Zicsr (csrrw/…) comes later
            end

            default: ;
        endcase
    end

endmodule
