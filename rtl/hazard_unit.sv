// Hazard unit (Phase 2: load-use stall; Phase 3: control-flow flush)
module hazard_unit (
    input  logic       id_ex_mem_read,
    input  logic [4:0] id_ex_rd,
    input  logic [4:0] if_id_rs1,
    input  logic [4:0] if_id_rs2,
    input  logic       if_id_use_rs1,
    input  logic       if_id_use_rs2,
    input  logic       pc_redirect,   // taken branch / jal / jalr in EX
    output logic       stall,         // freeze PC + IF/ID; bubble into ID/EX
    output logic       flush_if_id    // squash wrong-path instr in IF/ID
);

    logic load_use;
    assign load_use =
        id_ex_mem_read &&
        (id_ex_rd != 5'd0) &&
        ((if_id_use_rs1 && (id_ex_rd == if_id_rs1)) ||
         (if_id_use_rs2 && (id_ex_rd == if_id_rs2)));

    assign stall       = load_use;
    assign flush_if_id = pc_redirect;

endmodule
