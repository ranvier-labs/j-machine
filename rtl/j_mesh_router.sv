module j_mesh_router #(
  parameter int X_COORD = 0,
  parameter int Y_COORD = 0,
  parameter int Z_COORD = 0
) (
  input  logic clk,
  input  logic reset,

  input  logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] in_valid,
  output logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] in_ready,
  input  logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] in_flit,
  input  logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] in_tail,

  output logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] out_valid,
  input  logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] out_ready,
  output logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] out_flit,
  output logic [j_machine_pkg::J_PORTS-1:0][j_machine_pkg::J_PRIORITIES-1:0] out_tail
);
  import j_machine_pkg::*;

  logic [J_PORTS-1:0][J_PRIORITIES-1:0] buffer_valid;
  j_flit_t buffer_flit [J_PORTS][J_PRIORITIES];
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] buffer_tail;

  // There is one lock per virtual network per output.  The physical output
  // selects priority 1 whenever it is ready, preempting but not destroying a
  // priority-0 wormhole reservation.
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] lock_valid;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0][2:0] lock_port;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] lock_input_priority;

  logic [J_PORTS-1:0][J_PRIORITIES-1:0] grant_valid;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0][2:0] grant_port;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] grant_input_priority;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] dequeue;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] strip_header;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0] input_locked;
  logic [J_PORTS-1:0][J_PRIORITIES-1:0][1:0] expected_dimension;

  function automatic logic [2:0] input_dimension(input int port);
    unique case (port)
      J_PORT_LOCAL: input_dimension = 3'd0;
      J_PORT_X_NEG, J_PORT_X_POS: input_dimension = 3'd0;
      J_PORT_Y_NEG, J_PORT_Y_POS: input_dimension = 3'd1;
      default: input_dimension = 3'd2;
    endcase
  endfunction

  function automatic logic [2:0] requested_output(
      input logic [1:0] expected,
      input j_flit_t flit
  );
    logic [1:0] dimension;
    logic [5:0] coordinate;
    begin
      dimension = flit[J_HEADER_DIM_MSB:J_HEADER_DIM_LSB];
      coordinate = flit[J_HEADER_COORD_MSB:J_HEADER_COORD_LSB];
      if (expected != J_DIM_DATA && flit[J_HEADER_MARK_BIT]
          && dimension == expected) begin
        unique case (dimension)
          J_DIM_X: begin
            if (coordinate < X_COORD[5:0]) requested_output = J_PORT_X_NEG[2:0];
            else if (coordinate > X_COORD[5:0]) requested_output = J_PORT_X_POS[2:0];
            else requested_output = J_PORT_LOCAL[2:0];
          end
          J_DIM_Y: begin
            if (coordinate < Y_COORD[5:0]) requested_output = J_PORT_Y_NEG[2:0];
            else if (coordinate > Y_COORD[5:0]) requested_output = J_PORT_Y_POS[2:0];
            else requested_output = J_PORT_LOCAL[2:0];
          end
          default: begin
            if (coordinate < Z_COORD[5:0]) requested_output = J_PORT_Z_NEG[2:0];
            else if (coordinate > Z_COORD[5:0]) requested_output = J_PORT_Z_POS[2:0];
            else requested_output = J_PORT_LOCAL[2:0];
          end
        endcase
      end else begin
        requested_output = J_PORT_LOCAL[2:0];
      end
    end
  endfunction

  function automatic logic matching_dimension_header(
      input logic [1:0] expected,
      input j_flit_t flit
  );
    logic [1:0] header_dimension;
    logic coordinate_matches;
    begin
      header_dimension = flit[J_HEADER_DIM_MSB:J_HEADER_DIM_LSB];
      unique case (header_dimension)
        J_DIM_X: coordinate_matches =
            flit[J_HEADER_COORD_MSB:J_HEADER_COORD_LSB] == X_COORD[5:0];
        J_DIM_Y: coordinate_matches =
            flit[J_HEADER_COORD_MSB:J_HEADER_COORD_LSB] == Y_COORD[5:0];
        J_DIM_Z: coordinate_matches =
            flit[J_HEADER_COORD_MSB:J_HEADER_COORD_LSB] == Z_COORD[5:0];
        default: coordinate_matches = 1'b0;
      endcase
      matching_dimension_header = flit[J_HEADER_MARK_BIT]
          && expected != J_DIM_DATA
          && header_dimension == expected
          && coordinate_matches;
    end
  endfunction

  assign in_ready = ~buffer_valid;

  always_comb begin
    grant_valid = '0;
    grant_port = '0;
    grant_input_priority = '0;
    dequeue = '0;
    strip_header = '0;
    input_locked = '0;
    out_valid = '0;
    out_flit = '0;
    out_tail = '0;

    // A matching routing header is consumed at this node.  Headers for the
    // next dimension then become the head flit seen by the corresponding
    // dimension router, exactly as in the physical three-router pipeline.
    for (int output_port = 0; output_port < J_PORTS; output_port++) begin
      for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
        if (lock_valid[output_port][priority_index]) begin
          input_locked[lock_port[output_port][priority_index]]
                      [lock_input_priority[output_port][priority_index]] = 1'b1;
        end
      end
    end

    for (int input_port = 0; input_port < J_PORTS; input_port++) begin
      for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
        if (buffer_valid[input_port][priority_index]
            && !input_locked[input_port][priority_index]
            && matching_dimension_header(expected_dimension[input_port][priority_index],
                                         buffer_flit[input_port][priority_index])) begin
          strip_header[input_port][priority_index] = 1'b1;
          dequeue[input_port][priority_index] = 1'b1;
        end
      end
    end

    for (int output_port = 0; output_port < J_PORTS; output_port++) begin
      for (int priority_index = J_PRIORITIES-1; priority_index >= 0; priority_index--) begin
        if (lock_valid[output_port][priority_index]) begin
          if (buffer_valid[lock_port[output_port][priority_index]]
                          [lock_input_priority[output_port][priority_index]]) begin
            grant_valid[output_port][priority_index] = 1'b1;
            grant_port[output_port][priority_index]
                = lock_port[output_port][priority_index];
            grant_input_priority[output_port][priority_index]
                = lock_input_priority[output_port][priority_index];
          end
        end else begin
          for (int input_port = 0; input_port < J_PORTS; input_port++) begin
            if (!grant_valid[output_port][priority_index]
                && buffer_valid[input_port][priority_index]
                && !input_locked[input_port][priority_index]
                && !strip_header[input_port][priority_index]
                && requested_output(expected_dimension[input_port][priority_index],
                                    buffer_flit[input_port][priority_index])
                   == output_port[2:0]) begin
              grant_valid[output_port][priority_index] = 1'b1;
              grant_port[output_port][priority_index] = input_port[2:0];
              grant_input_priority[output_port][priority_index] = priority_index[0];
            end
          end
        end
      end

      // Only one virtual network drives a physical output in a cycle.
      if (grant_valid[output_port][1]) begin
        out_valid[output_port][1] = 1'b1;
        out_flit[output_port][1]
            = buffer_flit[grant_port[output_port][1]][grant_input_priority[output_port][1]];
        out_tail[output_port][1]
            = buffer_tail[grant_port[output_port][1]][grant_input_priority[output_port][1]];
        if (out_ready[output_port][1]) begin
          dequeue[grant_port[output_port][1]][grant_input_priority[output_port][1]] = 1'b1;
        end
      end else if (grant_valid[output_port][0]) begin
        out_valid[output_port][0] = 1'b1;
        out_flit[output_port][0]
            = buffer_flit[grant_port[output_port][0]][grant_input_priority[output_port][0]];
        out_tail[output_port][0]
            = buffer_tail[grant_port[output_port][0]][grant_input_priority[output_port][0]];
        if (out_ready[output_port][0]) begin
          dequeue[grant_port[output_port][0]][grant_input_priority[output_port][0]] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      buffer_valid <= '0;
      buffer_tail <= '0;
      lock_valid <= '0;
      lock_port <= '0;
      lock_input_priority <= '0;
      for (int input_port = 0; input_port < J_PORTS; input_port++) begin
        for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
          expected_dimension[input_port][priority_index]
              <= input_dimension(input_port)[1:0];
        end
      end
    end else begin
      for (int input_port = 0; input_port < J_PORTS; input_port++) begin
        for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
          if (dequeue[input_port][priority_index]) begin
            buffer_valid[input_port][priority_index] <= 1'b0;
          end
          if (strip_header[input_port][priority_index]) begin
            if (expected_dimension[input_port][priority_index] == J_DIM_Z) begin
              expected_dimension[input_port][priority_index] <= J_DIM_DATA;
            end else begin
              expected_dimension[input_port][priority_index]
                  <= expected_dimension[input_port][priority_index] + 1'b1;
            end
          end
          if (in_valid[input_port][priority_index]
              && in_ready[input_port][priority_index]) begin
            buffer_valid[input_port][priority_index] <= 1'b1;
            buffer_flit[input_port][priority_index] <= in_flit[input_port][priority_index];
            buffer_tail[input_port][priority_index] <= in_tail[input_port][priority_index];
          end
          if (dequeue[input_port][priority_index]
              && buffer_tail[input_port][priority_index]) begin
            expected_dimension[input_port][priority_index]
                <= input_dimension(input_port)[1:0];
          end
        end
      end

      for (int output_port = 0; output_port < J_PORTS; output_port++) begin
        for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
          if (out_valid[output_port][priority_index]
              && out_ready[output_port][priority_index]) begin
            if (out_tail[output_port][priority_index]) begin
              lock_valid[output_port][priority_index] <= 1'b0;
            end else if (!lock_valid[output_port][priority_index]) begin
              lock_valid[output_port][priority_index] <= 1'b1;
              lock_port[output_port][priority_index]
                  <= grant_port[output_port][priority_index];
              lock_input_priority[output_port][priority_index]
                  <= grant_input_priority[output_port][priority_index];
            end
          end
        end
      end
    end
  end
