`ifndef J_MACHINE_PKG_SV
`define J_MACHINE_PKG_SV

package j_machine_pkg;
  // Message-Driven Processor Architecture, version 11 (AIM-1069).
  localparam int MDP_WORD_WIDTH = 36;
  localparam int MDP_DATA_WIDTH = 32;
  localparam int MDP_TAG_WIDTH  = 4;
  localparam int MDP_INSN_WIDTH = 17;
  localparam int MDP_ADDR_WIDTH = 20;
  localparam int MDP_ROW_WORDS  = 4;
  localparam int MDP_ROW_WIDTH  = MDP_WORD_WIDTH * MDP_ROW_WORDS;

  localparam int J_PHIT_WIDTH = 9;
  localparam int J_FLIT_WIDTH = 18;
  localparam int J_PRIORITIES = 2;
  localparam int J_PORTS = 7;

  localparam int J_PORT_LOCAL = 0;
  localparam int J_PORT_X_NEG = 1;
  localparam int J_PORT_X_POS = 2;
  localparam int J_PORT_Y_NEG = 3;
  localparam int J_PORT_Y_POS = 4;
  localparam int J_PORT_Z_NEG = 5;
  localparam int J_PORT_Z_POS = 6;

  typedef logic [MDP_WORD_WIDTH-1:0] mdp_word_t;
  typedef logic [MDP_INSN_WIDTH-1:0] mdp_instruction_t;
  typedef logic [MDP_ADDR_WIDTH-1:0] mdp_phys_addr_t;
  typedef logic [J_FLIT_WIDTH-1:0] j_flit_t;

  typedef enum logic [3:0] {
    MDP_TAG_SYM   = 4'h0,
    MDP_TAG_INT   = 4'h1,
    MDP_TAG_BOOL  = 4'h2,
    MDP_TAG_ADDR  = 4'h3,
    MDP_TAG_IP    = 4'h4,
    MDP_TAG_MSG   = 4'h5,
    MDP_TAG_CFUT  = 4'h6,
    MDP_TAG_FUT   = 4'h7,
    MDP_TAG_TAG8  = 4'h8,
    MDP_TAG_TAG9  = 4'h9,
    MDP_TAG_TAGA  = 4'ha,
    MDP_TAG_TAGB  = 4'hb,
    MDP_TAG_INST0 = 4'hc,
    MDP_TAG_INST1 = 4'hd,
    MDP_TAG_INST2 = 4'he,
    MDP_TAG_INST3 = 4'hf
  } mdp_tag_t;

  typedef enum logic [5:0] {
    MDP_OP_NOP     = 6'h00,
    MDP_OP_READ    = 6'h01,
    MDP_OP_WRITE   = 6'h02,
    MDP_OP_READR   = 6'h03,
    MDP_OP_WRITER  = 6'h04,
    MDP_OP_RTAG    = 6'h05,
    MDP_OP_WTAG    = 6'h06,
    MDP_OP_LDIP    = 6'h07,
    MDP_OP_LDIPR   = 6'h08,
    MDP_OP_CHECK   = 6'h09,
    MDP_OP_CARRY   = 6'h0a,
    MDP_OP_ADD     = 6'h0b,
    MDP_OP_SUB     = 6'h0c,
    MDP_OP_MULH    = 6'h0e,
    MDP_OP_MUL     = 6'h0f,
    MDP_OP_ASH     = 6'h10,
    MDP_OP_LSH     = 6'h11,
    MDP_OP_ROT     = 6'h12,
    MDP_OP_AND     = 6'h18,
    MDP_OP_OR      = 6'h19,
    MDP_OP_XOR     = 6'h1a,
    MDP_OP_FFB     = 6'h1b,
    MDP_OP_NOT     = 6'h1c,
    MDP_OP_NEG     = 6'h1d,
    MDP_OP_LT      = 6'h20,
    MDP_OP_LE      = 6'h21,
    MDP_OP_GE      = 6'h22,
    MDP_OP_GT      = 6'h23,
    MDP_OP_EQUAL   = 6'h24,
    MDP_OP_NEQUAL  = 6'h25,
    MDP_OP_EQ      = 6'h26,
    MDP_OP_NEQ     = 6'h27,
    MDP_OP_XLATE   = 6'h28,
    MDP_OP_ENTER   = 6'h29,
    MDP_OP_INVAL   = 6'h2a,
    MDP_OP_PROBE   = 6'h2d,
    MDP_OP_SUSPEND = 6'h30,
    MDP_OP_CALL    = 6'h31,
    MDP_OP_SEND    = 6'h34,
    MDP_OP_SENDE   = 6'h35,
    MDP_OP_SEND2   = 6'h36,
    MDP_OP_SEND2E  = 6'h37,
    MDP_OP_BR      = 6'h38,
    MDP_OP_BNIL    = 6'h3a,
    MDP_OP_BNNIL   = 6'h3b,
    MDP_OP_BF      = 6'h3c,
    MDP_OP_BT      = 6'h3d,
    MDP_OP_BZ      = 6'h3e,
    MDP_OP_BNZ     = 6'h3f
  } mdp_opcode_t;

  typedef enum logic [4:0] {
    MDP_FAULT_CATASTROPHE = 5'h00,
    MDP_FAULT_INTERRUPT   = 5'h01,
    MDP_FAULT_QUEUE       = 5'h02,
    MDP_FAULT_SEND        = 5'h03,
    MDP_FAULT_ILGINST     = 5'h04,
    MDP_FAULT_DRAMERR     = 5'h05,
    MDP_FAULT_INVADR      = 5'h06,
    MDP_FAULT_LIMIT       = 5'h07,
    MDP_FAULT_EARLY       = 5'h08,
    MDP_FAULT_MSG         = 5'h09,
    MDP_FAULT_XLATE       = 5'h0a,
    MDP_FAULT_OVERFLOW    = 5'h0b,
    MDP_FAULT_CFUT        = 5'h0c,
    MDP_FAULT_FUT         = 5'h0d,
    MDP_FAULT_TAG8        = 5'h0e,
    MDP_FAULT_TAG9        = 5'h0f,
    MDP_FAULT_TAGA        = 5'h10,
    MDP_FAULT_TAGB        = 5'h11,
    MDP_FAULT_TYPE        = 5'h12
  } mdp_fault_t;

  typedef enum logic [1:0] {
    J_DIM_X = 2'd0,
    J_DIM_Y = 2'd1,
    J_DIM_Z = 2'd2,
    J_DIM_DATA = 2'd3
  } j_dimension_t;

  // Canonical internal representation of the routing header placed in an
  // 18-bit flow-control digit by the network output interface.  The pin-level
  // 9-bit serializer is deliberately a separate target adapter.
  localparam int J_HEADER_MARK_BIT = 17;
  localparam int J_HEADER_DIM_MSB = 16;
  localparam int J_HEADER_DIM_LSB = 15;
  localparam int J_HEADER_POS_BIT = 14;
  localparam int J_HEADER_NEG_BIT = 13;
  localparam int J_HEADER_COORD_MSB = 5;
  localparam int J_HEADER_COORD_LSB = 0;

  function automatic mdp_word_t mdp_word(
      input logic [3:0] tag,
      input logic [31:0] data
  );
    return {tag, data};
  endfunction

  function automatic logic [3:0] mdp_tag(input mdp_word_t word);
    return word[35:32];
  endfunction

  function automatic logic [31:0] mdp_data(input mdp_word_t word);
    return word[31:0];
  endfunction

  function automatic mdp_word_t mdp_bool(input logic value);
    return mdp_word(MDP_TAG_BOOL, {31'b0, value});
  endfunction

  function automatic mdp_word_t mdp_int(input logic [31:0] value);
    return mdp_word(MDP_TAG_INT, value);
  endfunction

  function automatic mdp_word_t mdp_addr(
      input logic relocatable,
      input logic invalid,
      input logic [19:0] base,
      input logic [9:0] length
  );
    return mdp_word(MDP_TAG_ADDR, {relocatable, invalid, base, length});
  endfunction

  function automatic mdp_word_t mdp_ip(
      input logic unchecked_mode,
      input logic fault_mode,
      input logic [19:0] offset,
      input logic phase,
      input logic absolute_a0
  );
    return mdp_word(
        MDP_TAG_IP,
        {unchecked_mode, fault_mode, offset, phase, absolute_a0, 8'b0});
  endfunction

  function automatic mdp_word_t mdp_msg(
      input logic unchecked_mode,
      input logic fault_mode,
      input logic [19:0] handler,
      input logic [9:0] length
  );
    return mdp_word(MDP_TAG_MSG, {unchecked_mode, fault_mode, handler, length});
  endfunction

  function automatic mdp_instruction_t mdp_instruction(
      input logic [5:0] opcode,
      input logic [1:0] op2,
      input logic [1:0] op1,
      input logic [6:0] op0
  );
    return {opcode, op2, op1, op0};
  endfunction

  function automatic mdp_word_t mdp_instruction_pair(
      input mdp_instruction_t high_instruction,
      input mdp_instruction_t low_instruction
  );
    // Raw instruction bits are {tag[1:0], data[31:0]}; tag[3:2] is 2'b11.
    return {2'b11, high_instruction, low_instruction};
  endfunction

  function automatic logic mdp_is_instruction_word(input mdp_word_t word);
    return word[35:34] == 2'b11;
  endfunction

  function automatic mdp_instruction_t mdp_high_instruction(input mdp_word_t word);
    return {word[33:32], word[31:17]};
  endfunction

  function automatic mdp_instruction_t mdp_low_instruction(input mdp_word_t word);
    return word[16:0];
  endfunction

  function automatic logic [6:0] mdp_op0_r(input logic [1:0] number);
    return {5'b00000, number};
  endfunction

  function automatic logic [6:0] mdp_op0_a(input logic [1:0] number);
    return {5'b00001, number};
  endfunction

  function automatic logic [6:0] mdp_op0_mem_r(
      input logic [1:0] offset_register,
      input logic [1:0] address_register
  );
    return {3'b001, offset_register, address_register};
  endfunction

  function automatic logic [6:0] mdp_op0_imm5(input logic signed [4:0] value);
    return {2'b01, value};
  endfunction

  function automatic logic [6:0] mdp_op0_mem_i(
      input logic [3:0] offset,
      input logic [1:0] address_register
  );
    return {1'b1, offset, address_register};
  endfunction

  function automatic logic [6:0] mdp_register_operand(
      input logic background_relative,
      input logic priority_relative,
      input logic [4:0] register_number
  );
    return {background_relative, priority_relative, register_number};
  endfunction

  function automatic j_flit_t j_header(
      input j_dimension_t dimension,
      input logic positive,
      input logic negative,
      input logic [5:0] coordinate
  );
    j_flit_t result;
    result = '0;
    result[J_HEADER_MARK_BIT] = 1'b1;
    result[J_HEADER_DIM_MSB:J_HEADER_DIM_LSB] = dimension;
    result[J_HEADER_POS_BIT] = positive;
    result[J_HEADER_NEG_BIT] = negative;
    result[J_HEADER_COORD_MSB:J_HEADER_COORD_LSB] = coordinate;
    return result;
  endfunction

  function automatic logic [19:0] mdp_align4(input logic [19:0] value);
    return {value[19:2] + (|value[1:0]), 2'b00};
  endfunction
endpackage

`endif
