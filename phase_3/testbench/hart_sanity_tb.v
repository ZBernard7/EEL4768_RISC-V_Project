`timescale 1ns/1ps
`default_nettype none

module hart_sanity_tb;

    reg clk;
    reg rst;

    wire [31:0] imem_addr;
    reg  [31:0] imem_rdata;

    wire [31:0] dmem_addr;
    wire        dmem_ren;
    wire        dmem_wen;
    wire [31:0] dmem_wdata;
    wire [3:0]  dmem_mask;
    reg  [31:0] dmem_rdata;

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
        .o_retire_next_pc(retire_next_pc)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        imem_rdata = 32'h00000013; // nop
        dmem_rdata = 32'd0;

        #10;
        rst = 1'b0;

        // addi x1, x0, 5
        imem_rdata = 32'h00500093;
        #10;

        $display("TEST 1 ADDI");
        $display("pc=%h next=%h rd=%0d wdata=%h trap=%b",
                 retire_pc, retire_next_pc,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (retire_rd_waddr != 5'd1)
            $display("FAIL: expected rd=x1");

        if (retire_rd_wdata != 32'd5)
            $display("FAIL: expected writeback=5");

        if (retire_trap != 1'b0)
            $display("FAIL: ADDI trapped");

        // addi x2, x1, 3
        imem_rdata = 32'h00308113;
        #10;

        $display("TEST 2 DEPENDENCY");
        $display("rs1=%0d rs1_data=%h rd=%0d wdata=%h",
                 retire_rs1_raddr, retire_rs1_rdata,
                 retire_rd_waddr, retire_rd_wdata);

        if (retire_rs1_raddr != 5'd1)
            $display("FAIL: expected rs1=x1");

        if (retire_rs1_rdata != 32'd5)
            $display("FAIL: expected x1=5");

        if (retire_rd_waddr != 5'd2)
            $display("FAIL: expected rd=x2");

        if (retire_rd_wdata != 32'd8)
            $display("FAIL: expected writeback=8");

        // Test 3: BEQ taken
        // beq x1, x1, +8
        imem_rdata = 32'h00108463;
        #10;

        $display("TEST 3 BEQ TAKEN");
        $display("pc=%h next=%h trap=%b",
                 retire_pc, retire_next_pc, retire_trap);

        if (retire_next_pc != retire_pc + 32'd8)
            $display("FAIL: BEQ should branch by +8");

        if (retire_trap)
            $display("FAIL: BEQ trapped");

        // Test 4: BEQ not taken
        // beq x1, x2, +8
        imem_rdata = 32'h00208463;
        #10;

        $display("TEST 4 BEQ NOT TAKEN");
        $display("pc=%h next=%h trap=%b",
                 retire_pc, retire_next_pc, retire_trap);

        if (retire_next_pc != retire_pc + 32'd4)
            $display("FAIL: BEQ should fall through");

        if (retire_trap)
            $display("FAIL: BEQ trapped");

        // Test 5: SW x2, 0(x0)
        // x2 should currently contain 8
        imem_rdata = 32'h00202023;
        #10;

        $display("TEST 5 SW");
        $display("addr=%h wen=%b mask=%b wdata=%h trap=%b",
                 dmem_addr, dmem_wen, dmem_mask,
                 dmem_wdata, retire_trap);

        if (dmem_wen != 1'b1)
            $display("FAIL: SW should assert write enable");

        if (dmem_addr != 32'h00000000)
            $display("FAIL: SW expected address 0");

        if (dmem_mask != 4'b1111)
            $display("FAIL: SW expected mask 1111");

        if (dmem_wdata != 32'd8)
            $display("FAIL: SW expected data 8");

        if (retire_trap)
            $display("FAIL: SW trapped");


        // Test 6: LW x3, 0(x0)
        // Pretend memory at address 0 contains 8
        dmem_rdata = 32'd8;
        imem_rdata = 32'h00002183;
        #10;

        $display("TEST 6 LW");
        $display("addr=%h ren=%b mask=%b rd=%0d wdata=%h trap=%b",
                 dmem_addr, dmem_ren, dmem_mask,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (dmem_ren != 1'b1)
            $display("FAIL: LW should assert read enable");

        if (dmem_addr != 32'h00000000)
            $display("FAIL: LW expected address 0");

        if (dmem_mask != 4'b1111)
            $display("FAIL: LW expected mask 1111");

        if (retire_rd_waddr != 5'd3)
            $display("FAIL: LW expected rd=x3");

        if (retire_rd_wdata != 32'd8)
            $display("FAIL: LW expected writeback=8");

        if (retire_trap)
            $display("FAIL: LW trapped");

        // Test 7: SB x2, 1(x0)
        // x2 = 8, so store byte 0x08 into byte lane 1
        imem_rdata = 32'h002000a3;
        #10;

        $display("TEST 7 SB");
        $display("addr=%h wen=%b mask=%b wdata=%h trap=%b",
                 dmem_addr, dmem_wen, dmem_mask,
                 dmem_wdata, retire_trap);

        if (dmem_wen != 1'b1)
            $display("FAIL: SB should assert write enable");

        if (dmem_addr != 32'h00000000)
            $display("FAIL: SB expected aligned address 0");

        if (dmem_mask != 4'b0010)
            $display("FAIL: SB expected mask 0010");

        if (dmem_wdata[15:8] != 8'h08)
            $display("FAIL: SB expected 08 in byte lane 1");

        if (retire_trap)
            $display("FAIL: SB trapped");


        // Test 8: LB x4, 1(x0)
        // Pretend word at address 0 is 0000FF00
        // byte lane 1 = FF, so LB should sign-extend to FFFFFFFF
        dmem_rdata = 32'h0000FF00;
        imem_rdata = 32'h00100203;
        #10;

        $display("TEST 8 LB");
        $display("addr=%h ren=%b mask=%b rd=%0d wdata=%h trap=%b",
                 dmem_addr, dmem_ren, dmem_mask,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (dmem_ren != 1'b1)
            $display("FAIL: LB should assert read enable");

        if (dmem_mask != 4'b0010)
            $display("FAIL: LB expected mask 0010");

        if (retire_rd_waddr != 5'd4)
            $display("FAIL: LB expected rd=x4");

        if (retire_rd_wdata != 32'hFFFFFFFF)
            $display("FAIL: LB expected sign-extended FF");

        if (retire_trap)
            $display("FAIL: LB trapped");

        // Test 9: SH x2, 2(x0)
        // x2 = 8, so write 0x0008 into upper halfword lanes
        imem_rdata = 32'h00201123;
        #10;

        $display("TEST 9 SH");
        $display("addr=%h wen=%b mask=%b wdata=%h trap=%b",
                 dmem_addr, dmem_wen, dmem_mask,
                 dmem_wdata, retire_trap);

        if (dmem_wen != 1'b1)
            $display("FAIL: SH should assert write enable");

        if (dmem_addr != 32'h00000000)
            $display("FAIL: SH expected aligned address 0");

        if (dmem_mask != 4'b1100)
            $display("FAIL: SH expected mask 1100");

        if (dmem_wdata[31:16] != 16'h0008)
            $display("FAIL: SH expected 0008 in upper halfword");

        if (retire_trap)
            $display("FAIL: SH trapped");


        // Test 10: LH x5, 2(x0)
        // upper halfword = FF80, so signed LH should become FFFFFF80
        dmem_rdata = 32'hFF800000;
        imem_rdata = 32'h00201283;
        #10;

        $display("TEST 10 LH");
        $display("addr=%h ren=%b mask=%b rd=%0d wdata=%h trap=%b",
                 dmem_addr, dmem_ren, dmem_mask,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (dmem_ren != 1'b1)
            $display("FAIL: LH should assert read enable");

        if (dmem_mask != 4'b1100)
            $display("FAIL: LH expected mask 1100");

        if (retire_rd_waddr != 5'd5)
            $display("FAIL: LH expected rd=x5");

        if (retire_rd_wdata != 32'hFFFFFF80)
            $display("FAIL: LH expected sign-extended FF80");

        if (retire_trap)
            $display("FAIL: LH trapped");


        // Test 11: LHU x6, 2(x0)
        // same halfword FF80, but unsigned -> 0000FF80
        dmem_rdata = 32'hFF800000;
        imem_rdata = 32'h00205303;
        #10;

        $display("TEST 11 LHU");
        $display("addr=%h ren=%b mask=%b rd=%0d wdata=%h trap=%b",
                 dmem_addr, dmem_ren, dmem_mask,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (retire_rd_wdata != 32'h0000FF80)
            $display("FAIL: LHU expected zero-extended FF80");

        if (retire_trap)
            $display("FAIL: LHU trapped");

        // Test 12: JAL x7, +8
        // Should write PC+4 to x7 and jump ahead by 8
        imem_rdata = 32'h008003ef;
        #10;

        $display("TEST 12 JAL");
        $display("pc=%h next=%h rd=%0d wdata=%h trap=%b",
                 retire_pc, retire_next_pc,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (retire_rd_waddr != 5'd7)
            $display("FAIL: JAL expected rd=x7");

        if (retire_rd_wdata != retire_pc + 32'd4)
            $display("FAIL: JAL expected link=PC+4");

        if (retire_next_pc != retire_pc + 32'd8)
            $display("FAIL: JAL expected next_pc=PC+8");

        if (retire_trap)
            $display("FAIL: JAL trapped");


        // Test 13: JALR x8, 0(x1)
        @(negedge clk);
        imem_rdata = 32'h00008467;
        #1;
       
        $display("TEST 13 JALR");
        $display("pc=%h next=%h rs1=%0d rs1_data=%h rd=%0d wdata=%h trap=%b",
                 retire_pc, retire_next_pc,
                 retire_rs1_raddr, retire_rs1_rdata,
                 retire_rd_waddr, retire_rd_wdata,
                 retire_trap);

        if (retire_rs1_raddr != 5'd1)
            $display("FAIL: JALR expected rs1=x1");

        if (retire_rs1_rdata != 32'd5)
            $display("FAIL: JALR expected x1=5");

        if (retire_rd_waddr != 5'd8)
            $display("FAIL: JALR expected rd=x8");

        if (retire_rd_wdata != retire_pc + 32'd4)
            $display("FAIL: JALR expected link=PC+4");
	
	if (retire_next_pc != 32'd4)
	    $display("FAIL: JALR expected target 4");
   

        if (retire_trap)
            $display("FAIL: JALR trapped");

        // Test 14: Misaligned LH x9, 1(x0)
        // Halfword loads must be 2-byte aligned, so address 1 must trap.
        @(negedge clk);
        imem_rdata = 32'h00101483;
        #1;

        $display("TEST 14 MISALIGNED LH");
        $display("pc=%h next=%h trap=%b ren=%b wen=%b rd=%0d",
                 retire_pc, retire_next_pc, retire_trap,
                 dmem_ren, dmem_wen, retire_rd_waddr);

        if (retire_trap != 1'b1)
            $display("FAIL: misaligned LH should trap");

        if (dmem_ren != 1'b0)
            $display("FAIL: trapped LH must not access memory");

        if (dmem_wen != 1'b0)
            $display("FAIL: trapped LH must not write memory");

        if (retire_rd_waddr != 5'd0)
            $display("FAIL: trapped LH must not write a register");

        if (retire_next_pc != retire_pc + 32'd4)
            $display("FAIL: trapped LH should continue to PC+4");


        // Test 15: Illegal instruction
        @(negedge clk);
        imem_rdata = 32'hFFFFFFFF;
        #1;

        $display("TEST 15 ILLEGAL");
        $display("pc=%h next=%h trap=%b halt=%b ren=%b wen=%b rd=%0d",
                 retire_pc, retire_next_pc,
                 retire_trap, retire_halt,
                 dmem_ren, dmem_wen,
                 retire_rd_waddr);

        if (retire_trap != 1'b1)
            $display("FAIL: illegal instruction should trap");

        if (retire_halt != 1'b0)
            $display("FAIL: illegal instruction should not halt");

        if (dmem_ren != 1'b0 || dmem_wen != 1'b0)
            $display("FAIL: illegal instruction must not access memory");

        if (retire_rd_waddr != 5'd0)
            $display("FAIL: illegal instruction must not write a register");

        if (retire_next_pc != retire_pc + 32'd4)
            $display("FAIL: illegal instruction should continue to PC+4");


        // Test 16: EBREAK
        @(negedge clk);
        imem_rdata = 32'h00100073;
        #1;

        $display("TEST 16 EBREAK");
        $display("pc=%h next=%h trap=%b halt=%b rs1=%0d rs2=%0d rd=%0d ren=%b wen=%b",
                 retire_pc, retire_next_pc,
                 retire_trap, retire_halt,
                 retire_rs1_raddr, retire_rs2_raddr,
                 retire_rd_waddr,
                 dmem_ren, dmem_wen);

        if (retire_halt != 1'b1)
            $display("FAIL: EBREAK should assert halt");

        if (retire_trap != 1'b0)
            $display("FAIL: EBREAK should not trap");

        if (retire_rs1_raddr != 5'd0)
            $display("FAIL: EBREAK should not read rs1");

        if (retire_rs2_raddr != 5'd0)
            $display("FAIL: EBREAK should not read rs2");

        if (retire_rd_waddr != 5'd0)
            $display("FAIL: EBREAK should not write a register");

        if (dmem_ren != 1'b0 || dmem_wen != 1'b0)
            $display("FAIL: EBREAK should not access memory");

        if (retire_next_pc != retire_pc + 32'd4)
            $display("FAIL: EBREAK expected next_pc=PC+4");

        // Test 17: BLTU taken
        // x1 = 5, x2 = 8, so 5 < 8 unsigned => branch taken
        @(negedge clk);
        imem_rdata = 32'h0020e463;
        #1;

        $display("TEST 17 BLTU");
        $display("pc=%h next=%h trap=%b",
                 retire_pc, retire_next_pc, retire_trap);

        if (retire_next_pc != retire_pc + 32'd8)
            $display("FAIL: BLTU should branch by +8");

        if (retire_trap)
            $display("FAIL: BLTU trapped");


        // Test 18: LUI x9, 0x12345
        @(negedge clk);
        imem_rdata = 32'h123454b7;
        #1;

        $display("TEST 18 LUI");
        $display("rd=%0d wdata=%h trap=%b",
                 retire_rd_waddr, retire_rd_wdata, retire_trap);

        if (retire_rd_waddr != 5'd9)
            $display("FAIL: LUI expected rd=x9");

        if (retire_rd_wdata != 32'h12345000)
            $display("FAIL: LUI expected 12345000");

        if (retire_trap)
            $display("FAIL: LUI trapped");


        // Test 19: AUIPC x10, 0x1
        // Expected writeback = current PC + 0x1000
        @(negedge clk);
        imem_rdata = 32'h00001517;
        #1;

        $display("TEST 19 AUIPC");
        $display("pc=%h rd=%0d wdata=%h trap=%b",
                 retire_pc, retire_rd_waddr,
                 retire_rd_wdata, retire_trap);

        if (retire_rd_waddr != 5'd10)
            $display("FAIL: AUIPC expected rd=x10");

        if (retire_rd_wdata != retire_pc + 32'h00001000)
            $display("FAIL: AUIPC expected PC+0x1000");

        if (retire_trap)
            $display("FAIL: AUIPC trapped");


        // Test 20: ADDI x0, x0, 7
        // x0 must never actually be written
        @(negedge clk);
        imem_rdata = 32'h00700013;
        #1;

        $display("TEST 20 X0 WRITE DISCARD");
        $display("rd=%0d wdata=%h trap=%b",
                 retire_rd_waddr, retire_rd_wdata, retire_trap);

        if (retire_rd_waddr != 5'd0)
            $display("FAIL: write to x0 must report rd=0");

        if (retire_trap)
            $display("FAIL: ADDI x0 should not trap");


        // Test 21: Read x0 after attempted write
        // addi x11, x0, 1
        @(negedge clk);
        imem_rdata = 32'h00100593;
        #1;

        $display("TEST 21 X0 READ ZERO");
        $display("rs1=%0d rs1_data=%h rd=%0d wdata=%h",
                 retire_rs1_raddr, retire_rs1_rdata,
                 retire_rd_waddr, retire_rd_wdata);

        if (retire_rs1_rdata != 32'd0)
            $display("FAIL: x0 should still read as zero");

        if (retire_rd_wdata != 32'd1)
            $display("FAIL: expected x11=1");

        $display("DONE");
        $finish;
    end

endmodule

`default_nettype wire

