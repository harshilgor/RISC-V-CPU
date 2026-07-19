// Boot ROM — dual-port (I-fetch + data read), TB loadable
module rom #(
    parameter int DEPTH = 1024
) (
    input  logic        clk,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] i_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] i_rdata,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] d_addr,
    /* verilator lint_on UNUSEDSIGNAL */
    output logic [31:0] d_rdata,

    input  logic        we,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] waddr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata
);

    localparam int AW = $clog2(DEPTH);
    logic [31:0] mem [0:DEPTH-1];
    logic [AW-1:0] i_idx, d_idx, widx;

    assign i_idx   = i_addr[2 +: AW];
    assign d_idx   = d_addr[2 +: AW];
    assign widx    = waddr[2 +: AW];
    assign i_rdata = mem[i_idx];
    assign d_rdata = mem[d_idx];

    always_ff @(posedge clk) begin
        if (we)
            mem[widx] <= wdata;
    end

endmodule
