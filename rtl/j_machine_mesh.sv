module j_machine_mesh #(
  parameter int X_SIZE = 2,
  parameter int Y_SIZE = 1,
  parameter int Z_SIZE = 1,
  parameter int NODES = X_SIZE * Y_SIZE * Z_SIZE
) (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,
  input  logic [NODES-1:0] external_interrupt,

  output logic [NODES-1:0] memory_request_valid,
  input  logic [NODES-1:0] memory_request_ready,
  output logic [NODES-1:0] memory_request_write,
  output logic [NODES-1:0][j_machine_pkg::MDP_ADDR_WIDTH-1:0] memory_request_address,
  output logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] memory_request_wdata,
  input  logic [NODES-1:0] memory_response_valid,
  input  logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] memory_response_rdata,
  input  logic [NODES-1:0] memory_response_dram_error,

  input  logic [NODES-1:0] qrb_ready,
  output logic [NODES-1:0] qrb_write,
  output logic [NODES-1:0][j_machine_pkg::MDP_ADDR_WIDTH-3:0] qrb_row_address,
  output logic [NODES-1:0][j_machine_pkg::MDP_ROW_WIDTH-1:0] qrb_write_data,
  output logic [NODES-1:0][j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable,

  output logic [NODES-1:0][15:0] node_number,
  output logic [NODES-1:0] node_background,
  output logic [NODES-1:0] node_priority,
  output logic [NODES-1:0] node_interrupt_mask,
  output logic [NODES-1:0] node_fault_mode,
  output logic [NODES-1:0] node_unchecked_mode,
  output logic [NODES-1:0][4:0] node_last_fault,
  output logic [NODES-1:0] node_catastrophe,
  output logic [NODES-1:0][63:0] node_retired_instructions,
  output logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] node_debug_ip,
  output logic [NODES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] node_debug_r0,
  output logic [NODES-1:0] node_debug_fetch,
  output logic [NODES-1:0][7:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] node_debug_registers,
  output logic [NODES-1:0][j_machine_pkg::J_PRIORITIES-1:0] node_queue_pending,
  output logic [NODES-1:0][j_machine_pkg::J_PRIORITIES-1:0] node_queue_full
);
  import j_machine_pkg::*;

  logic [NODES-1:0][J_PRIORITIES-1:0] node_tx_valid;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_tx_ready;
  logic [NODES-1:0][J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] node_tx_flit;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_tx_tail;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_rx_valid;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_rx_ready;
  logic [NODES-1:0][J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] node_rx_flit;
  logic [NODES-1:0][J_PRIORITIES-1:0] node_rx_tail;

  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_in_valid;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_in_ready;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] router_in_flit;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_in_tail;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_out_valid;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_out_ready;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] router_out_flit;
  logic [NODES-1:0][J_PORTS-1:0][J_PRIORITIES-1:0] router_out_tail;

  generate
    for (genvar z = 0; z < Z_SIZE; z++) begin : gen_z
      for (genvar y = 0; y < Y_SIZE; y++) begin : gen_y
        for (genvar x = 0; x < X_SIZE; x++) begin : gen_x
          localparam int ID = x + X_SIZE * (y + Y_SIZE * z);

          j_node node (
            .clk,
            .reset,
            .run_enable,
            .external_interrupt(external_interrupt[ID]),
            .memory_request_valid(memory_request_valid[ID]),
            .memory_request_ready(memory_request_ready[ID]),
            .memory_request_write(memory_request_write[ID]),
            .memory_request_address(memory_request_address[ID]),
            .memory_request_wdata(memory_request_wdata[ID]),
            .memory_response_valid(memory_response_valid[ID]),
            .memory_response_rdata(memory_response_rdata[ID]),
            .memory_response_dram_error(memory_response_dram_error[ID]),
            .qrb_ready(qrb_ready[ID]),
            .qrb_write(qrb_write[ID]),
            .qrb_row_address(qrb_row_address[ID]),
            .qrb_write_data(qrb_write_data[ID]),
            .qrb_write_enable(qrb_write_enable[ID]),
            .network_tx_valid(node_tx_valid[ID]),
            .network_tx_ready(node_tx_ready[ID]),
            .network_tx_flit(node_tx_flit[ID]),
            .network_tx_tail(node_tx_tail[ID]),
            .network_rx_valid(node_rx_valid[ID]),
            .network_rx_ready(node_rx_ready[ID]),
            .network_rx_flit(node_rx_flit[ID]),
            .network_rx_tail(node_rx_tail[ID]),
            .node_number(node_number[ID]),
            .background(node_background[ID]),
            .current_priority(node_priority[ID]),
            .interrupt_mask(node_interrupt_mask[ID]),
            .fault_mode(node_fault_mode[ID]),
            .unchecked_mode(node_unchecked_mode[ID]),
            .last_fault(node_last_fault[ID]),
            .catastrophe(node_catastrophe[ID]),
            .retired_instructions(node_retired_instructions[ID]),
            .debug_current_ip(node_debug_ip[ID]),
            .debug_r0(node_debug_r0[ID]),
            .debug_fetch(node_debug_fetch[ID]),
            .debug_registers(node_debug_registers[ID]),
            .queue_pending(node_queue_pending[ID]),
            .queue_full(node_queue_full[ID])
          );

          j_mesh_router #(
            .X_COORD(x),
            .Y_COORD(y),
            .Z_COORD(z)
          ) router (
            .clk,
            .reset,
            .in_valid(router_in_valid[ID]),
            .in_ready(router_in_ready[ID]),
            .in_flit(router_in_flit[ID]),
            .in_tail(router_in_tail[ID]),
            .out_valid(router_out_valid[ID]),
            .out_ready(router_out_ready[ID]),
            .out_flit(router_out_flit[ID]),
            .out_tail(router_out_tail[ID])
          );

          assign router_in_valid[ID][J_PORT_LOCAL] = node_tx_valid[ID];
          assign router_in_flit[ID][J_PORT_LOCAL] = node_tx_flit[ID];
          assign router_in_tail[ID][J_PORT_LOCAL] = node_tx_tail[ID];
          assign node_tx_ready[ID] = router_in_ready[ID][J_PORT_LOCAL];
          assign node_rx_valid[ID] = router_out_valid[ID][J_PORT_LOCAL];
          assign node_rx_flit[ID] = router_out_flit[ID][J_PORT_LOCAL];
          assign node_rx_tail[ID] = router_out_tail[ID][J_PORT_LOCAL];
          assign router_out_ready[ID][J_PORT_LOCAL] = node_rx_ready[ID];

          if (x > 0) begin : gen_x_neg
            localparam int NEIGHBOR = ID - 1;
            assign router_in_valid[ID][J_PORT_X_NEG]
                = router_out_valid[NEIGHBOR][J_PORT_X_POS];
            assign router_in_flit[ID][J_PORT_X_NEG]
                = router_out_flit[NEIGHBOR][J_PORT_X_POS];
            assign router_in_tail[ID][J_PORT_X_NEG]
                = router_out_tail[NEIGHBOR][J_PORT_X_POS];
            assign router_out_ready[ID][J_PORT_X_NEG]
                = router_in_ready[NEIGHBOR][J_PORT_X_POS];
          end else begin : gen_no_x_neg
            assign router_in_valid[ID][J_PORT_X_NEG] = '0;
            assign router_in_flit[ID][J_PORT_X_NEG] = '0;
            assign router_in_tail[ID][J_PORT_X_NEG] = '0;
            assign router_out_ready[ID][J_PORT_X_NEG] = '0;
          end

          if (x + 1 < X_SIZE) begin : gen_x_pos
            localparam int NEIGHBOR = ID + 1;
            assign router_in_valid[ID][J_PORT_X_POS]
                = router_out_valid[NEIGHBOR][J_PORT_X_NEG];
            assign router_in_flit[ID][J_PORT_X_POS]
                = router_out_flit[NEIGHBOR][J_PORT_X_NEG];
            assign router_in_tail[ID][J_PORT_X_POS]
                = router_out_tail[NEIGHBOR][J_PORT_X_NEG];
            assign router_out_ready[ID][J_PORT_X_POS]
                = router_in_ready[NEIGHBOR][J_PORT_X_NEG];
          end else begin : gen_no_x_pos
            assign router_in_valid[ID][J_PORT_X_POS] = '0;
            assign router_in_flit[ID][J_PORT_X_POS] = '0;
            assign router_in_tail[ID][J_PORT_X_POS] = '0;
            assign router_out_ready[ID][J_PORT_X_POS] = '0;
          end

          if (y > 0) begin : gen_y_neg
            localparam int NEIGHBOR = ID - X_SIZE;
            assign router_in_valid[ID][J_PORT_Y_NEG]
                = router_out_valid[NEIGHBOR][J_PORT_Y_POS];
            assign router_in_flit[ID][J_PORT_Y_NEG]
                = router_out_flit[NEIGHBOR][J_PORT_Y_POS];
            assign router_in_tail[ID][J_PORT_Y_NEG]
                = router_out_tail[NEIGHBOR][J_PORT_Y_POS];
            assign router_out_ready[ID][J_PORT_Y_NEG]
                = router_in_ready[NEIGHBOR][J_PORT_Y_POS];
          end else begin : gen_no_y_neg
            assign router_in_valid[ID][J_PORT_Y_NEG] = '0;
            assign router_in_flit[ID][J_PORT_Y_NEG] = '0;
            assign router_in_tail[ID][J_PORT_Y_NEG] = '0;
            assign router_out_ready[ID][J_PORT_Y_NEG] = '0;
          end

          if (y + 1 < Y_SIZE) begin : gen_y_pos
            localparam int NEIGHBOR = ID + X_SIZE;
            assign router_in_valid[ID][J_PORT_Y_POS]
                = router_out_valid[NEIGHBOR][J_PORT_Y_NEG];
            assign router_in_flit[ID][J_PORT_Y_POS]
                = router_out_flit[NEIGHBOR][J_PORT_Y_NEG];
            assign router_in_tail[ID][J_PORT_Y_POS]
                = router_out_tail[NEIGHBOR][J_PORT_Y_NEG];
            assign router_out_ready[ID][J_PORT_Y_POS]
                = router_in_ready[NEIGHBOR][J_PORT_Y_NEG];
          end else begin : gen_no_y_pos
            assign router_in_valid[ID][J_PORT_Y_POS] = '0;
            assign router_in_flit[ID][J_PORT_Y_POS] = '0;
            assign router_in_tail[ID][J_PORT_Y_POS] = '0;
            assign router_out_ready[ID][J_PORT_Y_POS] = '0;
          end

          if (z > 0) begin : gen_z_neg
            localparam int NEIGHBOR = ID - X_SIZE * Y_SIZE;
            assign router_in_valid[ID][J_PORT_Z_NEG]
                = router_out_valid[NEIGHBOR][J_PORT_Z_POS];
            assign router_in_flit[ID][J_PORT_Z_NEG]
                = router_out_flit[NEIGHBOR][J_PORT_Z_POS];
            assign router_in_tail[ID][J_PORT_Z_NEG]
                = router_out_tail[NEIGHBOR][J_PORT_Z_POS];
            assign router_out_ready[ID][J_PORT_Z_NEG]
                = router_in_ready[NEIGHBOR][J_PORT_Z_POS];
          end else begin : gen_no_z_neg
            assign router_in_valid[ID][J_PORT_Z_NEG] = '0;
            assign router_in_flit[ID][J_PORT_Z_NEG] = '0;
            assign router_in_tail[ID][J_PORT_Z_NEG] = '0;
            assign router_out_ready[ID][J_PORT_Z_NEG] = '0;
          end

          if (z + 1 < Z_SIZE) begin : gen_z_pos
            localparam int NEIGHBOR = ID + X_SIZE * Y_SIZE;
            assign router_in_valid[ID][J_PORT_Z_POS]
                = router_out_valid[NEIGHBOR][J_PORT_Z_NEG];
            assign router_in_flit[ID][J_PORT_Z_POS]
                = router_out_flit[NEIGHBOR][J_PORT_Z_NEG];
            assign router_in_tail[ID][J_PORT_Z_POS]
                = router_out_tail[NEIGHBOR][J_PORT_Z_NEG];
            assign router_out_ready[ID][J_PORT_Z_POS]
                = router_in_ready[NEIGHBOR][J_PORT_Z_NEG];
          end else begin : gen_no_z_pos
            assign router_in_valid[ID][J_PORT_Z_POS] = '0;
            assign router_in_flit[ID][J_PORT_Z_POS] = '0;
            assign router_in_tail[ID][J_PORT_Z_POS] = '0;
            assign router_out_ready[ID][J_PORT_Z_POS] = '0;
          end
        end
      end
    end
  endgenerate
endmodule
