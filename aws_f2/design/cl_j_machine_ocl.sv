module cl_j_machine_ocl #(
  parameter int NODE_INDEX_WIDTH = 9
) (
  input  logic clk,
  input  logic reset,

  input  logic [31:0] s_awaddr,
  input  logic s_awvalid,
  output logic s_awready,
  input  logic [31:0] s_wdata,
  input  logic [3:0] s_wstrb,
  input  logic s_wvalid,
  output logic s_wready,
  output logic [1:0] s_bresp,
  output logic s_bvalid,
  input  logic s_bready,
  input  logic [31:0] s_araddr,
  input  logic s_arvalid,
  output logic s_arready,
  output logic [31:0] s_rdata,
  output logic [1:0] s_rresp,
  output logic s_rvalid,
  input  logic s_rready,

  output logic run_enable,
  output logic soft_reset,
  output logic [63:0] host_memory_base,
  output logic [NODE_INDEX_WIDTH-1:0] debug_node,
  output logic clear_memory_errors,

  input  logic memory_busy,
  input  logic memory_write_error,
  input  logic memory_read_error,
  input  logic any_catastrophe,
  input  logic [15:0] debug_node_number,
  input  logic debug_background,
  input  logic debug_priority,
  input  logic debug_interrupt_mask,
  input  logic debug_fault_mode,
  input  logic debug_unchecked_mode,
  input  logic [4:0] debug_last_fault,
  input  logic debug_catastrophe,
  input  logic [63:0] debug_retired_instructions,
  input  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_ip,
  input  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_r0,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_pending,
  input  logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_full
);
  import j_machine_pkg::*;

  localparam logic [31:0] REG_ID = 32'h0000_0000;
  localparam logic [31:0] REG_VERSION = 32'h0000_0004;
  localparam logic [31:0] REG_CONTROL = 32'h0000_0008;
  localparam logic [31:0] REG_STATUS = 32'h0000_000c;
  localparam logic [31:0] REG_MEMORY_BASE_LOW = 32'h0000_0010;
  localparam logic [31:0] REG_MEMORY_BASE_HIGH = 32'h0000_0014;
  localparam logic [31:0] REG_MEMORY_BYTES_LOW = 32'h0000_0018;
  localparam logic [31:0] REG_MEMORY_BYTES_HIGH = 32'h0000_001c;
  localparam logic [31:0] REG_DEBUG_NODE = 32'h0000_0020;
  localparam logic [31:0] REG_NODE_STATUS = 32'h0000_0024;
  localparam logic [31:0] REG_RETIRED_LOW = 32'h0000_0028;
  localparam logic [31:0] REG_RETIRED_HIGH = 32'h0000_002c;
  localparam logic [31:0] REG_IP_DATA = 32'h0000_0030;
  localparam logic [31:0] REG_IP_TAG = 32'h0000_0034;
  localparam logic [31:0] REG_R0_DATA = 32'h0000_0038;
  localparam logic [31:0] REG_R0_TAG = 32'h0000_003c;
  localparam logic [31:0] REG_MEMORY_ERRORS = 32'h0000_0040;

  logic aw_held;
  logic [31:0] awaddr_held;
  logic w_held;
  logic [31:0] wdata_held;
  logic [3:0] wstrb_held;
  logic aw_take;
  logic w_take;
  logic write_fire;
  logic [31:0] write_address;
  logic [31:0] write_data;
  logic [3:0] write_strobes;
  logic write_address_valid;
  logic [31:0] read_data;
  logic read_address_valid;

  function automatic logic [31:0] apply_strobes(
      input logic [31:0] previous,
      input logic [31:0] next_value,
      input logic [3:0] strobes
  );
    logic [31:0] result;
    result = previous;
    for (int byte_index = 0; byte_index < 4; byte_index++) begin
      if (strobes[byte_index]) begin
        result[byte_index*8 +: 8] = next_value[byte_index*8 +: 8];
      end
    end
    return result;
  endfunction

  assign s_awready = !aw_held && !s_bvalid;
  assign s_wready = !w_held && !s_bvalid;
  assign aw_take = s_awvalid && s_awready;
  assign w_take = s_wvalid && s_wready;
  assign write_fire = !s_bvalid && (aw_held || aw_take) && (w_held || w_take);
  assign write_address = aw_held ? awaddr_held : s_awaddr;
  assign write_data = w_held ? wdata_held : s_wdata;
  assign write_strobes = w_held ? wstrb_held : s_wstrb;
  assign s_arready = !s_rvalid;

  always_comb begin
    unique case (write_address)
      REG_CONTROL,
      REG_MEMORY_BASE_LOW,
      REG_MEMORY_BASE_HIGH,
      REG_DEBUG_NODE,
      REG_MEMORY_ERRORS: write_address_valid = 1'b1;
      default: write_address_valid = 1'b0;
    endcase
  end

  always_comb begin
    read_data = 32'b0;
    read_address_valid = 1'b1;
    unique case (s_araddr)
      REG_ID: read_data = 32'h4a4d_4632; // "JMF2"
      REG_VERSION: read_data = 32'h0001_0000;
      REG_CONTROL: read_data = {31'b0, run_enable};
      REG_STATUS: begin
        read_data[0] = run_enable;
        read_data[1] = memory_busy;
        read_data[2] = memory_write_error;
        read_data[3] = memory_read_error;
        read_data[4] = any_catastrophe;
        read_data[5] = host_memory_base[5:0] != 6'b0;
      end
      REG_MEMORY_BASE_LOW: read_data = host_memory_base[31:0];
      REG_MEMORY_BASE_HIGH: read_data = host_memory_base[63:32];
      REG_MEMORY_BYTES_LOW: read_data = 32'h0000_0000;
      REG_MEMORY_BYTES_HIGH: read_data = 32'h0000_0001;
      REG_DEBUG_NODE: read_data[NODE_INDEX_WIDTH-1:0] = debug_node;
      REG_NODE_STATUS: begin
        read_data[15:0] = debug_node_number;
        read_data[16] = debug_background;
        read_data[17] = debug_priority;
        read_data[18] = debug_interrupt_mask;
        read_data[19] = debug_fault_mode;
        read_data[20] = debug_unchecked_mode;
        read_data[25:21] = debug_last_fault;
        read_data[26] = debug_catastrophe;
        read_data[28:27] = debug_queue_pending;
        read_data[30:29] = debug_queue_full;
      end
      REG_RETIRED_LOW: read_data = debug_retired_instructions[31:0];
      REG_RETIRED_HIGH: read_data = debug_retired_instructions[63:32];
      REG_IP_DATA: read_data = debug_ip[31:0];
      REG_IP_TAG: read_data[3:0] = debug_ip[35:32];
      REG_R0_DATA: read_data = debug_r0[31:0];
      REG_R0_TAG: read_data[3:0] = debug_r0[35:32];
      REG_MEMORY_ERRORS: begin
        read_data[0] = memory_write_error;
        read_data[1] = memory_read_error;
      end
      default: begin
        read_data = 32'hdead_beef;
        read_address_valid = 1'b0;
      end
    endcase
  end

  always_ff @(posedge clk) begin
    soft_reset <= 1'b0;
    clear_memory_errors <= 1'b0;

    if (reset) begin
      aw_held <= 1'b0;
      awaddr_held <= 32'b0;
      w_held <= 1'b0;
      wdata_held <= 32'b0;
      wstrb_held <= 4'b0;
      s_bvalid <= 1'b0;
      s_bresp <= 2'b00;
      s_rvalid <= 1'b0;
      s_rdata <= 32'b0;
      s_rresp <= 2'b00;
      run_enable <= 1'b0;
      host_memory_base <= 64'b0;
      debug_node <= '0;
    end else begin
      if (s_bvalid && s_bready) s_bvalid <= 1'b0;
      if (s_rvalid && s_rready) s_rvalid <= 1'b0;

      if (aw_take) begin
        aw_held <= 1'b1;
        awaddr_held <= s_awaddr;
      end
      if (w_take) begin
        w_held <= 1'b1;
        wdata_held <= s_wdata;
        wstrb_held <= s_wstrb;
      end

      if (write_fire) begin
        aw_held <= 1'b0;
        w_held <= 1'b0;
        s_bvalid <= 1'b1;
        s_bresp <= write_address_valid ? 2'b00 : 2'b10;
        if (write_address_valid) begin
          unique case (write_address)
            REG_CONTROL: begin
              logic [31:0] control_value;
              control_value = apply_strobes(
                  {31'b0, run_enable}, write_data, write_strobes);
              run_enable <= control_value[0];
              soft_reset <= control_value[1];
            end
            REG_MEMORY_BASE_LOW: begin
              host_memory_base[31:0] <= apply_strobes(
                  host_memory_base[31:0], write_data, write_strobes);
            end
            REG_MEMORY_BASE_HIGH: begin
              host_memory_base[63:32] <= apply_strobes(
                  host_memory_base[63:32], write_data, write_strobes);
            end
            REG_DEBUG_NODE: begin
              logic [31:0] node_value;
              node_value = apply_strobes(
                  {{(32-NODE_INDEX_WIDTH){1'b0}}, debug_node},
                  write_data, write_strobes);
              debug_node <= node_value[NODE_INDEX_WIDTH-1:0];
            end
            REG_MEMORY_ERRORS: begin
              logic [31:0] error_value;
              error_value = apply_strobes(32'b0, write_data, write_strobes);
              clear_memory_errors <= |error_value[1:0];
            end
            default: begin end
          endcase
        end
      end

      if (s_arvalid && s_arready) begin
        s_rvalid <= 1'b1;
        s_rdata <= read_data;
        s_rresp <= read_address_valid ? 2'b00 : 2'b10;
      end
    end
  end

  property stable_read_response;
    @(posedge clk) disable iff (reset)
      s_rvalid && !s_rready |=> s_rvalid && $stable({s_rdata, s_rresp});
  endproperty
  assert property (stable_read_response);

  property stable_write_response;
    @(posedge clk) disable iff (reset)
      s_bvalid && !s_bready |=> s_bvalid && $stable(s_bresp);
  endproperty
  assert property (stable_write_response);
endmodule
