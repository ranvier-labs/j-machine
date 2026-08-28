module j_node_backpressure_top (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic block_network,

  input  logic debug_write,
  input  logic [j_machine_pkg::MDP_ADDR_WIDTH-1:0] debug_address,
  input  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_wdata,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_rdata,

  output logic [15:0] node_number,
  output logic catastrophe,
  output logic [4:0] last_fault,
  output logic [63:0] retired_instructions,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_current_ip,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_r0,
  output logic background,
  output logic current_priority,
  output logic interrupt_mask,
  output logic fault_mode,
  output logic unchecked_mode,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_pending,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] queue_full,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] network_tx_valid,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] network_tx_tail
);
  import j_machine_pkg::*;

  logic memory_request_valid;
  logic memory_request_ready;
  logic memory_request_write;
  mdp_phys_addr_t memory_request_address;
  mdp_word_t memory_request_wdata;
  logic memory_response_valid;
  mdp_word_t memory_response_rdata;
  logic memory_response_dram_error;
  logic qrb_write;
  logic [MDP_ADDR_WIDTH-3:0] qrb_row_address;
  logic [MDP_ROW_WIDTH-1:0] qrb_write_data;
  logic [MDP_ROW_WORDS-1:0] qrb_write_enable;
  logic [J_PRIORITIES-1:0] network_tx_ready;
  logic [J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] network_tx_flit;
  logic [J_PRIORITIES-1:0] network_rx_ready;

  assign network_tx_ready = block_network ? '0 : '1;

  j_node node (
    .clk,
    .reset,
    .run_enable,
    .external_interrupt(1'b0),
    .memory_request_valid,
    .memory_request_ready,
    .memory_request_write,
    .memory_request_address,
    .memory_request_wdata,
    .memory_response_valid,
    .memory_response_rdata,
    .memory_response_dram_error,
    .qrb_ready(1'b1),
    .qrb_write,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable,
    .network_tx_valid,
    .network_tx_ready,
    .network_tx_flit,
    .network_tx_tail,
    .network_rx_valid('0),
    .network_rx_ready,
    .network_rx_flit('0),
    .network_rx_tail('0),
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
    .debug_r0,
    .queue_pending,
    .queue_full
  );

  mdp_memory_sim memory (
    .clk,
    .cpu_request_valid(memory_request_valid),
    .cpu_request_ready(memory_request_ready),
    .cpu_request_write(memory_request_write),
    .cpu_request_address(memory_request_address),
    .cpu_request_wdata(memory_request_wdata),
    .cpu_response_valid(memory_response_valid),
    .cpu_response_rdata(memory_response_rdata),
    .cpu_response_dram_error(memory_response_dram_error),
    .qrb_write,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable,
    .debug_write,
    .debug_address,
    .debug_wdata,
    .debug_rdata,
    .dram_error_inject(1'b0),
    .dram_error_address('0)
  );
endmodule
