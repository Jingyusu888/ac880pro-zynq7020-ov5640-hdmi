set root [file normalize [file join [file dirname [info script]] ..]]
set dest [file join $root camera_live]
set phase [lindex $argv 0]
set_param general.maxThreads 8
if {![file exists $dest/camera_live.xpr]} {
 create_project camera_live $dest -part xc7z020clg484-2
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 set src $root/cam_yolo.srcs/sources_1/new
 foreach mod {video_clock_reset video_timing tmds_encoder tmds_encode_rgb serializer_10to1 dvi_tx camera_clock_reset ov5640_control ov5640_config ov5640_init_ctrl sccb_master ov5640_capture ddr_clock_reset ddr_controller rgb565_packer frame_buffer_manager} {
  add_files $src/$mod.v
 }
 add_files $root/cam_yolo.srcs/sources_1/imports/camera_init/ov5640_init_table_rgb.v
 add_files [glob $root/rtl/camera/*.v]
 foreach ip {video_clk camera_clk ddr_clk mig_7series_0} {
  read_ip $dest/ip/$ip/$ip.xci
 }
 set_property CONFIG.XML_INPUT_FILE [file normalize $dest/ip/mig_7series_0/mig_camera.prj] [get_ips mig_7series_0]
 generate_target all [get_ips mig_7series_0]
 add_files -fileset constrs_1 $root/constraints/camera_hdmi.xdc
 set_property top camera_hdmi_top [get_filesets sources_1]
 update_compile_order -fileset sources_1
} else { open_project $dest/camera_live.xpr }
# The delivery copy synchronizes SDA; retain the original teaching source.
set old_sccb [get_files -quiet $root/cam_yolo.srcs/sources_1/new/sccb_master.v]
if {[llength $old_sccb]} {remove_files $old_sccb}
if {![llength [get_files -quiet $root/rtl/camera/sccb_master.v]]} {add_files $root/rtl/camera/sccb_master.v}
foreach clock_ip {video_clk camera_clk ddr_clk} {
 if {[get_property CONFIG.PRIM_SOURCE [get_ips $clock_ip]] ne "No_buffer"} {
  set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer}] [get_ips $clock_ip]
  generate_target all [get_ips $clock_ip]
 }
}
if {$phase eq "synth" || $phase eq "all"} {
 if {[get_property STATUS [get_runs synth_1]] ne "Not started"} {reset_run synth_1}
 launch_runs synth_1 -jobs 4
 wait_on_run synth_1
 if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis did not finish"}
 open_run synth_1
 report_utilization -file $dest/utilization_synth.rpt
 report_drc -file $dest/drc_synth.rpt
 close_design
}
if {$phase eq "impl" || $phase eq "all"} {
 set_property STEPS.WRITE_BITSTREAM.TCL.PRE $root/scripts/bitstream_timing_guard.tcl [get_runs impl_1]
 launch_runs impl_1 -to_step write_bitstream -jobs 4
 wait_on_run impl_1
 if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation/bitstream did not finish"}
 open_run impl_1
 report_timing_summary -file $dest/timing_final.rpt
 report_drc -file $dest/drc_final.rpt
 report_cdc -file $dest/cdc_final.rpt
 report_clocks -file $dest/clocks_final.rpt
 report_methodology -file $dest/methodology_final.rpt
 report_utilization -file $dest/utilization_final.rpt
 close_design
}
close_project
