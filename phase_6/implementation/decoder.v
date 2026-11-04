`default_nettype none

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
    // [0] = ALU result (including the RV32M multiply/divide result)
    // [1] = immediate
    // [2] = PC + 4
    // [3] = memory
    // [4] = floating-point unit integer result (F extension): fmv.x.w,
    //       fclass.s, feq/flt/fle.s, fcvt.w[u].s, and the old CSR value
    //       for the CSR instructions.
    output wire [ 4:0] o_rd_sel,
    // Asserted for the RV32M instructions (OP opcode, funct7 = 0000001).
    // The ALU then performs the multiply/divide operation selected by
    // `o_alu_opsel` (the instruction's funct3).
    output wire        o_mext,
    // F extension. The floating-point unit decodes the details of its own
    // instructions (funct7, rs2, rm) from the instruction word; the decoder
    // only reports legality and which register file each operand uses.
    //
    // Asserted for instructions executed by the floating-point unit: every
    // OP-FP and fused multiply-add instruction, and the CSR instructions on
    // fflags/frm/fcsr. flw/fsw are ordinary memory accesses and are not
    // included.
    output wire        o_fpu,
    // Asserted when the instruction reads floating-point rs1/rs2/rs3. The
    // register addresses are the usual `o_rs1`/`o_rs2` fields, plus `o_rs3`
    // (bits [31:27]) for the fused multiply-add instructions.
    output wire        o_frs1_en,
    output wire        o_frs2_en,
    output wire        o_frs3_en,
    output wire [ 4:0] o_rs3,
    // Asserted when the instruction writes floating-point register rd
    // (bits [11:7]). For these instructions `o_rd` is 5'd0, since they do
    // not write the integer register file.
    output wire        o_frd_en,
    // If asserted, the PC jumps to the target address calculated by the ALU
    // rather than directly to the PC + immediate. This is used for JALR.
    output wire        o_pc_sel
);

// Write your code here.
// ---------- Instruction fields ----------

wire [6:0] opcode = i_inst[6:0];
wire [4:0] rd     = i_inst[11:7];
wire [2:0] funct3 = i_inst[14:12];
wire [4:0] rs1    = i_inst[19:15];
wire [4:0] rs2    = i_inst[24:20];
wire [6:0] funct7 = i_inst[31:25];

wire is_lui    = opcode == 7'b0110111;
wire is_auipc  = opcode == 7'b0010111;
wire is_jal    = opcode == 7'b1101111;
wire is_jalr   = opcode == 7'b1100111;
wire is_branch = opcode == 7'b1100011;
wire is_load   = opcode == 7'b0000011;
wire is_store  = opcode == 7'b0100011;
wire is_op_imm = opcode == 7'b0010011;
wire is_op     = opcode == 7'b0110011;
wire is_system = opcode == 7'b1110011;

wire is_flw    = opcode == 7'b0000111;
wire is_fsw    = opcode == 7'b0100111;
wire is_op_fp  = opcode == 7'b1010011;

wire is_fused =
    (opcode == 7'b1000011) ||
    (opcode == 7'b1000111) ||
    (opcode == 7'b1001011) ||
    (opcode == 7'b1001111);

// ---------- Immediate generator ----------

wire [5:0] format;

assign format =
    (is_op_imm || is_load || is_jalr || is_flw)
        ? 6'b000010 :
    (is_store || is_fsw)
        ? 6'b000100 :
    is_branch
        ? 6'b001000 :
    (is_lui || is_auipc)
        ? 6'b010000 :
    is_jal
        ? 6'b100000 :
          6'b000001;

imm immediate_generator (
    .i_inst(i_inst),
    .i_format(format),
    .o_immediate(o_immediate)
);

// ---------- RV32I and RV32M legality ----------

wire legal_branch = is_branch &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b001) ||
     (funct3 == 3'b100) ||
     (funct3 == 3'b101) ||
     (funct3 == 3'b110) ||
     (funct3 == 3'b111));

wire legal_load = is_load &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b001) ||
     (funct3 == 3'b010) ||
     (funct3 == 3'b100) ||
     (funct3 == 3'b101));

wire legal_store = is_store &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b001) ||
     (funct3 == 3'b010));

wire legal_jalr = is_jalr && (funct3 == 3'b000);

wire legal_m = is_op && (funct7 == 7'b0000001);

wire legal_op = is_op &&
    ((funct7 == 7'b0000000) ||
     ((funct7 == 7'b0100000) &&
      ((funct3 == 3'b000) || (funct3 == 3'b101))) ||
     (funct7 == 7'b0000001));

wire legal_op_imm = is_op_imm &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b010) ||
     (funct3 == 3'b011) ||
     (funct3 == 3'b100) ||
     (funct3 == 3'b110) ||
     (funct3 == 3'b111) ||
     ((funct3 == 3'b001) && (funct7 == 7'b0000000)) ||
     ((funct3 == 3'b101) &&
      ((funct7 == 7'b0000000) ||
       (funct7 == 7'b0100000))));

assign o_halt = i_inst == 32'h00100073;

// ---------- Floating-point legality ----------

// Static modes 000-100 and dynamic mode 111 are legal.
// The FPU checks the current frm when dynamic rounding is selected.
wire legal_rm = (funct3 <= 3'b100) || (funct3 == 3'b111);

wire legal_flw = is_flw && (funct3 == 3'b010);
wire legal_fsw = is_fsw && (funct3 == 3'b010);

wire fp_add_sub_mul_div = is_op_fp && legal_rm &&
    ((funct7 == 7'b0000000) ||  // FADD.S
     (funct7 == 7'b0000100) ||  // FSUB.S
     (funct7 == 7'b0001000) ||  // FMUL.S
     (funct7 == 7'b0001100));   // FDIV.S

wire fp_sqrt = is_op_fp && legal_rm &&
    (funct7 == 7'b0101100) && (rs2 == 5'd0);

wire fp_sign = is_op_fp &&
    (funct7 == 7'b0010000) &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b001) ||
     (funct3 == 3'b010));

wire fp_min_max = is_op_fp &&
    (funct7 == 7'b0010100) &&
    ((funct3 == 3'b000) || (funct3 == 3'b001));

wire fp_compare = is_op_fp &&
    (funct7 == 7'b1010000) &&
    ((funct3 == 3'b000) ||
     (funct3 == 3'b001) ||
     (funct3 == 3'b010));

wire fp_to_int = is_op_fp && legal_rm &&
    (funct7 == 7'b1100000) &&
    ((rs2 == 5'd0) || (rs2 == 5'd1));

wire int_to_fp = is_op_fp && legal_rm &&
    (funct7 == 7'b1101000) &&
    ((rs2 == 5'd0) || (rs2 == 5'd1));

wire fp_move_to_int = is_op_fp &&
    (funct7 == 7'b1110000) &&
    (rs2 == 5'd0) && (funct3 == 3'b000);

wire fp_class = is_op_fp &&
    (funct7 == 7'b1110000) &&
    (rs2 == 5'd0) && (funct3 == 3'b001);

wire int_move_to_fp = is_op_fp &&
    (funct7 == 7'b1111000) &&
    (rs2 == 5'd0) && (funct3 == 3'b000);

wire legal_fused = is_fused &&
    (i_inst[26:25] == 2'b00) && legal_rm;

wire legal_op_fp =
    fp_add_sub_mul_div ||
    fp_sqrt ||
    fp_sign ||
    fp_min_max ||
    fp_compare ||
    fp_to_int ||
    int_to_fp ||
    fp_move_to_int ||
    fp_class ||
    int_move_to_fp;

// ---------- Floating-point CSR legality ----------

wire legal_csr_address =
    (i_inst[31:20] == 12'h001) ||
    (i_inst[31:20] == 12'h002) ||
    (i_inst[31:20] == 12'h003);

wire legal_csr = is_system && legal_csr_address &&
    ((funct3 == 3'b001) ||
     (funct3 == 3'b010) ||
     (funct3 == 3'b011) ||
     (funct3 == 3'b101) ||
     (funct3 == 3'b110) ||
     (funct3 == 3'b111));

assign o_legal =
    is_lui || is_auipc || is_jal ||
    legal_jalr || legal_branch ||
    legal_load || legal_store ||
    legal_op_imm || legal_op ||
    legal_flw || legal_fsw ||
    legal_op_fp || legal_fused ||
    legal_csr || o_halt;

// ---------- Register-bank controls ----------

assign o_mext = legal_m;
assign o_fpu = legal_op_fp || legal_fused || legal_csr;

assign o_frs1_en =
    fp_add_sub_mul_div || fp_sqrt ||
    fp_sign || fp_min_max || fp_compare ||
    fp_to_int || fp_move_to_int || fp_class ||
    legal_fused;

assign o_frs2_en =
    fp_add_sub_mul_div || fp_sign ||
    fp_min_max || fp_compare ||
    legal_fused || legal_fsw;

assign o_frs3_en = legal_fused;
assign o_rs3 = i_inst[31:27];

assign o_frd_en =
    legal_flw || fp_add_sub_mul_div || fp_sqrt ||
    fp_sign || fp_min_max ||
    int_to_fp || int_move_to_fp || legal_fused;

wire reads_xrs1 =
    legal_op || legal_op_imm ||
    legal_load || legal_store ||
    legal_branch || legal_jalr ||
    legal_flw || legal_fsw ||
    int_to_fp || int_move_to_fp ||
    (legal_csr && !funct3[2]);

wire reads_xrs2 =
    legal_op || legal_store || legal_branch;

// These address outputs serve either register bank.
// The FP enable outputs identify when they refer to FP registers.
assign o_rs1 = (reads_xrs1 || o_frs1_en) ? rs1 : 5'd0;
assign o_rs2 = (reads_xrs2 || o_frs2_en) ? rs2 : 5'd0;

wire writes_integer =
    is_lui || is_auipc || is_jal ||
    legal_jalr || legal_load ||
    legal_op_imm || legal_op ||
    fp_compare || fp_to_int ||
    fp_move_to_int || fp_class || legal_csr;

assign o_rd = writes_integer ? rd : 5'd0;

// ---------- Datapath and ALU controls ----------

assign o_op1_sel = is_auipc;

assign o_op2_sel =
    legal_op_imm || legal_load || legal_store ||
    is_auipc || legal_jalr || legal_flw || legal_fsw;

assign o_alu_opsel =
    (legal_op || legal_op_imm) ? funct3 : 3'b000;

assign o_alu_sub =
    is_op && (funct3 == 3'b000) &&
    (funct7 == 7'b0100000);

assign o_alu_arith =
    (is_op || is_op_imm) &&
    (funct3 == 3'b101) &&
    (funct7 == 7'b0100000);

assign o_alu_unsigned =
    ((legal_op || legal_op_imm) && (funct3 == 3'b011)) ||
    (legal_branch && funct3[1]);

assign o_branch = legal_branch;
assign o_jump = is_jal || legal_jalr;
assign o_pc_sel = legal_jalr;

assign o_branch_equal =
    legal_branch && (funct3[2:1] == 2'b00);

assign o_branch_unsigned =
    legal_branch && (funct3[2:1] == 2'b11);

assign o_branch_invert = legal_branch && funct3[0];

// ---------- Memory controls ----------

wire memory_access =
    legal_load || legal_store || legal_flw || legal_fsw;

assign o_dmem_ren = legal_load || legal_flw;
assign o_dmem_wen = legal_store || legal_fsw;

assign o_dmem_memb =
    memory_access && (funct3[1:0] == 2'b00);

assign o_dmem_memh =
    memory_access && (funct3[1:0] == 2'b01);

assign o_dmem_memw =
    memory_access && (funct3[1:0] == 2'b10);

assign o_dmem_memu = legal_load && funct3[2];

assign o_dmem_align =
    o_dmem_memw ? 2'b11 :
    o_dmem_memh ? 2'b01 :
                  2'b00;

// ---------- Integer writeback selection ----------

// FP destinations use o_frd_en and their own writeback path.
assign o_rd_sel =
    !writes_integer
        ? 5'b00000 :
    is_lui
        ? 5'b00010 :
    (is_jal || legal_jalr)
        ? 5'b00100 :
    legal_load
        ? 5'b01000 :
    (fp_compare || fp_to_int ||
     fp_move_to_int || fp_class || legal_csr)
        ? 5'b10000 :
          5'b00001;

endmodule

`default_nettype wire