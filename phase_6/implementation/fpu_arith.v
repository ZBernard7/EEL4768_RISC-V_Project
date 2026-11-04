`default_nettype none
// Exact fixed-point multiply/add and iterative significand divide/square root.
// All signal shifts have literal amounts; no signal multiply/divide operators.
module fpu_arith (
 input wire i_clk, i_rst, i_valid, i_advance,
 input wire [31:0] i_inst, i_a, i_b, i_c,
 input wire [2:0] i_rm,
 output wire [31:0] o_result,
 output wire [4:0] o_flags,
 output wire o_busy
);
wire [6:0] op = i_inst[6:0];
wire [6:0] f7 = i_inst[31:25];
wire fused = (op == 7'h43) || (op == 7'h47) || (op == 7'h4B) || (op == 7'h4F);
wire addsub = (op == 7'h53) && ((f7 == 7'h00) || (f7 == 7'h04));
wire mul = (op == 7'h53) && (f7 == 7'h08);
wire divide = (op == 7'h53) && (f7 == 7'h0C);
wire root = (op == 7'h53) && (f7 == 7'h2C);
wire long_op = divide || root;
wire negate_product = (op == 7'h4B) || (op == 7'h4F);
wire negate_c = (op == 7'h47) || (op == 7'h4F) || (addsub && (f7 == 7'h04));
// An add is a*1+b; multiply skips the addend entirely (preserves -0).
wire [31:0] a = i_a;
wire [31:0] b = addsub ? 32'h3F800000 : i_b;
wire [31:0] c = addsub ? i_b : i_c;
wire use_c = addsub || fused;
wire az = a[30:0] == 31'd0;
wire bz = b[30:0] == 31'd0;
wire cz = c[30:0] == 31'd0;
wire an = (&a[30:23]) && (|a[22:0]);
wire bn = (&b[30:23]) && (|b[22:0]);
wire cn = (&c[30:23]) && (|c[22:0]);
wire ai = (&a[30:23]) && !(|a[22:0]);
wire bi = (&b[30:23]) && !(|b[22:0]);
wire ci = (&c[30:23]) && !(|c[22:0]);
wire asn = an && !a[22];
wire bsn = bn && !b[22];
wire csn = cn && !c[22];
wire psign = a[31] ^ b[31] ^ negate_product;
wire csign = c[31] ^ negate_c;
wire pinf = ai || bi;
wire pzero = az || bz;
wire invalid_product = (ai && bz) || (bi && az);
wire invalid_sum = use_c && !an && !bn && pinf && ci && (psign != csign);
wire madd_nan = an || bn || (use_c && cn) || invalid_product || invalid_sum;
wire madd_nv = asn || bsn || (use_c && csn) || invalid_product || invalid_sum;
wire madd_special = madd_nan || pinf || (use_c && ci);
wire [31:0] madd_special_result = madd_nan ? 32'h7FC00000 :
    {pinf ? psign : csign, 8'hFF, 23'd0};

wire [7:0] ea = (a[30:23] == 0) ? 8'd1 : a[30:23];
wire [7:0] eb = (b[30:23] == 0) ? 8'd1 : b[30:23];
wire [7:0] ec = (c[30:23] == 0) ? 8'd1 : c[30:23];
wire [23:0] sa = {(|a[30:23]), a[22:0]};
wire [23:0] sb = {(|b[30:23]), b[22:0]};
wire [23:0] sc = {(|c[30:23]), c[22:0]};

// 24 partial products, summed in 48 bits.
wire [47:0] products [0:24];
assign products[0] = 48'd0;
genvar k;
generate
 for (k=0; k<24; k=k+1) begin : partial_product
  wire [47:0] row;
  assign row = {{(24-k){1'b0}}, sa, {k{1'b0}}};
  assign products[k+1] = products[k] + (sb[k] ? row : 48'd0);
 end
endgenerate

// Finite terms are exact integers with a common scale of 2^-298.
// 576 bits cover the full binary32 product range and carry out.
wire [9:0] pshift = {2'd0,ea} + {2'd0,eb} - 10'd2;
wire [9:0] cshift = {2'd0,ec} + 10'd148;
wire [575:0] p0 = {528'd0, products[24]};
wire [575:0] c0 = use_c ? {552'd0, sc} : 576'd0;
wire [575:0] p1 = pshift[0] ? (p0 << 1) : p0;
wire [575:0] p2 = pshift[1] ? (p1 << 2) : p1;
wire [575:0] p3 = pshift[2] ? (p2 << 4) : p2;
wire [575:0] p4 = pshift[3] ? (p3 << 8) : p3;
wire [575:0] p5 = pshift[4] ? (p4 << 16) : p4;
wire [575:0] p6 = pshift[5] ? (p5 << 32) : p5;
wire [575:0] p7 = pshift[6] ? (p6 << 64) : p6;
wire [575:0] p8 = pshift[7] ? (p7 << 128) : p7;
wire [575:0] p9 = pshift[8] ? (p8 << 256) : p8;
wire [575:0] c1 = cshift[0] ? (c0 << 1) : c0;
wire [575:0] c2 = cshift[1] ? (c1 << 2) : c1;
wire [575:0] c3 = cshift[2] ? (c2 << 4) : c2;
wire [575:0] c4 = cshift[3] ? (c3 << 8) : c3;
wire [575:0] c5 = cshift[4] ? (c4 << 16) : c4;
wire [575:0] c6 = cshift[5] ? (c5 << 32) : c5;
wire [575:0] c7 = cshift[6] ? (c6 << 64) : c6;
wire [575:0] c8 = cshift[7] ? (c7 << 128) : c7;
wire [575:0] c9 = cshift[8] ? (c8 << 256) : c8;
wire p_ge_c = p9 >= c9;
wire [575:0] magnitude = (psign == csign) ? p9 + c9 :
                         (p_ge_c ? p9 - c9 : c9 - p9);
wire magnitude_zero = !(|magnitude);
wire zero_sign = use_c ? ((pzero && cz && (psign == csign)) ? psign : (i_rm == 3'd2)) : psign;
wire result_sign = magnitude_zero ? zero_sign : (p_ge_c ? psign : csign);
// Highest set bit, using an elaborated priority chain.
wire [9:0] topbit [0:576];
assign topbit[0] = 10'd0;
genvar h;
generate
 for (h=0; h<576; h=h+1) begin : highest_bit
  localparam [9:0] POSITION = h;
  assign topbit[h+1] = magnitude[h] ? POSITION : topbit[h];
 end
endgenerate
wire [9:0] norm_right = (topbit[576] > 10'd26) ? topbit[576] - 10'd26 : 10'd0;
wire [4:0] norm_left = (topbit[576] < 10'd26) ? 5'd26 - topbit[576][4:0] : 5'd0;
wire [575:0] n0 = magnitude;
wire ns0 = 1'b0;
wire [575:0] n1 = norm_right[0] ? (n0 >> 1) : n0;
wire ns1 = ns0 | (norm_right[0] && (|n0[0:0]));
wire [575:0] n2 = norm_right[1] ? (n1 >> 2) : n1;
wire ns2 = ns1 | (norm_right[1] && (|n1[1:0]));
wire [575:0] n3 = norm_right[2] ? (n2 >> 4) : n2;
wire ns3 = ns2 | (norm_right[2] && (|n2[3:0]));
wire [575:0] n4 = norm_right[3] ? (n3 >> 8) : n3;
wire ns4 = ns3 | (norm_right[3] && (|n3[7:0]));
wire [575:0] n5 = norm_right[4] ? (n4 >> 16) : n4;
wire ns5 = ns4 | (norm_right[4] && (|n4[15:0]));
wire [575:0] n6 = norm_right[5] ? (n5 >> 32) : n5;
wire ns6 = ns5 | (norm_right[5] && (|n5[31:0]));
wire [575:0] n7 = norm_right[6] ? (n6 >> 64) : n6;
wire ns7 = ns6 | (norm_right[6] && (|n6[63:0]));
wire [575:0] n8 = norm_right[7] ? (n7 >> 128) : n7;
wire ns8 = ns7 | (norm_right[7] && (|n7[127:0]));
wire [575:0] n9 = norm_right[8] ? (n8 >> 256) : n8;
wire ns9 = ns8 | (norm_right[8] && (|n8[255:0]));
wire [575:0] n10 = norm_right[9] ? (n9 >> 512) : n9;
wire ns10 = ns9 | (norm_right[9] && (|n9[511:0]));
wire [26:0] nl0 = magnitude[26:0];
wire [26:0] nl1 = norm_left[0] ? (nl0 << 1) : nl0;
wire [26:0] nl2 = norm_left[1] ? (nl1 << 2) : nl1;
wire [26:0] nl3 = norm_left[2] ? (nl2 << 4) : nl2;
wire [26:0] nl4 = norm_left[3] ? (nl3 << 8) : nl3;
wire [26:0] nl5 = norm_left[4] ? (nl4 << 16) : nl4;
wire [26:0] madd_sig = (topbit[576] < 10'd26) ? nl5 : {n10[26:1], n10[0] | ns10};
wire [11:0] madd_position = {2'b00,topbit[576]};
wire [11:0] madd_exp = madd_position - 12'd171;
wire [31:0] madd_rounded;
wire [4:0] madd_flags;
fpu_round madd_round (.i_sign(result_sign), .i_exp(madd_exp),
 .i_sig(madd_sig), .i_rm(i_rm), .o_result(madd_rounded), .o_flags(madd_flags));

// Normalize divide/square-root significands, including subnormals.
wire [4:0] alz [0:24];
wire [4:0] blz [0:24];
assign alz[0] = 5'd23;
assign blz[0] = 5'd23;
genvar z;
generate
 for (z=0; z<24; z=z+1) begin : leading_zeros
  localparam [4:0] ZEROS = 23-z;
  assign alz[z+1] = sa[z] ? ZEROS : alz[z];
  assign blz[z+1] = sb[z] ? ZEROS : blz[z];
 end
endgenerate
wire [23:0] na0 = sa;
wire [23:0] nb0 = sb;
wire [23:0] na1 = alz[24][0] ? (na0 << 1) : na0;
wire [23:0] na2 = alz[24][1] ? (na1 << 2) : na1;
wire [23:0] na3 = alz[24][2] ? (na2 << 4) : na2;
wire [23:0] na4 = alz[24][3] ? (na3 << 8) : na3;
wire [23:0] na5 = alz[24][4] ? (na4 << 16) : na4;
wire [23:0] nb1 = blz[24][0] ? (nb0 << 1) : nb0;
wire [23:0] nb2 = blz[24][1] ? (nb1 << 2) : nb1;
wire [23:0] nb3 = blz[24][2] ? (nb2 << 4) : nb2;
wire [23:0] nb4 = blz[24][3] ? (nb3 << 8) : nb3;
wire [23:0] nb5 = blz[24][4] ? (nb4 << 16) : nb4;
wire [11:0] a_exp_signed = {4'd0,ea};
wire [11:0] b_exp_signed = {4'd0,eb};
wire [11:0] a_lz_signed = {7'd0,alz[24]};
wire [11:0] b_lz_signed = {7'd0,blz[24]};
wire [11:0] ax = a_exp_signed - 12'd127 - a_lz_signed;
wire [11:0] bx = b_exp_signed - 12'd127 - b_lz_signed;
wire ratio_small = na5 < nb5;
wire [11:0] div_exp = ax - bx + 12'd127 - (ratio_small ? 12'd1 : 12'd0);
wire [11:0] sqrt_exp = {ax[11],ax[11:1]} + 12'd127;
wire [24:0] div_initial = ratio_small ? {na5,1'b0} : {1'b0,na5};
wire div_nan = an || bn || (az && bz) || (ai && bi);
wire div_nv = asn || bsn || (az && bz) || (ai && bi);
wire div_dz = !an && !bn && !ai && !az && bz;
wire div_special = div_nan || ai || bi || az || bz;
wire [31:0] div_special_result = div_nan ? 32'h7FC00000 :
    {a[31]^b[31], ((ai || bz) ? 8'hFF : 8'd0),23'd0};
wire sqrt_nan = an || (a[31] && !az);
wire sqrt_nv = asn || (a[31] && !az && !an);
wire sqrt_special = sqrt_nan || ai || az;
wire [31:0] sqrt_special_result = sqrt_nan ? 32'h7FC00000 : a;
wire special_long = root ? sqrt_special : div_special;
wire [31:0] special_result = root ? sqrt_special_result : div_special_result;
wire [4:0] special_flags = root ? {sqrt_nv,4'd0} : {div_nv,div_dz,3'd0};

localparam [1:0] IDLE=2'd0, RUN=2'd1, DONE=2'd2;
reg [1:0] state;
reg [5:0] count;
reg saved_root, saved_sign;
reg [11:0] saved_exp;
reg [2:0] saved_rm;
reg [24:0] div_rem;
reg [23:0] div_den;
reg [25:0] quotient;
reg [51:0] radicand;
reg [53:0] sqrt_rem;
reg [25:0] sqrt_q;
reg [31:0] long_result;
reg [4:0] long_flags;
wire [24:0] div_trial = {div_rem[23:0],1'b0};
wire div_bit = div_trial >= {1'b0,div_den};
wire [24:0] div_rem_next = div_bit ? div_trial - {1'b0,div_den} : div_trial;
wire [25:0] quotient_next = {quotient[24:0],div_bit};
wire [53:0] sqrt_trial_rem = {sqrt_rem[51:0],radicand[51:50]};
wire [53:0] sqrt_trial_divisor = {26'd0,sqrt_q,2'b01};
wire sqrt_bit = sqrt_trial_rem >= sqrt_trial_divisor;
wire [53:0] sqrt_rem_next = sqrt_bit ? sqrt_trial_rem - sqrt_trial_divisor : sqrt_trial_rem;
wire [25:0] sqrt_q_next = {sqrt_q[24:0],sqrt_bit};
wire [26:0] long_sig = saved_root ? {sqrt_q_next,(|sqrt_rem_next)} :
                                                   {quotient_next,(|div_rem_next)};
wire [31:0] long_rounded;
wire [4:0] long_round_flags;
fpu_round long_round (.i_sign(saved_sign),.i_exp(saved_exp),.i_sig(long_sig),
 .i_rm(saved_rm),.o_result(long_rounded),.o_flags(long_round_flags));
assign o_busy = i_valid && long_op && (state != DONE);
assign o_result = long_op ? long_result :
    madd_special ? madd_special_result :
    magnitude_zero ? {zero_sign,31'd0} : madd_rounded;
assign o_flags = long_op ? long_flags : madd_special ? {madd_nv,4'd0} :
                      magnitude_zero ? 5'd0 : madd_flags;
always @(posedge i_clk) begin
 if (i_rst) begin
  state <= IDLE; count <= 0; saved_root <= 0; saved_sign <= 0;
  saved_exp <= 0; saved_rm <= 0; div_rem <= 0; div_den <= 0;
  quotient <= 0; radicand <= 0; sqrt_rem <= 0; sqrt_q <= 0;
  long_result <= 0; long_flags <= 0;
 end else begin
  case (state)
   IDLE: begin
    if (i_valid && long_op) begin
     saved_root <= root; saved_sign <= root ? 1'b0 : a[31]^b[31];
     saved_exp <= root ? sqrt_exp : div_exp; saved_rm <= i_rm;
     count <= 0;
     if (special_long) begin
      long_result <= special_result; long_flags <= special_flags; state <= DONE;
     end else begin
      state <= RUN;
      div_rem <= div_initial - {1'b0,nb5}; div_den <= nb5; quotient <= 26'd1;
      radicand <= ax[0] ? {na5,28'd0} : {1'b0,na5,27'd0};
      sqrt_rem <= 0; sqrt_q <= 0;
     end
    end
   end
   RUN: begin
    count <= count + 6'd1;
    if (saved_root) begin
     sqrt_rem <= sqrt_rem_next; sqrt_q <= sqrt_q_next;
     radicand <= {radicand[49:0],2'b00};
     if (count == 6'd25) begin
      long_result <= long_rounded; long_flags <= long_round_flags; state <= DONE;
     end
    end else begin
     div_rem <= div_rem_next; quotient <= quotient_next;
     if (count == 6'd24) begin
      long_result <= long_rounded; long_flags <= long_round_flags; state <= DONE;
     end
    end
   end
   DONE: begin
    if (i_advance) state <= IDLE;
   end
   default: state <= IDLE;
  endcase
 end
end
endmodule
`default_nettype wire