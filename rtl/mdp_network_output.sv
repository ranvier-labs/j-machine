module mdp_network_output #(
  parameter int FIFO_WORDS = 8
) (
  input  logic clk,
  input  logic reset,
  input  logic [15:0] local_node,

  input  logic send_valid,
  output logic send_ready,
  input  logic send_two,
  input  logic send_end,
  input  logic send_priority,
  input  j_machine_pkg::mdp_word_t send_word0,
  input  j_machine_pkg::mdp_word_t send_word1,

  output logic [j_machine_pkg::J_PRIORITIES-1:0] link_valid,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] link_ready,
  output logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] link_flit,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] link_tail
);
  import j_machine_pkg::*;

  localparam int PTR_WIDTH = (FIFO_WORDS <= 2) ? 1 : $clog2(FIFO_WORDS);
  localparam int COUNT_WIDTH = $clog2(FIFO_WORDS + 1);

  typedef enum logic [2:0] {
    TX_IDLE,
    TX_HEADER_X,
    TX_HEADER_Y,
    TX_HEADER_Z,
    TX_WORD_HIGH,
    TX_WORD_LOW
  } tx_state_t;

  mdp_word_t fifo_word [0:FIFO_WORDS-1];
  logic [FIFO_WORDS-1:0] fifo_tail;
  logic [FIFO_WORDS-1:0] fifo_head;
  logic [FIFO_WORDS-1:0] fifo_priority;
  logic [15:0] fifo_destination [0:FIFO_WORDS-1];
  logic [PTR_WIDTH-1:0] read_pointer;
  logic [PTR_WIDTH-1:0] write_pointer;
  logic [COUNT_WIDTH-1:0] fifo_count;

  logic building_message;
  logic [15:0] building_destination;
  logic building_priority;
  logic building_first_payload;
  logic [3:0] building_words;

  tx_state_t tx_state;
  logic tx_priority;
  logic [15:0] tx_destination;
  mdp_word_t tx_word;
  logic tx_word_tail;
  logic continuing_message;
  logic launchable;
  logic [3:0] words_before_tail;
  logic handshake;
  logic [COUNT_WIDTH-1:0] free_words;

  logic [5:0] local_x;
  logic [5:0] local_y;
  logic [5:0] local_z;
  logic [5:0] destination_x;
  logic [5:0] destination_y;
  logic [5:0] destination_z;

  assign local_x = {1'b0, local_node[4:0]};
  assign local_y = {1'b0, local_node[9:5]};
  assign local_z = local_node[15:10];
  assign destination_x = {1'b0, tx_destination[4:0]};
  assign destination_y = {1'b0, tx_destination[9:5]};
  assign destination_z = tx_destination[15:10];

  always_comb begin
    int needed_words;
    needed_words = send_two ? 2 : 1;
    if (!building_message) begin
      needed_words = needed_words - 1; // The routing word is not delivered.
    end
    free_words = COUNT_WIDTH'(FIFO_WORDS) - fifo_count;
    send_ready = (COUNT_WIDTH'(needed_words) <= free_words);

    launchable = 1'b0;
    words_before_tail = '0;
    for (int offset = 0; offset < FIFO_WORDS; offset++) begin
      if (offset < fifo_count && !launchable) begin
        words_before_tail = words_before_tail + 1'b1;
        if (fifo_tail[(int'(read_pointer) + offset) % FIFO_WORDS]) begin
          launchable = 1'b1;
        end
      end
    end
    if (words_before_tail >= 4) begin
      launchable = 1'b1;
    end

    link_valid = '0;
    link_flit = '0;
    link_tail = '0;
    if (tx_state != TX_IDLE) begin
      link_valid[tx_priority] = 1'b1;
      unique case (tx_state)
        TX_HEADER_X: link_flit[tx_priority] = j_header(
            J_DIM_X, destination_x > local_x, destination_x < local_x,
            destination_x);
        TX_HEADER_Y: link_flit[tx_priority] = j_header(
            J_DIM_Y, destination_y > local_y, destination_y < local_y,
            destination_y);
        TX_HEADER_Z: link_flit[tx_priority] = j_header(
            J_DIM_Z, destination_z > local_z, destination_z < local_z,
            destination_z);
        TX_WORD_HIGH: link_flit[tx_priority] = tx_word[35:18];
        TX_WORD_LOW: begin
          link_flit[tx_priority] = tx_word[17:0];
          link_tail[tx_priority] = tx_word_tail;
        end
        default: begin end
      endcase
    end
    handshake = link_valid[tx_priority] && link_ready[tx_priority];
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      read_pointer <= '0;
      write_pointer <= '0;
      fifo_count <= '0;
      fifo_tail <= '0;
      fifo_head <= '0;
      fifo_priority <= '0;
      building_message <= 1'b0;
      building_destination <= '0;
      building_priority <= 1'b0;
      building_first_payload <= 1'b0;
      building_words <= '0;
      tx_state <= TX_IDLE;
      tx_priority <= 1'b0;
      tx_destination <= '0;
      tx_word <= '0;
      tx_word_tail <= 1'b0;
      continuing_message <= 1'b0;
    end else begin
      int pushes;
      logic [PTR_WIDTH-1:0] push_pointer;
      logic local_building;
      logic [15:0] local_destination;
      logic local_priority;
      logic local_first;
      logic [3:0] local_words;

      pushes = 0;
      push_pointer = write_pointer;
      local_building = building_message;
      local_destination = building_destination;
      local_priority = building_priority;
      local_first = building_first_payload;
      local_words = building_words;

      if (send_valid && send_ready) begin
        for (int item = 0; item < 2; item++) begin
          if (item == 0 || send_two) begin
            mdp_word_t offered_word;
            offered_word = (item == 0) ? send_word0 : send_word1;
            if (!local_building) begin
              local_destination = offered_word[15:0];
              local_priority = send_priority;
              local_building = 1'b1;
              local_first = 1'b1;
              local_words = '0;
              // A routing word alone may not terminate an MDP message.
              assert (!(send_end && !send_two))
                else $error("SENDE used as a routing word without a message header");
            end else begin
              fifo_word[push_pointer] <= offered_word;
              fifo_tail[push_pointer] <= send_end && (item == (send_two ? 1 : 0));
              fifo_head[push_pointer] <= local_first;
              fifo_priority[push_pointer] <= local_priority;
              fifo_destination[push_pointer] <= local_destination;
              push_pointer = push_pointer + 1'b1;
              pushes = pushes + 1;
              local_first = 1'b0;
              local_words = local_words + 1'b1;
              if (send_end && (item == (send_two ? 1 : 0))) begin
                local_building = 1'b0;
                local_words = '0;
              end
            end
          end
        end
      end

      building_message <= local_building;
      building_destination <= local_destination;
      building_priority <= local_priority;
      building_first_payload <= local_first;
      building_words <= local_words;
      if (pushes != 0) begin
        write_pointer <= push_pointer;
      end

      unique case (tx_state)
        TX_IDLE: begin
          if (fifo_count != 0 && continuing_message) begin
            tx_word <= fifo_word[read_pointer];
            tx_word_tail <= fifo_tail[read_pointer];
            tx_state <= TX_WORD_HIGH;
          end else if (fifo_count != 0 && fifo_head[read_pointer] && launchable) begin
            tx_priority <= fifo_priority[read_pointer];
            tx_destination <= fifo_destination[read_pointer];
            tx_word <= fifo_word[read_pointer];
            tx_word_tail <= fifo_tail[read_pointer];
            continuing_message <= 1'b1;
            tx_state <= TX_HEADER_X;
          end
        end
        TX_HEADER_X: if (handshake) tx_state <= TX_HEADER_Y;
        TX_HEADER_Y: if (handshake) tx_state <= TX_HEADER_Z;
        TX_HEADER_Z: if (handshake) tx_state <= TX_WORD_HIGH;
        TX_WORD_HIGH: if (handshake) tx_state <= TX_WORD_LOW;
        TX_WORD_LOW: begin
          if (handshake) begin
            read_pointer <= read_pointer + 1'b1;
            if (tx_word_tail) begin
              continuing_message <= 1'b0;
              tx_state <= TX_IDLE;
            end else if (fifo_count > 1) begin
              tx_word <= fifo_word[read_pointer + 1'b1];
              tx_word_tail <= fifo_tail[read_pointer + 1'b1];
              tx_state <= TX_WORD_HIGH;
            end else begin
              // A message may have launched when the FIFO became half full.
              // Wait for the producer without inserting an invalid flit.
              tx_state <= TX_IDLE;
            end
          end
        end
        default: tx_state <= TX_IDLE;
      endcase

      unique case ({pushes != 0, tx_state == TX_WORD_LOW && handshake})
        2'b10: fifo_count <= fifo_count + COUNT_WIDTH'(pushes);
        2'b01: fifo_count <= fifo_count - 1'b1;
        2'b11: fifo_count <= fifo_count + COUNT_WIDTH'(pushes) - 1'b1;
        default: begin end
      endcase
    end
  end
endmodule
