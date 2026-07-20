// Minimal machine-mode CSR file (Zicsr + timer interrupt bits)
module csr_file (
    input  logic        clk,
    input  logic        rst_n,

    // CSR instruction port
    input  logic [11:0] addr,
    input  logic [31:0] wdata,
    input  logic        we,
    output logic [31:0] rdata,

    // Trap / interrupt entry (hardware)
    input  logic        trap,
    input  logic [31:0] trap_cause,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] trap_pc,
    /* verilator lint_on UNUSEDSIGNAL */

    // mret side-effects
    input  logic        mret,

    // External pending bits into mip (level)
    input  logic        ext_mtip,

    // Exposed for next-PC / interrupt check / debug
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic [31:0] mcause,
    output logic [31:0] mstatus,
    output logic [31:0] mie,
    output logic [31:0] mip,
    output logic        irq_timer   // MIE & MTIE & MTIP
);

    localparam logic [11:0]
        CSR_MSTATUS = 12'h300,
        CSR_MIE     = 12'h304,
        CSR_MTVEC   = 12'h305,
        CSR_MEPC    = 12'h341,
        CSR_MCAUSE  = 12'h342,
        CSR_MIP     = 12'h344;

    // mstatus: only MIE (bit3) and MPIE (bit7) implemented
    logic [31:0] mstatus_r, mtvec_r, mepc_r, mcause_r, mie_r;

    logic [31:0] mip_r;
    assign mip_r = {24'b0, ext_mtip, 7'b0};  // bit7 = MTIP

    assign mstatus = mstatus_r;
    assign mtvec   = mtvec_r;
    assign mepc    = mepc_r;
    assign mcause  = mcause_r;
    assign mie     = mie_r;
    assign mip     = mip_r;

    assign irq_timer = mstatus_r[3] & mie_r[7] & ext_mtip;

    always_comb begin
        unique case (addr)
            CSR_MSTATUS: rdata = mstatus_r;
            CSR_MIE:     rdata = mie_r;
            CSR_MTVEC:   rdata = mtvec_r;
            CSR_MEPC:    rdata = mepc_r;
            CSR_MCAUSE:  rdata = mcause_r;
            CSR_MIP:     rdata = mip_r;
            default:     rdata = 32'h0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mstatus_r <= 32'h0;
            mie_r     <= 32'h0;
            mtvec_r   <= 32'h0000_0100;
            mepc_r    <= 32'h0;
            mcause_r  <= 32'h0;
        end else if (trap) begin
            mepc_r      <= {trap_pc[31:1], 1'b0};
            mcause_r    <= trap_cause;
            // MPIE <- MIE; MIE <- 0
            mstatus_r[7] <= mstatus_r[3];
            mstatus_r[3] <= 1'b0;
        end else if (mret) begin
            // MIE <- MPIE; MPIE <- 1
            mstatus_r[3] <= mstatus_r[7];
            mstatus_r[7] <= 1'b1;
        end else if (we) begin
            unique case (addr)
                CSR_MSTATUS: mstatus_r <= wdata;
                CSR_MIE:     mie_r     <= wdata & 32'h0000_0080; // MTIE only
                CSR_MTVEC:   mtvec_r   <= {wdata[31:2], 2'b00};
                CSR_MEPC:    mepc_r    <= {wdata[31:1], 1'b0};
                CSR_MCAUSE:  mcause_r  <= wdata;
                CSR_MIP:     ; // MTIP is read-only from software
                default: ;
            endcase
        end
    end

endmodule
