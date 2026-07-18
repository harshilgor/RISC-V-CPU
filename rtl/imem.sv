// Instruction memory — word-addressed ROM with a load port for the testbench
module imem #(
    parameter int DEPTH = 256
) (
    input  logic        clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,   // byte address; [1:0] ignored (word aligned)
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] instr,

    // Testbench loader (hold we=0 while the CPU runs)
    input  logic        we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] waddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata
);

    localparam int AW = $clog2(DEPTH);

    logic [31:0] mem [0:DEPTH-1];
    logic [AW-1:0] ridx, widx;

    assign ridx = addr[2 +: AW];
    assign widx = waddr[2 +: AW];

    assign instr = mem[ridx];

    always_ff @(posedge clk) begin
        if (we)
            mem[widx] <= wdata;
    end

endmodule
