$ErrorActionPreference = 'Stop'
$bin = if ($env:VIVADO_BIN) { $env:VIVADO_BIN } else { 'C:\Xilinx\Vivado\2018.3\bin' }
Push-Location $PSScriptRoot
try {
    $sources = @(
        '../../rtl/camera/stream_async_fifo.v',
        '../../rtl/camera/camera_ingress.v',
        '../../rtl/camera/axi_frame_writer.v',
        '../../rtl/camera/axi_display_reader.v',
        '../../cam_yolo.srcs/sources_1/new/rgb565_packer.v',
        '../../cam_yolo.srcs/sources_1/new/frame_buffer_manager.v',
        '../../rtl/camera/sccb_master.v',
        '../../cam_yolo.srcs/sources_1/new/ov5640_init_ctrl.v',
        '../../cam_yolo.srcs/sources_1/new/ov5640_config.v',
        '../../cam_yolo.srcs/sources_1/new/ov5640_capture.v',
        '../../cam_yolo.srcs/sources_1/new/video_timing.v',
        '../../cam_yolo.srcs/sources_1/imports/camera_init/ov5640_init_table_rgb.v',
        'tb_stream_fifo.v','tb_writer.v','tb_packer.v','tb_reader.v','tb_sccb.v','tb_init.v'
    )
    & "$bin/xvlog.bat" @sources
    if ($LASTEXITCODE -ne 0) { throw 'xvlog failed' }
    function Run-Check([string]$top,[string]$snapshot) {
        & "$bin/xelab.bat" $top -s $snapshot
        if ($LASTEXITCODE -ne 0) { throw "Elaboration failed: $top" }
        & "$bin/xsim.bat" $snapshot -runall -log "$snapshot.run.log"
        $result = Get-Content -LiteralPath "$snapshot.run.log" -Raw
        if ($LASTEXITCODE -ne 0 -or $result -notmatch 'PASS ' -or $result -match 'Fatal:') {
            throw "Check failed: $top"
        }
    }
    Run-Check tb_stream_fifo fifo_check
    Run-Check tb_writer writer_check
    Run-Check tb_packer packer_check
    Run-Check tb_reader reader_check
    Run-Check tb_sccb sccb_check
    Run-Check tb_init init_check
    foreach ($faults in @($false,$true)) {
        if ($faults) { py generate_integration_tb.py --faults } else { py generate_integration_tb.py }
        if ($LASTEXITCODE -ne 0) { throw 'Testbench generation failed' }
        & "$bin/xvlog.bat" ../../rtl/camera/camera_hdmi_top.v tb_pipeline.v
        if ($LASTEXITCODE -ne 0) { throw 'Integration compile failed' }
        if ($faults) { Run-Check tb_pipeline fault_check } else { Run-Check tb_pipeline pipeline_check }
    }
    Write-Output 'PASS all camera checks'
} finally { Pop-Location }
