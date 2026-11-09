# 720p + OV5640 单次自动对焦候选版

> 报告文件（`*.rpt`）头部的主机名与绝对路径已替换为占位符 `(omitted)` / `<out>`，报告的时序、资源与 DRC 数据未作任何改动。

## 打开和下载哪个版本

独立工程：`camera_af/camera_af.xpr`。顶层：`rtl/camera_af/camera_hdmi_af_top.v`。位流 `camera_hdmi_af_top.bit` 未纳入仓库，需按 `build.tcl` 自行生成。本轮不执行 JTAG 或 Flash 写入。

原 720p 顶层 `rtl/camera/camera_hdmi_top.v` 保留作为对照。旧 720p 位流已移出工程，当前只保留本 AF 版的构建脚本与报告。

## 固件来源

Espressif 官方仓库 https://github.com/espressif/esp32-camera ，固定提交 `281d951f75b6559adec3cdb8cf076366da103880`。

- `sensors/private_include/ov5640_af_firmware.h`：固件原文。
- `sensors/ov5640_af.c`：下载与单次对焦流程参考。
- 原文件和上游 LICENSE 保存于 `third_party/ov5640_af/`；该仓库 LICENSE 是 Apache-2.0，固件头文件没有独立的许可声明，本项目不另行声称固件权利归属。
- 有效固件 4077 字节；SHA256 `439245623bc99f3b0d8c44d47baed3cc17cad01b9191509c89bb8d92a98949c9`。
- 传感器写入地址 0x8000…0x8FEC；ROM 文件补零至 4096 字节，但只写有效的 4077 字节。

此固件是通用 OV5640 AF 实现的候选，不等于已确认兼容当前实物 VCM 接线和镜头结构。

## 模块及逻辑

- `ov5640_init_bus_ctrl.v`：从原初始化控制器提取事务接口，原 252 项图像初始化顺序保留；原文件未修改。
- `ov5640_af_rom.v` + `ov5640_af_firmware.mem`：同步固件 ROM。
- `ov5640_af_ctrl.v`：固件下载、状态轮询、单次自动对焦。
- `ov5640_af_camera.v`：组合时钟、图像 ROM、初始化控制、AF 控制和唯一的 `sccb_master`。
- `camera_hdmi_af_top.v`：720p 顶层副本，只替换摄像头控制封装和 LED；FIFO、DDR、显示数据路径保留。

图像初始化完成 → 转交 SCCB 给 AF → 0x3000=0x20 复位 MCU → 写 4077 字节 → 清 0x3022…0x3028 → 0x3029=0x7F → 0x3000=0 启动 MCU → 轮询 0x3029=0x70 → 等待 200 ms → 按参考驱动写 CMD_MAIN=0x01、0x08 并等 ACK → CMD_ACK=1、CMD_MAIN=0x03 单次对焦 → 等 ACK 清零和 FW_STATUS=0x10。

`af_ready` 表示固件就绪；`af_success` 表示固件状态报告 0x10，不是光学清晰度或电机运动的测量证据。控制器支持同系统时钟域 `focus_start` 上升沿再次请求；本版顶层将它接 0，故每次系统复位后只自动执行一次。没有新增按钮引脚，也没有实现持续追焦。

AF 的 init_done 与图像 init_done 分离：图像初始化成功后就放行采集；AF 失败不拉低 camera_done、不复位 DDR 或显示通路。失败保留到复位，不自动反复下载或重试。

## LED 与错误码

本候选版与之前 DVP 调试位流的 LED 含义不同：

| LED | 含义 |
|---|---|
| 0 | 图像配置成功 camera_done |
| 1 | AF 固件加载就绪 af_ready |
| 2 | 固件报告聚焦完成 af_success |
| 3 | AF 错误 af_error |

内部 af_error_code：1 SCCB NACK；2 事务超时；3 固件未进入 idle；4 命令 ACK 超时；5 未返回 focused 状态。错误不通过四个 LED 编码，必要时可后续读内部信号。

## 仿真边界

`verification/camera_af/tb_camera_af.v` 使用实际 SCCB 主机和总线应答模型：核对 252 项 720p 配置、全部 4077 固件字节及其传感器地址、MCU 启动和忙碌轮询、一次对焦成功状态；再注入固件写入 NACK，确认只报告 AF 错误而图像初始化仍成功。

模型给出固件状态，不执行传感器内部 MCU 固件，不模拟 VCM 电机和光学过程；不能据此宣称实物已自动对焦。最终验收需要远近目标切换后，镜头实际调整且画面重新清晰。

## 复现

从本交付目录执行 Vivado 2018.3：`vivado.bat -mode batch -source build.tcl`。ROM 的 .mem 文件已加入工程。

构建沿用现有 IP 参数和引脚电气约束，没有新增物理引脚或改电压。

## 本轮构建结果

Vivado 2018.3 位流生成成功，未下载。WNS +0.970 ns，WHS +0.054 ns，TNS/THS 0。LUT 7427（13.96%），FF 8175（7.68%），BRAM36 折算 4.5（3.21%），DSP 0。相较 720p 版净增 180 LUT、108 FF、1 块 BRAM36，包含 LED 替换的影响。普通方法学及 DRC 告警保留在报告中，未整体消除。

位流 SHA256：`2481e4c9d7054b6720a8fc227fc4253b0939b1ddb8e37307a055036965c359b4`。

后续记录：本版已通过 JTAG 下载成功，startup HIGH，未写 Flash。物理镜头动作及清晰度效果尚待板上确认。详见 program_af.log。
