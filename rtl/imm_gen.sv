// RV32I immediate generator — combinational
// Assembles and sign-extends immediates from the instruction word.
module imm_gen (
    // Full instruction word; format bits are selected by imm_src.
    // Opcode/rd/rs fields are intentionally unused here.
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] instr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [2:0]  imm_src,
    output logic [31:0] imm
);

    // Format select (driven later by the control unit from opcode)
    localparam logic [2:0]
        IMM_I = 3'b000,
        IMM_S = 3'b001,
        IMM_B = 3'b010,
        IMM_U = 3'b011,
        IMM_J = 3'b100;

    always_comb begin
        unique case (imm_src)
            // I-type: instr[31:20]
            IMM_I: imm = {{20{instr[31]}}, instr[31:20]};

            // S-type: {instr[31:25], instr[11:7]}
            IMM_S: imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};

            // B-type: {instr[31], instr[7], instr[30:25], instr[11:8], 1'b0}
            IMM_B: imm = {{19{instr[31]}}, instr[31], instr[7],
                          instr[30:25], instr[11:8], 1'b0};

            // U-type: {instr[31:12], 12'b0}
            IMM_U: imm = {instr[31:12], 12'b0};

            // J-type: {instr[31], instr[19:12], instr[20], instr[30:21], 1'b0}
            IMM_J: imm = {{11{instr[31]}}, instr[31], instr[19:12],
                          instr[20], instr[30:21], 1'b0};

            default: imm = 32'h0;
        endcase
    end

endmodule
