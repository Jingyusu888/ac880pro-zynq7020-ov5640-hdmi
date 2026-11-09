$ErrorActionPreference='Stop'
$bin = if ($env:VIVADO_BIN) { $env:VIVADO_BIN } else { 'C:\Xilinx\Vivado\2018.3\bin' }
Push-Location $PSScriptRoot
try {
 Copy-Item -LiteralPath '../../rtl/camera_af/ov5640_af_firmware.mem' -Destination 'ov5640_af_firmware.mem' -Force
 & "$bin/xvlog.bat" ../../rtl/camera_af/ov5640_af_rom.v ../../rtl/camera_af/ov5640_af_ctrl.v ../../rtl/camera_af/ov5640_init_bus_ctrl.v ../../rtl/camera_af/ov5640_af_camera.v ../../rtl/camera/sccb_master.v ../../cam_yolo.srcs/sources_1/imports/camera_init/ov5640_init_table_rgb.v tb_camera_af.v
 if($LASTEXITCODE -ne 0) {throw 'AF compile failed'}
 & "$bin/xelab.bat" tb_camera_af -s camera_af_check
 if($LASTEXITCODE -ne 0) {throw 'AF elaboration failed'}
 & "$bin/xsim.bat" camera_af_check -runall -log camera_af_check.run.log
 $result=Get-Content camera_af_check.run.log -Raw
 if($LASTEXITCODE -ne 0 -or $result -notmatch 'PASS AF NACK' -or $result -match 'Fatal:') {throw 'AF checks failed'}
} finally {Pop-Location}
