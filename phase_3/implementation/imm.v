`default_nettype none

module imm (
    input wire [31:0] i_inst,
    input wire [5:0]  i_format,
    output wire [31:0] o_immediate
);

    reg [31:0] immediate;

    always @(*) begin
        case (i_format)

            // R-type: no immediate
            6'b000001:
                immediate = 32'b0;

            // I-type
            6'b000010:
                immediate = {{20{i_inst[31]}}, i_inst[31:20]};

            // S-type
            6'b000100:
                immediate = {{20{i_inst[31]}}, i_inst[31:25], i_inst[11:7]};

            // B-type
            6'b001000:
                immediate = {{19{i_inst[31]}},
                             i_inst[31],
                             i_inst[7],
                             i_inst[30:25],
                             i_inst[11:8],
                             1'b0};

            // U-type
            6'b010000:
                immediate = {i_inst[31:12], 12'b0};

            // J-type
            6'b100000:
                immediate = {{11{i_inst[31]}},
                             i_inst[31],
                             i_inst[19:12],
                             i_inst[20],
                             i_inst[30:21],
                             1'b0};

            default:
                immediate = 32'b0;

        endcase
    end

    assign o_immediate = immediate;

endmodule

`default_nettype wire