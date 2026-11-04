// AI USE DISCLOSURE:
// OpenAI ChatGPT and Claude were used as aids in the development of this file.
// Accessed October 2026.

`default_nettype none

module hart #(
    // After reset, the program counter (PC) should be initialized to this
    // address and start executing instructions from there.
    parameter RESET_ADDR = 32'h00000000,
    // When set, pipeline forwarding optimizations are enabled.
    parameter FWD_EN = 1,
    // When set, register file bypassing is enabled.
    parameter BYPASS_EN = 1,
    // Cache configuration. Pass these down unchanged to the instruction
    // cache and the data cache (see cache.v). The testbench sets all five,
    // so these defaults are never used for grading.
    parameter EVICT_POLICY = 0,
    parameter NUM_WAYS     = 1,
    parameter CACHE_SIZE   = 16,
    parameter BLOCK_SIZE   = 128,
    parameter PREFETCH_EN  = 0
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Phase 4's combinational instruction and data memory ports are now
    // internal: they connect the pipeline to two `cache` instances inside
    // the hart, one for instructions and one for data. What leaves the hart
    // is the caches' memory side, one block (BLOCK_SIZE bytes) per transfer,
    // against a main memory with a fixed delay:
    //  * o_*mem_rd is a one-cycle request for the line at o_*mem_rd_addr
    //    (line aligned); i_*mem_valid is high for one cycle when that line
    //    is on i_*mem_rd_data. Requests are answered in order.
    //  * o_dmem_wr is a one-cycle line write; o_dmem_wr_be has one bit per
    //    byte (all ones for a dirty write-back, only the stored bytes for a
    //    write-through). Instructions are read only, so there is no
    //    instruction-side write port.
    output wire                    o_imem_rd,
    output wire [31:0]             o_imem_rd_addr,
    input  wire                    i_imem_valid,
    input  wire [BLOCK_SIZE*8-1:0] i_imem_rd_data,
    output wire                    o_dmem_rd,
    output wire [31:0]             o_dmem_rd_addr,
    input  wire                    i_dmem_valid,
    input  wire [BLOCK_SIZE*8-1:0] i_dmem_rd_data,
    output wire                    o_dmem_wr,
    output wire [31:0]             o_dmem_wr_addr,
    output wire [BLOCK_SIZE*8-1:0] o_dmem_wr_data,
    output wire [BLOCK_SIZE-1:0]   o_dmem_wr_be,
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

    // Pipeline signals are declared before use for strict checking.
    wire [31:0] o_imem_raddr, i_imem_rdata;
    wire [31:0] o_dmem_addr, o_dmem_wdata, i_dmem_rdata;
    wire [3:0] o_dmem_mask;
    wire o_dmem_ren, o_dmem_wen;
    wire ic_ready, dc_ready, ex_stall, pipe_stall;
    wire alu_busy, fpu_busy;
    wire ex_advance;
    wire mem_request;
    wire dec_mext, dec_fpu, dec_frs1, dec_frs2, dec_frs3, dec_frd;
    wire [4:0] dec_rs3;
    wire [4:0] dec_xrs1;
    wire [4:0] dec_xrs2;
    wire [31:0] rf_f1, rf_f2, rf_f3;
    wire [31:0] ex_fp_result, ex_int_result;
    wire [4:0] ex_fflags;
    wire ex_rm_trap;
    wire branch_taken_ex;
    wire [31:0] branch_target_ex;
    wire load_use_stall;
    reg [31:0] pc_reg;
    wire [31:0] pc_plus_4_if;
    wire [31:0] next_pc;
    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg if_id_valid;
    wire dec_legal, dec_halt;
    wire [ 4:0] dec_rs1, dec_rs2, dec_rd;
    wire [31:0] dec_imm;
    wire dec_op1_sel, dec_op2_sel;
    wire [ 2:0] dec_alu_opsel;
    wire dec_alu_sub, dec_alu_unsigned, dec_alu_arith;
    wire dec_branch, dec_jump;
    wire dec_branch_equal, dec_branch_unsigned, dec_branch_invert;
    wire dec_dmem_ren, dec_dmem_wen;
    wire [ 1:0] dec_dmem_align;
    wire dec_dmem_memb, dec_dmem_memh, dec_dmem_memw, dec_dmem_memu;
    wire [ 4:0] dec_rd_sel;
    wire dec_pc_sel;
    wire [31:0] rf_rs1_rdata, rf_rs2_rdata;
    wire [ 4:0] wb_rd;
    wire [31:0] wb_data;
    reg [ 4:0] ex_mem_rd_sel;
    wire id_trap;
    reg id_ex_dmem_ren;
    reg [4:0] id_ex_rd;
    wire dep_ex;
    wire dep_mem;
    wire dep_wb;
    wire fp_dep_ex;
    wire fp_dep_mem;
    wire fp_dep_wb;
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_inst;
    reg id_ex_valid;
    reg id_ex_trap;
    reg id_ex_halt;
    reg [ 4:0] id_ex_rs1;
    reg [ 4:0] id_ex_rs2;
    reg [31:0] id_ex_rs1_rdata;
    reg [31:0] id_ex_rs2_rdata;
    reg [31:0] id_ex_imm;
    reg id_ex_op1_sel;
    reg id_ex_op2_sel;
    reg [ 2:0] id_ex_alu_opsel;
    reg id_ex_alu_sub;
    reg id_ex_alu_unsigned;
    reg id_ex_alu_arith;
    reg id_ex_branch;
    reg id_ex_jump;
    reg id_ex_branch_equal;
    reg id_ex_branch_unsigned;
    reg id_ex_branch_invert;
    reg id_ex_dmem_wen;
    reg [ 1:0] id_ex_dmem_align;
    reg id_ex_dmem_memb;
    reg id_ex_dmem_memh;
    reg id_ex_dmem_memw;
    reg id_ex_dmem_memu;
    reg [ 4:0] id_ex_rd_sel;
    reg id_ex_pc_sel;
    reg [ 4:0] ex_mem_rd;
    reg [31:0] ex_mem_alu_result;
    reg ex_mem_reg_write;
    wire mem_wb_reg_write;
    wire [1:0] forward_a;
    wire [1:0] forward_b;
    reg [31:0] ex_mem_imm;
    reg [31:0] ex_mem_pc;
    wire [31:0] ex_mem_stage_val;
    wire [31:0] ex_rs1_val;
    wire [31:0] ex_rs2_val;
    wire [31:0] alu_op1;
    wire [31:0] alu_op2;
    wire [31:0] ex_alu_result;
    wire alu_eq, alu_slt;
    wire branch_condition;
    wire branch_eval;
    wire redirect_requested;
    wire branch_misaligned;
    wire [31:0] branch_target_calc;
    wire [1:0] ex_dmem_byte_off;
    wire ex_dmem_misaligned;
    wire ex_stage_trap;
    reg [31:0] ex_mem_next_pc;
    reg [31:0] ex_mem_inst;
    reg ex_mem_valid;
    reg ex_mem_trap;
    reg ex_mem_halt;
    reg [ 4:0] ex_mem_rs1;
    reg [ 4:0] ex_mem_rs2;
    reg [31:0] ex_mem_rs1_rdata;
    reg [31:0] ex_mem_rs2_rdata;
    reg ex_mem_dmem_ren;
    reg ex_mem_dmem_wen;
    reg [ 1:0] ex_mem_dmem_align;
    reg ex_mem_dmem_memb;
    reg ex_mem_dmem_memh;
    reg ex_mem_dmem_memw;
    reg ex_mem_dmem_memu;
    wire [1:0] mem_byte_off;
    wire [31:0] mem_store_src;
    wire [7:0] load_byte;
    wire [15:0] load_half;
    wire [31:0] mem_load_data;
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_next_pc;
    reg [31:0] mem_wb_inst;
    reg mem_wb_valid;
    reg mem_wb_trap;
    reg mem_wb_halt;
    reg [ 4:0] mem_wb_rs1;
    reg [ 4:0] mem_wb_rs2;
    reg [ 4:0] mem_wb_rd;
    reg [31:0] mem_wb_rs1_rdata;
    reg [31:0] mem_wb_rs2_rdata;
    reg [31:0] mem_wb_imm;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_load_data;
    reg [ 4:0] mem_wb_rd_sel;
    reg mem_wb_reg_write_reg;
    reg [31:0] mem_wb_dmem_addr;
    reg mem_wb_dmem_ren;
    reg mem_wb_dmem_wen;
    reg [ 3:0] mem_wb_dmem_mask;
    reg [31:0] mem_wb_dmem_wdata;
    reg [31:0] mem_wb_dmem_rdata;
    reg id_ex_mext, id_ex_fpu, id_ex_frd;
    reg id_ex_fr1_en, id_ex_fr2_en, id_ex_fr3_en;
    reg [4:0] id_ex_fr1, id_ex_fr2, id_ex_fr3, id_ex_fd;
    reg [31:0] id_ex_f1, id_ex_f2, id_ex_f3;
    reg ex_mem_frd;
    reg [4:0] ex_mem_fr1, ex_mem_fr2, ex_mem_fr3, ex_mem_fd;
    reg [31:0] ex_mem_f1, ex_mem_f2, ex_mem_f3, ex_mem_fp_result;
    reg [4:0] ex_mem_fflags;
    reg [31:0] ex_mem_store_data;
    reg mem_wb_frd;
    reg [4:0] mem_wb_fr1, mem_wb_fr2, mem_wb_fr3, mem_wb_fd;
    reg [31:0] mem_wb_f1, mem_wb_f2, mem_wb_f3, mem_wb_fp_result;
    reg [4:0] mem_wb_fflags;
    wire [31:0] wb_fp_data;




    // Phase 6 cache bridge. Long operations freeze every pipeline stage.







    assign mem_request = o_dmem_ren || o_dmem_wen;
    assign ex_stall = alu_busy || fpu_busy;
    assign pipe_stall = ex_stall || !ic_ready || (mem_request && !dc_ready);
    assign ex_advance = id_ex_valid && !pipe_stall;
    cache #(.EVICT_POLICY(EVICT_POLICY), .NUM_WAYS(NUM_WAYS),
      .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE), .PREFETCH_EN(PREFETCH_EN)) icache (
      .i_clk(i_clk), .i_rst(i_rst), .i_ren(!i_rst), .i_wen(1'b0),
      .i_addr(o_imem_raddr), .i_mask(4'b1111), .i_wdata(32'd0),
      .o_ready(ic_ready), .o_rdata(i_imem_rdata),
      .o_mem_rd(o_imem_rd), .o_mem_rd_addr(o_imem_rd_addr),
      .i_mem_valid(i_imem_valid), .i_mem_rd_data(i_imem_rd_data),
      .o_mem_wr(), .o_mem_wr_addr(), .o_mem_wr_data(), .o_mem_wr_be()
    );
    // Gate requests on EX stalls and instruction-cache freezes: stores fire once.
    cache #(.EVICT_POLICY(EVICT_POLICY), .NUM_WAYS(NUM_WAYS),
      .CACHE_SIZE(CACHE_SIZE), .BLOCK_SIZE(BLOCK_SIZE), .PREFETCH_EN(PREFETCH_EN)) dcache (
      .i_clk(i_clk), .i_rst(i_rst),
      .i_ren(o_dmem_ren && !ex_stall && ic_ready),
      .i_wen(o_dmem_wen && !ex_stall && ic_ready),
      .i_addr(o_dmem_addr), .i_mask(o_dmem_mask), .i_wdata(o_dmem_wdata),
      .o_ready(dc_ready), .o_rdata(i_dmem_rdata),
      .o_mem_rd(o_dmem_rd), .o_mem_rd_addr(o_dmem_rd_addr),
      .i_mem_valid(i_dmem_valid), .i_mem_rd_data(i_dmem_rd_data),
      .o_mem_wr(o_dmem_wr), .o_mem_wr_addr(o_dmem_wr_addr),
      .o_mem_wr_data(o_dmem_wr_data), .o_mem_wr_be(o_dmem_wr_be)
    );


    assign dec_xrs1 = dec_frs1 ? 5'd0 : dec_rs1;
    assign dec_xrs2 = dec_frs2 ? 5'd0 : dec_rs2;




    // =========================================================================
    // Signals fed backwards from later stages
    // =========================================================================




    // =========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE
    // -------------------------------------------------------------------------
    // CHANGE 3: UPDATING THE PROGRAM COUNTER (PC)
    // WHAT: Decide the next instruction address:
    //   1. If a branch/jump in Execute was taken, jump to the branch target.
    //   2. If we are paused for a load-use stall, freeze the PC in place.
    //   3. Otherwise, keep walking forward normally (pc + 4).
    // -------------------------------------------------------------------------

    assign pc_plus_4_if = pc_reg + 32'd4;

    assign next_pc = branch_taken_ex ? branch_target_ex :
                          load_use_stall  ? pc_reg :
                                            pc_plus_4_if;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_reg <= RESET_ADDR;
        end else begin
            if (!pipe_stall) pc_reg <= next_pc;
        end
    end

    assign o_imem_raddr = pc_reg;

    // =========================================================================
    // 2. IF / ID PIPELINE REGISTER (Tray between Fetch and Decode)
    // -------------------------------------------------------------------------
    // CHANGE 4: PASSING INSTRUCTIONS FROM FETCH TO DECODE
    // WHAT: Saves the fetched instruction and PC for the next clock tick.
    // - On branch taken: Erase what was fetched (replace with a harmless NOP)
    //   because we guessed wrong.
    // - On load-use stall: Don't update, hold onto the current instruction so
    //   it doesn't get lost while we wait.
    // -------------------------------------------------------------------------




    always @(posedge i_clk) begin
        if (i_rst) begin
            if_id_pc    <= 32'h0000_0000;
            if_id_inst  <= 32'h0000_0013; // RISC-V NOP: addi x0, x0, 0
            if_id_valid <= 1'b0;
        end else if (!pipe_stall) begin
            if (branch_taken_ex) begin
            if_id_pc    <= 32'h0000_0000;
            if_id_inst  <= 32'h0000_0013; // RISC-V NOP: addi x0, x0, 0
            if_id_valid <= 1'b0;
            end else if (!load_use_stall) begin
            if_id_pc    <= pc_reg;
            if_id_inst  <= i_imem_rdata;
            if_id_valid <= 1'b1;
            end
        end
    end

    // =========================================================================
    // 3. INSTRUCTION DECODE (ID) STAGE
    // =========================================================================














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

    // -------------------------------------------------------------------------
    // CHANGE 5: SAME-CYCLE REGISTER BYPASS (BYPASS_EN = 1)
    // WHAT: Turn on BYPASS_EN = 1 inside rf.v.
    // WHY: If Stage 5 is writing a result into a register on the exact same clock
    // tick Stage 2 is trying to read it, this makes the register file immediately
    // hand over the new value without making us wait an extra cycle.
    // -------------------------------------------------------------------------




    rf #(.BYPASS_EN(BYPASS_EN)) u_rf (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(dec_xrs1),
        .o_rs1_rdata(rf_rs1_rdata),
        .i_rs2_raddr(dec_xrs2),
        .o_rs2_rdata(rf_rs2_rdata),
        .i_rd_waddr ((!pipe_stall && mem_wb_valid) ? wb_rd : 5'd0),
        .i_rd_wdata (wb_data),
        .i_frs1_raddr(dec_rs1), .o_frs1_rdata(rf_f1),
        .i_frs2_raddr(dec_rs2), .o_frs2_rdata(rf_f2),
        .i_frs3_raddr(dec_rs3), .o_frs3_rdata(rf_f3),
        .i_frd_wen(mem_wb_frd && mem_wb_valid && !pipe_stall),
        .i_frd_waddr(mem_wb_fd), .i_frd_wdata(wb_fp_data)
    );

    assign id_trap = if_id_valid & ~dec_legal;

    // -------------------------------------------------------------------------
    // CHANGE 6: LOAD-USE HAZARD DETECTOR (THE PAUSE BUTTON)
    // WHAT: Check if the instruction currently in Execute is loading from RAM,
    // and the instruction right behind it in Decode wants to use that same register.
    // WHY: RAM data isn't ready yet, so we can't forward it. We must pause the
    // pipeline for 1 clock tick by inserting a blank bubble (NOP) into Execute.
    // -------------------------------------------------------------------------

 // Declared here for the hazard check; not re-declared below

    assign dep_ex = id_ex_valid && (id_ex_rd != 0) &&
        ((dec_xrs1 == id_ex_rd) || (dec_xrs2 == id_ex_rd));
    assign dep_mem = ex_mem_valid && (ex_mem_rd != 0) &&
        ((dec_xrs1 == ex_mem_rd) || (dec_xrs2 == ex_mem_rd));
    assign dep_wb = mem_wb_valid && (mem_wb_rd != 0) &&
        ((dec_xrs1 == mem_wb_rd) || (dec_xrs2 == mem_wb_rd));
    assign fp_dep_ex = id_ex_valid && id_ex_frd &&
        ((dec_frs1 && dec_rs1 == id_ex_fd) ||
         (dec_frs2 && dec_rs2 == id_ex_fd) ||
         (dec_frs3 && dec_rs3 == id_ex_fd));
    assign fp_dep_mem = ex_mem_valid && ex_mem_frd &&
        ((dec_frs1 && dec_rs1 == ex_mem_fd) ||
         (dec_frs2 && dec_rs2 == ex_mem_fd) ||
         (dec_frs3 && dec_rs3 == ex_mem_fd));
    assign fp_dep_wb = mem_wb_valid && mem_wb_frd &&
        ((dec_frs1 && dec_rs1 == mem_wb_fd) ||
         (dec_frs2 && dec_rs2 == mem_wb_fd) ||
         (dec_frs3 && dec_rs3 == mem_wb_fd));
    assign load_use_stall = if_id_valid &&
        ((dep_ex && (id_ex_dmem_ren || (FWD_EN == 0))) ||
         (dep_mem && (FWD_EN == 0)) ||
         (dep_wb && (BYPASS_EN == 0)) || fp_dep_ex || fp_dep_mem ||
         (fp_dep_wb && (BYPASS_EN == 0)));


    // =========================================================================
    // 4. ID / EX PIPELINE REGISTER (Tray between Decode and Execute)
    // -------------------------------------------------------------------------
    // CHANGE 7: PASSING DECODED INFO TO EXECUTE
    // WHAT: Latch control signals, register numbers, and read data into flip-flops.
    // If we have to pause (load_use_stall) or toss out a bad guess (branch_taken),
    // clear this register to zero so it acts as a do-nothing bubble (NOP).
    // -------------------------------------------------------------------------







    // NOTE: id_ex_rd declared above























    always @(posedge i_clk) begin
        if (i_rst) begin
            id_ex_pc              <= 32'h0000_0000;
            id_ex_inst            <= 32'h0000_0013; // Bubble / NOP
            id_ex_valid           <= 1'b0;
            id_ex_trap            <= 1'b0;
            id_ex_halt            <= 1'b0;
            id_ex_rs1             <= 5'd0;
            id_ex_rs2             <= 5'd0;
            id_ex_rd              <= 5'd0;
            id_ex_rs1_rdata       <= 32'd0;
            id_ex_rs2_rdata       <= 32'd0;
            id_ex_imm             <= 32'd0;
            id_ex_op1_sel         <= 1'b0;
            id_ex_op2_sel         <= 1'b0;
            id_ex_alu_opsel       <= 3'b000;
            id_ex_alu_sub         <= 1'b0;
            id_ex_alu_unsigned    <= 1'b0;
            id_ex_alu_arith       <= 1'b0;
            id_ex_branch          <= 1'b0;
            id_ex_jump            <= 1'b0;
            id_ex_branch_equal    <= 1'b0;
            id_ex_branch_unsigned <= 1'b0;
            id_ex_branch_invert   <= 1'b0;
            id_ex_dmem_ren        <= 1'b0;
            id_ex_dmem_wen        <= 1'b0;
            id_ex_dmem_align      <= 2'b00;
            id_ex_dmem_memb       <= 1'b0;
            id_ex_dmem_memh       <= 1'b0;
            id_ex_dmem_memw       <= 1'b0;
            id_ex_dmem_memu       <= 1'b0;
            id_ex_rd_sel          <= 5'b00001;
            id_ex_pc_sel          <= 1'b0;
        end else if (!pipe_stall) begin
            if (branch_taken_ex || load_use_stall) begin
            id_ex_pc              <= 32'h0000_0000;
            id_ex_inst            <= 32'h0000_0013; // Bubble / NOP
            id_ex_valid           <= 1'b0;
            id_ex_trap            <= 1'b0;
            id_ex_halt            <= 1'b0;
            id_ex_rs1             <= 5'd0;
            id_ex_rs2             <= 5'd0;
            id_ex_rd              <= 5'd0;
            id_ex_rs1_rdata       <= 32'd0;
            id_ex_rs2_rdata       <= 32'd0;
            id_ex_imm             <= 32'd0;
            id_ex_op1_sel         <= 1'b0;
            id_ex_op2_sel         <= 1'b0;
            id_ex_alu_opsel       <= 3'b000;
            id_ex_alu_sub         <= 1'b0;
            id_ex_alu_unsigned    <= 1'b0;
            id_ex_alu_arith       <= 1'b0;
            id_ex_branch          <= 1'b0;
            id_ex_jump            <= 1'b0;
            id_ex_branch_equal    <= 1'b0;
            id_ex_branch_unsigned <= 1'b0;
            id_ex_branch_invert   <= 1'b0;
            id_ex_dmem_ren        <= 1'b0;
            id_ex_dmem_wen        <= 1'b0;
            id_ex_dmem_align      <= 2'b00;
            id_ex_dmem_memb       <= 1'b0;
            id_ex_dmem_memh       <= 1'b0;
            id_ex_dmem_memw       <= 1'b0;
            id_ex_dmem_memu       <= 1'b0;
            id_ex_rd_sel          <= 5'b00001;
            id_ex_pc_sel          <= 1'b0;
            end else begin
            id_ex_pc              <= if_id_pc;
            id_ex_inst            <= if_id_inst;
            id_ex_valid           <= if_id_valid;
            id_ex_trap            <= id_trap;
            id_ex_halt            <= dec_halt;
            id_ex_rs1             <= dec_xrs1;
            id_ex_rs2             <= dec_xrs2;
            id_ex_rd              <= dec_rd;
            id_ex_rs1_rdata       <= rf_rs1_rdata;
            id_ex_rs2_rdata       <= rf_rs2_rdata;
            id_ex_imm             <= dec_imm;
            id_ex_op1_sel         <= dec_op1_sel;
            id_ex_op2_sel         <= dec_op2_sel;
            id_ex_alu_opsel       <= dec_alu_opsel;
            id_ex_alu_sub         <= dec_alu_sub;
            id_ex_alu_unsigned    <= dec_alu_unsigned;
            id_ex_alu_arith       <= dec_alu_arith;
            id_ex_branch          <= dec_branch;
            id_ex_jump            <= dec_jump;
            id_ex_branch_equal    <= dec_branch_equal;
            id_ex_branch_unsigned <= dec_branch_unsigned;
            id_ex_branch_invert   <= dec_branch_invert;
            id_ex_dmem_ren        <= dec_dmem_ren;
            id_ex_dmem_wen        <= dec_dmem_wen;
            id_ex_dmem_align      <= dec_dmem_align;
            id_ex_dmem_memb       <= dec_dmem_memb;
            id_ex_dmem_memh       <= dec_dmem_memh;
            id_ex_dmem_memw       <= dec_dmem_memw;
            id_ex_dmem_memu       <= dec_dmem_memu;
            id_ex_rd_sel          <= dec_rd_sel;
            id_ex_pc_sel          <= dec_pc_sel;
            end
        end
    end

    // =========================================================================
    // 5. EXECUTE (EX) STAGE & FORWARDING UNIT
    // -------------------------------------------------------------------------
    // CHANGE 8: FORWARDING UNIT (PASSING ANSWERS EARLY)
    // WHAT: Check if the instructions ahead of us (in Stage 4 or Stage 5) are
    // writing to the register we need right now.
    // - If Stage 4 matches: Grab Stage 4's ALU result directly.
    // - Else if Stage 5 matches: Grab Stage 5's final writeback data.
    // - Else: Use the regular value read from the register file.
    // WHY: Saves clock cycles by getting new answers immediately without waiting
    // for them to be written into the register file.
    // -------------------------------------------------------------------------





    assign forward_a =
        ((FWD_EN != 0) && ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) ? 2'b10 :
        ((FWD_EN != 0) && mem_wb_reg_write && (wb_rd != 5'd0)     && (wb_rd == id_ex_rs1))     ? 2'b01 :
                                                                                 2'b00;

    assign forward_b =
        ((FWD_EN != 0) && ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) ? 2'b10 :
        ((FWD_EN != 0) && mem_wb_reg_write && (wb_rd != 5'd0)     && (wb_rd == id_ex_rs2))     ? 2'b01 :
                                                                                 2'b00;




    // Select the actual result computed in the EX/MEM stage
    // (Handles ALU, LUI/AUIPC immediates, and JAL/JALR return addresses)

assign ex_mem_stage_val = (ex_mem_rd_sel[0] || ex_mem_rd_sel[4]) ? ex_mem_alu_result :
                          ex_mem_rd_sel[1] ? ex_mem_imm :
                          ex_mem_rd_sel[2] ? (ex_mem_pc + 32'd4) :
                                             ex_mem_alu_result;
    assign ex_rs1_val = (forward_a == 2'b10) ? ex_mem_stage_val :
                             (forward_a == 2'b01) ? wb_data :
                                                    id_ex_rs1_rdata;

    assign ex_rs2_val = (forward_b == 2'b10) ? ex_mem_stage_val :
                             (forward_b == 2'b01) ? wb_data :
                                                    id_ex_rs2_rdata;
                                                    
    // ALU Inputs (picks either the forwarded register value, PC, or immediate)
    assign alu_op1 = id_ex_op1_sel ? id_ex_pc  : ex_rs1_val;
    assign alu_op2 = id_ex_op2_sel ? id_ex_imm : ex_rs2_val;




    alu u_alu (
        .i_clk(i_clk), .i_rst(i_rst),
        .i_mext(id_ex_valid && id_ex_mext && !id_ex_trap),
        .i_advance(ex_advance),
        .i_opsel   (id_ex_alu_opsel),
        .i_sub     (id_ex_alu_sub),
        .i_unsigned(id_ex_alu_unsigned),
        .i_arith   (id_ex_alu_arith),
        .i_op1     (alu_op1),
        .i_op2     (alu_op2),
        .o_result  (ex_alu_result),
        .o_eq      (alu_eq),
        .o_slt     (alu_slt),
        .o_busy    (alu_busy)
    );

    // -------------------------------------------------------------------------
    // CHANGE 9: CHECKING BRANCHES HERE IN EXECUTE
    // WHAT: Compare the forwarded numbers in the ALU to decide if the branch is taken.
    // WHY: Section 4.1.3 explicitly requires checking branch conditions in Execute.
    // If it is taken, branch_taken_ex turns high and clears wrong guesses in IF/ID.
    // -------------------------------------------------------------------------
    assign branch_condition = id_ex_branch_equal ? alu_eq : alu_slt;
    assign branch_eval = id_ex_branch & (branch_condition ^ id_ex_branch_invert);

    assign redirect_requested = id_ex_valid & (id_ex_jump | branch_eval) & ~id_ex_trap;
    assign branch_misaligned = redirect_requested && (|branch_target_calc[1:0]);
    assign branch_taken_ex = redirect_requested && !branch_misaligned;

    assign branch_target_calc =
        id_ex_pc_sel ? (ex_alu_result & ~32'd1) :
                       (id_ex_pc + id_ex_imm);

    assign branch_target_ex = branch_target_calc;

    // -------------------------------------------------------------------------
    // CHANGE 10: CHECKING MEMORY ALIGNMENT TRAPS
    // WHAT: Checks if a load or store uses an invalid unaligned address
    // (e.g. reading a 4-byte word from address 1 instead of 0 or 4).
    // WHY: If misaligned, mark this instruction as trapped so later stages can
    // prevent it from accidentally modifying RAM or registers.
    // -------------------------------------------------------------------------
    assign ex_dmem_byte_off = ex_alu_result[1:0];
    assign ex_dmem_misaligned = (id_ex_dmem_ren | id_ex_dmem_wen) &
                                    |(ex_dmem_byte_off & id_ex_dmem_align);
    assign ex_stage_trap = id_ex_trap | (id_ex_valid & ex_dmem_misaligned) | branch_misaligned | ex_rm_trap;

    // =========================================================================
    // 6. EX / MEM PIPELINE REGISTER (Tray between Execute and Memory)
    // -------------------------------------------------------------------------
    // CHANGE 11: PASSING EXECUTION RESULTS TO MEMORY STAGE
    // WHAT: Saves the computed ALU result, store data, and trap flags for Stage 4.
    // If the instruction trapped, force destination register rd to x0 so it can't write.
    // -------------------------------------------------------------------------
    









    







    

    always @(posedge i_clk) begin
        if (i_rst) begin
            ex_mem_pc          <= 32'h0000_0000;
            ex_mem_next_pc     <= 32'h0000_0000;
            ex_mem_inst        <= 32'h0000_0013;
            ex_mem_valid       <= 1'b0;
            ex_mem_trap        <= 1'b0;
            ex_mem_halt        <= 1'b0;
            ex_mem_rs1         <= 5'd0;
            ex_mem_rs2         <= 5'd0;
            ex_mem_rd          <= 5'd0;
            ex_mem_rs1_rdata   <= 32'd0;
            ex_mem_rs2_rdata   <= 32'd0;
            ex_mem_imm         <= 32'd0;
            ex_mem_alu_result  <= 32'd0;
            ex_mem_reg_write   <= 1'b0;
            ex_mem_dmem_ren    <= 1'b0;
            ex_mem_dmem_wen    <= 1'b0;
            ex_mem_dmem_align  <= 2'b00;
            ex_mem_dmem_memb   <= 1'b0;
            ex_mem_dmem_memh   <= 1'b0;
            ex_mem_dmem_memw   <= 1'b0;
            ex_mem_dmem_memu   <= 1'b0;
            ex_mem_rd_sel      <= 5'b00001;
        end else if (!pipe_stall) begin
            ex_mem_pc          <= id_ex_pc;
            ex_mem_next_pc     <= branch_taken_ex ? branch_target_calc : (id_ex_pc + 32'd4);
            ex_mem_inst        <= id_ex_inst;
            ex_mem_valid       <= id_ex_valid;
            ex_mem_trap        <= ex_stage_trap;
            ex_mem_halt        <= id_ex_halt;
            ex_mem_rs1         <= id_ex_rs1;
            ex_mem_rs2         <= id_ex_rs2;
            ex_mem_rd          <= ex_stage_trap ? 5'd0 : id_ex_rd;
            ex_mem_rs1_rdata   <= ex_rs1_val; // Save forwarded value used by ALU
            ex_mem_rs2_rdata   <= ex_rs2_val;
            ex_mem_imm         <= id_ex_imm;
            ex_mem_alu_result  <= id_ex_rd_sel[4] ? ex_int_result : ex_alu_result;
            ex_mem_reg_write   <= id_ex_valid & (id_ex_rd != 5'd0) & ~ex_stage_trap & ~id_ex_dmem_ren;
            ex_mem_dmem_ren    <= id_ex_dmem_ren & ~ex_stage_trap;
            ex_mem_dmem_wen    <= id_ex_dmem_wen & ~ex_stage_trap;
            ex_mem_dmem_align  <= id_ex_dmem_align;
            ex_mem_dmem_memb   <= id_ex_dmem_memb;
            ex_mem_dmem_memh   <= id_ex_dmem_memh;
            ex_mem_dmem_memw   <= id_ex_dmem_memw;
            ex_mem_dmem_memu   <= id_ex_dmem_memu;
            ex_mem_rd_sel      <= id_ex_rd_sel;
        end
    end

    // =========================================================================
    // 7. MEMORY ACCESS (MEM) STAGE
    // -------------------------------------------------------------------------
    // CHANGE 12: STORE DATA FORWARDING & CANCELING BAD MEMORY WRITES
    // WHAT: 
    // - Store forwarding: If saving to RAM and the value to store was just computed
    //   by the instruction in Writeback, take that value immediately (mem_store_src).
    // - Trap safety: If trapped, disable memory read and write completely.
    // -------------------------------------------------------------------------
    assign mem_byte_off = ex_mem_alu_result[1:0];

    assign mem_store_src = ex_mem_store_data;

    assign o_dmem_addr = {ex_mem_alu_result[31:2], 2'b00};
    assign o_dmem_ren  = ex_mem_dmem_ren & ~ex_mem_trap & ex_mem_valid;
    assign o_dmem_wen  = ex_mem_dmem_wen & ~ex_mem_trap & ex_mem_valid;

    assign o_dmem_mask =
        ex_mem_dmem_memw ? 4'b1111 :
        ex_mem_dmem_memh ? (mem_byte_off[1] ? 4'b1100 : 4'b0011) :
        ex_mem_dmem_memb ? (mem_byte_off == 2'b00 ? 4'b0001 :
                            mem_byte_off == 2'b01 ? 4'b0010 :
                            mem_byte_off == 2'b10 ? 4'b0100 :
                                                    4'b1000) :
                           4'b0000;

    assign o_dmem_wdata =
        ex_mem_dmem_memw ? mem_store_src :
        ex_mem_dmem_memh ? {2{mem_store_src[15:0]}} :
        ex_mem_dmem_memb ? {4{mem_store_src[7:0]}} :
                           32'b0;

    assign load_byte =
        (mem_byte_off == 2'b00) ? i_dmem_rdata[7:0]   :
        (mem_byte_off == 2'b01) ? i_dmem_rdata[15:8]  :
        (mem_byte_off == 2'b10) ? i_dmem_rdata[23:16] :
                                  i_dmem_rdata[31:24];

    assign load_half = mem_byte_off[1] ? i_dmem_rdata[31:16] : i_dmem_rdata[15:0];

    assign mem_load_data =
        ex_mem_dmem_memb ? (ex_mem_dmem_memu ? {24'b0, load_byte} : {{24{load_byte[7]}}, load_byte}) :
        ex_mem_dmem_memh ? (ex_mem_dmem_memu ? {16'b0, load_half} : {{16{load_half[15]}}, load_half}) :
                           i_dmem_rdata;

    // =========================================================================
    // 8. MEM / WB PIPELINE REGISTER (Tray between Memory and Writeback)
    // -------------------------------------------------------------------------
    // CHANGE 13: HOLDING DATA READY FOR WRITEBACK & SAVING MEMORY TRACE
    // WHAT: Latches the loaded memory data or ALU result into Stage 5 flip-flops.
    // Also saves the exact memory bus signals (address, mask, data) so the
    // testbench can inspect them at the exact moment this instruction retires.
    // -------------------------------------------------------------------------
























    always @(posedge i_clk) begin
        if (i_rst) begin
            mem_wb_pc            <= 32'h0000_0000;
            mem_wb_next_pc       <= 32'h0000_0000;
            mem_wb_inst          <= 32'h0000_0013;
            mem_wb_valid         <= 1'b0;
            mem_wb_trap          <= 1'b0;
            mem_wb_halt          <= 1'b0;
            mem_wb_rs1           <= 5'd0;
            mem_wb_rs2           <= 5'd0;
            mem_wb_rd            <= 5'd0;
            mem_wb_rs1_rdata     <= 32'd0;
            mem_wb_rs2_rdata     <= 32'd0;
            mem_wb_imm           <= 32'd0;
            mem_wb_alu_result    <= 32'd0;
            mem_wb_load_data     <= 32'd0;
            mem_wb_rd_sel        <= 5'b00001;
            mem_wb_reg_write_reg <= 1'b0;

            mem_wb_dmem_addr     <= 32'd0;
            mem_wb_dmem_ren      <= 1'b0;
            mem_wb_dmem_wen      <= 1'b0;
            mem_wb_dmem_mask     <= 4'b0000;
            mem_wb_dmem_wdata    <= 32'd0;
            mem_wb_dmem_rdata    <= 32'd0;
        end else if (!pipe_stall) begin
            mem_wb_pc            <= ex_mem_pc;
            mem_wb_next_pc       <= ex_mem_next_pc;
            mem_wb_inst          <= ex_mem_inst;
            mem_wb_valid         <= ex_mem_valid;
            mem_wb_trap          <= ex_mem_trap;
            mem_wb_halt          <= ex_mem_halt;
            mem_wb_rs1           <= ex_mem_rs1;
            mem_wb_rs2           <= ex_mem_rs2;
            mem_wb_rd <= ex_mem_trap ? 5'd0 : ex_mem_rd;
            mem_wb_rs1_rdata     <= ex_mem_rs1_rdata;
            mem_wb_rs2_rdata     <= ex_mem_rs2_rdata;
            mem_wb_imm           <= ex_mem_imm;
            mem_wb_alu_result    <= ex_mem_alu_result;
            mem_wb_load_data     <= mem_load_data;
            mem_wb_rd_sel        <= ex_mem_rd_sel;
            mem_wb_reg_write_reg <= ex_mem_valid & (ex_mem_rd != 5'd0) & ~ex_mem_trap;

            mem_wb_dmem_addr     <= o_dmem_addr;
            mem_wb_dmem_ren      <= o_dmem_ren;
            mem_wb_dmem_wen      <= o_dmem_wen;
            mem_wb_dmem_mask     <= o_dmem_mask;
            mem_wb_dmem_wdata    <= o_dmem_wdata;
            mem_wb_dmem_rdata    <= i_dmem_rdata;
        end
    end

    // =========================================================================
    // 9. WRITEBACK (WB) STAGE & RETIRE BUS
    // -------------------------------------------------------------------------
    // CHANGE 14: RETIRING ONLY COMPLETED INSTRUCTIONS
    // WHAT:
    // - Writeback: Pick which result to write to the register file (ALU, RAM, or PC+4).
    // - Retire bus: Output the instruction details directly from Stage 5.
    // - o_retire_valid stays low during bubbles, stalls, or flushes, and only turns
    //   high when a real instruction crosses the finish line.
    // -------------------------------------------------------------------------
    assign mem_wb_reg_write = mem_wb_reg_write_reg;

    assign wb_rd = mem_wb_trap ? 5'd0 : mem_wb_rd;

    assign wb_data =
        (mem_wb_rd_sel[0] || mem_wb_rd_sel[4]) ? mem_wb_alu_result :
        mem_wb_rd_sel[1] ? mem_wb_imm :
        mem_wb_rd_sel[2] ? (mem_wb_pc + 32'd4) :
                           mem_wb_load_data;

    // Retire Bus Outputs
    assign o_retire_valid     = mem_wb_valid && !pipe_stall && !i_rst;
    assign o_retire_inst      = mem_wb_inst;
    assign o_retire_trap      = mem_wb_trap;
    assign o_retire_halt      = mem_wb_halt;
    assign o_retire_rs1_raddr = mem_wb_rs1;
    assign o_retire_rs1_rdata = mem_wb_rs1_rdata;
    assign o_retire_rs2_raddr = mem_wb_rs2;
    assign o_retire_rs2_rdata = mem_wb_rs2_rdata;
    assign o_retire_rd_waddr  = wb_rd;
    assign o_retire_rd_wdata  = wb_data;
    assign o_retire_pc        = mem_wb_pc;
    assign o_retire_next_pc   = mem_wb_next_pc;

    // Retire Memory Operation Mirrors
    assign o_retire_dmem_addr  = mem_wb_dmem_addr;
    assign o_retire_dmem_ren   = mem_wb_dmem_ren;
    assign o_retire_dmem_wen   = mem_wb_dmem_wen;
    assign o_retire_dmem_mask  = mem_wb_dmem_mask;
    assign o_retire_dmem_wdata = mem_wb_dmem_wdata;
    assign o_retire_dmem_rdata = mem_wb_dmem_rdata;

    // Phase 6 FP pipeline metadata. No FP forwarding is required: ID stalls
    // until each producer reaches WB (or commits when bypass is disabled).













    assign wb_fp_data = mem_wb_fp_result;
    fpu u_fpu (
      .i_clk(i_clk), .i_rst(i_rst), .i_inst(id_ex_inst),
      .i_valid(id_ex_valid && id_ex_fpu && !id_ex_trap),
      .i_advance(ex_advance && !ex_stage_trap),
      .i_frs1(id_ex_f1), .i_frs2(id_ex_f2), .i_frs3(id_ex_f3),
      .i_xrs1(ex_rs1_val), .o_fp_result(ex_fp_result), .o_int_result(ex_int_result),
      .o_fflags(ex_fflags), .o_busy(fpu_busy), .o_rm_trap(ex_rm_trap)
    );
    always @(posedge i_clk) begin
        if (i_rst) begin
            id_ex_mext <= 0;
            id_ex_fpu <= 0;
            id_ex_frd <= 0;
            id_ex_fr1_en <= 0;
            id_ex_fr2_en <= 0;
            id_ex_fr3_en <= 0;
            id_ex_fr1 <= 0;
            id_ex_fr2 <= 0;
            id_ex_fr3 <= 0;
            id_ex_fd <= 0;
            id_ex_f1 <= 0;
            id_ex_f2 <= 0;
            id_ex_f3 <= 0;
        end else if (!pipe_stall) begin
          if (branch_taken_ex || load_use_stall) begin
            id_ex_mext <= 0;
            id_ex_fpu <= 0;
            id_ex_frd <= 0;
            id_ex_fr1_en <= 0;
            id_ex_fr2_en <= 0;
            id_ex_fr3_en <= 0;
            id_ex_fr1 <= 0;
            id_ex_fr2 <= 0;
            id_ex_fr3 <= 0;
            id_ex_fd <= 0;
            id_ex_f1 <= 0;
            id_ex_f2 <= 0;
            id_ex_f3 <= 0;
          end else begin
            id_ex_mext <= dec_mext;
            id_ex_fpu <= dec_fpu;
            id_ex_frd <= dec_frd;
            id_ex_fr1_en <= dec_frs1;
            id_ex_fr2_en <= dec_frs2;
            id_ex_fr3_en <= dec_frs3;
            id_ex_fr1 <= dec_frs1 ? dec_rs1 : 5'd0;
            id_ex_fr2 <= dec_frs2 ? dec_rs2 : 5'd0;
            id_ex_fr3 <= dec_frs3 ? dec_rs3 : 5'd0;
            id_ex_fd <= if_id_inst[11:7];
            id_ex_f1 <= rf_f1;
            id_ex_f2 <= rf_f2;
            id_ex_f3 <= rf_f3;
          end
        end
    end
    always @(posedge i_clk) begin
        if (i_rst) begin
            ex_mem_frd <= 0;
            ex_mem_fd <= 0;
            ex_mem_fr1 <= 0;
            ex_mem_fr2 <= 0;
            ex_mem_fr3 <= 0;
            ex_mem_f1 <= 0;
            ex_mem_f2 <= 0;
            ex_mem_f3 <= 0;
            ex_mem_fp_result <= 0;
            ex_mem_fflags <= 0;
            ex_mem_store_data <= 0;
        end else if (!pipe_stall) begin
            ex_mem_frd <= id_ex_frd && id_ex_valid && !ex_stage_trap;
            ex_mem_fd <= id_ex_fd;
            ex_mem_fr1 <= id_ex_fr1;
            ex_mem_fr2 <= id_ex_fr2;
            ex_mem_fr3 <= id_ex_fr3;
            ex_mem_f1 <= id_ex_f1;
            ex_mem_f2 <= id_ex_f2;
            ex_mem_f3 <= id_ex_f3;
            ex_mem_fp_result <= ex_fp_result;
            ex_mem_fflags <= ex_fflags;
            ex_mem_store_data <= id_ex_fr2_en ? id_ex_f2 : ex_rs2_val;
        end
    end
    always @(posedge i_clk) begin
        if (i_rst) begin
            mem_wb_frd <= 0;
            mem_wb_fd <= 0;
            mem_wb_fr1 <= 0;
            mem_wb_fr2 <= 0;
            mem_wb_fr3 <= 0;
            mem_wb_f1 <= 0;
            mem_wb_f2 <= 0;
            mem_wb_f3 <= 0;
            mem_wb_fp_result <= 0;
            mem_wb_fflags <= 0;
        end else if (!pipe_stall) begin
            mem_wb_frd <= ex_mem_frd;
            mem_wb_fd <= ex_mem_fd;
            mem_wb_fr1 <= ex_mem_fr1;
            mem_wb_fr2 <= ex_mem_fr2;
            mem_wb_fr3 <= ex_mem_fr3;
            mem_wb_f1 <= ex_mem_f1;
            mem_wb_f2 <= ex_mem_f2;
            mem_wb_f3 <= ex_mem_f3;
            mem_wb_fp_result <= ex_mem_dmem_ren ? mem_load_data : ex_mem_fp_result;
            mem_wb_fflags <= ex_mem_fflags;
        end
    end
    assign o_retire_frs1_raddr = mem_wb_fr1;
    assign o_retire_frs1_rdata = mem_wb_f1;
    assign o_retire_frs2_raddr = mem_wb_fr2;
    assign o_retire_frs2_rdata = mem_wb_f2;
    assign o_retire_frs3_raddr = mem_wb_fr3;
    assign o_retire_frs3_rdata = mem_wb_f3;
    assign o_retire_frd_wen = mem_wb_frd && mem_wb_valid && !mem_wb_trap;
    assign o_retire_frd_waddr = mem_wb_fd;
    assign o_retire_frd_wdata = wb_fp_data;
    assign o_retire_fflags = mem_wb_fflags;

endmodule

`default_nettype wire