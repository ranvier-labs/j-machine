module mdp_message_unit (
  input  logic clk,
  input  logic reset,

  // A target memory may arbitrate queue-row commits onto a shared physical
  // port. qrb_write is valid independent of qrb_ready; the committing receive
  // word and complete four-word row remain stable until the handshake.
  input  logic qrb_ready,

  input  logic [j_machine_pkg::J_PRIORITIES-1:0] receive_valid,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] receive_ready,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] receive_word,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] receive_tail,

  input  logic queue_register_write,
  input  logic queue_register_priority,
  input  logic queue_register_select_qhl,
  input  j_machine_pkg::mdp_word_t queue_register_wdata,
  output j_machine_pkg::mdp_word_t qbm [j_machine_pkg::J_PRIORITIES],
  output j_machine_pkg::mdp_word_t qhl [j_machine_pkg::J_PRIORITIES],

  input  logic suspend_valid,
  input  logic suspend_priority,
  input  logic [9:0] suspend_message_length,
  output logic suspend_ready,
  output logic suspend_early,

  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_pending,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_full,

  output logic qrb_write,
  output logic [j_machine_pkg::MDP_ADDR_WIDTH-3:0] qrb_row_address,
  output logic [j_machine_pkg::MDP_ROW_WIDTH-1:0] qrb_write_data,
  output logic [j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable
);
  import j_machine_pkg::*;

  mdp_word_t qbm_register [J_PRIORITIES];
  mdp_word_t qhl_register [J_PRIORITIES];
  mdp_word_t row_buffer [J_PRIORITIES][MDP_ROW_WORDS];
  logic [J_PRIORITIES-1:0][1:0] row_count;

  logic selected_receive_valid;
  logic selected_priority;
  logic selected_commit;
  logic [19:0] selected_tail_address;
  logic [19:0] selected_occupancy;
  logic direct_qrb_write;
  logic [MDP_ADDR_WIDTH-3:0] direct_qrb_row_address;
  logic [MDP_ROW_WIDTH-1:0] direct_qrb_write_data;
  logic [MDP_ROW_WORDS-1:0] direct_qrb_write_enable;
  logic qrb_pending;
  logic [MDP_ADDR_WIDTH-3:0] pending_qrb_row_address;
  logic [MDP_ROW_WIDTH-1:0] pending_qrb_write_data;
  logic [MDP_ROW_WORDS-1:0] pending_qrb_write_enable;

  always_comb begin
    for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
      qbm[priority_index] = qbm_register[priority_index];
      qhl[priority_index] = qhl_register[priority_index];
      queue_pending[priority_index] = qhl_register[priority_index][9:0] >= 4;
      queue_full[priority_index] =
          {10'b0, qhl_register[priority_index][9:0]}
          >= ({10'b0, qbm_register[priority_index][9:0]} + 20'd1);
    end
  end

  // Select a receive independently of downstream QRB readiness. Keeping this
  // cone independent is required by ready/valid and prevents a combinational
  // path from the shared memory arbiter back into qrb_write.
  always_comb begin
    selected_receive_valid = 1'b0;
    selected_priority = 1'b0;
    // Priority 1 owns the shared queue-row-buffer write port on a tie.
    for (int priority_index = J_PRIORITIES-1; priority_index >= 0; priority_index--) begin
      logic [10:0] capacity;
      logic [10:0] reserved;
      capacity = {1'b0, qbm_register[priority_index][9:0]} + 1'b1;
      reserved = {1'b0, qhl_register[priority_index][9:0]}
               + ((row_count[priority_index] != 0) ? 11'd4 : 11'd0);
      if (!selected_receive_valid && receive_valid[priority_index]
          && !qbm_register[priority_index][30]
          && (row_count[priority_index] != 0 || reserved + 4 <= capacity)
          && !(queue_register_write
               && queue_register_priority == priority_index[0])) begin
        selected_receive_valid = 1'b1;
        selected_priority = priority_index[0];
      end
    end

    selected_commit = selected_receive_valid
                    && (receive_tail[selected_priority]
                        || row_count[selected_priority] == 2'd3);
    selected_occupancy = {10'b0, qhl_register[selected_priority][9:0]};
    selected_tail_address = qbm_register[selected_priority][29:10]
        | ((qhl_register[selected_priority][29:10] + selected_occupancy)
           & {10'b0, qbm_register[selected_priority][9:0]});

    direct_qrb_write = selected_commit;
    direct_qrb_row_address = selected_tail_address[19:2];
    direct_qrb_write_data = '0;
    direct_qrb_write_enable = selected_commit ? 4'b1111 : 4'b0000;
    for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
      if (word_index < row_count[selected_priority]) begin
        direct_qrb_write_data[word_index*MDP_WORD_WIDTH +: MDP_WORD_WIDTH]
            = row_buffer[selected_priority][word_index];
      end else if (word_index[1:0] == row_count[selected_priority]
                   && selected_receive_valid) begin
        direct_qrb_write_data[word_index*MDP_WORD_WIDTH +: MDP_WORD_WIDTH]
            = receive_word[selected_priority];
      end else begin
        direct_qrb_write_data[word_index*MDP_WORD_WIDTH +: MDP_WORD_WIDTH]
            = mdp_word(MDP_TAG_SYM, 32'b0);
      end
    end
  end

  // A non-committing receive only updates the local row buffer. A committing
  // receive can flow directly to memory, occupy the pending register, or
  // replace that register in the cycle in which its old row is accepted.
  always_comb begin
    receive_ready = '0;
    if (selected_receive_valid) begin
      receive_ready[selected_priority] = !selected_commit
          || !qrb_pending || qrb_ready;
    end
  end

  always_comb begin
    if (qrb_pending) begin
      qrb_write = 1'b1;
      qrb_row_address = pending_qrb_row_address;
      qrb_write_data = pending_qrb_write_data;
      qrb_write_enable = pending_qrb_write_enable;
    end else begin
      qrb_write = direct_qrb_write;
      qrb_row_address = direct_qrb_row_address;
      qrb_write_data = direct_qrb_write_data;
      qrb_write_enable = direct_qrb_write_enable;
    end
  end

  always_comb begin
    suspend_ready = suspend_valid;
    suspend_early = 1'b0;
    if (suspend_valid) begin
      suspend_early = {10'b0, qhl_register[suspend_priority][9:0]}
                    < mdp_align4({10'b0, suspend_message_length});
    end
  end

  property stable_qrb_while_stalled;
    @(posedge clk) disable iff (reset)
      qrb_write && !qrb_ready |=>
          qrb_write && $stable({qrb_row_address, qrb_write_data,
                                qrb_write_enable});
  endproperty
  assert property (stable_qrb_while_stalled);

  always_ff @(posedge clk) begin
    if (reset) begin
      qrb_pending <= 1'b0;
      pending_qrb_row_address <= '0;
      pending_qrb_write_data <= '0;
      pending_qrb_write_enable <= '0;
      for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
        qbm_register[priority_index] <= mdp_addr(1'b0, 1'b1, 20'b0, 10'b0);
        qhl_register[priority_index] <= mdp_addr(1'b0, 1'b0, 20'b0, 10'b0);
        row_count[priority_index] <= '0;
        for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
          row_buffer[priority_index][word_index] <= '0;
        end
      end
    end else begin
      if (qrb_pending && qrb_ready) begin
        qrb_pending <= 1'b0;
      end

      if (queue_register_write) begin
        if (queue_register_select_qhl) begin
          qhl_register[queue_register_priority] <= queue_register_wdata;
        end else begin
          qbm_register[queue_register_priority] <= queue_register_wdata;
        end
      end

      if (selected_receive_valid && receive_ready[selected_priority]) begin
        if (selected_commit && (qrb_pending || !qrb_ready)) begin
          qrb_pending <= 1'b1;
          pending_qrb_row_address <= direct_qrb_row_address;
          pending_qrb_write_data <= direct_qrb_write_data;
          pending_qrb_write_enable <= direct_qrb_write_enable;
        end
        if (selected_commit) begin
          row_count[selected_priority] <= '0;
          qhl_register[selected_priority][9:0]
              <= qhl_register[selected_priority][9:0] + 10'd4;
        end else begin
          row_buffer[selected_priority][row_count[selected_priority]]
              <= receive_word[selected_priority];
          row_count[selected_priority] <= row_count[selected_priority] + 1'b1;
        end
      end

      if (suspend_valid && suspend_ready && !suspend_early) begin
        logic [19:0] allocated_length;
        logic [19:0] next_head;
        allocated_length = mdp_align4({10'b0, suspend_message_length});
        next_head = qbm_register[suspend_priority][29:10]
            | ((qhl_register[suspend_priority][29:10] + allocated_length)
               & {10'b0, qbm_register[suspend_priority][9:0]});
        qhl_register[suspend_priority][29:10] <= next_head;
        qhl_register[suspend_priority][9:0]
            <= qhl_register[suspend_priority][9:0] - allocated_length[9:0];
      end
    end
  end
endmodule
