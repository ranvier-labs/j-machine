package j_fpu_pkg;
  typedef enum logic {
    J_FPU_BINARY32 = 1'b0,
    J_FPU_BINARY64 = 1'b1
  } j_fpu_format_t;

  // Values intentionally match HardFloat and IEEE rounding-direction encodings.
  typedef enum logic [2:0] {
    J_FPU_ROUND_NEAR_EVEN    = 3'b000,
    J_FPU_ROUND_MIN_MAG      = 3'b001,
    J_FPU_ROUND_MIN          = 3'b010,
    J_FPU_ROUND_MAX          = 3'b011,
    J_FPU_ROUND_NEAR_MAX_MAG = 3'b100,
    J_FPU_ROUND_ODD          = 3'b110
  } j_fpu_rounding_t;

  typedef enum logic [4:0] {
    J_FPU_ADD          = 5'd0,
    J_FPU_SUB          = 5'd1,
    J_FPU_MUL          = 5'd2,
    J_FPU_FMA          = 5'd3,
    J_FPU_DIV          = 5'd4,
    J_FPU_SQRT         = 5'd5,
    J_FPU_COMPARE      = 5'd6,
    J_FPU_I32_TO_FLOAT = 5'd7,
    J_FPU_U32_TO_FLOAT = 5'd8,
    J_FPU_FLOAT_TO_I32 = 5'd9,
    J_FPU_FLOAT_TO_U32 = 5'd10,
    J_FPU_F32_TO_F64   = 5'd11,
    J_FPU_F64_TO_F32   = 5'd12
  } j_fpu_operation_t;

  // result_compare is {unordered, greater-than, equal, less-than}.
  typedef logic [3:0] j_fpu_compare_t;

  // IEEE exception flags are {invalid, divide-by-zero, overflow,
  // underflow, inexact}, matching HardFloat's exceptionFlags order.
  typedef logic [4:0] j_fpu_exception_flags_t;
endpackage
