// Program counter — holds address of current instruction
module pc (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] pc_next,
    output logic [31:0] pc
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'h0;
        else
            pc <= pc_next;
    end

endmodule
