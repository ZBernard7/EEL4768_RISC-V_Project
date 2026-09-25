`default_nettype none

// AI USE DISCLOSURE:
// OpenAI ChatGPT was used as an aid in the development of this file.
// Accessed September 2026.

// A hart ("hardware thread") is one complete RISC-V CPU: it fetches an
// instruction, decodes it, executes it, and writes the result back. This one
// is single-cycle, so all four of those happen in the same clock cycle and
// exactly one instruction retires every cycle -- there are no bubbles and no
// pipeline stages.
//
// You do not write the datapath blocks again here. Instantiate the four
// modules from phase 2 (`alu`, `rf`, `decoder`, which itself contains `imm`)
// and wire them together, then add the parts phase 2 did not have: the
// program counter, the branch/jump target logic, and the memory interfaces.
//
// Remember the two small changes phase 3 needs from your phase 2 modules:
// `rf` is instantiated with BYPASS_EN = 0 (a single-cycle design writes back
// on the same edge the next read samples, so there is nothing to bypass),
// and `rf` no longer has a write enable -- gate a write by driving its write
// address to 5'd0 instead. Do not instantiate a second copy of `imm`; your
// `decoder` already contains one.
module hart #(
    // The address the program counter is initialized to on reset. The first
    // instruction to retire after `i_rst` deasserts must be the one fetched
    // from this address.
    parameter RESET_ADDR = 32'h00000000
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,

    // ---- Instruction memory ------------------------------------------
    // The instruction memory is external to your design, read-only, and
    // combinational: the word at `o_imem_raddr` appears on `i_imem_rdata`
    // in the same cycle, with no clock edge and no latency.
    //
    // Address of the instruction to fetch. One instruction per cycle,
    // always 4-byte aligned.
    output wire [31:0] o_imem_raddr,
    // The instruction word stored at `o_imem_raddr`.
    input  wire [31:0] i_imem_rdata,

    // ---- Data memory -------------------------------------------------
    // The data memory is also external and combinational: reads need no
    // clock edge, and writes commit on the next clock edge.
    //
    // Data address. This is **always word-aligned** -- the low two bits of
    // the computed byte address never reach memory. Which bytes inside that
    // word are touched is `o_dmem_mask`'s job, not the address's.
    output wire [31:0] o_dmem_addr,
    // Read enable. Must never be high in the same cycle as `o_dmem_wen`.
    output wire        o_dmem_ren,
    // Write enable.
    output wire        o_dmem_wen,
    // Store data. Only the byte lanes selected by `o_dmem_mask` are used;
    // the rest are ignored, so they may hold anything. For a sub-word store
    // (`sb`, `sh`), the byte(s) must be positioned in the lane(s) they are
    // being written to, not left at the bottom of the word.
    output wire [31:0] o_dmem_wdata,
    // Which of the four byte lanes of the word at `o_dmem_addr` are read or
    // written. A byte access asserts one lane, a half-word two adjacent
    // lanes, and a word all four.
    output wire [ 3:0] o_dmem_mask,
    // The full 32-bit word at `o_dmem_addr`, regardless of the mask.
    // Extracting the requested bytes and sign- or zero-extending them
    // (`lb`/`lh` vs `lbu`/`lhu`) is this module's job.
    input  wire [31:0] i_dmem_rdata,

    // ---- Retire interface --------------------------------------------
    // These outputs are not part of RV32I. They exist so a testbench can see
    // what your design actually did each cycle. Drive every one of them
    // appropriately on every cycle; all of them are checked on every
    // retiring instruction.
    //
    // An instruction retired this cycle. Because the design is
    // single-cycle, this is high every cycle after `i_rst` deasserts,
    // through the cycle `o_retire_halt` fires.
    output wire        o_retire_valid,
    // The raw instruction word that was fetched and retired this cycle.
    output wire [31:0] o_retire_inst,
    // The instruction was an illegal encoding, or a misaligned data access
    // (a half-word access at an odd address, or a word access at an address
    // that is not a multiple of four -- a byte access is never misaligned).
    // A trapping instruction has no side effects: no memory access happens,
    // `o_retire_rd_waddr` is 5'd0, and control flow is not redirected
    // (there is no trap vector in this interface, so `o_retire_next_pc` is
    // still the pc plus four).
    output wire        o_retire_trap,
    // The instruction is `ebreak`, and execution should halt. Like a trap,
    // it reads nothing, writes nothing, and touches no memory.
    output wire        o_retire_halt,
    // First source register address, and the value read from it.
    // Instructions that do not read a first source register (`lui`,
    // `auipc`, `jal`, and illegal encodings) must report 5'd0 here.
    output wire [ 4:0] o_retire_rs1_raddr,
    output wire [31:0] o_retire_rs1_rdata,
    // Second source register address, and the value read from it. Only
    // R-type, store and branch instructions read a second source register;
    // everything else must report 5'd0 here.
    output wire [ 4:0] o_retire_rs2_raddr,
    output wire [31:0] o_retire_rs2_rdata,
    // Destination register address, and the value written to it. When the
    // instruction writes no register, this address must be 5'd0 -- the same
    // convention the decoder used in phase 2, and what discards the write
    // in the register file. The address is checked on every instruction,
    // including trapping ones; the data only matters when the address is
    // nonzero.
    output wire [ 4:0] o_retire_rd_waddr,
    output wire [31:0] o_retire_rd_wdata,
    // The address this instruction was fetched from.
    output wire [31:0] o_retire_pc,
    // The address the next instruction will be fetched from: the pc plus
    // four, or the branch or jump target when a branch is taken or a jump
    // is executed. This is what proves your branch targets, `jal`/`jalr`
    // targets, and `jalr`'s cleared low bit are right.
    output wire [31:0] o_retire_next_pc
);
  
    // =========================================================================
    // SECTION 1: Instruction Slicing & Control Identification
    // -------------------------------------------------------------------------
    // What it does:
    //   Extracts the opcode and funct3 fields from the fetched instruction word
    //   and identifies whether the instruction is a branch, JAL, or JALR.
    //
    // Design Choice for Smooth Running:
    //   Used localparam constants rather than raw literals in comparisons. This
    //   keeps the control logic clean, self-documenting, and avoids magic numbers.
    // =========================================================================
    
    // Zahra's Notes:
    // Everything about "what kind of instruction is this" now comes out of
    // the decoder instead of being re-derived here. Basically our
    // immediate is already the right one for whatever instruction so there's
    // no need to compute imm_b/imm_j/imm_i 
    // and no second imm.v instance (decoder already has one inside it).

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
        .i_inst            (i_imem_rdata),
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

    // =========================================================================
    // SECTION 2: Immediate Generation (Offset Reconstruction)
    // -------------------------------------------------------------------------
    // What it does:
    //   Unscrambles the scattered immediate bits for B, J, and I instruction
    //   types and sign-extends them into full 32-bit signed offsets.
    // =========================================================================

    // Handled internally by decoder and imm.v.

    // =========================================================================
    // SECTION 3: Register File Instantiation & Datapath Interface
    // -------------------------------------------------------------------------
    // What it does:
    //   Slices register address fields (rs1, rs2) from the instruction and plugs
    //   in rf.v so read data is immediately available to target and ALU logic.
    // =========================================================================

    wire [31:0] rs1_rdata, rs2_rdata;
    wire [ 4:0] rf_waddr;
    wire [31:0] rf_wdata;

    rf #(.BYPASS_EN(0)) u_rf (
        .i_clk      (i_clk),
        .i_rst      (i_rst),
        .i_rs1_raddr(dec_rs1),
        .o_rs1_rdata(rs1_rdata),
        .i_rs2_raddr(dec_rs2),
        .o_rs2_rdata(rs2_rdata),
        .i_rd_waddr (rf_waddr),
        .i_rd_wdata (rf_wdata)
    );

    reg  [31:0] pc;
    wire [31:0] alu_op1 = dec_op1_sel ? pc : rs1_rdata;
    wire [31:0] alu_op2 = dec_op2_sel ? dec_imm : rs2_rdata;

    wire [31:0] alu_result;
    wire        alu_eq, alu_slt, alu_sltu;

    alu u_alu (
        .i_opsel   (dec_alu_opsel),
        .i_sub     (dec_alu_sub),
        .i_unsigned(dec_alu_unsigned),
        .i_arith   (dec_alu_arith),
        .i_op1     (alu_op1),
        .i_op2     (alu_op2),
        .o_result  (alu_result),
        .o_eq      (alu_eq),
        .o_slt     (alu_slt),
        .o_sltu    (alu_sltu)
    );

    // =========================================================================
    // SECTION 4: Program Counter Arithmetic & Target Calculations
    // -------------------------------------------------------------------------
    // What it does:
    //   Calculates every candidate next-PC address in parallel combinational logic:
    //     - pc_plus_4: Sequential instruction step.
    //     - rel_target: Relative offset from PC for conditional branches and JAL.
    //     - jalr_target: Absolute base-plus-offset address from register rs1.
    // =========================================================================

    wire is_lui   = dec_rd_sel[1];
    wire is_auipc = dec_op1_sel;
    wire is_jal   = dec_jump & ~dec_pc_sel;

    wire [31:0] pc_plus_4   = pc + 32'd4;
    wire [31:0] rel_target  = pc + dec_imm;
    wire [31:0] jalr_target = alu_result & ~32'd1;

    // =========================================================================
    // SECTION 5: Branch Condition Evaluation
    // -------------------------------------------------------------------------
    // What it does:
    //   Inspects funct3 to select the comparison operation and tests against
    //   the ALU condition flags.
    // =========================================================================

    wire branch_condition = dec_branch_equal ? alu_eq : alu_slt;
    wire branch_taken     = dec_branch & (branch_condition ^ dec_branch_invert);

    // =========================================================================
    // SECTION 6: PCSrc Selection Multiplexer & Trap Handling
    // -------------------------------------------------------------------------
    // What it does:
    //   Decides which calculated address becomes next_pc for the next clock cycle.
    // =========================================================================

    wire [1:0] dmem_byte_off   = alu_result[1:0];
    wire       dmem_misaligned = (dec_dmem_ren | dec_dmem_wen) &
                                  |(dmem_byte_off & dec_dmem_align);
    wire       trap = ~dec_legal | dmem_misaligned;

    wire [31:0] next_pc =
        trap                      ? pc_plus_4   :
        dec_pc_sel                ? jalr_target :
        (dec_jump | branch_taken) ? rel_target  :
                                     pc_plus_4;

    // =========================================================================
    // SECTION 7: Program Counter State Register & Interface Routing
    // -------------------------------------------------------------------------
    // What it does:
    //   Implements the sequential state element storing the PC and routes
    //   addresses to instruction memory and the retire bus.
    // =========================================================================

    always @(posedge i_clk) begin
        if (i_rst) begin
            pc <= RESET_ADDR;
        end else begin
            pc <= next_pc;
        end
    end

    assign o_imem_raddr     = pc;
    assign o_retire_pc      = pc;
    assign o_retire_next_pc = next_pc;

    // =========================================================================
    // SECTION 8: Data Memory Interface & Writeback Logic
    // =========================================================================

    assign o_dmem_addr = {alu_result[31:2], 2'b00};
    assign o_dmem_ren  = dec_dmem_ren & ~trap;
    assign o_dmem_wen  = dec_dmem_wen & ~trap;

    assign o_dmem_mask =
        dec_dmem_memw ? 4'b1111 :
        dec_dmem_memh ? (dmem_byte_off[1] ? 4'b1100 : 4'b0011) :
        dec_dmem_memb ? (dmem_byte_off == 2'b00 ? 4'b0001 :
                         dmem_byte_off == 2'b01 ? 4'b0010 :
                         dmem_byte_off == 2'b10 ? 4'b0100 :
                                                   4'b1000) :
                         4'b0000;

    // Replicate sub-word data across lanes so active lane(s) capture valid bits
    assign o_dmem_wdata =
        dec_dmem_memw ? rs2_rdata :
        dec_dmem_memh ? {2{rs2_rdata[15:0]}} :
        dec_dmem_memb ? {4{rs2_rdata[7:0]}} :
                        32'b0;

    wire [7:0] load_byte =
        (dmem_byte_off == 2'b00) ? i_dmem_rdata[7:0]   :
        (dmem_byte_off == 2'b01) ? i_dmem_rdata[15:8]  :
        (dmem_byte_off == 2'b10) ? i_dmem_rdata[23:16] :
                                   i_dmem_rdata[31:24];

    wire [15:0] load_half = dmem_byte_off[1] ? i_dmem_rdata[31:16] : i_dmem_rdata[15:0];

    wire [31:0] load_data =
        dec_dmem_memb ? (dec_dmem_memu ? {24'b0, load_byte} : {{24{load_byte[7]}}, load_byte}) :
        dec_dmem_memh ? (dec_dmem_memu ? {16'b0, load_half} : {{16{load_half[15]}}, load_half}) :
                        i_dmem_rdata;

    wire [31:0] writeback_data =
        dec_rd_sel[0] ? alu_result :
        dec_rd_sel[1] ? dec_imm :
        dec_rd_sel[2] ? pc_plus_4 :
                        load_data;

    assign rf_waddr = trap ? 5'd0 : dec_rd;
    assign rf_wdata = writeback_data;

    // =========================================================================
    // SECTION 9: Retire Interface
    // =========================================================================

    assign o_retire_valid = ~i_rst;
    assign o_retire_inst  = i_imem_rdata;
    assign o_retire_trap  = trap;
    assign o_retire_halt  = dec_halt;

    wire is_r_type =
        dec_legal & ~dec_halt &
        ~dec_op2_sel & ~dec_branch &
        ~is_lui & ~is_jal & ~is_auipc;

    wire reads_rs1 =
        dec_legal & ~dec_halt &
        ~is_lui & ~is_auipc & ~is_jal;

    wire reads_rs2 =
        dec_legal & ~dec_halt &
        (is_r_type | dec_branch | dec_dmem_wen);

    assign o_retire_rs1_raddr = reads_rs1 ? dec_rs1 : 5'd0;
    assign o_retire_rs1_rdata = reads_rs1 ? rs1_rdata : 32'd0;
    assign o_retire_rs2_raddr = reads_rs2 ? dec_rs2 : 5'd0;
    assign o_retire_rs2_rdata = reads_rs2 ? rs2_rdata : 32'd0;

    assign o_retire_rd_waddr = rf_waddr;
    assign o_retire_rd_wdata = rf_wdata;

endmodule

`default_nettype wire