// AI USE DISCLOSURE:
// Chat GPT was used to help type redunant parts of the code.
// Accessed November 2026.
`default_nettype none

module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00400000,
    // When set, register file bypassing is enabled.
    parameter BYPASS_EN = 1,
    // Configuration for the Phase 5 data cache.
    parameter EVICT_POLICY = 0,
    parameter NUM_WAYS     = 1,
    parameter CACHE_SIZE   = 16,
    parameter BLOCK_SIZE   = 128,
    parameter PREFETCH_EN  = 0,
    parameter WRITE_ALLOCATE = 0
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    output wire [31:0] o_imem_raddr,
    input wire [31:0] i_imem_rdata,
    input wire i_mem_ready,
    input wire i_mem_valid,
    input wire [BLOCK_SIZE*8-1:0] i_mem_rd_data,
    output wire o_mem_rd,
    output wire o_mem_wr,
    output wire [31:0] o_mem_rd_addr,
    output wire [31:0] o_mem_wr_addr,
    output wire [BLOCK_SIZE*8-1:0] o_mem_wr_data,
    output wire [BLOCK_SIZE-1:0] o_mem_wr_be,
    // The output `retire` interface is used to signal to the testbench that
    // the CPU has completed and retired an instruction. A single cycle
    // implementation will assert this every cycle; however, a pipelined
    // implementation that needs to stall (due to internal hazards or waiting
    // on memory accesses) will not assert the signal on cycles where the
    // instruction in the writeback stage is not retiring.
    //
    // Asserted when an instruction is being retired this cycle. If this is
    // not asserted, the other retire signals are ignored and may be left invalid.
    output wire        o_retire_valid,
    // The 32 bit instruction word of the instrution being retired. This
    // should be the unmodified instruction word fetched from instruction
    // memory.
    output wire [31:0] o_retire_inst,
    // Asserted if the instruction produced a trap, due to an illegal
    // instruction, unaligned data memory access, or unaligned instruction
    // address on a taken branch or jump.
    output wire        o_retire_trap,
    // Asserted if the instruction is an `ebreak` instruction used to halt the
    // processor. This is used for debugging and testing purposes to end
    // a program.
    output wire        o_retire_halt,
    // The first register address read by the instruction being retired. If
    // the instruction does not read from a register (like `lui`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs1_raddr,
    // The second register address read by the instruction being retired. If
    // the instruction does not read from a second register (like `addi`), this
    // should be 5'd0.
    output wire [ 4:0] o_retire_rs2_raddr,
    // The first source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs1 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs1_rdata,
    // The second source register data read from the register file (in the
    // decode stage) for the instruction being retired. If rs2 is 5'd0, this
    // should also be 32'd0.
    output wire [31:0] o_retire_rs2_rdata,
    // The destination register address written by the instruction being
    // retired. If the instruction does not write to a register (like `sw`),
    // this should be 5'd0.
    output wire [ 4:0] o_retire_rd_waddr,
    // The destination register data written to the register file in the
    // writeback stage by this instruction. If rd is 5'd0, this field is
    // ignored and can be treated as a don't care.
    output wire [31:0] o_retire_rd_wdata,
    output wire [31:0] o_retire_dmem_addr,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [31:0] o_retire_dmem_rdata,
    output wire [31:0] o_retire_dmem_wdata,
    // The current program counter of the instruction being retired - i.e.
    // the instruction memory address that the instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // the next program counter after the instruction is retired. For most
    // instructions, this is `o_retire_pc + 4`, but must be the branch or jump
    // target for *taken* branches and jumps.
    output wire [31:0] o_retire_next_pc,
    output wire o_complete_valid,
    output wire [2:0] o_complete_tag,
    output wire [4:0] o_complete_rd,
    output wire [31:0] o_complete_value,
    output wire [31:0] o_complete_pc,
    // Phase 6: FP sources, destination and accrued flags at retirement.
    output wire [4:0] o_retire_frs1_raddr,
    output wire [31:0] o_retire_frs1_rdata,
    output wire [4:0] o_retire_frs2_raddr,
    output wire [31:0] o_retire_frs2_rdata,
    output wire [4:0] o_retire_frs3_raddr,
    output wire [31:0] o_retire_frs3_rdata,
    output wire o_retire_frd_wen,
    output wire [4:0] o_retire_frd_waddr,
    output wire [31:0] o_retire_frd_wdata,
    output wire [4:0] o_retire_fflags

`ifdef RISCV_FORMAL
    ,`RVFI_OUTPUTS,
`endif
);

    reg [31:0] pc, id_pc, if_id_inst;
    reg id_valid, control_pending, halted;

    wire dec_legal, dec_halt, dec_op1_sel, dec_op2_sel;
    wire [4:0] dec_rs1, dec_rs2, dec_rd, dec_rd_sel, dec_rs3;
    wire [31:0] dec_imm;
    wire [2:0] dec_alu_opsel;
    wire dec_alu_sub, dec_alu_unsigned, dec_alu_arith;
    wire dec_branch, dec_jump, dec_branch_equal, dec_branch_unsigned;
    wire dec_branch_invert, dec_pc_sel;
    wire dec_dmem_ren, dec_dmem_wen, dec_dmem_memb, dec_dmem_memh;
    wire dec_dmem_memw, dec_dmem_memu;
    wire [1:0] dec_dmem_align;
    wire dec_mext, dec_fpu, dec_frs1, dec_frs2, dec_frs3, dec_frd;

    decoder u_decoder (
        .i_inst            (if_id_inst),
        .o_legal           (dec_legal),
        .o_halt            (dec_halt),
        .o_rs1             (dec_rs1),
        .o_rs2             (dec_rs2),
        .o_rd              (dec_rd),
        .o_immediate       (dec_imm),
        .o_op1_sel         (dec_op1_sel),
        .o_op2_sel         (dec_op2_sel),
        .o_alu_opsel       (dec_alu_opsel),
        .o_alu_sub         (dec_alu_sub),
        .o_alu_unsigned    (dec_alu_unsigned),
        .o_alu_arith       (dec_alu_arith),
        .o_branch          (dec_branch),
        .o_jump            (dec_jump),
        .o_branch_equal    (dec_branch_equal),
        .o_branch_unsigned (dec_branch_unsigned),
        .o_branch_invert   (dec_branch_invert),
        .o_dmem_ren        (dec_dmem_ren),
        .o_dmem_wen        (dec_dmem_wen),
        .o_dmem_align      (dec_dmem_align),
        .o_dmem_memb       (dec_dmem_memb),
        .o_dmem_memh       (dec_dmem_memh),
        .o_dmem_memw       (dec_dmem_memw),
        .o_dmem_memu       (dec_dmem_memu),
        .o_rd_sel          (dec_rd_sel),
        .o_mext(dec_mext), .o_fpu(dec_fpu),
        .o_frs1_en(dec_frs1), .o_frs2_en(dec_frs2), .o_frs3_en(dec_frs3),
        .o_frd_en(dec_frd), .o_rs3(dec_rs3),
        .o_pc_sel          (dec_pc_sel)
    );

    // The ROB tag indexes stored instruction metadata. The reservation station
    // uses the same indices and admits at most four undispatched integer ops.
    reg [2:0] head, tail;
    reg [3:0] used, waiting_count;
    reg [7:0] live, done, waiting, memory_op, store_op, trap, halt;
    reg [31:0] inst [0:7], instr_pc [0:7], next_pc [0:7];
    reg [31:0] imm [0:7], value [0:7], lhs [0:7], rhs [0:7];
    reg [4:0] rs1 [0:7], rs2 [0:7], rd [0:7], result_select [0:7];
    reg [2:0] lhs_tag [0:7], rhs_tag [0:7], alu_op [0:7];
    reg [7:0] lhs_wait, rhs_wait, pc_operand, imm_operand;
    reg [7:0] alu_sub, alu_unsigned, alu_arith, mext;
    reg [7:0] branch, jump, branch_eq, branch_invert, indirect;
    reg [7:0] byte_access, half_access, unsigned_load;
    reg [1:0] alignment [0:7];
    reg [31:0] mem_addr [0:7], mem_bus_data [0:7];
    reg [3:0] mem_mask [0:7];

    reg [7:0] fp_waiting, fp_execute, fp_csr, fp_writes;
    reg [7:0] use_fp1, use_fp2, use_fp3, third_wait;
    reg [4:0] fp_rd [0:7], fp_src3 [0:7];
    reg [2:0] third_tag [0:7];
    reg [31:0] third [0:7];
    reg [7:0] shared_fcsr;
    reg [7:0] fp_csr_result [0:7];
    reg [4:0] fp_flags [0:7];

    wire issue_trap = !dec_legal;
    wire issue_mem = dec_legal && (dec_dmem_ren || dec_dmem_wen);
    wire issue_fp = dec_legal && dec_fpu;
    wire issue_int = dec_legal && !dec_halt && !issue_mem && !issue_fp;
    wire [4:0] issue_rd = issue_trap ? 5'd0 : dec_rd;

    wire dispatch;
    wire int_map1, int_map2;
    wire [2:0] int_tag1, int_tag2;
    wire [31:0] rf1, rf2, fp1, fp2, fp3;
    wire [4:0] xrs1 = dec_frs1 ? 5'd0 : dec_rs1;
    wire [4:0] xrs2 = dec_frs2 ? 5'd0 : dec_rs2;
    wire recover_int = o_retire_valid && trap[head] && rd[head] != 5'd0;
    wire recover_fp = o_retire_valid && trap[head] && fp_writes[head];
    wire recover = recover_int || recover_fp;
    wire [31:0] recovery_value = recover_fp ? fp1 : rf1;

    // Search from the youngest allocated ROB slot for each FP producer.
    // Unlike x0, f0 participates in dependency tracking and writeback.
    wire [7:0] fp_match1, fp_match2, fp_match3;
    wire [7:0] fp_pick1, fp_pick2, fp_pick3;
    wire [2:0] recent_tag [0:7];
    genvar recent;
    generate
        for (recent = 0; recent < 8; recent = recent + 1) begin : fp_rename
            localparam [2:0] BACK = recent;
            localparam [7:0] NEWER = (8'b1 << recent) - 8'b1;
            wire [2:0] slot = tail - 3'd1 - BACK;
            wire writer = live[slot] && fp_writes[slot];
            assign recent_tag[recent] = slot;
            assign fp_match1[recent] = writer && fp_rd[slot] == dec_rs1;
            assign fp_match2[recent] = writer && fp_rd[slot] == dec_rs2;
            assign fp_match3[recent] = writer && fp_rd[slot] == dec_rs3;
            assign fp_pick1[recent] = fp_match1[recent] && !(|(fp_match1 & NEWER));
            assign fp_pick2[recent] = fp_match2[recent] && !(|(fp_match2 & NEWER));
            assign fp_pick3[recent] = fp_match3[recent] && !(|(fp_match3 & NEWER));
        end
    endgenerate

    wire map1 = dec_frs1 ? (|fp_pick1) : int_map1;
    wire map2 = dec_frs2 ? (|fp_pick2) : int_map2;
    wire map3 = dec_frs3 && (|fp_pick3);
    wire [2:0] fp_pick1_index = {(|fp_pick1[7:4]), (|(fp_pick1 & 8'hcc)), (|(fp_pick1 & 8'haa))};
    wire [2:0] tag1 = dec_frs1 ? recent_tag[fp_pick1_index] : int_tag1;
    wire [2:0] fp_pick2_index = {(|fp_pick2[7:4]), (|(fp_pick2 & 8'hcc)), (|(fp_pick2 & 8'haa))};
    wire [2:0] tag2 = dec_frs2 ? recent_tag[fp_pick2_index] : int_tag2;
    wire [2:0] fp_pick3_index = {(|fp_pick3[7:4]), (|(fp_pick3 & 8'hcc)), (|(fp_pick3 & 8'haa))};
    wire [2:0] tag3 = recent_tag[fp_pick3_index];
    wire bypass1 = map1 && o_complete_valid && o_complete_tag == tag1;
    wire bypass2 = map2 && o_complete_valid && o_complete_tag == tag2;
    wire bypass3 = map3 && o_complete_valid && o_complete_tag == tag3;
    // A failed writer has no CDB value. Keep its consumers waiting until
    // retirement, when the RF holds the most recent successful older write.
    wire pending1 = map1 && (!done[tag1] || trap[tag1]) && !bypass1;
    wire pending2 = map2 && (!done[tag2] || trap[tag2]) && !bypass2;
    wire pending3 = map3 && (!done[tag3] || trap[tag3]) && !bypass3;
    wire issue = id_valid && !control_pending && !halted && !i_rst && !recover &&
                 ((used < 4'd8) || o_retire_valid) &&
                 (!issue_int || (waiting_count < 4'd4) || dispatch);

    rat u_rat (
        .i_clk(i_clk), .i_rst(i_rst), .i_rs1(xrs1), .i_rs2(xrs2),
        .o_rs1_mapped(int_map1), .o_rs2_mapped(int_map2),
        .o_rs1_tag(int_tag1), .o_rs2_tag(int_tag2),
        .i_rename_valid(issue), .i_rename_rd(issue_rd), .i_rename_tag(tail),
        .i_retire_valid(o_retire_valid), .i_retire_rd(rd[head]),
        .i_retire_tag(head)
    );

    rf #(.BYPASS_EN(BYPASS_EN)) u_rf (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_rs1_raddr(recover_int ? rd[head] : xrs1), .i_rs2_raddr(xrs2),
        .o_rs1_rdata(rf1), .o_rs2_rdata(rf2),
        .i_rd_waddr(o_retire_valid ? o_retire_rd_waddr : 5'd0),
        .i_rd_wdata(o_retire_rd_wdata),
        .i_frs1_raddr(recover_fp ? fp_rd[head] : dec_rs1),
        .i_frs2_raddr(dec_rs2), .i_frs3_raddr(dec_rs3),
        .o_frs1_rdata(fp1), .o_frs2_rdata(fp2), .o_frs3_rdata(fp3),
        .i_frd_wen(o_retire_frd_wen),
        .i_frd_waddr(o_retire_frd_waddr), .i_frd_wdata(o_retire_frd_wdata)
    );

    // Select the oldest ready integer op and the oldest unfinished memory op.
    // Memory selection deliberately ignores operand readiness.
    wire [7:0] int_pick, mem_pick, fp_pick, fp_ready, csr_live;
    wire [2:0] age_tag [0:7];
    wire [7:0] int_ready, mem_pending;
    genvar age;
    generate
        for (age = 0; age < 8; age = age + 1) begin : select_by_age
            localparam [2:0] OFFSET = age;
            localparam [7:0] OLDER = (8'b1 << age) - 8'b1;
            wire [2:0] slot = head + OFFSET;
            assign age_tag[age] = slot;
            assign int_ready[age] = waiting[slot] &&
                                    !lhs_wait[slot] && !rhs_wait[slot];
            assign mem_pending[age] = live[slot] && memory_op[slot] &&
                                      (!done[slot] || (store_op[slot] && !trap[slot]));
            assign csr_live[age] = live[slot] && fp_csr[slot];
            assign fp_ready[age] = fp_waiting[slot] &&
                                   !lhs_wait[slot] && !rhs_wait[slot] && !third_wait[slot] &&
                                   !(|(csr_live & OLDER)) && (!fp_csr[slot] || slot == head);
            assign fp_pick[age] = fp_ready[age] && !(|(fp_ready & OLDER));
            assign int_pick[age] = int_ready[age] && !(|(int_ready & OLDER));
            assign mem_pick[age] = mem_pending[age] && !(|(mem_pending & OLDER));
        end
    endgenerate

    reg alu_locked, alu_pending;
    reg [2:0] locked_tag, alu_tag;
    reg [31:0] alu_value;
    wire [2:0] int_pick_index = {(|int_pick[7:4]), (|(int_pick & 8'hcc)), (|(int_pick & 8'haa))};
    wire [2:0] exec_tag = alu_locked ? locked_tag : age_tag[int_pick_index];
    wire [2:0] mem_pick_index = {(|mem_pick[7:4]), (|(mem_pick & 8'hcc)), (|(mem_pick & 8'haa))};
    wire [2:0] mem_tag = age_tag[mem_pick_index];
    wire [3:0] grant;
    wire alu_busy, alu_eq, alu_slt;
    wire [31:0] alu_result;
    wire exec_valid = (alu_locked || (|int_pick)) &&
                      (!alu_pending || grant[0]) && !i_rst && !halted;
    assign dispatch = exec_valid && !alu_busy;
    wire [31:0] exec_pc = instr_pc[exec_tag];
    wire [31:0] exec_imm = imm[exec_tag];
    wire [31:0] fallthrough = exec_pc + 32'd4;
    wire [31:0] target = indirect[exec_tag] ?
                         {alu_result[31:1], 1'b0} : exec_pc + exec_imm;
    wire branch_match = branch_eq[exec_tag] ? alu_eq : alu_slt;
    wire taken = jump[exec_tag] ||
                 (branch[exec_tag] && (branch_match ^ branch_invert[exec_tag]));
    wire branch_trap = taken && (|target[1:0]);
    wire redirect = dispatch && taken && !branch_trap;
    wire [4:0] exec_select = result_select[exec_tag];

    alu u_alu (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_mext(exec_valid && mext[exec_tag]), .i_advance(dispatch),
        .i_opsel(alu_op[exec_tag]), .i_sub(alu_sub[exec_tag]),
        .i_unsigned(alu_unsigned[exec_tag]), .i_arith(alu_arith[exec_tag]),
        .i_op1(pc_operand[exec_tag] ? exec_pc : lhs[exec_tag]),
        .i_op2(imm_operand[exec_tag] ? exec_imm : rhs[exec_tag]),
        .o_result(alu_result), .o_eq(alu_eq), .o_slt(alu_slt), .o_busy(alu_busy)
    );

    // Hold the LSU head through a cache miss. After cache acceptance, retain
    // the load result locally until its CDB grant, without reissuing the read.
    reg load_pending;
    reg [31:0] load_value, load_word;
    wire mem_valid = (|mem_pick) && !i_rst && !halted;
    wire mem_operands_ready = mem_valid && !lhs_wait[mem_tag] && !rhs_wait[mem_tag];
    wire [31:0] byte_addr = lhs[mem_tag] + imm[mem_tag];
    wire [1:0] lane = byte_addr[1:0];
    wire misaligned = |(lane & alignment[mem_tag]);
    wire mem_trap = mem_operands_ready && misaligned;
    wire [3:0] mask = byte_access[mem_tag] ?
                      (lane == 2'd0 ? 4'b0001 : lane == 2'd1 ? 4'b0010 :
                       lane == 2'd2 ? 4'b0100 : 4'b1000) :
                      half_access[mem_tag] ? (lane[1] ? 4'b1100 : 4'b0011) : 4'b1111;
    wire [31:0] store_data = byte_access[mem_tag] ? {4{rhs[mem_tag][7:0]}} :
                             half_access[mem_tag] ? {2{rhs[mem_tag][15:0]}} :
                             rhs[mem_tag];
    wire store_ready = mem_operands_ready && !misaligned && store_op[mem_tag];
    wire cache_write = store_ready && mem_tag == head && done[head];
    wire cache_read = mem_operands_ready && !misaligned &&
                      !store_op[mem_tag] && !load_pending;
    wire cache_ready;
    wire [31:0] cache_word;
    wire [7:0] selected_byte = lane == 2'd0 ? cache_word[7:0] :
                               lane == 2'd1 ? cache_word[15:8] :
                               lane == 2'd2 ? cache_word[23:16] : cache_word[31:24];
    wire [15:0] selected_half = lane[1] ? cache_word[31:16] : cache_word[15:0];
    wire [31:0] extended_load = byte_access[mem_tag] ?
        {{24{selected_byte[7] && !unsigned_load[mem_tag]}}, selected_byte} :
        half_access[mem_tag] ?
        {{16{selected_half[15] && !unsigned_load[mem_tag]}}, selected_half} : cache_word;
    wire cache_load_ready = cache_read && cache_ready;
    wire load_request = load_pending || cache_load_ready;

    cache #(.EVICT_POLICY(EVICT_POLICY), .NUM_WAYS(NUM_WAYS),
            .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE),
            .PREFETCH_EN(PREFETCH_EN)) dcache (
        .i_clk(i_clk), .i_rst(i_rst), .i_ren(cache_read), .i_wen(cache_write),
        .i_addr({byte_addr[31:2], 2'b00}), .i_mask(mask), .i_wdata(store_data),
        .o_ready(cache_ready), .o_rdata(cache_word),
        .o_mem_rd(o_mem_rd), .o_mem_rd_addr(o_mem_rd_addr),
        .i_mem_valid(i_mem_valid), .i_mem_rd_data(i_mem_rd_data),
        .o_mem_wr(o_mem_wr), .o_mem_wr_addr(o_mem_wr_addr),
        .o_mem_wr_data(o_mem_wr_data), .o_mem_wr_be(o_mem_wr_be)
    );

    // CSR instructions execute at the ROB head. Younger FP instructions
    // wait behind them so they see the committed rounding mode.
    reg [1:0] fp_pending;
    reg next_fp_lane;
    wire lane0_available = !fp_pending[0] || grant[2];
    wire lane1_available = !fp_pending[1] || grant[3];
    wire chosen_lane = lane1_available && (!lane0_available || next_fp_lane);
    wire fp_dispatch = (|fp_pick) && (lane0_available || lane1_available) && !i_rst && !halted;
    wire [2:0] fp_pick_index = {(|fp_pick[7:4]), (|(fp_pick & 8'hcc)), (|(fp_pick & 8'haa))};
    wire [2:0] fp_exec = age_tag[fp_pick_index];
    wire [1:0] fp_trap;
    wire [7:0] fp_next_state [0:1];
    wire [4:0] fp_op_flags [0:1];
    wire [2:0] fp_cdb_tag [0:1];
    wire [31:0] fp_cdb_value [0:1];
    wire fp_fault = fp_dispatch && fp_trap[chosen_lane];

    genvar unit_index;
    generate
        for (unit_index = 0; unit_index < 2; unit_index = unit_index + 1) begin : fp_unit
            localparam UNIT = unit_index;
            wire launch = fp_dispatch && chosen_lane == (UNIT != 0);
            wire [31:0] float_result, int_result;
            reg [2:0] pending_tag;
            reg [31:0] pending_value;
            assign fp_cdb_tag[unit_index] = pending_tag;
            assign fp_cdb_value[unit_index] = pending_value;

            fpu #(.EXTERNAL_FCSR(1)) execute_fp (
                .i_clk(i_clk), .i_rst(i_rst), .i_inst(inst[fp_exec]),
                .i_valid(launch), .i_advance(1'b0), .i_fcsr(shared_fcsr),
                .i_frs1(lhs[fp_exec]), .i_frs2(rhs[fp_exec]), .i_frs3(third[fp_exec]),
                .i_xrs1(lhs[fp_exec]), .o_fp_result(float_result), .o_int_result(int_result),
                .o_fflags(), .o_busy(), .o_rm_trap(fp_trap[unit_index]),
                .o_next_fcsr(fp_next_state[unit_index]), .o_operation_flags(fp_op_flags[unit_index])
            );

            always @(posedge i_clk) begin
                if (i_rst) begin
                    fp_pending[unit_index] <= 1'b0;
                end else begin
                    if (grant[2 + unit_index])
                        fp_pending[unit_index] <= 1'b0;
                    if (launch && !fp_fault) begin
                        fp_pending[unit_index] <= 1'b1;
                        pending_tag <= fp_exec;
                        pending_value <= fp_writes[fp_exec] ? float_result : int_result;
                    end
                end
            end
        end
    endgenerate

    cdb_arb u_cdb (
        .i_rob_head(head), .i_req({fp_pending, load_request, alu_pending} & {4{!i_rst && !halted}}),
        .i_tags({fp_cdb_tag[1], fp_cdb_tag[0], mem_tag, alu_tag}),
        .i_values({fp_cdb_value[1], fp_cdb_value[0], (load_pending ? load_value : extended_load), alu_value}),
        .o_grant(grant), .o_valid(o_complete_valid),
        .o_tag(o_complete_tag), .o_value(o_complete_value)
    );

    assign o_imem_raddr = pc;
    assign o_complete_pc = instr_pc[o_complete_tag];
    assign o_complete_rd = trap[o_complete_tag] ? 5'd0 :
                           fp_writes[o_complete_tag] ? fp_rd[o_complete_tag] : rd[o_complete_tag];

    assign o_retire_valid = live[head] && done[head] && !i_rst && !halted &&
                            (!store_op[head] || trap[head] || (cache_write && cache_ready));
    assign o_retire_inst = inst[head];
    assign o_retire_trap = trap[head];
    assign o_retire_halt = halt[head];
    assign o_retire_rs1_raddr = use_fp1[head] ? 5'd0 : rs1[head];
    assign o_retire_rs2_raddr = use_fp2[head] ? 5'd0 : rs2[head];
    assign o_retire_rs1_rdata = use_fp1[head] ? 32'd0 : lhs[head];
    assign o_retire_rs2_rdata = use_fp2[head] ? 32'd0 : rhs[head];
    assign o_retire_rd_waddr = trap[head] ? 5'd0 : rd[head];
    assign o_retire_rd_wdata = value[head];
    assign o_retire_pc = instr_pc[head];
    assign o_retire_next_pc = next_pc[head];
    assign o_retire_dmem_addr = mem_addr[head];
    assign o_retire_dmem_mask = mem_mask[head];
    assign o_retire_dmem_ren = memory_op[head] && !store_op[head] && !trap[head];
    assign o_retire_dmem_wen = store_op[head] && !trap[head];
    assign o_retire_dmem_rdata = o_retire_dmem_ren ? mem_bus_data[head] : 32'd0;
    assign o_retire_dmem_wdata = o_retire_dmem_wen ? mem_bus_data[head] : 32'd0;
    assign o_retire_frs1_raddr = use_fp1[head] ? rs1[head] : 5'd0;
    assign o_retire_frs2_raddr = use_fp2[head] ? rs2[head] : 5'd0;
    assign o_retire_frs3_raddr = use_fp3[head] ? fp_src3[head] : 5'd0;
    assign o_retire_frs1_rdata = use_fp1[head] ? lhs[head] : 32'd0;
    assign o_retire_frs2_rdata = use_fp2[head] ? rhs[head] : 32'd0;
    assign o_retire_frs3_rdata = use_fp3[head] ? third[head] : 32'd0;
    assign o_retire_frd_wen = o_retire_valid && !trap[head] && fp_writes[head];
    assign o_retire_frd_waddr = fp_writes[head] ? fp_rd[head] : 5'd0;
    assign o_retire_frd_wdata = value[head];
    wire [7:0] committed_fcsr = !trap[head] && fp_execute[head] ?
        (fp_csr[head] ? fp_csr_result[head] :
         {shared_fcsr[7:5], shared_fcsr[4:0] | fp_flags[head]}) : shared_fcsr;
    assign o_retire_fflags = committed_fcsr[4:0];

    always @(posedge i_clk) begin
        if (i_rst) begin
            shared_fcsr <= 8'd0;
            next_fp_lane <= 1'b0;
            pc <= RESET_ADDR;
            id_valid <= 1'b0;
            control_pending <= 1'b0;
            halted <= 1'b0;
            head <= 3'd0;
            tail <= 3'd0;
            used <= 4'd0;
            waiting_count <= 4'd0;
            alu_locked <= 1'b0;
            alu_pending <= 1'b0;
            load_pending <= 1'b0;
        end else begin
            if (o_retire_valid)
                shared_fcsr <= committed_fcsr;
            if (fp_dispatch)
                next_fp_lane <= !chosen_lane;
            if (redirect) begin
                pc <= target;
                id_valid <= 1'b0;
            end else if (!halted && (!id_valid || issue)) begin
                id_pc <= pc;
                if_id_inst <= i_imem_rdata;
                id_valid <= 1'b1;
                pc <= pc + 32'd4;
            end
            if (dispatch && (branch[exec_tag] || jump[exec_tag]))
                control_pending <= 1'b0;
            if (issue && !issue_trap && (dec_branch || dec_jump || dec_halt))
                control_pending <= 1'b1;
            if (o_retire_valid && o_retire_halt)
                halted <= 1'b1;
            if (o_retire_valid)
                head <= head + 3'd1;
            if (issue)
                tail <= tail + 3'd1;
            used <= used + {3'b0, issue} - {3'b0, o_retire_valid};
            waiting_count <= waiting_count + {3'b0, issue && issue_int} -
                             {3'b0, dispatch};

            if (exec_valid && alu_busy) begin
                locked_tag <= exec_tag;
                alu_locked <= 1'b1;
            end
            if (grant[0])
                alu_pending <= 1'b0;
            if (dispatch) begin
                alu_locked <= 1'b0;
                alu_pending <= !branch_trap;
                alu_tag <= exec_tag;
                alu_value <= branch[exec_tag] ? 32'd0 :
                             exec_select[2] ? fallthrough :
                             exec_select[1] ? exec_imm : alu_result;
            end
            if (cache_load_ready && !grant[1]) begin
                load_pending <= 1'b1;
                load_value <= extended_load;
                load_word <= cache_word;
            end
            if (grant[1])
                load_pending <= 1'b0;
        end
    end

    genvar entry;
    generate
        for (entry = 0; entry < 8; entry = entry + 1) begin : rob_entry
            localparam [2:0] TAG = entry;
            always @(posedge i_clk) begin
                if (i_rst) begin
                    live[entry] <= 1'b0;
                    done[entry] <= 1'b0;
                    waiting[entry] <= 1'b0;
                    fp_waiting[entry] <= 1'b0;
                    third_wait[entry] <= 1'b0;
                    lhs_wait[entry] <= 1'b0;
                    rhs_wait[entry] <= 1'b0;
                end else begin
                    if (o_retire_valid && head == TAG)
                        live[entry] <= 1'b0;

                    if (recover && live[entry]) begin
                        if (lhs_wait[entry] && lhs_tag[entry] == head) begin
                            lhs_wait[entry] <= 1'b0;
                            lhs[entry] <= recovery_value;
                        end
                        if (rhs_wait[entry] && rhs_tag[entry] == head) begin
                            rhs_wait[entry] <= 1'b0;
                            rhs[entry] <= recovery_value;
                        end
                        if (third_wait[entry] && third_tag[entry] == head) begin
                            third_wait[entry] <= 1'b0;
                            third[entry] <= recovery_value;
                        end
                    end

                    if (fp_dispatch && fp_exec == TAG) begin
                        fp_waiting[entry] <= 1'b0;
                        fp_csr_result[entry] <= fp_next_state[chosen_lane];
                        fp_flags[entry] <= fp_op_flags[chosen_lane];
                        if (fp_fault) begin
                            trap[entry] <= 1'b1;
                            done[entry] <= 1'b1;
                        end
                    end

                    if (o_complete_valid && live[entry]) begin
                        if (lhs_wait[entry] && lhs_tag[entry] == o_complete_tag) begin
                            lhs_wait[entry] <= 1'b0;
                            lhs[entry] <= o_complete_value;
                        end
                        if (rhs_wait[entry] && rhs_tag[entry] == o_complete_tag) begin
                            rhs_wait[entry] <= 1'b0;
                            rhs[entry] <= o_complete_value;
                        end
                        if (third_wait[entry] && third_tag[entry] == o_complete_tag) begin
                            third_wait[entry] <= 1'b0;
                            third[entry] <= o_complete_value;
                        end
                        if (o_complete_tag == TAG) begin
                            done[entry] <= 1'b1;
                            value[entry] <= o_complete_value;
                        end
                    end

                    if (dispatch && exec_tag == TAG) begin
                        waiting[entry] <= 1'b0;
                        next_pc[entry] <= redirect ? target : fallthrough;
                        if (branch_trap) begin
                            trap[entry] <= 1'b1;
                            done[entry] <= 1'b1;
                        end
                    end

                    if (mem_tag == TAG && (mem_trap || store_ready || grant[1])) begin
                        mem_addr[entry] <= {byte_addr[31:2], 2'b00};
                        mem_mask[entry] <= misaligned ? 4'b0 : mask;
                        mem_bus_data[entry] <= store_op[entry] ? store_data :
                                               load_pending ? load_word : cache_word;
                        done[entry] <= 1'b1;
                        trap[entry] <= misaligned;
                    end

                    if (issue && tail == TAG) begin
                        live[entry] <= 1'b1;
                        done[entry] <= issue_trap || dec_halt;
                        waiting[entry] <= issue_int;
                        fp_waiting[entry] <= issue_fp;
                        fp_execute[entry] <= issue_fp;
                        fp_csr[entry] <= issue_fp && if_id_inst[6:0] == 7'h73;
                        fp_writes[entry] <= !issue_trap && dec_frd;
                        fp_rd[entry] <= if_id_inst[11:7];
                        fp_src3[entry] <= dec_rs3;
                        use_fp1[entry] <= dec_frs1;
                        use_fp2[entry] <= dec_frs2;
                        use_fp3[entry] <= dec_frs3;
                        third_tag[entry] <= tag3;
                        third_wait[entry] <= pending3 && !issue_trap;
                        third[entry] <= bypass3 ? o_complete_value :
                                        map3 ? value[tag3] : fp3;
                        memory_op[entry] <= issue_mem;
                        store_op[entry] <= issue_mem && dec_dmem_wen;
                        trap[entry] <= issue_trap;
                        halt[entry] <= dec_halt && !issue_trap;
                        inst[entry] <= if_id_inst;
                        instr_pc[entry] <= id_pc;
                        next_pc[entry] <= id_pc + 32'd4;
                        imm[entry] <= dec_imm;
                        value[entry] <= 32'd0;
                        rs1[entry] <= dec_rs1;
                        rs2[entry] <= dec_rs2;
                        rd[entry] <= issue_rd;
                        lhs_wait[entry] <= pending1 && !issue_trap;
                        rhs_wait[entry] <= pending2 && !issue_trap;
                        lhs_tag[entry] <= tag1;
                        rhs_tag[entry] <= tag2;
                        lhs[entry] <= bypass1 ? o_complete_value :
                                      map1 ? value[tag1] : dec_frs1 ? fp1 : rf1;
                        rhs[entry] <= bypass2 ? o_complete_value :
                                      map2 ? value[tag2] : dec_frs2 ? fp2 : rf2;
                        result_select[entry] <= dec_rd_sel;
                        pc_operand[entry] <= dec_op1_sel;
                        imm_operand[entry] <= dec_op2_sel;
                        alu_op[entry] <= dec_alu_opsel;
                        alu_sub[entry] <= dec_alu_sub;
                        alu_unsigned[entry] <= dec_alu_unsigned;
                        alu_arith[entry] <= dec_alu_arith;
                        mext[entry] <= dec_mext;
                        branch[entry] <= dec_branch;
                        jump[entry] <= dec_jump;
                        branch_eq[entry] <= dec_branch_equal;
                        branch_invert[entry] <= dec_branch_invert;
                        indirect[entry] <= dec_pc_sel;
                        alignment[entry] <= dec_dmem_align;
                        byte_access[entry] <= dec_dmem_memb;
                        half_access[entry] <= dec_dmem_memh;
                        unsigned_load[entry] <= dec_dmem_memu;
                        mem_addr[entry] <= 32'd0;
                        mem_mask[entry] <= 4'd0;
                        mem_bus_data[entry] <= 32'd0;
                    end
                end
            end
        end
    endgenerate
endmodule

`default_nettype wire
