// AI USE DISCLOSURE:
// Chat GPT was used to help type redunant parts of the code.
// Accessed November 2026.

// Graded FV harness. Fill this in and submit as riscv_fv.v (submission root,
// next to hart.v). Module name must remain riscv_fv.
//
// The shipped riscv_fv.sby always compiles exactly:
//   riscv_fv.v  cdb_arb.v  rat.v
// Instantiate YOUR cdb_arb / rat here and write assume/assert properties that
// SymbiYosys (sby) reports as PASS. Learn the toolchain first with
// fv/example/mutex/.
//
// Self-check:
//   fv/riscv/run.sh /path/to/your/submission   (from phase_7/)
//
// Credit (PDF Sections 6.2, 7.7): at least 10 non-vacuous asserts using the assert keyword, and sby reports PASS.

`default_nettype wire

`default_nettype none

module riscv_fv (
  input wire         i_clk,
  input wire         i_rst,
  input wire [2:0]   i_rob_head,
  input wire [3:0]   i_req,
  input wire [11:0]  i_tags,
  input wire [127:0] i_values,
  input wire [4:0]   i_rs2,
  input wire         i_rename_valid,
  input wire [4:0]   i_rename_rd,
  input wire [2:0]   i_rename_tag,
  input wire         i_retire_valid,
  input wire [4:0]   i_retire_rd,
  input wire [2:0]   i_retire_tag
);

  (* anyconst *) reg [4:0] watched_reg;

  wire [3:0] grant;
  wire cdb_valid;
  wire [2:0] cdb_tag;
  wire [31:0] cdb_value;
  wire rs1_mapped, rs2_mapped;
  wire [2:0] rs1_tag, rs2_tag;

  cdb_arb dut_cdb (
    .i_rob_head(i_rob_head),
    .i_req(i_req),
    .i_tags(i_tags),
    .i_values(i_values),
    .o_grant(grant),
    .o_valid(cdb_valid),
    .o_tag(cdb_tag),
    .o_value(cdb_value)
  );

  rat dut_rat (
    .i_clk(i_clk),
    .i_rst(i_rst),
    .i_rs1(watched_reg),
    .i_rs2(i_rs2),
    .o_rs1_mapped(rs1_mapped),
    .o_rs2_mapped(rs2_mapped),
    .o_rs1_tag(rs1_tag),
    .o_rs2_tag(rs2_tag),
    .i_rename_valid(i_rename_valid),
    .i_rename_rd(i_rename_rd),
    .i_rename_tag(i_rename_tag),
    .i_retire_valid(i_retire_valid),
    .i_retire_rd(i_retire_rd),
    .i_retire_tag(i_retire_tag)
  );

  always @(*) begin
    assert (cdb_valid == (|grant));
    assert (cdb_valid == (|i_req));
    assert ((grant & ~i_req) == 4'b0);
    assert (grant == 4'b0000 || grant == 4'b0001 ||
            grant == 4'b0010 || grant == 4'b0100 ||
            grant == 4'b1000);

    if (watched_reg == 5'd0) begin
      assert (!rs1_mapped);
      assert (rs1_tag == 3'd0);
    end
    if (i_rs2 == 5'd0) begin
      assert (!rs2_mapped);
      assert (rs2_tag == 3'd0);
    end
  end

  genvar lane;
  generate
    for (lane = 0; lane < 4; lane = lane + 1) begin : gen_check_lane
      wire [2:0] request_tag = i_tags[3*lane +: 3];
      wire [2:0] age = request_tag - i_rob_head;

      always @(*) begin
        if (grant[lane]) begin
          assert (cdb_tag == request_tag);
          assert (cdb_value == i_values[32*lane +: 32]);
        end
      end

      genvar peer;
      for (peer = 0; peer < 4; peer = peer + 1) begin : gen_check_peer
        wire [2:0] peer_age = i_tags[3*peer +: 3] - i_rob_head;

        always @(*) begin
          if (grant[lane] && i_req[peer]) begin
            assert (age <= peer_age);
            if (peer < lane)
              assert (age < peer_age);
          end
        end
      end
    end
  endgenerate

  reg past_valid = 1'b0;
  reg expected_mapped;
  reg [2:0] expected_tag;

  always @(posedge i_clk) begin
    past_valid <= 1'b1;
    if (!past_valid)
      assume (i_rst);

    if (i_rst || watched_reg == 5'd0) begin
      expected_mapped <= 1'b0;
      expected_tag <= 3'd0;
    end else if (i_rename_valid && i_rename_rd == watched_reg) begin
      expected_mapped <= 1'b1;
      expected_tag <= i_rename_tag;
    end else if (i_retire_valid && i_retire_rd == watched_reg &&
                 expected_mapped && i_retire_tag == expected_tag) begin
      expected_mapped <= 1'b0;
    end

    if (past_valid) begin
      assert (rs1_mapped == expected_mapped);
      if (expected_mapped)
        assert (rs1_tag == expected_tag);

      if (i_rs2 == watched_reg) begin
        assert (rs2_mapped == rs1_mapped);
        assert (rs2_tag == rs1_tag);
      end
    end
  end
endmodule

`default_nettype wire