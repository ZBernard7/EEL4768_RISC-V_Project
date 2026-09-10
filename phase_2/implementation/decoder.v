// AI USE DISCLOSURE:
// OpenAI ChatGPT was used as an aid in the development of this file.
// Accessed September 2026.

`default_nettype none

// Remember to instantiate the imm in this module

module decoder (
    // Input instruction word.
    input  wire [31:0] i_inst,
    // Asserted if the instruction was decoded as a legal instruction. It is
    // important that the decoder not accept any illegal instruction
    // encodings as this could lead to undefined behavior in the processor
    // which is a safety hazard.
    output wire        o_legal,
    // Indicates that the instruction is an ebreak and should halt execution.
    output wire        o_halt,
    // First source register address.
    // For instructions that do not use a source register, this is effectively
    // a don't care because reading unused registers does not have any side
    // effects (and we don't care about power usage, really).
    output wire [ 4:0] o_rs1,
    // Second source register address.
    // Similarly to o_rs1, this is a don't care for instructions that do not
    // read a (second) source register.
    output wire [ 4:0] o_rs2,
    // Destination register address.
    // For instructions that do not write to a register, this must be set to
    // x0 so the value is discarded. This avoids the need for a separate write
    // enable since discard behavior must be present anyway.
    output wire [ 4:0] o_rd,
    // 32-bit immediate value, decoded from the instruction word. For R-type
    // instructions that do not use an immediate, this is a don't care.
    output wire [31:0] o_immediate,
    // Selects whether the first operand for the ALU is fed by the first
    // register source (rs1) or the current pc.
    // When asserted, the second operand is the immediate.
    output wire        o_op1_sel,
    // Selects whether the second operand for the ALU is fed by the second
    // register source (rs2) or the immediate.
    // When asserted, the second operand is the immediate.
    output wire        o_op2_sel,
    // Major opsel for the ALU. See ALU documentation for the encoding.
    output wire [ 2:0] o_alu_opsel,
    // Minor opsel flags for the ALU. See ALU documentation for the encoding.
    output wire        o_alu_sub,
    output wire        o_alu_unsigned,
    output wire        o_alu_arith,
    // If asserted, the instruction is a branch instruction and the PC should
    // be updated to the target address if the branch condition is met.
    output wire        o_branch,
    // If asserted, the instruction is a jump instruction and the PC should
    // be updated to the target address unconditionally.
    output wire        o_jump,
    // When asserted, the branch comparator checks for equality. When not
    // asserted, it checks for less than [unsigned].
    output wire        o_branch_equal,
    // When asserted, the branch comparator treats the less than comparison
    // operands as unsigned. This is only used when `!o_branch_equal`.
    output wire        o_branch_unsigned,
    // When asserted, the branch condition is inverted.
    // Equality -> inequality, less than -> greater than or equal.
    output wire        o_branch_invert,
    // When asserted, the instruction will load from memory.
    output wire        o_dmem_ren,
    // When asserted, the instruction will store to memory.
    output wire        o_dmem_wen,
    // This 2-bit mask selects which LSBs of the memory address should be
    // checked for alignment. This is because byte and half-word accesses need
    // only be 1-byte and 2-byte aligned, respectively.
    output wire [ 1:0] o_dmem_align,
    // These 3 bits select the size of the memory access.
    // They are effectively one-hot encoded.
    output wire        o_dmem_memb,
    output wire        o_dmem_memh,
    output wire        o_dmem_memw,
    // If asserted, the (byte or half-word) memory access is unsigned and the
    // load should be zero-extended to 32 bits instead of sign-extended.
    output wire        o_dmem_memu,
    // Selects the data to write to the destination register, one-hot.
    // [0] = ALU result
    // [1] = immediate
    // [2] = PC + 4
    // [3] = memory
    output wire [ 3:0] o_rd_sel,
    // If asserted, the PC jumps to the target address calculated by the ALU
    // rather than directly to the PC + immediate. This is used for JALR.
    output wire        o_pc_sel
);
    // Your implementation goes under here
    // ------------------------------------
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [4:0] rs1;
    wire [4:0] rs2;
    wire [4:0] rd;

    assign opcode = i_inst[6:0];
    assign rd     = i_inst[11:7];
    assign funct3 = i_inst[14:12];
    assign rs1    = i_inst[19:15];
    assign rs2    = i_inst[24:20];
    assign funct7 = i_inst[31:25];

    wire [5:0] format;

    imm immediate_generator (
        .i_inst(i_inst),
        .i_format(format),
        .o_immediate(o_immediate)
    );

wire is_lui;
wire is_auipc;
wire is_jal;
wire is_jalr;
wire is_branch;
wire is_load;
wire is_store;
wire is_op_imm;
wire is_op;
wire is_system;
assign is_lui    = (opcode == 7'b0110111);
assign is_auipc  = (opcode == 7'b0010111);
assign is_jal    = (opcode == 7'b1101111);
assign is_jalr   = (opcode == 7'b1100111);
assign is_branch = (opcode == 7'b1100011);
assign is_load   = (opcode == 7'b0000011);
assign is_store  = (opcode == 7'b0100011);
assign is_op_imm = (opcode == 7'b0010011);
assign is_op     = (opcode == 7'b0110011);
assign is_system = (opcode == 7'b1110011);

assign format =
    (is_op)                         ? 6'b000001 :
    (is_op_imm || is_load || is_jalr) ? 6'b000010 :
    (is_store)                      ? 6'b000100 :
    (is_branch)                     ? 6'b001000 :
    (is_lui || is_auipc)            ? 6'b010000 :
    (is_jal)                        ? 6'b100000 :
                                      6'b000000;

assign o_rs1 = rs1;
assign o_rs2 = rs2;

assign o_op1_sel = is_auipc;
assign o_op2_sel =
    is_op_imm || is_load || is_store ||
    is_auipc || is_jalr;

assign o_alu_opsel =
    (is_op || is_op_imm) ? funct3 :
                           3'b000;

assign o_alu_sub =
    is_op && (funct3 == 3'b000) && (funct7 == 7'b0100000);

assign o_alu_arith =
    (funct3 == 3'b101) &&
    (funct7 == 7'b0100000) &&
    (is_op || is_op_imm);

assign o_alu_unsigned =
    ((is_op || is_op_imm) && (funct3 == 3'b011)) ||
    (is_branch && funct3[1]);

assign o_branch = is_branch;
assign o_jump   = is_jal || is_jalr;
assign o_pc_sel = is_jalr;

assign o_branch_equal =
    is_branch && (funct3[2:1] == 2'b00);

assign o_branch_unsigned =
    is_branch && (funct3[2:1] == 2'b11);

assign o_branch_invert =
    is_branch && funct3[0];

assign o_dmem_ren = is_load;
assign o_dmem_wen = is_store;

assign o_dmem_memb =
    (is_load || is_store) && (funct3[1:0] == 2'b00);

assign o_dmem_memh =
    (is_load || is_store) && (funct3[1:0] == 2'b01);

assign o_dmem_memw =
    (is_load || is_store) && (funct3[1:0] == 2'b10);

assign o_dmem_memu =
    is_load && funct3[2];

assign o_dmem_align =
    o_dmem_memw ? 2'b11 :
    o_dmem_memh ? 2'b01 :
                  2'b00;

assign o_rd_sel =
    is_lui                 ? 4'b0010 :
    (is_jal || is_jalr)    ? 4'b0100 :
    is_load                ? 4'b1000 :
                             4'b0001;

assign o_halt = (i_inst == 32'h00100073);

wire legal_branch;
wire legal_load;
wire legal_store;
wire legal_jalr;
wire legal_op_imm;
wire legal_op;

assign o_rd =
    (is_lui ||
     is_auipc ||
     is_jal ||
     legal_jalr ||
     legal_load ||
     legal_op_imm ||
     legal_op)
        ? rd
        : 5'b00000;

assign legal_branch =
    is_branch &&
    ((funct3 == 3'b000) ||   // BEQ
     (funct3 == 3'b001) ||   // BNE
     (funct3 == 3'b100) ||   // BLT
     (funct3 == 3'b101) ||   // BGE
     (funct3 == 3'b110) ||   // BLTU
     (funct3 == 3'b111));    // BGEU

assign legal_load =
    is_load &&
    ((funct3 == 3'b000) ||   // LB
     (funct3 == 3'b001) ||   // LH
     (funct3 == 3'b010) ||   // LW
     (funct3 == 3'b100) ||   // LBU
     (funct3 == 3'b101));    // LHU

assign legal_store =
    is_store &&
    ((funct3 == 3'b000) ||   // SB
     (funct3 == 3'b001) ||   // SH
     (funct3 == 3'b010));    // SW

assign legal_jalr =
    is_jalr && (funct3 == 3'b000);

assign legal_op =
    is_op &&
    (
        // ADD, SLL, SLT, SLTU, XOR, SRL, OR, AND
        ((funct7 == 7'b0000000) &&
         ((funct3 == 3'b000) ||
          (funct3 == 3'b001) ||
          (funct3 == 3'b010) ||
          (funct3 == 3'b011) ||
          (funct3 == 3'b100) ||
          (funct3 == 3'b101) ||
          (funct3 == 3'b110) ||
          (funct3 == 3'b111)))
        ||
        // SUB and SRA
        ((funct7 == 7'b0100000) &&
         ((funct3 == 3'b000) ||
          (funct3 == 3'b101)))
    );

assign legal_op_imm =
    is_op_imm &&
    (
        // ADDI, SLTI, SLTIU, XORI, ORI, ANDI
        (funct3 == 3'b000) ||
        (funct3 == 3'b010) ||
        (funct3 == 3'b011) ||
        (funct3 == 3'b100) ||
        (funct3 == 3'b110) ||
        (funct3 == 3'b111) ||

        // SLLI
        ((funct3 == 3'b001) &&
         (funct7 == 7'b0000000)) ||

        // SRLI
        ((funct3 == 3'b101) &&
         (funct7 == 7'b0000000)) ||

        // SRAI
        ((funct3 == 3'b101) &&
         (funct7 == 7'b0100000))
    );

assign o_legal =
    is_lui ||
    is_auipc ||
    is_jal ||
    legal_jalr ||
    legal_branch ||
    legal_load ||
    legal_store ||
    legal_op_imm ||
    legal_op ||
    o_halt;

endmodule

`default_nettype wire
