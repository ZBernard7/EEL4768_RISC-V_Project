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
//
// Phase 6: the same module also holds the 32 floating-point registers
// f0-f31, with three read ports (the fused multiply-add instructions read
// rs3) and a write port with an explicit write enable. Unlike x0, f0 is an
// ordinary register, so address 5'd0 cannot mean "no write" there.
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
    input  wire [ 4:0] i_rd_waddr,
    input  wire [31:0] i_rd_wdata,
    // Floating-point read ports 1-3, with input address [0, 31] and output
    // data. All three are asynchronous and independent, like the integer
    // ports. f0 is an ordinary register.
    input  wire [ 4:0] i_frs1_raddr,
    output wire [31:0] o_frs1_rdata,
    input  wire [ 4:0] i_frs2_raddr,
    output wire [31:0] o_frs2_rdata,
    input  wire [ 4:0] i_frs3_raddr,
    output wire [31:0] o_frs3_rdata,
    // Floating-point write port: synchronous, written at the next clock edge
    // when the write enable is high (any address, f0 included).
    input  wire        i_frd_wen,
    input  wire [ 4:0] i_frd_waddr,
    input  wire [31:0] i_frd_wdata
);

// Write your code here.
// Separate integer and floating-point register banks.
reg [31:0] xregs [0:31];
reg [31:0] fregs [0:31];

// A generate loop builds one clocked block per register.
// Unlike a procedural loop, this is allowed by the coding rules.
genvar r;
generate
    for (r = 0; r < 32; r = r + 1) begin : gen_registers
        always @(posedge i_clk) begin
            if (i_rst) begin
                xregs[r] <= 32'd0;
                fregs[r] <= 32'd0;
            end else begin
                // No integer write enable: writing x0 means discard.
                if ((r != 0) && (i_rd_waddr == r)) begin
                    xregs[r] <= i_rd_wdata;
                end

                // All FP registers, including f0, are writable.
                if (i_frd_wen && (i_frd_waddr == r)) begin
                    fregs[r] <= i_frd_wdata;
                end
            end
        end
    end
endgenerate

// Integer reads: x0 always reads as zero.
// With bypass enabled, matching writes are visible immediately.
assign o_rs1_rdata =
    (i_rs1_raddr == 5'd0) ? 32'd0 :
    ((BYPASS_EN != 0) && (i_rd_waddr == i_rs1_raddr))
        ? i_rd_wdata : xregs[i_rs1_raddr];

assign o_rs2_rdata =
    (i_rs2_raddr == 5'd0) ? 32'd0 :
    ((BYPASS_EN != 0) && (i_rd_waddr == i_rs2_raddr))
        ? i_rd_wdata : xregs[i_rs2_raddr];

// FP reads: bypass requires an enabled FP write.
// Integer writes never bypass into the FP bank, or vice versa.
assign o_frs1_rdata =
    ((BYPASS_EN != 0) && i_frd_wen
     && (i_frd_waddr == i_frs1_raddr))
        ? i_frd_wdata : fregs[i_frs1_raddr];

assign o_frs2_rdata =
    ((BYPASS_EN != 0) && i_frd_wen
     && (i_frd_waddr == i_frs2_raddr))
        ? i_frd_wdata : fregs[i_frs2_raddr];

assign o_frs3_rdata =
    ((BYPASS_EN != 0) && i_frd_wen
     && (i_frd_waddr == i_frs3_raddr))
        ? i_frd_wdata : fregs[i_frs3_raddr];

endmodule

`default_nettype wire