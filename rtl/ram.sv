// Data RAM — same byte/half/word behavior as dmem
module ram #(
    parameter int DEPTH = 1024
) (
    input  logic        clk,
    /* verilator lint_off UNUSEDSIGNAL */
    input  logic [31:0] addr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic [31:0] wdata,
    input  logic        we,
    input  logic [2:0]  funct3,
    output logic [31:0] rdata
);

    localparam int AW = $clog2(DEPTH);
    logic [31:0] mem [0:DEPTH-1];
    logic [AW-1:0] idx;
    logic [31:0] word;
    logic [7:0]  byte_val;
    logic [15:0] half_val;

    assign idx  = addr[2 +: AW];
    assign word = mem[idx];

    always_comb begin
        unique case (addr[1:0])
            2'b00: byte_val = word[7:0];
            2'b01: byte_val = word[15:8];
            2'b10: byte_val = word[23:16];
            2'b11: byte_val = word[31:24];
        endcase
        half_val = addr[1] ? word[31:16] : word[15:0];
    end

    always_comb begin
        unique case (funct3)
            3'b000:  rdata = {{24{byte_val[7]}}, byte_val};
            3'b001:  rdata = {{16{half_val[15]}}, half_val};
            3'b010:  rdata = word;
            3'b100:  rdata = {24'b0, byte_val};
            3'b101:  rdata = {16'b0, half_val};
            default: rdata = word;
        endcase
    end

    always_ff @(posedge clk) begin
        if (we) begin
            unique case (funct3)
                3'b000: begin
                    unique case (addr[1:0])
                        2'b00: mem[idx][7:0]   <= wdata[7:0];
                        2'b01: mem[idx][15:8]  <= wdata[7:0];
                        2'b10: mem[idx][23:16] <= wdata[7:0];
                        2'b11: mem[idx][31:24] <= wdata[7:0];
                    endcase
                end
                3'b001: begin
                    if (addr[1]) mem[idx][31:16] <= wdata[15:0];
                    else         mem[idx][15:0]  <= wdata[15:0];
                end
                default: mem[idx] <= wdata;
            endcase
        end
    end

endmodule
