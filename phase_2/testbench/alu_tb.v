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

        //testing 5-8
    i_opsel = 3'b000;
    i_sub   = 1'b1;

    i_op1 = 32'd5;
    i_op2 = 32'd8;

    #10;

    $display("Result = %d", o_result);
    $finish;

end

endmodule

