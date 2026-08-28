module j_mdp_core (
  input  logic clk,
  input  logic reset,
  input  logic run_enable,

  output logic memory_request_valid,
  input  logic memory_request_ready,
  output logic memory_request_write,
  output j_machine_pkg::mdp_phys_addr_t memory_request_address,
  output j_machine_pkg::mdp_word_t memory_request_wdata,
  input  logic memory_response_valid,
  input  j_machine_pkg::mdp_word_t memory_response_rdata,
  input  logic memory_response_dram_error,

  input  j_machine_pkg::mdp_word_t qbm [j_machine_pkg::J_PRIORITIES],
  input  j_machine_pkg::mdp_word_t qhl [j_machine_pkg::J_PRIORITIES],
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] queue_pending,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] queue_full,
  output logic queue_register_write,
  output logic queue_register_priority,
  output logic queue_register_select_qhl,
  output j_machine_pkg::mdp_word_t queue_register_wdata,

  output logic suspend_valid,
  output logic suspend_priority,
  output logic [9:0] suspend_message_length,
  input  logic suspend_ready,
  input  logic suspend_early,

  output logic send_valid,
  input  logic send_ready,
  output logic send_two,
  output logic send_end,
  output logic send_priority,
  output j_machine_pkg::mdp_word_t send_word0,
  output j_machine_pkg::mdp_word_t send_word1,

  input  logic external_interrupt,

  output logic [15:0] node_number,
  output logic background,
  output logic current_priority,
  output logic interrupt_mask,
  output logic fault_mode,
  output logic unchecked_mode,
  output logic [4:0] last_fault,
  output logic catastrophe,
  output logic [63:0] retired_instructions,
  output j_machine_pkg::mdp_word_t debug_current_ip,
  output j_machine_pkg::mdp_word_t debug_r0
);
  import j_machine_pkg::*;

  localparam logic [1:0] CONTEXT_BACKGROUND = 2'd2;

  typedef enum logic [4:0] {
    CORE_FETCH,
    CORE_FETCH_WAIT,
    CORE_EXECUTE,
    CORE_OP0_READ,
    CORE_OP0_READ_WAIT,
    CORE_VECTOR,
    CORE_VECTOR_WAIT,
    CORE_CALL,
    CORE_CALL_WAIT,
    CORE_DISPATCH,
    CORE_DISPATCH_WAIT,
    CORE_TABLE_READ,
    CORE_TABLE_READ_WAIT,
    CORE_TABLE_EVALUATE,
    CORE_TABLE_WRITE_DATA,
    CORE_TABLE_WRITE_KEY,
    CORE_RESULT_WRITE,
    CORE_SUSPEND
  } core_state_t;

  typedef enum logic [2:0] {
    DEST_NONE,
    DEST_DATA_REGISTER,
    DEST_ADDRESS_REGISTER,
    DEST_MEMORY,
    DEST_REGISTER_MODE
  } destination_kind_t;

  mdp_word_t data_register [3][4];
  mdp_word_t address_register [3][4];
  mdp_word_t id_register [J_PRIORITIES][4];
  mdp_word_t ip_register [3];
  mdp_word_t fip_register [3];
  mdp_word_t fir_register [J_PRIORITIES];
  mdp_word_t fop0_register [J_PRIORITIES];
  mdp_word_t fop1_register [J_PRIORITIES];
  logic [J_PRIORITIES-1:0] queue_addressing;
  logic [J_PRIORITIES-1:0] active_message;

  mdp_word_t tbm_register;
  logic [31:0] nnr_register;
  logic [19:0] mar_register;
  logic priority_flag;
  logic background_flag;
  logic interrupt_flag;

  core_state_t state;
  mdp_instruction_t instruction_register;
  logic [1:0] execution_context;
  logic execution_priority;
  logic execution_background;
  logic [19:0] instruction_word_offset;
  mdp_word_t operand0_register;
  logic operand0_loaded;
  logic [1:0] operand0_address_register;
  destination_kind_t operand0_destination_kind;
  mdp_phys_addr_t operand0_memory_address;

  mdp_fault_t pending_fault;
  logic [1:0] fault_context;
  logic fault_priority;

  logic dispatch_priority;
  logic [1:0] table_word_index;
  logic [19:0] table_row_address;
  mdp_word_t table_row [MDP_ROW_WORDS];
  mdp_word_t table_key;
  mdp_word_t table_data;
  mdp_word_t table_result_comb;
  logic table_hit_comb;
  logic table_hit_way_comb;
  logic table_way;
  logic replacement_way;
  destination_kind_t result_destination_kind;
  logic [1:0] result_destination_register;
  mdp_phys_addr_t result_destination_address;
  mdp_word_t result_word;

  logic [5:0] opcode;
  logic [1:0] op2;
  logic [1:0] op1;
  logic [6:0] op0;
  logic [1:0] op0_extension;
  mdp_word_t rs_value;
  mdp_word_t op0_value;
  logic op0_is_memory;
  logic op0_is_destination_memory;
  logic op0_decode_fault;
  mdp_fault_t op0_decode_fault_number;
  destination_kind_t op0_kind;
  logic [1:0] op0_register_number;
  mdp_phys_addr_t op0_address;
  logic [19:0] op0_offset;
  logic [1:0] op0_address_number;
  logic [30:0] selected_address_comb;
  logic [19:0] selected_length_comb;
  logic [19:0] logical_offset_comb;
  logic [1:0] current_context;
  mdp_word_t current_ip;
  logic current_unchecked;
  logic current_fault_mode;
  logic dispatch_needed;
  logic dispatch_choice;
  logic [19:0] fetch_logical_offset;
  logic fetch_address_fault;
  mdp_fault_t fetch_fault_number;
  mdp_phys_addr_t fetch_physical_address;

  function automatic mdp_word_t increment_ip(input mdp_word_t value);
    mdp_word_t result;
    begin
      result = value;
      if (!value[9]) begin
        result[9] = 1'b1;
      end else begin
        result[29:10] = value[29:10] + 1'b1;
        result[9] = 1'b0;
      end
      return result;
    end
  endfunction

  function automatic mdp_word_t next_word_ip(
      input mdp_word_t value,
      input logic signed [19:0] displacement
  );
    mdp_word_t result;
    begin
      result = value;
      result[29:10] = value[29:10] + 1'b1 + displacement;
      result[9] = 1'b0;
      return result;
    end
  endfunction

  function automatic mdp_phys_addr_t priority_map(
      input mdp_phys_addr_t address,
      input logic selected_priority
  );
    mdp_phys_addr_t result;
    begin
      result = address;
      if (address < 20'h00040) begin
        result[5] = address[5] ^ selected_priority;
      end
      return result;
    end
  endfunction

  function automatic mdp_fault_t type_fault_for(input mdp_word_t value);
    unique case (mdp_tag(value))
      MDP_TAG_CFUT: type_fault_for = MDP_FAULT_CFUT;
      MDP_TAG_FUT: type_fault_for = MDP_FAULT_FUT;
      MDP_TAG_TAG8: type_fault_for = MDP_FAULT_TAG8;
      MDP_TAG_TAG9: type_fault_for = MDP_FAULT_TAG9;
      MDP_TAG_TAGA: type_fault_for = MDP_FAULT_TAGA;
      MDP_TAG_TAGB: type_fault_for = MDP_FAULT_TAGB;
      default: type_fault_for = MDP_FAULT_TYPE;
    endcase
  endfunction

  function automatic logic [31:0] arithmetic_shift(
      input logic [31:0] value,
      input logic signed [31:0] amount
  );
    if (amount >= 32) return value[31] ? 32'hffff_ffff : 32'b0;
    if (amount <= -32) return value[31] ? 32'hffff_ffff : 32'b0;
    if (amount < 0) return $signed(value) >>> -amount;
    return value << amount;
  endfunction

  function automatic logic [31:0] logical_shift(
      input logic [31:0] value,
      input logic signed [31:0] amount
  );
    if (amount >= 32 || amount <= -32) return 32'b0;
    if (amount < 0) return value >> -amount;
    return value << amount;
  endfunction

  function automatic logic [31:0] rotate_left(
      input logic [31:0] value,
      input logic [4:0] amount
  );
    if (amount == 0) return value;
    return (value << amount) | (value >> (32 - amount));
  endfunction

  function automatic logic [31:0] find_first_bit(input logic [31:0] value);
    logic sign_bit;
    logic found;
    logic [31:0] result;
    begin
      sign_bit = value[31];
      found = 1'b0;
      result = 31;
      for (int bit_index = 30; bit_index >= 0; bit_index--) begin
        if (!found && value[bit_index] != sign_bit) begin
          result = 30 - bit_index;
          found = 1'b1;
        end
      end
      return result;
    end
  endfunction

  function automatic logic signed_add_overflow(
      input logic left_sign,
      input logic right_sign,
      input logic result_sign
  );
    return (left_sign == right_sign) && (result_sign != left_sign);
  endfunction

  function automatic logic signed_sub_overflow(
      input logic left_sign,
      input logic right_sign,
      input logic result_sign
  );
    return (left_sign != right_sign) && (result_sign != left_sign);
  endfunction

  function automatic logic [1:0] register_mode_context(
      input logic background_select,
      input logic priority_select
  );
    logic use_background;
    begin
      use_background = background_select ^ execution_background;
      if (use_background) return CONTEXT_BACKGROUND[1:0];
      return {1'b0, execution_priority ^ priority_select};
    end
  endfunction

  task automatic begin_fault(
      input mdp_fault_t requested_fault,
      input logic instruction_specific,
      input mdp_word_t saved_operand0,
      input mdp_word_t saved_operand1
  );
    mdp_fault_t selected_fault;
    begin
      selected_fault = requested_fault;
      if (ip_register[execution_context][30]) begin
        selected_fault = MDP_FAULT_CATASTROPHE;
      end
      pending_fault <= selected_fault;
      last_fault <= selected_fault;
      fault_context <= execution_context;
      fault_priority <= execution_priority;
      fip_register[execution_context] <= ip_register[execution_context];
      fir_register[execution_priority] <= instruction_specific
          ? mdp_instruction_pair(17'b0, instruction_register)
          : mdp_word(MDP_TAG_SYM, 32'b0);
      fop0_register[execution_priority] <= saved_operand0;
      fop1_register[execution_priority] <= saved_operand1;
      state <= CORE_VECTOR;
    end
  endtask

  assign current_context = background_flag ? CONTEXT_BACKGROUND
                                           : {1'b0, priority_flag};
  assign current_ip = ip_register[current_context];
  assign current_unchecked = current_ip[31];
  assign current_fault_mode = current_ip[30];
  assign node_number = nnr_register[15:0];
  assign background = background_flag;
  assign current_priority = priority_flag;
  assign interrupt_mask = interrupt_flag;
  assign fault_mode = current_fault_mode;
  assign unchecked_mode = current_unchecked;
  assign debug_current_ip = current_ip;
  assign debug_r0 = data_register[current_context][0];

  assign opcode = instruction_register[16:11];
  assign op2 = instruction_register[10:9];
  assign op1 = instruction_register[8:7];
  assign op0 = instruction_register[6:0];
  assign rs_value = data_register[execution_context][op1];
  assign table_hit_comb = table_row[1] == table_key || table_row[3] == table_key;
  assign table_hit_way_comb = table_row[3] == table_key;
  assign table_result_comb = table_hit_way_comb ? table_row[2] : table_row[0];

  always_comb begin
    unique case (opcode)
      MDP_OP_READ, MDP_OP_RTAG, MDP_OP_FFB, MDP_OP_NOT, MDP_OP_NEG:
        op0_extension = op1;
      MDP_OP_WRITE: op0_extension = op2;
      MDP_OP_LDIP, MDP_OP_CALL, MDP_OP_BR,
      MDP_OP_BNIL, MDP_OP_BNNIL, MDP_OP_BF, MDP_OP_BT,
      MDP_OP_BZ, MDP_OP_BNZ: op0_extension = op2;
      MDP_OP_SEND, MDP_OP_SENDE: op0_extension = op1;
      default: op0_extension = 2'b00;
    endcase
  end

  always_comb begin
    op0_value = mdp_word(MDP_TAG_SYM, 32'b0);
    op0_is_memory = 1'b0;
    op0_is_destination_memory = 1'b0;
    op0_decode_fault = 1'b0;
    op0_decode_fault_number = MDP_FAULT_ILGINST;
    op0_kind = DEST_NONE;
    op0_register_number = op0[1:0];
    op0_address = '0;
    op0_offset = '0;
    op0_address_number = op0[1:0];
    selected_address_comb = '0;
    selected_length_comb = '0;
    logical_offset_comb = '0;

    if (op0[6:2] == 5'b00000) begin
      op0_kind = DEST_DATA_REGISTER;
      op0_value = data_register[execution_context][op0[1:0]];
    end else if (op0[6:2] == 5'b00001) begin
      op0_kind = DEST_ADDRESS_REGISTER;
      op0_value = address_register[execution_context][op0[1:0]];
    end else if (op0 >= 7'h08 && op0 <= 7'h0f) begin
      unique case (op0)
        7'h08: op0_value = mdp_word(MDP_TAG_SYM, 32'b0);
        7'h09: op0_value = mdp_bool(1'b0);
        7'h0a: op0_value = mdp_bool(1'b1);
        7'h0b: op0_value = mdp_int(32'h8000_0000);
        7'h0c: op0_value = mdp_int(32'h0000_00ff);
        7'h0d: op0_value = mdp_int(32'h0000_03ff);
        7'h0e: op0_value = mdp_int(32'h0000_ffff);
        default: op0_value = mdp_int(32'h000f_ffff);
      endcase
    end else if (op0[6:4] == 3'b001) begin
      op0_is_memory = 1'b1;
      op0_kind = DEST_MEMORY;
      op0_offset = data_register[execution_context][op0[3:2]][19:0];
      op0_address_number = op0[1:0];
      if (!ip_register[execution_context][31]
          && mdp_tag(data_register[execution_context][op0[3:2]]) != MDP_TAG_INT) begin
        op0_decode_fault = 1'b1;
        op0_decode_fault_number
            = type_fault_for(data_register[execution_context][op0[3:2]]);
      end
    end else if (op0[6:5] == 2'b01) begin
      op0_value = mdp_int({{25{op0_extension[1]}},
                           op0_extension, op0[4:0]});
    end else if (op0[6]) begin
      op0_is_memory = 1'b1;
      op0_kind = DEST_MEMORY;
      op0_offset = {14'b0, op0_extension, op0[5:2]};
      op0_address_number = op0[1:0];
    end else begin
      op0_decode_fault = 1'b1;
      op0_decode_fault_number = MDP_FAULT_ILGINST;
    end

    if (op0_is_memory && !op0_decode_fault) begin
      selected_address_comb
          = address_register[execution_context][op0_address_number][30:0];
      selected_length_comb = {10'b0, selected_address_comb[9:0]};
      logical_offset_comb = op0_offset;
      if (op0_address_number == 0 && ip_register[execution_context][8]) begin
        op0_address = priority_map(logical_offset_comb, execution_priority);
      end else if (selected_address_comb[30]) begin
        op0_decode_fault = 1'b1;
        op0_decode_fault_number = MDP_FAULT_INVADR;
      end else if (selected_length_comb != 0
                   && logical_offset_comb >= selected_length_comb) begin
        op0_decode_fault = 1'b1;
        op0_decode_fault_number = MDP_FAULT_LIMIT;
      end else if (!execution_background && queue_addressing[execution_priority]
                   && op0_address_number == 3) begin
        if (opcode != MDP_OP_WRITE
            && logical_offset_comb >= {10'b0, qhl[execution_priority][9:0]}) begin
          op0_decode_fault = 1'b1;
          op0_decode_fault_number = MDP_FAULT_EARLY;
        end else begin
          op0_address = qbm[execution_priority][29:10]
              | ((selected_address_comb[29:10] + logical_offset_comb)
                 & {10'b0, qbm[execution_priority][9:0]});
        end
      end else begin
        op0_address = priority_map(
            selected_address_comb[29:10] + logical_offset_comb, execution_priority);
      end
    end
    op0_is_destination_memory = op0_is_memory;
    if (opcode == MDP_OP_READR || opcode == MDP_OP_WRITER
        || opcode == MDP_OP_LDIPR) begin
      op0_value = mdp_word(MDP_TAG_SYM, 32'b0);
      op0_is_memory = 1'b0;
      op0_is_destination_memory = 1'b0;
      op0_decode_fault = 1'b0;
      op0_kind = DEST_REGISTER_MODE;
    end else if (operand0_loaded) begin
      op0_value = operand0_register;
      op0_is_memory = 1'b0;
      op0_is_destination_memory = 1'b0;
      op0_decode_fault = 1'b0;
      op0_kind = operand0_destination_kind;
      op0_register_number = operand0_address_register;
      op0_address = operand0_memory_address;
    end
  end

  always_comb begin
    fetch_logical_offset = current_ip[29:10];
    fetch_address_fault = 1'b0;
    fetch_fault_number = MDP_FAULT_INVADR;
    if (current_ip[8]) begin
      fetch_physical_address = priority_map(fetch_logical_offset, priority_flag);
    end else if (address_register[current_context][0][30]) begin
      fetch_physical_address = '0;
      fetch_address_fault = 1'b1;
      fetch_fault_number = MDP_FAULT_INVADR;
    end else if (address_register[current_context][0][9:0] != 0
                 && fetch_logical_offset
                    >= {10'b0, address_register[current_context][0][9:0]}) begin
      fetch_physical_address = '0;
      fetch_address_fault = 1'b1;
      fetch_fault_number = MDP_FAULT_LIMIT;
    end else begin
      fetch_physical_address = priority_map(
          address_register[current_context][0][29:10] + fetch_logical_offset,
          priority_flag);
    end
  end

  always_comb begin
    dispatch_needed = 1'b0;
    dispatch_choice = 1'b0;
    if (!interrupt_flag) begin
      if (queue_pending[1] && !active_message[1]
          && (background_flag || !priority_flag)) begin
        dispatch_needed = 1'b1;
        dispatch_choice = 1'b1;
      end else if (queue_pending[0] && !active_message[0] && background_flag) begin
        dispatch_needed = 1'b1;
        dispatch_choice = 1'b0;
      end
    end
  end

  always_comb begin
    memory_request_valid = 1'b0;
    memory_request_write = 1'b0;
    memory_request_address = '0;
    memory_request_wdata = '0;
    unique case (state)
      CORE_FETCH: begin
        if (run_enable && !dispatch_needed && !fetch_address_fault
            && !(external_interrupt && !interrupt_flag && !current_fault_mode)
            && !(queue_full[priority_flag] && !interrupt_flag
                 && !current_fault_mode && !background_flag)) begin
          memory_request_valid = 1'b1;
          memory_request_address = fetch_physical_address;
        end
      end
      CORE_OP0_READ: begin
        memory_request_valid = 1'b1;
        memory_request_address = operand0_memory_address;
      end
      CORE_VECTOR: begin
        memory_request_valid = 1'b1;
        memory_request_address = 20'h00040
            + ({19'b0, fault_priority} << 5)
            + {{15{1'b0}}, pending_fault};
      end
      CORE_CALL: begin
        memory_request_valid = 1'b1;
        memory_request_address = 20'h00080 + operand0_register[19:0];
      end
      CORE_DISPATCH: begin
        memory_request_valid = 1'b1;
        memory_request_address = qhl[dispatch_priority][29:10];
      end
      CORE_TABLE_READ: begin
        memory_request_valid = 1'b1;
        memory_request_address = table_row_address
                               + {{18{1'b0}}, table_word_index};
      end
      CORE_TABLE_WRITE_DATA: begin
        memory_request_valid = 1'b1;
        memory_request_write = 1'b1;
        memory_request_address = table_row_address + {18'b0, table_way, 1'b0};
        memory_request_wdata = table_data;
      end
      CORE_TABLE_WRITE_KEY: begin
        memory_request_valid = 1'b1;
        memory_request_write = 1'b1;
        memory_request_address = table_row_address + {18'b0, table_way, 1'b0} + 1'b1;
        memory_request_wdata = table_key;
      end
      CORE_RESULT_WRITE: begin
        memory_request_valid = result_destination_kind == DEST_MEMORY;
        memory_request_write = 1'b1;
        memory_request_address = result_destination_address;
        memory_request_wdata = result_word;
      end
      default: begin end
    endcase
  end

  always_comb begin
    suspend_valid = state == CORE_SUSPEND;
    suspend_priority = execution_priority;
    suspend_message_length = address_register[execution_context][3][9:0];

    send_valid = 1'b0;
    send_two = opcode == MDP_OP_SEND2 || opcode == MDP_OP_SEND2E;
    send_end = opcode == MDP_OP_SENDE || opcode == MDP_OP_SEND2E;
    send_priority = op2[0];
    send_word0 = operand0_register;
    send_word1 = rs_value;
    if (state == CORE_EXECUTE
        && (opcode == MDP_OP_SEND || opcode == MDP_OP_SENDE
            || opcode == MDP_OP_SEND2 || opcode == MDP_OP_SEND2E)
        && !op0_is_memory && !op0_decode_fault) begin
      send_valid = 1'b1;
      send_word0 = op0_value;
    end else if (state == CORE_OP0_READ_WAIT
                 && memory_response_valid
                 && (opcode == MDP_OP_SEND || opcode == MDP_OP_SENDE
                     || opcode == MDP_OP_SEND2 || opcode == MDP_OP_SEND2E)) begin
      send_valid = 1'b1;
      send_word0 = memory_response_rdata;
    end
  end

  always_ff @(posedge clk) begin : core_sequential
    if (reset) begin
      state <= CORE_FETCH;
      priority_flag <= 1'b0;
      background_flag <= 1'b1;
      interrupt_flag <= 1'b1;
      queue_addressing <= '0;
      active_message <= '0;
      tbm_register <= mdp_addr(1'b0, 1'b0, 20'b0, 10'b0);
      nnr_register <= '0;
      mar_register <= '0;
      instruction_register <= '0;
      execution_context <= CONTEXT_BACKGROUND[1:0];
      execution_priority <= 1'b0;
      execution_background <= 1'b1;
      instruction_word_offset <= '0;
      operand0_register <= '0;
      operand0_loaded <= 1'b0;
      operand0_address_register <= '0;
      operand0_destination_kind <= DEST_NONE;
      operand0_memory_address <= '0;
      pending_fault <= MDP_FAULT_CATASTROPHE;
      fault_context <= CONTEXT_BACKGROUND[1:0];
      fault_priority <= 1'b0;
      dispatch_priority <= 1'b0;
      table_word_index <= '0;
      table_row_address <= '0;
      table_key <= '0;
      table_data <= '0;
      table_way <= 1'b0;
      replacement_way <= 1'b0;
      result_destination_kind <= DEST_NONE;
      result_destination_register <= '0;
      result_destination_address <= '0;
      result_word <= '0;
      last_fault <= '0;
      catastrophe <= 1'b0;
      retired_instructions <= '0;
      queue_register_write <= 1'b0;
      queue_register_priority <= 1'b0;
      queue_register_select_qhl <= 1'b0;
      queue_register_wdata <= '0;
      for (int context_index = 0; context_index < 3; context_index++) begin
        ip_register[context_index] <= mdp_ip(1'b1, 1'b0,
            context_index == int'(CONTEXT_BACKGROUND) ? 20'h01000 : 20'b0,
            1'b0, context_index == int'(CONTEXT_BACKGROUND));
        fip_register[context_index] <= mdp_ip(1'b1, 1'b0, 20'b0, 1'b0, 1'b1);
        for (int register_number = 0; register_number < 4; register_number++) begin
          data_register[context_index][register_number]
              <= mdp_word(MDP_TAG_SYM, 32'b0);
          address_register[context_index][register_number]
              <= mdp_addr(1'b0, 1'b0, 20'b0, 10'b0);
        end
      end
      for (int priority_index = 0; priority_index < J_PRIORITIES; priority_index++) begin
        fir_register[priority_index] <= mdp_word(MDP_TAG_SYM, 32'b0);
        fop0_register[priority_index] <= mdp_word(MDP_TAG_SYM, 32'b0);
        fop1_register[priority_index] <= mdp_word(MDP_TAG_SYM, 32'b0);
        for (int register_number = 0; register_number < 4; register_number++) begin
          id_register[priority_index][register_number] <= mdp_word(MDP_TAG_SYM, 32'b0);
        end
      end
      for (int word_index = 0; word_index < MDP_ROW_WORDS; word_index++) begin
        table_row[word_index] <= '0;
      end
    end else begin
      queue_register_write <= 1'b0;
      unique case (state)
        CORE_FETCH: begin
          if (run_enable) begin
            execution_context <= current_context;
            execution_priority <= priority_flag;
            execution_background <= background_flag;
            if (external_interrupt && !interrupt_flag && !current_fault_mode) begin
              instruction_register <= '0;
              begin_fault(MDP_FAULT_INTERRUPT, 1'b0, '0, '0);
            end else if (queue_full[priority_flag] && !interrupt_flag
                         && !current_fault_mode && !background_flag) begin
              instruction_register <= '0;
              begin_fault(MDP_FAULT_QUEUE, 1'b0, '0, '0);
            end else if (dispatch_needed) begin
              dispatch_priority <= dispatch_choice;
              state <= CORE_DISPATCH;
            end else if (fetch_address_fault) begin
              instruction_register <= '0;
              begin_fault(fetch_fault_number, 1'b0, '0, '0);
            end else if (memory_request_valid && memory_request_ready) begin
              state <= CORE_FETCH_WAIT;
            end
          end
        end

        CORE_FETCH_WAIT: begin
          if (memory_response_valid) begin
            if (memory_response_dram_error) begin
              instruction_register <= '0;
              begin_fault(MDP_FAULT_DRAMERR, 1'b0, '0, '0);
            end else if (!mdp_is_instruction_word(memory_response_rdata)) begin
              data_register[current_context][0] <= memory_response_rdata;
              ip_register[current_context][29:10] <= current_ip[29:10] + 1'b1;
              ip_register[current_context][9] <= 1'b0;
              state <= CORE_FETCH;
            end else begin
              execution_context <= current_context;
              execution_priority <= priority_flag;
              execution_background <= background_flag;
              instruction_word_offset <= current_ip[29:10];
              instruction_register <= current_ip[9]
                  ? mdp_low_instruction(memory_response_rdata)
                  : mdp_high_instruction(memory_response_rdata);
              ip_register[current_context] <= increment_ip(current_ip);
              operand0_loaded <= 1'b0;
              state <= CORE_EXECUTE;
            end
          end
        end

        CORE_EXECUTE: begin
          logic checked;
          logic [31:0] left_data;
          logic [31:0] right_data;
          logic [31:0] arithmetic_result;
          logic [63:0] multiply_result;
          logic carry_out;
          logic operation_complete;
          logic branch_taken;
          checked = !ip_register[execution_context][31];
          left_data = rs_value[31:0];
          right_data = op0_value[31:0];
          arithmetic_result = '0;
          multiply_result = '0;
          carry_out = left_data > ~right_data;
          operation_complete = 1'b1;
          branch_taken = 1'b0;

          if (op0_decode_fault) begin
            begin_fault(op0_decode_fault_number, 1'b1, op0_value, rs_value);
            operation_complete = 1'b0;
          end else if (op0_is_memory && opcode != MDP_OP_WRITE
                       && opcode != MDP_OP_XLATE && opcode != MDP_OP_PROBE) begin
            operand0_memory_address <= op0_address;
            operand0_destination_kind <= op0_kind;
            operand0_address_register <= op0_register_number;
            mar_register <= op0_address;
            state <= CORE_OP0_READ;
            operation_complete = 1'b0;
          end else begin
            unique case (opcode)
              MDP_OP_NOP: begin end
              MDP_OP_READ: begin
                if (checked && mdp_tag(op0_value) == MDP_TAG_CFUT) begin
                  begin_fault(MDP_FAULT_CFUT, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  data_register[execution_context][op2] <= op0_value;
                end
              end
              MDP_OP_WRITE: begin
                if (!op0_is_destination_memory) begin
                  begin_fault(MDP_FAULT_ILGINST, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  result_destination_kind <= DEST_MEMORY;
                  result_destination_address <= op0_address;
                  result_word <= rs_value;
                  mar_register <= op0_address;
                  state <= CORE_RESULT_WRITE;
                  operation_complete = 1'b0;
                end
              end
              MDP_OP_READR, MDP_OP_LDIPR: begin
                mdp_word_t register_value;
                logic [1:0] selected_context;
                logic [4:0] selected_register;
                selected_context = register_mode_context(op0[6], op0[5]);
                selected_register = op0[4:0];
                register_value = mdp_word(MDP_TAG_SYM, 32'b0);
                unique case (selected_register)
                  5'h00,5'h01,5'h02,5'h03:
                    register_value = data_register[selected_context][selected_register[1:0]];
                  5'h04,5'h05,5'h06,5'h07:
                    register_value = address_register[selected_context][selected_register[1:0]];
                  5'h08,5'h09,5'h0a,5'h0b:
                    register_value = selected_context == CONTEXT_BACKGROUND
                        ? mdp_word(MDP_TAG_SYM, 32'b0)
                        : id_register[selected_context[0]][selected_register[1:0]];
                  5'h0c: register_value = fip_register[selected_context];
                  5'h0d: register_value = selected_context == CONTEXT_BACKGROUND
                        ? mdp_word(MDP_TAG_SYM, 32'b0)
                        : fir_register[selected_context[0]];
                  5'h0e: register_value = selected_context == CONTEXT_BACKGROUND
                        ? mdp_word(MDP_TAG_SYM, 32'b0)
                        : fop0_register[selected_context[0]];
                  5'h0f: register_value = selected_context == CONTEXT_BACKGROUND
                        ? mdp_word(MDP_TAG_SYM, 32'b0)
                        : fop1_register[selected_context[0]];
                  5'h10: register_value = qbm[execution_priority ^ op0[5]];
                  5'h11: register_value = qhl[execution_priority ^ op0[5]];
                  5'h12: register_value = ip_register[selected_context];
                  5'h13: register_value = tbm_register;
                  5'h14: register_value = mdp_int(nnr_register);
                  5'h15: register_value = mdp_int({12'b0, mar_register});
                  5'h18: register_value = mdp_bool(priority_flag);
                  5'h19: register_value = mdp_bool(background_flag);
                  5'h1a: register_value = mdp_bool(interrupt_flag);
                  5'h1b: register_value = mdp_bool(ip_register[selected_context][30]);
                  5'h1c: register_value = mdp_bool(ip_register[selected_context][31]);
                  5'h1d: register_value = mdp_bool(queue_addressing[execution_priority ^ op0[5]]);
                  default: begin
                    begin_fault(MDP_FAULT_ILGINST, 1'b1, register_value, rs_value);
                    operation_complete = 1'b0;
                  end
                endcase
                if (operation_complete) begin
                  if (checked && mdp_tag(register_value) == MDP_TAG_CFUT) begin
                    begin_fault(MDP_FAULT_CFUT, 1'b1, register_value, rs_value);
                    operation_complete = 1'b0;
                  end else if (opcode == MDP_OP_LDIPR) begin
                    if (checked && mdp_tag(register_value) != MDP_TAG_IP) begin
                      begin_fault(type_fault_for(register_value), 1'b1,
                                  register_value, rs_value);
                      operation_complete = 1'b0;
                    end else begin
                      ip_register[execution_context] <= register_value;
                    end
                  end else begin
                    data_register[execution_context][op2] <= register_value;
                  end
                end
              end
              MDP_OP_WRITER: begin
                logic [1:0] selected_context;
                logic [4:0] selected_register;
                logic selected_queue_priority;
                selected_context = register_mode_context(op0[6], op0[5]);
                selected_register = op0[4:0];
                selected_queue_priority = execution_priority ^ op0[5];
                if (checked && selected_register >= 5'h04 && selected_register <= 5'h07
                    && mdp_tag(rs_value) != MDP_TAG_ADDR) begin
                  begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked && selected_register == 5'h12
                             && mdp_tag(rs_value) != MDP_TAG_IP) begin
                  begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  unique case (selected_register)
                    5'h00,5'h01,5'h02,5'h03:
                      data_register[selected_context][selected_register[1:0]] <= rs_value;
                    5'h04,5'h05,5'h06,5'h07:
                      address_register[selected_context][selected_register[1:0]] <= rs_value;
                    5'h08,5'h09,5'h0a,5'h0b:
                      if (selected_context != CONTEXT_BACKGROUND)
                        id_register[selected_context[0]][selected_register[1:0]] <= rs_value;
                    5'h0c: fip_register[selected_context] <= rs_value;
                    5'h0d: if (selected_context != CONTEXT_BACKGROUND)
                      fir_register[selected_context[0]] <= rs_value;
                    5'h0e: if (selected_context != CONTEXT_BACKGROUND)
                      fop0_register[selected_context[0]] <= rs_value;
                    5'h0f: if (selected_context != CONTEXT_BACKGROUND)
                      fop1_register[selected_context[0]] <= rs_value;
                    5'h10,5'h11: begin
                      queue_register_write <= 1'b1;
                      queue_register_priority <= selected_queue_priority;
                      queue_register_select_qhl <= selected_register == 5'h11;
                      queue_register_wdata <= rs_value;
                    end
                    5'h12: ip_register[selected_context] <= rs_value;
                    5'h13: tbm_register <= rs_value;
                    5'h14: nnr_register <= rs_value[31:0];
                    5'h15: begin
                      begin_fault(MDP_FAULT_ILGINST, 1'b1, op0_value, rs_value);
                      operation_complete = 1'b0;
                    end
                    5'h18: priority_flag <= rs_value[0];
                    5'h19: background_flag <= rs_value[0];
                    5'h1a: interrupt_flag <= rs_value[0];
                    5'h1b: ip_register[selected_context][30] <= rs_value[0];
                    5'h1c: ip_register[selected_context][31] <= rs_value[0];
                    5'h1d: queue_addressing[selected_queue_priority] <= rs_value[0];
                    default: begin
                      begin_fault(MDP_FAULT_ILGINST, 1'b1, op0_value, rs_value);
                      operation_complete = 1'b0;
                    end
                  endcase
                end
              end
              MDP_OP_RTAG: begin
                if (checked && mdp_tag(op0_value) == MDP_TAG_CFUT) begin
                  begin_fault(MDP_FAULT_CFUT, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2]
                    <= mdp_int({28'b0, mdp_tag(op0_value)});
              end
              MDP_OP_WTAG: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (op0_value[31:0] > 15) begin
                  begin_fault(MDP_FAULT_TYPE, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2]
                    <= mdp_word(op0_value[3:0], rs_value[31:0]);
              end
              MDP_OP_LDIP: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_IP) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else ip_register[execution_context] <= op0_value;
              end
              MDP_OP_CHECK: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2]
                    <= mdp_bool(mdp_tag(rs_value) == op0_value[3:0]);
              end
              MDP_OP_CARRY, MDP_OP_ADD, MDP_OP_SUB: begin
                arithmetic_result = opcode == MDP_OP_SUB
                    ? left_data - right_data : left_data + right_data;
                if (checked && (mdp_tag(rs_value) != MDP_TAG_INT
                                || mdp_tag(op0_value) != MDP_TAG_INT)) begin
                  begin_fault(mdp_tag(rs_value) != MDP_TAG_INT
                                  ? type_fault_for(rs_value) : type_fault_for(op0_value),
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked && ((opcode != MDP_OP_SUB
                              && signed_add_overflow(left_data[31], right_data[31],
                                                     arithmetic_result[31]))
                             || (opcode == MDP_OP_SUB
                              && signed_sub_overflow(left_data[31], right_data[31],
                                                     arithmetic_result[31])))) begin
                  begin_fault(MDP_FAULT_OVERFLOW, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (opcode == MDP_OP_CARRY) begin
                  data_register[execution_context][op2]
                      <= mdp_int({31'b0, carry_out});
                end else begin
                  data_register[execution_context][op2] <= mdp_word(
                      checked ? MDP_TAG_INT : mdp_tag(rs_value), arithmetic_result);
                end
              end
              MDP_OP_MUL, MDP_OP_MULH: begin
                multiply_result = $signed(left_data) * $signed(right_data);
                if (checked && (mdp_tag(rs_value) != MDP_TAG_INT
                                || mdp_tag(op0_value) != MDP_TAG_INT)) begin
                  begin_fault(mdp_tag(rs_value) != MDP_TAG_INT
                                  ? type_fault_for(rs_value) : type_fault_for(op0_value),
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked
                    && multiply_result[63:32] != {32{multiply_result[31]}}) begin
                  begin_fault(MDP_FAULT_OVERFLOW, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2] <= mdp_word(
                    checked ? MDP_TAG_INT : mdp_tag(rs_value),
                    opcode == MDP_OP_MUL ? multiply_result[31:0]
                                         : multiply_result[63:32]);
              end
              MDP_OP_ASH, MDP_OP_LSH: begin
                logic [31:0] shifted;
                shifted = opcode == MDP_OP_ASH
                    ? arithmetic_shift(left_data, $signed(right_data))
                    : logical_shift(left_data, $signed(right_data));
                if (checked && (mdp_tag(rs_value) != MDP_TAG_INT
                                || mdp_tag(op0_value) != MDP_TAG_INT)) begin
                  begin_fault(mdp_tag(rs_value) != MDP_TAG_INT
                                  ? type_fault_for(rs_value) : type_fault_for(op0_value),
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked && $signed(right_data) > 0
                             && ((opcode == MDP_OP_ASH
                                  && arithmetic_shift(shifted, -$signed(right_data)) != left_data)
                                 || (opcode == MDP_OP_LSH
                                  && logical_shift(shifted, -$signed(right_data)) != left_data))) begin
                  begin_fault(MDP_FAULT_OVERFLOW, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2] <= mdp_word(
                    checked ? MDP_TAG_INT : mdp_tag(rs_value), shifted);
              end
              MDP_OP_ROT: begin
                if (checked && (mdp_tag(rs_value) != MDP_TAG_INT
                                || mdp_tag(op0_value) != MDP_TAG_INT)) begin
                  begin_fault(mdp_tag(rs_value) != MDP_TAG_INT
                                  ? type_fault_for(rs_value) : type_fault_for(op0_value),
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2] <= mdp_word(
                    checked ? MDP_TAG_INT : mdp_tag(rs_value),
                    rotate_left(left_data, right_data[4:0]));
              end
              MDP_OP_AND, MDP_OP_OR, MDP_OP_XOR: begin
                logic legal_pair;
                legal_pair = (mdp_tag(rs_value) == MDP_TAG_INT
                              && mdp_tag(op0_value) == MDP_TAG_INT)
                          || (mdp_tag(rs_value) == MDP_TAG_BOOL
                              && mdp_tag(op0_value) == MDP_TAG_BOOL);
                if (checked && !legal_pair) begin
                  begin_fault(mdp_tag(rs_value) != MDP_TAG_INT
                              && mdp_tag(rs_value) != MDP_TAG_BOOL
                                  ? type_fault_for(rs_value)
                                  : (mdp_tag(op0_value) != MDP_TAG_INT
                                     && mdp_tag(op0_value) != MDP_TAG_BOOL)
                                    ? type_fault_for(op0_value) : MDP_FAULT_TYPE,
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  unique case (opcode)
                    MDP_OP_AND: arithmetic_result = left_data & right_data;
                    MDP_OP_OR: arithmetic_result = left_data | right_data;
                    default: arithmetic_result = left_data ^ right_data;
                  endcase
                  data_register[execution_context][op2]
                      <= mdp_word(mdp_tag(rs_value), arithmetic_result);
                end
              end
              MDP_OP_FFB: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2]
                    <= mdp_int(find_first_bit(op0_value[31:0]));
              end
              MDP_OP_NOT: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT
                            && mdp_tag(op0_value) != MDP_TAG_BOOL) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (mdp_tag(op0_value) == MDP_TAG_BOOL) begin
                  data_register[execution_context][op2]
                      <= mdp_word(MDP_TAG_BOOL, {op0_value[31:1], ~op0_value[0]});
                end else data_register[execution_context][op2]
                    <= mdp_word(checked ? MDP_TAG_INT : mdp_tag(op0_value),
                                ~op0_value[31:0]);
              end
              MDP_OP_NEG: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked && op0_value[31:0] == 32'h8000_0000) begin
                  begin_fault(MDP_FAULT_OVERFLOW, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2] <= mdp_word(
                    checked ? MDP_TAG_INT : mdp_tag(op0_value), -op0_value[31:0]);
              end
              MDP_OP_LT, MDP_OP_LE, MDP_OP_GE, MDP_OP_GT: begin
                logic legal_pair;
                logic comparison;
                legal_pair = mdp_tag(rs_value) == mdp_tag(op0_value)
                    && (mdp_tag(rs_value) == MDP_TAG_INT
                        || mdp_tag(rs_value) == MDP_TAG_BOOL);
                if (checked && !legal_pair) begin
                  begin_fault(type_fault_for(
                      mdp_tag(rs_value) != MDP_TAG_INT
                      && mdp_tag(rs_value) != MDP_TAG_BOOL ? rs_value : op0_value),
                      1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  unique case (opcode)
                    MDP_OP_LT: comparison = $signed(left_data) < $signed(right_data);
                    MDP_OP_LE: comparison = $signed(left_data) <= $signed(right_data);
                    MDP_OP_GE: comparison = $signed(left_data) >= $signed(right_data);
                    default: comparison = $signed(left_data) > $signed(right_data);
                  endcase
                  data_register[execution_context][op2] <= mdp_bool(comparison);
                end
              end
              MDP_OP_EQUAL, MDP_OP_NEQUAL: begin
                logic legal_pair;
                logic comparison;
                legal_pair = mdp_tag(rs_value) == mdp_tag(op0_value)
                    && (mdp_tag(rs_value) == MDP_TAG_INT
                        || mdp_tag(rs_value) == MDP_TAG_BOOL
                        || mdp_tag(rs_value) == MDP_TAG_SYM);
                if (checked && !legal_pair) begin
                  begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  comparison = left_data == right_data;
                  if (opcode == MDP_OP_NEQUAL) comparison = !comparison;
                  data_register[execution_context][op2] <= mdp_bool(comparison);
                end
              end
              MDP_OP_EQ, MDP_OP_NEQ: begin
                if (checked && (mdp_tag(rs_value) == MDP_TAG_CFUT
                                || mdp_tag(rs_value) == MDP_TAG_FUT
                                || mdp_tag(op0_value) == MDP_TAG_CFUT
                                || mdp_tag(op0_value) == MDP_TAG_FUT)) begin
                  begin_fault((mdp_tag(rs_value) == MDP_TAG_CFUT
                               || mdp_tag(op0_value) == MDP_TAG_CFUT)
                                  ? MDP_FAULT_CFUT : MDP_FAULT_FUT,
                              1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else data_register[execution_context][op2] <= mdp_bool(
                    opcode == MDP_OP_EQ ? rs_value == op0_value
                                        : rs_value != op0_value);
              end
              MDP_OP_XLATE, MDP_OP_PROBE: begin
                if (op0_kind != DEST_DATA_REGISTER
                    && op0_kind != DEST_ADDRESS_REGISTER) begin
                  begin_fault(MDP_FAULT_ILGINST, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (checked && mdp_tag(rs_value) == MDP_TAG_CFUT) begin
                  begin_fault(MDP_FAULT_CFUT, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  table_key <= rs_value;
                  table_data <= '0;
                  table_row_address <= (tbm_register[29:10]
                      | (rs_value[19:0] & {10'b0, tbm_register[9:0]}))
                      & 20'hffffc;
                  table_word_index <= '0;
                  result_destination_kind <= op0_kind;
                  result_destination_register <= op0_register_number;
                  state <= CORE_TABLE_READ;
                  operation_complete = 1'b0;
                end
              end
              MDP_OP_ENTER: begin
                if (checked && mdp_tag(op0_value) == MDP_TAG_CFUT) begin
                  begin_fault(MDP_FAULT_CFUT, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  table_key <= op0_value;
                  table_data <= rs_value;
                  table_row_address <= (tbm_register[29:10]
                      | (op0_value[19:0] & {10'b0, tbm_register[9:0]}))
                      & 20'hffffc;
                  table_word_index <= '0;
                  state <= CORE_TABLE_READ;
                  operation_complete = 1'b0;
                end
              end
              MDP_OP_INVAL: begin
                for (int context_index = 0; context_index < 2; context_index++) begin
                  for (int register_number = 0; register_number < 4; register_number++) begin
                    address_register[context_index][register_number][30]
                        <= address_register[context_index][register_number][31];
                  end
                end
              end
              MDP_OP_SUSPEND: begin
                if (execution_background) begin
                  catastrophe <= 1'b1;
                  state <= CORE_FETCH;
                end else begin
                  state <= CORE_SUSPEND;
                end
                operation_complete = 1'b0;
              end
              MDP_OP_CALL: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  operand0_register <= op0_value;
                  state <= CORE_CALL;
                  operation_complete = 1'b0;
                end
              end
              MDP_OP_SEND, MDP_OP_SENDE, MDP_OP_SEND2, MDP_OP_SEND2E: begin
                if (checked && mdp_tag(op0_value) == MDP_TAG_CFUT) begin
                  begin_fault(MDP_FAULT_CFUT, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else if (!send_ready) begin
                  begin_fault(MDP_FAULT_SEND, 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  interrupt_flag <= !(opcode == MDP_OP_SENDE
                                      || opcode == MDP_OP_SEND2E);
                end
              end
              MDP_OP_BR, MDP_OP_BNIL, MDP_OP_BNNIL,
              MDP_OP_BF, MDP_OP_BT, MDP_OP_BZ, MDP_OP_BNZ: begin
                if (checked && mdp_tag(op0_value) != MDP_TAG_INT) begin
                  begin_fault(type_fault_for(op0_value), 1'b1, op0_value, rs_value);
                  operation_complete = 1'b0;
                end else begin
                  unique case (opcode)
                    MDP_OP_BR: branch_taken = 1'b1;
                    MDP_OP_BNIL: branch_taken = rs_value == mdp_word(MDP_TAG_SYM, 32'b0);
                    MDP_OP_BNNIL: branch_taken = rs_value != mdp_word(MDP_TAG_SYM, 32'b0);
                    MDP_OP_BF: branch_taken = !rs_value[0];
                    MDP_OP_BT: branch_taken = rs_value[0];
                    MDP_OP_BZ: branch_taken = rs_value[31:0] == 0;
                    default: branch_taken = rs_value[31:0] != 0;
                  endcase
                  if (checked && opcode >= MDP_OP_BF && opcode <= MDP_OP_BT
                              && mdp_tag(rs_value) != MDP_TAG_BOOL) begin
                    begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                    operation_complete = 1'b0;
                  end else if (checked && opcode >= MDP_OP_BZ
                                      && mdp_tag(rs_value) != MDP_TAG_INT) begin
                    begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                    operation_complete = 1'b0;
                  end else if (checked && (opcode == MDP_OP_BNIL || opcode == MDP_OP_BNNIL)
                                      && (mdp_tag(rs_value) == MDP_TAG_CFUT
                                          || mdp_tag(rs_value) == MDP_TAG_FUT)) begin
                    begin_fault(type_fault_for(rs_value), 1'b1, op0_value, rs_value);
                    operation_complete = 1'b0;
                  end else if (branch_taken) begin
                    ip_register[execution_context] <= next_word_ip(
                        mdp_ip(ip_register[execution_context][31],
                               ip_register[execution_context][30],
                               instruction_word_offset, 1'b0,
                               ip_register[execution_context][8]),
                        $signed(op0_value[19:0]));
                  end
                end
              end
              default: begin
                begin_fault(MDP_FAULT_ILGINST, 1'b1, op0_value, rs_value);
                operation_complete = 1'b0;
              end
            endcase
          end
          if (operation_complete) begin
            retired_instructions <= retired_instructions + 1'b1;
            operand0_loaded <= 1'b0;
            state <= CORE_FETCH;
          end
        end

        CORE_OP0_READ: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_OP0_READ_WAIT;
        end

        CORE_OP0_READ_WAIT: begin
          if (memory_response_valid) begin
            operand0_register <= memory_response_rdata;
            if (memory_response_dram_error) begin
              begin_fault(MDP_FAULT_DRAMERR, 1'b1, memory_response_rdata, rs_value);
            end else begin
              operand0_loaded <= 1'b1;
              state <= CORE_EXECUTE;
            end
          end
        end

        CORE_RESULT_WRITE: begin
          if (memory_request_valid && memory_request_ready) begin
            retired_instructions <= retired_instructions + 1'b1;
            state <= CORE_FETCH;
          end
        end

        CORE_VECTOR: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_VECTOR_WAIT;
        end

        CORE_VECTOR_WAIT: begin
          if (memory_response_valid) begin
            if (memory_response_dram_error || mdp_tag(memory_response_rdata) != MDP_TAG_IP) begin
              if (pending_fault == MDP_FAULT_CATASTROPHE) begin
                catastrophe <= 1'b1;
                state <= CORE_FETCH;
              end else begin
                pending_fault <= MDP_FAULT_CATASTROPHE;
                last_fault <= MDP_FAULT_CATASTROPHE;
                state <= CORE_VECTOR;
              end
            end else begin
              ip_register[fault_context] <= memory_response_rdata;
              background_flag <= fault_context == CONTEXT_BACKGROUND;
              priority_flag <= fault_priority;
              state <= CORE_FETCH;
            end
          end
        end

        CORE_CALL: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_CALL_WAIT;
        end

        CORE_CALL_WAIT: begin
          if (memory_response_valid) begin
            if (memory_response_dram_error) begin
              begin_fault(MDP_FAULT_DRAMERR, 1'b1, operand0_register, rs_value);
            end else if (mdp_tag(memory_response_rdata) != MDP_TAG_IP) begin
              begin_fault(type_fault_for(memory_response_rdata), 1'b1,
                          operand0_register, rs_value);
            end else begin
              fip_register[execution_context] <= ip_register[execution_context];
              ip_register[execution_context] <= memory_response_rdata;
              retired_instructions <= retired_instructions + 1'b1;
              state <= CORE_FETCH;
            end
          end
        end

        CORE_DISPATCH: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_DISPATCH_WAIT;
        end

        CORE_DISPATCH_WAIT: begin
          if (memory_response_valid) begin
            execution_context <= {1'b0, dispatch_priority};
            execution_priority <= dispatch_priority;
            execution_background <= 1'b0;
            if (memory_response_dram_error) begin
              pending_fault <= MDP_FAULT_DRAMERR;
              last_fault <= MDP_FAULT_DRAMERR;
              fault_context <= {1'b0, dispatch_priority};
              fault_priority <= dispatch_priority;
              fir_register[dispatch_priority] <= mdp_word(MDP_TAG_SYM, 32'b0);
              state <= CORE_VECTOR;
            end else if (mdp_tag(memory_response_rdata) != MDP_TAG_MSG
                         || memory_response_rdata[9:0] == 0) begin
              pending_fault <= MDP_FAULT_MSG;
              last_fault <= MDP_FAULT_MSG;
              fault_context <= {1'b0, dispatch_priority};
              fault_priority <= dispatch_priority;
              fir_register[dispatch_priority] <= mdp_word(MDP_TAG_SYM, 32'b0);
              state <= CORE_VECTOR;
            end else begin
              priority_flag <= dispatch_priority;
              background_flag <= 1'b0;
              active_message[dispatch_priority] <= 1'b1;
              queue_addressing[dispatch_priority] <= 1'b1;
              address_register[{1'b0, dispatch_priority}][3] <= mdp_addr(
                  1'b0, 1'b0, qhl[dispatch_priority][29:10],
                  memory_response_rdata[9:0]);
              ip_register[{1'b0, dispatch_priority}] <= mdp_ip(
                  memory_response_rdata[31], memory_response_rdata[30],
                  memory_response_rdata[29:10], 1'b0, 1'b1);
              state <= CORE_FETCH;
            end
          end
        end

        CORE_TABLE_READ: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_TABLE_READ_WAIT;
        end

        CORE_TABLE_READ_WAIT: begin
          if (memory_response_valid) begin
            if (memory_response_dram_error) begin
              begin_fault(MDP_FAULT_DRAMERR, 1'b1, op0_value, rs_value);
            end else begin
              table_row[table_word_index] <= memory_response_rdata;
              if (table_word_index == 2'd3) begin
                state <= CORE_TABLE_EVALUATE;
              end else begin
                table_word_index <= table_word_index + 1'b1;
                state <= CORE_TABLE_READ;
              end
            end
          end
        end

        CORE_TABLE_EVALUATE: begin
          if (opcode == MDP_OP_ENTER) begin
            table_way <= table_hit_comb ? table_hit_way_comb : replacement_way;
            replacement_way <= ~replacement_way;
            state <= CORE_TABLE_WRITE_DATA;
          end else if (opcode == MDP_OP_XLATE
                       && (!table_hit_comb
                           || table_result_comb == mdp_word(MDP_TAG_SYM, 32'b0))) begin
            begin_fault(MDP_FAULT_XLATE, 1'b1, op0_value, rs_value);
          end else begin
            result_word <= table_hit_comb
                ? table_result_comb : mdp_word(MDP_TAG_SYM, 32'b0);
            if (result_destination_kind == DEST_DATA_REGISTER) begin
              data_register[execution_context][result_destination_register]
                  <= table_hit_comb
                      ? table_result_comb : mdp_word(MDP_TAG_SYM, 32'b0);
            end else begin
              address_register[execution_context][result_destination_register]
                  <= table_hit_comb
                      ? table_result_comb : mdp_word(MDP_TAG_SYM, 32'b0);
              if (!execution_background) begin
                id_register[execution_priority][result_destination_register] <= table_key;
              end
            end
            retired_instructions <= retired_instructions + 1'b1;
            state <= CORE_FETCH;
          end
        end

        CORE_TABLE_WRITE_DATA: begin
          if (memory_request_valid && memory_request_ready) state <= CORE_TABLE_WRITE_KEY;
        end

        CORE_TABLE_WRITE_KEY: begin
          if (memory_request_valid && memory_request_ready) begin
            retired_instructions <= retired_instructions + 1'b1;
            state <= CORE_FETCH;
          end
        end

        CORE_SUSPEND: begin
          if (suspend_ready) begin
            if (suspend_early) begin
              begin_fault(MDP_FAULT_EARLY, 1'b1, op0_value, rs_value);
            end else begin
              active_message[execution_priority] <= 1'b0;
              queue_addressing[execution_priority] <= 1'b0;
              if (execution_priority == 1'b1 && active_message[0]) begin
                priority_flag <= 1'b0;
                background_flag <= 1'b0;
              end else begin
                background_flag <= 1'b1;
              end
              retired_instructions <= retired_instructions + 1'b1;
              state <= CORE_FETCH;
            end
          end
        end

        default: state <= CORE_FETCH;
      endcase
    end
  end
endmodule
