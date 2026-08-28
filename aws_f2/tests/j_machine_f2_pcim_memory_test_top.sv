module j_machine_f2_pcim_memory_test_top (
  input  logic clk,
  input  logic reset,
  input  logic [63:0] host_memory_base,
  input  logic [3:0] cpu_request_valid,
  output logic [3:0] cpu_request_ready,
  input  logic [3:0] cpu_request_write,
  input  logic [19:0] cpu_request_address,
  input  logic [35:0] cpu_request_wdata,
  output logic [3:0] cpu_response_valid,
  output logic [35:0] cpu_response_rdata0,
  output logic [35:0] cpu_response_rdata1,
  output logic [35:0] cpu_response_rdata2,
  output logic [35:0] cpu_response_rdata3,
  output logic [3:0] cpu_response_dram_error,
  input  logic [3:0] qrb_write,
  output logic [3:0] qrb_ready,
  input  logic [17:0] qrb_row_address,
  input  logic [143:0] qrb_write_data,
  input  logic [3:0] qrb_write_enable,
  output logic busy,
  output logic write_error,
  output logic read_error,
  input  logic clear_errors,
  output logic [63:0] pcim_awaddr,
  output logic pcim_awvalid,
  input  logic pcim_awready,
  output logic [511:0] pcim_wdata,
  output logic [63:0] pcim_wstrb,
  output logic pcim_wvalid,
  input  logic pcim_wready,
  input  logic [1:0] pcim_bresp,
  input  logic pcim_bvalid,
  output logic pcim_bready,
  output logic [63:0] pcim_araddr,
  output logic pcim_arvalid,
  input  logic pcim_arready,
  input  logic [511:0] pcim_rdata,
  input  logic [1:0] pcim_rresp,
  input  logic pcim_rlast,
  input  logic pcim_rvalid,
  output logic pcim_rready
);
  logic [3:0][19:0] addresses;
  logic [3:0][35:0] write_words;
  logic [3:0][35:0] response_words;
  logic [3:0][17:0] row_addresses;
  logic [3:0][143:0] row_data;
  logic [3:0][3:0] row_enable;

  always_comb begin
    for (int node = 0; node < 4; node++) begin
      addresses[node] = cpu_request_address;
      write_words[node] = cpu_request_wdata;
      row_addresses[node] = qrb_row_address;
      row_data[node] = qrb_write_data;
      row_enable[node] = qrb_write_enable;
    end
    cpu_response_rdata0 = response_words[0];
    cpu_response_rdata1 = response_words[1];
    cpu_response_rdata2 = response_words[2];
    cpu_response_rdata3 = response_words[3];
  end

  j_machine_f2_pcim_memory #(
    .NODES(4),
    .NODE_INDEX_WIDTH(2)
  ) dut (
    .clk,
    .reset,
    .host_memory_base,
    .cpu_request_valid,
    .cpu_request_ready,
    .cpu_request_write,
    .cpu_request_address(addresses),
    .cpu_request_wdata(write_words),
    .cpu_response_valid,
    .cpu_response_rdata(response_words),
    .cpu_response_dram_error,
    .qrb_write,
    .qrb_ready,
    .qrb_row_address(row_addresses),
    .qrb_write_data(row_data),
    .qrb_write_enable(row_enable),
    .busy,
    .write_error,
    .read_error,
    .clear_errors,
    .pcim_awid(),
    .pcim_awaddr,
    .pcim_awlen(),
    .pcim_awsize(),
    .pcim_awburst(),
    .pcim_awcache(),
    .pcim_awlock(),
    .pcim_awprot(),
    .pcim_awqos(),
    .pcim_awuser(),
    .pcim_awvalid,
    .pcim_awready,
    .pcim_wid(),
    .pcim_wdata,
    .pcim_wstrb,
    .pcim_wlast(),
    .pcim_wuser(),
    .pcim_wvalid,
    .pcim_wready,
    .pcim_bid('0),
    .pcim_bresp,
    .pcim_bvalid,
    .pcim_bready,
    .pcim_arid(),
    .pcim_araddr,
    .pcim_arlen(),
    .pcim_arsize(),
    .pcim_arburst(),
    .pcim_arcache(),
    .pcim_arlock(),
    .pcim_arprot(),
    .pcim_arqos(),
    .pcim_aruser(),
    .pcim_arvalid,
    .pcim_arready,
    .pcim_rid('0),
    .pcim_rdata,
    .pcim_rresp,
    .pcim_rlast,
    .pcim_ruser('0),
    .pcim_rvalid,
    .pcim_rready
  );
endmodule
