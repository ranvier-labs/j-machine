module j_node (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic external_interrupt,

  output logic memory_request_valid,
  input  logic memory_request_ready,
  output logic memory_request_write,
  output j_machine_pkg::mdp_phys_addr_t memory_request_address,
  output j_machine_pkg::mdp_word_t memory_request_wdata,
  input  logic memory_response_valid,
  input  j_machine_pkg::mdp_word_t memory_response_rdata,
  input  logic memory_response_dram_error,

  input  logic qrb_ready,
  output logic qrb_write,
  output logic [j_machine_pkg::MDP_ADDR_WIDTH-3:0] qrb_row_address,
  output logic [j_machine_pkg::MDP_ROW_WIDTH-1:0] qrb_write_data,
  output logic [j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable,

  output logic [j_machine_pkg::J_PRIORITIES-1:0] network_tx_valid,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] network_tx_ready,
  output logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] network_tx_flit,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] network_tx_tail,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] network_rx_valid,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] network_rx_ready,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] network_rx_flit,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] network_rx_tail,

  output logic [15:0] node_number,
  output logic background,
  output logic current_priority,
  output logic interrupt_mask,
  output logic fault_mode,
  output logic unchecked_mode,
  output logic [4:0] last_fault,
  output logic catastrophe,
  output logic [63:0] retired_instructions,
  output j_machine_pkg::mdp_word_t debug_current_ip,
  output j_machine_pkg::mdp_word_t debug_r0,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_pending,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_full
);
  // Compile the identical processor/router endpoint once when the optional
  // hierarchical simulation target is selected. Synthesis treats this as a
  // comment, and the ordinary flat simulation target ignores it as well.
  /* verilator hier_block */
  import j_machine_pkg::*;

  logic [J_PRIORITIES-1:0] receive_word_valid;
  logic [J_PRIORITIES-1:0] receive_word_ready;
  logic [J_PRIORITIES-1:0][MDP_WORD_WIDTH-1:0] receive_word;
  logic [J_PRIORITIES-1:0] receive_word_tail;

  mdp_word_t qbm [J_PRIORITIES];
  mdp_word_t qhl [J_PRIORITIES];
  logic queue_register_write;
  logic queue_register_priority;
  logic queue_register_select_qhl;
  mdp_word_t queue_register_wdata;
  logic suspend_valid;
  logic suspend_priority;
  logic [9:0] suspend_message_length;
  logic suspend_ready;
  logic suspend_early;

  logic send_valid;
  logic send_ready;
  logic send_two;
  logic send_end;
  logic send_priority;
  mdp_word_t send_word0;
  mdp_word_t send_word1;

  mdp_network_input network_input (
    .clk,
    .reset,
    .link_valid(network_rx_valid),
    .link_ready(network_rx_ready),
    .link_flit(network_rx_flit),
    .link_tail(network_rx_tail),
    .word_valid(receive_word_valid),
    .word_ready(receive_word_ready),
    .word_data(receive_word),
    .word_tail(receive_word_tail)
  );

  mdp_message_unit message_unit (
    .clk,
    .reset,
    .qrb_ready,
    .receive_valid(receive_word_valid),
    .receive_ready(receive_word_ready),
    .receive_word,
    .receive_tail(receive_word_tail),
    .queue_register_write,
    .queue_register_priority,
    .queue_register_select_qhl,
    .queue_register_wdata,
    .qbm,
    .qhl,
    .suspend_valid,
    .suspend_priority,
    .suspend_message_length,
    .suspend_ready,
    .suspend_early,
    .queue_pending,
    .queue_full,
    .qrb_write,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable
  );

  mdp_network_output network_output (
    .clk,
    .reset,
    .local_node(node_number),
    .send_valid,
    .send_ready,
    .send_two,
    .send_end,
    .send_priority,
    .send_word0,
    .send_word1,
    .link_valid(network_tx_valid),
    .link_ready(network_tx_ready),
    .link_flit(network_tx_flit),
    .link_tail(network_tx_tail)
  );

  j_mdp_core core (
    .clk,
    .reset,
    .run_enable,
    .memory_request_valid,
    .memory_request_ready,
    .memory_request_write,
    .memory_request_address,
    .memory_request_wdata,
    .memory_response_valid,
    .memory_response_rdata,
    .memory_response_dram_error,
    .qbm,
    .qhl,
    .queue_pending,
    .queue_full,
    .queue_register_write,
    .queue_register_priority,
    .queue_register_select_qhl,
    .queue_register_wdata,
    .suspend_valid,
    .suspend_priority,
    .suspend_message_length,
    .suspend_ready,
    .suspend_early,
    .send_valid,
    .send_ready,
    .send_two,
    .send_end,
    .send_priority,
    .send_word0,
    .send_word1,
    .external_interrupt,
    .node_number,
    .background,
    .current_priority,
    .interrupt_mask,
    .fault_mode,
    .unchecked_mode,
    .last_fault,
    .catastrophe,
    .retired_instructions,
    .debug_current_ip,
    .debug_r0
  );
endmodule
