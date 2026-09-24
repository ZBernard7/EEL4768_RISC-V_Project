`timescale 1ns/1ps
`default_nettype none

module hart_trace_local_tb;

    reg clk;
    reg rst;

    // ------------------------------------------------------------
    // Instruction memory
    // ------------------------------------------------------------
    wire [31:0] imem_addr;
    wire [31:0] imem_rdata;

    reg [31:0] imem [0:65535];

    assign imem_rdata = imem[imem_addr[17:2]];

    // ------------------------------------------------------------
    // Data memory
    // ------------------------------------------------------------
    wire [31:0] dmem_addr;
    wire        dmem_ren;
    wire        dmem_wen;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_mask;
    wire [31:0] dmem_rdata;

    reg [31:0] dmem [0:1023];

    wire [31:0] dmem_index;
    assign dmem_index = (dmem_addr + 32'd2048) >> 2;

    assign dmem_rdata = dmem[dmem_index[9:0]];

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

    hart dut (
        .i_clk(i_clk),
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
        .o_retire_next_pc(retire_next_pc)
    );

    // Alias so DUT clock connection stays readable
    wire i_clk = clk;

    always #5 clk = ~clk;

    // ------------------------------------------------------------
    // Data-memory writes commit on the rising edge.
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (dmem_wen) begin
            if (dmem_mask[0])
                dmem[dmem_index[9:0]][7:0] <= dmem_wdata[7:0];

            if (dmem_mask[1])
                dmem[dmem_index[9:0]][15:8] <= dmem_wdata[15:8];

            if (dmem_mask[2])
                dmem[dmem_index[9:0]][23:16] <= dmem_wdata[23:16];

            if (dmem_mask[3])
                dmem[dmem_index[9:0]][31:24] <= dmem_wdata[31:24];
        end
    end

    // ------------------------------------------------------------
    // Expected trace fields
    // ------------------------------------------------------------
    reg [31:0] exp_pc;
    reg [31:0] exp_inst;

    reg        exp_trap;
    reg        exp_halt;

    reg [4:0]  exp_rs1_raddr;
    reg [31:0] exp_rs1_rdata;

    reg [4:0]  exp_rs2_raddr;
    reg [31:0] exp_rs2_rdata;

    reg [4:0]  exp_rd_waddr;
    reg [31:0] exp_rd_wdata;

    reg [1:0]  exp_mem_op;
    reg [31:0] exp_mem_addr;
    reg [3:0]  exp_mem_mask;
    reg [31:0] exp_mem_wdata;

    reg [31:0] exp_next_pc;

    wire [1:0] actual_mem_op;

    assign actual_mem_op =
        dmem_ren ? 2'd1 :
        dmem_wen ? 2'd2 :
                   2'd0;

    integer trace_file;
    integer scan_count;
    integer vector_num;
    integer failures;
    integer i;

    // ------------------------------------------------------------
    // Compare one retired instruction.
    //
    // Trace fields containing x are represented as X in the
    // expected register, so reduction-XOR lets us detect don't-care.
    // ------------------------------------------------------------
    task check_vector;
    begin
        if (retire_valid !== 1'b1) begin
            $display("[FAIL] vector %0d: retire_valid is not 1", vector_num);
            failures = failures + 1;
        end

        if (retire_pc !== exp_pc) begin
            $display("[FAIL] vector %0d: pc got=%h expected=%h",
                     vector_num, retire_pc, exp_pc);
            failures = failures + 1;
        end

        if (retire_inst !== exp_inst) begin
            $display("[FAIL] vector %0d: inst got=%h expected=%h",
                     vector_num, retire_inst, exp_inst);
            failures = failures + 1;
        end

        if (retire_trap !== exp_trap) begin
            $display("[FAIL] vector %0d: trap got=%b expected=%b",
                     vector_num, retire_trap, exp_trap);
            failures = failures + 1;
        end

        if (retire_halt !== exp_halt) begin
            $display("[FAIL] vector %0d: halt got=%b expected=%b",
                     vector_num, retire_halt, exp_halt);
            failures = failures + 1;
        end

        if ((^exp_rs1_raddr !== 1'bx) &&
            (retire_rs1_raddr !== exp_rs1_raddr)) begin
            $display("[FAIL] vector %0d: rs1_raddr got=%h expected=%h",
                     vector_num, retire_rs1_raddr, exp_rs1_raddr);
            failures = failures + 1;
        end

        if ((^exp_rs1_rdata !== 1'bx) &&
            (retire_rs1_rdata !== exp_rs1_rdata)) begin
            $display("[FAIL] vector %0d: rs1_rdata got=%h expected=%h",
                     vector_num, retire_rs1_rdata, exp_rs1_rdata);
            failures = failures + 1;
        end

        if ((^exp_rs2_raddr !== 1'bx) &&
            (retire_rs2_raddr !== exp_rs2_raddr)) begin
            $display("[FAIL] vector %0d: rs2_raddr got=%h expected=%h",
                     vector_num, retire_rs2_raddr, exp_rs2_raddr);
            failures = failures + 1;
        end

        if ((^exp_rs2_rdata !== 1'bx) &&
            (retire_rs2_rdata !== exp_rs2_rdata)) begin
            $display("[FAIL] vector %0d: rs2_rdata got=%h expected=%h",
                     vector_num, retire_rs2_rdata, exp_rs2_rdata);
            failures = failures + 1;
        end

        if (retire_rd_waddr !== exp_rd_waddr) begin
            $display("[FAIL] vector %0d: rd_waddr got=%h expected=%h",
                     vector_num, retire_rd_waddr, exp_rd_waddr);
            failures = failures + 1;
        end

        if ((exp_rd_waddr != 5'd0) &&
            (retire_rd_wdata !== exp_rd_wdata)) begin
            $display("[FAIL] vector %0d: rd_wdata got=%h expected=%h",
                     vector_num, retire_rd_wdata, exp_rd_wdata);
            failures = failures + 1;
        end

        if (actual_mem_op !== exp_mem_op) begin
            $display("[FAIL] vector %0d: mem_op got=%h expected=%h",
                     vector_num, actual_mem_op, exp_mem_op);
            failures = failures + 1;
        end

        if (exp_mem_op != 2'd0) begin
            if (dmem_addr !== exp_mem_addr) begin
                $display("[FAIL] vector %0d: mem_addr got=%h expected=%h",
                         vector_num, dmem_addr, exp_mem_addr);
                failures = failures + 1;
            end

            if (dmem_mask !== exp_mem_mask) begin
                $display("[FAIL] vector %0d: mem_mask got=%h expected=%h",
                         vector_num, dmem_mask, exp_mem_mask);
                failures = failures + 1;
            end
        end

        if (exp_mem_op == 2'd2) begin
            if (exp_mem_mask[0] &&
                dmem_wdata[7:0] !== exp_mem_wdata[7:0]) begin
                $display("[FAIL] vector %0d: mem_wdata lane0", vector_num);
                failures = failures + 1;
            end

            if (exp_mem_mask[1] &&
                dmem_wdata[15:8] !== exp_mem_wdata[15:8]) begin
                $display("[FAIL] vector %0d: mem_wdata lane1", vector_num);
                failures = failures + 1;
            end

            if (exp_mem_mask[2] &&
                dmem_wdata[23:16] !== exp_mem_wdata[23:16]) begin
                $display("[FAIL] vector %0d: mem_wdata lane2", vector_num);
                failures = failures + 1;
            end

            if (exp_mem_mask[3] &&
                dmem_wdata[31:24] !== exp_mem_wdata[31:24]) begin
                $display("[FAIL] vector %0d: mem_wdata lane3", vector_num);
                failures = failures + 1;
            end
        end

        if (retire_next_pc !== exp_next_pc) begin
            $display("[FAIL] vector %0d: next_pc got=%h expected=%h",
                     vector_num, retire_next_pc, exp_next_pc);
            failures = failures + 1;
        end
    end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin
        clk = 1'b0;
        rst = 1'b1;

        vector_num = 0;
        failures = 0;

        // Zero local memories.
        for (i = 0; i < 65536; i = i + 1)
            imem[i] = 32'h00000013;

        for (i = 0; i < 1024; i = i + 1)
            dmem[i] = 32'd0;

        $readmemh("../traces/hart_program.hex", imem);

        trace_file = $fopen("hart_clean.trace", "r");

        if (trace_file == 0) begin
            $display("ERROR: could not open hart_clean.trace");
            $finish;
        end

        // Apply synchronous reset for a complete rising edge.
        @(posedge clk);
        #1;

        @(negedge clk);
        rst = 1'b0;

        while (!$feof(trace_file)) begin

            scan_count = $fscanf(
                trace_file,
                "%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",
                exp_pc,
                exp_inst,
                exp_trap,
                exp_halt,
                exp_rs1_raddr,
                exp_rs1_rdata,
                exp_rs2_raddr,
                exp_rs2_rdata,
                exp_rd_waddr,
                exp_rd_wdata,
                exp_mem_op,
                exp_mem_addr,
                exp_mem_mask,
                exp_mem_wdata,
                exp_next_pc
            );

            if (scan_count == 15) begin
                #1;

                check_vector;

                vector_num = vector_num + 1;

                if (failures >= 20) begin
                    $display("");
                    $display("STOPPING AFTER 20 FAILURES");
                    $display("First problems occurred by vector %0d",
                             vector_num);
                    $finish;
                end

                if (exp_halt == 1'b1) begin
                    $display("");
                    $display("Reached EBREAK at vector %0d", vector_num);
                end

                @(posedge clk);
                #1;
                @(negedge clk);
            end
        end

        $fclose(trace_file);

        $display("");
        $display("--------------------------------");
        $display("vectors checked: %0d", vector_num);
        $display("failures:        %0d", failures);

        if ((vector_num == 22661) && (failures == 0))
            $display("TRACE TEST PASSED");
        else
            $display("TRACE TEST FAILED");

        $finish;
    end

endmodule

`default_nettype wire
