// RV32M multiply / divide unit (combinational — fine for simulation)
module mdu (
    input  logic [31:0] a,
    input  logic [31:0] b,
    input  logic [2:0]  funct3,
    output logic [31:0] result
);

    // funct3 encodings
    // 000 MUL, 001 MULH, 010 MULHSU, 011 MULHU
    // 100 DIV, 101 DIVU, 110 REM, 111 REMU

    logic signed [63:0] prod_ss;
    /* verilator lint_off UNUSEDSIGNAL */
    logic        [63:0] prod_uu;  // low half unused (MULHU takes [63:32])
    logic signed [63:0] prod_su;  // low half unused (MULHSU takes [63:32])
    /* verilator lint_on UNUSEDSIGNAL */

    logic signed [31:0] quot_s, rem_s;
    logic        [31:0] quot_u, rem_u;

    assign prod_ss = $signed(a) * $signed(b);
    assign prod_uu = {32'b0, a} * {32'b0, b};
    // signed rs1 × unsigned rs2
    assign prod_su = $signed({{32{a[31]}}, a}) * $signed({32'b0, b});

    always_comb begin
        // RISC-V divide-by-zero and signed-overflow rules
        if (b == 32'h0) begin
            quot_s = 32'hFFFF_FFFF;           // -1
            rem_s  = $signed(a);
            quot_u = 32'hFFFF_FFFF;
            rem_u  = a;
        end else if ((a == 32'h8000_0000) && (b == 32'hFFFF_FFFF)) begin
            quot_s = 32'h8000_0000;           // overflow: return dividend
            rem_s  = 32'sh0;
            quot_u = a / b;
            rem_u  = a % b;
        end else begin
            quot_s = $signed(a) / $signed(b);
            rem_s  = $signed(a) % $signed(b);
            quot_u = a / b;
            rem_u  = a % b;
        end
    end

    always_comb begin
        unique case (funct3)
            3'b000:  result = prod_ss[31:0];    // MUL
            3'b001:  result = prod_ss[63:32];   // MULH
            3'b010:  result = prod_su[63:32];   // MULHSU
            3'b011:  result = prod_uu[63:32];   // MULHU
            3'b100:  result = quot_s;           // DIV
            3'b101:  result = quot_u;           // DIVU
            3'b110:  result = rem_s;            // REM
            3'b111:  result = rem_u;            // REMU
            default: result = 32'h0;
        endcase
    end

endmodule
