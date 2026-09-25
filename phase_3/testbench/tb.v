`timescale 1ns/1ps
`default_nettype none

// ============================================================================
// Phase 3 RV32I HART TESTBENCH
// ============================================================================
// This testbench is intentionally simulation-only. It uses a software
// "golden model" to calculate what each instruction SHOULD do, then checks
// the DUT's retire interface every cycle.
//
// Coverage includes:
//   - ADD / SUB
//   - SLL / SRL / SRA
//   - SLT / SLTU
//   - XOR / OR / AND
//   - ADDI / SLTI / SLTIU / XORI / ORI / ANDI
//   - SLLI / SRLI / SRAI
//   - LUI / AUIPC
//   - LB / LBU / LH / LHU / LW
//   - SB / SH / SW
//   - BEQ / BNE / BLT / BGE / BLTU / BGEU
//   - JAL / JALR
//   - EBREAK
//   - misaligned load/store traps
//   - x0 write protection
//   - random operands, random immediates, and boundary values
//
// The synthesizable-subset restrictions from the Phase 3 handout apply to
// the submitted hardware modules, NOT to this simulation-only testbench.
// ============================================================================

module tb;

    // ------------------------------------------------------------------------
    // DUT interface
    // ------------------------------------------------------------------------
    reg         i_clk;
    reg         i_rst;

    wire [31:0] o_imem_raddr;
    reg  [31:0] i_imem_rdata;

    wire [31:0] o_dmem_addr;
    wire        o_dmem_ren;
    wire        o_dmem_wen;
    wire [31:0] o_dmem_wdata;
    wire [3:0]  o_dmem_mask;
    reg  [31:0] i_dmem_rdata;

    wire        o_retire_valid;
    wire [31:0] o_retire_inst;
    wire        o_retire_trap;
    wire        o_retire_halt;
    wire [4:0]  o_retire_rs1_raddr;
    wire [31:0] o_retire_rs1_rdata;
    wire [4:0]  o_retire_rs2_raddr;
    wire [31:0] o_retire_rs2_rdata;
    wire [4:0]  o_retire_rd_waddr;
    wire [31:0] o_retire_rd_wdata;
    wire [31:0] o_retire_pc;
    wire [31:0] o_retire_next_pc;

    hart #(
        .RESET_ADDR(32'h00000000)
    ) dut (
        .i_clk              (i_clk),
        .i_rst              (i_rst),

        .o_imem_raddr       (o_imem_raddr),
        .i_imem_rdata       (i_imem_rdata),

        .o_dmem_addr        (o_dmem_addr),
        .o_dmem_ren         (o_dmem_ren),
        .o_dmem_wen         (o_dmem_wen),
        .o_dmem_wdata       (o_dmem_wdata),
        .o_dmem_mask        (o_dmem_mask),
        .i_dmem_rdata       (i_dmem_rdata),

        .o_retire_valid     (o_retire_valid),
        .o_retire_inst      (o_retire_inst),
        .o_retire_trap      (o_retire_trap),
        .o_retire_halt      (o_retire_halt),
        .o_retire_rs1_raddr (o_retire_rs1_raddr),
        .o_retire_rs1_rdata (o_retire_rs1_rdata),
        .o_retire_rs2_raddr (o_retire_rs2_raddr),
        .o_retire_rs2_rdata (o_retire_rs2_rdata),
        .o_retire_rd_waddr  (o_retire_rd_waddr),
        .o_retire_rd_wdata  (o_retire_rd_wdata),
        .o_retire_pc        (o_retire_pc),
        .o_retire_next_pc   (o_retire_next_pc)
    );

    // ------------------------------------------------------------------------
    // Instruction and data memory models
    // ------------------------------------------------------------------------
    reg [31:0] imem [0:32767];
    reg [31:0] dmem [0:255];
    reg [31:0] golden_dmem [0:255];

    integer imem_index;
    integer dmem_index;

    // Instruction memory is combinational.
    always @(*) begin
        imem_index = o_imem_raddr[17:2];

        if (imem_index >= 0 && imem_index < 32768)
            i_imem_rdata = imem[imem_index];
        else
            i_imem_rdata = 32'h00000013; // NOP = ADDI x0,x0,0
    end

    // Data memory is combinational for reads.
    always @(*) begin
        dmem_index = o_dmem_addr[9:2];

        if (dmem_index >= 0 && dmem_index < 256)
            i_dmem_rdata = dmem[dmem_index];
        else
            i_dmem_rdata = 32'h00000000;
    end

    // The DUT's stores commit on the clock edge.
    always @(posedge i_clk) begin
        if (!i_rst && o_dmem_wen) begin
            if (o_dmem_mask[0])
                dmem[o_dmem_addr[9:2]][7:0]   <= o_dmem_wdata[7:0];

            if (o_dmem_mask[1])
                dmem[o_dmem_addr[9:2]][15:8]  <= o_dmem_wdata[15:8];

            if (o_dmem_mask[2])
                dmem[o_dmem_addr[9:2]][23:16] <= o_dmem_wdata[23:16];

            if (o_dmem_mask[3])
                dmem[o_dmem_addr[9:2]][31:24] <= o_dmem_wdata[31:24];
        end
    end

    // ------------------------------------------------------------------------
    // Golden-model register file and counters
    // ------------------------------------------------------------------------
    reg [31:0] golden_regs [0:31];

    integer seed;
    integer k;
    integer cycle_count;
    integer pass_count;
    integer fail_count;
    integer vector_count;

    reg [31:0] build_pc;

    // ------------------------------------------------------------------------
    // Golden-model expected values
    // ------------------------------------------------------------------------
    reg [31:0] exp_inst;
    reg [31:0] exp_pc;
    reg [31:0] exp_next_pc;

    reg        exp_trap;
    reg        exp_halt;

    reg [4:0]  exp_rs1_addr;
    reg [31:0] exp_rs1_data;
    reg [4:0]  exp_rs2_addr;
    reg [31:0] exp_rs2_data;

    reg [4:0]  exp_rd_addr;
    reg [31:0] exp_rd_data;

    reg        exp_dmem_ren;
    reg        exp_dmem_wen;
    reg [3:0]  exp_dmem_mask;
    reg [31:0] exp_dmem_addr;
    reg [31:0] exp_dmem_wdata;

    reg [31:0] model_result;
    reg [31:0] model_imm;
    reg [31:0] model_addr;
    reg [31:0] model_mem_word;
    reg [31:0] model_load_data;

    reg [31:0] rs1_value;
    reg [31:0] rs2_value;

    reg [6:0]  opcode;
    reg [2:0]  funct3;
    reg [6:0]  funct7;
    reg [4:0]  rs1;
    reg [4:0]  rs2;
    reg [4:0]  rd;

    reg        branch_taken;
    reg        valid_instruction;

    integer signed_temp;
    integer unsigned_temp;

    // ------------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------------
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    // ------------------------------------------------------------------------
    // RV32I instruction encoders
    // ------------------------------------------------------------------------

    function [31:0] enc_r;
        input [6:0] f7;
        input [4:0] rs2_f;
        input [4:0] rs1_f;
        input [2:0] f3;
        input [4:0] rd_f;
        begin
            enc_r = {f7, rs2_f, rs1_f, f3, rd_f, 7'b0110011};
        end
    endfunction

    function [31:0] enc_i;
        input [11:0] imm12;
        input [4:0] rs1_f;
        input [2:0] f3;
        input [4:0] rd_f;
        input [6:0] op;
        begin
            enc_i = {imm12, rs1_f, f3, rd_f, op};
        end
    endfunction

    function [31:0] enc_s;
        input [11:0] imm12;
        input [4:0] rs2_f;
        input [4:0] rs1_f;
        input [2:0] f3;
        begin
            enc_s = {imm12[11:5], rs2_f, rs1_f, f3, imm12[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] enc_b;
        input [12:0] imm13;
        input [4:0] rs2_f;
        input [4:0] rs1_f;
        input [2:0] f3;
        begin
            enc_b = {
                imm13[12],
                imm13[10:5],
                rs2_f,
                rs1_f,
                f3,
                imm13[4:1],
                imm13[11],
                1'b0,
                7'b1100011
            };
        end
    endfunction

    function [31:0] enc_u;
        input [31:0] value;
        input [4:0] rd_f;
        input [6:0] op;
        begin
            enc_u = {value[31:12], rd_f, op};
        end
    endfunction

    function [31:0] enc_j;
        input [20:0] imm21;
        input [4:0] rd_f;
        begin
            enc_j = {
                imm21[20],
                imm21[10:1],
                imm21[11],
                imm21[19:12],
                rd_f,
                7'b1101111
            };
        end
    endfunction

    // ------------------------------------------------------------------------
    // Program-building tasks
    // ------------------------------------------------------------------------

    task emit;
        input [31:0] instruction;
        begin
            imem[build_pc[17:2]] = instruction;
            build_pc = build_pc + 32'd4;
            vector_count = vector_count + 1;
        end
    endtask

    // Loads any 32-bit constant using LUI + ADDI.
    task load_constant;
        input [4:0] reg_num;
        input [31:0] value;
        reg [31:0] upper_value;
        reg [11:0] lower_value;
        begin
            // The +0x800 adjustment makes the lower 12-bit ADDI signed
            // immediate reconstruct the original 32-bit value correctly.
            upper_value = (value + 32'h00000800) >> 12;
            lower_value = value[11:0];

            emit(enc_u(upper_value << 12, reg_num, 7'b0110111));
            emit(enc_i(lower_value, reg_num, 3'b000, reg_num, 7'b0010011));
        end
    endtask

    task emit_nop;
        begin
            emit(32'h00000013);
        end
    endtask

    // ------------------------------------------------------------------------
    // Random arithmetic test generation
    // ------------------------------------------------------------------------
    task generate_random_r_vector;
        input [31:0] a;
        input [31:0] b;
        input [3:0] operation;
        begin
            load_constant(5'd1, a);
            load_constant(5'd2, b);

            case (operation)
                4'd0: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3)); // ADD
                4'd1: emit(enc_r(7'b0100000, 5'd2, 5'd1, 3'b000, 5'd3)); // SUB
                4'd2: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b001, 5'd3)); // SLL
                4'd3: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b010, 5'd3)); // SLT
                4'd4: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b011, 5'd3)); // SLTU
                4'd5: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b100, 5'd3)); // XOR
                4'd6: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b101, 5'd3)); // SRL
                4'd7: emit(enc_r(7'b0100000, 5'd2, 5'd1, 3'b101, 5'd3)); // SRA
                4'd8: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b110, 5'd3)); // OR
                4'd9: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b111, 5'd3)); // AND
                default: emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd3));
            endcase
        end
    endtask

    // ------------------------------------------------------------------------
    // Build a large randomized program
    // ------------------------------------------------------------------------
    task build_program;
        integer i;
        integer op_select;
        reg [31:0] rand_a;
        reg [31:0] rand_b;
        reg [11:0] rand_imm;
        reg [31:0] special_values [0:15];
        begin
            build_pc = 32'h00000000;
            vector_count = 0;

            // Useful boundary values. These are especially important for
            // signed/unsigned comparisons and arithmetic overflow.
            special_values[0]  = 32'h00000000;
            special_values[1]  = 32'h00000001;
            special_values[2]  = 32'h00000002;
            special_values[3]  = 32'h00000003;
            special_values[4]  = 32'h00000004;
            special_values[5]  = 32'h00000007;
            special_values[6]  = 32'h00000008;
            special_values[7]  = 32'h0000001F;
            special_values[8]  = 32'h00000020;
            special_values[9]  = 32'h7FFFFFFF;
            special_values[10] = 32'h80000000;
            special_values[11] = 32'h80000001;
            special_values[12] = 32'hFFFFFFFF;
            special_values[13] = 32'hFFFFFFFE;
            special_values[14] = 32'hAAAAAAAA;
            special_values[15] = 32'h55555555;

            // First, exhaustively mix the important edge values.
            for (i = 0; i < 16; i = i + 1) begin
                for (op_select = 0; op_select < 10; op_select = op_select + 1) begin
                    generate_random_r_vector(
                        special_values[i],
                        special_values[15-i],
                        op_select[3:0]
                    );
                end
            end

            // Large randomized R-type campaign.
            for (i = 0; i < 1200; i = i + 1) begin
                rand_a = $random(seed);
                rand_b = $random(seed);
                op_select = $random(seed);
                if (op_select < 0)
                    op_select = -op_select;
                op_select = op_select % 10;

                generate_random_r_vector(
                    rand_a,
                    rand_b,
                    op_select[3:0]
                );
            end

            // Random I-type arithmetic and logical instructions.
            for (i = 0; i < 1000; i = i + 1) begin
                rand_a = $random(seed);
                rand_imm = $random(seed);

                load_constant(5'd1, rand_a);

                op_select = $random(seed);
                if (op_select < 0)
                    op_select = -op_select;
                op_select = op_select % 9;

                case (op_select)
                    0: emit(enc_i(rand_imm, 5'd1, 3'b000, 5'd3, 7'b0010011)); // ADDI
                    1: emit(enc_i(rand_imm, 5'd1, 3'b010, 5'd3, 7'b0010011)); // SLTI
                    2: emit(enc_i(rand_imm, 5'd1, 3'b011, 5'd3, 7'b0010011)); // SLTIU
                    3: emit(enc_i(rand_imm, 5'd1, 3'b100, 5'd3, 7'b0010011)); // XORI
                    4: emit(enc_i(rand_imm, 5'd1, 3'b110, 5'd3, 7'b0010011)); // ORI
                    5: emit(enc_i(rand_imm, 5'd1, 3'b111, 5'd3, 7'b0010011)); // ANDI
                    6: emit(enc_i({7'b0000000, rand_imm[4:0]}, 5'd1, 3'b001, 5'd3, 7'b0010011)); // SLLI
                    7: emit(enc_i({7'b0000000, rand_imm[4:0]}, 5'd1, 3'b101, 5'd3, 7'b0010011)); // SRLI
                    8: emit(enc_i({7'b0100000, rand_imm[4:0]}, 5'd1, 3'b101, 5'd3, 7'b0010011)); // SRAI
                endcase
            end

            // x0 must always stay zero, even if an instruction tries to write it.
            for (i = 0; i < 100; i = i + 1) begin
                rand_a = $random(seed);
                rand_b = $random(seed);
                load_constant(5'd1, rand_a);
                load_constant(5'd2, rand_b);
                emit(enc_r(7'b0000000, 5'd2, 5'd1, 3'b000, 5'd0));
                emit(enc_i(12'h7FF, 5'd0, 3'b000, 5'd0, 7'b0010011));
            end

            // ----------------------------------------------------------------
            // Memory tests.
            // ----------------------------------------------------------------
            // Base address 0x100 is safely inside our small test memory.
            load_constant(5'd10, 32'h00000100);

            for (i = 0; i < 250; i = i + 1) begin
                rand_a = $random(seed);
                load_constant(5'd11, rand_a);

                // Randomly exercise SB, SH, and SW.
                op_select = $random(seed);
                if (op_select < 0)
                    op_select = -op_select;
                op_select = op_select % 3;

                case (op_select)
                    0: begin
                        // Byte store at one of the four byte offsets.
                        case (i % 4)
                            0: emit(enc_s(12'd0, 5'd11, 5'd10, 3'b000));
                            1: emit(enc_s(12'd1, 5'd11, 5'd10, 3'b000));
                            2: emit(enc_s(12'd2, 5'd11, 5'd10, 3'b000));
                            default: emit(enc_s(12'd3, 5'd11, 5'd10, 3'b000));
                        endcase
                    end

                    1: begin
                        // Half-word stores at aligned offsets.
                        if (i[0] == 1'b0)
                            emit(enc_s(12'd0, 5'd11, 5'd10, 3'b001));
                        else
                            emit(enc_s(12'd2, 5'd11, 5'd10, 3'b001));
                    end

                    default: begin
                        emit(enc_s(12'd0, 5'd11, 5'd10, 3'b010));
                    end
                endcase

                // Exercise all five load variants.
                case (i % 5)
                    0: emit(enc_i(12'd0, 5'd10, 3'b000, 5'd12, 7'b0000011)); // LB
                    1: emit(enc_i(12'd0, 5'd10, 3'b100, 5'd12, 7'b0000011)); // LBU
                    2: emit(enc_i(12'd0, 5'd10, 3'b001, 5'd12, 7'b0000011)); // LH
                    3: emit(enc_i(12'd0, 5'd10, 3'b101, 5'd12, 7'b0000011)); // LHU
                    default: emit(enc_i(12'd0, 5'd10, 3'b010, 5'd12, 7'b0000011)); // LW
                endcase
            end

            // Misaligned accesses. These should trap and must not write memory
            // or registers.
            emit(enc_i(12'd1, 5'd10, 3'b001, 5'd13, 7'b0000011)); // LH @ +1
            emit(enc_i(12'd2, 5'd10, 3'b010, 5'd13, 7'b0000011)); // LW @ +2
            emit(enc_s(12'd1, 5'd11, 5'd10, 3'b001));              // SH @ +1
            emit(enc_s(12'd2, 5'd11, 5'd10, 3'b010));              // SW @ +2

            // ----------------------------------------------------------------
            // Branch tests.
            // Each branch has a +8 target, so a taken branch skips exactly one
            // instruction. The instruction after the skipped instruction is
            // always reached, keeping the test program linear.
            // ----------------------------------------------------------------
            for (i = 0; i < 150; i = i + 1) begin
                rand_a = $random(seed);
                rand_b = $random(seed);

                load_constant(5'd1, rand_a);
                load_constant(5'd2, rand_b);

                case (i % 6)
                    0: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b000)); // BEQ
                    1: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b001)); // BNE
                    2: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b100)); // BLT
                    3: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b101)); // BGE
                    4: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b110)); // BLTU
                    default: emit(enc_b(13'd8, 5'd2, 5'd1, 3'b111)); // BGEU
                endcase

                emit(enc_i(12'd1, 5'd4, 3'b000, 5'd4, 7'b0010011));
                emit(enc_i(12'd1, 5'd5, 3'b000, 5'd5, 7'b0010011));
            end

            // ----------------------------------------------------------------
            // JAL test.
            // ----------------------------------------------------------------
            emit(enc_j(21'd8, 5'd6));
            emit(enc_i(12'd123, 5'd0, 3'b000, 5'd7, 7'b0010011)); // skipped
            emit(enc_i(12'd1, 5'd6, 3'b000, 5'd7, 7'b0010011));

            // ----------------------------------------------------------------
            // JALR test.
            // We know the target address while building the program.
            // ----------------------------------------------------------------
            load_constant(5'd7, build_pc + 32'd16);
            emit(enc_i(12'd0, 5'd7, 3'b000, 5'd8, 7'b1100111)); // JALR
            emit(enc_i(12'd99, 5'd0, 3'b000, 5'd9, 7'b0010011)); // skipped
            emit(enc_i(12'd100, 5'd0, 3'b000, 5'd9, 7'b0010011)); // skipped
            emit_nop(); // target

            // AUIPC gets a dedicated test near the end.
            emit(enc_u(32'h12345000, 5'd14, 7'b0010111));

            // End the program.
            emit(32'h00100073); // EBREAK
        end
    endtask

    // ------------------------------------------------------------------------
    // Helper: mismatch reporting
    // ------------------------------------------------------------------------
    task report_mismatch;
        input [8*80-1:0] signal_name;
        input [31:0] expected;
        input [31:0] actual;
        begin
            fail_count = fail_count + 1;
            $display("FAIL cycle=%0d pc=%08h inst=%08h signal=%s expected=%08h actual=%08h",
                     cycle_count, o_retire_pc, o_retire_inst,
                     signal_name, expected, actual);
        end
    endtask

    // ------------------------------------------------------------------------
    // Main testbench
    // ------------------------------------------------------------------------
    initial begin
        // Initialize memories.
        for (k = 0; k < 32768; k = k + 1)
            imem[k] = 32'h00000013;

        for (k = 0; k < 256; k = k + 1) begin
            dmem[k] = 32'h00000000;
            golden_dmem[k] = 32'h00000000;
        end

        for (k = 0; k < 32; k = k + 1)
            golden_regs[k] = 32'h00000000;

        seed = 32'h5A17C0DE;
        cycle_count = 0;
        pass_count = 0;
        fail_count = 0;

        build_program();

        $display("============================================================");
        $display("Phase 3 RV32I randomized golden-model testbench");
        $display("Generated %0d instruction vectors", vector_count);
        $display("Random seed = %08h", seed);
        $display("============================================================");

        // Synchronous reset.
        i_rst = 1'b1;

        repeat (2)
            @(posedge i_clk);

        i_rst = 1'b0;

        // Check one retired instruction per cycle.
        run_loop: forever begin
            @(negedge i_clk);
            #1;

            cycle_count = cycle_count + 1;

            // Stop if something has gone badly wrong with the test.
            if (cycle_count > 30000) begin
                $display("ERROR: test exceeded maximum cycle count.");
                fail_count = fail_count + 1;
                disable run_loop;
            end

            // ------------------------------------------------------------
            // Start every vector with default expected values.
            // ------------------------------------------------------------
            exp_inst      = i_imem_rdata;
            exp_pc        = o_imem_raddr;
            exp_next_pc   = exp_pc + 32'd4;

            exp_trap      = 1'b0;
            exp_halt      = 1'b0;

            exp_rs1_addr  = 5'd0;
            exp_rs1_data  = 32'd0;
            exp_rs2_addr  = 5'd0;
            exp_rs2_data  = 32'd0;

            exp_rd_addr   = 5'd0;
            exp_rd_data   = 32'd0;

            exp_dmem_ren  = 1'b0;
            exp_dmem_wen  = 1'b0;
            exp_dmem_mask = 4'b0000;
            exp_dmem_addr = 32'd0;
            exp_dmem_wdata = 32'd0;

            model_result  = 32'd0;
            model_imm     = 32'd0;
            model_addr    = 32'd0;
            model_load_data = 32'd0;
            branch_taken  = 1'b0;
            valid_instruction = 1'b1;

            opcode = exp_inst[6:0];
            funct3 = exp_inst[14:12];
            funct7 = exp_inst[31:25];
            rs1    = exp_inst[19:15];
            rs2    = exp_inst[24:20];
            rd     = exp_inst[11:7];

            rs1_value = (rs1 == 5'd0) ? 32'd0 : golden_regs[rs1];
            rs2_value = (rs2 == 5'd0) ? 32'd0 : golden_regs[rs2];

            // ------------------------------------------------------------
            // Golden model decode + execute
            // ------------------------------------------------------------
            case (opcode)

                // --------------------------------------------------------
                // R-type register arithmetic/logical instructions
                // --------------------------------------------------------
                7'b0110011: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rs2_addr = rs2;
                    exp_rs2_data = rs2_value;

                    exp_rd_addr = rd;

                    case (funct3)
                        3'b000: begin
                            if (funct7 == 7'b0100000)
                                model_result = rs1_value - rs2_value;
                            else
                                model_result = rs1_value + rs2_value;
                        end

                        3'b001:
                            model_result = rs1_value << rs2_value[4:0];

                        3'b010:
                            model_result = ($signed(rs1_value) < $signed(rs2_value)) ? 32'd1 : 32'd0;

                        3'b011:
                            model_result = (rs1_value < rs2_value) ? 32'd1 : 32'd0;

                        3'b100:
                            model_result = rs1_value ^ rs2_value;

                        3'b101: begin
                            if (funct7 == 7'b0100000)
                                model_result = $signed(rs1_value) >>> rs2_value[4:0];
                            else
                                model_result = rs1_value >> rs2_value[4:0];
                        end

                        3'b110:
                            model_result = rs1_value | rs2_value;

                        3'b111:
                            model_result = rs1_value & rs2_value;

                        default: begin
                            valid_instruction = 1'b0;
                            exp_rd_addr = 5'd0;
                        end
                    endcase

                    exp_rd_data = model_result;
                end

                // --------------------------------------------------------
                // I-type ALU instructions
                // --------------------------------------------------------
                7'b0010011: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rd_addr  = rd;
                    model_imm = {{20{exp_inst[31]}}, exp_inst[31:20]};

                    case (funct3)
                        3'b000:
                            model_result = rs1_value + model_imm;

                        3'b010:
                            model_result = ($signed(rs1_value) < $signed(model_imm)) ? 32'd1 : 32'd0;

                        3'b011:
                            model_result = (rs1_value < model_imm) ? 32'd1 : 32'd0;

                        3'b100:
                            model_result = rs1_value ^ model_imm;

                        3'b110:
                            model_result = rs1_value | model_imm;

                        3'b111:
                            model_result = rs1_value & model_imm;

                        3'b001:
                            model_result = rs1_value << exp_inst[24:20];

                        3'b101: begin
                            if (exp_inst[30])
                                model_result = $signed(rs1_value) >>> exp_inst[24:20];
                            else
                                model_result = rs1_value >> exp_inst[24:20];
                        end

                        default: begin
                            valid_instruction = 1'b0;
                            exp_rd_addr = 5'd0;
                        end
                    endcase

                    exp_rd_data = model_result;
                end

                // --------------------------------------------------------
                // LUI
                // --------------------------------------------------------
                7'b0110111: begin
                    exp_rd_addr = rd;
                    exp_rd_data = {exp_inst[31:12], 12'b0};
                end

                // --------------------------------------------------------
                // AUIPC
                // --------------------------------------------------------
                7'b0010111: begin
                    exp_rd_addr = rd;
                    exp_rd_data = exp_pc + {exp_inst[31:12], 12'b0};
                end

                // --------------------------------------------------------
                // Loads
                // --------------------------------------------------------
                7'b0000011: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rd_addr  = rd;

                    model_imm = {{20{exp_inst[31]}}, exp_inst[31:20]};
                    model_addr = rs1_value + model_imm;

                    exp_dmem_addr = {model_addr[31:2], 2'b00};

                    if ((funct3 == 3'b001 || funct3 == 3'b101) &&
                        model_addr[0]) begin
                        exp_trap = 1'b1;
                    end

                    if (funct3 == 3'b010 && model_addr[1:0] != 2'b00) begin
                        exp_trap = 1'b1;
                    end

                    if (!exp_trap) begin
                        exp_dmem_ren = 1'b1;

                        if (exp_dmem_addr[9:2] < 256)
                            model_mem_word = golden_dmem[exp_dmem_addr[9:2]];
                        else
                            model_mem_word = 32'd0;

                        case (model_addr[1:0])
                            2'b00: begin
                                model_load_data = model_mem_word[7:0];
                            end
                            2'b01: begin
                                model_load_data = model_mem_word[15:8];
                            end
                            2'b10: begin
                                model_load_data = model_mem_word[23:16];
                            end
                            default: begin
                                model_load_data = model_mem_word[31:24];
                            end
                        endcase

                        case (funct3)
                            3'b000: // LB
                                exp_rd_data = {{24{model_load_data[7]}}, model_load_data[7:0]};

                            3'b100: // LBU
                                exp_rd_data = {24'b0, model_load_data[7:0]};

                            3'b001: begin // LH
                                if (model_addr[1])
                                    exp_rd_data = {{16{model_mem_word[31]}}, model_mem_word[31:16]};
                                else
                                    exp_rd_data = {{16{model_mem_word[15]}}, model_mem_word[15:0]};
                            end

                            3'b101: begin // LHU
                                if (model_addr[1])
                                    exp_rd_data = {16'b0, model_mem_word[31:16]};
                                else
                                    exp_rd_data = {16'b0, model_mem_word[15:0]};
                            end

                            3'b010: // LW
                                exp_rd_data = model_mem_word;

                            default: begin
                                valid_instruction = 1'b0;
                                exp_rd_addr = 5'd0;
                            end
                        endcase
                    end
                    else begin
                        exp_rd_addr = 5'd0;
                        exp_rd_data = 32'd0;
                    end
                end

                // --------------------------------------------------------
                // Stores
                // --------------------------------------------------------
                7'b0100011: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rs2_addr = rs2;
                    exp_rs2_data = rs2_value;

                    model_imm = {{20{exp_inst[31]}}, exp_inst[31:25], exp_inst[11:7]};
                    model_addr = rs1_value + model_imm;

                    exp_dmem_addr = {model_addr[31:2], 2'b00};

                    if (funct3 == 3'b001 && model_addr[0])
                        exp_trap = 1'b1;

                    if (funct3 == 3'b010 && model_addr[1:0] != 2'b00)
                        exp_trap = 1'b1;

                    if (!exp_trap) begin
                        exp_dmem_wen = 1'b1;

                        case (funct3)
                            3'b000: begin // SB
                                case (model_addr[1:0])
                                    2'b00: begin
                                        exp_dmem_mask = 4'b0001;
                                        exp_dmem_wdata = {24'b0, rs2_value[7:0]};
                                    end
                                    2'b01: begin
                                        exp_dmem_mask = 4'b0010;
                                        exp_dmem_wdata = {16'b0, rs2_value[7:0], 8'b0};
                                    end
                                    2'b10: begin
                                        exp_dmem_mask = 4'b0100;
                                        exp_dmem_wdata = {8'b0, rs2_value[7:0], 16'b0};
                                    end
                                    default: begin
                                        exp_dmem_mask = 4'b1000;
                                        exp_dmem_wdata = {rs2_value[7:0], 24'b0};
                                    end
                                endcase
                            end

                            3'b001: begin // SH
                                if (model_addr[1]) begin
                                    exp_dmem_mask = 4'b1100;
                                    exp_dmem_wdata = {rs2_value[15:0], 16'b0};
                                end
                                else begin
                                    exp_dmem_mask = 4'b0011;
                                    exp_dmem_wdata = {16'b0, rs2_value[15:0]};
                                end
                            end

                            3'b010: begin // SW
                                exp_dmem_mask = 4'b1111;
                                exp_dmem_wdata = rs2_value;
                            end

                            default: begin
                                valid_instruction = 1'b0;
                                exp_dmem_wen = 1'b0;
                            end
                        endcase
                    end
                end

                // --------------------------------------------------------
                // Conditional branches
                // --------------------------------------------------------
                7'b1100011: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rs2_addr = rs2;
                    exp_rs2_data = rs2_value;

                    model_imm = {
                        {19{exp_inst[31]}},
                        exp_inst[31],
                        exp_inst[7],
                        exp_inst[30:25],
                        exp_inst[11:8],
                        1'b0
                    };

                    case (funct3)
                        3'b000: branch_taken = (rs1_value == rs2_value); // BEQ
                        3'b001: branch_taken = (rs1_value != rs2_value); // BNE
                        3'b100: branch_taken = ($signed(rs1_value) < $signed(rs2_value)); // BLT
                        3'b101: branch_taken = ($signed(rs1_value) >= $signed(rs2_value)); // BGE
                        3'b110: branch_taken = (rs1_value < rs2_value); // BLTU
                        3'b111: branch_taken = (rs1_value >= rs2_value); // BGEU
                        default: begin
                            valid_instruction = 1'b0;
                            branch_taken = 1'b0;
                        end
                    endcase

                    if (branch_taken)
                        exp_next_pc = exp_pc + model_imm;
                end

                // --------------------------------------------------------
                // JAL
                // --------------------------------------------------------
                7'b1101111: begin
                    exp_rd_addr = rd;
                    exp_rd_data = exp_pc + 32'd4;

                    model_imm = {
                        {11{exp_inst[31]}},
                        exp_inst[31],
                        exp_inst[19:12],
                        exp_inst[20],
                        exp_inst[30:21],
                        1'b0
                    };

                    exp_next_pc = exp_pc + model_imm;
                end

                // --------------------------------------------------------
                // JALR
                // --------------------------------------------------------
                7'b1100111: begin
                    exp_rs1_addr = rs1;
                    exp_rs1_data = rs1_value;
                    exp_rd_addr  = rd;
                    exp_rd_data  = exp_pc + 32'd4;

                    model_imm = {{20{exp_inst[31]}}, exp_inst[31:20]};
                    exp_next_pc = (rs1_value + model_imm) & 32'hFFFFFFFE;
                end

                // --------------------------------------------------------
                // SYSTEM: EBREAK
                // --------------------------------------------------------
                7'b1110011: begin
                    if (exp_inst == 32'h00100073) begin
                        exp_halt = 1'b1;
                    end
                    else begin
                        valid_instruction = 1'b0;
                        exp_trap = 1'b1;
                    end
                end

                default: begin
                    valid_instruction = 1'b0;
                    exp_trap = 1'b1;
                end
            endcase

            // Any invalid instruction is modeled as a trap with no side effects.
            if (!valid_instruction) begin
                exp_trap = 1'b1;
                exp_halt = 1'b0;
                exp_next_pc = exp_pc + 32'd4;
                exp_rs1_addr = 5'd0;
                exp_rs1_data = 32'd0;
                exp_rs2_addr = 5'd0;
                exp_rs2_data = 32'd0;
                exp_rd_addr = 5'd0;
                exp_rd_data = 32'd0;
                exp_dmem_ren = 1'b0;
                exp_dmem_wen = 1'b0;
                exp_dmem_mask = 4'b0000;
                exp_dmem_wdata = 32'd0;
            end

            // A trap suppresses all architectural side effects.
            if (exp_trap) begin
                exp_rd_addr = 5'd0;
                exp_rd_data = 32'd0;
                exp_dmem_ren = 1'b0;
                exp_dmem_wen = 1'b0;
                exp_dmem_mask = 4'b0000;
                exp_dmem_wdata = 32'd0;
                exp_next_pc = exp_pc + 32'd4;
            end

            // ------------------------------------------------------------
            // Compare the complete retire interface.
            // ------------------------------------------------------------
            if (!o_retire_valid) begin
                fail_count = fail_count + 1;
                $display("FAIL cycle=%0d: retire_valid is low after reset.", cycle_count);
            end

            if (o_retire_inst !== exp_inst)
                report_mismatch("retire_inst", exp_inst, o_retire_inst);

            if (o_retire_pc !== exp_pc)
                report_mismatch("retire_pc", exp_pc, o_retire_pc);

            if (o_retire_next_pc !== exp_next_pc)
                report_mismatch("next_pc", exp_next_pc, o_retire_next_pc);

            if (o_retire_trap !== exp_trap)
                report_mismatch("retire_trap", {31'd0, exp_trap},
                                {31'd0, o_retire_trap});

            if (o_retire_halt !== exp_halt)
                report_mismatch("retire_halt", {31'd0, exp_halt},
                                {31'd0, o_retire_halt});

            if (o_retire_rs1_raddr !== exp_rs1_addr)
                report_mismatch("rs1_addr", {27'd0, exp_rs1_addr},
                                {27'd0, o_retire_rs1_raddr});

            if (o_retire_rs1_rdata !== exp_rs1_data)
                report_mismatch("rs1_data", exp_rs1_data, o_retire_rs1_rdata);

            if (o_retire_rs2_raddr !== exp_rs2_addr)
                report_mismatch("rs2_addr", {27'd0, exp_rs2_addr},
                                {27'd0, o_retire_rs2_raddr});

            if (o_retire_rs2_rdata !== exp_rs2_data)
                report_mismatch("rs2_data", exp_rs2_data, o_retire_rs2_rdata);

            if (o_retire_rd_waddr !== exp_rd_addr)
                report_mismatch("rd_addr", {27'd0, exp_rd_addr},
                                {27'd0, o_retire_rd_waddr});

            if (exp_rd_addr != 5'd0 &&
                o_retire_rd_wdata !== exp_rd_data)
                report_mismatch("rd_data", exp_rd_data, o_retire_rd_wdata);

            // Data-memory interface is checked only when the instruction is
            // supposed to access memory. For non-memory instructions these
            // fields are intentionally treated as don't-care.
            if (o_dmem_ren !== exp_dmem_ren)
                report_mismatch("dmem_ren", {31'd0, exp_dmem_ren},
                                {31'd0, o_dmem_ren});

            if (o_dmem_wen !== exp_dmem_wen)
                report_mismatch("dmem_wen", {31'd0, exp_dmem_wen},
                                {31'd0, o_dmem_wen});

            if (exp_dmem_ren || exp_dmem_wen) begin
                if (o_dmem_addr !== exp_dmem_addr)
                    report_mismatch("dmem_addr", exp_dmem_addr, o_dmem_addr);

                if (o_dmem_mask !== exp_dmem_mask)
                    report_mismatch("dmem_mask", {28'd0, exp_dmem_mask},
                                    {28'd0, o_dmem_mask});

                if (o_dmem_wdata !== exp_dmem_wdata)
                    report_mismatch("dmem_wdata", exp_dmem_wdata, o_dmem_wdata);
            end

            // ------------------------------------------------------------
            // Update the golden architectural state AFTER checking the
            // current instruction.
            // ------------------------------------------------------------
            if (!exp_trap && !exp_halt) begin
                if (exp_rd_addr != 5'd0)
                    golden_regs[exp_rd_addr] = exp_rd_data;
            end

            // x0 is hardwired to zero.
            golden_regs[0] = 32'h00000000;

            // The DUT's store updates dmem at the following posedge. The
            // golden memory is updated here so it agrees by the next negedge.
            if (exp_dmem_wen && !exp_trap) begin
                if (exp_dmem_mask[0])
                    golden_dmem[exp_dmem_addr[9:2]][7:0] = exp_dmem_wdata[7:0];

                if (exp_dmem_mask[1])
                    golden_dmem[exp_dmem_addr[9:2]][15:8] = exp_dmem_wdata[15:8];

                if (exp_dmem_mask[2])
                    golden_dmem[exp_dmem_addr[9:2]][23:16] = exp_dmem_wdata[23:16];

                if (exp_dmem_mask[3])
                    golden_dmem[exp_dmem_addr[9:2]][31:24] = exp_dmem_wdata[31:24];
            end

            if (fail_count == 0)
                pass_count = pass_count + 1;

            // EBREAK is the intentional end of the test program.
            if (exp_halt)
                disable run_loop;
        end

        begin
            $display("");
            $display("============================================================");
            $display("TEST COMPLETE");
            $display("Cycles checked : %0d", cycle_count);
            $display("Passed vectors : %0d", pass_count);
            $display("Failures       : %0d", fail_count);
            $display("============================================================");

            if (fail_count == 0)
                $display("PASS: DUT matched the golden model on every checked vector.");
            else
                $display("FAIL: DUT did not match the golden model.");

            $finish;
        end
    end

endmodule

`default_nettype wire
