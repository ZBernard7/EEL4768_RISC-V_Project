`timescale 1ns/1ps

module alu_tb;


// ------------------------------------------------------------
// DUT inputs
// ------------------------------------------------------------

reg  [2:0]  i_opsel;
reg         i_sub;
reg         i_unsigned;
reg         i_arith;
reg  [31:0] i_op1;
reg  [31:0] i_op2;

// DUT outputs
wire [31:0] o_result;
wire        o_eq;
wire        o_slt;

// ------------------------------------------------------------
// Golden model outputs
// ------------------------------------------------------------

reg [31:0] expected_result;
reg        expected_eq;
reg        expected_slt;

// ------------------------------------------------------------
// Test counters
// ------------------------------------------------------------

integer total_tests;
integer passed_tests;
integer failed_tests;

integer i;
integer j;

// ------------------------------------------------------------
// Instantiate the ALU
// ------------------------------------------------------------

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

// ------------------------------------------------------------
// Golden model
//
// This model intentionally uses normal Verilog operators.
// The restrictions on +, -, <<, >>, etc. apply to the ALU,
// not this independent reference model.
// ------------------------------------------------------------

task calculate_expected;
    begin

        // Equality is always checked.
        expected_eq = (i_op1 == i_op2);

        // ----------------------------------------------------
        // SLT comparison
        //
        // i_unsigned = 0:
        //     signed comparison
        //
        // i_unsigned = 1:
        //     unsigned comparison
        // ----------------------------------------------------

        if (i_unsigned)
            expected_slt = (i_op1 < i_op2);
        else
            expected_slt = ($signed(i_op1) < $signed(i_op2));

        // ----------------------------------------------------
        // Operation result
        // ----------------------------------------------------

        case (i_opsel)

            // ADD / SUB
            3'b000: begin
                if (i_sub)
                    expected_result = i_op1 - i_op2;
                else
                    expected_result = i_op1 + i_op2;
            end

            // SLL
            3'b001: begin
                expected_result = i_op1 << i_op2[4:0];
            end

            // SLT signed
            3'b010: begin
                expected_result = {31'b0,
                                   ($signed(i_op1) < $signed(i_op2))};
            end

            // SLTU unsigned
            3'b011: begin
                expected_result = {31'b0,
                                   (i_op1 < i_op2)};
            end

            // XOR
            3'b100: begin
                expected_result = i_op1 ^ i_op2;
            end

            // SRL / SRA
            3'b101: begin
                if (i_arith)
                    expected_result =
                        $signed(i_op1) >>> i_op2[4:0];
                else
                    expected_result =
                        i_op1 >> i_op2[4:0];
            end

            // OR
            3'b110: begin
                expected_result = i_op1 | i_op2;
            end

            // AND
            3'b111: begin
                expected_result = i_op1 & i_op2;
            end

            default: begin
                expected_result = 32'b0;
            end

        endcase

    end
endtask

// ------------------------------------------------------------
// Check current vector against the golden model
// ------------------------------------------------------------

task check_result;
    begin

        total_tests = total_tests + 1;

        calculate_expected;

        #1;

        if ((o_result === expected_result) &&
            (o_eq     === expected_eq)     &&
            (o_slt    === expected_slt)) begin

            passed_tests = passed_tests + 1;

        end
        else begin

            failed_tests = failed_tests + 1;

            $display("");
            $display("====================================================");
            $display("FAILURE - Test %0d", total_tests);
            $display("====================================================");

            $display("Inputs:");
            $display("  i_opsel     = %03b", i_opsel);
            $display("  i_sub       = %b",   i_sub);
            $display("  i_unsigned  = %b",   i_unsigned);
            $display("  i_arith     = %b",   i_arith);
            $display("  i_op1       = 0x%08h", i_op1);
            $display("  i_op2       = 0x%08h", i_op2);

            $display("");
            $display("Expected:");
            $display("  result      = 0x%08h", expected_result);
            $display("  eq          = %b", expected_eq);
            $display("  slt         = %b", expected_slt);

            $display("");
            $display("Actual:");
            $display("  result      = 0x%08h", o_result);
            $display("  eq          = %b", o_eq);
            $display("  slt         = %b", o_slt);

            $display("====================================================");
            $display("");

        end

    end
endtask

// ------------------------------------------------------------
// Apply a vector
// ------------------------------------------------------------

task apply_vector;
    input [2:0]  opsel;
    input        sub;
    input        unsigned_compare;
    input        arithmetic_shift;
    input [31:0] op1;
    input [31:0] op2;

    begin

        i_opsel    = opsel;
        i_sub      = sub;
        i_unsigned = unsigned_compare;
        i_arith    = arithmetic_shift;
        i_op1      = op1;
        i_op2      = op2;

        check_result;

    end
endtask

// ------------------------------------------------------------
// Test
// ------------------------------------------------------------

initial begin

    // --------------------------------------------------------
    // Initialize counters
    // --------------------------------------------------------

    total_tests  = 0;
    passed_tests = 0;
    failed_tests = 0;

    i_opsel    = 3'b000;
    i_sub      = 1'b0;
    i_unsigned = 1'b0;
    i_arith    = 1'b0;
    i_op1      = 32'b0;
    i_op2      = 32'b0;

    #1;

    $display("");
    $display("====================================================");
    $display("          RISC-V ALU RANDOMIZED TESTBENCH");
    $display("====================================================");
    $display("");

    // ========================================================
    // TARGETED EDGE CASE TESTS
    // ========================================================

    $display("Running targeted edge-case tests...");

    // --------------------------------------------------------
    // ADD / SUB
    // --------------------------------------------------------

    apply_vector(3'b000, 1'b0, 1'b0, 1'b0,
                 32'h00000000, 32'h00000000);

    apply_vector(3'b000, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'h00000001);

    apply_vector(3'b000, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h00000001);

    apply_vector(3'b000, 1'b0, 1'b0, 1'b0,
                 32'h7FFFFFFF, 32'h00000001);

    apply_vector(3'b000, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h80000000);

    apply_vector(3'b000, 1'b1, 1'b0, 1'b0,
                 32'h00000005, 32'h00000003);

    apply_vector(3'b000, 1'b1, 1'b0, 1'b0,
                 32'h00000003, 32'h00000005);

    apply_vector(3'b000, 1'b1, 1'b0, 1'b0,
                 32'h80000000, 32'h00000001);

    apply_vector(3'b000, 1'b1, 1'b0, 1'b0,
                 32'h00000000, 32'h00000001);

    // --------------------------------------------------------
    // SLL
    // --------------------------------------------------------

    apply_vector(3'b001, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'h00000000);

    apply_vector(3'b001, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'h00000001);

    apply_vector(3'b001, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'h0000001F);

    apply_vector(3'b001, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h00000010);

    apply_vector(3'b001, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h00000001);

    // --------------------------------------------------------
    // SLT signed
    // --------------------------------------------------------

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h00000001);

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'hFFFFFFFF);

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h7FFFFFFF);

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'h7FFFFFFF, 32'h80000000);

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h80000000);

    apply_vector(3'b010, 1'b0, 1'b0, 1'b0,
                 32'h7FFFFFFF, 32'h7FFFFFFF);

    // --------------------------------------------------------
    // SLTU unsigned
    // --------------------------------------------------------

    apply_vector(3'b011, 1'b0, 1'b0, 1'b0,
                 32'h00000000, 32'hFFFFFFFF);

    apply_vector(3'b011, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h00000000);

    apply_vector(3'b011, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h7FFFFFFF);

    apply_vector(3'b011, 1'b0, 1'b0, 1'b0,
                 32'h00000001, 32'h00000001);

    // --------------------------------------------------------
    // XOR
    // --------------------------------------------------------

    apply_vector(3'b100, 1'b0, 1'b0, 1'b0,
                 32'hAAAAAAAA, 32'h55555555);

    apply_vector(3'b100, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'hFFFFFFFF);

    apply_vector(3'b100, 1'b0, 1'b0, 1'b0,
                 32'h00000000, 32'hFFFFFFFF);

    // --------------------------------------------------------
    // SRL
    // --------------------------------------------------------

    apply_vector(3'b101, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h00000001);

    apply_vector(3'b101, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h00000010);

    apply_vector(3'b101, 1'b0, 1'b0, 1'b0,
                 32'h80000000, 32'h0000001F);

    // --------------------------------------------------------
    // SRA
    // --------------------------------------------------------

    apply_vector(3'b101, 1'b0, 1'b0, 1'b1,
                 32'h80000000, 32'h00000001);

    apply_vector(3'b101, 1'b0, 1'b0, 1'b1,
                 32'hFFFFFFFF, 32'h00000001);

    apply_vector(3'b101, 1'b0, 1'b0, 1'b1,
                 32'h80000000, 32'h00000010);

    apply_vector(3'b101, 1'b0, 1'b0, 1'b1,
                 32'h80000000, 32'h0000001F);

    // --------------------------------------------------------
    // OR
    // --------------------------------------------------------

    apply_vector(3'b110, 1'b0, 1'b0, 1'b0,
                 32'hAAAAAAAA, 32'h55555555);

    apply_vector(3'b110, 1'b0, 1'b0, 1'b0,
                 32'h00000000, 32'h00000000);

    // --------------------------------------------------------
    // AND
    // --------------------------------------------------------

    apply_vector(3'b111, 1'b0, 1'b0, 1'b0,
                 32'hAAAAAAAA, 32'h55555555);

    apply_vector(3'b111, 1'b0, 1'b0, 1'b0,
                 32'hFFFFFFFF, 32'h55555555);

    // --------------------------------------------------------
    // Equality
    // --------------------------------------------------------

    apply_vector(3'b100, 1'b0, 1'b0, 1'b0,
                 32'h12345678, 32'h12345678);

    apply_vector(3'b100, 1'b0, 1'b0, 1'b0,
                 32'h12345678, 32'h12345679);

    // ========================================================
    // RANDOMIZED TESTING
    // ========================================================

    $display("Running randomized tests...");

    // --------------------------------------------------------
    // Random tests for every operation.
    //
    // Each operation gets 5000 random vectors.
    // 8 operations x 5000 = 40,000 random tests.
    // --------------------------------------------------------

    for (i = 0; i < 8; i = i + 1) begin

        for (j = 0; j < 5000; j = j + 1) begin

            i_opsel    = i[2:0];
            i_sub      = $random;
            i_unsigned = $random;
            i_arith    = $random;
            i_op1      = $random;
            i_op2      = $random;

            check_result;

        end

    end

    // ========================================================
    // ADDITION/SUBTRACTION DIRECTED RANDOM TESTS
    // ========================================================

    $display("Running additional ADD/SUB stress tests...");

    for (j = 0; j < 5000; j = j + 1) begin

        i_opsel    = 3'b000;
        i_sub      = $random;
        i_unsigned = $random;
        i_arith    = $random;
        i_op1      = $random;
        i_op2      = $random;

        check_result;

    end

    // ========================================================
    // SHIFT STRESS TESTS
    //
    // Explicitly emphasize every possible shift amount.
    // ========================================================

    $display("Running shift stress tests...");

    for (j = 0; j < 32; j = j + 1) begin

        // SLL
        i_opsel    = 3'b001;
        i_sub      = 1'b0;
        i_unsigned = 1'b0;
        i_arith    = 1'b0;
        i_op1      = $random;
        i_op2      = j;

        check_result;

        // SRL
        i_opsel    = 3'b101;
        i_arith    = 1'b0;
        i_op1      = $random;
        i_op2      = j;

        check_result;

        // SRA
        i_opsel    = 3'b101;
        i_arith    = 1'b1;
        i_op1      = $random;
        i_op2      = j;

        check_result;

    end

    // ========================================================
    // COMPARATOR STRESS TESTS
    // ========================================================

    $display("Running comparator stress tests...");

    for (j = 0; j < 5000; j = j + 1) begin

        i_op1 = $random;
        i_op2 = $random;

        // Signed SLT
        i_opsel    = 3'b010;
        i_sub      = 1'b0;
        i_unsigned = 1'b0;
        i_arith    = 1'b0;

        check_result;

        // Unsigned SLTU
        i_opsel    = 3'b011;
        i_unsigned = 1'b1;

        check_result;

        // Branch comparison: signed
        i_opsel    = 3'b000;
        i_unsigned = 1'b0;

        check_result;

        // Branch comparison: unsigned
        i_unsigned = 1'b1;

        check_result;

    end

    // ========================================================
    // FINAL SUMMARY
    // ========================================================

    $display("");
    $display("====================================================");
    $display("                 TEST SUMMARY");
    $display("====================================================");
    $display("Total tests : %0d", total_tests);
    $display("Passed      : %0d", passed_tests);
    $display("Failed      : %0d", failed_tests);
    $display("====================================================");

    if (failed_tests == 0) begin

        $display("");
        $display("*************** ALL TESTS PASSED ***************");
        $display("");

    end
    else begin

        $display("");
        $display("*************** TESTS FAILED ***************");
        $display("");

    end

    $finish;

end


endmodule

