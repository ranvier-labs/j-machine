module mdp_memory_sim (
  input  logic clk,

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
  input  logic [j_machine_pkg::MDP_ROW_WORDS-1:0] qrb_write_enable,

  input  logic debug_write,
  input  j_machine_pkg::mdp_phys_addr_t debug_address,
  input  j_machine_pkg::mdp_word_t debug_wdata,
  output j_machine_pkg::mdp_word_t debug_rdata,

  input  logic dram_error_inject,
  input  j_machine_pkg::mdp_phys_addr_t dram_error_address
);
  import j_machine_pkg::*;

  // The generated C++ object zero-initializes this storage directly.  There is
  // no procedural million-iteration reset loop, but the full architectural
  // address space remains present and unwritten words are NIL.
  mdp_word_t store [0:(1 << MDP_ADDR_WIDTH)-1];
  logic response_pending;
  mdp_word_t response_data;
  logic response_error;

  // A QRB commit owns the SRAM row port for this cycle.  A later FPGA memory
  // target may implement the same contract with a true 144-bit row write.
  assign cpu_request_ready = !qrb_write;
  assign debug_rdata = store[debug_address];
  assign cpu_response_valid = response_pending;
  assign cpu_response_rdata = response_data;
  assign cpu_response_dram_error = response_error;

  always_ff @(posedge clk) begin
    response_pending <= 1'b0;
    response_error <= 1'b0;

    if (qrb_write) begin
      for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
        if (qrb_write_enable[word_index]) begin
          store[mdp_phys_addr_t'({qrb_row_address, 2'b00}
                                 + mdp_phys_addr_t'(word_index))]
              <= qrb_write_data[word_index*MDP_WORD_WIDTH +: MDP_WORD_WIDTH];
        end
      end
    end

    if (cpu_request_valid && cpu_request_ready) begin
      if (cpu_request_write) begin
        // $01000-$01fff is architectural ROM.  The debug loader represents
        // programming that ROM image before reset and is allowed to write it.
        if (!(cpu_request_address >= 20'h01000
              && cpu_request_address <= 20'h01fff)) begin
          store[cpu_request_address] <= cpu_request_wdata;
        end
      end else begin
        response_pending <= 1'b1;
        response_data <= store[cpu_request_address];
        response_error <= dram_error_inject
            && cpu_request_address == dram_error_address
            && cpu_request_address >= 20'h02000;
      end
    end

    if (debug_write) begin
      store[debug_address] <= debug_wdata;
    end
  end
endmodule
