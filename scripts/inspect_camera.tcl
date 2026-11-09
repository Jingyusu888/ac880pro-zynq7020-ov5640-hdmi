set root [file normalize [file join [file dirname [info script]] ..]]
open_project $root/camera_live/camera_live.xpr
open_run impl_1
report_cdc -details -file $root/camera_live/cdc_details.rpt
report_timing -max_paths 10 -file $root/camera_live/timing_paths_final.rpt
close_project
