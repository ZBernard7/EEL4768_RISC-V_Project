import sys

def check(sim_file, ref_file):
    with open(sim_file) as f_sim, open(ref_file) as f_ref:
        sim_lines = [l.strip() for l in f_sim if l.strip() and not l.startswith("#") and "TIMEOUT" not in l and "warning" not in l.lower()]
        ref_lines = [l.strip() for l in f_ref if l.strip() and not l.startswith("#")]

    print(f"Comparing {len(sim_lines)} simulated vectors against {len(ref_lines)} reference vectors...")
    
    passed = 0
    failed = 0
    
    for i, (s_line, r_line) in enumerate(zip(sim_lines, ref_lines)):
        s_tokens = s_line.split()
        r_tokens = r_line.split()
        
        err = False
        # Columns (0-indexed):
        # 0:pc, 1:inst, 2:trap, 3:halt, 4:rs1_addr, 5:rs1_data, 6:rs2_addr, 7:rs2_data,
        # 8:rd_addr, 9:rd_data, 10:mem_op, 11:mem_addr, 12:mem_mask, 13:mem_wdata, 14:next_pc
        for col, (s, r) in enumerate(zip(s_tokens, r_tokens)):
            # Explicit wildcard
            if "x" in r.lower():
                continue
            
            # Rule: rd_wdata (col 9) only checked when rd_waddr != 0
            if col == 9:
                if int(r_tokens[8], 16) == 0:
                    continue

            # Rule: mem_addr/mask/wdata only checked when mem_op != 0
            if col in (11, 12, 13):
                if int(r_tokens[10], 16) == 0:
                    continue

            # Rule: mem_wdata (col 13) only compared on byte lanes enabled by mem_mask (col 12)
            if col == 13:
                mask = int(r_tokens[12], 16)
                s_val = int(s, 16)
                r_val = int(r, 16)
                
                lane_err = False
                for byte_idx in range(4):
                    if (mask >> byte_idx) & 1:
                        s_byte = (s_val >> (byte_idx * 8)) & 0xFF
                        r_byte = (r_val >> (byte_idx * 8)) & 0xFF
                        if s_byte != r_byte:
                            lane_err = True
                            break
                if lane_err:
                    err = True
                    break
                continue
                
            if s.lower() != r.lower():
                err = True
                break
        
        if err:
            if failed < 10:
                print(f"[FAIL] Vector {i}:")
                print(f"  Got:      {s_line}")
                print(f"  Expected: {r_line}")
            failed += 1
        else:
            passed += 1

    print(f"\nResult: {passed} passed, {failed} failed out of {len(ref_lines)} vectors.")
    if failed == 0 and len(sim_lines) == len(ref_lines):
        print(">>> ALL TRACE VECTORS MATCHED SUCCESSFULLY! <<<")

if __name__ == "__main__":
    check(sys.argv[1], sys.argv[2])
