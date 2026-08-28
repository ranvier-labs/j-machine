`include "cl_id_defines.vh"

module cl_j_machine (
  `include "cl_ports.vh"
);
  logic rst_main_n_sync;
  logic platform_reset;
  logic run_enable;
  logic soft_reset;
  logic [63:0] host_memory_base;
  logic [8:0] debug_node;
  logic clear_memory_errors;
  logic memory_busy;
  logic memory_write_error;
  logic memory_read_error;
  logic any_catastrophe;
  logic [15:0] debug_node_number;
  logic debug_background;
  logic debug_priority;
  logic debug_interrupt_mask;
  logic debug_fault_mode;
  logic debug_unchecked_mode;
  logic [4:0] debug_last_fault;
  logic debug_catastrophe;
  logic [63:0] debug_retired_instructions;
  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_ip;
  logic [j_machine_pkg::MDP_WORD_WIDTH-1:0] debug_r0;
  logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_pending;
  logic [j_machine_pkg::J_PRIORITIES-1:0] debug_queue_full;

  assign rst_main_n_sync = rst_main_n;
  assign platform_reset = !rst_main_n || sh_cl_flr_assert || soft_reset;

  assign cl_sh_id0 = `CL_SH_ID0;
  assign cl_sh_id1 = `CL_SH_ID1;
  assign cl_sh_status0 = {
    26'b0,
    host_memory_base[5:0] != 6'b0,
    any_catastrophe,
    memory_read_error,
    memory_write_error,
    memory_busy,
    run_enable
  };
  assign cl_sh_status1 = {16'b0, debug_node_number};
  assign cl_sh_status2 = debug_retired_instructions[31:0];
  assign cl_sh_status_vled = {
    3'b0,
    debug_node,
    memory_read_error,
    memory_write_error,
    any_catastrophe,
    run_enable
  };

  always_ff @(posedge clk_main_a0) begin
    if (!rst_main_n) begin
      cl_sh_flr_done <= 1'b0;
    end else begin
      cl_sh_flr_done <= sh_cl_flr_assert;
    end
  end

  cl_j_machine_ocl #(.NODE_INDEX_WIDTH(9)) ocl (
    .clk(clk_main_a0),
    .reset(!rst_main_n || sh_cl_flr_assert),
    .s_awaddr(ocl_cl_awaddr),
    .s_awvalid(ocl_cl_awvalid),
    .s_awready(cl_ocl_awready),
    .s_wdata(ocl_cl_wdata),
    .s_wstrb(ocl_cl_wstrb),
    .s_wvalid(ocl_cl_wvalid),
    .s_wready(cl_ocl_wready),
    .s_bresp(cl_ocl_bresp),
    .s_bvalid(cl_ocl_bvalid),
    .s_bready(ocl_cl_bready),
    .s_araddr(ocl_cl_araddr),
    .s_arvalid(ocl_cl_arvalid),
    .s_arready(cl_ocl_arready),
    .s_rdata(cl_ocl_rdata),
    .s_rresp(cl_ocl_rresp),
    .s_rvalid(cl_ocl_rvalid),
    .s_rready(ocl_cl_rready),
    .run_enable,
    .soft_reset,
    .host_memory_base,
    .debug_node,
    .clear_memory_errors,
    .memory_busy,
    .memory_write_error,
    .memory_read_error,
    .any_catastrophe,
    .debug_node_number,
    .debug_background,
    .debug_priority,
    .debug_interrupt_mask,
    .debug_fault_mode,
    .debug_unchecked_mode,
    .debug_last_fault,
    .debug_catastrophe,
    .debug_retired_instructions,
    .debug_ip,
    .debug_r0,
    .debug_queue_pending,
    .debug_queue_full
  );

  j_machine_f2_core core (
    .clk(clk_main_a0),
    .reset(platform_reset),
    .run_enable(run_enable && sh_cl_pwr_state == 2'b00),
    .host_memory_base,
    .debug_node,
    .clear_memory_errors,
    .memory_busy,
    .memory_write_error,
    .memory_read_error,
    .any_catastrophe,
    .debug_node_number,
    .debug_background,
    .debug_priority,
    .debug_interrupt_mask,
    .debug_fault_mode,
    .debug_unchecked_mode,
    .debug_last_fault,
    .debug_catastrophe,
    .debug_retired_instructions,
    .debug_ip,
    .debug_r0,
    .debug_queue_pending,
    .debug_queue_full,
    .pcim_awid(cl_sh_pcim_awid),
    .pcim_awaddr(cl_sh_pcim_awaddr),
    .pcim_awlen(cl_sh_pcim_awlen),
    .pcim_awsize(cl_sh_pcim_awsize),
    .pcim_awburst(cl_sh_pcim_awburst),
    .pcim_awcache(cl_sh_pcim_awcache),
    .pcim_awlock(cl_sh_pcim_awlock),
    .pcim_awprot(cl_sh_pcim_awprot),
    .pcim_awqos(cl_sh_pcim_awqos),
    .pcim_awuser(cl_sh_pcim_awuser),
    .pcim_awvalid(cl_sh_pcim_awvalid),
    .pcim_awready(sh_cl_pcim_awready),
    .pcim_wid(cl_sh_pcim_wid),
    .pcim_wdata(cl_sh_pcim_wdata),
    .pcim_wstrb(cl_sh_pcim_wstrb),
    .pcim_wlast(cl_sh_pcim_wlast),
    .pcim_wuser(cl_sh_pcim_wuser),
    .pcim_wvalid(cl_sh_pcim_wvalid),
    .pcim_wready(sh_cl_pcim_wready),
    .pcim_bid(sh_cl_pcim_bid),
    .pcim_bresp(sh_cl_pcim_bresp),
    .pcim_bvalid(sh_cl_pcim_bvalid),
    .pcim_bready(cl_sh_pcim_bready),
    .pcim_arid(cl_sh_pcim_arid),
    .pcim_araddr(cl_sh_pcim_araddr),
    .pcim_arlen(cl_sh_pcim_arlen),
    .pcim_arsize(cl_sh_pcim_arsize),
    .pcim_arburst(cl_sh_pcim_arburst),
    .pcim_arcache(cl_sh_pcim_arcache),
    .pcim_arlock(cl_sh_pcim_arlock),
    .pcim_arprot(cl_sh_pcim_arprot),
    .pcim_arqos(cl_sh_pcim_arqos),
    .pcim_aruser(cl_sh_pcim_aruser),
    .pcim_arvalid(cl_sh_pcim_arvalid),
    .pcim_arready(sh_cl_pcim_arready),
    .pcim_rid(sh_cl_pcim_rid),
    .pcim_rdata(sh_cl_pcim_rdata),
    .pcim_rresp(sh_cl_pcim_rresp),
    .pcim_rlast(sh_cl_pcim_rlast),
    .pcim_ruser(sh_cl_pcim_ruser),
    .pcim_rvalid(sh_cl_pcim_rvalid),
    .pcim_rready(cl_sh_pcim_rready)
  );

  `include "unused_ddr_template.inc"
  `include "unused_cl_sda_template.inc"
  `include "unused_apppf_irq_template.inc"
  `include "unused_dma_pcis_template.inc"

  assign cl_sh_dma_pcis_bid[15:6] = '0;
  assign cl_sh_dma_pcis_rid[15:6] = '0;

  assign tdo = 1'b0;
  assign hbm_apb_paddr_0 = '0;
  assign hbm_apb_pprot_0 = '0;
  assign hbm_apb_psel_0 = 1'b0;
  assign hbm_apb_penable_0 = 1'b0;
  assign hbm_apb_pwrite_0 = 1'b0;
  assign hbm_apb_pwdata_0 = '0;
  assign hbm_apb_pstrb_0 = '0;
  assign hbm_apb_pready_0 = 1'b1;
  assign hbm_apb_prdata_0 = '0;
  assign hbm_apb_pslverr_0 = 1'b0;
  assign hbm_apb_paddr_1 = '0;
  assign hbm_apb_pprot_1 = '0;
  assign hbm_apb_psel_1 = 1'b0;
  assign hbm_apb_penable_1 = 1'b0;
  assign hbm_apb_pwrite_1 = 1'b0;
  assign hbm_apb_pwdata_1 = '0;
  assign hbm_apb_pstrb_1 = '0;
  assign hbm_apb_pready_1 = 1'b1;
  assign hbm_apb_prdata_1 = '0;
  assign hbm_apb_pslverr_1 = 1'b0;
  assign PCIE_EP_TXP = '0;
  assign PCIE_EP_TXN = '0;
  assign PCIE_RP_PERSTN = 1'b0;
  assign PCIE_RP_TXP = '0;
  assign PCIE_RP_TXN = '0;

  logic unused_shell_inputs;
  assign unused_shell_inputs = ^{
    clk_hbm_ref,
    sh_cl_ctl0,
    sh_cl_ctl1,
    sh_cl_ctl2,
    sh_cl_status_vdip,
    cfg_max_payload,
    cfg_max_read_req,
    ocl_cl_awuser,
    ocl_cl_aruser,
    drck,
    shift,
    tdi,
    update,
    sel,
    tms,
    tck,
    runtest,
    reset,
    capture,
    bscanid_en,
    sh_cl_glcount0,
    sh_cl_glcount1,
    hbm_apb_preset_n_0,
    hbm_apb_preset_n_1,
    PCIE_EP_PERSTN,
    PCIE_EP_REF_CLK_P,
    PCIE_EP_REF_CLK_N,
    PCIE_EP_RXP,
    PCIE_EP_RXN,
    PCIE_RP_REF_CLK_P,
    PCIE_RP_REF_CLK_N,
    PCIE_RP_RXP,
    PCIE_RP_RXN
  };
endmodule
