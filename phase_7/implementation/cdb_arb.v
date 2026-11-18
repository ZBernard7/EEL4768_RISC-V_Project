// AI USE DISCLOSURE:
// Chat GPT was used to help type redunant parts of the code.
// Accessed November 2026.
`default_nettype none

module cdb_arb #(
  parameter TAG_W = 3
) (
  input  wire [TAG_W-1:0]     i_rob_head,
  input  wire [3:0]           i_req,
  input  wire [(TAG_W<<2)-1:0] i_tags,
  input  wire [127:0]         i_values,
  output wire [3:0]           o_grant,
  output wire                 o_valid,
  output wire [TAG_W-1:0]     o_tag,
  output wire [31:0]          o_value
);
  wire [TAG_W-1:0] tags [0:3];
  wire [TAG_W-1:0] distance [0:3];

  assign {tags[3], tags[2], tags[1], tags[0]} = i_tags;

  genvar lane;
  generate
    for (lane = 0; lane < 4; lane = lane + 1) begin : gen_lane
      wire [3:0] blocked;
      assign distance[lane] = tags[lane] - i_rob_head;

      genvar peer;
      for (peer = 0; peer < 4; peer = peer + 1) begin : gen_peer
        assign blocked[peer] = i_req[peer] &&
            ((distance[peer] < distance[lane]) ||
             ((distance[peer] == distance[lane]) && (peer < lane)));
      end

      assign o_grant[lane] = i_req[lane] && !(|blocked);
    end
  endgenerate

  assign o_valid = |o_grant;
  assign o_tag = o_grant[0] ? tags[0] :
                 o_grant[1] ? tags[1] :
                 o_grant[2] ? tags[2] :
                 o_grant[3] ? tags[3] : {TAG_W{1'b0}};
  assign o_value = o_grant[0] ? i_values[31:0] :
                   o_grant[1] ? i_values[63:32] :
                   o_grant[2] ? i_values[95:64] :
                   o_grant[3] ? i_values[127:96] : 32'b0;
endmodule

`default_nettype wire