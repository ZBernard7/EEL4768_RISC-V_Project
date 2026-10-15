`default_nettype none

// Phase 5 cache implementation: demand accesses, configurable associativity,
// LRU/PLRU, write-back hits, write-through/no-allocate misses,
// and pipelined next-line prefetching.
module cache #(
    parameter EVICT_POLICY = 0,
    parameter NUM_WAYS = 1,
    parameter CACHE_SIZE = 16,
    parameter BLOCK_SIZE = 128,
    parameter PREFETCH_EN = 0
)(
    input wire i_clk,
    input wire i_rst,
    input wire i_ren,
    input wire i_wen,
    input wire [31:0] i_addr,
    input wire [3:0] i_mask,
    input wire [31:0] i_wdata,
    output wire o_ready,
    output wire [31:0] o_rdata,
    output wire o_mem_rd,
    output wire [31:0] o_mem_rd_addr,
    input wire i_mem_valid,
    input wire [BLOCK_SIZE*8-1:0] i_mem_rd_data,
    output wire o_mem_wr,
    output wire [31:0] o_mem_wr_addr,
    output wire [BLOCK_SIZE*8-1:0] o_mem_wr_data,
    output wire [BLOCK_SIZE-1:0] o_mem_wr_be
);
    localparam TOTAL_BYTES = CACHE_SIZE * 1024;
    localparam NUM_LINES = TOTAL_BYTES / BLOCK_SIZE;
    localparam NUM_SETS = NUM_LINES / NUM_WAYS;
    localparam OFFSET_BITS = $clog2(BLOCK_SIZE);
    localparam SET_BITS = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 0;
    localparam INDEX_WIDTH = (SET_BITS > 0) ? SET_BITS : 1;
    localparam TAG_BITS = 32 - OFFSET_BITS - SET_BITS;
    localparam LINE_BITS = (NUM_LINES > 1) ? $clog2(NUM_LINES) : 1;
    localparam LRU_CALC = $clog2(NUM_WAYS);
    localparam LRU_BITS = (NUM_WAYS > 1) ? LRU_CALC : 1;
    localparam PLRU_DEPTH = $clog2(NUM_WAYS);
    localparam PLRU_LEAVES = 2 ** PLRU_DEPTH;
    localparam PLRU_NODES = PLRU_LEAVES - 1;
    localparam PLRU_WIDTH = (PLRU_NODES > 0) ? PLRU_NODES : 1;
    localparam WAY_CALC = $clog2(NUM_WAYS);
localparam WAY_BITS = (NUM_WAYS > 1) ? WAY_CALC : 1;
    localparam WORD_BITS = (BLOCK_SIZE > 4) ? $clog2(BLOCK_SIZE / 4) : 1;

    wire [INDEX_WIDTH-1:0] addr_index;
    wire [TAG_BITS-1:0] addr_tag = i_addr[31:OFFSET_BITS+SET_BITS];
    wire [OFFSET_BITS-1:0] addr_offset = i_addr[OFFSET_BITS-1:0];
    wire [31:0] aligned_addr = {i_addr[31:OFFSET_BITS], {OFFSET_BITS{1'b0}}};
    wire [WORD_BITS-1:0] word_index;
    generate
        if (NUM_SETS == 1) begin : single_set
            assign addr_index = {INDEX_WIDTH{1'b0}};
        end else begin : multiple_sets
            assign addr_index = i_addr[OFFSET_BITS +: SET_BITS];
        end
        if (BLOCK_SIZE == 4) begin : single_word
            assign word_index = {WORD_BITS{1'b0}};
        end else begin : multiple_words
            assign word_index = addr_offset[OFFSET_BITS-1:2];
        end
    endgenerate

    reg [BLOCK_SIZE*8-1:0] cache_data [0:NUM_LINES-1];
    reg [TAG_BITS-1:0] cache_tag [0:NUM_LINES-1];
    reg cache_valid [0:NUM_LINES-1];
    reg cache_dirty [0:NUM_LINES-1];
    reg [LRU_BITS-1:0] lru_rank [0:NUM_LINES-1];
    reg [PLRU_WIDTH-1:0] plru_tree [0:NUM_SETS-1];

    wire [NUM_LINES-1:0] hit_bits;
    wire [NUM_LINES-1:0] invalid_bits;
    wire [NUM_LINES-1:0] lru_bits;
    wire hit = |hit_bits;
    wire has_invalid = |invalid_bits;
    wire [LINE_BITS-1:0] hit_chain [0:NUM_LINES];
    wire [LINE_BITS-1:0] invalid_chain [0:NUM_LINES];
    wire [LINE_BITS-1:0] lru_chain [0:NUM_LINES];
    assign hit_chain[0] = {LINE_BITS{1'b0}};
    assign invalid_chain[NUM_LINES] = {LINE_BITS{1'b0}};
    assign lru_chain[NUM_LINES] = {LINE_BITS{1'b0}};

    genvar k;
    generate
        for (k = 0; k < NUM_LINES; k = k + 1) begin : match_lines
            localparam LINE_SET = k / NUM_WAYS;
            localparam LAST_RANK = NUM_WAYS - 1;
            wire [INDEX_WIDTH-1:0] line_set;
            wire [LRU_BITS-1:0] last_rank;
            wire [LINE_BITS-1:0] line_number;
            assign line_set = LINE_SET;
            assign last_rank = LAST_RANK;
            assign line_number = k;
            assign hit_bits[k] = cache_valid[k] &&
                (addr_index == line_set) && (cache_tag[k] == addr_tag);
            assign invalid_bits[k] = !cache_valid[k] && (addr_index == line_set);
            assign lru_bits[k] = cache_valid[k] && (addr_index == line_set) &&
                (lru_rank[k] == last_rank);
            assign hit_chain[k+1] = hit_bits[k] ? line_number : hit_chain[k];
            assign invalid_chain[k] = invalid_bits[k] ? line_number : invalid_chain[k+1];
            assign lru_chain[k] = lru_bits[k] ? line_number : lru_chain[k+1];
        end
    endgenerate

    wire [LINE_BITS-1:0] hit_line = hit_chain[NUM_LINES];

    // PLRU: walk the tree. For a non-power-of-two way count, a branch
    // whose subtree contains only padded leaves is never selected.
    wire [31:0] tree_node [0:PLRU_DEPTH];
    wire [31:0] tree_way [0:PLRU_DEPTH];
    assign tree_node[0] = 32'd0;
    assign tree_way[0] = 32'd0;
    genvar depth;
    generate
        for (depth=0; depth<PLRU_DEPTH; depth=depth+1) begin : traverse_tree
            localparam HALF_SPAN = PLRU_LEAVES / (2 ** (depth+1));
            wire choose_right;
            assign choose_right = (tree_way[depth] + HALF_SPAN < NUM_WAYS) &&
                plru_tree[addr_index][tree_node[depth]];
            assign tree_way[depth+1] = tree_way[depth] +
                (choose_right ? HALF_SPAN : 0);
            assign tree_node[depth+1] = tree_node[depth] + tree_node[depth] +
                (choose_right ? 32'd2 : 32'd1);
        end
    endgenerate

    // Translate the selected PLRU way into a physical line number without
    // multiplying a run-time index by NUM_WAYS.
    wire [NUM_LINES-1:0] plru_bits;
    wire [LINE_BITS-1:0] plru_chain [0:NUM_LINES];
    assign plru_chain[NUM_LINES] = {LINE_BITS{1'b0}};
    genvar p;
    generate
        for (p=0; p<NUM_LINES; p=p+1) begin : choose_plru
            localparam THIS_SET = p / NUM_WAYS;
            localparam THIS_WAY = p % NUM_WAYS;
            wire [INDEX_WIDTH-1:0] set_number;
            wire [31:0] way_number;
            wire [LINE_BITS-1:0] line_number;
            assign set_number = THIS_SET;
            assign way_number = THIS_WAY;
            assign line_number = p;
            assign plru_bits[p] = (addr_index == set_number) &&
                (tree_way[PLRU_DEPTH] == way_number);
            assign plru_chain[p] = plru_bits[p] ? line_number : plru_chain[p+1];
        end
    endgenerate
    wire [LINE_BITS-1:0] victim_line = has_invalid ? invalid_chain[0] :
        (EVICT_POLICY == 1 ? plru_chain[0] : lru_chain[0]);
    wire [BLOCK_SIZE*8-1:0] read_block = cache_data[hit_line];
    wire [31:0] read_word = read_block[{word_index,5'b00000} +: 32];

    // CPU holds request stable while o_ready is low.
    localparam [1:0] IDLE = 2'd0, WAIT_MEM = 2'd1, RESPONSE = 2'd2;
    reg [1:0] state;
    reg [LINE_BITS-1:0] pending_victim;
    reg [TAG_BITS-1:0] pending_tag;
    reg [31:0] pending_addr;
    reg [INDEX_WIDTH-1:0] pending_set;
    // A speculative block may return while CPU continues running. To keep
    // responses in order, hold a subsequent read miss until prefetch completes.
    reg prefetch_scheduled;
    reg prefetch_outstanding;
    reg [31:0] prefetch_addr;
    localparam [31:0] BLOCK_SIZE_U = BLOCK_SIZE;
wire [31:0] next_line_addr = aligned_addr + BLOCK_SIZE_U;
    wire [TAG_BITS-1:0] next_tag = next_line_addr[31:OFFSET_BITS+SET_BITS];
    wire [INDEX_WIDTH-1:0] next_set;
    wire [NUM_LINES-1:0] next_hit_bits;
    generate
        if (NUM_SETS == 1) begin : next_single_set
            assign next_set = {INDEX_WIDTH{1'b0}};
        end else begin : next_many_sets
            assign next_set = next_line_addr[OFFSET_BITS +: SET_BITS];
        end
    endgenerate
    genvar n;
    generate
        for (n=0; n<NUM_LINES; n=n+1) begin : check_next
            localparam THIS_SET = n / NUM_WAYS;
            wire [INDEX_WIDTH-1:0] set_number;
            assign set_number = THIS_SET;
            assign next_hit_bits[n] = cache_valid[n] &&
                (next_set == set_number) && (cache_tag[n] == next_tag);
        end
    endgenerate
    wire next_hit = |next_hit_bits;

    // Prefetch arrival takes priority over CPU operations for one cycle.
    wire prefetch_return = prefetch_outstanding && i_mem_valid &&
        (state != WAIT_MEM) && !i_rst;
    wire cpu_usable = !prefetch_return && !prefetch_scheduled;
    wire read_miss = (state == IDLE) && cpu_usable &&
        !prefetch_outstanding && i_ren && !i_wen && !hit && !i_rst;
    wire store_hit = (state == IDLE) && cpu_usable && i_wen && hit && !i_rst;
    wire store_miss = (state == IDLE) && cpu_usable && i_wen && !hit && !i_rst;
    wire fill = (state == WAIT_MEM) && i_mem_valid && !i_rst;
    wire prefetch_fire = (PREFETCH_EN != 0) && prefetch_scheduled && !i_rst;
    wire [LRU_BITS-1:0] maximum_rank = {LRU_BITS{1'b1}};

    // A hit can be served immediately. A demand miss completes one cycle
    // after the returned line has been installed in the storage arrays.
    assign o_ready = !i_rst && ((state == RESPONSE) ||
        ((state == IDLE) && cpu_usable && (i_wen ||
         !i_ren || hit)));
    assign o_rdata = read_word;
    assign o_mem_rd = read_miss || prefetch_fire;
    assign o_mem_rd_addr = prefetch_fire ? prefetch_addr : aligned_addr;

    // Place write-through bytes at their byte lanes within the line.
    reg [BLOCK_SIZE*8-1:0] store_block;
    reg [BLOCK_SIZE-1:0] store_byte_en;
    always @(*) begin
        store_block = {BLOCK_SIZE*8{1'b0}};
        store_block[{word_index,5'b00000} +: 32] = i_wdata;
        store_byte_en = {BLOCK_SIZE{1'b0}};
        store_byte_en[{word_index,2'b00} +: 4] = i_mask;
    end

    // Victim selection for a prefetched line, at arrival (not request time).
    wire [INDEX_WIDTH-1:0] pf_set;
    wire [TAG_BITS-1:0] pf_tag = prefetch_addr[31:OFFSET_BITS+SET_BITS];
    generate
        if (NUM_SETS == 1) begin : pf_single_set
            assign pf_set = {INDEX_WIDTH{1'b0}};
        end else begin : pf_many_sets
            assign pf_set = prefetch_addr[OFFSET_BITS +: SET_BITS];
        end
    endgenerate
    wire [NUM_LINES-1:0] pf_invalid;
    wire [NUM_LINES-1:0] pf_lru;
    wire [NUM_LINES-1:0] pf_hit_bits;
    wire [LINE_BITS-1:0] pf_invalid_chain[0:NUM_LINES];
    wire [LINE_BITS-1:0] pf_lru_chain[0:NUM_LINES];
    assign pf_invalid_chain[NUM_LINES] = {LINE_BITS{1'b0}};
    assign pf_lru_chain[NUM_LINES] = {LINE_BITS{1'b0}};
    genvar q;
    generate
        for (q=0; q<NUM_LINES; q=q+1) begin : pf_candidates
            localparam THIS_SET = q / NUM_WAYS;
            wire [INDEX_WIDTH-1:0] set_number;
            wire [LRU_BITS-1:0] last_rank;
            wire [LINE_BITS-1:0] line_number;
            assign set_number = THIS_SET;
            assign last_rank = NUM_WAYS-1;
            assign line_number = q;
            assign pf_invalid[q] = !cache_valid[q] && (pf_set == set_number);
            assign pf_lru[q] = cache_valid[q] && (pf_set == set_number) &&
                (lru_rank[q] == last_rank);
            assign pf_hit_bits[q] = cache_valid[q] && (pf_set == set_number) &&
                (cache_tag[q] == pf_tag);
            assign pf_invalid_chain[q] = pf_invalid[q] ? line_number : pf_invalid_chain[q+1];
            assign pf_lru_chain[q] = pf_lru[q] ? line_number : pf_lru_chain[q+1];
        end
    endgenerate
    wire [31:0] pf_node[0:PLRU_DEPTH];
    wire [31:0] pf_way[0:PLRU_DEPTH];
    assign pf_node[0] = 32'd0;
    assign pf_way[0] = 32'd0;
    genvar pd;
    generate
        for (pd=0; pd<PLRU_DEPTH; pd=pd+1) begin : pf_walk
            localparam HALF_SPAN = PLRU_LEAVES / (2 ** (pd+1));
            wire right_side;
            assign right_side = (pf_way[pd] + HALF_SPAN < NUM_WAYS) &&
                plru_tree[pf_set][pf_node[pd]];
            assign pf_way[pd+1] = pf_way[pd] + (right_side ? HALF_SPAN : 0);
            assign pf_node[pd+1] = pf_node[pd] + pf_node[pd] +
                (right_side ? 32'd2 : 32'd1);
        end
    endgenerate
    wire [NUM_LINES-1:0] pf_plru_bits;
    wire [LINE_BITS-1:0] pf_plru_chain[0:NUM_LINES];
    assign pf_plru_chain[NUM_LINES] = {LINE_BITS{1'b0}};
    genvar pq;
    generate
        for (pq=0; pq<NUM_LINES; pq=pq+1) begin : pf_plru_select
            localparam THIS_SET = pq / NUM_WAYS;
            localparam THIS_WAY = pq % NUM_WAYS;
            wire [INDEX_WIDTH-1:0] set_number;
            wire [31:0] way_number;
            wire [LINE_BITS-1:0] line_number;
            assign set_number = THIS_SET;
            assign way_number = THIS_WAY;
            assign line_number = pq;
            assign pf_plru_bits[pq] = (pf_set == set_number) &&
                (pf_way[PLRU_DEPTH] == way_number);
            assign pf_plru_chain[pq] = pf_plru_bits[pq] ? line_number : pf_plru_chain[pq+1];
        end
    endgenerate
    wire [LINE_BITS-1:0] pf_victim = (|pf_invalid) ? pf_invalid_chain[0] :
        (EVICT_POLICY == 1 ? pf_plru_chain[0] : pf_lru_chain[0]);
    wire pf_fill = prefetch_return && !(|pf_hit_bits);
    wire [LINE_BITS-1:0] touched_line = pf_fill ? pf_victim :
        (fill ? pending_victim : hit_line);
    wire touch = pf_fill || fill || ((state == IDLE) && cpu_usable && hit &&
        (i_ren || i_wen) && !i_rst);
    wire [LRU_BITS-1:0] touched_rank = pf_fill ? lru_rank[pf_victim] :
        (fill ? lru_rank[pending_victim] : lru_rank[hit_line]);
    wire dirty_eviction = (fill && cache_valid[pending_victim] &&
        cache_dirty[pending_victim]) || (pf_fill && cache_valid[pf_victim] &&
        cache_dirty[pf_victim]);
    assign o_mem_wr = dirty_eviction || store_miss;
    wire [31:0] evicted_addr;
    generate
        if (NUM_SETS == 1) begin : evict_single_set
            assign evicted_addr = {cache_tag[pending_victim], {OFFSET_BITS{1'b0}}};
        end else begin : evict_multiple_sets
            assign evicted_addr = {cache_tag[pending_victim],
                pending_addr[OFFSET_BITS+SET_BITS-1:OFFSET_BITS],
                {OFFSET_BITS{1'b0}}};
        end
    endgenerate
    wire [31:0] pf_evicted_addr;
    generate
        if (NUM_SETS == 1) begin : pf_evict_single
            assign pf_evicted_addr = {cache_tag[pf_victim],{OFFSET_BITS{1'b0}}};
        end else begin : pf_evict_multiple
            assign pf_evicted_addr = {cache_tag[pf_victim],
                prefetch_addr[OFFSET_BITS+SET_BITS-1:OFFSET_BITS],
                {OFFSET_BITS{1'b0}}};
        end
    endgenerate
    assign o_mem_wr_addr = pf_fill && cache_valid[pf_victim] &&
        cache_dirty[pf_victim] ? pf_evicted_addr :
        (dirty_eviction ? evicted_addr : aligned_addr);
    assign o_mem_wr_data = pf_fill && cache_valid[pf_victim] &&
        cache_dirty[pf_victim] ? cache_data[pf_victim] :
        (dirty_eviction ? cache_data[pending_victim] : store_block);
    assign o_mem_wr_be = dirty_eviction ? {BLOCK_SIZE{1'b1}} : store_byte_en;

    always @(posedge i_clk) begin
        if (i_rst) begin
            state <= IDLE;
            pending_victim <= {LINE_BITS{1'b0}};
            pending_tag <= {TAG_BITS{1'b0}};
            pending_addr <= 32'd0;
            pending_set <= {INDEX_WIDTH{1'b0}};
            prefetch_scheduled <= 1'b0;
            prefetch_outstanding <= 1'b0;
            prefetch_addr <= 32'd0;
        end else begin
            if (prefetch_scheduled) begin
                prefetch_scheduled <= 1'b0;
                prefetch_outstanding <= 1'b1;
            end
            if (prefetch_return) prefetch_outstanding <= 1'b0;
            case (state)
                IDLE: begin
                    if (read_miss) begin
                        pending_victim <= victim_line;
                        pending_tag <= addr_tag;
                        pending_addr <= aligned_addr;
                        pending_set <= addr_index;
                        if (PREFETCH_EN != 0 && !next_hit) begin
                            prefetch_scheduled <= 1'b1;
                            prefetch_addr <= next_line_addr;
                        end
                        state <= WAIT_MEM;
                    end
                end
                WAIT_MEM: begin
                    if (i_mem_valid) state <= RESPONSE;
                end
                RESPONSE: state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    // Merge masked word-lane writes into the current cached word.
    wire [31:0] old_word = read_word;
    wire [31:0] new_word = {
        i_mask[3] ? i_wdata[31:24] : old_word[31:24],
        i_mask[2] ? i_wdata[23:16] : old_word[23:16],
        i_mask[1] ? i_wdata[15:8]  : old_word[15:8],
        i_mask[0] ? i_wdata[7:0]   : old_word[7:0]
    };

    genvar j;
    generate
        for (j = 0; j < NUM_LINES; j = j + 1) begin : update_lines
            localparam INITIAL_RANK = j % NUM_WAYS;
            localparam LINE_SET = j / NUM_WAYS;
            wire [INDEX_WIDTH-1:0] line_set;
            wire [LRU_BITS-1:0] first_rank;
            wire [LRU_BITS-1:0] last_rank;
            assign line_set = LINE_SET;
            assign first_rank = INITIAL_RANK;
            assign last_rank = NUM_WAYS - 1;
            always @(posedge i_clk) begin
                if (i_rst) begin
                    cache_valid[j] <= 1'b0;
                    cache_dirty[j] <= 1'b0;
                    cache_tag[j] <= {TAG_BITS{1'b0}};
                    lru_rank[j] <= first_rank;
                end else begin
                    if (pf_fill && (pf_victim == j)) begin
                        cache_data[j] <= i_mem_rd_data;
                        cache_tag[j] <= pf_tag;
                        cache_valid[j] <= 1'b1;
                        cache_dirty[j] <= 1'b0;
                    end else if (fill && (pending_victim == j)) begin
                        cache_data[j] <= i_mem_rd_data;
                        cache_tag[j] <= pending_tag;
                        cache_valid[j] <= 1'b1;
                        cache_dirty[j] <= 1'b0;
                    end else if (store_hit && (hit_line == j)) begin
                        cache_data[j][{word_index,5'b00000} +: 32] <= new_word;
                        cache_dirty[j] <= 1'b1;
                    end
                    if (touch && ((pf_fill && pf_set == line_set) ||
                                  (!pf_fill && fill && pending_set == line_set) ||
                                  (!pf_fill && !fill && addr_index == line_set))) begin
                        if (touched_line == j) begin
                            lru_rank[j] <= {LRU_BITS{1'b0}};
                        end else if (cache_valid[j] &&
                            ((fill || pf_fill) ? (lru_rank[j] < last_rank) :
                                    (lru_rank[j] < touched_rank))) begin
                            lru_rank[j] <= lru_rank[j] + 1'b1;
                        end
                    end
                end
            end
        end
    endgenerate

    // Every tree node points away from the most recently touched way.
    genvar ps, pn;
    generate
        for (ps=0; ps<NUM_SETS; ps=ps+1) begin : plru_sets
            for (pn=0; pn<PLRU_NODES; pn=pn+1) begin : plru_nodes
                localparam LEVEL = $clog2(pn+2)-1;
                localparam FIRST_NODE = (2 ** LEVEL)-1;
                localparam POSITION = pn-FIRST_NODE;
                localparam SPAN = PLRU_LEAVES / (2 ** LEVEL);
                localparam START = POSITION*SPAN;
                localparam HALF = SPAN/2;
                localparam FIRST_LINE = ps*NUM_WAYS;
                always @(posedge i_clk) begin
                    if (i_rst) plru_tree[ps][pn] <= 1'b0;
                    else if (touch && touched_line >= FIRST_LINE + START &&
                        touched_line < FIRST_LINE + START + SPAN)
                        plru_tree[ps][pn] <=
                            (touched_line < FIRST_LINE + START + HALF);
                end
            end
        end
    endgenerate
endmodule

`default_nettype wire
