module mdp_sparse_memory_dpi #(
  parameter int unsigned NODE_INDEX = 0
) (
  input  logic clk,
  input  logic reset,

  input  logic cpu_request_valid,
  output logic cpu_request_ready,
  input  logic cpu_request_write,
  input  j_machine_pkg::mdp_phys_addr_t cpu_request_address,
  input  j_machine_pkg::mdp_word_t cpu_request_wdata,
  output logic cpu_response_valid,
  output j_machine_pkg::mdp_word_t cpu_response_rdata,
  output logic cpu_response_dram_error,

  input  logic qrb_write,
  input  logic [j_machine_pkg::MDP_ADDR_WIDTH-3:0] qrb_row_address,
  input  logic [j_machine_pkg::MDP_ROW_WIDTH-1:0] qrb_write_data,
  input  logic [j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable
);
  import j_machine_pkg::*;

  import "DPI-C" function longint unsigned mdp_sparse_memory_read(
    input int unsigned node,
    input int unsigned address
  );
  import "DPI-C" function void mdp_sparse_memory_write(
    input int unsigned node,
    input int unsigned address,
    input longint unsigned value
  );

  logic response_pending;
  mdp_word_t response_data;

  // This is the same arbitration and latency contract as mdp_memory_sim: a
  // four-word receive-queue commit owns the SRAM row port for the cycle, and
  // an accepted processor read responds one cycle later. Storage itself lives
  // in the C++ target adapter so 512 nodes do not allocate 512 dense 1M-word
  // simulation arrays. No architectural address, tag, or timing rule changes.
  assign cpu_request_ready = !qrb_write;
  assign cpu_response_valid = response_pending;
  assign cpu_response_rdata = response_data;
  assign cpu_response_dram_error = 1'b0;

  always_ff @(posedge clk) begin
    if (reset) begin
      response_pending <= 1'b0;
      response_data <= '0;
    end else begin
      response_pending <= 1'b0;

      if (qrb_write) begin
        for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
          if (qrb_write_enable[word_index]) begin
            mdp_sparse_memory_write(
              NODE_INDEX,
              int'({qrb_row_address, 2'b00}) + word_index,
              64'(qrb_write_data[word_index*MDP_WORD_WIDTH +: MDP_WORD_WIDTH])
            );
          end
        end
      end

      if (cpu_request_valid && cpu_request_ready) begin
        if (cpu_request_write) begin
          // $01000-$01fff is architectural ROM. Image loading is performed by
          // the host before execution and is therefore allowed to populate it.
          if (!(cpu_request_address >= 20'h01000
                && cpu_request_address <= 20'h01fff)) begin
            mdp_sparse_memory_write(
              NODE_INDEX,
              int'(cpu_request_address),
              64'(cpu_request_wdata)
            );
          end
        end else begin
          response_pending <= 1'b1;
          response_data <= mdp_word_t'(
            mdp_sparse_memory_read(NODE_INDEX, int'(cpu_request_address))
          );
        end
      end
    end
  end
endmodule
