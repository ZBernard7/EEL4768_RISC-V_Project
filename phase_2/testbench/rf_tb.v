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

    // Main Simulation Execution
    initial begin
        // Initialize signals
        i_clk       = 0;
        i_rst       = 0;
        i_rs1_raddr = 0;
        i_rs2_raddr = 0;
        i_rd_wen    = 0;
        i_rd_waddr  = 0;
        i_rd_wdata  = 0;

        $display("========== Starting Register File Trace Vector Verification ==========");
        
        // Execute official trace files
        run_trace_file("traces/rf_no_bypass.trace", 0);
        run_trace_file("traces/rf_bypass.trace", 1);

        $display("\n========== Starting Full Section 6.1 Register File Specification Tests ==========");

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

        $display("\n==================================================");
        $display("SUMMARY: %0d Passed, %0d Failed", pass_count, fail_count);
        $display("==================================================");

        $finish;
    end

    // Task to load and execute trace files
    task run_trace_file(input [1024:0] trace_filename, input is_bypass);
        integer file, status;
        integer line_num;
        
        reg        tr_rst;
        reg [4:0]  tr_rs1_raddr;
        reg [4:0]  tr_rs2_raddr;
        reg        tr_rd_wen;
        reg [4:0]  tr_rd_waddr;
        reg [31:0] tr_rd_wdata;
        
        reg [31:0] exp_rs1_rdata;
        reg [31:0] exp_rs2_rdata;
        
        begin
            file = $fopen(trace_filename, "r");
            if (file == 0) begin
                $display("[ERROR] Could not open trace file: %s", trace_filename);
                $finish;
            end
            
            $display("--- Running Trace: %s ---", trace_filename);
            line_num = 0;
            
            // Loop using fscanf status directly to avoid $feof hanging on trailing newlines
            while ($fscanf(file, "%h %h %h %h %h %h %h %h", 
                           tr_rst, tr_rs1_raddr, tr_rs2_raddr, 
                           tr_rd_wen, tr_rd_waddr, tr_rd_wdata, 
                           exp_rs1_rdata, exp_rs2_rdata) == 8) begin
                           
                line_num = line_num + 1;
                
                @(negedge i_clk);
                i_rst       = tr_rst;
                i_rs1_raddr = tr_rs1_raddr;
                i_rs2_raddr = tr_rs2_raddr;
                i_rd_wen    = tr_rd_wen;
                i_rd_waddr  = tr_rd_waddr;
                i_rd_wdata  = tr_rd_wdata;
                
                #1;
                if (is_bypass) begin
                    if (o_rs1_rdata_bypass !== exp_rs1_rdata) begin
                        $display("[TRACE FAIL Line %0d] Bypass rs1 mismatch! Exp: 0x%h, Got: 0x%h", 
                                 line_num, exp_rs1_rdata, o_rs1_rdata_bypass);
                        fail_count = fail_count + 1;
                    end else pass_count = pass_count + 1;

                    if (o_rs2_rdata_bypass !== exp_rs2_rdata) begin
                        $display("[TRACE FAIL Line %0d] Bypass rs2 mismatch! Exp: 0x%h, Got: 0x%h", 
                                 line_num, exp_rs2_rdata, o_rs2_rdata_bypass);
                        fail_count = fail_count + 1;
                    end else pass_count = pass_count + 1;
                end else begin
                    if (o_rs1_rdata_nobypass !== exp_rs1_rdata) begin
                        $display("[TRACE FAIL Line %0d] NoBypass rs1 mismatch! Exp: 0x%h, Got: 0x%h", 
                                 line_num, exp_rs1_rdata, o_rs1_rdata_nobypass);
                        fail_count = fail_count + 1;
                    end else pass_count = pass_count + 1;

                    if (o_rs2_rdata_nobypass !== exp_rs2_rdata) begin
                        $display("[TRACE FAIL Line %0d] NoBypass rs2 mismatch! Exp: 0x%h, Got: 0x%h", 
                                 line_num, exp_rs2_rdata, o_rs2_rdata_nobypass);
                        fail_count = fail_count + 1;
                    end else pass_count = pass_count + 1;
                end
            end
            
            $fclose(file);
            $display("--- Finished Trace: %s ---", trace_filename);
        end
    endtask

endmodule
`default_nettype wire