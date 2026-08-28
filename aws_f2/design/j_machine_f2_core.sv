module j_machine_f2_core #(
  parameter int X_SIZE = 8,
  parameter int Y_SIZE = 8,
  parameter int Z_SIZE = 8,
  parameter int NODES = X_SIZE * Y_SIZE * Z_SIZE,
  parameter int NODE_INDEX_WIDTH = NODES <= 1 ? 1 : $clog2(NODES)
) (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic [63:0] host_memory_base,
  input  logic [NODE_INDEX_WIDTH-1:0] debug_node,
  input  logic clear_memory_errors,

  output logic memory_busy,
  output logic memory_write_error,
  output logic memory_read_error,
  output logic any_catastrophe,
  output logic [15:0] debug_node_number,
  output logic debug_background,
  output logic debug_priority,
  output logic debug_interrupt_mask,
  output logic debug_fault_mode,
  output logic debug_unchecked_mode,
  output logic [4:0] debug_last_fault,
  output logic debug_catastrophe,
  output logic [63:0] debug_retired_instructions,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_ip,
  output logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_r0,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_pending,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_full,

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

  logic [NODES-1:0] memory_request_valid;
  logic [NODES-1:0] memory_request_ready;
  logic [NODES-1:0] memory_request_write;
  logic [NODES-1:0][MDP_ADDR_WIDTH-1:0] memory_request_address;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] memory_request_wdata;
  logic [NODES-1:0] memory_response_valid;
  logic [NODES-1:0][MDP_WORD_WIDTH-1:0] memory_response_rdata;
  logic [NODES-1:0] memory_response_dram_error;
  logic [NODES-1:0] qrb_ready;
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

  j_machine_mesh #(
    .X_SIZE(X_SIZE),
    .Y_SIZE(Y_SIZE),
    .Z_SIZE(Z_SIZE)
  ) mesh (
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

  j_machine_f2_pcim_memory #(
    .NODES(NODES),
    .NODE_INDEX_WIDTH(NODE_INDEX_WIDTH)
  ) memory (
    .clk,
    .reset,
    .host_memory_base,
    .cpu_request_valid(memory_request_valid),
    .cpu_request_ready(memory_request_ready),
    .cpu_request_write(memory_request_write),
    .cpu_request_address(memory_request_address),
    .cpu_request_wdata(memory_request_wdata),
    .cpu_response_valid(memory_response_valid),
    .cpu_response_rdata(memory_response_rdata),
    .cpu_response_dram_error(memory_response_dram_error),
    .qrb_write,
    .qrb_ready,
    .qrb_row_address,
    .qrb_write_data,
    .qrb_write_enable,
    .busy(memory_busy),
    .write_error(memory_write_error),
    .read_error(memory_read_error),
    .clear_errors(clear_memory_errors),
    .pcim_awid,
    .pcim_awaddr,
    .pcim_awlen,
    .pcim_awsize,
    .pcim_awburst,
    .pcim_awcache,
    .pcim_awlock,
    .pcim_awprot,
    .pcim_awqos,
    .pcim_awuser,
    .pcim_awvalid,
    .pcim_awready,
    .pcim_wid,
    .pcim_wdata,
    .pcim_wstrb,
    .pcim_wlast,
    .pcim_wuser,
    .pcim_wvalid,
    .pcim_wready,
    .pcim_bid,
    .pcim_bresp,
    .pcim_bvalid,
    .pcim_bready,
    .pcim_arid,
    .pcim_araddr,
    .pcim_arlen,
    .pcim_arsize,
    .pcim_arburst,
    .pcim_arcache,
    .pcim_arlock,
    .pcim_arprot,
    .pcim_arqos,
    .pcim_aruser,
    .pcim_arvalid,
    .pcim_arready,
    .pcim_rid,
    .pcim_rdata,
    .pcim_rresp,
    .pcim_rlast,
    .pcim_ruser,
    .pcim_rvalid,
    .pcim_rready
  );

  always_comb begin
    any_catastrophe = |node_catastrophe;
    debug_node_number = node_number[debug_node];
    debug_background = node_background[debug_node];
    debug_priority = node_priority[debug_node];
    debug_interrupt_mask = node_interrupt_mask[debug_node];
    debug_fault_mode = node_fault_mode[debug_node];
    debug_unchecked_mode = node_unchecked_mode[debug_node];
    debug_last_fault = node_last_fault[debug_node];
    debug_catastrophe = node_catastrophe[debug_node];
    debug_retired_instructions = node_retired_instructions[debug_node];
    debug_ip = node_debug_ip[debug_node];
    debug_r0 = node_debug_r0[debug_node];
    debug_queue_pending = node_queue_pending[debug_node];
    debug_queue_full = node_queue_full[debug_node];
  end
endmodule
