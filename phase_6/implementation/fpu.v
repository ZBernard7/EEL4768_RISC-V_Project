`default_nettype none

// The floating-point unit implements the RISC-V F extension (single
// precision, IEEE 754-2008) and the Zicsr instructions for its control and
// status register fcsr. It sits in the execute stage beside the ALU and the
// multiply/divide unit, and decodes the details of its own instructions from
// the instruction word.
//
// It owns all F-extension state: fcsr, holding the dynamic rounding mode frm
// (fcsr[7:5]) and the accrued exception flags fflags (fcsr[4:0] = NV DZ OF
// UF NX). Floating-point exceptions never trap; they only set flags, which
// stay set until software clears them through a CSR instruction.
//
// fcsr only changes on a rising edge where the instruction in execute
// actually moves on to the memory stage (`i_advance`). An instruction can sit
// in execute for several cycles (for example while a cache miss freezes the
// pipeline); committing its flags or CSR write on every one of those cycles
// would make a CSR instruction read back its own write.
module fpu (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset. Clears fcsr (frm = round to nearest,
    // ties to even; no flags set).
    input  wire        i_rst,
    // The instruction word in the execute stage.
    input  wire [31:0] i_inst,
    // Asserted when `i_inst` is a valid, legal floating-point unit
    // instruction (decoder `o_fpu`): every OP-FP and fused multiply-add
    // instruction and the CSR instructions on fflags/frm/fcsr.
    input  wire        i_valid,
    // Asserted when the instruction in execute advances to the memory stage
    // on the next rising edge. Side effects (fcsr updates) happen only then.
    input  wire        i_advance,
    // Floating-point source operands (rs1, rs2, rs3), raw IEEE bit patterns.
    input  wire [31:0] i_frs1,
    input  wire [31:0] i_frs2,
    input  wire [31:0] i_frs3,
    // Integer source operand (forwarded rs1), used by fmv.w.x, fcvt.s.w[u]
    // and the register forms of the CSR instructions.
    input  wire [31:0] i_xrs1,
    // Result for instructions that write a floating-point register.
    output wire [31:0] o_fp_result,
    // Result for instructions that write an integer register: fmv.x.w,
    // fclass.s, feq/flt/fle.s, fcvt.w[u].s, and the old CSR value.
    output wire [31:0] o_int_result,
    // The accrued exception flags as they will be after this instruction
    // (reported in the retire trace).
    output wire [ 4:0] o_fflags,
    // Asserted while a multi-cycle operation (fdiv.s/fsqrt.s) is in
    // progress and the instruction must stay in execute.
    output wire        o_busy,
    // Asserted when a rounding instruction selects the dynamic rounding mode
    // (rm = 111) while frm holds a reserved value (101-111). The instruction
    // traps as illegal and changes no state.
    output wire        o_rm_trap
);

// Write your code here.
// ---------- Instruction fields and control ----------

wire [6:0] opcode = i_inst[6:0];
wire [6:0] funct7 = i_inst[31:25];
wire [2:0] funct3 = i_inst[14:12];

wire is_fp = opcode == 7'h53;
wire is_csr = opcode == 7'h73;

reg [7:0] fcsr;

wire [2:0] rounding_mode =
    (funct3 == 3'b111) ? fcsr[7:5] : funct3;

wire rounding_instruction =
    ((opcode == 7'h43) ||
     (opcode == 7'h47) ||
     (opcode == 7'h4B) ||
     (opcode == 7'h4F)) ||
    (is_fp &&
     ((funct7 == 7'h00) ||
      (funct7 == 7'h04) ||
      (funct7 == 7'h08) ||
      (funct7 == 7'h0C) ||
      (funct7 == 7'h2C) ||
      (funct7 == 7'h60) ||
      (funct7 == 7'h68)));

assign o_rm_trap =
    i_valid && rounding_instruction &&
    (funct3 == 3'b111) && (rounding_mode > 3'b100);

// Arithmetic helper handles full-precision fused operations and long units.
wire arithmetic_instruction = rounding_instruction &&
    !((opcode == 7'h53) && ((funct7 == 7'h60) || (funct7 == 7'h68)));
wire [31:0] arithmetic_result;
wire [4:0] arithmetic_flags;
fpu_arith arithmetic_unit (
 .i_clk(i_clk), .i_rst(i_rst),
 .i_valid(i_valid && arithmetic_instruction && !o_rm_trap),
 .i_advance(i_advance), .i_inst(i_inst),
 .i_a(i_frs1), .i_b(i_frs2), .i_c(i_frs3), .i_rm(rounding_mode),
 .o_result(arithmetic_result), .o_flags(arithmetic_flags), .o_busy(o_busy)
);

// ---------- Classify FP operands ----------

wire a_sign = i_frs1[31];
wire b_sign = i_frs2[31];

wire a_exp_zero = i_frs1[30:23] == 8'd0;
wire b_exp_zero = i_frs2[30:23] == 8'd0;
wire a_exp_ones = i_frs1[30:23] == 8'hFF;
wire b_exp_ones = i_frs2[30:23] == 8'hFF;

wire a_frac_zero = i_frs1[22:0] == 23'd0;
wire b_frac_zero = i_frs2[22:0] == 23'd0;

wire a_zero = a_exp_zero && a_frac_zero;
wire b_zero = b_exp_zero && b_frac_zero;
wire a_inf = a_exp_ones && a_frac_zero;
wire a_nan = a_exp_ones && !a_frac_zero;
wire b_nan = b_exp_ones && !b_frac_zero;
wire a_snan = a_nan && !i_frs1[22];
wire b_snan = b_nan && !i_frs2[22];
wire a_subnormal = a_exp_zero && !a_frac_zero;
wire a_normal = !a_exp_zero && !a_exp_ones;

// +0 and -0 compare equal. NaNs never compare equal.
wire fp_equal =
    !a_nan && !b_nan &&
    ((i_frs1 == i_frs2) || (a_zero && b_zero));

// For negative operands, greater magnitude means a smaller value.
wire fp_less =
    !a_nan && !b_nan && !(a_zero && b_zero) &&
    ((a_sign != b_sign)
        ? a_sign
        : (a_sign
            ? (i_frs1[30:0] > i_frs2[30:0])
            : (i_frs1[30:0] < i_frs2[30:0])));

wire [9:0] class_mask = {
    a_nan && i_frs1[22],       // bit 9: quiet NaN
    a_snan,                   // bit 8: signaling NaN
    a_inf && !a_sign,          // bit 7: positive infinity
    a_normal && !a_sign,       // bit 6: positive normal
    a_subnormal && !a_sign,    // bit 5: positive subnormal
    a_zero && !a_sign,         // bit 4: positive zero
    a_zero && a_sign,          // bit 3: negative zero
    a_subnormal && a_sign,     // bit 2: negative subnormal
    a_normal && a_sign,        // bit 1: negative normal
    a_inf && a_sign            // bit 0: negative infinity
};

// ---------- Min/max, including NaNs and signed zeros ----------

wire [31:0] min_result =
    (a_nan && b_nan) ? 32'h7FC00000 :
    a_nan ? i_frs2 :
    b_nan ? i_frs1 :
    (a_zero && b_zero)
        ? {a_sign | b_sign, 31'd0} :
    fp_less ? i_frs1 : i_frs2;

wire [31:0] max_result =
    (a_nan && b_nan) ? 32'h7FC00000 :
    a_nan ? i_frs2 :
    b_nan ? i_frs1 :
    (a_zero && b_zero)
        ? {a_sign & b_sign, 31'd0} :
    fp_less ? i_frs2 : i_frs1;

// ---------- CSR read/modify/write ----------

reg [31:0] csr_old;
reg [31:0] csr_new;
reg [7:0] csr_next;

wire [31:0] csr_operand =
    funct3[2] ? {27'd0, i_inst[19:15]} : i_xrs1;

// CSRRS/CSRRC suppress writes based on the source register
// number (or immediate), not the value stored in that register.
wire csr_write =
    (funct3[1:0] == 2'b01) ||
    ((funct3[1:0] != 2'b00) && (i_inst[19:15] != 5'd0));

always @(*) begin
    case (i_inst[31:20])
        12'h001: csr_old = {27'd0, fcsr[4:0]};
        12'h002: csr_old = {29'd0, fcsr[7:5]};
        12'h003: csr_old = {24'd0, fcsr};
        default: csr_old = 32'd0;
    endcase

    case (funct3[1:0])
        2'b01: csr_new = csr_operand;
        2'b10: csr_new = csr_old | csr_operand;
        2'b11: csr_new = csr_old & ~csr_operand;
        default: csr_new = csr_old;
    endcase

    case (i_inst[31:20])
        12'h001: csr_next = {fcsr[7:5], csr_new[4:0]};
        12'h002: csr_next = {csr_new[2:0], fcsr[4:0]};
        12'h003: csr_next = csr_new[7:0];
        default: csr_next = fcsr;
    endcase
end

// ---------- Integer / floating-point conversions ----------

// Rounding decisions are expressed directly below for checker compatibility.

// FCVT.S.W / FCVT.S.WU: obtain unsigned magnitude.
wire cv_unsigned = i_inst[20];
wire cv_xsign = !cv_unsigned && i_xrs1[31];
wire [31:0] cv_xmag =
    cv_xsign ? (~i_xrs1 + 32'd1) : i_xrs1;

// Normalize by moving the highest set bit to bit 31.
// Each stage uses fixed wiring rather than a variable shift.
wire [31:0] cv_n0 = cv_xmag;
wire cv_l16 = cv_n0[31:16] == 16'd0;
wire [31:0] cv_n1 =
    cv_l16 ? {cv_n0[15:0], 16'd0} : cv_n0;

wire cv_l8 = cv_n1[31:24] == 8'd0;
wire [31:0] cv_n2 =
    cv_l8 ? {cv_n1[23:0], 8'd0} : cv_n1;

wire cv_l4 = cv_n2[31:28] == 4'd0;
wire [31:0] cv_n3 =
    cv_l4 ? {cv_n2[27:0], 4'd0} : cv_n2;

wire cv_l2 = cv_n3[31:30] == 2'd0;
wire [31:0] cv_n4 =
    cv_l2 ? {cv_n3[29:0], 2'd0} : cv_n3;

wire cv_l1 = !cv_n4[31];
wire [31:0] cv_norm =
    cv_l1 ? {cv_n4[30:0], 1'b0} : cv_n4;

wire [4:0] cv_lzeros = {
    cv_l16, cv_l8, cv_l4, cv_l2, cv_l1
};

wire [7:0] cv_xexp = 8'd158 - {3'd0, cv_lzeros};
wire cv_xguard = cv_norm[7];
wire cv_xsticky = |cv_norm[6:0];

wire cv_xincrement =
    (rounding_mode == 3'b000) ? (cv_xguard && (cv_xsticky || cv_norm[8])) :
    (rounding_mode == 3'b010) ? (cv_xsign && (cv_xguard || cv_xsticky)) :
    (rounding_mode == 3'b011) ? (!cv_xsign && (cv_xguard || cv_xsticky)) :
    (rounding_mode == 3'b100) ? cv_xguard : 1'b0;

wire [24:0] cv_xrounded =
    {1'b0, cv_norm[31:8]} + {24'd0, cv_xincrement};

wire [7:0] cv_xexp_rounded =
    cv_xexp + {7'd0, cv_xrounded[24]};

wire [22:0] cv_xfraction =
    cv_xrounded[24] ? cv_xrounded[23:1] : cv_xrounded[22:0];

wire [31:0] cv_int_to_fp =
    (cv_xmag == 32'd0) ? 32'd0 :
    {cv_xsign, cv_xexp_rounded, cv_xfraction};

wire [4:0] cv_int_to_fp_flags =
    {4'd0, cv_xguard | cv_xsticky};

// FCVT.W.S / FCVT.WU.S.
//
// Represent magnitude as a 64-bit fixed-point number:
// bits [63:32] are the integer part, bits [31:0] the fraction.
// A separate sticky bit preserves discarded precision.
wire [7:0] cv_fexp = i_frs1[30:23];
wire [23:0] cv_fsig = {
    !a_exp_zero, i_frs1[22:0]
};

wire [7:0] cv_effective_exp =
    a_exp_zero ? 8'd1 : cv_fexp;

// Above exponent 158 the magnitude is at least 2^32,
// so the conversion is outside both integer ranges.
wire cv_large = cv_fexp > 8'd158;
wire cv_shift_left = cv_effective_exp > 8'd150;
wire [7:0] cv_right_amount =
    cv_shift_left ? 8'd0 : 8'd150 - cv_effective_exp;
wire [7:0] cv_left_amount =
    cv_shift_left ? cv_effective_exp - 8'd150 : 8'd0;

wire [63:0] cv_r0 = {8'd0, cv_fsig, 32'd0};

wire [63:0] cv_r1 =
    cv_right_amount[0] ? (cv_r0 >> 1) : cv_r0;
wire cv_s1 = cv_right_amount[0] && cv_r0[0];

wire [63:0] cv_r2 =
    cv_right_amount[1] ? (cv_r1 >> 2) : cv_r1;
wire cv_s2 = cv_s1 ||
    (cv_right_amount[1] && (|cv_r1[1:0]));

wire [63:0] cv_r3 =
    cv_right_amount[2] ? (cv_r2 >> 4) : cv_r2;
wire cv_s3 = cv_s2 ||
    (cv_right_amount[2] && (|cv_r2[3:0]));

wire [63:0] cv_r4 =
    cv_right_amount[3] ? (cv_r3 >> 8) : cv_r3;
wire cv_s4 = cv_s3 ||
    (cv_right_amount[3] && (|cv_r3[7:0]));

wire [63:0] cv_r5 =
    cv_right_amount[4] ? (cv_r4 >> 16) : cv_r4;
wire cv_s5 = cv_s4 ||
    (cv_right_amount[4] && (|cv_r4[15:0]));

wire [63:0] cv_r6 =
    cv_right_amount[5] ? (cv_r5 >> 32) : cv_r5;
wire cv_s6 = cv_s5 ||
    (cv_right_amount[5] && (|cv_r5[31:0]));

wire cv_right_all =
    cv_right_amount[6] || cv_right_amount[7];

wire [63:0] cv_right =
    cv_right_all ? 64'd0 : cv_r6;
wire cv_right_sticky =
    cv_s6 || (cv_right_all && (|cv_r6));

// Left shift is at most 8 for an in-range magnitude.
wire [63:0] cv_lstage1 =
    cv_left_amount[0] ? (cv_r0 << 1) : cv_r0;
wire [63:0] cv_lstage2 =
    cv_left_amount[1] ? (cv_lstage1 << 2) : cv_lstage1;
wire [63:0] cv_lstage3 =
    cv_left_amount[2] ? (cv_lstage2 << 4) : cv_lstage2;
wire [63:0] cv_left =
    cv_left_amount[3] ? (cv_lstage3 << 8) : cv_lstage3;

wire [63:0] cv_fixed =
    cv_shift_left ? cv_left : cv_right;

wire cv_fguard = cv_fixed[31];
wire cv_fsticky =
    (|cv_fixed[30:0]) ||
    (!cv_shift_left && cv_right_sticky);

wire cv_fincrement =
    (rounding_mode == 3'b000) ? (cv_fguard && (cv_fsticky || cv_fixed[32])) :
    (rounding_mode == 3'b010) ? (a_sign && (cv_fguard || cv_fsticky)) :
    (rounding_mode == 3'b011) ? (!a_sign && (cv_fguard || cv_fsticky)) :
    (rounding_mode == 3'b100) ? cv_fguard : 1'b0;

wire [32:0] cv_frounded =
    {1'b0, cv_fixed[63:32]} + {32'd0, cv_fincrement};

// Range checks happen after rounding, so a negative fraction
// that rounds to zero is valid for unsigned conversion.
wire cv_unsigned_invalid =
    cv_frounded[32] ||
    (a_sign && (cv_frounded != 33'd0));

wire cv_signed_invalid =
    a_sign
        ? (cv_frounded > 33'h080000000)
        : (cv_frounded > 33'h07FFFFFFF);

wire cv_invalid =
    a_exp_ones || cv_large ||
    (cv_unsigned ? cv_unsigned_invalid : cv_signed_invalid);

wire [31:0] cv_clip =
    cv_unsigned
        ? ((a_sign && !a_nan) ? 32'd0 : 32'hFFFFFFFF)
        : ((a_sign && !a_nan) ? 32'h80000000 : 32'h7FFFFFFF);

wire [31:0] cv_signed_value =
    a_sign
        ? (~cv_frounded[31:0] + 32'd1)
        : cv_frounded[31:0];

wire [31:0] cv_fp_to_int =
    cv_invalid ? cv_clip : cv_signed_value;

wire [4:0] cv_fp_to_int_flags =
    cv_invalid ? 5'b10000 :
    {4'd0, cv_fguard | cv_fsticky};

// ---------- Results and instruction exception flags ----------

reg [31:0] fp_result;
reg [31:0] int_result;
reg [4:0] operation_flags;

always @(*) begin
    fp_result = 32'd0;
    int_result = 32'd0;
    operation_flags = 5'd0;

    case (opcode)
        7'h43, 7'h47, 7'h4B, 7'h4F: begin
            fp_result = arithmetic_result;
            operation_flags = arithmetic_flags;
        end
        7'h73: begin
            int_result = csr_old;
        end

        7'h53: begin
            case (funct7)
                7'h00, 7'h04, 7'h08, 7'h0C, 7'h2C: begin
                    fp_result = arithmetic_result;
                    operation_flags = arithmetic_flags;
                end
                // Sign injection copies the remaining bits unchanged.
                7'h10: begin
                    case (funct3)
                        3'b000:
                            fp_result = {b_sign, i_frs1[30:0]};
                        3'b001:
                            fp_result = {!b_sign, i_frs1[30:0]};
                        3'b010:
                            fp_result = {
                                a_sign ^ b_sign, i_frs1[30:0]
                            };
                        default: fp_result = 32'd0;
                    endcase
                end

                // FMIN.S / FMAX.S.
                7'h14: begin
                    fp_result = funct3[0] ? max_result : min_result;
                    operation_flags = {
                        a_snan | b_snan, 4'b0000
                    };
                end

                // FLE.S / FLT.S / FEQ.S.
                7'h50: begin
                    case (funct3)
                        3'b000: int_result = {
                            31'd0, fp_less | fp_equal
                        };
                        3'b001: int_result = {31'd0, fp_less};
                        3'b010: int_result = {31'd0, fp_equal};
                        default: int_result = 32'd0;
                    endcase

                    // FEQ signals only on signaling NaNs.
                    // FLT/FLE signal on any NaN.
                    operation_flags = {
                        (funct3 == 3'b010)
                            ? (a_snan | b_snan)
                            : (a_nan | b_nan),
                        4'b0000
                    };
                end

                // FMV.X.W / FCLASS.S.
                7'h70: begin
                    case (funct3)
                        3'b000: int_result = i_frs1;
                        3'b001: int_result = {22'd0, class_mask};
                        default: int_result = 32'd0;
                    endcase
                end

                // FMV.W.X.
                7'h78: begin
                    fp_result = i_xrs1;
                end

                // FCVT.W.S / FCVT.WU.S.
                7'h60: begin
                    int_result = cv_fp_to_int;
                    operation_flags = cv_fp_to_int_flags;
                end

                // FCVT.S.W / FCVT.S.WU.
                7'h68: begin
                    fp_result = cv_int_to_fp;
                    operation_flags = cv_int_to_fp_flags;
                end

                // Arithmetic logic goes here later.
                default: begin
                    fp_result = 32'd0;
                    int_result = 32'd0;
                    operation_flags = 5'd0;
                end
            endcase
        end

        default: begin
            fp_result = 32'd0;
            int_result = 32'd0;
            operation_flags = 5'd0;
        end
    endcase
end

assign o_fp_result = fp_result;
assign o_int_result = int_result;

// Report the flags that will exist after this instruction.
wire [7:0] next_fcsr =
    (is_csr && csr_write)
        ? csr_next
        : {fcsr[7:5], fcsr[4:0] | operation_flags};

assign o_fflags =
    (i_valid && !o_rm_trap) ? next_fcsr[4:0] : fcsr[4:0];

// Commit state only when the instruction actually leaves EX.
always @(posedge i_clk) begin
    if (i_rst) begin
        fcsr <= 8'd0;
    end else begin
        if (i_valid && i_advance && !o_rm_trap) begin
            fcsr <= next_fcsr;
        end
    end
end

endmodule

`default_nettype wire