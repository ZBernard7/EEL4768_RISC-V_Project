// AI USE DISCLOSURE:
// OpenAI ChatGPT was used as an aid in the development of this file.
// Accessed September 2026.

`timescale 1ns/1ps
`default_nettype none

module decoder_tb;

    integer passed;
    integer failed;

    reg [31:0] i_inst;

    wire        o_legal;
    wire        o_halt;
    wire [4:0]  o_rs1;
    wire [4:0]  o_rs2;
    wire [4:0]  o_rd;
    wire [31:0] o_immediate;
    wire        o_op1_sel;
    wire        o_op2_sel;
    wire [2:0]  o_alu_opsel;
    wire        o_alu_sub;
    wire        o_alu_unsigned;
    wire        o_alu_arith;
    wire        o_branch;
    wire        o_jump;
    wire        o_branch_equal;
    wire        o_branch_unsigned;
    wire        o_branch_invert;
    wire        o_dmem_ren;
    wire        o_dmem_wen;
    wire [1:0]  o_dmem_align;
    wire        o_dmem_memb;
    wire        o_dmem_memh;
    wire        o_dmem_memw;
    wire        o_dmem_memu;
    wire [3:0]  o_rd_sel;
    wire        o_pc_sel;

decoder dut (
        .i_inst(i_inst),
        .o_legal(o_legal),
        .o_halt(o_halt),
        .o_rs1(o_rs1),
        .o_rs2(o_rs2),
        .o_rd(o_rd),
        .o_immediate(o_immediate),
        .o_op1_sel(o_op1_sel),
        .o_op2_sel(o_op2_sel),
        .o_alu_opsel(o_alu_opsel),
        .o_alu_sub(o_alu_sub),
        .o_alu_unsigned(o_alu_unsigned),
        .o_alu_arith(o_alu_arith),
        .o_branch(o_branch),
        .o_jump(o_jump),
        .o_branch_equal(o_branch_equal),
        .o_branch_unsigned(o_branch_unsigned),
        .o_branch_invert(o_branch_invert),
        .o_dmem_ren(o_dmem_ren),
        .o_dmem_wen(o_dmem_wen),
        .o_dmem_align(o_dmem_align),
        .o_dmem_memb(o_dmem_memb),
        .o_dmem_memh(o_dmem_memh),
        .o_dmem_memw(o_dmem_memw),
        .o_dmem_memu(o_dmem_memu),
        .o_rd_sel(o_rd_sel),
        .o_pc_sel(o_pc_sel)
    );

        initial begin
        passed = 0;
        failed = 0;

        // --------------------------------------------------
        // Test 1: LUI x5, 0x12345
        // --------------------------------------------------
        i_inst = 32'h123452B7;
        #1;

        $display("Testing LUI");

        if ((o_legal === 1'b1) &&
            (o_rd === 5'd5) &&
            (o_rd_sel === 4'b0010) &&
            (o_halt === 1'b0)) begin
            $display("PASS: LUI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LUI");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 2: AUIPC x5, 0x12345
        // --------------------------------------------------
        i_inst = 32'h12345297;
        #1;

        $display("Testing AUIPC");

        if ((o_legal === 1'b1) &&
            (o_rd === 5'd5) &&
            (o_op1_sel === 1'b1) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b000) &&
            (o_rd_sel === 4'b0001)) begin
            $display("PASS: AUIPC");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: AUIPC");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 3: ADD x5, x6, x7
        // --------------------------------------------------
        i_inst = 32'h007302B3;
        #1;

        $display("Testing ADD");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rs2 === 5'd7) &&
            (o_rd === 5'd5) &&
            (o_alu_opsel === 3'b000) &&
            (o_alu_sub === 1'b0) &&
            (o_op1_sel === 1'b0) &&
            (o_op2_sel === 1'b0) &&
            (o_rd_sel === 4'b0001)) begin
            $display("PASS: ADD");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: ADD");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 4: SUB x5, x6, x7
        // --------------------------------------------------
        i_inst = 32'h407302B3;
        #1;

        $display("Testing SUB");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rs2 === 5'd7) &&
            (o_rd === 5'd5) &&
            (o_alu_opsel === 3'b000) &&
            (o_alu_sub === 1'b1) &&
            (o_op1_sel === 1'b0) &&
            (o_op2_sel === 1'b0) &&
            (o_rd_sel === 4'b0001)) begin
            $display("PASS: SUB");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SUB");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 5: ADDI x5, x6, 10
        // --------------------------------------------------
        i_inst = 32'h00A30293;
        #1;

        $display("Testing ADDI");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rd === 5'd5) &&
            (o_op1_sel === 1'b0) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b000) &&
            (o_alu_sub === 1'b0) &&
            (o_rd_sel === 4'b0001)) begin
            $display("PASS: ADDI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: ADDI");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 6: SRAI x5, x6, 3
        // --------------------------------------------------
        i_inst = 32'h40335293;
        #1;

        $display("Testing SRAI");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rd === 5'd5) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b101) &&
            (o_alu_arith === 1'b1) &&
            (o_rd_sel === 4'b0001)) begin
            $display("PASS: SRAI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SRAI");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 7: LW x5, 8(x6)
        // --------------------------------------------------
        i_inst = 32'h00832283;
        #1;

        $display("Testing LW");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rd === 5'd5) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b000) &&
            (o_dmem_ren === 1'b1) &&
            (o_dmem_wen === 1'b0) &&
            (o_dmem_memw === 1'b1) &&
            (o_dmem_memb === 1'b0) &&
            (o_dmem_memh === 1'b0) &&
            (o_dmem_align === 2'b11) &&
            (o_rd_sel === 4'b1000)) begin
            $display("PASS: LW");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LW");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 8: SW x7, 8(x6)
        // --------------------------------------------------
        i_inst = 32'h00732423;
        #1;

        $display("Testing SW");

        if ((o_legal === 1'b1) &&
            (o_rs1 === 5'd6) &&
            (o_rs2 === 5'd7) &&
            (o_rd === 5'd0) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b000) &&
            (o_dmem_ren === 1'b0) &&
            (o_dmem_wen === 1'b1) &&
            (o_dmem_memw === 1'b1) &&
            (o_dmem_memb === 1'b0) &&
            (o_dmem_memh === 1'b0) &&
            (o_dmem_align === 2'b11)) begin
            $display("PASS: SW");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SW");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 9: LB x5, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00030283;
        #1;

        $display("Testing LB");

        if ((o_legal === 1'b1) &&
            (o_dmem_ren === 1'b1) &&
            (o_dmem_memb === 1'b1) &&
            (o_dmem_memh === 1'b0) &&
            (o_dmem_memw === 1'b0) &&
            (o_dmem_memu === 1'b0) &&
            (o_dmem_align === 2'b00)) begin
            $display("PASS: LB");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LB");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 10: LBU x5, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00034283;
        #1;

        $display("Testing LBU");

        if ((o_legal === 1'b1) &&
            (o_dmem_ren === 1'b1) &&
            (o_dmem_memb === 1'b1) &&
            (o_dmem_memu === 1'b1) &&
            (o_dmem_align === 2'b00)) begin
            $display("PASS: LBU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LBU");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 11: LH x5, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00031283;
        #1;

        $display("Testing LH");

        if ((o_legal === 1'b1) &&
            (o_dmem_memh === 1'b1) &&
            (o_dmem_memb === 1'b0) &&
            (o_dmem_memw === 1'b0) &&
            (o_dmem_memu === 1'b0) &&
            (o_dmem_align === 2'b01)) begin
            $display("PASS: LH");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LH");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 12: LHU x5, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00035283;
        #1;

        $display("Testing LHU");

        if ((o_legal === 1'b1) &&
            (o_dmem_memh === 1'b1) &&
            (o_dmem_memu === 1'b1) &&
            (o_dmem_align === 2'b01)) begin
            $display("PASS: LHU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: LHU");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 13: SB x7, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00730023;
        #1;

        $display("Testing SB");

        if ((o_legal === 1'b1) &&
            (o_dmem_wen === 1'b1) &&
            (o_dmem_memb === 1'b1) &&
            (o_dmem_align === 2'b00) &&
            (o_rd === 5'd0)) begin
            $display("PASS: SB");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SB");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 14: SH x7, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h00731023;
        #1;

        $display("Testing SH");

        if ((o_legal === 1'b1) &&
            (o_dmem_wen === 1'b1) &&
            (o_dmem_memh === 1'b1) &&
            (o_dmem_align === 2'b01) &&
            (o_rd === 5'd0)) begin
            $display("PASS: SH");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SH");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 15: BEQ x6, x7
        // --------------------------------------------------
        i_inst = 32'h00730063;
        #1;

        $display("Testing BEQ");

        if ((o_legal === 1'b1) &&
            (o_branch === 1'b1) &&
            (o_jump === 1'b0) &&
            (o_rs1 === 5'd6) &&
            (o_rs2 === 5'd7) &&
            (o_rd === 5'd0) &&
            (o_branch_equal === 1'b1) &&
            (o_branch_unsigned === 1'b0) &&
            (o_branch_invert === 1'b0)) begin
            $display("PASS: BEQ");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BEQ");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 16: BNE x6, x7
        // --------------------------------------------------
        i_inst = 32'h00731063;
        #1;

        $display("Testing BNE");

        if ((o_legal === 1'b1) &&
            (o_branch === 1'b1) &&
            (o_branch_equal === 1'b1) &&
            (o_branch_unsigned === 1'b0) &&
            (o_branch_invert === 1'b1)) begin
            $display("PASS: BNE");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BNE");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 17: BLT x6, x7
        // --------------------------------------------------
        i_inst = 32'h00734063;
        #1;

        $display("Testing BLT");

        if ((o_legal === 1'b1) &&
            (o_branch === 1'b1) &&
            (o_branch_equal === 1'b0) &&
            (o_branch_unsigned === 1'b0) &&
            (o_alu_unsigned === 1'b0) &&
            (o_branch_invert === 1'b0)) begin
            $display("PASS: BLT");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BLT");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 18: BGE x6, x7
        // --------------------------------------------------
        i_inst = 32'h00735063;
        #1;

        $display("Testing BGE");

        if ((o_legal === 1'b1) &&
            (o_branch_equal === 1'b0) &&
            (o_branch_unsigned === 1'b0) &&
            (o_branch_invert === 1'b1)) begin
            $display("PASS: BGE");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BGE");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 19: BLTU x6, x7
        // --------------------------------------------------
        i_inst = 32'h00736063;
        #1;

        $display("Testing BLTU");

        if ((o_legal === 1'b1) &&
            (o_branch_equal === 1'b0) &&
            (o_branch_unsigned === 1'b1) &&
            (o_alu_unsigned === 1'b1) &&
            (o_branch_invert === 1'b0)) begin
            $display("PASS: BLTU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BLTU");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 20: BGEU x6, x7
        // --------------------------------------------------
        i_inst = 32'h00737063;
        #1;

        $display("Testing BGEU");

        if ((o_legal === 1'b1) &&
            (o_branch_equal === 1'b0) &&
            (o_branch_unsigned === 1'b1) &&
            (o_alu_unsigned === 1'b1) &&
            (o_branch_invert === 1'b1)) begin
            $display("PASS: BGEU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: BGEU");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 21: JAL x5, offset
        // --------------------------------------------------
        i_inst = 32'h000002EF;
        #1;

        $display("Testing JAL");

        if ((o_legal === 1'b1) &&
            (o_jump === 1'b1) &&
            (o_branch === 1'b0) &&
            (o_rd === 5'd5) &&
            (o_rd_sel === 4'b0100) &&
            (o_pc_sel === 1'b0)) begin
            $display("PASS: JAL");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: JAL");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 22: JALR x5, 0(x6)
        // --------------------------------------------------
        i_inst = 32'h000302E7;
        #1;

        $display("Testing JALR");

        if ((o_legal === 1'b1) &&
            (o_jump === 1'b1) &&
            (o_branch === 1'b0) &&
            (o_rs1 === 5'd6) &&
            (o_rd === 5'd5) &&
            (o_op1_sel === 1'b0) &&
            (o_op2_sel === 1'b1) &&
            (o_alu_opsel === 3'b000) &&
            (o_rd_sel === 4'b0100) &&
            (o_pc_sel === 1'b1)) begin
            $display("PASS: JALR");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: JALR");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 23: EBREAK
        // --------------------------------------------------
        i_inst = 32'h00100073;
        #1;

        $display("Testing EBREAK");

        if ((o_legal === 1'b1) &&
            (o_halt === 1'b1) &&
            (o_rd === 5'd0)) begin
            $display("PASS: EBREAK");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: EBREAK");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 24: ECALL should be illegal
        // --------------------------------------------------
        i_inst = 32'h00000073;
        #1;

        $display("Testing illegal ECALL");

        if ((o_legal === 1'b0) &&
            (o_halt === 1'b0)) begin
            $display("PASS: ECALL rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: ECALL was not rejected");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 25: Completely unsupported opcode
        // --------------------------------------------------
        i_inst = 32'h00000000;
        #1;

        $display("Testing unsupported opcode");

        if ((o_legal === 1'b0) &&
            (o_halt === 1'b0)) begin
            $display("PASS: unsupported opcode rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: unsupported opcode was not rejected");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 26: Illegal BRANCH funct3
        // BRANCH opcode with funct3 = 010
        // --------------------------------------------------
        i_inst = 32'h00002063;
        #1;

        $display("Testing illegal BRANCH encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal BRANCH rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal BRANCH was accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 27: Illegal LOAD funct3
        // LOAD opcode with funct3 = 011
        // --------------------------------------------------
        i_inst = 32'h00003003;
        #1;

        $display("Testing illegal LOAD encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal LOAD rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal LOAD was accepted");
            failed = failed + 1;
        end

                // Test 28: SLL x5, x6, x7
        i_inst = 32'h007312B3;
        #1;
        $display("Testing SLL");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b001) &&
            (o_alu_sub === 1'b0)) begin
            $display("PASS: SLL");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLL");
            failed = failed + 1;
        end


        // Test 29: SLT x5, x6, x7
        i_inst = 32'h007322B3;
        #1;
        $display("Testing SLT");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b010)) begin
            $display("PASS: SLT");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLT");
            failed = failed + 1;
        end


        // Test 30: SLTU x5, x6, x7
        i_inst = 32'h007332B3;
        #1;
        $display("Testing SLTU");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b011) &&
            (o_alu_unsigned === 1'b1)) begin
            $display("PASS: SLTU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLTU");
            failed = failed + 1;
        end


        // Test 31: XOR x5, x6, x7
        i_inst = 32'h007342B3;
        #1;
        $display("Testing XOR");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b100)) begin
            $display("PASS: XOR");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: XOR");
            failed = failed + 1;
        end


        // Test 32: SRL x5, x6, x7
        i_inst = 32'h007352B3;
        #1;
        $display("Testing SRL");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b101) &&
            (o_alu_arith === 1'b0)) begin
            $display("PASS: SRL");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SRL");
            failed = failed + 1;
        end


        // Test 33: SRA x5, x6, x7
        i_inst = 32'h407352B3;
        #1;
        $display("Testing SRA");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b101) &&
            (o_alu_arith === 1'b1)) begin
            $display("PASS: SRA");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SRA");
            failed = failed + 1;
        end


        // Test 34: OR x5, x6, x7
        i_inst = 32'h007362B3;
        #1;
        $display("Testing OR");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b110)) begin
            $display("PASS: OR");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: OR");
            failed = failed + 1;
        end


        // Test 35: AND x5, x6, x7
        i_inst = 32'h007372B3;
        #1;
        $display("Testing AND");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b111)) begin
            $display("PASS: AND");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: AND");
            failed = failed + 1;
        end

                // Test 36: SLTI x5, x6, 10
        i_inst = 32'h00A32293;
        #1;
        $display("Testing SLTI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b010) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: SLTI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLTI");
            failed = failed + 1;
        end


        // Test 37: SLTIU x5, x6, 10
        i_inst = 32'h00A33293;
        #1;
        $display("Testing SLTIU");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b011) &&
            (o_alu_unsigned === 1'b1) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: SLTIU");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLTIU");
            failed = failed + 1;
        end


        // Test 38: XORI x5, x6, 10
        i_inst = 32'h00A34293;
        #1;
        $display("Testing XORI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b100) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: XORI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: XORI");
            failed = failed + 1;
        end


        // Test 39: ORI x5, x6, 10
        i_inst = 32'h00A36293;
        #1;
        $display("Testing ORI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b110) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: ORI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: ORI");
            failed = failed + 1;
        end


        // Test 40: ANDI x5, x6, 10
        i_inst = 32'h00A37293;
        #1;
        $display("Testing ANDI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b111) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: ANDI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: ANDI");
            failed = failed + 1;
        end


        // Test 41: SLLI x5, x6, 3
        i_inst = 32'h00331293;
        #1;
        $display("Testing SLLI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b001) &&
            (o_alu_arith === 1'b0) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: SLLI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SLLI");
            failed = failed + 1;
        end


        // Test 42: SRLI x5, x6, 3
        i_inst = 32'h00335293;
        #1;
        $display("Testing SRLI");

        if ((o_legal === 1'b1) &&
            (o_alu_opsel === 3'b101) &&
            (o_alu_arith === 1'b0) &&
            (o_op2_sel === 1'b1)) begin
            $display("PASS: SRLI");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: SRLI");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 43: Illegal R-type funct7
        // Looks like ADD, but funct7 is invalid
        // --------------------------------------------------
        i_inst = 32'h207302B3;
        #1;
        $display("Testing illegal R-type funct7");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal R-type funct7 rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal R-type funct7 accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 44: Illegal SUB-style encoding
        // funct7 = 0100000 is only valid for SUB and SRA
        // Here funct3 = 001 (SLL), so this must be illegal
        // --------------------------------------------------
        i_inst = 32'h407312B3;
        #1;
        $display("Testing illegal R-type SLL encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal R-type SLL rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal R-type SLL accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 45: Illegal SLLI funct7
        // SLLI requires funct7 = 0000000
        // --------------------------------------------------
        i_inst = 32'h40331293;
        #1;
        $display("Testing illegal SLLI encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal SLLI rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal SLLI accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 46: Illegal right-shift immediate funct7
        // SRLI allows 0000000
        // SRAI allows 0100000
        // This uses neither
        // --------------------------------------------------
        i_inst = 32'h20335293;
        #1;
        $display("Testing illegal shift-immediate encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal shift-immediate rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal shift-immediate accepted");
            failed = failed + 1;
        end

                // --------------------------------------------------
        // Test 47: Illegal JALR funct3
        // JALR requires funct3 = 000
        // --------------------------------------------------
        i_inst = 32'h000312E7;
        #1;
        $display("Testing illegal JALR encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal JALR rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal JALR accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 48: Illegal STORE funct3
        // STORE only allows 000, 001, 010
        // --------------------------------------------------
        i_inst = 32'h00733023;
        #1;
        $display("Testing illegal STORE encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal STORE rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal STORE accepted");
            failed = failed + 1;
        end


        // --------------------------------------------------
        // Test 49: Illegal OP-IMM shift encoding
        // SLLI requires funct7 = 0000000
        // --------------------------------------------------
        i_inst = 32'h20331293;
        #1;
        $display("Testing illegal OP-IMM shift encoding");

        if ((o_legal === 1'b0) &&
            (o_rd === 5'd0)) begin
            $display("PASS: illegal OP-IMM shift rejected");
            passed = passed + 1;
        end
        else begin
            $display("FAIL: illegal OP-IMM shift accepted");
            failed = failed + 1;
        end

        // --------------------------------------------------
        // Results
        // --------------------------------------------------
        $display("");
        $display("%0d passed, %0d failed", passed, failed);

        if (failed == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");

        $finish;
    end

endmodule

`default_nettype wire