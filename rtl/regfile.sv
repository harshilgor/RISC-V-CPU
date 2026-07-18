// RV32I register file: 32 x 32-bit registers
// - 2 asynchronous read ports
// - 1 synchronous write port
// - x0 is hardwired to 0 (reads as 0, writes ignored)
module regfile (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        we,
    input  logic [4:0]  rs1_addr,
    input  logic [4:0]  rs2_addr,
    input  logic [4:0]  rd_addr,
    input  logic [31:0] rd_data,
    output logic [31:0] rs1_data,
    output logic [31:0] rs2_data,
    // Debug peek port for the testbench / GTKWave
    input  logic [4:0]  dbg_addr,
    output logic [31:0] dbg_data
);

    logic [31:0] regs [0:31];

    // Synchronous write; x0 is never written
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 32; i++)
                regs[i] <= 32'h0;
        end else if (we && (rd_addr != 5'd0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    // Asynchronous reads; x0 always returns 0
    assign rs1_data = (rs1_addr == 5'd0) ? 32'h0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == 5'd0) ? 32'h0 : regs[rs2_addr];
    assign dbg_data = (dbg_addr == 5'd0) ? 32'h0 : regs[dbg_addr];

endmodule
