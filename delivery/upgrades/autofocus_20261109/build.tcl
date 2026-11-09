set out [file dirname [file normalize [info script]]]
set root [file normalize [file join $out ../../..]]
set dest "$root/camera_af"
if {![file exists "$dest/camera_af.xpr"]} {
 create_project camera_af $dest -part xc7z020clg484-2
 set_property target_language Verilog [current_project]
 set_property simulator_language Mixed [current_project]
 foreach mod {video_clock_reset video_timing tmds_encoder tmds_encode_rgb serializer_10to1 dvi_tx camera_clock_reset ov5640_capture ddr_clock_reset ddr_controller rgb565_packer frame_buffer_manager} {
  add_files "$root/cam_yolo.srcs/sources_1/new/$mod.v"
 }
 foreach mod {camera_ingress stream_async_fifo axi_frame_writer axi_display_reader sccb_master} {
  add_files "$root/rtl/camera/$mod.v"
 }
 add_files "$root/cam_yolo.srcs/sources_1/imports/camera_init/ov5640_init_table_rgb.v"
 add_files [glob "$root/rtl/camera_af/*.v"]
 add_files "$root/rtl/camera_af/ov5640_af_firmware.mem"
 foreach ip {video_clk camera_clk ddr_clk mig_7series_0} {
  read_ip "$root/camera_live/ip/$ip/$ip.xci"
 }
 add_files -fileset constrs_1 "$root/constraints/camera_hdmi.xdc"
 set_property top camera_hdmi_af_top [get_filesets sources_1]
 update_compile_order -fileset sources_1
} else {open_project "$dest/camera_af.xpr"}
set_property STEPS.WRITE_BITSTREAM.TCL.PRE "$root/scripts/bitstream_timing_guard.tcl" [get_runs impl_1]
if {[get_property STATUS [get_runs synth_1]] ne "Not started"} {reset_run synth_1}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "AF synthesis failed"}
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "AF implementation failed"}
open_run impl_1
report_timing_summary -file "$out/timing.rpt"
report_utilization -file "$out/utilization.rpt"
report_methodology -file "$out/methodology.rpt"
report_drc -file "$out/drc.rpt"
file copy -force "$dest/camera_af.runs/impl_1/camera_hdmi_af_top.bit" "$out/camera_hdmi_af_top.bit"
puts "RESULT: AUTOFOCUS_BITSTREAM_BUILT"
close_project
