module j_machine_mesh_512 (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic [511:0] external_interrupt,

  output logic [511:0] memory_request_valid,
  input  logic [511:0] memory_request_ready,
  output logic [511:0] memory_request_write,
  output logic [511:0][j_machine_pkg::MDP_ADDR_WIDTH-1:0] memory_request_address,
  output logic [511:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] memory_request_wdata,
  input  logic [511:0] memory_response_valid,
  input  logic [511:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] memory_response_rdata,
  input  logic [511:0] memory_response_dram_error,

  input  logic [511:0] qrb_ready,
  output logic [511:0] qrb_write,
  output logic [511:0][j_machine_pkg::MDP_ADDR_WIDTH-3:0] qrb_row_address,
  output logic [511:0][j_machine_pkg::MDP_ROW_WIDTH-1:0] qrb_write_data,
  output logic [511:0][j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable,

  output logic [511:0][15:0] node_number,
  output logic [511:0] node_background,
  output logic [511:0] node_priority,
  output logic [511:0] node_interrupt_mask,
  output logic [511:0] node_fault_mode,
  output logic [511:0] node_unchecked_mode,
  output logic [511:0][4:0] node_last_fault,
  output logic [511:0] node_catastrophe,
  output logic [511:0][63:0] node_retired_instructions,
  output logic [511:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] node_debug_ip,
  output logic [511:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] node_debug_r0,
  output logic [511:0][j_machine_pkg::J_PRIORITIES-1:0] node_queue_pending,
  output logic [511:0][j_machine_pkg::J_PRIORITIES-1:0] node_queue_full
);
  // The historical 512-node configuration is a true 8 x 8 x 8 mesh. Node
  // numbering remains x + 8 * (y + 8 * z), so node 511 is coordinate (7,7,7).
  j_machine_mesh #(
    .X_SIZE(8),
    .Y_SIZE(8),
    .Z_SIZE(8)
  ) mesh (
    .clk,
    .reset,
    .run_enable,
    .external_interrupt,
    .memory_request_valid,
    .memory_request_ready,
    .memory_request_write,
    .memory_request_address,
    .memory_request_wdata,
    .memory_response_valid,
    .memory_response_rdata,
    .memory_response_dram_error,
    .qrb_ready,
    .qrb_write,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable,
    .node_number,
    .node_background,
    .node_priority,
    .node_interrupt_mask,
    .node_fault_mode,
    .node_unchecked_mode,
    .node_last_fault,
    .node_catastrophe,
    .node_retired_instructions,
    .node_debug_ip,
    .node_debug_r0,
    .node_queue_pending,
    .node_queue_full
  );
endmodule
