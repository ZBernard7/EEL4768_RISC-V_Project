`timescale 1ns/1ps
`default_nettype none

// AI USE DISCLOSURE:
// OpenAI ChatGPT and Claude were used as aids in the development of this file.
// Accessed October 2026.

module hart_trace_local_tb;

    reg clk;
    reg rst;

    // ------------------------------------------------------------
    // Instruction memory (Base address: 0x0040_0000)
    // ------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    reg [31:0] imem [0:65535];

    wire [31:0] imem_offset = imem_addr - 32'h0040_0000;
    assign imem_rdata = (imem_addr >= 32'h0040_0000 && (imem_offset >> 2) < 65536) ?
                        imem[imem_offset[17:2]] : 32'h0000_0013;

    // ------------------------------------------------------------
    // Data memory
    // ------------------------------------------------------------
    wire [31:0] dmem_addr;
    wire        dmem_ren;
    wire        dmem_wen;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_mask;
    wire [31:0] dmem_rdata;

    reg [31:0] dmem [0:4095];

    wire [31:0] dmem_index = (dmem_addr + 32'd2048) >> 2;
    assign dmem_rdata = dmem[dmem_index[11:0]];

    // ------------------------------------------------------------
    // Retire interface
    // ------------------------------------------------------------
    wire        retire_valid;
    wire [31:0] retire_inst;
    wire        retire_trap;
    wire        retire_halt;

    wire [4:0]  retire_rs1_raddr;
    wire [31:0] retire_rs1_rdata;

    wire [4:0]  retire_rs2_raddr;
    wire [31:0] retire_rs2_rdata;

    wire [4:0]  retire_rd_waddr;
    wire [31:0] retire_rd_wdata;

    wire [31:0] retire_pc;
    wire [31:0] retire_next_pc;

    wire [31:0] retire_dmem_addr;
    wire        retire_dmem_ren;
    wire        retire_dmem_wen;
    wire [3:0]  retire_dmem_mask;
    wire [31:0] retire_dmem_wdata;
    wire [31:0] retire_dmem_rdata;

    hart dut (
        .i_clk(clk),
        .i_rst(rst),

        .o_imem_raddr(imem_addr),
        .i_imem_rdata(imem_rdata),

        .o_dmem_addr(dmem_addr),
        .o_dmem_ren(dmem_ren),
        .o_dmem_wen(dmem_wen),
        .o_dmem_wdata(dmem_wdata),
        .o_dmem_mask(dmem_mask),
        .i_dmem_rdata(dmem_rdata),

        .o_retire_valid(retire_valid),
        .o_retire_inst(retire_inst),
        .o_retire_trap(retire_trap),
        .o_retire_halt(retire_halt),

        .o_retire_rs1_raddr(retire_rs1_raddr),
        .o_retire_rs1_rdata(retire_rs1_rdata),

        .o_retire_rs2_raddr(retire_rs2_raddr),
        .o_retire_rs2_rdata(retire_rs2_rdata),

        .o_retire_rd_waddr(retire_rd_waddr),
        .o_retire_rd_wdata(retire_rd_wdata),

        .o_retire_pc(retire_pc),
        .o_retire_next_pc(retire_next_pc),

        .o_retire_dmem_addr(retire_dmem_addr),
        .o_retire_dmem_ren(retire_dmem_ren),
        .o_retire_dmem_wen(retire_dmem_wen),
        .o_retire_dmem_mask(retire_dmem_mask),
        .o_retire_dmem_wdata(retire_dmem_wdata),
        .o_retire_dmem_rdata(retire_dmem_rdata)
    );

    always #5 clk = ~clk;

    // Synchronous memory writes
    always @(posedge clk) begin
        if (dmem_wen) begin
            if (dmem_mask[0]) dmem[dmem_index[11:0]][ 7: 0] <= dmem_wdata[ 7: 0];
            if (dmem_mask[1]) dmem[dmem_index[11:0]][15: 8] <= dmem_wdata[15: 8];
            if (dmem_mask[2]) dmem[dmem_index[11:0]][23:16] <= dmem_wdata[23:16];
            if (dmem_mask[3]) dmem[dmem_index[11:0]][31:24] <= dmem_wdata[31:24];
        end
    end

    integer cycle_num;
    integer i;
    reg [1023:0] hex_path;
    reg tabular_mode;

    function has_rs1(input [31:0] inst);
        reg [6:0] op;
        begin
            op = inst[6:0];
            has_rs1 = (op == 7'b0110011) || (op == 7'b0010011) ||
                      (op == 7'b0000011) || (op == 7'b1100111) ||
                      (op == 7'b0100011) || (op == 7'b1100011);
        end
    endfunction

    function has_rs2(input [31:0] inst);
        reg [6:0] op;
        begin
            op = inst[6:0];
            has_rs2 = (op == 7'b0110011) || (op == 7'b0100011) || (op == 7'b1100011);
        end
    endfunction

    initial begin
        tabular_mode = $test$plusargs("TABULAR");
        clk = 1'b0;
        rst = 1'b1;
        cycle_num = 0;

        for (i = 0; i < 65536; i = i + 1)
            imem[i] = 32'h0000_0013;

        for (i = 0; i < 4096; i = i + 1)
            dmem[i] = 32'd0;

        if (!$value$plusargs("HEX=%s", hex_path))
            hex_path = "traces/hazard_program.hex";

        $readmemh(hex_path, imem);

        // Count cycles 1 and 2 under reset for cycle-accurate trace alignment
        @(posedge clk);
        #1;
        cycle_num = cycle_num + 1;
        if (!tabular_mode)
            $display("cycle=%05d BUBBLE", cycle_num);

        @(posedge clk);
        #1;
        cycle_num = cycle_num + 1;
        if (!tabular_mode)
            $display("cycle=%05d BUBBLE", cycle_num);

        // Deassert reset cleanly on negedge
        @(negedge clk);
        rst = 1'b0;

        while (1) begin
            @(posedge clk);
            #1; // Sample output once registers latch
            cycle_num = cycle_num + 1;

            if (!retire_valid) begin
                if (!tabular_mode)
                    $display("cycle=%05d BUBBLE", cycle_num);
            end else begin
                if (tabular_mode) begin
                    $display("%08x %08x %01d %01d %02x %08x %02x %08x %02x %08x %01d %08x %01x %08x %08x",
                        retire_pc,
                        retire_inst,
                        retire_trap,
                        retire_halt,
                        retire_rs1_raddr,
                        retire_rs1_rdata,
                        retire_rs2_raddr,
                        retire_rs2_rdata,
                        retire_rd_waddr,
                        retire_rd_wdata,
                        retire_dmem_wen ? 2 : (retire_dmem_ren ? 1 : 0),
                        retire_dmem_addr,
                        retire_dmem_mask,
                        retire_dmem_wdata,
                        retire_next_pc
                    );
                end else begin
                    $write("cycle=%05d [%08x] %08x ", cycle_num, retire_pc, retire_inst);

                    // RS1
                    if (has_rs1(retire_inst))
                        $write("r[%2d]=%08x ", retire_rs1_raddr, retire_rs1_rdata);
                    else
                        $write("r[--]=-------- ");

                    // RS2
                    if (has_rs2(retire_inst))
                        $write("r[%2d]=%08x ", retire_rs2_raddr, retire_rs2_rdata);
                    else
                        $write("r[--]=-------- ");

                    // Register writeback
                    if (retire_rd_waddr != 5'd0)
                        $write("w[%2d]=%08x ", retire_rd_waddr, retire_rd_wdata);

                    // Memory load
                    if (retire_dmem_ren)
                        $write("l[%08x,%04b]=%08x ", retire_dmem_addr, retire_dmem_mask, retire_dmem_rdata);

                    // Memory store
                    if (retire_dmem_wen)
                        $write("s[%08x,%04b]=%08x ", retire_dmem_addr, retire_dmem_mask, retire_dmem_wdata);

                    $display("");
                end

                if (retire_halt) begin
                    if (!tabular_mode)
                        $display("Program halted after %0d cycles.", cycle_num);
                    $finish;
                end
            end

            if (cycle_num > (tabular_mode ? 500000 : 500)) begin
                $display("TIMEOUT: Simulation exceeded limit.");
                $finish;
            end
        end
    end

endmodule

`default_nettype wire