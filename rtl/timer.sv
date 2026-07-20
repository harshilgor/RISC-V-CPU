// Simple 32-bit CLINT-style timer for the teaching SoC
//
// Map (word offsets from TIMER_BASE):
//   +0x0  mtime     (R/W)  free-running counter (+1 per clock)
//   +0x4  mtimecmp  (R/W)  compare register
//
// irq asserted while (mtime >= mtimecmp). Software clears by writing
// a future mtimecmp (or advancing mtime).
module timer (
    input  logic        clk,
    input  logic        rst_n,

    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic        re,
    output logic [31:0] rdata,
    output logic        irq
);

    logic [31:0] mtime, mtimecmp;

    assign irq = (mtime >= mtimecmp);

    always_comb begin
        rdata = 32'h0;
        if (re) begin
            unique case (addr[3:2])
                2'b00: rdata = mtime;
                2'b01: rdata = mtimecmp;
                default: rdata = 32'h0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime    <= 32'h0;
            mtimecmp <= 32'hFFFF_FFFF;  // no IRQ until software programs cmp
        end else begin
            if (we && addr[3:2] == 2'b00)
                mtime <= wdata;
            else
                mtime <= mtime + 32'd1;

            if (we && addr[3:2] == 2'b01)
                mtimecmp <= wdata;
        end
    end

endmodule
