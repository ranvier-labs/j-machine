module mdp_qrb_backpressure_test_top (
  input  logic clk,
  input  logic reset,
  input  logic configure_qbm,
  input  logic [35:0] qbm_value,
  input  logic receive_valid,
  output logic receive_ready,
  input  logic [35:0] receive_word,
  input  logic receive_tail,
  input  logic qrb_ready,
  output logic qrb_write,
  output logic [17:0] qrb_row_address,
  output logic [143:0] qrb_write_data,
  output logic [3:0] qrb_write_enable
);
  import j_machine_pkg::*;

  logic [J_PRIORITIES-1:0] receive_valid_vector;
  logic [J_PRIORITIES-1:0] receive_ready_vector;
  logic [J_PRIORITIES-1:0][MDP_WORD_WIDTH-1:0] receive_word_vector;
  logic [J_PRIORITIES-1:0] receive_tail_vector;
  mdp_word_t qbm [J_PRIORITIES];
  mdp_word_t qhl [J_PRIORITIES];
  logic [J_PRIORITIES-1:0] queue_pending;
  logic [J_PRIORITIES-1:0] queue_full;

  always_comb begin
    receive_valid_vector = '0;
    receive_valid_vector[0] = receive_valid;
    receive_word_vector = '0;
    receive_word_vector[0] = receive_word;
    receive_tail_vector = '0;
    receive_tail_vector[0] = receive_tail;
    receive_ready = receive_ready_vector[0];
  end

  mdp_message_unit dut (
    .clk,
    .reset,
    .qrb_ready,
    .receive_valid(receive_valid_vector),
    .receive_ready(receive_ready_vector),
    .receive_word(receive_word_vector),
    .receive_tail(receive_tail_vector),
    .queue_register_write(configure_qbm),
    .queue_register_priority(1'b0),
    .queue_register_select_qhl(1'b0),
    .queue_register_wdata(qbm_value),
    .qbm,
    .qhl,
    .suspend_valid(1'b0),
    .suspend_priority(1'b0),
    .suspend_message_length('0),
    .suspend_ready(),
    .suspend_early(),
    .queue_pending,
    .queue_full,
    .qrb_write,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable
  );
endmodule
