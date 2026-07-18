// RV32I ALU — combinational, 32-bit
// Ops cover the integer ALU used by R-type and most I-type instructions.
module alu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [3:0]  op,
    output logic [31:0] result,
    output logic        zero
);

    // ALU op encodings (used later by the control unit)
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

    logic [4:0] shamt;
    assign shamt = b[4:0];

    always_comb begin
        unique case (op)
            ALU_ADD:  result = a + b;
            ALU_SUB:  result = a - b;
            ALU_AND:  result = a & b;
            ALU_OR:   result = a | b;
            ALU_XOR:  result = a ^ b;
            ALU_SLL:  result = a << shamt;
            ALU_SRL:  result = a >> shamt;
            ALU_SRA:  result = $signed(a) >>> shamt;
            ALU_SLT:  result = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU: result = {31'b0, (a < b)};
            default:  result = 32'h0000_0000;
        endcase
    end

    assign zero = (result == 32'h0000_0000);

endmodule
