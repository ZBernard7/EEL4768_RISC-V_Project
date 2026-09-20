`timescale 1ns / 1ps
`default_nettype none

module pc_tb;

    // Clock and Reset
    reg         clk;
    reg         rst;

    // Hart instruction memory interface
    reg  [31:0] imem_rdata;
    wire [31:0] imem_raddr;

    // Hart retire outputs checked by testbench
    wire [31:0] retire_pc;
    wire [31:0] retire_next_pc;

    // Wires to hook up datapath mock signals to hart
    // (These correspond to internal wires or external inputs driving your logic)
    integer errors = 0;

    // -------------------------------------------------------------
    // Instantiate Device Under Test (DUT)
    // -------------------------------------------------------------
    hart #(
        .RESET_ADDR(32'h0000_1000)
    ) dut (
        .i_clk(clk),
        .i_rst(rst),
        .o_imem_raddr(imem_raddr),
        .i_imem_rdata(imem_rdata),
        .o_retire_pc(retire_pc),
        .o_retire_next_pc(retire_next_pc),

        // Unused top-level ports tied off / left open
        .o_dmem_addr(),
        .o_dmem_ren(),
        .o_dmem_wen(),
        .o_dmem_wdata(),
        .o_dmem_mask(),
        .i_dmem_rdata(32'd0),
        .o_retire_valid(),
        .o_retire_inst(),
        .o_retire_trap(),
        .o_retire_halt(),
        .o_retire_rs1_raddr(),
        .o_retire_rs1_rdata(),
        .o_retire_rs2_raddr(),
        .o_retire_rs2_rdata(),
        .o_retire_rd_waddr(),
        .o_retire_rd_wdata()
    );

    // 100 MHz clock generation (10ns period)
    always #5 clk = ~clk;

    // Task for verification
    task check_pc(input [31:0] expected_pc, input [31:0] expected_next_pc, input [8*24:1] test_name);
        begin
            #1; // Small delta delay after clock edge
            if (retire_pc !== expected_pc) begin
                $display("[FAIL] %0s: PC expected 0x%08h, got 0x%08h", test_name, expected_pc, retire_pc);
                errors = errors + 1;
            end else if (retire_next_pc !== expected_next_pc) begin
                $display("[FAIL] %0s: next_pc expected 0x%08h, got 0x%08h", test_name, expected_next_pc, retire_next_pc);
                errors = errors + 1;
            end else begin
                $display("[PASS] %0s: PC = 0x%08h -> next_pc = 0x%08h", test_name, retire_pc, retire_next_pc);
            end
        end
    endtask

    initial begin
        clk        = 0;
        rst        = 1;
        imem_rdata = 32'h00000013; // NOP (addi x0, x0, 0)

        // Hold reset across 2 clock edges
        @(posedge clk);
        @(posedge clk);
        #1;
        if (retire_pc !== 32'h0000_1000) begin
            $display("[FAIL] Reset State: Expected PC 0x00001000, got 0x%08h", retire_pc);
            errors = errors + 1;
        end else begin
            $display("[PASS] Reset State: PC initialized correctly to 0x00001000.");
        end

        // Deassert reset
        rst = 0;

        // -----------------------------------------------------------------
        // TEST 1: Sequential Increment (PC + 4)
        // -----------------------------------------------------------------
        imem_rdata = 32'h00000013; // NOP
        check_pc(32'h0000_1000, 32'h0000_1004, "Sequential step 1");

        @(posedge clk);
        imem_rdata = 32'h00000013; // NOP
        check_pc(32'h0000_1004, 32'h0000_1008, "Sequential step 2");

        // -----------------------------------------------------------------
        // TEST 2: JAL (Jump and Link) -> imm = +32 bytes (0x20)
        // Expected target: 0x1008 + 0x20 = 0x1028
        // JAL format: [imm[20|10:1|11|19:12]] [rd] [opcode=1101111]
        // -----------------------------------------------------------------
        @(posedge clk);
        imem_rdata = 32'h020000ef; // jal x1, +32
        check_pc(32'h0000_1008, 32'h0000_1028, "JAL Jump Target");

        @(posedge clk);
        // Landed on 0x1028; feed NOP to test sequential after jump
        imem_rdata = 32'h00000013;
        check_pc(32'h0000_1028, 32'h0000_102c, "Step after JAL");

        // -----------------------------------------------------------------
        // TEST 3: Branch Not Taken (BEQ when condition false)
        // BNE/BEQ instruction with offset +12 (0x0c)
        // Current PC: 0x102c -> next sequential: 0x1030
        // -----------------------------------------------------------------
        @(posedge clk);
        imem_rdata = 32'h00000663; // beq x0, x0, +12 (with alu_eq = 0 default)
        check_pc(32'h0000_102c, 32'h0000_1030, "Untaken Branch");

        // -----------------------------------------------------------------
        // Summary Banner
        // -----------------------------------------------------------------
        #10;
        $display("\n========================================================");
        if (errors == 0) begin
            $display("    ALL PC / TARGET TESTS PASSED SUCCESSFULLY!");
        end else begin
            $display("    TESTS FAILED WITH %0d ERROR(S)", errors);
        end
        $display("========================================================\n");

        $finish;
    end

endmodule

`default_nettype wire