module j_fpu_hardfloat (
  input  logic clk,
  input  logic reset,

  input  logic request_valid,
  output logic request_ready,
  input  j_fpu_pkg::j_fpu_operation_t request_operation,
  input  j_fpu_pkg::j_fpu_format_t request_format,
  input  j_fpu_pkg::j_fpu_rounding_t request_rounding,
  input  logic request_tininess_after_rounding,
  input  logic [63:0] request_a,
  input  logic [63:0] request_b,
  input  logic [63:0] request_c,

  output logic response_valid,
  input  logic response_ready,
  output logic [63:0] response_result,
  output j_fpu_pkg::j_fpu_exception_flags_t response_exception_flags,
  output j_fpu_pkg::j_fpu_compare_t response_compare
);
  import j_fpu_pkg::*;

  logic [32:0] rec32_a;
  logic [32:0] rec32_b;
  logic [32:0] rec32_c;
  logic [64:0] rec64_a;
  logic [64:0] rec64_b;
  logic [64:0] rec64_c;

  fNToRecFN #(8, 24) to_rec32_a(request_a[31:0], rec32_a);
  fNToRecFN #(8, 24) to_rec32_b(request_b[31:0], rec32_b);
  fNToRecFN #(8, 24) to_rec32_c(request_c[31:0], rec32_c);
  fNToRecFN #(11, 53) to_rec64_a(request_a, rec64_a);
  fNToRecFN #(11, 53) to_rec64_b(request_b, rec64_b);
  fNToRecFN #(11, 53) to_rec64_c(request_c, rec64_c);

  logic [32:0] rec32_add;
  logic [32:0] rec32_mul;
  logic [32:0] rec32_fma;
  logic [4:0] flags32_add;
  logic [4:0] flags32_mul;
  logic [4:0] flags32_fma;
  logic [64:0] rec64_add;
  logic [64:0] rec64_mul;
  logic [64:0] rec64_fma;
  logic [4:0] flags64_add;
  logic [4:0] flags64_mul;
  logic [4:0] flags64_fma;

  addRecFN #(8, 24) add32(
    request_tininess_after_rounding,
    request_operation == J_FPU_SUB,
    rec32_a,
    rec32_b,
    request_rounding,
    rec32_add,
    flags32_add
  );
  mulRecFN #(8, 24) mul32(
    request_tininess_after_rounding,
    rec32_a,
    rec32_b,
    request_rounding,
    rec32_mul,
    flags32_mul
  );
  mulAddRecFN #(8, 24) fma32(
    request_tininess_after_rounding,
    2'b00,
    rec32_a,
    rec32_b,
    rec32_c,
    request_rounding,
    rec32_fma,
    flags32_fma
  );
  addRecFN #(11, 53) add64(
    request_tininess_after_rounding,
    request_operation == J_FPU_SUB,
    rec64_a,
    rec64_b,
    request_rounding,
    rec64_add,
    flags64_add
  );
  mulRecFN #(11, 53) mul64(
    request_tininess_after_rounding,
    rec64_a,
    rec64_b,
    request_rounding,
    rec64_mul,
    flags64_mul
  );
  mulAddRecFN #(11, 53) fma64(
    request_tininess_after_rounding,
    2'b00,
    rec64_a,
    rec64_b,
    rec64_c,
    request_rounding,
    rec64_fma,
    flags64_fma
  );

  logic [31:0] bits32_add;
  logic [31:0] bits32_mul;
  logic [31:0] bits32_fma;
  logic [63:0] bits64_add;
  logic [63:0] bits64_mul;
  logic [63:0] bits64_fma;
  recFNToFN #(8, 24) from_rec32_add(rec32_add, bits32_add);
  recFNToFN #(8, 24) from_rec32_mul(rec32_mul, bits32_mul);
  recFNToFN #(8, 24) from_rec32_fma(rec32_fma, bits32_fma);
  recFNToFN #(11, 53) from_rec64_add(rec64_add, bits64_add);
  recFNToFN #(11, 53) from_rec64_mul(rec64_mul, bits64_mul);
  recFNToFN #(11, 53) from_rec64_fma(rec64_fma, bits64_fma);

  logic compare32_lt;
  logic compare32_eq;
  logic compare32_gt;
  logic compare32_unordered;
  logic [4:0] compare32_flags;
  logic compare64_lt;
  logic compare64_eq;
  logic compare64_gt;
  logic compare64_unordered;
  logic [4:0] compare64_flags;
  compareRecFN #(8, 24) compare32(
    rec32_a, rec32_b, 1'b0,
    compare32_lt, compare32_eq, compare32_gt, compare32_unordered,
    compare32_flags
  );
  compareRecFN #(11, 53) compare64(
    rec64_a, rec64_b, 1'b0,
    compare64_lt, compare64_eq, compare64_gt, compare64_unordered,
    compare64_flags
  );

  logic [32:0] rec32_from_i32;
  logic [64:0] rec64_from_i32;
  logic [4:0] flags32_from_i32;
  logic [4:0] flags64_from_i32;
  logic integer_input_signed;
  assign integer_input_signed = request_operation == J_FPU_I32_TO_FLOAT;
  iNToRecFN #(32, 8, 24) i32_to_rec32(
    request_tininess_after_rounding,
    integer_input_signed,
    request_a[31:0],
    request_rounding,
    rec32_from_i32,
    flags32_from_i32
  );
  iNToRecFN #(32, 11, 53) i32_to_rec64(
    request_tininess_after_rounding,
    integer_input_signed,
    request_a[31:0],
    request_rounding,
    rec64_from_i32,
    flags64_from_i32
  );
  logic [31:0] bits32_from_i32;
  logic [63:0] bits64_from_i32;
  recFNToFN #(8, 24) from_rec32_i32(rec32_from_i32, bits32_from_i32);
  recFNToFN #(11, 53) from_rec64_i32(rec64_from_i32, bits64_from_i32);

  logic [31:0] integer32_from_f32;
  logic [31:0] integer32_from_f64;
  logic [2:0] int_flags_from_f32;
  logic [2:0] int_flags_from_f64;
  logic integer_output_signed;
  assign integer_output_signed = request_operation == J_FPU_FLOAT_TO_I32;
  recFNToIN #(8, 24, 32) rec32_to_i32(
    request_tininess_after_rounding,
    rec32_a,
    request_rounding,
    integer_output_signed,
    integer32_from_f32,
    int_flags_from_f32
  );
  recFNToIN #(11, 53, 32) rec64_to_i32(
    request_tininess_after_rounding,
    rec64_a,
    request_rounding,
    integer_output_signed,
    integer32_from_f64,
    int_flags_from_f64
  );

  logic [64:0] rec64_from_f32;
  logic [32:0] rec32_from_f64;
  logic [4:0] flags_f32_to_f64;
  logic [4:0] flags_f64_to_f32;
  logic [63:0] bits_f32_to_f64;
  logic [31:0] bits_f64_to_f32;
  recFNToRecFN #(8, 24, 11, 53) widen_f32(
    request_tininess_after_rounding,
    rec32_a,
    request_rounding,
    rec64_from_f32,
    flags_f32_to_f64
  );
  recFNToRecFN #(11, 53, 8, 24) narrow_f64(
    request_tininess_after_rounding,
    rec64_a,
    request_rounding,
    rec32_from_f64,
    flags_f64_to_f32
  );
  recFNToFN #(11, 53) from_rec64_widen(rec64_from_f32, bits_f32_to_f64);
  recFNToFN #(8, 24) from_rec32_narrow(rec32_from_f64, bits_f64_to_f32);

  logic div32_in_ready;
  logic div32_in_valid;
  logic div32_out_valid;
  logic [32:0] rec32_div;
  logic [4:0] flags32_div;
  logic div32_sqrt_op_out;
  logic div64_in_ready;
  logic div64_in_valid;
  logic div64_out_valid;
  logic [64:0] rec64_div;
  logic [4:0] flags64_div;
  logic div64_sqrt_op_out;
  logic [31:0] bits32_div;
  logic [63:0] bits64_div;

  divSqrtRecFN_small #(8, 24, 0) div_sqrt32(
    ~reset,
    clk,
    request_tininess_after_rounding,
    div32_in_ready,
    div32_in_valid,
    request_operation == J_FPU_SQRT,
    rec32_a,
    rec32_b,
    request_rounding,
    div32_out_valid,
    div32_sqrt_op_out,
    rec32_div,
    flags32_div
  );
  divSqrtRecFN_small #(11, 53, 0) div_sqrt64(
    ~reset,
    clk,
    request_tininess_after_rounding,
    div64_in_ready,
    div64_in_valid,
    request_operation == J_FPU_SQRT,
    rec64_a,
    rec64_b,
    request_rounding,
    div64_out_valid,
    div64_sqrt_op_out,
    rec64_div,
    flags64_div
  );
  recFNToFN #(8, 24) from_rec32_div(rec32_div, bits32_div);
  recFNToFN #(11, 53) from_rec64_div(rec64_div, bits64_div);

  logic iterative_pending;
  j_fpu_format_t iterative_format;
  logic iterative_sqrt;
  logic response_valid_reg;
  logic [63:0] response_result_reg;
  j_fpu_exception_flags_t response_exception_flags_reg;
  j_fpu_compare_t response_compare_reg;
  logic request_iterative;
  logic [63:0] combinational_result;
  j_fpu_exception_flags_t combinational_flags;
  j_fpu_compare_t combinational_compare;

  assign request_iterative = request_operation == J_FPU_DIV ||
      request_operation == J_FPU_SQRT;
  assign request_ready = !iterative_pending && !response_valid_reg &&
      (!request_iterative ||
       (request_format == J_FPU_BINARY32 ? div32_in_ready : div64_in_ready));
  assign div32_in_valid = request_valid && request_ready && request_iterative &&
      request_format == J_FPU_BINARY32;
  assign div64_in_valid = request_valid && request_ready && request_iterative &&
      request_format == J_FPU_BINARY64;

  always_comb begin
    combinational_result = 64'b0;
    combinational_flags = 5'b0;
    combinational_compare = 4'b0;
    unique case (request_operation)
      J_FPU_ADD, J_FPU_SUB: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_result = {32'b0, bits32_add};
          combinational_flags = flags32_add;
        end else begin
          combinational_result = bits64_add;
          combinational_flags = flags64_add;
        end
      end
      J_FPU_MUL: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_result = {32'b0, bits32_mul};
          combinational_flags = flags32_mul;
        end else begin
          combinational_result = bits64_mul;
          combinational_flags = flags64_mul;
        end
      end
      J_FPU_FMA: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_result = {32'b0, bits32_fma};
          combinational_flags = flags32_fma;
        end else begin
          combinational_result = bits64_fma;
          combinational_flags = flags64_fma;
        end
      end
      J_FPU_COMPARE: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_compare = {
            compare32_unordered, compare32_gt, compare32_eq, compare32_lt};
          combinational_flags = compare32_flags;
        end else begin
          combinational_compare = {
            compare64_unordered, compare64_gt, compare64_eq, compare64_lt};
          combinational_flags = compare64_flags;
        end
      end
      J_FPU_I32_TO_FLOAT, J_FPU_U32_TO_FLOAT: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_result = {32'b0, bits32_from_i32};
          combinational_flags = flags32_from_i32;
        end else begin
          combinational_result = bits64_from_i32;
          combinational_flags = flags64_from_i32;
        end
      end
      J_FPU_FLOAT_TO_I32, J_FPU_FLOAT_TO_U32: begin
        if (request_format == J_FPU_BINARY32) begin
          combinational_result = {32'b0, integer32_from_f32};
          combinational_flags = {
            int_flags_from_f32[2] | int_flags_from_f32[1],
            3'b000,
            int_flags_from_f32[0]
          };
        end else begin
          combinational_result = {32'b0, integer32_from_f64};
          combinational_flags = {
            int_flags_from_f64[2] | int_flags_from_f64[1],
            3'b000,
            int_flags_from_f64[0]
          };
        end
      end
      J_FPU_F32_TO_F64: begin
        combinational_result = bits_f32_to_f64;
        combinational_flags = flags_f32_to_f64;
      end
      J_FPU_F64_TO_F32: begin
        combinational_result = {32'b0, bits_f64_to_f32};
        combinational_flags = flags_f64_to_f32;
      end
      default: begin end
    endcase
  end

  always_ff @(posedge clk) begin
    if (reset) begin
      iterative_pending <= 1'b0;
      iterative_format <= J_FPU_BINARY32;
      iterative_sqrt <= 1'b0;
      response_valid_reg <= 1'b0;
      response_result_reg <= 64'b0;
      response_exception_flags_reg <= 5'b0;
      response_compare_reg <= 4'b0;
    end else begin
      if (response_valid_reg && response_ready) begin
        response_valid_reg <= 1'b0;
      end

      if (request_valid && request_ready) begin
        if (request_iterative) begin
          iterative_pending <= 1'b1;
          iterative_format <= request_format;
          iterative_sqrt <= request_operation == J_FPU_SQRT;
        end else begin
          response_valid_reg <= 1'b1;
          response_result_reg <= combinational_result;
          response_exception_flags_reg <= combinational_flags;
          response_compare_reg <= combinational_compare;
        end
      end

      if (iterative_pending &&
          ((iterative_format == J_FPU_BINARY32 && div32_out_valid) ||
           (iterative_format == J_FPU_BINARY64 && div64_out_valid))) begin
        iterative_pending <= 1'b0;
        response_valid_reg <= 1'b1;
        response_compare_reg <= 4'b0;
        if (iterative_format == J_FPU_BINARY32) begin
          response_result_reg <= {32'b0, bits32_div};
          response_exception_flags_reg <= flags32_div;
        end else begin
          response_result_reg <= bits64_div;
          response_exception_flags_reg <= flags64_div;
        end
      end
    end
  end

  assign response_valid = response_valid_reg;
  assign response_result = response_result_reg;
  assign response_exception_flags = response_exception_flags_reg;
  assign response_compare = response_compare_reg;

  property response_stable_while_stalled;
    @(posedge clk) disable iff (reset)
      response_valid && !response_ready |=> response_valid &&
        $stable({response_result, response_exception_flags, response_compare});
  endproperty
  assert property (response_stable_while_stalled);

  property iterative_operation_matches_response;
    @(posedge clk) disable iff (reset)
      iterative_pending &&
        ((iterative_format == J_FPU_BINARY32 && div32_out_valid) ||
         (iterative_format == J_FPU_BINARY64 && div64_out_valid)) |->
        (iterative_format == J_FPU_BINARY32 ? div32_sqrt_op_out :
          div64_sqrt_op_out) == iterative_sqrt;
  endproperty
  assert property (iterative_operation_matches_response);
endmodule
