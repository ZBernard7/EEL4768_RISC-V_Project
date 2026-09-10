`timescale 1ns/1ps
`default_nettype none

// Part 2: Immediate Generator Testbench
// Golden model:
//   R = 0
//   I = sign-extended inst[31:20]
//   S = sign-extended {inst[31:25], inst[11:7]}
//   B = sign-extended {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0}
//   U = {inst[31:12], 12'b0}
//   J = sign-extended {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0}
//
// Valid one-hot formats:
//   000001 R, 000010 I, 000100 S, 001000 B, 010000 U, 100000 J
//
// The testbench uses a software golden model and checks every vector.

module imm_tb;

    reg  [31:0] i_inst;
    reg  [5:0]  i_format;
    wire [31:0] o_immediate;

    // Change "immediate_generator" below if your module has a different name.
    imm dut (
        .i_inst(i_inst),
        .i_format(i_format),
        .o_immediate(o_immediate)
    );

    integer total_tests;
    integer passed_tests;
    integer failed_tests;

    // ------------------------------------------------------------------------
    // Golden/reference model
    // ------------------------------------------------------------------------
    function [31:0] expected_immediate;
        input [31:0] inst;
        input [5:0]  format;

        reg [11:0] i_imm;
        reg [11:0] s_imm;
        reg [12:0] b_imm;
        reg [19:0] u_imm;
        reg [20:0] j_imm;

        begin
            i_imm = inst[31:20];
            s_imm = {inst[31:25], inst[11:7]};
            b_imm = {inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            u_imm = inst[31:12];
            j_imm = {inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

            case (format)
                6'b000001: expected_immediate = 32'b0;
                6'b000010: expected_immediate = {{20{i_imm[11]}}, i_imm};
                6'b000100: expected_immediate = {{20{s_imm[11]}}, s_imm};
                6'b001000: expected_immediate = {{19{b_imm[12]}}, b_imm};
                6'b010000: expected_immediate = {u_imm, 12'b0};
                6'b100000: expected_immediate = {{11{j_imm[20]}}, j_imm};
                default:   expected_immediate = 32'b0;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------------
    // Check one vector
    // ------------------------------------------------------------------------
    task check_vector;
        input [31:0] inst;
        input [5:0]  format;

        reg [31:0] expected;

        begin
            i_inst   = inst;
            i_format = format;
            #1;

            expected = expected_immediate(inst, format);
            total_tests = total_tests + 1;

            if (o_immediate === expected) begin
                passed_tests = passed_tests + 1;
            end
            else begin
                failed_tests = failed_tests + 1;

                $display("");
                $display("============================================================");
                $display("FAILURE - Test %0d", total_tests);
                $display("============================================================");
                $display("Inputs:");
                $display("  i_format   = %06b", format);
                $display("  i_inst     = 0x%08h", inst);
                $display("");
                $display("Expected:");
                $display("  immediate  = 0x%08h", expected);
                $display("");
                $display("Actual:");
                $display("  immediate  = 0x%08h", o_immediate);
                $display("============================================================");
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Directed boundary and bit-isolation tests
    // ------------------------------------------------------------------------
    task directed_tests;
        integer k;
        reg [31:0] inst;

        begin
            $display("Running directed tests...");

            // R: no immediate
            check_vector(32'h00000000, 6'b000001);
            check_vector(32'hFFFFFFFF, 6'b000001);
            check_vector(32'hAAAAAAAA, 6'b000001);
            check_vector(32'h55555555, 6'b000001);
            check_vector(32'h12345678, 6'b000001);

            // I-format boundaries
            check_vector(32'h00000000, 6'b000010); // 0
            check_vector(32'h00100000, 6'b000010); // +1
            check_vector(32'h7FF00000, 6'b000010); // +2047
            check_vector(32'h80000000, 6'b000010); // -2048
            check_vector(32'hFFF00000, 6'b000010); // -1
            check_vector(32'hABC00000, 6'b000010); // arbitrary negative

            // S-format boundaries
            check_vector(32'h00000000, 6'b000100);
            check_vector(32'h00000080, 6'b000100);
            check_vector(32'h00000F80, 6'b000100);
            check_vector(32'h7E000F80, 6'b000100);
            check_vector(32'hFE000F80, 6'b000100);
            check_vector(32'hFFFFFFFF, 6'b000100);

            // B-format boundaries / sign extension
            check_vector(32'h00000000, 6'b001000);
            check_vector(32'h00000080, 6'b001000);
            check_vector(32'h00000F00, 6'b001000);
            check_vector(32'h7E000F80, 6'b001000);
            check_vector(32'hFE000F80, 6'b001000);
            check_vector(32'hFFFFFFFF, 6'b001000);

            // U-format
            check_vector(32'h00000000, 6'b010000);
            check_vector(32'h00001000, 6'b010000);
            check_vector(32'h12345000, 6'b010000);
            check_vector(32'h80000000, 6'b010000);
            check_vector(32'hFFFFF000, 6'b010000);
            check_vector(32'hFFFFFFFF, 6'b010000);

            // J-format
            check_vector(32'h00000000, 6'b100000);
            check_vector(32'h00001000, 6'b100000);
            check_vector(32'h7FFFF000, 6'b100000);
            check_vector(32'h80000000, 6'b100000);
            check_vector(32'hFFFFF000, 6'b100000);
            check_vector(32'hFFFFFFFF, 6'b100000);

            // Toggle every instruction bit individually.
            // This catches incorrect source-bit wiring/extraction.
            for (k = 0; k < 32; k = k + 1) begin
                inst = 32'b0;
                inst[k] = 1'b1;

                check_vector(inst, 6'b000010);
                check_vector(inst, 6'b000100);
                check_vector(inst, 6'b001000);
                check_vector(inst, 6'b010000);
                check_vector(inst, 6'b100000);
            end

            // Toggle each bit against an all-ones background as well.
            for (k = 0; k < 32; k = k + 1) begin
                inst = 32'hFFFFFFFF;
                inst[k] = 1'b0;

                check_vector(inst, 6'b000010);
                check_vector(inst, 6'b000100);
                check_vector(inst, 6'b001000);
                check_vector(inst, 6'b010000);
                check_vector(inst, 6'b100000);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Randomized tests
    // ------------------------------------------------------------------------
    task random_tests;
        integer k;
        reg [31:0] random_inst;

        begin
            $display("Running randomized tests...");

            // 20,000 random instruction words.
            // Each word is tested against all six valid formats:
            // 120,000 random-format combinations.
            for (k = 0; k < 20000; k = k + 1) begin
                random_inst = {$random, $random};

                check_vector(random_inst, 6'b000001);
                check_vector(random_inst, 6'b000010);
                check_vector(random_inst, 6'b000100);
                check_vector(random_inst, 6'b001000);
                check_vector(random_inst, 6'b010000);
                check_vector(random_inst, 6'b100000);
            end

            // Additional random tests concentrating on immediate-sign
            // behavior: force the instruction's upper half to random values
            // while varying the lower half independently.
            for (k = 0; k < 10000; k = k + 1) begin
                random_inst = {$random, $random};
                check_vector(random_inst, 6'b000010);
                check_vector(random_inst, 6'b000100);
                check_vector(random_inst, 6'b001000);
                check_vector(random_inst, 6'b100000);
            end
        end
    endtask

    // ------------------------------------------------------------------------
    // Invalid format tests
    //
    // The provided Part 2 specification defines behavior for six valid
    // one-hot formats but does not specify invalid encodings. The golden
    // model assumes zero for unsupported formats. Remove this task if your
    // instructor requires a different invalid-format behavior.
    // ------------------------------------------------------------------------
    task invalid_format_tests;
        begin
            $display("Running invalid-format tests...");

            check_vector(32'h12345678, 6'b000000);
            check_vector(32'h12345678, 6'b000011);
            check_vector(32'h12345678, 6'b001010);
            check_vector(32'h12345678, 6'b010101);
            check_vector(32'h12345678, 6'b101010);
            check_vector(32'h12345678, 6'b111111);

            check_vector(32'hFFFFFFFF, 6'b000000);
            check_vector(32'hFFFFFFFF, 6'b111111);
        end
    endtask

    // ------------------------------------------------------------------------
    // Main
    // ------------------------------------------------------------------------
    initial begin
        total_tests  = 0;
        passed_tests = 0;
        failed_tests = 0;

        i_inst   = 32'b0;
        i_format = 6'b000001;

        #1;

        directed_tests();
        invalid_format_tests();
        random_tests();

        $display("");
        $display("============================================================");
        $display("IMMEDIATE GENERATOR TEST SUMMARY");
        $display("============================================================");
        $display("Total tests : %0d", total_tests);
        $display("Passed      : %0d", passed_tests);
        $display("Failed      : %0d", failed_tests);
        $display("============================================================");

        if (failed_tests == 0)
            $display("ALL TESTS PASSED!");
        else
            $display("TESTS FAILED - CHECK THE FAILURE VECTORS ABOVE.");

        $display("");
        $finish;
    end

endmodule

`default_nettype wire
