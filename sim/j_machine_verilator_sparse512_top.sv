// Fixed-size form of the sparse simulation top. Keeping the 8 x 8 x 8 shape
// out of command-line parameters lets Verilator compile j_node as a reusable
// hierarchical child without forwarding unrelated -G options to that child.
/* verilator lint_off DECLFILENAME */
module j_machine_verilator_sparse_top (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic [8:0] debug_node,

  output logic [15:0] debug_node_number,
  output logic debug_catastrophe,
  output logic [4:0] debug_last_fault,
  output logic [63:0] debug_retired,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_ip,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_r0,
  output logic debug_background,
  output logic debug_priority,
  output logic debug_interrupt_mask,
  output logic debug_fault_mode,
  output logic debug_unchecked_mode,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_pending,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_full,
  output logic any_catastrophe
);
  import j_machine_pkg::*;

  localparam int NODES = 512;

  logic [NODES-1:0] memory_request_valid;
  logic [NODES-1:0] memory_request_ready;
  logic [NODES-1:0] memory_request_write;
  logic [NODES-1:0][MDP_ADDR_WIDTH-1:0] memory_request_address;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] memory_request_wdata;
  logic [NODES-1:0] memory_response_valid;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] memory_response_rdata;
  logic [NODES-1:0] memory_response_dram_error;
  logic [NODES-1:0] qrb_write;
  logic [NODES-1:0][MDP_ADDR_WIDTH-3:0] qrb_row_address;
  logic [NODES-1:0][MDP_ROW_WIDTH-1:0] qrb_write_data;
  logic [NODES-1:0][MDP_ROW_WORDS-1:0] qrb_write_enable;
  logic [NODES-1:0][15:0] node_number;
  logic [NODES-1:0] node_background;
  logic [NODES-1:0] node_priority;
  logic [NODES-1:0] node_interrupt_mask;
  logic [NODES-1:0] node_fault_mode;
  logic [NODES-1:0] node_unchecked_mode;
  logic [NODES-1:0][4:0] node_last_fault;
  logic [NODES-1:0] node_catastrophe;
  logic [NODES-1:0][63:0] node_retired_instructions;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] node_debug_ip;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] node_debug_r0;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_queue_pending;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_queue_full;

  j_machine_mesh_512 mesh (
    .clk,
    .reset,
    .run_enable,
    .external_interrupt('0),
    .memory_request_valid,
    .memory_request_ready,
    .memory_request_write,
    .memory_request_address,
    .memory_request_wdata,
    .memory_response_valid,
    .memory_response_rdata,
    .memory_response_dram_error,
    .qrb_ready('1),
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

  for (genvar node_index = 0; node_index < NODES; node_index++) begin : memories
    mdp_sparse_memory_dpi #(.NODE_INDEX(node_index)) memory (
      .clk,
      .reset,
      .cpu_request_valid(memory_request_valid[node_index]),
      .cpu_request_ready(memory_request_ready[node_index]),
      .cpu_request_write(memory_request_write[node_index]),
      .cpu_request_address(memory_request_address[node_index]),
      .cpu_request_wdata(memory_request_wdata[node_index]),
      .cpu_response_valid(memory_response_valid[node_index]),
      .cpu_response_rdata(memory_response_rdata[node_index]),
      .cpu_response_dram_error(memory_response_dram_error[node_index]),
      .qrb_write(qrb_write[node_index]),
      .qrb_row_address(qrb_row_address[node_index]),
      .qrb_write_data(qrb_write_data[node_index]),
      .qrb_write_enable(qrb_write_enable[node_index])
    );
  end

  always_comb begin
    debug_node_number = node_number[debug_node];
    debug_catastrophe = node_catastrophe[debug_node];
    debug_last_fault = node_last_fault[debug_node];
    debug_retired = node_retired_instructions[debug_node];
    debug_ip = node_debug_ip[debug_node];
    debug_r0 = node_debug_r0[debug_node];
    debug_background = node_background[debug_node];
    debug_priority = node_priority[debug_node];
    debug_interrupt_mask = node_interrupt_mask[debug_node];
    debug_fault_mode = node_fault_mode[debug_node];
    debug_unchecked_mode = node_unchecked_mode[debug_node];
    debug_queue_pending = node_queue_pending[debug_node];
    debug_queue_full = node_queue_full[debug_node];
  end

  assign any_catastrophe = |node_catastrophe;
endmodule
/* verilator lint_on DECLFILENAME */
