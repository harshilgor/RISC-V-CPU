// Minimal machine-mode CSR file (Zicsr-accessible)
module csr_file (
    input  logic        clk,
    input  logic        rst_n,

    // CSR instruction port
    input  logic [11:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    output logic [31:0] rdata,

    // Trap side-effects (hardware)
    input  logic        trap,
    input  logic        trap_ebreak,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] trap_pc,   // bit[0] forced 0 into mepc (IALIGN)
    /* verilator lint_on UNUSEDSIGNAL */

    // Exposed for next-PC logic / debug
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic [31:0] mcause,
    output logic [31:0] mstatus
);

    // Standard CSR addresses
    localparam logic [11:0]
        CSR_MSTATUS = 12'h300,
        CSR_MTVEC   = 12'h305,
        CSR_MEPC    = 12'h341,
        CSR_MCAUSE  = 12'h342;

    logic [31:0] mstatus_r, mtvec_r, mepc_r, mcause_r;

    assign mstatus = mstatus_r;
    assign mtvec   = mtvec_r;
    assign mepc    = mepc_r;
    assign mcause  = mcause_r;

    // Combinational read
    always_comb begin
        unique case (addr)
            CSR_MSTATUS: rdata = mstatus_r;
            CSR_MTVEC:   rdata = mtvec_r;
            CSR_MEPC:    rdata = mepc_r;
            CSR_MCAUSE:  rdata = mcause_r;
            default:     rdata = 32'h0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_r <= 32'h0;
            mtvec_r   <= 32'h0000_0100;  // default handler base
            mepc_r    <= 32'h0;
            mcause_r  <= 32'h0;
        end else if (trap) begin
            // Spec: mepc = address of the faulting instruction
            mepc_r   <= {trap_pc[31:1], 1'b0};  // IALIGN: clear LSB
            mcause_r <= trap_ebreak ? 32'd3 : 32'd11;
        end else if (we) begin
            unique case (addr)
                CSR_MSTATUS: mstatus_r <= wdata;
                CSR_MTVEC:   mtvec_r   <= {wdata[31:2], 2'b00}; // MODE=Direct
                CSR_MEPC:    mepc_r    <= {wdata[31:1], 1'b0};
                CSR_MCAUSE:  mcause_r  <= wdata;
                default: ;
            endcase
        end
    end

endmodule
