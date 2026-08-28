module j_fpu_mmio_hardfloat #(
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
  output logic memory_response_error
);
  j_fpu_pkg::j_fpu_operation_t service_request_operation;
  j_fpu_pkg::j_fpu_format_t service_request_format;
  j_fpu_pkg::j_fpu_rounding_t service_request_rounding;
  logic service_request_valid;
  logic service_request_ready;
  logic service_request_tininess_after_rounding;
  logic [63:0] service_request_a;
  logic [63:0] service_request_b;
  logic [63:0] service_request_c;
  logic service_response_valid;
  logic service_response_ready;
  logic [63:0] service_response_result;
  j_fpu_pkg::j_fpu_exception_flags_t service_response_exception_flags;
  j_fpu_pkg::j_fpu_compare_t service_response_compare;

  j_fpu_mmio #(.BASE_ADDRESS(BASE_ADDRESS)) mmio (
    .clk,
    .reset,
    .memory_request_valid,
    .memory_request_ready,
    .memory_request_write,
    .memory_request_address,
    .memory_request_wdata,
    .memory_response_valid,
    .memory_response_rdata,
    .memory_response_error,
    .service_request_valid,
    .service_request_ready,
    .service_request_operation,
    .service_request_format,
    .service_request_rounding,
    .service_request_tininess_after_rounding,
    .service_request_a,
    .service_request_b,
    .service_request_c,
    .service_response_valid,
    .service_response_ready,
    .service_response_result,
    .service_response_exception_flags,
    .service_response_compare
  );

  j_fpu_hardfloat hardfloat (
    .clk,
    .reset,
    .request_valid(service_request_valid),
    .request_ready(service_request_ready),
    .request_operation(service_request_operation),
    .request_format(service_request_format),
    .request_rounding(service_request_rounding),
    .request_tininess_after_rounding(service_request_tininess_after_rounding),
    .request_a(service_request_a),
    .request_b(service_request_b),
    .request_c(service_request_c),
    .response_valid(service_response_valid),
    .response_ready(service_response_ready),
    .response_result(service_response_result),
    .response_exception_flags(service_response_exception_flags),
    .response_compare(service_response_compare)
  );
endmodule
