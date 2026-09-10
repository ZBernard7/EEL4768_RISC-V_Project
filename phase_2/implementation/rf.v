// Utilized gemini accessed 9/8/26
`default_nettype none

// The register file is effectively a single cycle memory with 32-bit words
// and depth 32. It has two asynchronous read ports, allowing two independent
// registers to be read at the same time combinationally, and one synchronous
// write port, allowing a register to be written to on the next clock edge.
//
// The register `x0` is hardwired to zero.
// NOTE: This can be implemented either by silently discarding writesto
// address 5'd0, or by muxing the output to zero when reading from that
// address.
module rf #(
    // When this parameter is set to 1, "RF bypass" mode is enabled. This
    // allows data at the write port to be observed at the read ports
    // immediately without having to wait for the next clock edge. This is
    // a common forwarding optimization in a pipelined core (phase 5), but will
    // cause a single-cycle processor to behave incorrectly. You are required
    // to implement and test both modes. In phase 4, you will disable this
    // parameter, before enabling it in phase 6.
    parameter BYPASS_EN = 0
) (
    // Global clock.
    input  wire        i_clk,
    // Synchronous active-high reset.
    input  wire        i_rst,
    // Both read register ports are asynchronous (zero-cycle). That is, read
    // data is visible combinationally without having to wait for a clock.
    //
    // The read ports are *independent* and can read two different registers
    // (but of course, also the same register if needed).
    //
    // Register `x0` is hardwired to zero, so reading from address 5'd0
    // should always return 32'd0 on either port regardless of any writes.
    //
    // Register read port 1, with input address [0, 31] and output data.
    input  wire [ 4:0] i_rs1_raddr,
    output wire [31:0] o_rs1_rdata,
    // Register read port 2, with input address [0, 31] and output data.
    input  wire [ 4:0] i_rs2_raddr,
    output wire [31:0] o_rs2_rdata,
    // The register write port is synchronous. When write is enabled, the
    // data at the write port will be written to the specified register
    // at the next clock edge. When the writen enable is low, the register
    // file should remain unchanged at the clock edge.
    //
    // Write register enable, address [0, 31] and input data.
    input  wire        i_rd_wen,
    input  wire [ 4:0] i_rd_waddr,
    input  wire [31:0] i_rd_wdata
);
    // Your implementation goes under here
    // ------------------------------------

    // 1. Array storage holding 32 registers (32-bit each)
    reg [31:0] registers [31:0];
    integer i;

    // Initialize array at time 0 to prevent 'x' values before any reset pulse
    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] = 32'b0;
        end
    end

    // 2. Synchronous Register Write & Reset
    always @(posedge i_clk) begin
        if (i_rst) begin
            // Active-high synchronous reset: clear all 32 registers to 0
            for (i = 0; i < 32; i = i + 1) begin
                registers[i] <= 32'b0;
            end
        end else if (i_rd_wen && (i_rd_waddr != 5'b00000)) begin
            // Write to register if write enable is active and target is not x0
            registers[i_rd_waddr] <= i_rd_wdata;
        end
    end

    // 3. Combinational Read Ports with Generate-based Bypass Logic
    generate
        if (BYPASS_EN != 0) begin : gen_bypass_enabled
            // Read Port 1 (with forwarding)
            assign o_rs1_rdata = (i_rs1_raddr == 5'b00000) ? 32'b0 :
                                 (i_rd_wen && (i_rd_waddr == i_rs1_raddr)) ? i_rd_wdata :
                                 registers[i_rs1_raddr];

            // Read Port 2 (with forwarding)
            assign o_rs2_rdata = (i_rs2_raddr == 5'b00000) ? 32'b0 :
                                 (i_rd_wen && (i_rd_waddr == i_rs2_raddr)) ? i_rd_wdata :
                                 registers[i_rs2_raddr];
        end else begin : gen_bypass_disabled
            // Read Port 1 (standard read)
            assign o_rs1_rdata = (i_rs1_raddr == 5'b00000) ? 32'b0 : registers[i_rs1_raddr];

            // Read Port 2 (standard read)
            assign o_rs2_rdata = (i_rs2_raddr == 5'b00000) ? 32'b0 : registers[i_rs2_raddr];
        end
    endgenerate

endmodule

`default_nettype wire