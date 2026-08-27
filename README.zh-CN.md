# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

无需手工配置 Python 环境、匹配 CUDA 依赖或整理模型目录，即可在 Linux 上运行
RVC。

rvc.nix 将固定版本的
[RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)
打包为适用于 `x86_64-linux` 的可复现 Nix 软件包。项目提供上游 Realtime GUI、
WebUI、RVC CLI 和 PyMSS CLI，并分别支持 CPU、CUDA 11.8 与 CUDA 12.8。可选的
NixOS 模块还可配置本机 WebUI 服务和 PipeWire 虚拟麦克风。

## 快速开始

请先安装已启用 flake 命令的 Nix，无需克隆仓库。首次运行时，Nix 可能会询问是否
接受本 flake 的 Cachix 配置；接受后可在缓存可用时直接下载 CI 构建的软件包。
不接受也能使用，但可能需要在本机完成体积较大的构建。

根据目标机器选择一条命令：

```console
# CPU 后端；使用 AMD 或 Intel 显卡的机器也选择此项
nix run github:Ruixi-rebirth/rvc.nix

# 适用于 RTX 50 系以前受支持 NVIDIA 显卡的 CUDA 11.8
nix run github:Ruixi-rebirth/rvc.nix#realtime-cuda118

# 适用于 NVIDIA RTX 50 系列显卡的 CUDA 12.8
nix run github:Ruixi-rebirth/rvc.nix#realtime-cuda128
```

以上三条命令都包含用于提取内容特征的 HuBERT 和用于提取音高的 RMVPE，但不包含
目标音色。Realtime GUI 打开后，需要选择用户自己的可信 `.pth` 语音模型；配套的
`.index` 文件可选。

Realtime GUI 需要 X11，在 Wayland 会话中需要 XWayland。AMD 和 Intel 机器使用
CPU 推理；本项目不提供 ROCm、Vulkan 或 Intel GPU 加速。

## WebUI 与命令行工具

```console
# WebUI：包含文件变声所需的推理模型
nix run github:Ruixi-rebirth/rvc.nix#web

# WebUI：包含本项目打包的完整模型集（下载量更大）
nix run github:Ruixi-rebirth/rvc.nix#web-all

# RVC CLI
nix run github:Ruixi-rebirth/rvc.nix#cli -- --help

# PyMSS 音源分离 CLI：包含配套权重
nix run github:Ruixi-rebirth/rvc.nix#pymss -- infer --help
```

## 每条命令包含哪些模型

可运行命令会自动带上该功能所需的资源，普通用户不必再单独选择模型组合。

| 命令 | 预置资源 | 用途 |
| --- | --- | --- |
| `realtime`、`web`、`cli` | HuBERT、RMVPE | 语音变声 |
| `pymss` | 5 个 PyMSS 权重 | 音乐音源分离 |
| `web-all` | 本项目打包的全部模型资源 | 变声、训练和音源分离 |

在任意命令名后添加 `-cuda118` 或 `-cuda128`，只会切换运行后端。例如
`web-cuda118` 和 `web-all-cuda128`。

这些命令都不包含已经训练完成的目标音色。`web-all` 在推理模型和 PyMSS 权重
之外，还加入上游训练所需的 RVC v1/v2 预训练权重与静音样本。预训练权重只用于
初始化训练；用户仍需准备目标声音的录音，训练产出的 `.pth` 才是变声时使用的
目标音色模型。

以上名称是供 `nix run` 使用的应用入口。安装到 NixOS 时只需选择一个 CPU/CUDA
运行软件包；`models-*` 输出仅用于高级模型组合。三类输出的完整列表和自定义方式
见[使用手册](docs/usage.zh-CN.md)。

## 选择 CPU 或 CUDA

CUDA 软件包的划分遵循
[固定上游版本的硬件说明](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/blob/81eed5e8f68b6bed1789f682fe78cdd324495afc/README.md#按硬件选择依赖)：
RTX 50 系以前的 NVIDIA GPU 使用 CUDA 11.8，RTX 50 系列使用 CUDA 12.8。

RVC 的 Python 环境和原生用户态依赖均由软件包从 Nix store 提供。启动器会丢弃
宿主机的 `LD_LIBRARY_PATH`；CUDA 启动器只会加入指定的 NVIDIA 驱动目录，不要求
宿主机另行安装 CUDA Toolkit。

在 CUDA 软件包中，RVC Realtime GUI、WebUI、CLI 和 `rvc-doctor` 要求显卡至少
具有 4 GiB 显存和 CUDA 计算能力 5.3；没有可用的受支持显卡时，它们会直接失败，
不会悄然回退到 CPU。

使用所选软件包中的 `rvc-doctor` 可以检查 Torch、RVC 推理设备、二进制扩展、
ONNX Runtime 和 cuDNN。CUDA 11.8 已在 RTX 2070 Super Max-Q 上完成实际变声
测试；CUDA 12.8 已通过软件包构建和不依赖实际显卡的检查，但尚未在 RTX 50 系
显卡上实测。

在 NixOS 上，CUDA 软件包默认从 `/run/opengl-driver/lib` 使用驱动接口。其他
Linux 发行版需要将 `RVC_DRIVER_LIBRARY_PATH` 指向包含 `libcuda.so.1` 的目录。

## NixOS 虚拟麦克风

NixOS 模块可以创建两个设备：Realtime GUI 将变声音频写入 `RVC-Output`，语音
软件则把 `RVC-Microphone` 作为麦克风使用。只有设置
`programs.rvc.virtualMic.enable` 后，模块才会启用所需的 PipeWire 集成。不用耳机
时，还可启用 WebRTC 回声消除输入，而且无需硬编码 PCH 等 ALSA 设备名。模块配置
和准确的设备选择见 [NixOS 与 PipeWire 手册](docs/nixos.zh-CN.md)。

## 文档

- [使用手册](docs/usage.zh-CN.md)：全部命令、软件包、模型和数据目录。
- [NixOS 与 PipeWire](docs/nixos.zh-CN.md)：模块、WebUI 服务和虚拟麦克风。
- [安全说明](SECURITY.md)：可信模型规则和 WebUI 网络边界。
- [贡献指南](CONTRIBUTING.md)：仓库结构、检查项目和发布流程。

本项目根据 [MIT License](LICENSE) 发布。上游 RVC 和模型资源保留各自的许可证
与使用条款。
