// AI USE DISCLOSURE:
// Chat GPT was used to help type redunant parts of the code.
// Accessed November 2026.
`default_nettype none

module rat #(
  parameter TAG_W = 3
) (
  input  wire             i_clk,
  input  wire             i_rst,
  input  wire [4:0]       i_rs1,
  input  wire [4:0]       i_rs2,
  output wire             o_rs1_mapped,
  output wire             o_rs2_mapped,
  output wire [TAG_W-1:0] o_rs1_tag,
  output wire [TAG_W-1:0] o_rs2_tag,
  input  wire             i_rename_valid,
  input  wire [4:0]       i_rename_rd,
  input  wire [TAG_W-1:0] i_rename_tag,
  input  wire             i_retire_valid,
  input  wire [4:0]       i_retire_rd,
  input  wire [TAG_W-1:0] i_retire_tag
);
  wire [31:0] mapped;
  wire [TAG_W-1:0] tags [0:31];

  assign mapped[0] = 1'b0;
  assign tags[0] = {TAG_W{1'b0}};

  assign o_rs1_mapped = mapped[i_rs1];
  assign o_rs2_mapped = mapped[i_rs2];
  assign o_rs1_tag = tags[i_rs1];
  assign o_rs2_tag = tags[i_rs2];

  genvar reg_index;
  generate
    for (reg_index = 1; reg_index < 32; reg_index = reg_index + 1) begin : gen_mapping
      localparam [4:0] REG_NUM = reg_index;
      reg valid;
      reg [TAG_W-1:0] tag;

      assign mapped[reg_index] = valid;
      assign tags[reg_index] = tag;

      always @(posedge i_clk) begin
        if (i_rst) begin
          valid <= 1'b0;
          tag <= {TAG_W{1'b0}};
        end else if (i_rename_valid && i_rename_rd == REG_NUM) begin
          valid <= 1'b1;
          tag <= i_rename_tag;
        end else if (i_retire_valid && i_retire_rd == REG_NUM &&
                     valid && i_retire_tag == tag) begin
          valid <= 1'b0;
        end
      end
    end
  endgenerate
endmodule

`default_nettype wire