`ifdef J_MACHINE_NETWORK_TRACE
  // Sample pre-edge handshakes, once per simulated clock. Kept out of synthesis
  // and normal RTL targets. Records are interpreted after the entire edge.
  import "DPI-C" function void jmc_trace_router(
      input int unsigned node, kind, port, priority_index, aux, flit, flags);
  localparam int TRACE_NODE = X_COORD | (Y_COORD << 5) | (Z_COORD << 10);
  always @(posedge clk) begin
    if (!reset) begin
      for (int p = 0; p < J_PORTS; p++) begin
        for (int v = 0; v < J_PRIORITIES; v++) begin
          if (in_valid[p][v] && in_ready[p][v])
            jmc_trace_router(TRACE_NODE, 1, p, v, 0, int'(in_flit[p][v]), int'(in_tail[p][v]));
          if (out_valid[p][v] && out_ready[p][v])
            jmc_trace_router(TRACE_NODE, 2, p, v,
                int'(grant_port[p][v]) | (int'(grant_input_priority[p][v]) << 8),
                int'(out_flit[p][v]), int'(out_tail[p][v]));
          if (strip_header[p][v])
            jmc_trace_router(TRACE_NODE, 3, p, v, int'(expected_dimension[p][v]),
                int'(buffer_flit[p][v]), int'(buffer_tail[p][v]));
          if (buffer_valid[p][v] && !dequeue[p][v]) begin
            int dest;
            int reason;
            dest = int'(requested_output(expected_dimension[p][v], buffer_flit[p][v]));
            for (int o = 0; o < J_PORTS; o++)
              if (lock_valid[o][v] && lock_port[o][v] == p[2:0]
                  && lock_input_priority[o][v] == v[0]) dest = o;
            reason = 4; // Another input won arbitration.
            if (lock_valid[dest][v] && lock_port[dest][v] != p[2:0]) reason = 3;
            if (grant_valid[dest][v] && grant_port[dest][v] == p[2:0]) begin
              if (!out_valid[dest][v]) reason = 2; // Priority 1 owns the physical link.
              else if (!out_ready[dest][v]) reason = 1; // Downstream backpressure.
            end
            jmc_trace_router(TRACE_NODE, 4, p, v, dest, int'(buffer_flit[p][v]), reason);
          end
          if (lock_valid[p][v] && !buffer_valid[lock_port[p][v]][lock_input_priority[p][v]])
            jmc_trace_router(TRACE_NODE, 5, p, v, int'(lock_port[p][v]), 0, 5);
        end
      end
    end
  end
`endif
endmodule
