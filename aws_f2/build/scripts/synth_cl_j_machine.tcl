source ${HDK_SHELL_DIR}/build/scripts/synth_cl_header.tcl

print "Reading J-Machine customer-logic sources"
read_verilog -sv [list \
  ${src_post_enc_dir}/j_machine_pkg.sv \
  ${src_post_enc_dir}/mdp_network_input.sv \
  ${src_post_enc_dir}/mdp_network_output.sv \
  ${src_post_enc_dir}/mdp_message_unit.sv \
  ${src_post_enc_dir}/j_mdp_core.sv \
  ${src_post_enc_dir}/j_mesh_router.sv \
  ${src_post_enc_dir}/j_node.sv \
  ${src_post_enc_dir}/j_machine_mesh.sv \
  ${src_post_enc_dir}/j_machine_f2_pcim_memory.sv \
  ${src_post_enc_dir}/j_machine_f2_core.sv \
  ${src_post_enc_dir}/cl_j_machine_ocl.sv \
  ${src_post_enc_dir}/cl_j_machine.sv \
]

print "Reading J-Machine constraints"
read_xdc [list \
  ${constraints_dir}/cl_synth_user.xdc \
  ${constraints_dir}/cl_timing_user.xdc \
]
set_property PROCESSING_ORDER LATE [get_files cl_synth_user.xdc]
set_property PROCESSING_ORDER LATE [get_files cl_timing_user.xdc]

print "Synthesizing customer design ${CL}"
update_compile_order -fileset sources_1
synth_design -mode out_of_context \
             -top ${CL} \
             -part ${DEVICE_TYPE} \
             -keep_equivalent_registers

source ${HDK_SHELL_DIR}/build/scripts/synth_cl_footer.tcl
