`timescale 1ns/1ps
`default_nettype none

// Phase 4 RV32I pipelined hart testbench.
// - Builds a directed + randomized instruction program (no external hex file).
// - Models instruction/data memory.
// - Uses an independent architectural golden model at retirement to check
//   PC flow, source operands, destination writes, arithmetic, loads/stores,
//   branches, and jumps.
// - Exercises RAW forwarding, load-use stalls, store-data forwarding, and flushes.
//
// Compile with the project RTL files, for example:
//   iverilog -g2012 -s tb -o simv tb.v hart.v alu.v imm.v rf.v decoder.v
//   vvp simv
//
// This is a simulation testbench; synthesizable-subset restrictions apply to RTL,
// not to this file.

module tb;

    localparam RESET_ADDR = 32'h0040_0000;
    localparam IMEM_WORDS = 512;
    localparam DMEM_WORDS = 256;
    localparam MAX_RETIRE = 2000;

    reg clk;
    reg rst;

    wire [31:0] imem_addr;
    reg  [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire        dmem_ren;
    wire        dmem_wen;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_mask;
    reg  [31:0] dmem_rdata;

    wire        retire_valid;
    wire [31:0] retire_inst;
    wire        retire_trap;
    wire        retire_halt;
    wire [4:0]  retire_rs1_addr;
    wire [31:0] retire_rs1_data;
    wire [4:0]  retire_rs2_addr;
    wire [31:0] retire_rs2_data;
    wire [4:0]  retire_rd_addr;
    wire [31:0] retire_rd_data;
    wire [31:0] retire_pc;
    wire [31:0] retire_next_pc;
    wire [31:0] retire_dmem_addr;
    wire        retire_dmem_ren;
    wire        retire_dmem_wen;
    wire [3:0]  retire_dmem_mask;
    wire [31:0] retire_dmem_wdata;
    wire [31:0] retire_dmem_rdata;

    hart #(.RESET_ADDR(RESET_ADDR)) dut (
        .i_clk(clk), .i_rst(rst),
        .o_imem_raddr(imem_addr), .i_imem_rdata(imem_rdata),
        .o_dmem_addr(dmem_addr), .o_dmem_ren(dmem_ren),
        .o_dmem_wen(dmem_wen), .o_dmem_wdata(dmem_wdata),
        .o_dmem_mask(dmem_mask), .i_dmem_rdata(dmem_rdata),
        .o_retire_valid(retire_valid), .o_retire_inst(retire_inst),
        .o_retire_trap(retire_trap), .o_retire_halt(retire_halt),
        .o_retire_rs1_raddr(retire_rs1_addr),
        .o_retire_rs1_rdata(retire_rs1_data),
        .o_retire_rs2_raddr(retire_rs2_addr),
        .o_retire_rs2_rdata(retire_rs2_data),
        .o_retire_rd_waddr(retire_rd_addr),
        .o_retire_rd_wdata(retire_rd_data),
        .o_retire_pc(retire_pc), .o_retire_next_pc(retire_next_pc),
        .o_retire_dmem_addr(retire_dmem_addr),
        .o_retire_dmem_ren(retire_dmem_ren),
        .o_retire_dmem_wen(retire_dmem_wen),
        .o_retire_dmem_mask(retire_dmem_mask),
        .o_retire_dmem_wdata(retire_dmem_wdata),
        .o_retire_dmem_rdata(retire_dmem_rdata)
    );

    reg [31:0] imem [0:IMEM_WORDS-1];
    reg [31:0] dmem [0:DMEM_WORDS-1];
    reg [31:0] golden_mem [0:DMEM_WORDS-1];
    reg [31:0] golden_regs [0:31];

    integer program_words;
    integer i, j, k;
    integer retired_count;
    integer errors;
    integer random_count;
    integer seed;
    reg finished;
    reg [31:0] expected_pc;
    reg [31:0] inst;
    reg [31:0] expected_rs1, expected_rs2, expected_result;
    reg [31:0] expected_next_pc;
    reg [31:0] imm_i, imm_s, imm_b, imm_j, imm_u;
    reg [31:0] addr;
    reg [31:0] old_word;
    reg [31:0] loaded;
    reg [4:0] rs1, rs2, rd;
    reg [6:0] opcode;
    reg [2:0] funct3;
    reg [6:0] funct7;
    reg [31:0] rand_a, rand_b;
    reg [31:0] temp_inst;

    // Clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // Combinational instruction/data reads.
    always @* begin
        if ((imem_addr >= RESET_ADDR) &&
            (((imem_addr - RESET_ADDR) >> 2) < IMEM_WORDS))
            imem_rdata = imem[(imem_addr - RESET_ADDR) >> 2];
        else
            imem_rdata = 32'h0010_0073; // EBREAK outside the program
    end

    always @* begin
        if ((dmem_addr >= 32'h0000_0100) &&
            (dmem_addr < 32'h0000_0500))
            dmem_rdata = dmem[(dmem_addr - 32'h0000_0100) >> 2];
        else
            dmem_rdata = 32'd0;
    end

    // Byte-lane writes for the DUT's data memory bus.
    always @(posedge clk) begin
        if (!rst && dmem_wen &&
            (dmem_addr >= 32'h0000_0100) &&
            (dmem_addr < 32'h0000_0500)) begin
            if (dmem_mask[0]) dmem[(dmem_addr - 32'h100) >> 2][7:0]   <= dmem_wdata[7:0];
            if (dmem_mask[1]) dmem[(dmem_addr - 32'h100) >> 2][15:8]  <= dmem_wdata[15:8];
            if (dmem_mask[2]) dmem[(dmem_addr - 32'h100) >> 2][23:16] <= dmem_wdata[23:16];
            if (dmem_mask[3]) dmem[(dmem_addr - 32'h100) >> 2][31:24] <= dmem_wdata[31:24];
        end
    end

    // Instruction encoders.
    function [31:0] enc_r;
        input [6:0] f7;
        input [4:0] r2;
        input [4:0] r1;
        input [2:0] f3;
        input [4:0] dest;
        input [6:0] opc;
        begin enc_r = {f7, r2, r1, f3, dest, opc}; end
    endfunction

    function [31:0] enc_i;
        input integer imm;
        input [4:0] r1;
        input [2:0] f3;
        input [4:0] dest;
        input [6:0] opc;
        begin enc_i = {imm[11:0], r1, f3, dest, opc}; end
    endfunction

    function [31:0] enc_s;
        input integer imm;
        input [4:0] r2;
        input [4:0] r1;
        input [2:0] f3;
        begin enc_s = {imm[11:5], r2, r1, f3, imm[4:0], 7'b0100011}; end
    endfunction

    function [31:0] enc_b;
        input integer imm;
        input [4:0] r2;
        input [4:0] r1;
        input [2:0] f3;
        begin enc_b = {imm[12], imm[10:5], r2, r1, f3, imm[4:1], imm[11], 7'b1100011}; end
    endfunction

    function [31:0] enc_u;
        input [19:0] imm;
        input [4:0] dest;
        input [6:0] opc;
        begin enc_u = {imm, dest, opc}; end
    endfunction

    function [31:0] enc_j;
        input integer imm;
        input [4:0] dest;
        begin enc_j = {imm[20], imm[10:1], imm[11], imm[19:12], dest, 7'b1101111}; end
    endfunction

    task emit;
        input [31:0] word;
        begin
            if (program_words < IMEM_WORDS) begin
                imem[program_words] = word;
                program_words = program_words + 1;
            end else begin
                $display("ERROR: instruction memory program overflow");
                $finish;
            end
        end
    endtask

    task emit_random_alu;
        integer op, a, b, d, imm;
        reg [31:0] rword;
        begin
            op = $random(seed) & 7;
            a = 1 + ($random(seed) & 30);
            b = 1 + ($random(seed) & 30);
            d = 2 + ($random(seed) & 29);
            imm = $random(seed) % 2048;
            case (op)
                0: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b000, d[4:0], 7'b0110011); // ADD
                1: rword = enc_r(7'b0100000, b[4:0], a[4:0], 3'b000, d[4:0], 7'b0110011); // SUB
                2: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b001, d[4:0], 7'b0110011); // SLL
                3: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b101, d[4:0], 7'b0110011); // SRL
                4: rword = enc_r(7'b0100000, b[4:0], a[4:0], 3'b101, d[4:0], 7'b0110011); // SRA
                5: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b010, d[4:0], 7'b0110011); // SLT
                6: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b011, d[4:0], 7'b0110011); // SLTU
                default: rword = enc_r(7'b0000000, b[4:0], a[4:0], 3'b100, d[4:0], 7'b0110011); // XOR
            endcase
            emit(rword);
            case (($random(seed) & 7))
                0: emit(enc_r(7'b0000000, b[4:0], a[4:0], 3'b110, d[4:0], 7'b0110011)); // OR
                1: emit(enc_r(7'b0000000, b[4:0], a[4:0], 3'b111, d[4:0], 7'b0110011)); // AND
                2: emit(enc_i(imm & 31, a[4:0], 3'b001, d[4:0], 7'b0010011)); // SLLI
                3: emit(enc_i(imm & 31, a[4:0], 3'b101, d[4:0], 7'b0010011)); // SRLI
                4: emit(enc_i((imm & 31) | 12'h400, a[4:0], 3'b101, d[4:0], 7'b0010011)); // SRAI
                5: emit(enc_i(imm, a[4:0], 3'b000, d[4:0], 7'b0010011)); // ADDI
                6: emit(enc_i(imm, a[4:0], 3'b010, d[4:0], 7'b0010011)); // SLTI
                default: emit(enc_i(imm, a[4:0], 3'b011, d[4:0], 7'b0010011)); // SLTIU
            endcase
        end
    endtask

    // Build a deterministic directed prologue, then randomized operations.
    // x1 is kept as a stable base pointer into data memory (0x100).
    task build_program;
        integer n, r1, r2, rd, off;
        reg [31:0] r;
        begin
            program_words = 0;
            emit(enc_i(256, 5'd0, 3'b000, 5'd1, 7'b0010011)); // addi x1,x0,256
            emit(enc_i(123, 5'd0, 3'b000, 5'd2, 7'b0010011)); // addi x2,x0,123
            emit(enc_i(-77, 5'd0, 3'b000, 5'd3, 7'b0010011)); // addi x3,x0,-77
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b000, 5'd4, 7'b0110011)); // add
            emit(enc_r(7'b0100000, 5'd3, 5'd2, 3'b000, 5'd5, 7'b0110011)); // sub
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b001, 5'd6, 7'b0110011)); // sll
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b101, 5'd7, 7'b0110011)); // srl
            emit(enc_r(7'b0100000, 5'd3, 5'd2, 3'b101, 5'd8, 7'b0110011)); // sra
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b010, 5'd9, 7'b0110011)); // slt
            emit(enc_r(7'b0000000, 5'd3, 5'd2, 3'b011, 5'd10, 7'b0110011)); // sltu
            emit(enc_u(20'h12345, 5'd11, 7'b0110111)); // lui
            emit(enc_u(20'h00012, 5'd12, 7'b0010111)); // auipc
            emit(enc_s(0, 5'd2, 5'd1, 3'b010)); // sw x2,0(x1)
            emit(enc_i(0, 5'd1, 3'b010, 5'd13, 7'b0000011)); // lw x13,0(x1)
            emit(enc_r(7'b0000000, 5'd13, 5'd13, 3'b000, 5'd14, 7'b0110011)); // immediate load-use RAW
            emit(enc_s(4, 5'd14, 5'd1, 3'b010)); // sw x14,4(x1), store forwarding
            emit(enc_i(4, 5'd1, 3'b010, 5'd15, 7'b0000011)); // lw x15,4(x1)
            emit(enc_i(1, 5'd0, 3'b000, 5'd16, 7'b0010011)); // addi x16,x0,1
            emit(enc_b(8, 5'd16, 5'd16, 3'b000)); // beq x16,x16,+8 (taken)
            emit(enc_i(999, 5'd0, 3'b000, 5'd17, 7'b0010011)); // flushed instruction
            emit(enc_i(7, 5'd0, 3'b000, 5'd17, 7'b0010011)); // target
            emit(enc_b(8, 5'd16, 5'd0, 3'b000)); // beq x0,x16,+8 (not taken)
            emit(enc_i(-1, 5'd17, 3'b000, 5'd18, 7'b0010011)); // addi
            emit(enc_j(8, 5'd19)); // jal x19,+8 (skip one)
            emit(enc_i(555, 5'd0, 3'b000, 5'd20, 7'b0010011)); // flushed
            emit(enc_i(22, 5'd0, 3'b000, 5'd20, 7'b0010011)); // jal target

            for (n = 0; n < 120; n = n + 1) begin
                emit_random_alu();
                // Keep a stable base in x1; random load/store offsets stay in range.
                r1 = 1 + ($random(seed) & 30);
                r2 = 1 + ($random(seed) & 30);
                rd = 2 + ($random(seed) & 29);
                off = ($random(seed) & 31) * 4;
                case ($random(seed) & 3)
                    0: emit(enc_s(off, r2[4:0], 5'd1, 3'b010)); // sw
                    1: emit(enc_i(off, 5'd1, 3'b010, rd[4:0], 7'b0000011)); // lw
                    2: emit(enc_i(off, 5'd1, 3'b000, rd[4:0], 7'b0000011)); // lb
                    default: emit(enc_i(off, 5'd1, 3'b100, rd[4:0], 7'b0000011)); // lbu
                endcase
            end
            emit(32'h0010_0073); // ebreak
        end
    endtask

    // Golden-model retirement checker. Architectural state is updated only
    // when an instruction retires, independent of the DUT's internal pipeline.
    task check_retirement;
        integer index;
        reg [31:0] calculated;
        reg [31:0] effective_addr;
        reg [31:0] memory_word;
        reg [7:0] byte_value;
        reg [15:0] half_value;
        reg [31:0] target;
        reg write_rd;
        reg read_rs1;
        reg read_rs2;
        reg is_load;
        reg is_store;
        reg [3:0] expected_mask;
        reg [31:0] expected_store_data;
        begin
            inst = retire_inst;
            opcode = inst[6:0];
            rd = inst[11:7];
            funct3 = inst[14:12];
            rs1 = inst[19:15];
            rs2 = inst[24:20];
            funct7 = inst[31:25];

            imm_i = {{20{inst[31]}}, inst[31:20]};
            imm_s = {{20{inst[31]}}, inst[31:25], inst[11:7]};
            imm_b = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
            imm_u = {inst[31:12], 12'b0};
            imm_j = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};

            expected_rs1 = (rs1 == 0) ? 32'd0 : golden_regs[rs1];
            expected_rs2 = (rs2 == 0) ? 32'd0 : golden_regs[rs2];
            expected_next_pc = retire_pc + 32'd4;
            calculated = 32'd0;
            write_rd = 1'b0;
            read_rs1 = 1'b0;
            read_rs2 = 1'b0;
            is_load = 1'b0;
            is_store = 1'b0;
            expected_mask = 4'b0000;
            expected_store_data = 32'd0;
            effective_addr = 32'd0;

            case (opcode)
                7'b0110011: begin // R-type arithmetic
                    read_rs1 = 1'b1; read_rs2 = 1'b1; write_rd = (rd != 0);
                    case (funct3)
                        3'b000: calculated = (funct7[5]) ? (expected_rs1 - expected_rs2) : (expected_rs1 + expected_rs2);
                        3'b001: calculated = expected_rs1 << expected_rs2[4:0];
                        3'b010: calculated = ($signed(expected_rs1) < $signed(expected_rs2)) ? 1 : 0;
                        3'b011: calculated = (expected_rs1 < expected_rs2) ? 1 : 0;
                        3'b100: calculated = expected_rs1 ^ expected_rs2;
                        3'b101: calculated = funct7[5] ? ($signed(expected_rs1) >>> expected_rs2[4:0]) : (expected_rs1 >> expected_rs2[4:0]);
                        3'b110: calculated = expected_rs1 | expected_rs2;
                        3'b111: calculated = expected_rs1 & expected_rs2;
                    endcase
                end
                7'b0010011: begin // I-type ALU
                    read_rs1 = 1'b1; write_rd = (rd != 0);
                    case (funct3)
                        3'b000: calculated = expected_rs1 + imm_i;
                        3'b010: calculated = ($signed(expected_rs1) < $signed(imm_i)) ? 1 : 0;
                        3'b011: calculated = (expected_rs1 < imm_i) ? 1 : 0;
                        3'b100: calculated = expected_rs1 ^ imm_i;
                        3'b110: calculated = expected_rs1 | imm_i;
                        3'b111: calculated = expected_rs1 & imm_i;
                        3'b001: calculated = expected_rs1 << inst[24:20];
                        3'b101: calculated = inst[30] ? ($signed(expected_rs1) >>> inst[24:20]) : (expected_rs1 >> inst[24:20]);
                    endcase
                end
                7'b0110111: begin calculated = imm_u; write_rd = (rd != 0); end // LUI
                7'b0010111: begin calculated = retire_pc + imm_u; write_rd = (rd != 0); end // AUIPC
                7'b0000011: begin // loads
                    read_rs1 = 1'b1; write_rd = (rd != 0); is_load = 1'b1;
                    effective_addr = expected_rs1 + imm_i;
                    index = (effective_addr - 32'h100) >> 2;
                    if ((effective_addr < 32'h100) || (effective_addr >= 32'h500)) begin
                        $display("ERROR: generated load address out of range: %08x", effective_addr);
                        errors = errors + 1;
                        calculated = 0;
                    end else begin
                        memory_word = golden_mem[index];
                        case (funct3)
                            3'b000: begin
                                case (effective_addr[1:0])
                                    0: byte_value = memory_word[7:0];
                                    1: byte_value = memory_word[15:8];
                                    2: byte_value = memory_word[23:16];
                                    3: byte_value = memory_word[31:24];
                                endcase
                                calculated = {{24{byte_value[7]}}, byte_value};
                            end
                            3'b100: begin
                                case (effective_addr[1:0])
                                    0: byte_value = memory_word[7:0];
                                    1: byte_value = memory_word[15:8];
                                    2: byte_value = memory_word[23:16];
                                    3: byte_value = memory_word[31:24];
                                endcase
                                calculated = {24'd0, byte_value};
                            end
                            3'b001: begin
                                half_value = effective_addr[1] ? memory_word[31:16] : memory_word[15:0];
                                calculated = {{16{half_value[15]}}, half_value};
                            end
                            3'b101: begin
                                half_value = effective_addr[1] ? memory_word[31:16] : memory_word[15:0];
                                calculated = {16'd0, half_value};
                            end
                            default: calculated = memory_word;
                        endcase
                    end
                end
                7'b0100011: begin // stores
                    read_rs1 = 1'b1; read_rs2 = 1'b1; is_store = 1'b1;
                    effective_addr = expected_rs1 + imm_s;
                    case (funct3)
                        3'b000: begin
                            expected_mask = 4'b0001 << effective_addr[1:0];
                            expected_store_data = {4{expected_rs2[7:0]}};
                        end
                        3'b001: begin
                            expected_mask = effective_addr[1] ? 4'b1100 : 4'b0011;
                            expected_store_data = {2{expected_rs2[15:0]}};
                        end
                        default: begin expected_mask = 4'b1111; expected_store_data = expected_rs2; end
                    endcase
                end
                7'b1100011: begin // conditional branches
                    read_rs1 = 1'b1; read_rs2 = 1'b1;
                    case (funct3)
                        3'b000: if (expected_rs1 == expected_rs2) expected_next_pc = retire_pc + imm_b; // BEQ
                        3'b001: if (expected_rs1 != expected_rs2) expected_next_pc = retire_pc + imm_b; // BNE
                        3'b100: if ($signed(expected_rs1) < $signed(expected_rs2)) expected_next_pc = retire_pc + imm_b; // BLT
                        3'b101: if ($signed(expected_rs1) >= $signed(expected_rs2)) expected_next_pc = retire_pc + imm_b; // BGE
                        3'b110: if (expected_rs1 < expected_rs2) expected_next_pc = retire_pc + imm_b; // BLTU
                        3'b111: if (expected_rs1 >= expected_rs2) expected_next_pc = retire_pc + imm_b; // BGEU
                    endcase
                end
                7'b1101111: begin // JAL
                    calculated = retire_pc + 32'd4; write_rd = (rd != 0);
                    expected_next_pc = retire_pc + imm_j;
                end
                7'b1100111: begin // JALR
                    read_rs1 = 1'b1; calculated = retire_pc + 32'd4; write_rd = (rd != 0);
                    expected_next_pc = (expected_rs1 + imm_i) & 32'hffff_fffe;
                end
                7'b1110011: begin // EBREAK
                    // The program's only system instruction is EBREAK.
                end
                default: begin
                    $display("ERROR: golden model encountered unsupported opcode %07b at PC %08x", opcode, retire_pc);
                    errors = errors + 1;
                end
            endcase

            if (retire_pc !== expected_pc) begin
                $display("FAIL retire %0d: PC expected %08x got %08x", retired_count, expected_pc, retire_pc);
                errors = errors + 1;
            end
            if (retire_next_pc !== expected_next_pc) begin
                $display("FAIL PC+next expected %08x got %08x for inst %08x at %08x",
                         expected_next_pc, retire_next_pc, inst, retire_pc);
                errors = errors + 1;
            end

            if (read_rs1 && (retire_rs1_addr !== rs1)) begin
                $display("FAIL rs1 address at PC %08x: expected %0d got %0d", retire_pc, rs1, retire_rs1_addr);
                errors = errors + 1;
            end
            if (!read_rs1 && (retire_rs1_addr !== 5'd0)) begin
                $display("FAIL unexpected rs1 read at PC %08x: got %0d", retire_pc, retire_rs1_addr);
                errors = errors + 1;
            end
            if (read_rs1 && (retire_rs1_data !== expected_rs1)) begin
                $display("FAIL rs1 data at PC %08x: expected %08x got %08x", retire_pc, expected_rs1, retire_rs1_data);
                errors = errors + 1;
            end
            if (read_rs2 && (retire_rs2_addr !== rs2)) begin
                $display("FAIL rs2 address at PC %08x: expected %0d got %0d", retire_pc, rs2, retire_rs2_addr);
                errors = errors + 1;
            end
            if (!read_rs2 && (retire_rs2_addr !== 5'd0)) begin
                $display("FAIL unexpected rs2 read at PC %08x: got %0d", retire_pc, retire_rs2_addr);
                errors = errors + 1;
            end
            if (read_rs2 && (retire_rs2_data !== expected_rs2)) begin
                $display("FAIL rs2 data at PC %08x: expected %08x got %08x", retire_pc, expected_rs2, retire_rs2_data);
                errors = errors + 1;
            end

            if (retire_trap !== 1'b0) begin
                $display("FAIL unexpected trap at PC %08x instruction %08x", retire_pc, inst);
                errors = errors + 1;
            end

            if (write_rd) begin
                if (retire_rd_addr !== rd) begin
                    $display("FAIL rd address at PC %08x: expected %0d got %0d", retire_pc, rd, retire_rd_addr);
                    errors = errors + 1;
                end
                if (retire_rd_data !== calculated) begin
                    $display("FAIL rd data at PC %08x inst %08x: expected %08x got %08x",
                             retire_pc, inst, calculated, retire_rd_data);
                    errors = errors + 1;
                end
                golden_regs[rd] = calculated;
            end else begin
                if (retire_rd_addr !== 5'd0) begin
                    $display("FAIL unexpected rd write at PC %08x: got x%0d", retire_pc, retire_rd_addr);
                    errors = errors + 1;
                end
            end

            // Check memory-side retirement metadata. Stores update golden memory
            // in retirement order, so later loads see the architectural value.
            if (is_load) begin
                if (retire_dmem_ren !== 1'b1 || retire_dmem_wen !== 1'b0) begin
                    $display("FAIL load memory enables at PC %08x", retire_pc);
                    errors = errors + 1;
                end
                if (retire_dmem_addr !== {effective_addr[31:2], 2'b00}) begin
                    $display("FAIL load address at PC %08x expected %08x got %08x", retire_pc,
                             {effective_addr[31:2], 2'b00}, retire_dmem_addr);
                    errors = errors + 1;
                end
                if (retire_dmem_rdata !== golden_mem[(effective_addr - 32'h100) >> 2]) begin
                    $display("FAIL load raw word at PC %08x expected %08x got %08x", retire_pc,
                             golden_mem[(effective_addr - 32'h100) >> 2], retire_dmem_rdata);
                    errors = errors + 1;
                end
            end else if (is_store) begin
                if (retire_dmem_wen !== 1'b1 || retire_dmem_ren !== 1'b0) begin
                    $display("FAIL store memory enables at PC %08x", retire_pc);
                    errors = errors + 1;
                end
                if (retire_dmem_addr !== {effective_addr[31:2], 2'b00}) begin
                    $display("FAIL store address at PC %08x", retire_pc);
                    errors = errors + 1;
                end
                if (retire_dmem_mask !== expected_mask) begin
                    $display("FAIL store mask at PC %08x expected %b got %b", retire_pc, expected_mask, retire_dmem_mask);
                    errors = errors + 1;
                end
                if (retire_dmem_wdata !== expected_store_data) begin
                    $display("FAIL store data at PC %08x expected %08x got %08x", retire_pc, expected_store_data, retire_dmem_wdata);
                    errors = errors + 1;
                end
                index = (effective_addr - 32'h100) >> 2;
                old_word = golden_mem[index];
                case (expected_mask)
                    4'b0001: golden_mem[index] = {old_word[31:8], expected_store_data[7:0]};
                    4'b0010: golden_mem[index] = {old_word[31:16], expected_store_data[15:8], old_word[7:0]};
                    4'b0100: golden_mem[index] = {old_word[31:24], expected_store_data[23:16], old_word[15:0]};
                    4'b1000: golden_mem[index] = {expected_store_data[31:24], old_word[23:0]};
                    4'b0011: golden_mem[index] = {old_word[31:16], expected_store_data[15:0]};
                    4'b1100: golden_mem[index] = {expected_store_data[15:0], old_word[15:0]};
                    default: golden_mem[index] = expected_store_data;
                endcase
            end else begin
                if (retire_dmem_ren !== 1'b0 || retire_dmem_wen !== 1'b0) begin
                    $display("FAIL unexpected memory operation at PC %08x", retire_pc);
                    errors = errors + 1;
                end
            end

            if (retire_halt) begin
                if (opcode !== 7'b1110011) begin
                    $display("FAIL halt asserted for non-system instruction at PC %08x", retire_pc);
                    errors = errors + 1;
                end
                finished = 1'b1;
            end

            expected_pc = expected_next_pc;
            retired_count = retired_count + 1;
        end
    endtask

    // Retire outputs are sampled on the falling edge, away from DUT NBAs.
    always @(negedge clk) begin
        if (!rst && retire_valid && !finished) begin
            check_retirement;
        end
    end

    initial begin
        errors = 0;
        retired_count = 0;
        random_count = 0;
        seed = 32'h5eed1234;
        finished = 1'b0;
        expected_pc = RESET_ADDR;
        rst = 1'b1;

        for (i = 0; i < IMEM_WORDS; i = i + 1)
            imem[i] = 32'h0010_0073; // ebreak padding
        for (i = 0; i < DMEM_WORDS; i = i + 1) begin
            dmem[i] = 32'd0;
            golden_mem[i] = 32'd0;
        end
        for (i = 0; i < 32; i = i + 1)
            golden_regs[i] = 32'd0;

        // Deterministic initial data lets loads exercise positive, negative,
        // all-zero, all-one, and mixed-bit patterns.
        dmem[0] = 32'h8000_00ff;
        dmem[1] = 32'h7fff_8001;
        dmem[2] = 32'hffff_ffff;
        dmem[3] = 32'h0000_0000;
        dmem[4] = 32'ha5a5_5a5a;
        dmem[5] = 32'h1234_5678;
        dmem[6] = 32'hdead_beef;
        dmem[7] = 32'h0102_0304;
        for (i = 0; i < DMEM_WORDS; i = i + 1)
            golden_mem[i] = dmem[i];

        build_program;

        $display("Built %0d instructions. Starting Phase 4 golden-model test.", program_words);
        repeat (4) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // A watchdog prevents a broken pipeline from hanging simulation forever.
        for (i = 0; i < MAX_RETIRE; i = i + 1) begin
            @(negedge clk);
            if (finished) i = MAX_RETIRE;
        end

        if (!finished) begin
            $display("FAIL: watchdog expired before EBREAK retired.");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: %0d retired instructions checked with zero mismatches.", retired_count);
        else
            $display("FAIL: %0d mismatches across %0d retired instructions.", errors, retired_count);

        $finish;
    end

endmodule

`default_nettype wire
