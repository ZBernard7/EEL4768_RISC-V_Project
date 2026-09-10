`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. This ALU is a purely combinational block, so
// you should not attempt to add any registers or pipeline it.
module alu (
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010: set less than
    // 3'b011: set less than unsigned
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is only used for branch comparisons, as the set less than unsigned
    // mode is already specified by `i_opsel`. For branch operations, the ALU
    // result is not used, only the comparison results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out (from addition) should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_eq,
    // Set less than result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_slt
);
    // Your implementation goes under here
    // ------------------------------------

    //Part 1 of Phase #2
        
    // 32-bit 2's-complement ADD/SUB w/ Carry Lookahead Adder


    // Addition: op2_modified = i_op2,so carry[0] = 0 (same as A+B)
    // Subtraction: op2_modified = ~i_op2,so carry[0] = 1 (same as A+1+~B)

    wire [31:0] op2_modified;
    assign op2_modified = i_op2 ^ {32{i_sub}};

    wire [31:0] gener;
    wire [31:0] propagate;

    assign gener  = i_op1 & op2_modified;
    assign propagate = i_op1 ^ op2_modified;
    wire [32:0] carry;
    assign carry[0] = i_sub;
// 8 groups of 4 bits,each group has its own CLA
    wire [7:0] group_generate;//i put the 32 bits into 8 groups (so basically 4 bits at a time)
    wire [7:0] group_propagate;
//bite 3:0
    assign group_propagate[0] =
        propagate[3] & propagate[2] & propagate[1] & propagate[0];
    assign group_generate[0] =
        gener[3] | (propagate[3] & gener[2]) | (propagate[3] & propagate[2] & gener[1]) |
        (propagate[3] & propagate[2] & propagate[1] & gener[0]);
//bits 7:4
    assign group_propagate[1] =
        propagate[7] & propagate[6] & propagate[5] & propagate[4];
    assign group_generate[1] =
        gener[7] | (propagate[7] & gener[6]) | (propagate[7] & propagate[6] & gener[5]) |
        (propagate[7] & propagate[6] & propagate[5] & gener[4]);
//bits 11:8
    assign group_propagate[2] =
        propagate[11] & propagate[10] & propagate[9] & propagate[8];
    assign group_generate[2] =
        gener[11] | (propagate[11] & gener[10]) | (propagate[11] & propagate[10] & gener[9]) |
        (propagate[11] & propagate[10] & propagate[9] & gener[8]);
//bit 15:12
    assign group_propagate[3] =
        propagate[15] & propagate[14] & propagate[13] & propagate[12];
    assign group_generate[3] =
        gener[15] | (propagate[15] & gener[14]) | (propagate[15] & propagate[14] & gener[13]) |
        (propagate[15] & propagate[14] & propagate[13] & gener[12]);
// 19:16
    assign group_propagate[4] =
        propagate[19] & propagate[18] & propagate[17] & propagate[16];
    assign group_generate[4] =
        gener[19] | (propagate[19] & gener[18]) | (propagate[19] & propagate[18] & gener[17]) |
        (propagate[19] & propagate[18] & propagate[17] & gener[16]);
//bit 23:20
    assign group_propagate[5] =
        propagate[23] & propagate[22] & propagate[21] & propagate[20];
    assign group_generate[5] =
        gener[23] | (propagate[23] & gener[22]) | (propagate[23] & propagate[22] & gener[21]) |
        (propagate[23] & propagate[22] & propagate[21] & gener[20]);
//bits: 27:24
    assign group_propagate[6] =
    propagate[27] & propagate[26] & propagate[25] & propagate[24];
    assign group_generate[6] =
        gener[27] | (propagate[27] & gener[26]) | (propagate[27] & propagate[26] & gener[25]) |
        (propagate[27] & propagate[26] & propagate[25] & gener[24]);
//bits: 31:28
    assign group_propagate[7] =
        propagate[31] & propagate[30] & propagate[29] & propagate[28];
    assign group_generate[7] =
        gener[31] | (propagate[31] & gener[30]) | (propagate[31] & propagate[30] & gener[29]) |
        (propagate[31] & propagate[30] & propagate[29] & gener[28]);


//Lookahead for the groups, the carry being assigned is going to the next group
    //PROPAGATE MEANS PASS A CARRY THROUGH

    assign carry[4] =
        group_generate[0] | (group_propagate[0] & carry[0]);
    
    assign carry[8] =
        group_generate[1] | (group_propagate[1] & group_generate[0]) |
        (group_propagate[1] & group_propagate[0] & carry[0]);
//carry[8] is coming out of group 1
    assign carry[12] =
        group_generate[2] | (group_propagate[2] & group_generate[1]) |
        (group_propagate[2] & group_propagate[1] & group_generate[0]) |
        (group_propagate[2] & group_propagate[1] &
         group_propagate[0] & carry[0]);

    assign carry[16] =
        group_generate[3] |
        (group_propagate[3] & group_generate[2]) |
        (group_propagate[3] & group_propagate[2] & group_generate[1]) |
        (group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_generate[0]) |
        (group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_propagate[0] & carry[0]);

    assign carry[20] =
        group_generate[4] |
        (group_propagate[4] & group_generate[3]) |
        (group_propagate[4] & group_propagate[3] & group_generate[2]) |
        (group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_generate[1]) |
        (group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_propagate[1] & group_generate[0]) |
        (group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_propagate[1] &
         group_propagate[0] & carry[0]);

    assign carry[24] =
        group_generate[5] |
        (group_propagate[5] & group_generate[4]) |
        (group_propagate[5] & group_propagate[4] & group_generate[3]) |
        (group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_generate[2]) |
        (group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] & group_generate[1]) |
        (group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_generate[0]) |
        (group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_propagate[0] & carry[0]);

    assign carry[28] =
        group_generate[6] |
        (group_propagate[6] & group_generate[5]) |
        (group_propagate[6] & group_propagate[5] & group_generate[4]) |
        (group_propagate[6] & group_propagate[5] &
         group_propagate[4] & group_generate[3]) |
        (group_propagate[6] & group_propagate[5] &
         group_propagate[4] & group_propagate[3] & group_generate[2]) |
        (group_propagate[6] & group_propagate[5] &
         group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_generate[1]) |
        (group_propagate[6] & group_propagate[5] &
         group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_propagate[1] &
         group_generate[0]) |
        (group_propagate[6] & group_propagate[5] &
         group_propagate[4] & group_propagate[3] &
         group_propagate[2] & group_propagate[1] &
         group_propagate[0] & carry[0]);

    assign carry[32] =
        group_generate[7] |
        (group_propagate[7] & group_generate[6]) |
        (group_propagate[7] & group_propagate[6] & group_generate[5]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_generate[4]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_propagate[4] & group_generate[3]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_generate[2]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] &
         group_generate[1]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_generate[0]) |
        (group_propagate[7] & group_propagate[6] &
         group_propagate[5] & group_propagate[4] &
         group_propagate[3] & group_propagate[2] &
         group_propagate[1] & group_propagate[0] & carry[0]);

    assign carry[1] =
        gener[0] |
        (propagate[0] & carry[0]);

    assign carry[2] =
        gener[1] |
        (propagate[1] & gener[0]) |
        (propagate[1] & propagate[0] & carry[0]);

    assign carry[3] =
        gener[2] |
        (propagate[2] & gener[1]) |
        (propagate[2] & propagate[1] & gener[0]) |
        (propagate[2] & propagate[1] &
         propagate[0] & carry[0]);

    assign carry[5] =
        gener[4] |
        (propagate[4] & carry[4]);

    assign carry[6] =
        gener[5] |
        (propagate[5] & gener[4]) |
        (propagate[5] & propagate[4] & carry[4]);

    assign carry[7] =
        gener[6] |
        (propagate[6] & gener[5]) |
        (propagate[6] & propagate[5] & gener[4]) |
        (propagate[6] & propagate[5] &
         propagate[4] & carry[4]);

    assign carry[9] =
        gener[8] |
        (propagate[8] & carry[8]);

    assign carry[10] =
        gener[9] |
        (propagate[9] & gener[8]) |
        (propagate[9] & propagate[8] & carry[8]);

    assign carry[11] =
        gener[10] |
        (propagate[10] & gener[9]) |
        (propagate[10] & propagate[9] & gener[8]) |
        (propagate[10] & propagate[9] &
         propagate[8] & carry[8]);

    assign carry[13] =
        gener[12] |
        (propagate[12] & carry[12]);

    assign carry[14] =
        gener[13] |
        (propagate[13] & gener[12]) |
        (propagate[13] & propagate[12] & carry[12]);

    assign carry[15] =
        gener[14] |
        (propagate[14] & gener[13]) |
        (propagate[14] & propagate[13] & gener[12]) |
        (propagate[14] & propagate[13] &
         propagate[12] & carry[12]);

    assign carry[17] =
        gener[16] |
        (propagate[16] & carry[16]);

    assign carry[18] =
        gener[17] |
        (propagate[17] & gener[16]) |
        (propagate[17] & propagate[16] & carry[16]);

    assign carry[19] =
        gener[18] |
        (propagate[18] & gener[17]) |
        (propagate[18] & propagate[17] & gener[16]) |
        (propagate[18] & propagate[17] &
         propagate[16] & carry[16]);

    assign carry[21] =
        gener[20] |
        (propagate[20] & carry[20]);

    assign carry[22] =
        gener[21] |
        (propagate[21] & gener[20]) |
        (propagate[21] & propagate[20] & carry[20]);

    assign carry[23] =
        gener[22] |
        (propagate[22] & gener[21]) |
        (propagate[22] & propagate[21] & gener[20]) |
        (propagate[22] & propagate[21] &
         propagate[20] & carry[20]);

    assign carry[25] =
        gener[24] |
        (propagate[24] & carry[24]);

    assign carry[26] =
        gener[25] |
        (propagate[25] & gener[24]) |
        (propagate[25] & propagate[24] & carry[24]);

    assign carry[27] =
        gener[26] |
        (propagate[26] & gener[25]) |
        (propagate[26] & propagate[25] & gener[24]) |
        (propagate[26] & propagate[25] &
         propagate[24] & carry[24]);

    assign carry[29] =
        gener[28] |
        (propagate[28] & carry[28]);

    assign carry[30] =
        gener[29] |
        (propagate[29] & gener[28]) |
        (propagate[29] & propagate[28] & carry[28]);

    assign carry[31] =
        gener[30] |
        (propagate[30] & gener[29]) |
        (propagate[30] & propagate[29] & gener[28]) |
        (propagate[30] & propagate[29] &
         propagate[28] & carry[28]);

    wire [31:0] add_sub_result;

    assign add_sub_result = propagate ^ carry[31:0];

    wire [31:0] sll_stage1;
    wire [31:0] sll_stage2;
    wire [31:0] sll_stage4;
    wire [31:0] sll_stage8;
    wire [31:0] sll_result;

    wire [31:0] srl_stage1;
    wire [31:0] srl_stage2;
    wire [31:0] srl_stage4;
    wire [31:0] srl_stage8;
    wire [31:0] srl_result;

    wire [31:0] bit_equal;
    wire [32:0] unsigned_less;
    wire signed_less;

    wire [31:0] slt_result;
    wire [31:0] sltu_result;
    wire [31:0] xor_result;
    wire [31:0] or_result;
    wire [31:0] and_result;

    assign sll_stage1 =
        i_op2[0] ? {i_op1[30:0], 1'b0} : i_op1;

    assign sll_stage2 =
        i_op2[1] ? {sll_stage1[29:0], 2'b00} : sll_stage1;

    assign sll_stage4 =
        i_op2[2] ? {sll_stage2[27:0], 4'b0000} : sll_stage2;

    assign sll_stage8 =
        i_op2[3] ? {sll_stage4[23:0], 8'b00000000} : sll_stage4;

    assign sll_result =
        i_op2[4] ? {sll_stage8[15:0], 16'b0000000000000000} : sll_stage8;

    assign bit_equal[31] = ~(i_op1[31] ^ i_op2[31]);
    assign bit_equal[30] = ~(i_op1[30] ^ i_op2[30]);
    assign bit_equal[29] = ~(i_op1[29] ^ i_op2[29]);
    assign bit_equal[28] = ~(i_op1[28] ^ i_op2[28]);
    assign bit_equal[27] = ~(i_op1[27] ^ i_op2[27]);
    assign bit_equal[26] = ~(i_op1[26] ^ i_op2[26]);
    assign bit_equal[25] = ~(i_op1[25] ^ i_op2[25]);
    assign bit_equal[24] = ~(i_op1[24] ^ i_op2[24]);
    assign bit_equal[23] = ~(i_op1[23] ^ i_op2[23]);
    assign bit_equal[22] = ~(i_op1[22] ^ i_op2[22]);
    assign bit_equal[21] = ~(i_op1[21] ^ i_op2[21]);
    assign bit_equal[20] = ~(i_op1[20] ^ i_op2[20]);
    assign bit_equal[19] = ~(i_op1[19] ^ i_op2[19]);
    assign bit_equal[18] = ~(i_op1[18] ^ i_op2[18]);
    assign bit_equal[17] = ~(i_op1[17] ^ i_op2[17]);
    assign bit_equal[16] = ~(i_op1[16] ^ i_op2[16]);
    assign bit_equal[15] = ~(i_op1[15] ^ i_op2[15]);
    assign bit_equal[14] = ~(i_op1[14] ^ i_op2[14]);
    assign bit_equal[13] = ~(i_op1[13] ^ i_op2[13]);
    assign bit_equal[12] = ~(i_op1[12] ^ i_op2[12]);
    assign bit_equal[11] = ~(i_op1[11] ^ i_op2[11]);
    assign bit_equal[10] = ~(i_op1[10] ^ i_op2[10]);
    assign bit_equal[9]  = ~(i_op1[9]  ^ i_op2[9]);
    assign bit_equal[8]  = ~(i_op1[8]  ^ i_op2[8]);
    assign bit_equal[7]  = ~(i_op1[7]  ^ i_op2[7]);
    assign bit_equal[6]  = ~(i_op1[6]  ^ i_op2[6]);
    assign bit_equal[5]  = ~(i_op1[5]  ^ i_op2[5]);
    assign bit_equal[4]  = ~(i_op1[4]  ^ i_op2[4]);
    assign bit_equal[3]  = ~(i_op1[3]  ^ i_op2[3]);
    assign bit_equal[2]  = ~(i_op1[2]  ^ i_op2[2]);
    assign bit_equal[1]  = ~(i_op1[1]  ^ i_op2[1]);
    assign bit_equal[0]  = ~(i_op1[0]  ^ i_op2[0]);

    // eq_chain[k] means "bits 31 downto k are all equal between i_op1 and i_op2".
    // This is needed because a lower-order bit is only allowed to decide the
    // comparison if every bit above it (all the way up to bit 31) was equal --
    // a single adjacent bit_equal[k] is not enough to know that.
    wire [32:0] eq_chain;
    assign eq_chain[32] = 1'b1;
    assign eq_chain[31] = bit_equal[31];
    assign eq_chain[30] = bit_equal[30] & eq_chain[31];
    assign eq_chain[29] = bit_equal[29] & eq_chain[30];
    assign eq_chain[28] = bit_equal[28] & eq_chain[29];
    assign eq_chain[27] = bit_equal[27] & eq_chain[28];
    assign eq_chain[26] = bit_equal[26] & eq_chain[27];
    assign eq_chain[25] = bit_equal[25] & eq_chain[26];
    assign eq_chain[24] = bit_equal[24] & eq_chain[25];
    assign eq_chain[23] = bit_equal[23] & eq_chain[24];
    assign eq_chain[22] = bit_equal[22] & eq_chain[23];
    assign eq_chain[21] = bit_equal[21] & eq_chain[22];
    assign eq_chain[20] = bit_equal[20] & eq_chain[21];
    assign eq_chain[19] = bit_equal[19] & eq_chain[20];
    assign eq_chain[18] = bit_equal[18] & eq_chain[19];
    assign eq_chain[17] = bit_equal[17] & eq_chain[18];
    assign eq_chain[16] = bit_equal[16] & eq_chain[17];
    assign eq_chain[15] = bit_equal[15] & eq_chain[16];
    assign eq_chain[14] = bit_equal[14] & eq_chain[15];
    assign eq_chain[13] = bit_equal[13] & eq_chain[14];
    assign eq_chain[12] = bit_equal[12] & eq_chain[13];
    assign eq_chain[11] = bit_equal[11] & eq_chain[12];
    assign eq_chain[10] = bit_equal[10] & eq_chain[11];
    assign eq_chain[9]  = bit_equal[9]  & eq_chain[10];
    assign eq_chain[8]  = bit_equal[8]  & eq_chain[9];
    assign eq_chain[7]  = bit_equal[7]  & eq_chain[8];
    assign eq_chain[6]  = bit_equal[6]  & eq_chain[7];
    assign eq_chain[5]  = bit_equal[5]  & eq_chain[6];
    assign eq_chain[4]  = bit_equal[4]  & eq_chain[5];
    assign eq_chain[3]  = bit_equal[3]  & eq_chain[4];
    assign eq_chain[2]  = bit_equal[2]  & eq_chain[3];
    assign eq_chain[1]  = bit_equal[1]  & eq_chain[2];

    // unsigned_less[k] = "considering bits 31 downto k, is i_op1 < i_op2?"
    // Once a decision is made at some higher bit, it must stick regardless
    // of what any lower bit looks like on its own -- so a lower bit is only
    // allowed to make a *new* decision when everything above it tied
    // (eq_chain[k+1]).
    assign unsigned_less[32] = 1'b0;

    assign unsigned_less[31] =
        (~i_op1[31] & i_op2[31]);

    assign unsigned_less[30] =
        unsigned_less[31] |
        (eq_chain[31] & (~i_op1[30] & i_op2[30]));

    assign unsigned_less[29] =
        unsigned_less[30] |
        (eq_chain[30] & (~i_op1[29] & i_op2[29]));

    assign unsigned_less[28] =
        unsigned_less[29] |
        (eq_chain[29] & (~i_op1[28] & i_op2[28]));

    assign unsigned_less[27] =
        unsigned_less[28] |
        (eq_chain[28] & (~i_op1[27] & i_op2[27]));

    assign unsigned_less[26] =
        unsigned_less[27] |
        (eq_chain[27] & (~i_op1[26] & i_op2[26]));

    assign unsigned_less[25] =
        unsigned_less[26] |
        (eq_chain[26] & (~i_op1[25] & i_op2[25]));

    assign unsigned_less[24] =
        unsigned_less[25] |
        (eq_chain[25] & (~i_op1[24] & i_op2[24]));

    assign unsigned_less[23] =
        unsigned_less[24] |
        (eq_chain[24] & (~i_op1[23] & i_op2[23]));

    assign unsigned_less[22] =
        unsigned_less[23] |
        (eq_chain[23] & (~i_op1[22] & i_op2[22]));

    assign unsigned_less[21] =
        unsigned_less[22] |
        (eq_chain[22] & (~i_op1[21] & i_op2[21]));

    assign unsigned_less[20] =
        unsigned_less[21] |
        (eq_chain[21] & (~i_op1[20] & i_op2[20]));

    assign unsigned_less[19] =
        unsigned_less[20] |
        (eq_chain[20] & (~i_op1[19] & i_op2[19]));

    assign unsigned_less[18] =
        unsigned_less[19] |
        (eq_chain[19] & (~i_op1[18] & i_op2[18]));

    assign unsigned_less[17] =
        unsigned_less[18] |
        (eq_chain[18] & (~i_op1[17] & i_op2[17]));

    assign unsigned_less[16] =
        unsigned_less[17] |
        (eq_chain[17] & (~i_op1[16] & i_op2[16]));

    assign unsigned_less[15] =
        unsigned_less[16] |
        (eq_chain[16] & (~i_op1[15] & i_op2[15]));

    assign unsigned_less[14] =
        unsigned_less[15] |
        (eq_chain[15] & (~i_op1[14] & i_op2[14]));

    assign unsigned_less[13] =
        unsigned_less[14] |
        (eq_chain[14] & (~i_op1[13] & i_op2[13]));

    assign unsigned_less[12] =
        unsigned_less[13] |
        (eq_chain[13] & (~i_op1[12] & i_op2[12]));

    assign unsigned_less[11] =
        unsigned_less[12] |
        (eq_chain[12] & (~i_op1[11] & i_op2[11]));

    assign unsigned_less[10] =
        unsigned_less[11] |
        (eq_chain[11] & (~i_op1[10] & i_op2[10]));

    assign unsigned_less[9] =
        unsigned_less[10] |
        (eq_chain[10] & (~i_op1[9] & i_op2[9]));

    assign unsigned_less[8] =
        unsigned_less[9] |
        (eq_chain[9] & (~i_op1[8] & i_op2[8]));

    assign unsigned_less[7] =
        unsigned_less[8] |
        (eq_chain[8] & (~i_op1[7] & i_op2[7]));

    assign unsigned_less[6] =
        unsigned_less[7] |
        (eq_chain[7] & (~i_op1[6] & i_op2[6]));

    assign unsigned_less[5] =
        unsigned_less[6] |
        (eq_chain[6] & (~i_op1[5] & i_op2[5]));

    assign unsigned_less[4] =
        unsigned_less[5] |
        (eq_chain[5] & (~i_op1[4] & i_op2[4]));

    assign unsigned_less[3] =
        unsigned_less[4] |
        (eq_chain[4] & (~i_op1[3] & i_op2[3]));

    assign unsigned_less[2] =
        unsigned_less[3] |
        (eq_chain[3] & (~i_op1[2] & i_op2[2]));

    assign unsigned_less[1] =
        unsigned_less[2] |
        (eq_chain[2] & (~i_op1[1] & i_op2[1]));

    assign unsigned_less[0] =
        unsigned_less[1] |
        (eq_chain[1] & (~i_op1[0] & i_op2[0]));

    assign sltu_result = {31'b0, unsigned_less[0]};

    assign signed_less =
        (i_op1[31] & ~i_op2[31]) |
        ((~(i_op1[31] ^ i_op2[31])) & unsigned_less[0]);

    assign slt_result = {31'b0, signed_less};

    assign xor_result = i_op1 ^ i_op2;

    assign or_result  = i_op1 | i_op2;

    assign and_result = i_op1 & i_op2;

    assign srl_stage1 =
        i_op2[0]
        ? {{1{i_arith ? i_op1[31] : 1'b0}}, i_op1[31:1]}
        : i_op1;

    assign srl_stage2 =
        i_op2[1]
        ? {{2{i_arith ? i_op1[31] : 1'b0}}, srl_stage1[31:2]}
        : srl_stage1;

    assign srl_stage4 =
        i_op2[2]
        ? {{4{i_arith ? i_op1[31] : 1'b0}}, srl_stage2[31:4]}
        : srl_stage2;

    assign srl_stage8 =
        i_op2[3]
        ? {{8{i_arith ? i_op1[31] : 1'b0}}, srl_stage4[31:8]}
        : srl_stage4;

    assign srl_result =
        i_op2[4]
        ? {{16{i_arith ? i_op1[31] : 1'b0}}, srl_stage8[31:16]}
        : srl_stage8;

    assign o_result =
        (i_opsel == 3'b000) ? add_sub_result :
        (i_opsel == 3'b001) ? sll_result :
        (i_opsel == 3'b010) ? slt_result :
        (i_opsel == 3'b011) ? sltu_result :
        (i_opsel == 3'b100) ? xor_result :
        (i_opsel == 3'b101) ? srl_result :
        (i_opsel == 3'b110) ? or_result :
                               and_result;

    assign o_eq = (i_op1 == i_op2);

    assign o_slt =
        i_unsigned ? unsigned_less[0] : signed_less;

endmodule

`default_nettype wire
