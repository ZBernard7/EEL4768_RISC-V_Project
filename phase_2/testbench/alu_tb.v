`timescale 1ns/1ps

module alu_tb;

    reg [2:0]  i_opsel;
    reg        i_sub;
    reg        i_unsigned;
    reg        i_arith;
    reg [31:0] i_op1;
    reg [31:0] i_op2;

    wire [31:0] o_result;
    wire        o_eq;
    wire        o_slt;

    alu uut (
        .i_opsel(i_opsel),
        .i_sub(i_sub),
        .i_unsigned(i_unsigned),
        .i_arith(i_arith),
        .i_op1(i_op1),
        .i_op2(i_op2),
        .o_result(o_result),
        .o_eq(o_eq),
        .o_slt(o_slt)
    );

    initial begin

        // ADD
        i_opsel = 3'b000;
        i_sub = 0;
        i_op1 = 32'd5;
        i_op2 = 32'd3;
        #10;
        $display("ADD  5 + 3       = %0d", o_result);


        // SUB
        i_sub = 1;
        #10;
        $display("SUB  5 - 3       = %0d", o_result);


        // SLL
        i_opsel = 3'b001;
        i_sub = 0;
        i_op1 = 32'd3;
        i_op2 = 32'd2;
        #10;
        $display("SLL  3 << 2      = %0d", o_result);


        // SLT signed
        i_opsel = 3'b010;
        i_op1 = -32'sd5;
        i_op2 = 32'd3;
        #10;
        $display("SLT  -5 < 3      = %0d", o_result);


        // SLTU unsigned
        i_opsel = 3'b011;
        i_op1 = 32'd3;
        i_op2 = 32'd5;
        #10;
        $display("SLTU 3 < 5       = %0d", o_result);


        // XOR
        i_opsel = 3'b100;
        i_op1 = 32'hAAAA_AAAA;
        i_op2 = 32'h5555_5555;
        #10;
        $display("XOR  AAAAAAAA ^ 55555555 = %h", o_result);


        // SRL
        i_opsel = 3'b101;
        i_arith = 0;
        i_op1 = 32'd16;
        i_op2 = 32'd2;
        #10;
        $display("SRL  16 >> 2     = %0d", o_result);


        // SRA
        i_arith = 1;
        i_op1 = -32'sd16;
        i_op2 = 32'd2;
        #10;
        $display("SRA  -16 >> 2    = %0d", $signed(o_result));


        // OR
        i_opsel = 3'b110;
        i_op1 = 32'hAAAA_AAAA;
        i_op2 = 32'h5555_5555;
        #10;
        $display("OR   AAAAAAAA | 55555555 = %h", o_result);


        // AND
        i_opsel = 3'b111;
        #10;
        $display("AND  AAAAAAAA & 55555555 = %h", o_result);


        // Equality TRUE
        i_op1 = 32'd25;
        i_op2 = 32'd25;
        #10;
        $display("EQ   25 == 25    = %b", o_eq);


        // Equality FALSE
        i_op2 = 32'd30;
        #10;
        $display("EQ   25 == 30    = %b", o_eq);


        // Signed branch comparison
        i_unsigned = 0;
        i_op1 = -32'sd5;
        i_op2 = 32'd3;
        #10;
        $display("Signed   -5 < 3  = %b", o_slt);


        // Unsigned branch comparison
        i_unsigned = 1;
        i_op1 = 32'hFFFF_FFFF;
        i_op2 = 32'd1;
        #10;
        $display("Unsigned FFFFFFFF < 1 = %b", o_slt);


        $finish;

    end

endmodule