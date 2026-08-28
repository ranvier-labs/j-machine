module j_fpu_mmio #(
  parameter j_machine_pkg::mdp_phys_addr_t BASE_ADDRESS = 20'hfff00
) (
  input  logic clk,
  input  logic reset,

  input  logic memory_request_valid,
  output logic memory_request_ready,
  input  logic memory_request_write,
  input  j_machine_pkg::mdp_phys_addr_t memory_request_address,
  input  j_machine_pkg::mdp_word_t memory_request_wdata,
  output logic memory_response_valid,
  output j_machine_pkg::mdp_word_t memory_response_rdata,
  output logic memory_response_error,

  output logic service_request_valid,
  input  logic service_request_ready,
  output j_fpu_pkg::j_fpu_operation_t service_request_operation,
  output j_fpu_pkg::j_fpu_format_t service_request_format,
  output j_fpu_pkg::j_fpu_rounding_t service_request_rounding,
  output logic service_request_tininess_after_rounding,
  output logic [63:0] service_request_a,
  output logic [63:0] service_request_b,
  output logic [63:0] service_request_c,
  input  logic service_response_valid,
  output logic service_response_ready,
  input  logic [63:0] service_response_result,
  input  j_fpu_pkg::j_fpu_exception_flags_t service_response_exception_flags,
  input  j_fpu_pkg::j_fpu_compare_t service_response_compare
);
  import j_machine_pkg::*;
  import j_fpu_pkg::*;

  localparam logic [7:0] CONTROL = 8'h00;
  localparam logic [7:0] OPERAND_A_LOW = 8'h01;
  localparam logic [7:0] OPERAND_A_HIGH = 8'h02;
  localparam logic [7:0] OPERAND_B_LOW = 8'h03;
  localparam logic [7:0] OPERAND_B_HIGH = 8'h04;
  localparam logic [7:0] OPERAND_C_LOW = 8'h05;
  localparam logic [7:0] OPERAND_C_HIGH = 8'h06;
  localparam logic [7:0] RESULT_LOW = 8'h07;
  localparam logic [7:0] RESULT_HIGH = 8'h08;
  localparam logic [7:0] STATUS = 8'h09;

  logic [31:0] control_reg;
  logic [63:0] operand_a_reg;
  logic [63:0] operand_b_reg;
  logic [63:0] operand_c_reg;
  logic [63:0] result_reg;
  j_fpu_exception_flags_t exception_flags_reg;
  j_fpu_compare_t compare_reg;
  logic busy_reg;
  logic done_reg;
  logic service_request_valid_reg;

  logic memory_response_valid_reg;
  mdp_word_t memory_response_rdata_reg;
  logic memory_response_error_reg;
  logic address_in_range;
  logic [7:0] address_offset;
  logic start_request;
  logic operation_valid;
  logic rounding_valid;
  logic [31:0] status_value;

  assign address_in_range = memory_request_address >= BASE_ADDRESS &&
      memory_request_address < BASE_ADDRESS + 20'd10;
  assign address_offset = 8'(memory_request_address - BASE_ADDRESS);
  assign start_request = memory_request_valid && memory_request_write &&
      address_in_range && address_offset == CONTROL &&
      memory_request_wdata[31];
  assign operation_valid = memory_request_wdata[4:0] <= J_FPU_F64_TO_F32;
  assign rounding_valid = memory_request_wdata[8:6] <= J_FPU_ROUND_NEAR_MAX_MAG ||
      memory_request_wdata[8:6] == J_FPU_ROUND_ODD;
  assign memory_request_ready = !memory_response_valid_reg &&
      !(start_request && busy_reg);

  always_comb begin
    status_value = 32'b0;
    status_value[0] = busy_reg;
    status_value[1] = done_reg;
    status_value[6:2] = exception_flags_reg;
    status_value[10:7] = compare_reg;
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      control_reg <= 32'b0;
      operand_a_reg <= 64'b0;
      operand_b_reg <= 64'b0;
      operand_c_reg <= 64'b0;
      result_reg <= 64'b0;
      exception_flags_reg <= 5'b0;
      compare_reg <= 4'b0;
      busy_reg <= 1'b0;
      done_reg <= 1'b0;
      service_request_valid_reg <= 1'b0;
      memory_response_valid_reg <= 1'b0;
      memory_response_rdata_reg <= mdp_int(32'b0);
      memory_response_error_reg <= 1'b0;
    end else begin
      memory_response_valid_reg <= 1'b0;
      memory_response_error_reg <= 1'b0;

      if (service_request_valid_reg && service_request_ready) begin
        service_request_valid_reg <= 1'b0;
      end

      if (memory_request_valid && memory_request_ready) begin
        memory_response_valid_reg <= 1'b1;
        memory_response_rdata_reg <= mdp_int(32'b0);
        if (!address_in_range) begin
          memory_response_error_reg <= 1'b1;
        end else if (memory_request_write &&
            mdp_tag(memory_request_wdata) != MDP_TAG_INT) begin
          memory_response_error_reg <= 1'b1;
        end else if (memory_request_write) begin
          unique case (address_offset)
            CONTROL: begin
              control_reg <= {1'b0, memory_request_wdata[30:0]};
              if (memory_request_wdata[31]) begin
                if (!operation_valid || !rounding_valid) begin
                  memory_response_error_reg <= 1'b1;
                end else begin
                  busy_reg <= 1'b1;
                  done_reg <= 1'b0;
                  exception_flags_reg <= 5'b0;
                  compare_reg <= 4'b0;
                  service_request_valid_reg <= 1'b1;
                end
              end
            end
            OPERAND_A_LOW: operand_a_reg[31:0] <= memory_request_wdata[31:0];
            OPERAND_A_HIGH: operand_a_reg[63:32] <= memory_request_wdata[31:0];
            OPERAND_B_LOW: operand_b_reg[31:0] <= memory_request_wdata[31:0];
            OPERAND_B_HIGH: operand_b_reg[63:32] <= memory_request_wdata[31:0];
            OPERAND_C_LOW: operand_c_reg[31:0] <= memory_request_wdata[31:0];
            OPERAND_C_HIGH: operand_c_reg[63:32] <= memory_request_wdata[31:0];
            STATUS: if (memory_request_wdata[1]) done_reg <= 1'b0;
            default: memory_response_error_reg <= 1'b1;
          endcase
        end else begin
          unique case (address_offset)
            CONTROL: memory_response_rdata_reg <= mdp_int(control_reg);
            OPERAND_A_LOW: memory_response_rdata_reg <= mdp_int(operand_a_reg[31:0]);
            OPERAND_A_HIGH: memory_response_rdata_reg <= mdp_int(operand_a_reg[63:32]);
            OPERAND_B_LOW: memory_response_rdata_reg <= mdp_int(operand_b_reg[31:0]);
            OPERAND_B_HIGH: memory_response_rdata_reg <= mdp_int(operand_b_reg[63:32]);
            OPERAND_C_LOW: memory_response_rdata_reg <= mdp_int(operand_c_reg[31:0]);
            OPERAND_C_HIGH: memory_response_rdata_reg <= mdp_int(operand_c_reg[63:32]);
            RESULT_LOW: memory_response_rdata_reg <= mdp_int(result_reg[31:0]);
            RESULT_HIGH: memory_response_rdata_reg <= mdp_int(result_reg[63:32]);
            STATUS: memory_response_rdata_reg <= mdp_int(status_value);
            default: memory_response_error_reg <= 1'b1;
          endcase
        end
      end

      if (service_response_valid && service_response_ready) begin
        result_reg <= service_response_result;
        exception_flags_reg <= service_response_exception_flags;
        compare_reg <= service_response_compare;
        busy_reg <= 1'b0;
        done_reg <= 1'b1;
      end
    end
  end

  assign service_request_valid = service_request_valid_reg;
  assign service_request_operation = j_fpu_operation_t'(control_reg[4:0]);
  assign service_request_format = j_fpu_format_t'(control_reg[5]);
  assign service_request_rounding = j_fpu_rounding_t'(control_reg[8:6]);
  assign service_request_tininess_after_rounding = control_reg[9];
  assign service_request_a = operand_a_reg;
  assign service_request_b = operand_b_reg;
  assign service_request_c = operand_c_reg;
  assign service_response_ready = busy_reg;
  assign memory_response_valid = memory_response_valid_reg;
  assign memory_response_rdata = memory_response_rdata_reg;
  assign memory_response_error = memory_response_error_reg;

  property request_held_until_accepted;
    @(posedge clk) disable iff (reset)
      service_request_valid && !service_request_ready |=> service_request_valid &&
        $stable({service_request_operation, service_request_format,
          service_request_rounding, service_request_tininess_after_rounding,
          service_request_a, service_request_b, service_request_c});
  endproperty
  assert property (request_held_until_accepted);
endmodule
