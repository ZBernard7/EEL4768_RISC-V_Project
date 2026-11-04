// AI USE DISCLOSURE:
// Chat GPT was used to help type redunant parts of the code.
// Accessed November 2026.
`default_nettype none

// The arithmetic logic unit (ALU) is responsible for performing the core
// calculations of the processor. It takes two 32-bit operands and outputs
// a 32 bit result based on the selection operation - addition, comparison,
// shift, or logical operation. Every RV32I operation is purely
// combinational. In phase 6 the ALU also performs the RV32M multiply and
// divide instructions, which may be combinational or take several cycles
// (see `documentation/phase_6.pdf`).
module alu (
    // Global clock and synchronous active-high reset (used by an iterative
    // multiplier or divider).
    input  wire        i_clk,
    input  wire        i_rst,
    // Major operation selection.
    // 3'b000: addition/subtraction if `i_sub` asserted
    // 3'b001: shift left logical
    // 3'b010: set less than
    // 3'b011: set less than unsigned
    // 3'b100: exclusive or
    // 3'b101: shift right logical/arithmetic if `i_arith` asserted
    // 3'b110: or
    // 3'b111: and
    // When `i_mext` is asserted, this is the M instruction's funct3 instead:
    // 3'b000: mul    - low 32 bits of op1 * op2
    // 3'b001: mulh   - high 32 bits of signed op1 * signed op2
    // 3'b010: mulhsu - high 32 bits of signed op1 * unsigned op2
    // 3'b011: mulhu  - high 32 bits of unsigned op1 * unsigned op2
    // 3'b100: div    - signed op1 / op2, rounded toward zero
    // 3'b101: divu   - unsigned op1 / op2
    // 3'b110: rem    - signed remainder, same sign as op1
    // 3'b111: remu   - unsigned remainder
    input  wire [ 2:0] i_opsel,
    // When asserted, addition operations should subtract instead.
    // This is only used for `i_opsel == 3'b000` (addition/subtraction).
    input  wire        i_sub,
    // When asserted, comparison operations should be treated as unsigned.
    // This is only used for branch comparisons, as the set less than unsigned
    // mode is already specified by `i_opsel`. For branch operations, the ALU
    // result is not used, only the comparison results.
    input  wire        i_unsigned,
    // When asserted, right shifts should be treated as arithmetic instead of
    // logical. This is only used for `i_opsel == 3'b101` (shift right).
    input  wire        i_arith,
    // Asserted while an RV32M instruction is in the execute stage.
    input  wire        i_mext,
    // Asserted when the instruction in the execute stage moves on at the next
    // rising edge. A finished M result is held until then.
    input  wire        i_advance,
    // First 32-bit input operand.
    input  wire [31:0] i_op1,
    // Second 32-bit input operand.
    input  wire [31:0] i_op2,
    // 32-bit output result. Any carry out (from addition) should be ignored.
    output wire [31:0] o_result,
    // Equality result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_eq,
    // Set less than result. This is used downstream to determine if a
    // branch should be taken.
    output wire        o_slt,
    // Asserted while an M operation is still running; the instruction must
    // stay in the execute stage until it drops.
    output wire        o_busy
);

// Write your code here.
// ---------- RV32I operations ----------

wire unsigned_lt;
wire signed_lt;

assign unsigned_lt = i_op1 < i_op2;
assign signed_lt = (i_op1[31] != i_op2[31])
                 ? i_op1[31] : unsigned_lt;

assign o_eq = i_op1 == i_op2;
assign o_slt = i_unsigned ? unsigned_lt : signed_lt;

// Barrel shifters: every individual shift uses a literal.
wire [31:0] left_stage [0:5];
wire [31:0] right_stage [0:5];
wire right_fill;

assign right_fill = i_arith & i_op1[31];
assign left_stage[0] = i_op1;
assign right_stage[0] = i_op1;

