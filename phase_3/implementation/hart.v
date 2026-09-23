`default_nettype none

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
    
    //Zahra's Notes
    //Everything about "what kind of instruction is this" now comes out of
    // the decoder instead of being re-derived here. Basically our
    // immeidate is already the right one for whatever instruction so theres
    // no need to compute imm_b/imm_j/imm_i 
    // and no second imm.v instance (decoder already has one inside it).
    // wire [6:0] opcode = i_imem_rdata[6:0];
    // wire [2:0] funct3 = i_imem_rdata[14:12];

    // localparam OPCODE_BRANCH = 7'b1100011; // B-type conditional branches
    // localparam OPCODE_JAL    = 7'b1101111; // J-type unconditional jump
    // localparam OPCODE_JALR   = 7'b1100111; // I-type register-indirect jump

    // wire is_branch = (opcode == OPCODE_BRANCH);
    // wire is_jal    = (opcode == OPCODE_JAL);
    // wire is_jalr   = (opcode == OPCODE_JALR);

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
    //
    // Design Choice for Smooth Running:
    //   Hardcoded bit-0 to 1'b0 directly in imm_b and imm_j concatenations.
    //   Because RISC-V branch and jump targets are always 2-byte aligned, bit 0
    //   is never stored in the instruction word; appending 0 here eliminates
    //   the need for an extra shift-left hardware unit.
    // =========================================================================


//Zahra's Notes:
//same rf thing as before its just that now rs1 and 2 addresses
//are being read from the decoder
    // wire [31:0] imm_b = {{20{i_imem_rdata[31]}},
    //                       i_imem_rdata[7],
    //                       i_imem_rdata[30:25],
    //                       i_imem_rdata[11:8],
    //                       1'b0};

    // wire [31:0] imm_j = {{12{i_imem_rdata[31]}},
    //                       i_imem_rdata[19:12],
    //                       i_imem_rdata[20],
    //                       i_imem_rdata[30:21],
    //                       1'b0};

    // wire [31:0] imm_i = {{20{i_imem_rdata[31]}},
    //                       i_imem_rdata[31:20]};

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

    // =========================================================================
    // SECTION 3: Register File Instantiation & Datapath Interface
    // -------------------------------------------------------------------------
    // What it does:
    //   Slices register address fields (rs1, rs2) from the instruction and plugs
    //   in rf.v so read data is immediately available to target and ALU logic[cite: 2].
    //
    // Design Choices for Smooth Running:
    //   1. BYPASS_EN is set to 0 as required for single-cycle designs (writes and
    //      reads happen across standard edge sampling; bypass is unnecessary)[cite: 2].
    //   2. Initialized unused inputs (rf_waddr, rf_wdata) and ALU flag wires
    //      to known default states (32'd0 / 1'b0)[cite: 2]. This prevents high-impedance
    //      or unknown ('x') propagation during isolated unit testing.
    // =========================================================================

// the alu wasnt instantiated yet and uses 2 operands fr the decoders op1_sel & op2_se4l
//no comparator module bc alu is doing branch compare and arthimetc

    // wire [4:0] rs1_addr = i_imem_rdata[19:15];
    // wire [4:0] rs2_addr = i_imem_rdata[24:20];

    // wire [31:0] rs1_rdata; // Directly feeds JALR target calculation below
    // wire [31:0] rs2_rdata;

    // // TODO (Teammate - Writeback): Replace these placeholder stubs with the
    // // destination register rd address (or 5'd0 if no write) and the writeback mux output.
    // wire [4:0]  rf_waddr = 5'd0;
    // wire [31:0] rf_wdata = 32'd0;

    // rf #(.BYPASS_EN(0)) u_rf (
    //     .i_clk      (i_clk),
    //     .i_rst      (i_rst),
    //     .i_rs1_raddr(rs1_addr),
    //     .o_rs1_rdata(rs1_rdata),
    //     .i_rs2_raddr(rs2_addr),
    //     .o_rs2_rdata(rs2_rdata),
    //     .i_rd_waddr (rf_waddr),
    //     .i_rd_wdata (rf_wdata)
    // );

    // // TODO (Teammate - ALU): Connect these wires to the comparison outputs of alu.v
    // // (e.g., .o_eq(alu_eq), .o_slt(alu_slt), .o_sltu(alu_sltu)).
    // wire alu_eq   = 1'b0;
    // wire alu_slt  = 1'b0;
    // wire alu_sltu = 1'b0;

    // // TODO (Teammate - Trap Logic): Replace this tie-off with the actual trap detection signal.
    // // When 1'b1, next_pc must stay pc_plus_4 and memory writes/register writes must be suppressed.
    // assign o_retire_trap = 1'b0;


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
    //     - branch_target: Relative offset from PC for conditional branches and JAL.
    //     - jalr_target: Absolute base-plus-offset address from register rs1.
    //
    // Design Choice for Smooth Running:
    //   Shared the relative adder between JAL and branches (`pc + (is_jal ? imm_j : imm_b)`).
    //   This synthesizes to a single 32-bit adder rather than two separate adders,
    //   saving gate area and matching single-cycle timing paths cleanly.
    //   Also applies the RISC-V specification masking `& ~32'd1` directly to
    //   guarantee JALR never branches to an odd byte address.
    // =========================================================================

    wire is_lui   = dec_rd_sel[1];
    wire is_auipc = dec_op1_sel;
    wire is_jal   = dec_jump & ~dec_pc_sel;
    // reg  [31:0] pc;
    // wire [31:0] pc_plus_4;
    // wire [31:0] branch_target;
    // wire [31:0] jalr_target;
    // wire [31:0] next_pc;
    // wire        branch_taken;

    // assign pc_plus_4     = pc + 32'd4;
    // assign branch_target = pc + (is_jal ? imm_j : imm_b);
    // assign jalr_target   = (rs1_rdata + imm_i) & ~32'd1;


    // =========================================================================
    // SECTION 5: Branch Condition Evaluation
    // -------------------------------------------------------------------------
    // What it does:
    //   Inspects funct3 to select the comparison operation (equality, signed
    //   less-than, unsigned less-than) and tests against the ALU condition flags.
    //
    // Design Choice for Smooth Running:
    //   Inverted comparison flags (!alu_eq, !alu_slt, !alu_sltu) directly handle
    //   opposite conditions (BNE, BGE, BGEU). This reuses comparison results
    //   without needing duplicate subtraction or comparison hardware.
    // =========================================================================
