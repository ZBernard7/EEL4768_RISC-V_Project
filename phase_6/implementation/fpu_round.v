`default_nettype none
// Binary32 round/pack. Tininess is detected after rounding.
module fpu_round (
 input wire i_sign,
 input wire [11:0] i_exp,
 input wire [26:0] i_sig,
 input wire [2:0] i_rm,
 output wire [31:0] o_result,
 output wire [4:0] o_flags
);
wire tiny = i_exp[11] || (i_exp == 12'd0);
wire [11:0] shift_count = tiny ? (12'd1 - i_exp) : 12'd0;
wire [26:0] s0 = i_sig;
wire t0 = 1'b0;
wire [26:0] s1 = shift_count[0] ? (s0 >> 1) : s0;
wire t1 = t0 | (shift_count[0] && (|s0[0:0]));
wire [26:0] s2 = shift_count[1] ? (s1 >> 2) : s1;
wire t2 = t1 | (shift_count[1] && (|s1[1:0]));
wire [26:0] s3 = shift_count[2] ? (s2 >> 4) : s2;
wire t3 = t2 | (shift_count[2] && (|s2[3:0]));
wire [26:0] s4 = shift_count[3] ? (s3 >> 8) : s3;
wire t4 = t3 | (shift_count[3] && (|s3[7:0]));
wire [26:0] s5 = shift_count[4] ? (s4 >> 16) : s4;
wire t5 = t4 | (shift_count[4] && (|s4[15:0]));
wire all_shift = |shift_count[11:5];
wire [26:0] shifted = all_shift ? {26'd0, (|i_sig)} :
                                  {s5[26:1], s5[0] | t5};
wire lost = |shifted[2:0];
wire increment =
 (i_rm == 3'd0) ? (shifted[2] && ((|shifted[1:0]) || shifted[3])) :
 (i_rm == 3'd2) ? (i_sign && lost) :
 (i_rm == 3'd3) ? (!i_sign && lost) :
 (i_rm == 3'd4) ? shifted[2] : 1'b0;
wire [24:0] rounded = {1'b0, shifted[26:3]} + {24'd0, increment};
wire [11:0] base_exp = tiny ? 12'd1 : i_exp;
wire [11:0] final_exp = base_exp + (rounded[24] ? 12'd1 : 12'd0);
wire overflow = final_exp >= 12'd255;
wire to_inf = (i_rm == 3'd0) || (i_rm == 3'd4) ||
             ((i_rm == 3'd2) && i_sign) || ((i_rm == 3'd3) && !i_sign);
wire [7:0] packed_exp = (!rounded[24] && !rounded[23]) ? 8'd0 : final_exp[7:0];
wire [22:0] fraction = rounded[24] ? rounded[23:1] : rounded[22:0];
assign o_result = overflow ? {i_sign, (to_inf ? 31'h7F800000 : 31'h7F7FFFFF)} :
                            {i_sign, packed_exp, fraction};
assign o_flags = {2'b00, overflow, (!overflow && (packed_exp == 0) && lost),
                 (overflow || lost)};
endmodule
`default_nettype wire