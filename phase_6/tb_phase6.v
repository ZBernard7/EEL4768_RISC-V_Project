`timescale 1ns/1ps
`default_nettype none

// Phase 6 self-checking testbench (simulation only, never submitted).
//
// Checks performed:
//   1. Final data memory vs traces/random_dmem.hex (labelled by test section).
//   2. Every retired instruction, independently of the hex files:
//        - PC chain and next_pc rules, traps have no side effects
//        - integer AND floating-point source values vs a shadow register file
//          (catches missing hazards / forwarding bugs in both register files)
//        - destination register file/number (x vs f), flw/fsw data
//        - RV32M results vs a reference (incl. divide-by-zero and overflow)
//        - sign injection, fmv, fclass, feq/flt/fle results and flags
//        - fflags accrue, CSR old values, CSR write rules, frm modelling
//        - reserved / dynamic rounding-mode traps
//   3. A stuck detector that prints the stall signals if nothing retires.
//
// Run from the folder containing traces/ and implementation/:
//   iverilog -g2012 -o tb_phase6_sim implementation/*.v tb_phase6_full.v
//   vvp tb_phase6_sim
module tb_phase6;

    // ---------------- Configuration ----------------
    localparam EVICT_POLICY = 1;      // 1 = PLRU in your cache.v
    localparam NUM_WAYS     = 4;
    localparam CACHE_SIZE   = 2;      // KILOBYTES in your cache.v
    localparam BLOCK_SIZE   = 16;
    localparam PREFETCH_EN  = 1;
    localparam MEM_DELAY    = 4;

    localparam TRACE_FIRST  = 0;      // print first N retires
    localparam HEARTBEAT    = 50000;
    localparam MAX_CYCLES   = 5000000;
    localparam STUCK_LIMIT  = 2000;   // cycles with no retire
    localparam MAX_PRINT    = 40;     // max check failures printed

    localparam IMEM_BASE = 32'h00400000;
    localparam DMEM_BASE = 32'h10010000;

    // ---------------- Clock / reset ----------------
    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;
    initial #25 rst = 0;

    // ---------------- Memories ----------------
    reg [31:0] imem     [0:65535];
    reg [31:0] dmem     [0:32767];
    reg [31:0] expected [0:32767];

    integer init_i;
    initial begin
        for (init_i = 0; init_i < 65536; init_i = init_i + 1) imem[init_i] = 32'h0;
        for (init_i = 0; init_i < 32768; init_i = init_i + 1) begin
            dmem[init_i]     = 32'h0;
            expected[init_i] = 32'h0;
        end
        $readmemh("traces/random_program.hex", imem);
        $readmemh("traces/random_dmem.hex",    expected);
        if (imem[0] === 32'h0) begin
            $display("[FATAL] traces/random_program.hex was not loaded");
            $finish;
        end
        $display("[INFO] ways=%0d size=%0dKB block=%0d prefetch=%0d policy=%0d mem_delay=%0d",
                 NUM_WAYS, CACHE_SIZE, BLOCK_SIZE, PREFETCH_EN, EVICT_POLICY, MEM_DELAY);
    end

    // ---------------- DUT ----------------
    wire         o_imem_rd;
    wire [31:0]  o_imem_rd_addr;
    reg          i_imem_valid = 0;
    reg  [127:0] i_imem_rd_data = 0;
    wire         o_dmem_rd;
    wire [31:0]  o_dmem_rd_addr;
    reg          i_dmem_valid = 0;
    reg  [127:0] i_dmem_rd_data = 0;
    wire         o_dmem_wr;
    wire [31:0]  o_dmem_wr_addr;
    wire [127:0] o_dmem_wr_data;
    wire [15:0]  o_dmem_wr_be;

    wire        o_retire_valid, o_retire_trap, o_retire_halt;
    wire [31:0] o_retire_inst, o_retire_pc, o_retire_next_pc;
    wire [4:0]  o_retire_rs1_raddr, o_retire_rs2_raddr, o_retire_rd_waddr;
    wire [31:0] o_retire_rs1_rdata, o_retire_rs2_rdata, o_retire_rd_wdata;
    wire [31:0] o_retire_dmem_addr, o_retire_dmem_wdata, o_retire_dmem_rdata;
    wire [3:0]  o_retire_dmem_mask;
    wire        o_retire_dmem_ren, o_retire_dmem_wen;
    wire [4:0]  o_retire_frs1_raddr, o_retire_frs2_raddr, o_retire_frs3_raddr, o_retire_frd_waddr;
    wire [31:0] o_retire_frs1_rdata, o_retire_frs2_rdata, o_retire_frs3_rdata, o_retire_frd_wdata;
    wire        o_retire_frd_wen;
    wire [4:0]  o_retire_fflags;

    hart #(
        .RESET_ADDR  (IMEM_BASE), .FWD_EN(1), .BYPASS_EN(1),
        .EVICT_POLICY(EVICT_POLICY), .NUM_WAYS(NUM_WAYS),
        .CACHE_SIZE  (CACHE_SIZE),   .BLOCK_SIZE(BLOCK_SIZE),
        .PREFETCH_EN (PREFETCH_EN)
    ) u_hart (
        .i_clk(clk), .i_rst(rst),
        .o_imem_rd(o_imem_rd), .o_imem_rd_addr(o_imem_rd_addr),
        .i_imem_valid(i_imem_valid), .i_imem_rd_data(i_imem_rd_data),
        .o_dmem_rd(o_dmem_rd), .o_dmem_rd_addr(o_dmem_rd_addr),
        .i_dmem_valid(i_dmem_valid), .i_dmem_rd_data(i_dmem_rd_data),
        .o_dmem_wr(o_dmem_wr), .o_dmem_wr_addr(o_dmem_wr_addr),
        .o_dmem_wr_data(o_dmem_wr_data), .o_dmem_wr_be(o_dmem_wr_be),
        .o_retire_valid(o_retire_valid), .o_retire_inst(o_retire_inst),
        .o_retire_trap(o_retire_trap), .o_retire_halt(o_retire_halt),
        .o_retire_rs1_raddr(o_retire_rs1_raddr), .o_retire_rs1_rdata(o_retire_rs1_rdata),
        .o_retire_rs2_raddr(o_retire_rs2_raddr), .o_retire_rs2_rdata(o_retire_rs2_rdata),
        .o_retire_rd_waddr(o_retire_rd_waddr), .o_retire_rd_wdata(o_retire_rd_wdata),
        .o_retire_dmem_addr(o_retire_dmem_addr), .o_retire_dmem_mask(o_retire_dmem_mask),
        .o_retire_dmem_ren(o_retire_dmem_ren), .o_retire_dmem_wen(o_retire_dmem_wen),
        .o_retire_dmem_rdata(o_retire_dmem_rdata), .o_retire_dmem_wdata(o_retire_dmem_wdata),
        .o_retire_pc(o_retire_pc), .o_retire_next_pc(o_retire_next_pc),
        .o_retire_frs1_raddr(o_retire_frs1_raddr), .o_retire_frs1_rdata(o_retire_frs1_rdata),
        .o_retire_frs2_raddr(o_retire_frs2_raddr), .o_retire_frs2_rdata(o_retire_frs2_rdata),
        .o_retire_frs3_raddr(o_retire_frs3_raddr), .o_retire_frs3_rdata(o_retire_frs3_rdata),
        .o_retire_frd_wen(o_retire_frd_wen), .o_retire_frd_waddr(o_retire_frd_waddr),
        .o_retire_frd_wdata(o_retire_frd_wdata), .o_retire_fflags(o_retire_fflags)
    );

    // ---------------- Main memory model ----------------
    wire [31:0] imem_req_idx = (o_imem_rd_addr - IMEM_BASE) >> 2;
    wire [31:0] dmem_req_idx = (o_dmem_rd_addr - DMEM_BASE) >> 2;
    wire [31:0] dmem_wr_idx  = (o_dmem_wr_addr - DMEM_BASE) >> 2;

    reg [MEM_DELAY-1:0] i_v_pipe = 0;
    reg [MEM_DELAY-1:0] d_v_pipe = 0;
    reg [31:0]          i_a_pipe [0:MEM_DELAY-1];
    reg [31:0]          d_a_pipe [0:MEM_DELAY-1];

    integer s, w, b;
    reg [31:0] ia, da;

    always @(posedge clk) begin
        i_v_pipe <= {i_v_pipe[MEM_DELAY-2:0], (o_imem_rd && !rst)};
        d_v_pipe <= {d_v_pipe[MEM_DELAY-2:0], (o_dmem_rd && !rst)};
        i_a_pipe[0] <= imem_req_idx;
        d_a_pipe[0] <= dmem_req_idx;
        for (s = 1; s < MEM_DELAY; s = s + 1) begin
            i_a_pipe[s] <= i_a_pipe[s-1];
            d_a_pipe[s] <= d_a_pipe[s-1];
        end

        i_imem_valid <= i_v_pipe[MEM_DELAY-1];
        i_dmem_valid <= d_v_pipe[MEM_DELAY-1];
        ia = i_a_pipe[MEM_DELAY-1];
        da = d_a_pipe[MEM_DELAY-1];
        if (i_v_pipe[MEM_DELAY-1]) begin
            if (ia < 32'd65532) i_imem_rd_data <= {imem[ia+3], imem[ia+2], imem[ia+1], imem[ia]};
            else                i_imem_rd_data <= 128'd0;
        end
        if (d_v_pipe[MEM_DELAY-1]) begin
            if (da < 32'd32765) i_dmem_rd_data <= {dmem[da+3], dmem[da+2], dmem[da+1], dmem[da]};
            else                i_dmem_rd_data <= 128'd0;
        end

        if (o_dmem_wr && !rst && dmem_wr_idx < 32'd32765) begin
            for (w = 0; w < 4; w = w + 1)
                for (b = 0; b < 4; b = b + 1)
                    if (o_dmem_wr_be[w*4+b])
                        dmem[dmem_wr_idx + w][b*8 +: 8] <= o_dmem_wr_data[w*32 + b*8 +: 8];
        end
    end

    // ---------------- Reference functions ----------------
    function [31:0] m_ref;
        input [2:0]  f3;
        input [31:0] a;
        input [31:0] bb;
        reg signed [63:0] sa, sb, ub, sp;
        reg        [63:0] up;
        begin
            sa = {{32{a[31]}},  a};
            sb = {{32{bb[31]}}, bb};
            ub = {32'd0, bb};
            case (f3)
                3'b000: begin sp = sa * sb; m_ref = sp[31:0]; end
                3'b001: begin sp = sa * sb; m_ref = sp[63:32]; end
                3'b010: begin sp = sa * ub; m_ref = sp[63:32]; end
                3'b011: begin up = {32'd0,a} * {32'd0,bb}; m_ref = up[63:32]; end
                3'b100: begin
                    if (bb == 32'd0) m_ref = 32'hFFFFFFFF;
                    else if (a == 32'h80000000 && bb == 32'hFFFFFFFF) m_ref = 32'h80000000;
                    else begin sp = sa / sb; m_ref = sp[31:0]; end
                end
                3'b101: m_ref = (bb == 32'd0) ? 32'hFFFFFFFF : (a / bb);
                3'b110: begin
                    if (bb == 32'd0) m_ref = a;
                    else if (a == 32'h80000000 && bb == 32'hFFFFFFFF) m_ref = 32'd0;
                    else begin sp = sa % sb; m_ref = sp[31:0]; end
                end
                default: m_ref = (bb == 32'd0) ? a : (a % bb);
            endcase
        end
    endfunction

    function is_nan; input [31:0] x; is_nan = (x[30:23] == 8'hFF) && (x[22:0] != 23'd0); endfunction
    function is_snan; input [31:0] x; is_snan = is_nan(x) && !x[22]; endfunction
    function is_zero; input [31:0] x; is_zero = (x[30:0] == 31'd0); endfunction

    // a < b for non-NaN operands
    function f_lt;
        input [31:0] a;
        input [31:0] bb;
        begin
            if (is_zero(a) && is_zero(bb)) f_lt = 1'b0;
            else if (a[31] != bb[31])      f_lt = a[31];
            else if (a[31])                f_lt = (a[30:0] > bb[30:0]);
            else                           f_lt = (a[30:0] < bb[30:0]);
        end
    endfunction

    function [9:0] fclass_ref;
        input [31:0] x;
        begin
            if (x[30:23] == 8'hFF) begin
                if (x[22:0] == 23'd0) fclass_ref = x[31] ? 10'h001 : 10'h080;
                else                  fclass_ref = x[22] ? 10'h200 : 10'h100;
            end else if (x[30:23] == 8'd0) begin
                if (x[22:0] == 23'd0) fclass_ref = x[31] ? 10'h008 : 10'h010;
                else                  fclass_ref = x[31] ? 10'h004 : 10'h020;
            end else                  fclass_ref = x[31] ? 10'h002 : 10'h040;
        end
    endfunction

    function [127:0] section_name;
        input [31:0] a;
        begin
            if      (a <  32'h10018000) section_name = "program data    ";
            else if (a <  32'h10020000) section_name = "flush area      ";
            else if (a <  32'h10021800) section_name = "muldiv          ";
            else if (a <  32'h10023000) section_name = "fp_move_compare ";
            else if (a <  32'h10024800) section_name = "fp_convert      ";
            else if (a <  32'h10026000) section_name = "fp_add_mul/fused";
            else if (a <  32'h10027800) section_name = "fp_div_sqrt     ";
            else if (a <  32'h10029000) section_name = "fp_csr          ";
            else if (a <  32'h1002A800) section_name = "mixed           ";
            else                        section_name = "cache_stall     ";
        end
    endfunction

    // ---------------- Counters / heartbeat ----------------
    integer total_cycles = 0;
    integer total_instructions = 0;
    integer m_ext_count = 0, f_ext_count = 0, trap_count = 0, trace_count = 0;

    always @(posedge clk) if (!rst) total_cycles <= total_cycles + 1;

    always @(posedge clk)
        if (!rst && total_cycles != 0 && (total_cycles % HEARTBEAT) == 0)
            $display("[HB] cycle %0d  retired %0d  last pc 0x%h", total_cycles, total_instructions, o_retire_pc);

    // ---------------- Retire-time checker ----------------
    reg [31:0] sx [0:31];
    reg [31:0] sf [0:31];
    reg [2:0]  sfrm;
    reg [4:0]  prev_fflags;
    reg [31:0] prev_next_pc;
    reg        have_prev, prev_halt;
    integer    chk_errors, ci;

    initial begin
        for (ci = 0; ci < 32; ci = ci + 1) begin sx[ci] = 32'd0; sf[ci] = 32'd0; end
        sfrm = 3'd0; prev_fflags = 5'd0; prev_next_pc = 32'd0;
        have_prev = 1'b0; prev_halt = 1'b0; chk_errors = 0;
    end

    task report;
        input [255:0] msg;
        begin
            chk_errors = chk_errors + 1;
            if (chk_errors <= MAX_PRINT)
                $display("[CHECK FAIL] cyc=%0d pc=0x%h inst=0x%h : %0s",
                         total_cycles, o_retire_pc, o_retire_inst, msg);
        end
    endtask

    reg [31:0] inst, cold, cnew, csrsrc, exp_val, fa, fb;
    reg [6:0]  op, f7;
    reg [2:0]  f3, new_frm;
    reg [4:0]  exp_flags, new_fflags, uimm;
    reg [11:0] caddr;
    reg        trp, is_fused, is_flw, is_fsw, is_opfp, fp_dest, fr1_read, fr2_read, fr3_read;
    reg        is_ctrl, rnd_instr, flags_known, cwr, na, nb, nany, nsig, eq, res1;

    always @(posedge clk) begin
        if (!rst && o_retire_valid) begin
            inst = o_retire_inst;
            op   = inst[6:0];
            f7   = inst[31:25];
            f3   = inst[14:12];
            trp  = o_retire_trap;
            exp_flags   = 5'd0;
            flags_known = 1'b0;

            is_fused = (op == 7'h43) || (op == 7'h47) || (op == 7'h4B) || (op == 7'h4F);
            is_flw   = (op == 7'h07) && (f3 == 3'b010);
            is_fsw   = (op == 7'h27) && (f3 == 3'b010);
            is_opfp  = (op == 7'h53);
            fp_dest  = is_flw || is_fused ||
                       (is_opfp && !(f7 == 7'h50 || f7 == 7'h60 || f7 == 7'h70));
            fr1_read = is_fused || (is_opfp && f7 != 7'h68 && f7 != 7'h78);
            fr2_read = is_fused || is_fsw ||
                       (is_opfp && (f7 == 7'h00 || f7 == 7'h04 || f7 == 7'h08 || f7 == 7'h0C ||
                                    f7 == 7'h10 || f7 == 7'h14 || f7 == 7'h50));
            fr3_read = is_fused;
            is_ctrl  = (op == 7'h63) || (op == 7'h6F) || (op == 7'h67);
            rnd_instr = is_fused ||
                        (is_opfp && (f7 == 7'h00 || f7 == 7'h04 || f7 == 7'h08 || f7 == 7'h0C ||
                                     f7 == 7'h2C || f7 == 7'h60 || f7 == 7'h68));

            // ---- control flow ----
            if (have_prev && !prev_halt && o_retire_pc !== prev_next_pc)
                report("pc != previous next_pc");
            if ((trp || !is_ctrl) && o_retire_next_pc !== o_retire_pc + 32'd4)
                report("next_pc != pc+4");
            if (o_retire_dmem_ren && o_retire_dmem_wen)
                report("dmem ren and wen both high");

            if (trp) begin
                // ---- trapped instruction: no side effects ----
                if (o_retire_rd_waddr !== 5'd0) report("trap wrote integer rd");
                if (o_retire_frd_wen !== 1'b0)  report("trap wrote FP rd");
                if (o_retire_dmem_ren || o_retire_dmem_wen) report("trap reported a memory access");
                if (o_retire_fflags !== prev_fflags) report("trap changed fflags");
            end else begin
                // ---- integer sources ----
                if (o_retire_rs1_raddr == 5'd0) begin
                    if (o_retire_rs1_rdata !== 32'd0) report("rs1 is x0 but data != 0");
                end else if (o_retire_rs1_rdata !== sx[o_retire_rs1_raddr])
                    report("rs1 data != architectural value");
                if (o_retire_rs2_raddr == 5'd0) begin
                    if (o_retire_rs2_rdata !== 32'd0) report("rs2 is x0 but data != 0");
                end else if (o_retire_rs2_rdata !== sx[o_retire_rs2_raddr])
                    report("rs2 data != architectural value");

                // ---- FP sources ----
                if (fr1_read) begin
                    if (o_retire_frs1_raddr !== inst[19:15]) report("frs1 address wrong");
                    else if (o_retire_frs1_rdata !== sf[inst[19:15]]) report("frs1 data != architectural value");
                end
                if (fr2_read) begin
                    if (o_retire_frs2_raddr !== inst[24:20]) report("frs2 address wrong");
                    else if (o_retire_frs2_rdata !== sf[inst[24:20]]) report("frs2 data != architectural value");
                end
                if (fr3_read) begin
                    if (o_retire_frs3_raddr !== inst[31:27]) report("frs3 address wrong");
                    else if (o_retire_frs3_rdata !== sf[inst[31:27]]) report("frs3 data != architectural value");
                end

                // ---- destinations ----
                if (o_retire_frd_wen !== fp_dest) report("frd_wen wrong for this instruction");
                else if (fp_dest && o_retire_frd_waddr !== inst[11:7]) report("frd address wrong");
                if (fp_dest && o_retire_rd_waddr !== 5'd0) report("FP-destination instr wrote integer rd");
                if (is_flw && (o_retire_dmem_ren !== 1'b1 || o_retire_frd_wdata !== o_retire_dmem_rdata))
                    report("flw result != loaded word");
                if (is_fsw && (o_retire_dmem_wen !== 1'b1 || o_retire_dmem_wdata !== o_retire_frs2_rdata))
                    report("fsw store data != FP rs2");

                // ---- RV32M reference ----
                if (op == 7'h33 && f7 == 7'h01 && o_retire_rd_waddr != 5'd0) begin
                    exp_val = m_ref(f3, o_retire_rs1_rdata, o_retire_rs2_rdata);
                    if (o_retire_rd_wdata !== exp_val) begin
                        report("RV32M result wrong");
                        if (chk_errors <= MAX_PRINT)
                            $display("      f3=%0d a=%h b=%h got=%h expected=%h", f3,
                                     o_retire_rs1_rdata, o_retire_rs2_rdata, o_retire_rd_wdata, exp_val);
                    end
                end

                // ---- simple FP references ----
                if (is_opfp) begin
                    fa = o_retire_frs1_rdata;
                    fb = o_retire_frs2_rdata;
                    na = is_nan(fa); nb = is_nan(fb);
                    nany = na | nb; nsig = is_snan(fa) | is_snan(fb);
                    eq = !nany && ((fa == fb) || (is_zero(fa) && is_zero(fb)));
                    if (f7 == 7'h10) begin
                        flags_known = 1'b1;
                        exp_val = {(f3 == 3'b000) ? fb[31] : (f3 == 3'b001) ? ~fb[31] : (fa[31] ^ fb[31]),
                                   fa[30:0]};
                        if (o_retire_frd_wdata !== exp_val) report("fsgnj result wrong");
                    end else if (f7 == 7'h70 && f3 == 3'b000) begin
                        flags_known = 1'b1;
                        if (o_retire_rd_waddr != 5'd0 && o_retire_rd_wdata !== fa) report("fmv.x.w result wrong");
                    end else if (f7 == 7'h70 && f3 == 3'b001) begin
                        flags_known = 1'b1;
                        if (o_retire_rd_waddr != 5'd0 && o_retire_rd_wdata !== {22'd0, fclass_ref(fa)})
                            report("fclass result wrong");
                    end else if (f7 == 7'h78) begin
                        flags_known = 1'b1;
                        if (o_retire_frd_wdata !== o_retire_rs1_rdata) report("fmv.w.x result wrong");
                    end else if (f7 == 7'h50) begin
                        flags_known = 1'b1;
                        case (f3)
                            3'b000: begin res1 = !nany && (f_lt(fa, fb) || eq); exp_flags[4] = nany; end
                            3'b001: begin res1 = !nany && f_lt(fa, fb);         exp_flags[4] = nany; end
                            default: begin res1 = eq;                           exp_flags[4] = nsig; end
                        endcase
                        if (o_retire_rd_waddr != 5'd0 && o_retire_rd_wdata !== {31'd0, res1})
                            report("compare result wrong");
                    end
                end

                // ---- rounding-mode traps that did not happen ----
                if (rnd_instr && (f3 == 3'd5 || f3 == 3'd6 || (f3 == 3'd7 && sfrm > 3'd4)))
                    report("reserved rounding mode did not trap");

                // ---- CSR instructions ----
                if (op == 7'h73 && f3 != 3'b000 && f3 != 3'b100) begin
                    caddr  = inst[31:20];
                    uimm   = inst[19:15];
                    csrsrc = f3[2] ? {27'd0, uimm} : o_retire_rs1_rdata;
                    if (caddr != 12'h001 && caddr != 12'h002 && caddr != 12'h003)
                        report("illegal CSR address did not trap");
                    case (caddr)
                        12'h001: cold = {27'd0, prev_fflags};
                        12'h002: cold = {29'd0, sfrm};
                        12'h003: cold = {24'd0, sfrm, prev_fflags};
                        default: cold = 32'd0;
                    endcase
                    if (o_retire_rd_waddr != 5'd0 && o_retire_rd_wdata !== cold)
                        report("CSR old value wrong");
                    cwr = (f3[1:0] == 2'b01) || (uimm != 5'd0);
                    case (f3[1:0])
                        2'b01:   cnew = csrsrc;
                        2'b10:   cnew = cold | csrsrc;
                        default: cnew = cold & ~csrsrc;
                    endcase
                    new_fflags = prev_fflags;
                    new_frm    = sfrm;
                    if (cwr) begin
                        case (caddr)
                            12'h001: new_fflags = cnew[4:0];
                            12'h002: new_frm = cnew[2:0];
                            12'h003: begin new_frm = cnew[7:5]; new_fflags = cnew[4:0]; end
                            default: ;
                        endcase
                    end
                    if (o_retire_fflags !== new_fflags) report("fflags after CSR instruction wrong");
                    sfrm = new_frm;
                end else begin
                    // non-CSR: flags only accrue
                    if ((prev_fflags & ~o_retire_fflags) != 5'd0) report("fflags cleared by a non-CSR instruction");
                    if (flags_known && o_retire_fflags !== (prev_fflags | exp_flags)) report("fflags wrong");
                end

                // ---- shadow register update ----
                if (o_retire_rd_waddr != 5'd0) sx[o_retire_rd_waddr] = o_retire_rd_wdata;
                if (o_retire_frd_wen)          sf[o_retire_frd_waddr] = o_retire_frd_wdata;
            end

            prev_fflags  = o_retire_fflags;
            prev_next_pc = o_retire_next_pc;
            have_prev    = 1'b1;
            prev_halt    = o_retire_halt;
        end
    end

    // ---------------- Statistics, trace, and finish ----------------
    integer k, errors;

    always @(posedge clk) begin
        if (!rst && o_retire_valid) begin
            total_instructions <= total_instructions + 1;
            if (o_retire_trap) trap_count <= trap_count + 1;
            if (o_retire_inst[6:0] == 7'b0110011 && o_retire_inst[31:25] == 7'b0000001)
                m_ext_count <= m_ext_count + 1;
            if (o_retire_inst[6:0] == 7'b0000111 || o_retire_inst[6:0] == 7'b0100111 ||
                o_retire_inst[6:0] == 7'b1010011 || o_retire_inst[6:0] == 7'b1000011 ||
                o_retire_inst[6:0] == 7'b1000111 || o_retire_inst[6:0] == 7'b1001011 ||
                o_retire_inst[6:0] == 7'b1001111)
                f_ext_count <= f_ext_count + 1;

            if (trace_count < TRACE_FIRST) begin
                trace_count <= trace_count + 1;
                $display("[RET] cyc=%0d pc=0x%h inst=0x%h trap=%b rd=x%0d<=%h frd=%b f%0d<=%h fflags=%b",
                         total_cycles, o_retire_pc, o_retire_inst, o_retire_trap,
                         o_retire_rd_waddr, o_retire_rd_wdata,
                         o_retire_frd_wen, o_retire_frd_waddr, o_retire_frd_wdata, o_retire_fflags);
            end

            if (o_retire_halt) begin
                errors = 0;
                for (k = 0; k < 32768; k = k + 1) begin
                    if (dmem[k] !== expected[k]) begin
                        if (errors < 20)
                            $display("MISMATCH [%0s] addr 0x%h: got %h expected %h",
                                     section_name(32'h10010000 + (k << 2)),
                                     32'h10010000 + (k << 2), dmem[k], expected[k]);
                        errors = errors + 1;
                    end
                end
                $display("");
                $display("==================================================");
                $display("             PHASE 6 TESTBENCH COMPLETE");
                $display("==================================================");
                $display("  Cycles                : %0d", total_cycles);
                $display("  Retired               : %0d", total_instructions + 1);
                $display("  RV32M / RV32F         : %0d / %0d", m_ext_count, f_ext_count);
                $display("  Traps                 : %0d", trap_count);
                $display("  Final fflags          : 5'b%b", o_retire_fflags);
                $display("  Retire-check failures : %0d  %0s", chk_errors, (chk_errors == 0) ? "(PASS)" : "(FAIL)");
                $display("  Memory mismatches     : %0d  %0s", errors, (errors == 0) ? "(PASS)" : "(FAIL)");
                $display("  OVERALL               : %0s", (chk_errors == 0 && errors == 0) ? "PASS" : "FAIL");
                $display("==================================================");
                $finish;
            end
        end
    end

    // ---------------- Stuck detector and watchdog ----------------
    integer idle = 0;
    always @(posedge clk) begin
        if (!rst) begin
            idle <= o_retire_valid ? 0 : idle + 1;
            if (idle == STUCK_LIMIT) begin
                $display("[STUCK] no retire for %0d cycles at cycle %0d", STUCK_LIMIT, total_cycles);
                $display("  pc_reg=%h pipe_stall=%b ex_stall=%b alu_busy=%b fpu_busy=%b ic_ready=%b dc_ready=%b",
                         u_hart.pc_reg, u_hart.pipe_stall, u_hart.ex_stall, u_hart.alu_busy,
                         u_hart.fpu_busy, u_hart.ic_ready, u_hart.dc_ready);
                $display("  id_ex_inst=%h ex_mem_inst=%h mem_wb_inst=%h",
                         u_hart.id_ex_inst, u_hart.ex_mem_inst, u_hart.mem_wb_inst);
                $display("  retire-check failures so far: %0d", chk_errors);
                $finish;
            end
        end
    end

    always @(posedge clk)
        if (total_cycles >= MAX_CYCLES) begin
            $display("[TIMEOUT] %0d cycles, no ebreak. retired=%0d last pc=0x%h",
                     total_cycles, total_instructions, o_retire_pc);
            $finish;
        end

endmodule
`default_nettype wire