//Zahra's Notes: we dont need to redecode here
    // assign branch_taken = is_branch && (
    //     (funct3 == 3'b000 &&  alu_eq)   || // BEQ  (Equal)
    //     (funct3 == 3'b001 && !alu_eq)   || // BNE  (Not Equal)
    //     (funct3 == 3'b100 &&  alu_slt)  || // BLT  (Signed Less Than)
    //     (funct3 == 3'b101 && !alu_slt)  || // BGE  (Signed Greater Than or Equal)
    //     (funct3 == 3'b110 &&  alu_sltu) || // BLTU (Unsigned Less Than)
    //     (funct3 == 3'b111 && !alu_sltu)    // BGEU (Unsigned Greater Than or Equal)
    // );

    wire branch_condition = dec_branch_equal ? alu_eq : alu_slt;
    wire branch_taken     = dec_branch & (branch_condition ^ dec_branch_invert);

    // =========================================================================
    // SECTION 6: PCSrc Selection Multiplexer
    // -------------------------------------------------------------------------
    // What it does:
    //   Decides which calculated address becomes next_pc for the next clock cycle.
    //
    // Design Choice for Smooth Running:
    //   Strict priority ordering ensures correct execution semantics:
    //     1. Trap assertion overrides all redirects and forces sequential pc_plus_4
    //        (preventing side-effects on misaligned or illegal instructions).
    //     2. JALR (indirect register jump) takes priority over PC-relative logic.
    //     3. JAL / taken branches take the relative target.
    //     4. Default falls through sequentially to pc_plus_4.
    // =========================================================================
    //Zahra's notes
    reg  [31:0] pc;
    wire [31:0] pc_plus_4   = pc + 32'd4;
    wire [31:0] rel_target  = pc + dec_imm;
    wire [31:0] jalr_target = alu_result & ~32'd1;

    // assign next_pc = o_retire_trap            ? pc_plus_4     :
    //                  is_jalr                  ? jalr_target   :
    //                  (is_jal || branch_taken) ? branch_target :
    //                                             pc_plus_4;


    // =========================================================================
    // SECTION 7: Program Counter State Register & Interface Routing
    // -------------------------------------------------------------------------
    // What it does:
    //   Implements the sequential state element (D-flip-flops) storing the PC
    //   and routes the address to the external instruction memory and retire bus.
    //
    // Design Choice for Smooth Running:
    //   Uses synchronous active-high reset matching the processor's clock domain.
    //   Directly routes the registered `pc` to `o_imem_raddr` and `o_retire_pc`,
    //   and routes combinational `next_pc` to `o_retire_next_pc` so testbenches
    //   can evaluate next-cycle branch predictions on the current cycle.
    // =========================================================================
    //ZB
    wire [1:0] dmem_byte_off   = alu_result[1:0];
    wire       dmem_misaligned = (dec_dmem_ren | dec_dmem_wen) &
                                  |(dmem_byte_off & dec_dmem_align);
    wire       trap = ~dec_legal | dmem_misaligned;

    // always @(posedge i_clk) begin
    //     if (i_rst) begin
    //         pc <= RESET_ADDR;
    //     end else begin
    //         pc <= next_pc;
    //     end
    // end

    // assign o_imem_raddr     = pc;
    // assign o_retire_pc      = pc;
    // assign o_retire_next_pc = next_pc;


    // =========================================================================
    // SECTION 8: Teammate Deliverables (Pending Integration)
    // =========================================================================

    wire [31:0] next_pc =
        trap                      ? pc_plus_4   :
        dec_pc_sel                ? jalr_target :
        (dec_jump | branch_taken) ? rel_target  :
                                     pc_plus_4;

    always @(posedge i_clk) begin
        if (i_rst) pc <= RESET_ADDR;
        else       pc <= next_pc;
    end

    assign o_imem_raddr     = pc;
    assign o_retire_pc      = pc;
    assign o_retire_next_pc = next_pc;  

    // TODO (Teammate): Data Memory Interface
    // Drive o_dmem_addr (word-aligned ALU result), o_dmem_ren, o_dmem_wen, o_dmem_mask, and o_dmem_wdata.
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

    assign o_dmem_wdata =
        dec_dmem_memw ? rs2_rdata :
        dec_dmem_memh ? (dmem_byte_off[1] ? {rs2_rdata[15:0], 16'b0}
                                           : {16'b0, rs2_rdata[15:0]}) :
        dec_dmem_memb ? (dmem_byte_off == 2'b00 ? {24'b0, rs2_rdata[7:0]} :
                          dmem_byte_off == 2'b01 ? {16'b0, rs2_rdata[7:0], 8'b0} :
                          dmem_byte_off == 2'b10 ? {8'b0, rs2_rdata[7:0], 16'b0} :
                                                    {rs2_rdata[7:0], 24'b0}) :
                         32'b0;

    wire [7:0]  load_byte = dmem_byte_off == 2'b00 ? i_dmem_rdata[7:0]   :
                             dmem_byte_off == 2'b01 ? i_dmem_rdata[15:8] :
                             dmem_byte_off == 2'b10 ? i_dmem_rdata[23:16]:
                                                       i_dmem_rdata[31:24];
    wire [15:0] load_half = dmem_byte_off[1] ? i_dmem_rdata[31:16] : i_dmem_rdata[15:0];

    wire [31:0] load_data =
        dec_dmem_memb ? (dec_dmem_memu ? {24'b0, load_byte} : {{24{load_byte[7]}}, load_byte}) :
        dec_dmem_memh ? (dec_dmem_memu ? {16'b0, load_half} : {{16{load_half[15]}}, load_half}) :
                         i_dmem_rdata;

    // TODO (Teammate): Remaining Retire Signals
    // Drive o_retire_valid, o_retire_inst, o_retire_halt, o_retire_rs1_raddr/data,
    // o_retire_rs2_raddr/data, and o_retire_rd_waddr/data.
    
    reg valid_r;
    always @(posedge i_clk) begin
        if (i_rst) valid_r <= 1'b0;
        else       valid_r <= 1'b1;
    end
    assign o_retire_valid = valid_r;
    assign o_retire_inst  = i_imem_rdata;
    assign o_retire_trap  = trap;
    assign o_retire_halt  = dec_halt;

    wire is_r_type = dec_legal & ~dec_op2_sel & ~dec_branch & ~is_lui & ~is_jal & ~is_auipc;
    wire reads_rs1 = dec_legal & ~is_lui & ~is_auipc & ~is_jal;
    wire reads_rs2 = dec_legal & (is_r_type | dec_branch | dec_dmem_wen);

    assign o_retire_rs1_raddr = reads_rs1 ? dec_rs1 : 5'd0;
    assign o_retire_rs1_rdata = reads_rs1 ? rs1_rdata : 32'd0;
    assign o_retire_rs2_raddr = reads_rs2 ? dec_rs2 : 5'd0;
    assign o_retire_rs2_rdata = reads_rs2 ? rs2_rdata : 32'd0;

    assign o_retire_rd_waddr = rf_waddr;
    assign o_retire_rd_wdata = rf_wdata;

endmodule

`default_nettype wire