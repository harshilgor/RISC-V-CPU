// Minimal memory-mapped UART TX (simulation-friendly)
// Registers (byte offsets from base):
//   +0x00 TXDATA  — write: transmit byte; read: 0
//   +0x04 TXSTATUS— bit0 = tx_ready (always 1 in this model)
module uart (
    input  logic        clk,
    input  logic        rst_n,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,     // offset from UART base
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic        re,
    output logic [31:0] rdata,

    // Sideband for testbench / host
    output logic [7:0]  tx_byte,
    output logic        tx_valid   // 1-cycle pulse when a byte is written
);

    /* verilator lint_off UNUSEDSIGNAL */
    wire [23:0] unused_wdata_hi = wdata[31:8];
    /* verilator lint_on UNUSEDSIGNAL */
    always_comb begin
        rdata = 32'h0;
        if (re) begin
            unique case (addr[3:2])
                2'b00: rdata = 32'h0;          // TXDATA read
                2'b01: rdata = 32'h1;          // TXSTATUS: always ready
                default: rdata = 32'h0;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_byte  <= 8'h0;
            tx_valid <= 1'b0;
        end else begin
            tx_valid <= 1'b0;
            if (we && (addr[3:2] == 2'b00)) begin
                tx_byte  <= wdata[7:0];
                tx_valid <= 1'b1;
            end
        end
    end

endmodule
