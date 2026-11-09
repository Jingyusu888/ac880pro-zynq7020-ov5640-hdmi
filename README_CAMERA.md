# AC880 摄像头 → DDR3L → HDMI2

当前主工程：`camera_af/camera_af.xpr`，顶层 `rtl/camera_af/camera_hdmi_af_top.v`。

## 当前版本

1280×720 原生全屏 + OV5640 单次自动对焦候选实现。已通过 JTAG 下载并在板上看到画面；LED 0/1/2 亮、3 灭，镜头动作与光学对焦效果尚未确认。此前清晰度改善来自手动调焦。

LED 定义：0 图像初始化、1 AF 固件就绪、2 固件报告聚焦完成、3 AF 错误。本版仅在启动或系统复位后对焦一次，不持续追焦。

**本仓库不含 `.bit` 位流**，需按根目录 README 第 7 节自行综合生成。

## 目录入口

| 目录 | 作用 |
|---|---|
| `rtl/camera_af/` | 当前 AF 顶层、控制器、共享 SCCB 封装、固件 ROM |
| `rtl/camera/` | 采集入口、异步 FIFO、AXI 写/读、SCCB，以及非 AF 720p 顶层 |
| `cam_yolo.srcs/` | 多阶段共用的显示、采集、时钟、打包、帧管理源文件，及本工程 IP 配置 |
| `camera_live/ip/` | 当前 AF 工程引用的时钟与 MIG IP 配置（`.xci`） |
| `constraints/` | 摄像头、HDMI 与 DDR 引脚约束 |
| `third_party/ov5640_af/` | 固定版本的 AF 固件来源、LICENSE 与哈希 |
| `verification/` | testbench、检查脚本与结果记录 |
| `delivery/upgrades/autofocus_20261109/` | 报告、manifest、构建与下载脚本 |
| `docs/` | 原理说明、阶段检查记录、TMDS 流程图 |
| `notes/` | 模块与数据流结构画布 |

## 构建与验证

在 `delivery/upgrades/autofocus_20261109/` 下运行：

```powershell
# 先把 Vivado 2018.3 的 bin 目录加入 PATH，或改写成你的安装路径
vivado -mode batch -source build.tcl
```

AF 专项仿真入口：`verification/camera_af/run_checks.ps1`（脚本读取环境变量 `VIVADO_BIN`，未设置时用默认安装路径）。
固件 ROM 可由 `scripts/prepare_af_firmware.py` 从固定上游快照重新生成。

## 来源与许可

- **引脚映射**：依据厂商原理图与板卡资料整理，版权归原厂；本仓库仅用于说明本工程如何连线，不构成对原厂资料的再分发授权。
- **`cam_yolo.srcs/`**：源自该板卡配套示例工程的工程骨架，本仓库只保留当前设计实际依赖的模块。
- **AF 固件**：`third_party/ov5640_af/`，Apache-2.0，上游 commit 与哈希见 `upstream.json`。
- **Xilinx IP**：仓库仅含 `.xci` 配置，不含 IP 源码。
- 整体授权范围见根目录 `LICENSE`：仅授权阅读与学习。若权利人认为本仓库内容不当，请开 issue 联系，会立即删除相关内容。
