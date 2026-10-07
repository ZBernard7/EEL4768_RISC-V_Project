`default_nettype none

// AI USE DISCLOSURE:
// OpenAI ChatGPT and Claude were used as aids in the development of this file.
// Accessed October 2026.

module hart #(
    // -------------------------------------------------------------------------
    // CHANGE 1: STARTING ADDRESS
    // WHAT: Changed RESET_ADDR from 0 to 0x00400000.
    // WHY: Phase 4 test programs are loaded starting at 0x00400000 instead of 0.
    // -------------------------------------------------------------------------
    parameter RESET_ADDR = 32'h0040_0000
) (
    input  wire        i_clk,
    input  wire        i_rst,

    // ---- Instruction memory ------------------------------------------
    output wire [31:0] o_imem_raddr,
    input  wire [31:0] i_imem_rdata,

    // ---- Data memory -------------------------------------------------
    output wire [31:0] o_dmem_addr,
    output wire        o_dmem_ren,
    output wire        o_dmem_wen,
    output wire [31:0] o_dmem_wdata,
    output wire [ 3:0] o_dmem_mask,
    input  wire [31:0] i_dmem_rdata,

    // ---- Retire interface --------------------------------------------
    output wire        o_retire_valid,
    output wire [31:0] o_retire_inst,
    output wire        o_retire_trap,
    output wire        o_retire_halt,
    output wire [ 4:0] o_retire_rs1_raddr,
    output wire [31:0] o_retire_rs1_rdata,
    output wire [ 4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs2_rdata,
    output wire [ 4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,
    output wire [31:0] o_retire_pc,
    output wire [31:0] o_retire_next_pc,

    // -------------------------------------------------------------------------
    // CHANGE 2: MEMORY CHECK PORTS FOR THE TESTBENCH
    // WHAT: Added 6 new outputs named o_retire_dmem_*.
    // WHY: In a pipeline, a load or store touches memory in stage 4, but the testbench
    // checks the instruction when it completely finishes in stage 5. These ports
    // hold onto the memory info and output it during stage 5 so the grader can see it.
    // -------------------------------------------------------------------------
    output wire [31:0] o_retire_dmem_addr,
    output wire        o_retire_dmem_ren,
    output wire        o_retire_dmem_wen,
    output wire [ 3:0] o_retire_dmem_mask,
    output wire [31:0] o_retire_dmem_wdata,
    output wire [31:0] o_retire_dmem_rdata
);

    // =========================================================================
    // Signals fed backwards from later stages
    // =========================================================================
    wire        branch_taken_ex;
    wire [31:0] branch_target_ex;
    wire        load_use_stall;

    // =========================================================================
    // 1. INSTRUCTION FETCH (IF) STAGE
    // -------------------------------------------------------------------------
    // CHANGE 3: UPDATING THE PROGRAM COUNTER (PC)
    // WHAT: Decide the next instruction address:
    //   1. If a branch/jump in Execute was taken, jump to the branch target.
    //   2. If we are paused for a load-use stall, freeze the PC in place.
    //   3. Otherwise, keep walking forward normally (pc + 4).
    // -------------------------------------------------------------------------
    reg  [31:0] pc_reg;
    wire [31:0] pc_plus_4_if = pc_reg + 32'd4;

    wire [31:0] next_pc = branch_taken_ex ? branch_target_ex :
                          load_use_stall  ? pc_reg :
                                            pc_plus_4_if;

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc_reg <= RESET_ADDR;
        end else begin
            pc_reg <= next_pc;
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
    reg [31:0] if_id_pc;
    reg [31:0] if_id_inst;
    reg        if_id_valid;

    always @(posedge i_clk) begin
        if (i_rst || branch_taken_ex) begin
            if_id_pc    <= 32'h0000_0000;
            if_id_inst  <= 32'h0000_0013; // RISC-V NOP: addi x0, x0, 0
            if_id_valid <= 1'b0;
        end else if (!load_use_stall) begin
            if_id_pc    <= pc_reg;
            if_id_inst  <= i_imem_rdata;
            if_id_valid <= 1'b1;
        end
    end

    // =========================================================================
    // 3. INSTRUCTION DECODE (ID) STAGE
    // =========================================================================
    wire        dec_legal, dec_halt;
    wire [ 4:0] dec_rs1, dec_rs2, dec_rd;
    wire [31:0] dec_imm;
    wire        dec_op1_sel, dec_op2_sel;
    wire [ 2:0] dec_alu_opsel;
    wire        dec_alu_sub, dec_alu_unsigned, dec_alu_arith;
    wire        dec_branch, dec_jump;
    wire        dec_branch_equal, dec_branch_unsigned, dec_branch_invert;
    wire        dec_dmem_ren, dec_dmem_wen;
    wire [ 1:0] dec_dmem_align;
    wire        dec_dmem_memb, dec_dmem_memh, dec_dmem_memw, dec_dmem_memu;
    wire [ 3:0] dec_rd_sel;
    wire        dec_pc_sel;

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
        .o_pc_sel          (dec_pc_sel)
    );

    // -------------------------------------------------------------------------
    // CHANGE 5: SAME-CYCLE REGISTER BYPASS (BYPASS_EN = 1)
    // WHAT: Turn on BYPASS_EN = 1 inside rf.v.
    // WHY: If Stage 5 is writing a result into a register on the exact same clock
    // tick Stage 2 is trying to read it, this makes the register file immediately
    // hand over the new value without making us wait an extra cycle.
    // -------------------------------------------------------------------------
    wire [31:0] rf_rs1_rdata, rf_rs2_rdata;
    wire [ 4:0] wb_rd;
    wire [31:0] wb_data;

    rf #(.BYPASS_EN(1)) u_rf (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(dec_rs1),
        .o_rs1_rdata(rf_rs1_rdata),
        .i_rs2_raddr(dec_rs2),
        .o_rs2_rdata(rf_rs2_rdata),
        .i_rd_waddr (wb_rd),
        .i_rd_wdata (wb_data)
    );

    wire id_trap = if_id_valid & ~dec_legal;

    // -------------------------------------------------------------------------
    // CHANGE 6: LOAD-USE HAZARD DETECTOR (THE PAUSE BUTTON)
    // WHAT: Check if the instruction currently in Execute is loading from RAM,
    // and the instruction right behind it in Decode wants to use that same register.
    // WHY: RAM data isn't ready yet, so we can't forward it. We must pause the
    // pipeline for 1 clock tick by inserting a blank bubble (NOP) into Execute.
    // -------------------------------------------------------------------------
    reg        id_ex_dmem_ren;
    reg  [4:0] id_ex_rd; // Declared here for the hazard check; not re-declared below

    assign load_use_stall = if_id_valid && id_ex_dmem_ren && (id_ex_rd != 5'd0) &&
                            (((dec_rs1 != 5'd0) && (id_ex_rd == dec_rs1)) ||
                             ((dec_rs2 != 5'd0) && (id_ex_rd == dec_rs2)));

    // =========================================================================
    // 4. ID / EX PIPELINE REGISTER (Tray between Decode and Execute)
    // -------------------------------------------------------------------------
    // CHANGE 7: PASSING DECODED INFO TO EXECUTE
    // WHAT: Latch control signals, register numbers, and read data into flip-flops.
    // If we have to pause (load_use_stall) or toss out a bad guess (branch_taken),
    // clear this register to zero so it acts as a do-nothing bubble (NOP).
    // -------------------------------------------------------------------------
    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_inst;
    reg        id_ex_valid;
    reg        id_ex_trap;
    reg        id_ex_halt;
    reg [ 4:0] id_ex_rs1;
    reg [ 4:0] id_ex_rs2;
    // NOTE: id_ex_rd declared above
    reg [31:0] id_ex_rs1_rdata;
    reg [31:0] id_ex_rs2_rdata;
    reg [31:0] id_ex_imm;
    reg        id_ex_op1_sel;
    reg        id_ex_op2_sel;
    reg [ 2:0] id_ex_alu_opsel;
    reg        id_ex_alu_sub;
    reg        id_ex_alu_unsigned;
    reg        id_ex_alu_arith;
    reg        id_ex_branch;
    reg        id_ex_jump;
    reg        id_ex_branch_equal;
    reg        id_ex_branch_unsigned;
    reg        id_ex_branch_invert;
    reg        id_ex_dmem_wen;
    reg [ 1:0] id_ex_dmem_align;
    reg        id_ex_dmem_memb;
    reg        id_ex_dmem_memh;
    reg        id_ex_dmem_memw;
    reg        id_ex_dmem_memu;
    reg [ 3:0] id_ex_rd_sel;
    reg        id_ex_pc_sel;

    always @(posedge i_clk) begin
        if (i_rst || branch_taken_ex || load_use_stall) begin
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
            id_ex_rd_sel          <= 4'b0001;
            id_ex_pc_sel          <= 1'b0;
        end else begin
            id_ex_pc              <= if_id_pc;
            id_ex_inst            <= if_id_inst;
            id_ex_valid           <= if_id_valid;
            id_ex_trap            <= id_trap;
            id_ex_halt            <= dec_halt;
            id_ex_rs1             <= dec_rs1;
            id_ex_rs2             <= dec_rs2;
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
    reg  [ 4:0] ex_mem_rd;
    reg  [31:0] ex_mem_alu_result;
    reg         ex_mem_reg_write;
    wire        mem_wb_reg_write;

    wire [1:0] forward_a =
        (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1)) ? 2'b10 :
        (mem_wb_reg_write && (wb_rd != 5'd0)     && (wb_rd == id_ex_rs1))     ? 2'b01 :
                                                                                 2'b00;

    wire [1:0] forward_b =
        (ex_mem_reg_write && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2)) ? 2'b10 :
        (mem_wb_reg_write && (wb_rd != 5'd0)     && (wb_rd == id_ex_rs2))     ? 2'b01 :
                                                                                 2'b00;

    // Select the actual result computed in the EX/MEM stage
    // (Handles ALU, LUI/AUIPC immediates, and JAL/JALR return addresses)
    wire [31:0] ex_mem_stage_val =
        ex_mem_rd_sel[0] ? ex_mem_alu_result :
        ex_mem_rd_sel[1] ? ex_mem_imm :
        ex_mem_rd_sel[2] ? (ex_mem_pc + 32'd4) :
                           ex_mem_alu_result;

    wire [31:0] ex_rs1_val = (forward_a == 2'b10) ? ex_mem_stage_val :
                             (forward_a == 2'b01) ? wb_data :
                                                    id_ex_rs1_rdata;

    wire [31:0] ex_rs2_val = (forward_b == 2'b10) ? ex_mem_stage_val :
                             (forward_b == 2'b01) ? wb_data :
                                                    id_ex_rs2_rdata;
                                                    
    // ALU Inputs (picks either the forwarded register value, PC, or immediate)
    wire [31:0] alu_op1 = id_ex_op1_sel ? id_ex_pc  : ex_rs1_val;
    wire [31:0] alu_op2 = id_ex_op2_sel ? id_ex_imm : ex_rs2_val;

    wire [31:0] ex_alu_result;
    wire        alu_eq, alu_slt, alu_sltu;

    alu u_alu (
        .i_opsel   (id_ex_alu_opsel),
        .i_sub     (id_ex_alu_sub),
        .i_unsigned(id_ex_alu_unsigned),
        .i_arith   (id_ex_alu_arith),
        .i_op1     (alu_op1),
        .i_op2     (alu_op2),
        .o_result  (ex_alu_result),
        .o_eq      (alu_eq),
        .o_slt     (alu_slt),
        .o_sltu    (alu_sltu)
    );

    // -------------------------------------------------------------------------
    // CHANGE 9: CHECKING BRANCHES HERE IN EXECUTE
    // WHAT: Compare the forwarded numbers in the ALU to decide if the branch is taken.
    // WHY: Section 4.1.3 explicitly requires checking branch conditions in Execute.
    // If it is taken, branch_taken_ex turns high and clears wrong guesses in IF/ID.
    // -------------------------------------------------------------------------
    wire branch_condition = id_ex_branch_equal ? alu_eq : alu_slt;
    wire branch_eval      = id_ex_branch & (branch_condition ^ id_ex_branch_invert);

    assign branch_taken_ex = id_ex_valid & (id_ex_jump | branch_eval) & ~id_ex_trap;

    wire [31:0] branch_target_calc =
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
    wire [1:0] ex_dmem_byte_off   = ex_alu_result[1:0];
    wire       ex_dmem_misaligned = (id_ex_dmem_ren | id_ex_dmem_wen) &
                                    |(ex_dmem_byte_off & id_ex_dmem_align);
    wire       ex_stage_trap      = id_ex_trap | (id_ex_valid & ex_dmem_misaligned);

    // =========================================================================
    // 6. EX / MEM PIPELINE REGISTER (Tray between Execute and Memory)
    // -------------------------------------------------------------------------
    // CHANGE 11: PASSING EXECUTION RESULTS TO MEMORY STAGE
    // WHAT: Saves the computed ALU result, store data, and trap flags for Stage 4.
    // If the instruction trapped, force destination register rd to x0 so it can't write.
    // -------------------------------------------------------------------------
    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_next_pc;
    reg [31:0] ex_mem_inst;
    reg        ex_mem_valid;
    reg        ex_mem_trap;
    reg        ex_mem_halt;
    reg [ 4:0] ex_mem_rs1;
    reg [ 4:0] ex_mem_rs2;
    reg [31:0] ex_mem_rs1_rdata;
    reg [31:0] ex_mem_rs2_rdata;
    reg [31:0] ex_mem_imm;
    reg        ex_mem_dmem_ren;
    reg        ex_mem_dmem_wen;
    reg [ 1:0] ex_mem_dmem_align;
    reg        ex_mem_dmem_memb;
    reg        ex_mem_dmem_memh;
    reg        ex_mem_dmem_memw;
    reg        ex_mem_dmem_memu;
    reg [ 3:0] ex_mem_rd_sel;

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
            ex_mem_rd_sel      <= 4'b0001;
        end else begin
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
            ex_mem_alu_result  <= ex_alu_result;
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
    wire [1:0] mem_byte_off = ex_mem_alu_result[1:0];

    wire [31:0] mem_store_src =
        (mem_wb_reg_write && (wb_rd != 5'd0) && (wb_rd == ex_mem_rs2)) ? wb_data :
                                                                         ex_mem_rs2_rdata;

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

    wire [7:0] load_byte =
        (mem_byte_off == 2'b00) ? i_dmem_rdata[7:0]   :
        (mem_byte_off == 2'b01) ? i_dmem_rdata[15:8]  :
        (mem_byte_off == 2'b10) ? i_dmem_rdata[23:16] :
                                  i_dmem_rdata[31:24];

    wire [15:0] load_half = mem_byte_off[1] ? i_dmem_rdata[31:16] : i_dmem_rdata[15:0];

    wire [31:0] mem_load_data =
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
    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_next_pc;
    reg [31:0] mem_wb_inst;
    reg        mem_wb_valid;
    reg        mem_wb_trap;
    reg        mem_wb_halt;
    reg [ 4:0] mem_wb_rs1;
    reg [ 4:0] mem_wb_rs2;
    reg [ 4:0] mem_wb_rd;
    reg [31:0] mem_wb_rs1_rdata;
    reg [31:0] mem_wb_rs2_rdata;
    reg [31:0] mem_wb_imm;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_load_data;
    reg [ 3:0] mem_wb_rd_sel;
    reg        mem_wb_reg_write_reg;

    reg [31:0] mem_wb_dmem_addr;
    reg        mem_wb_dmem_ren;
    reg        mem_wb_dmem_wen;
    reg [ 3:0] mem_wb_dmem_mask;
    reg [31:0] mem_wb_dmem_wdata;
    reg [31:0] mem_wb_dmem_rdata;

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
            mem_wb_rd_sel        <= 4'b0001;
            mem_wb_reg_write_reg <= 1'b0;

            mem_wb_dmem_addr     <= 32'd0;
            mem_wb_dmem_ren      <= 1'b0;
            mem_wb_dmem_wen      <= 1'b0;
            mem_wb_dmem_mask     <= 4'b0000;
            mem_wb_dmem_wdata    <= 32'd0;
            mem_wb_dmem_rdata    <= 32'd0;
        end else begin
            mem_wb_pc            <= ex_mem_pc;
            mem_wb_next_pc       <= ex_mem_next_pc;
            mem_wb_inst          <= ex_mem_inst;
            mem_wb_valid         <= ex_mem_valid;
            mem_wb_trap          <= ex_mem_trap;
            mem_wb_halt          <= ex_mem_halt;
            mem_wb_rs1           <= ex_mem_rs1;
            mem_wb_rs2           <= ex_mem_rs2;
            mem_wb_rd            <= mem_wb_trap ? 5'd0 : ex_mem_rd;
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
        mem_wb_rd_sel[0] ? mem_wb_alu_result :
        mem_wb_rd_sel[1] ? mem_wb_imm :
        mem_wb_rd_sel[2] ? (mem_wb_pc + 32'd4) :
                           mem_wb_load_data;

    // Retire Bus Outputs
    assign o_retire_valid     = mem_wb_valid;
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

endmodule

`default_nettype wire