assign left_stage[1] = i_op2[0]
                    ? {left_stage[0][30:0], 1'b0}
                    : left_stage[0];
assign left_stage[2] = i_op2[1]
                    ? {left_stage[1][29:0], 2'b0}
                    : left_stage[1];
assign left_stage[3] = i_op2[2]
                    ? {left_stage[2][27:0], 4'b0}
                    : left_stage[2];
assign left_stage[4] = i_op2[3]
                    ? {left_stage[3][23:0], 8'b0}
                    : left_stage[3];
assign left_stage[5] = i_op2[4]
                    ? {left_stage[4][15:0], 16'b0}
                    : left_stage[4];

assign right_stage[1] = i_op2[0]
                     ? {right_fill, right_stage[0][31:1]}
                     : right_stage[0];
assign right_stage[2] = i_op2[1]
                     ? {{2{right_fill}}, right_stage[1][31:2]}
                     : right_stage[1];
assign right_stage[3] = i_op2[2]
                     ? {{4{right_fill}}, right_stage[2][31:4]}
                     : right_stage[2];
assign right_stage[4] = i_op2[3]
                     ? {{8{right_fill}}, right_stage[3][31:8]}
                     : right_stage[3];
assign right_stage[5] = i_op2[4]
                     ? {{16{right_fill}}, right_stage[4][31:16]}
                     : right_stage[4];

reg [31:0] base_result;

always @(*) begin
    case (i_opsel)
        3'b000: base_result = i_sub
                           ? i_op1 - i_op2 : i_op1 + i_op2;
        3'b001: base_result = left_stage[5];
        3'b010: base_result = {31'd0, signed_lt};
        3'b011: base_result = {31'd0, unsigned_lt};
        3'b100: base_result = i_op1 ^ i_op2;
        3'b101: base_result = right_stage[5];
        3'b110: base_result = i_op1 | i_op2;
        3'b111: base_result = i_op1 & i_op2;
        default: base_result = 32'd0;
    endcase
end

// ---------- RV32M control ----------

localparam IDLE = 2'd0;
localparam RUN  = 2'd1;
localparam DONE = 2'd2;

reg [1:0] state;
reg [5:0] step;
reg [2:0] saved_op;
reg [31:0] m_result;

wire signed_a;
wire signed_b;
wire negative_a;
wire negative_b;
wire [31:0] magnitude_a;
wire [31:0] magnitude_b;

// MUL's low half is independent of signedness.
// MULH: both signed. MULHSU: only the first signed.
// DIV and REM: both signed.
assign signed_a = (i_opsel == 3'b001)
                | (i_opsel == 3'b010)
                | (i_opsel == 3'b100)
                | (i_opsel == 3'b110);

assign signed_b = (i_opsel == 3'b001)
                | (i_opsel == 3'b100)
                | (i_opsel == 3'b110);

assign negative_a = signed_a & i_op1[31];
assign negative_b = signed_b & i_op2[31];

assign magnitude_a = negative_a ? (~i_op1 + 32'd1) : i_op1;
assign magnitude_b = negative_b ? (~i_op2 + 32'd1) : i_op2;

reg negate_product;
reg negate_quotient;
reg negate_remainder;
reg divisor_zero;
reg [31:0] original_dividend;

// ---------- Shift-and-add multiplication ----------

reg [63:0] product;
reg [63:0] multiplicand;
reg [31:0] multiplier;

wire [63:0] product_next;
wire [63:0] product_signed;

assign product_next = product
                    + (multiplier[0] ? multiplicand : 64'd0);

assign product_signed = negate_product
                      ? (~product_next + 64'd1)
                      : product_next;

// ---------- Restoring division ----------

reg [31:0] divisor;
reg [31:0] quotient;
reg [32:0] remainder;

wire [32:0] trial_remainder;
wire subtract_divisor;
wire [32:0] remainder_next;
wire [31:0] quotient_next;
wire [31:0] quotient_signed;
wire [31:0] remainder_signed;

assign trial_remainder = {remainder[31:0], quotient[31]};
assign subtract_divisor = trial_remainder >= {1'b0, divisor};

assign remainder_next = subtract_divisor
                      ? trial_remainder - {1'b0, divisor}
                      : trial_remainder;

assign quotient_next = {quotient[30:0], subtract_divisor};

assign quotient_signed = negate_quotient
                       ? (~quotient_next + 32'd1)
                       : quotient_next;

assign remainder_signed = negate_remainder
                        ? (~remainder_next[31:0] + 32'd1)
                        : remainder_next[31:0];

// Busy must assert immediately when a new M instruction enters EX.
assign o_busy = i_mext & (state != DONE);
assign o_result = i_mext ? m_result : base_result;

always @(posedge i_clk) begin
    if (i_rst) begin
        state <= IDLE;
        step <= 6'd0;
        saved_op <= 3'd0;
        m_result <= 32'd0;

        negate_product <= 1'b0;
        negate_quotient <= 1'b0;
        negate_remainder <= 1'b0;
        divisor_zero <= 1'b0;
        original_dividend <= 32'd0;

        product <= 64'd0;
        multiplicand <= 64'd0;
        multiplier <= 32'd0;

        divisor <= 32'd0;
        quotient <= 32'd0;
        remainder <= 33'd0;
    end else begin
        case (state)
            IDLE: begin
                if (i_mext) begin
                    state <= RUN;
                    step <= 6'd0;
                    saved_op <= i_opsel;

                    negate_product <= negative_a ^ negative_b;
                    negate_quotient <= negative_a ^ negative_b;
                    negate_remainder <= negative_a;
                    divisor_zero <= (i_op2 == 32'd0);
                    original_dividend <= i_op1;

                    product <= 64'd0;
                    multiplicand <= {32'd0, magnitude_a};
                    multiplier <= magnitude_b;

                    divisor <= magnitude_b;
                    quotient <= magnitude_a;
                    remainder <= 33'd0;
                end
            end

            RUN: begin
                step <= step + 6'd1;

                if (!saved_op[2]) begin
                    product <= product_next;
                    multiplicand <= {multiplicand[62:0], 1'b0};
                    multiplier <= {1'b0, multiplier[31:1]};

                    if (step == 6'd31) begin
                        m_result <= (saved_op == 3'b000)
                                  ? product_signed[31:0]
                                  : product_signed[63:32];
                        state <= DONE;
                    end
                end else begin
                    remainder <= remainder_next;
                    quotient <= quotient_next;

                    if (step == 6'd31) begin
                        if (saved_op[1]) begin
                            m_result <= divisor_zero
                                      ? original_dividend
                                      : remainder_signed;
                        end else begin
                            m_result <= divisor_zero
                                      ? 32'hFFFFFFFF
                                      : quotient_signed;
                        end
                        state <= DONE;
                    end
                end
            end

            DONE: begin
                if (i_advance) begin
                    state <= IDLE;
                end
            end

            default: state <= IDLE;
        endcase
    end
end

endmodule

`default_nettype wire