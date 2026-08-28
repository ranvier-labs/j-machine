module j_machine_f2_pcim_memory #(
  parameter int NODES = 512,
  parameter int NODE_INDEX_WIDTH = NODES <= 1 ? 1 : $clog2(NODES)
) (
  input  logic clk,
  input  logic reset,
  input  logic [63:0] host_memory_base,

  input  logic [NODES-1:0] cpu_request_valid,
  output logic [NODES-1:0] cpu_request_ready,
  input  logic [NODES-1:0] cpu_request_write,
  input  logic [NODES-1:0][j_machine_pkg::MDP_ADDR_WIDTH-1:0]
      cpu_request_address,
  input  logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0]
      cpu_request_wdata,
  output logic [NODES-1:0] cpu_response_valid,
  output logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0]
      cpu_response_rdata,
  output logic [NODES-1:0] cpu_response_dram_error,

  input  logic [NODES-1:0] qrb_write,
  output logic [NODES-1:0] qrb_ready,
  input  logic [NODES-1:0][j_machine_pkg::MDP_ADDR_WIDTH-3:0]
      qrb_row_address,
  input  logic [NODES-1:0][j_machine_pkg::MDP_ROW_WIDTH-1:0]
      qrb_write_data,
  input  logic [NODES-1:0][j_machine_pkg::MDP_ROW_WORDS-1:0]
      qrb_write_enable,

  output logic busy,
  output logic write_error,
  output logic read_error,
  input  logic clear_errors,

  output logic [15:0] pcim_awid,
  output logic [63:0] pcim_awaddr,
  output logic [7:0] pcim_awlen,
  output logic [2:0] pcim_awsize,
  output logic [1:0] pcim_awburst,
  output logic [3:0] pcim_awcache,
  output logic pcim_awlock,
  output logic [2:0] pcim_awprot,
  output logic [3:0] pcim_awqos,
  output logic [54:0] pcim_awuser,
  output logic pcim_awvalid,
  input  logic pcim_awready,

  output logic [15:0] pcim_wid,
  output logic [511:0] pcim_wdata,
  output logic [63:0] pcim_wstrb,
  output logic pcim_wlast,
  output logic [63:0] pcim_wuser,
  output logic pcim_wvalid,
  input  logic pcim_wready,

  input  logic [15:0] pcim_bid,
  input  logic [1:0] pcim_bresp,
  input  logic pcim_bvalid,
  output logic pcim_bready,

  output logic [15:0] pcim_arid,
  output logic [63:0] pcim_araddr,
  output logic [7:0] pcim_arlen,
  output logic [2:0] pcim_arsize,
  output logic [1:0] pcim_arburst,
  output logic [3:0] pcim_arcache,
  output logic pcim_arlock,
  output logic [2:0] pcim_arprot,
  output logic [3:0] pcim_arqos,
  output logic [54:0] pcim_aruser,
  output logic pcim_arvalid,
  input  logic pcim_arready,

  input  logic [15:0] pcim_rid,
  input  logic [511:0] pcim_rdata,
  input  logic [1:0] pcim_rresp,
  input  logic pcim_rlast,
  input  logic [63:0] pcim_ruser,
  input  logic pcim_rvalid,
  output logic pcim_rready
);
  import j_machine_pkg::*;

  typedef enum logic [2:0] {
    MEMORY_IDLE,
    MEMORY_WRITE,
    MEMORY_WRITE_RESPONSE,
    MEMORY_READ_ADDRESS,
    MEMORY_READ_DATA
  } memory_state_t;

  memory_state_t state;
  logic [NODE_INDEX_WIDTH-1:0] round_robin_node;
  logic selected_valid;
  logic selected_qrb;
  logic [NODE_INDEX_WIDTH-1:0] selected_node;
  logic selected_write;
  logic selected_rom_write;
  logic [63:0] selected_address;
  logic [2:0] selected_lane;
  logic [511:0] selected_wdata;
  logic [63:0] selected_wstrb;

  logic [NODE_INDEX_WIDTH-1:0] transaction_node;
  logic [2:0] transaction_lane;
  logic [63:0] transaction_address;
  logic [511:0] transaction_wdata;
  logic [63:0] transaction_wstrb;
  logic aw_sent;
  logic w_sent;

  // Each architectural word occupies one 64-bit lane. Eight consecutive words
  // therefore fit exactly in one F2 PCIM beat. A node occupies 8 MiB, and all
  // 512 complete 20-bit address spaces occupy a contiguous 4 GiB aperture.
  function automatic logic [63:0] cpu_byte_address(
      input logic [NODE_INDEX_WIDTH-1:0] node,
      input logic [MDP_ADDR_WIDTH-1:3] beat_address
  );
    cpu_byte_address = host_memory_base
        + (64'(node) << 23)
        + (64'(beat_address) << 6);
  endfunction

  function automatic logic [63:0] qrb_byte_address(
      input logic [NODE_INDEX_WIDTH-1:0] node,
      input logic [MDP_ADDR_WIDTH-3:1] beat_address
  );
    qrb_byte_address = host_memory_base
        + (64'(node) << 23)
        + (64'(beat_address) << 6);
  endfunction

  always_comb begin
    selected_valid = 1'b0;
    selected_qrb = 1'b0;
    selected_node = '0;

    // Queue-row commits are lossless architectural writes, so they take
    // precedence over processor traffic. Round-robin selection prevents a hot
    // node from permanently excluding another node on the shared PCIM master.
    for (int offset = 0; offset < NODES; offset++) begin
      logic [NODE_INDEX_WIDTH-1:0] candidate;
      candidate = NODE_INDEX_WIDTH'((int'(round_robin_node) + offset) % NODES);
      if (!selected_valid && qrb_write[candidate]) begin
        selected_valid = 1'b1;
        selected_qrb = 1'b1;
        selected_node = NODE_INDEX_WIDTH'(candidate);
      end
    end
    for (int offset = 0; offset < NODES; offset++) begin
      logic [NODE_INDEX_WIDTH-1:0] candidate;
      candidate = NODE_INDEX_WIDTH'((int'(round_robin_node) + offset) % NODES);
      if (!selected_valid && cpu_request_valid[candidate]) begin
        selected_valid = 1'b1;
        selected_qrb = 1'b0;
        selected_node = NODE_INDEX_WIDTH'(candidate);
      end
    end

    selected_write = 1'b0;
    selected_rom_write = 1'b0;
    selected_address = '0;
    selected_lane = '0;
    selected_wdata = '0;
    selected_wstrb = '0;
    if (selected_valid && selected_qrb) begin
      selected_write = 1'b1;
      selected_address = qrb_byte_address(
          selected_node, qrb_row_address[selected_node][MDP_ADDR_WIDTH-3:1]);
      selected_lane = {qrb_row_address[selected_node][0], 2'b00};
      for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
        selected_wdata[(int'(selected_lane) + word_index)*64 +: MDP_WORD_WIDTH]
            = qrb_write_data[selected_node][word_index*MDP_WORD_WIDTH
                                            +: MDP_WORD_WIDTH];
        if (qrb_write_enable[selected_node][word_index]) begin
          selected_wstrb[(int'(selected_lane) + word_index)*8 +: 8] = 8'hff;
        end
      end
    end else if (selected_valid) begin
      selected_write = cpu_request_write[selected_node];
      selected_rom_write = selected_write
          && cpu_request_address[selected_node] >= 20'h01000
          && cpu_request_address[selected_node] <= 20'h01fff;
      selected_address = cpu_byte_address(
          selected_node,
          cpu_request_address[selected_node][MDP_ADDR_WIDTH-1:3]);
      selected_lane = cpu_request_address[selected_node][2:0];
      selected_wdata[selected_lane*64 +: MDP_WORD_WIDTH]
          = cpu_request_wdata[selected_node];
      selected_wstrb[selected_lane*8 +: 8] = 8'hff;
    end
  end

  always_comb begin
    cpu_request_ready = '0;
    qrb_ready = '0;
    if (state == MEMORY_IDLE && selected_valid) begin
      if (selected_qrb) begin
        qrb_ready[selected_node] = 1'b1;
      end else begin
        cpu_request_ready[selected_node] = 1'b1;
      end
    end
  end

  assign busy = state != MEMORY_IDLE;

  assign pcim_awid = 16'b0;
  assign pcim_awaddr = transaction_address;
  assign pcim_awlen = 8'b0;
  assign pcim_awsize = 3'd6;
  assign pcim_awburst = 2'b01;
  assign pcim_awcache = 4'b0011;
  assign pcim_awlock = 1'b0;
  assign pcim_awprot = 3'b000;
  assign pcim_awqos = 4'b0000;
  assign pcim_awuser = 55'b0;
  assign pcim_awvalid = state == MEMORY_WRITE && !aw_sent;

  assign pcim_wid = 16'b0;
  assign pcim_wdata = transaction_wdata;
  assign pcim_wstrb = transaction_wstrb;
  assign pcim_wlast = 1'b1;
  assign pcim_wuser = 64'b0;
  assign pcim_wvalid = state == MEMORY_WRITE && !w_sent;
  assign pcim_bready = state == MEMORY_WRITE_RESPONSE;

  assign pcim_arid = 16'b0;
  assign pcim_araddr = transaction_address;
  assign pcim_arlen = 8'b0;
  assign pcim_arsize = 3'd6;
  assign pcim_arburst = 2'b01;
  assign pcim_arcache = 4'b0011;
  assign pcim_arlock = 1'b0;
  assign pcim_arprot = 3'b000;
  assign pcim_arqos = 4'b0000;
  assign pcim_aruser = 55'b0;
  assign pcim_arvalid = state == MEMORY_READ_ADDRESS;
  assign pcim_rready = state == MEMORY_READ_DATA;

  always_ff @(posedge clk) begin
    cpu_response_valid <= '0;
    cpu_response_dram_error <= '0;

    if (reset) begin
      state <= MEMORY_IDLE;
      round_robin_node <= '0;
      transaction_node <= '0;
      transaction_lane <= '0;
      transaction_address <= '0;
      transaction_wdata <= '0;
      transaction_wstrb <= '0;
      aw_sent <= 1'b0;
      w_sent <= 1'b0;
      cpu_response_rdata <= '0;
      write_error <= 1'b0;
      read_error <= 1'b0;
    end else begin
      if (clear_errors) begin
        write_error <= 1'b0;
        read_error <= 1'b0;
      end

      unique case (state)
        MEMORY_IDLE: begin
          if (selected_valid) begin
            round_robin_node <= NODE_INDEX_WIDTH'(
                (int'(selected_node) + 1) % NODES);
            if (!selected_rom_write) begin
              transaction_node <= selected_node;
              transaction_lane <= selected_lane;
              transaction_address <= selected_address;
              transaction_wdata <= selected_wdata;
              transaction_wstrb <= selected_wstrb;
              aw_sent <= 1'b0;
              w_sent <= 1'b0;
              state <= selected_write ? MEMORY_WRITE : MEMORY_READ_ADDRESS;
            end
          end
        end
        MEMORY_WRITE: begin
          if (pcim_awvalid && pcim_awready) aw_sent <= 1'b1;
          if (pcim_wvalid && pcim_wready) w_sent <= 1'b1;
          if ((aw_sent || pcim_awready) && (w_sent || pcim_wready)) begin
            state <= MEMORY_WRITE_RESPONSE;
          end
        end
        MEMORY_WRITE_RESPONSE: begin
          if (pcim_bvalid) begin
            if (pcim_bresp != 2'b00) write_error <= 1'b1;
            state <= MEMORY_IDLE;
          end
        end
        MEMORY_READ_ADDRESS: begin
          if (pcim_arready) state <= MEMORY_READ_DATA;
        end
        MEMORY_READ_DATA: begin
          if (pcim_rvalid) begin
            cpu_response_valid[transaction_node] <= 1'b1;
            cpu_response_rdata[transaction_node]
                <= pcim_rdata[transaction_lane*64 +: MDP_WORD_WIDTH];
            cpu_response_dram_error[transaction_node]
                <= pcim_rresp != 2'b00 || !pcim_rlast;
            if (pcim_rresp != 2'b00 || !pcim_rlast) read_error <= 1'b1;
            state <= MEMORY_IDLE;
          end
        end
        default: state <= MEMORY_IDLE;
      endcase
    end
  end

  property stable_aw_while_stalled;
    @(posedge clk) disable iff (reset)
      pcim_awvalid && !pcim_awready |=>
          pcim_awvalid && $stable({pcim_awaddr, pcim_awlen, pcim_awsize,
                                  pcim_awburst});
  endproperty
  assert property (stable_aw_while_stalled);

  property stable_w_while_stalled;
    @(posedge clk) disable iff (reset)
      pcim_wvalid && !pcim_wready |=>
          pcim_wvalid && $stable({pcim_wdata, pcim_wstrb, pcim_wlast});
  endproperty
  assert property (stable_w_while_stalled);

  property stable_ar_while_stalled;
    @(posedge clk) disable iff (reset)
      pcim_arvalid && !pcim_arready |=>
          pcim_arvalid && $stable({pcim_araddr, pcim_arlen, pcim_arsize,
                                  pcim_arburst});
  endproperty
  assert property (stable_ar_while_stalled);

  // These response identifiers/users are intentionally ignored because this
  // adapter permits exactly one outstanding transaction.
  logic unused_response_fields;
  assign unused_response_fields = ^{pcim_bid, pcim_rid, pcim_ruser};
endmodule
