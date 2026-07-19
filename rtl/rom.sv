// Boot ROM — word-addressed, loadable by testbench; read-only at runtime
module rom #(
    parameter int DEPTH = 1024
) (
    input  logic        clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] rdata,

    input  logic        we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] waddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata
);

    localparam int AW = $clog2(DEPTH);
    logic [31:0] mem [0:DEPTH-1];
    logic [AW-1:0] ridx, widx;

    assign ridx  = addr[2 +: AW];
    assign widx  = waddr[2 +: AW];
    assign rdata = mem[ridx];

    always_ff @(posedge clk) begin
        if (we)
            mem[widx] <= wdata;
    end

endmodule
