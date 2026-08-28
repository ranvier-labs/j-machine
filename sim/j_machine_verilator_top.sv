module j_machine_verilator_top (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,

  input  logic [1:0] external_interrupt,
  input  logic [1:0] dram_error_inject,
  input  logic [j_machine_pkg::MDP_ADDR_WIDTH-1:0] dram_error_address,

  input  logic debug_write,
  input  logic debug_node,
  input  logic [j_machine_pkg::MDP_ADDR_WIDTH-1:0] debug_address,
  input  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_wdata,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_rdata,

  output logic [15:0] node0_number,
  output logic [15:0] node1_number,
  output logic node0_catastrophe,
  output logic node1_catastrophe,
  output logic [4:0] node0_last_fault,
  output logic [4:0] node1_last_fault,
  output logic [63:0] node0_retired,
  output logic [63:0] node1_retired,
  output logic [35:0] node0_ip,
  output logic [35:0] node1_ip,
  output logic [35:0] node0_r0,
  output logic [35:0] node1_r0,
  output logic node0_background,
  output logic node1_background,
  output logic node0_priority,
  output logic node1_priority,
  output logic node0_interrupt_mask,
  output logic node1_interrupt_mask,
  output logic node0_fault_mode,
  output logic node1_fault_mode,
  output logic node0_unchecked_mode,
  output logic node1_unchecked_mode,
  output logic [1:0] node0_queue_pending,
  output logic [1:0] node1_queue_pending,
  output logic [1:0] node0_queue_full,
  output logic [1:0] node1_queue_full
);
  import j_machine_pkg::*;

  localparam int NODES = 2;
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
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] memory_debug_rdata;

  j_machine_mesh #(.X_SIZE(2), .Y_SIZE(1), .Z_SIZE(1)) mesh (
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

  generate
    for (genvar node_index = 0; node_index < NODES; node_index++) begin : memories
      mdp_memory_sim memory (
        .clk,
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
        .qrb_write_enable(qrb_write_enable[node_index]),
        .debug_write(debug_write && debug_node == node_index[0]),
        .debug_address,
        .debug_wdata,
        .debug_rdata(memory_debug_rdata[node_index]),
        .dram_error_inject(dram_error_inject[node_index]),
        .dram_error_address
      );
    end
  endgenerate

  assign debug_rdata = memory_debug_rdata[debug_node];
  assign node0_number = node_number[0];
  assign node1_number = node_number[1];
  assign node0_catastrophe = node_catastrophe[0];
  assign node1_catastrophe = node_catastrophe[1];
  assign node0_last_fault = node_last_fault[0];
  assign node1_last_fault = node_last_fault[1];
  assign node0_retired = node_retired_instructions[0];
  assign node1_retired = node_retired_instructions[1];
  assign node0_ip = node_debug_ip[0];
  assign node1_ip = node_debug_ip[1];
  assign node0_r0 = node_debug_r0[0];
  assign node1_r0 = node_debug_r0[1];
  assign node0_background = node_background[0];
  assign node1_background = node_background[1];
  assign node0_priority = node_priority[0];
  assign node1_priority = node_priority[1];
  assign node0_interrupt_mask = node_interrupt_mask[0];
  assign node1_interrupt_mask = node_interrupt_mask[1];
  assign node0_fault_mode = node_fault_mode[0];
  assign node1_fault_mode = node_fault_mode[1];
  assign node0_unchecked_mode = node_unchecked_mode[0];
  assign node1_unchecked_mode = node_unchecked_mode[1];
  assign node0_queue_pending = node_queue_pending[0];
  assign node1_queue_pending = node_queue_pending[1];
  assign node0_queue_full = node_queue_full[0];
  assign node1_queue_full = node_queue_full[1];
endmodule
