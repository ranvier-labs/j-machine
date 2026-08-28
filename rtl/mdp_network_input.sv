module mdp_network_input (
  input  logic clk,
  input  logic reset,

  input  logic [j_machine_pkg::J_PRIORITIES-1:0] link_valid,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] link_ready,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::J_FLIT_WIDTH-1:0] link_flit,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] link_tail,

  output logic [j_machine_pkg::J_PRIORITIES-1:0] word_valid,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] word_ready,
  output logic [j_machine_pkg::J_PRIORITIES-1:0][j_machine_pkg::MDP_WORD_WIDTH-1:0] word_data,
  output logic [j_machine_pkg::J_PRIORITIES-1:0] word_tail
);
  import j_machine_pkg::*;

  logic [J_PRIORITIES-1:0] have_high;
  logic [J_PRIORITIES-1:0][J_FLIT_WIDTH-1:0] high_half;
  logic [J_PRIORITIES-1:0] buffered_word_valid;
  logic [J_PRIORITIES-1:0][MDP_WORD_WIDTH-1:0] buffered_word;
  logic [J_PRIORITIES-1:0] buffered_tail;

  always_comb begin
    word_valid = '0;
    word_data = '0;
    word_tail = '0;
    link_ready = '0;
    for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
      word_valid[priority_index] = buffered_word_valid[priority_index];
      word_data[priority_index] = buffered_word[priority_index];
      word_tail[priority_index] = buffered_tail[priority_index];
      link_ready[priority_index] = !buffered_word_valid[priority_index];
    end
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      have_high <= '0;
      high_half <= '0;
      buffered_word_valid <= '0;
      buffered_word <= '0;
      buffered_tail <= '0;
    end else begin
      for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
        if (buffered_word_valid[priority_index] && word_ready[priority_index]) begin
          buffered_word_valid[priority_index] <= 1'b0;
        end
        if (link_valid[priority_index] && link_ready[priority_index]) begin
          if (!have_high[priority_index]) begin
            high_half[priority_index] <= link_flit[priority_index];
            have_high[priority_index] <= 1'b1;
            // A well-formed MDP message always ends on a 36-bit word boundary.
            assert (!link_tail[priority_index])
              else $error("J-network tail arrived on the high half of an MDP word");
          end else begin
            have_high[priority_index] <= 1'b0;
            buffered_word[priority_index]
                <= {high_half[priority_index], link_flit[priority_index]};
            buffered_tail[priority_index] <= link_tail[priority_index];
            buffered_word_valid[priority_index] <= 1'b1;
          end
        end
      end
    end
  end
endmodule
