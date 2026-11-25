`timescale 1ns/1ps
`default_nettype none
module tb;
    reg clk=0, rst=1;
    always #5 clk=~clk;
    reg [2:0] opsel=0;
    reg sub=0, unsigned_mode=0, arith=0, mext=0, advance=0;
    reg [31:0] a=32'hffffffff, b=32'h00000001;
    wire [31:0] result;
    wire eq,slt,busy;
    alu dut (.i_clk(clk),.i_rst(rst),.i_opsel(opsel),.i_sub(sub),
        .i_unsigned(unsigned_mode),.i_arith(arith),.i_mext(mext),
        .i_advance(advance),.i_op1(a),.i_op2(b),.o_result(result),
        .o_eq(eq),.o_slt(slt),.o_busy(busy));

    integer seed=123456789, rng, ni=10000, nm=1000;
    integer total=0, errors=0, k,i,j,s,h;
    integer counts[0:17];
    reg [31:0] edgeval[0:19];
    reg [31:0] x,y;
    reg [31:0] shift_seen[0:17];
    reg [3:0] sign_seen[0:17];
    reg [2:0] signed_seen[0:17], unsigned_seen[0:17];

    function [31:0] golden;
        input integer op;
        input [31:0] p,q;
        reg signed [63:0] sp,sq,prod;
        reg [63:0] up,uq,u_prod;
        begin
            sp={{32{p[31]}},p}; sq={{32{q[31]}},q};
            up={32'b0,p}; uq={32'b0,q};
            prod=sp*sq; u_prod=up*uq;
            case(op)
                0: golden=p+q;
                1: golden=p-q;
                2: golden=p<<q[4:0];
                3: golden=($signed(p)<$signed(q));
                4: golden=(p<q);
                5: golden=p^q;
                6: golden=p>>q[4:0];
                7: golden=$signed(p)>>>q[4:0];
                8: golden=p|q;
                9: golden=p&q;
                10: golden=u_prod[31:0];
                11: golden=prod[63:32];
                12: begin prod=sp*$signed(uq); golden=prod[63:32]; end
                13: golden=u_prod[63:32];
                14: begin
    if (q == 0)
        golden = 32'hffffffff;
    else
        golden = $signed(sp) / $signed(sq);
end

15: begin
    if (q == 0)
        golden = 32'hffffffff;
    else
        golden = up / uq;
end

16: begin
    if (q == 0)
        golden = p;
    else
        golden = $signed(sp) % $signed(sq);
end

17: begin
    if (q == 0)
        golden = p;
    else
        golden = up % uq;
