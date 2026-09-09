`timescale 1ns / 1ps
`default_nettype none

module rf_tb;

    // Testbench Clock and Interface Signals
    reg        i_clk;
    reg        i_rst;
    reg  [4:0] i_rs1_raddr;
    wire [31:0] o_rs1_rdata_nobypass;
    wire [31:0] o_rs1_rdata_bypass;
    reg  [4:0] i_rs2_raddr;
    wire [31:0] o_rs2_rdata_nobypass;
    wire [31:0] o_rs2_rdata_bypass;
    reg        i_rd_wen;
    reg  [4:0] i_rd_waddr;
    reg  [31:0] i_rd_wdata;

    integer pass_count = 0;
    integer fail_count = 0;

    // Instantiate Register File WITHOUT Bypass (BYPASS_EN = 0)
    rf #(
        .BYPASS_EN(0)
    ) uut_no_bypass (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rs1_raddr(i_rs1_raddr),
        .o_rs1_rdata(o_rs1_rdata_nobypass),
        .i_rs2_raddr(i_rs2_raddr),
        .o_rs2_rdata(o_rs2_rdata_nobypass),
        .i_rd_wen(i_rd_wen),
        .i_rd_waddr(i_rd_waddr),
        .i_rd_wdata(i_rd_wdata)
    );

    // Instantiate Register File WITH Bypass (BYPASS_EN = 1)
    rf #(
        .BYPASS_EN(1)
    ) uut_bypass (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rs1_raddr(i_rs1_raddr),
        .o_rs1_rdata(o_rs1_rdata_bypass),
        .i_rs2_raddr(i_rs2_raddr),
        .o_rs2_rdata(o_rs2_rdata_bypass),
        .i_rd_wen(i_rd_wen),
        .i_rd_waddr(i_rd_waddr),
        .i_rd_wdata(i_rd_wdata)
    );

    // Clock Generation: 10ns period (50MHz)
    always #5 i_clk = ~i_clk;

    // Helper task to check test assertions
    task check_val(input [256:1] name, input [31:0] actual, input [31:0] expected);
        begin
            if (actual === expected) begin
                $display("[PASS] %s | Got: 0x%h", name, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %s | Expected: 0x%h, Got: 0x%h", name, expected, actual);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        // Initialize Signals
        i_clk       = 0;
        i_rst       = 0;
        i_rs1_raddr = 0;
        i_rs2_raddr = 0;
        i_rd_wen    = 0;
        i_rd_waddr  = 0;
        i_rd_wdata  = 0;

        $display("========== Starting Full Section 6.1 Register File Tests ==========");

        // -------------------------------------------------------------
        // Step 0: Global Synchronous Reset
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rst = 1;
        @(posedge i_clk);
        #1;
        i_rst = 0;

        // -------------------------------------------------------------
        // Requirement 1: Write to x0 (should retain 0)
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wen   = 1;
        i_rd_waddr = 5'd0;
        i_rd_wdata = 32'hDEADBEEF;
        @(posedge i_clk);
        #1;
        i_rd_wen   = 0;
        i_rs1_raddr = 5'd0;
        i_rs2_raddr = 5'd0;
        #1;
        check_val("Spec Check: x0 retains 0 after 0xDEADBEEF write (Port 1)", o_rs1_rdata_nobypass, 32'h0);
        check_val("Spec Check: x0 retains 0 after 0xDEADBEEF write (Port 2)", o_rs2_rdata_nobypass, 32'h0);

        // -------------------------------------------------------------
        // Requirement 2: Reset Verification
        // -------------------------------------------------------------
        // Write x1
        @(negedge i_clk);
        i_rd_wen   = 1;
        i_rd_waddr = 5'd1;
        i_rd_wdata = 32'h11111111;
        @(posedge i_clk);

        // Write x2
        @(negedge i_clk);
        i_rd_waddr = 5'd2;
        i_rd_wdata = 32'h22222222;
        @(posedge i_clk);

        // De-assert write enable and assert Reset
        @(negedge i_clk);
        i_rd_wen = 0;
        i_rst    = 1;
        @(posedge i_clk);
        #1;
        i_rst    = 0;

        i_rs1_raddr = 5'd1;
        i_rs2_raddr = 5'd2;
        #1;
        check_val("Reset Check: x1 cleared to 0", o_rs1_rdata_nobypass, 32'h0);
        check_val("Reset Check: x2 cleared to 0", o_rs2_rdata_nobypass, 32'h0);

        // -------------------------------------------------------------
        // Requirement 3: Synchronous Writes
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wen   = 1;
        i_rd_waddr = 5'd5;
        i_rd_wdata = 32'hA5A5A5A5;
        i_rs1_raddr = 5'd5;
        #1;
        check_val("Sync Write: Value NOT visible before rising edge (No Bypass)", o_rs1_rdata_nobypass, 32'h0);
        
        @(posedge i_clk); // Write commits
        #1;
        check_val("Sync Write: Value committed on rising edge", o_rs1_rdata_nobypass, 32'hA5A5A5A5);

        @(negedge i_clk);
        i_rd_wen = 0;

        // -------------------------------------------------------------
        // Requirement 4: Combinational Independent Reads
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wen   = 1;
        i_rd_waddr = 5'd10;
        i_rd_wdata = 32'h5555AAAA;
        @(posedge i_clk);
        #1;
        i_rd_wen   = 0;

        #2; i_rs1_raddr = 5'd5;  i_rs2_raddr = 5'd10; #1;
        check_val("Combinational Read: Port 1 reads x5",  o_rs1_rdata_nobypass, 32'hA5A5A5A5);
        check_val("Combinational Read: Port 2 reads x10", o_rs2_rdata_nobypass, 32'h5555AAAA);

        #2; i_rs1_raddr = 5'd10; i_rs2_raddr = 5'd5;  #1;
        check_val("Combinational Read Swap: Port 1 reads x10", o_rs1_rdata_nobypass, 32'h5555AAAA);
        check_val("Combinational Read Swap: Port 2 reads x5",  o_rs2_rdata_nobypass, 32'hA5A5A5A5);

        // -------------------------------------------------------------
        // Requirement 5: Dual-Port Bypass Behavior
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wen    = 1;
        i_rd_waddr  = 5'd15;
        i_rd_wdata  = 32'h87654321;
        i_rs1_raddr = 5'd15;
        i_rs2_raddr = 5'd15;
        #1;
        check_val("Bypass: Port 1 No-Bypass holds stored value 0", o_rs1_rdata_nobypass, 32'h0);
        check_val("Bypass: Port 2 No-Bypass holds stored value 0", o_rs2_rdata_nobypass, 32'h0);
        
        check_val("Bypass: Port 1 Bypass forwards immediately", o_rs1_rdata_bypass, 32'h87654321);
        check_val("Bypass: Port 2 Bypass forwards immediately", o_rs2_rdata_bypass, 32'h87654321);

        @(posedge i_clk);
        #1;
        i_rd_wen = 0;

        // -------------------------------------------------------------
        // Requirement 6: Bypass Exception for x0
        // -------------------------------------------------------------
        @(negedge i_clk);
        i_rd_wen    = 1;
        i_rd_waddr  = 5'd0;
        i_rd_wdata  = 32'hCAFEFEED;
        i_rs1_raddr = 5'd0;
        i_rs2_raddr = 5'd0;
        #1;
        check_val("Bypass x0 Exception: Port 1 stays 0 during x0 write", o_rs1_rdata_bypass, 32'h0);
        check_val("Bypass x0 Exception: Port 2 stays 0 during x0 write", o_rs2_rdata_bypass, 32'h0);

        $display("==================================================");
        $display("SUMMARY: %0d Passed, %0d Failed", pass_count, fail_count);
        $display("==================================================");

        $finish;
    end

endmodule
`default_nettype wire