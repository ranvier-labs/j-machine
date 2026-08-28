# Populate the HDK post-encryption source directory. The common AWS build flow
# sets src_post_enc_dir, HDK_SHELL_DESIGN_DIR, CL_DIR, and ENCRYPT.
if {[llength [glob -nocomplain -dir $src_post_enc_dir *]] != 0} {
  eval file delete -force [glob $src_post_enc_dir/*]
}

set interfaces_dir $HDK_SHELL_DESIGN_DIR/interfaces
foreach template {
  unused_ddr_template.inc
  unused_cl_sda_template.inc
  unused_apppf_irq_template.inc
  unused_dma_pcis_template.inc
} {
  file copy -force $interfaces_dir/$template $src_post_enc_dir
}

foreach source {
  cl_id_defines.vh
  cl_j_machine.sv
  cl_j_machine_ocl.sv
  j_machine_f2_core.sv
  j_machine_f2_pcim_memory.sv
} {
  file copy -force $CL_DIR/design/$source $src_post_enc_dir
}

foreach source {
  j_machine_pkg.sv
  mdp_network_input.sv
  mdp_network_output.sv
  mdp_message_unit.sv
  j_mdp_core.sv
  j_mesh_router.sv
  j_node.sv
  j_machine_mesh.sv
} {
  file copy -force $CL_DIR/design/rtl/$source $src_post_enc_dir
}

exec chmod +w {*}[glob ${src_post_enc_dir}/*]
if {$ENCRYPT} {
  encrypt -k ${HDK_SHELL_DIR}/build/scripts/vivado_keyfile.txt \
      -lang verilog -quiet \
      [glob -nocomplain -- ${src_post_enc_dir}/*.{v,sv,vh,inc}]
}