end
                default: golden=32'hxxxxxxxx;
            endcase
        end
    endfunction
    function [63:0] opname;
        input integer op;
        begin case(op)
            0:opname="ADD";1:opname="SUB";2:opname="SLL";
            3:opname="SLT";4:opname="SLTU";5:opname="XOR";
            6:opname="SRL";7:opname="SRA";8:opname="OR";9:opname="AND";
            10:opname="MUL";11:opname="MULH";12:opname="MULHSU";
            13:opname="MULHU";14:opname="DIV";15:opname="DIVU";
            16:opname="REM";17:opname="REMU";default:opname="?";
        endcase end
    endfunction
    task fail;
        input [255:0] reason;
        input integer op;
        input [31:0] expected,actual;
        begin
            errors=errors+1;
            if(errors<=30) $display("FAIL vector=%0d seed=%0d op=%0s a=%h b=%h %0s expected=%h actual=%h",total,seed,opname(op),a,b,reason,expected,actual);
        end
    endtask
    task flags;
        input integer op;
        reg lt;
        begin
            lt=unsigned_mode?(a<b):($signed(a)<$signed(b));
            if(eq !== (a==b)) fail("equality",op,(a==b),eq);
            if(slt !== lt) fail("comparison",op,lt,slt);
        end
    endtask
    task check;
        input integer op;
        input [31:0] p,q;
        input integer hold_cycles;
        reg [31:0] expected;
        integer cycles,t;
        begin
            @(negedge clk);
            a=p;b=q;advance=0;mext=(op>=10);
            sub=($random(rng)&1);arith=($random(rng)&1);
            unsigned_mode=($random(rng)&1);
            case(op)
                0:begin opsel=0;sub=0;end
                1:begin opsel=0;sub=1;end
                2:opsel=1;3:opsel=2;4:opsel=3;5:opsel=4;
                6:begin opsel=5;arith=0;end
                7:begin opsel=5;arith=1;end
                8:opsel=6;9:opsel=7;
                default:opsel=op-10;
            endcase
            expected=golden(op,p,q);
            total=total+1;counts[op]=counts[op]+1;
            shift_seen[op][q[4:0]]=1;
            sign_seen[op][{p[31],q[31]}]=1;
            signed_seen[op][(p==q)?1:($signed(p)<$signed(q)?0:2)]=1;
            unsigned_seen[op][(p==q)?1:(p<q?0:2)]=1;
            #1;flags(op);
            unsigned_mode=~unsigned_mode;#1;flags(op);
            if(op<10) begin
                if(busy !== 0) fail("integer busy",op,0,busy);
                if(result !== expected) fail("result",op,expected,result);
            end else begin
                if(busy !== 1) fail("initial busy",op,1,busy);
                cycles=0;
                while(busy===1'b1 && cycles<40) begin
                    @(posedge clk);#1;cycles=cycles+1;
                end
                if(busy !== 0) begin
                    fail("timeout or unknown busy",op,0,busy);
                    @(negedge clk);rst=1;mext=0;
                    @(posedge clk);#1;
                    @(negedge clk);rst=0;
                end else begin
                    if(cycles!=33) fail("implementation latency",op,33,cycles);
                    if(result !== expected) fail("result",op,expected,result);
                    for(t=0;t<hold_cycles;t=t+1) begin
                        @(posedge clk);#1;
                        if(result !== expected) fail("held result",op,expected,result);
                        if(busy !== 0) fail("held busy",op,0,busy);
                    end
                    @(negedge clk);advance=1;
                    @(posedge clk);#1;
                    if(busy !== 1) fail("rearm after advance",op,1,busy);
                    // Next check replaces inputs at the next falling edge.
                end
            end
        end
    endtask

    initial begin
        if($value$plusargs("SEED=%d",seed)) begin end
        if($value$plusargs("RANDOM=%d",ni)) begin end
        if($value$plusargs("M_RANDOM=%d",nm)) begin end
        if(ni<0 || nm<0) $fatal(1,"Counts must be nonnegative");
        rng=seed;
        edgeval[0]=0;edgeval[1]=1;edgeval[2]=2;edgeval[3]=3;
        edgeval[4]=32'hffffffff;edgeval[5]=32'hfffffffe;
        edgeval[6]=32'h80000000;edgeval[7]=32'h7fffffff;
        edgeval[8]=32'h80000001;edgeval[9]=32'h7ffffffe;
        edgeval[10]=32'haaaaaaaa;edgeval[11]=32'h55555555;
        edgeval[12]=32'hffff0000;edgeval[13]=32'h0000ffff;
        edgeval[14]=31;edgeval[15]=32;edgeval[16]=33;
        edgeval[17]=32'h40000000;edgeval[18]=32'h00010000;edgeval[19]=32'h8000ffff;
        for(k=0;k<18;k=k+1) begin
            counts[k]=0;shift_seen[k]=0;sign_seen[k]=0;
            signed_seen[k]=0;unsigned_seen[k]=0;
        end
        repeat(2) @(posedge clk);
        @(negedge clk);rst=0;
        $display("ALU test seed=%0d integer random/op=%0d M random/op=%0d",seed,ni,nm);
        for(k=0;k<18;k=k+1) begin
            for(i=0;i<20;i=i+1)
                for(j=0;j<20;j=j+1) check(k,edgeval[i],edgeval[j],(i+j)%3);
            for(i=0;i<32;i=i+1) begin
                x=32'b1<<i;
                check(k,x,~x,0);check(k,~x,x,0);
                check(k,x-1,1,0);check(k,x,1,0);
                check(k,x,x,0);check(k,~x,~x,0);
                // Guarantee every low-five-bit bin for every operation.
                check(k,32'h80000001,i,0);
            end
            if(k==2 || k==6 || k==7)
                for(i=0;i<20;i=i+1)
                    for(s=0;s<32;s=s+1) begin
                        check(k,edgeval[i],s,0);
                        check(k,edgeval[i],32'hffffffe0|s,0);
                        y=$random(rng);y[4:0]=s;
                        check(k,edgeval[i],y,0);
                    end
            for(i=0;i<((k<10)?ni:nm);i=i+1) begin
                x=$random(rng);y=$random(rng);
                case(i%8)
                    0:y=x;1:y=~x;2:y=0;3:y=edgeval[i%20];
                    4:y=x+1;5:x=edgeval[i%20];
                    default:begin end
                endcase
                h=($random(rng)&3);
                check(k,x,y,h);
            end
            $display("%0s: %0d vectors, signs=%b shifts=%h signed relations=%b unsigned relations=%b",opname(k),counts[k],sign_seen[k],shift_seen[k],signed_seen[k],unsigned_seen[k]);
            if(sign_seen[k]!==4'hf || shift_seen[k]!==32'hffffffff || signed_seen[k]!==3'b111 || unsigned_seen[k]!==3'b111) begin
                errors=errors+1;$display("FAIL coverage for %0s",opname(k));
            end
        end
        // Interrupt an active division with synchronous reset.
        @(negedge clk);mext=1;advance=0;opsel=4;a=12345;b=7;
        repeat(5) @(posedge clk);
        #1;if(busy!==1) fail("busy before reset",14,1,busy);
        @(negedge clk);rst=1;mext=0;
        @(posedge clk);#1;if(busy!==0) fail("busy after reset",14,0,busy);
        @(negedge clk);rst=0;
        check(14,12345,7,3);check(0,32'hffffffff,1,0);
        $display("TOTAL=%0d ERRORS=%0d SEED=%0d",total,errors,seed);
        if(errors!=0) $fatal(1,"ALU TEST FAILED");
        $display("PASS: all ALU vectors and coverage checks passed");
        $finish;
    end
endmodule
`default_nettype wire
