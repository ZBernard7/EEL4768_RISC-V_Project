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


    wire [31:0] gener; //gener creats a carry-out on its own
    wire [31:0] propagate; //propagate carrys whats generated to next

    assign gener  = i_op1 & op2_modified;
    assign propagate = i_op1 ^ op2_modified;
    wire [32:0] carry;
    assign carry[0] = i_sub;

    // 8 groups of 4 bits,each group has its own CLA

    wire [7:0] group_generate;//i put the 32 bits into 8 groups (so basically 4 bits at a time)
    wire [7:0] group_propagate;

    //bits 3:0
    assign group_propagate[0] =
        propagate[3] & propagate[2] & propagate[1] & propagate[0];
    //for this part since the last bit (bit3) can gener a carry itself, im just &ing
    //each generated bit after it and propagating those bits. This is literlaly a carry equation just expanded
    assign group_generate[0] =
        gener[3] | (propagate[3] & gener[2]) | (propagate[3] & propagate[2] & gener[1]) |
        (propagate[3] & propagate[2] & propagate[1] & gener[0]);

    //bits 7:4
    assign group_propagate[1] =
        propagate[7] & propagate[6] & propagate[5] & propagate[4];
    assign group_generate[1] =
        gener[7] | (propagate[7] & gener[6]) | (propagate[7] & propagate[6] & gener[5]) |
        (propagate[7] & propagate[6] & propagate[5] & gener[4]);

    // bits 11:8
    assign group_propagate[2] =
        propagate[11] & propagate[10] & propagate[9] & propagate[8];
    assign group_generate[2] =
        gener[11] | (propagate[11] & gener[10]) | (propagate[11] & propagate[10] & gener[9]) |
        (propagate[11] & propagate[10] & propagate[9] & gener[8]);

    //bits 15:12
    assign group_propagate[3] =
        propagate[15] & propagate[14] & propagate[13] & propagate[12];
    assign group_generate[3] =
        gener[15] | (propagate[15] & gener[14]) | (propagate[15] & propagate[14] & gener[13]) |
        (propagate[15] & propagate[14] & propagate[13] & gener[12]);

    //bits 19:16
    assign group_propagate[4] =
        propagate[19] & propagate[18] & propagate[17] & propagate[16];
    assign group_generate[4] =
        gener[19] | (propagate[19] & gener[18]) | (propagate[19] & propagate[18] & gener[17]) | 
        (propagate[19] & propagate[18] & propagate[17] & gener[16]);

    // bits 23:20
    assign group_propagate[5] =
        propagate[23] & propagate[22] & propagate[21] & propagate[20];
    assign group_generate[5] =
        gener[23] | (propagate[23] & gener[22]) | (propagate[23] & propagate[22] & gener[21]) |
        (propagate[23] & propagate[22] & propagate[21] & gener[20]);

    // bits 27:24
    assign group_propagate[6] = 
    propagate[27] & propagate[26] & propagate[25] & propagate[24];
    assign group_generate[6] =
        gener[27] | (propagate[27] & gener[26]) | (propagate[27] & propagate[26] & gener[25]) |
        (propagate[27] & propagate[26] & propagate[25] & gener[24]);

    // bits 31:28
    assign group_propagate[7] =
        propagate[31] & propagate[30] & propagate[29] & propagate[28];
    assign group_generate[7] =
        gener[31] | (propagate[31] & gener[30]) | (propagate[31] & propagate[30] & gener[29]) |
        (propagate[31] & propagate[30] & propagate[29] & gener[28]);


    //Lookahead for the groups, the carry being assigned is going to the next group
    //PROPAGATE MEANS PASS A CARRY THROUGH
    assign carry[4] =
        group_generate[0] | (group_propagate[0] & carry[0]);
//carry[8] is coming out of group 1
    assign carry[8] =
        group_generate[1] | (group_propagate[1] & group_generate[0]) |
        (group_propagate[1] & group_propagate[0] & carry[0]);

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


    // Lookahead carries INSIDE each 4-bit group

    // Group 0
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


    // Group 1
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


    // Group 2
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


    // Group 3
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


    // Group 4
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


    // Group 5
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


    // Group 6
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


    // Group 7
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


    // ------------------------------------------------------------
    // Sum
    // ------------------------------------------------------------

    wire [31:0] add_sub_result;

    assign add_sub_result = propagate ^ carry[31:0];


    // For now, this sends the ADD/SUB result directly to the output.
    // Later, this will be replaced by the i_opsel result selection.
    assign o_result = add_sub_result;

endmodule

`default_nettype wire
