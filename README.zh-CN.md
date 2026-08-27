# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

rvc.nix 为
[RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)
提供可复现的 Nix 软件包，支持 `x86_64-linux`。软件包包含上游 Realtime GUI、
WebUI、RVC CLI 和 PyMSS CLI，并提供 NixOS 与 PipeWire 集成。

## 启动 Realtime GUI

根据硬件选择一条命令：

```console
# CPU、AMD GPU 或 Intel GPU
nix run github:Ruixi-rebirth/rvc.nix

# RTX 50 系以前的 NVIDIA GPU
nix run github:Ruixi-rebirth/rvc.nix#cuda118-with-models

# RTX 50 系列 NVIDIA GPU
nix run github:Ruixi-rebirth/rvc.nix#cuda128-with-models
```

以上命令都包含 HuBERT 和 RMVPE。HuBERT 从输入语音中提取内容特征，RMVPE
提取音高，用户选择的 `.pth` 语音模型决定转换后的音色；配套的 `.index` 文件
可选。

打开 Realtime GUI 后，选择语音模型、麦克风和输出设备。Realtime GUI 使用
Tk/X11，在 Wayland 会话中通过 XWayland 运行。

## 启动 WebUI 或命令行工具

```console
# WebUI：文件变声
nix run github:Ruixi-rebirth/rvc.nix#web-with-models

# WebUI：文件变声、训练和音乐源分离
nix run github:Ruixi-rebirth/rvc.nix#web-with-all-models

# RVC CLI：查看命令行参数
nix run github:Ruixi-rebirth/rvc.nix#cli-with-models -- --help

# PyMSS CLI：查看分离参数
nix run github:Ruixi-rebirth/rvc.nix#pymss-with-models -- infer --help
```

`web-with-all-models` 在此基础上再加入 RVC v1/v2 训练用的预训练权重、静音样本
和 5 个 PyMSS 权重。训练时准备目标声音的录音；已有 `.pth` 语音模型时，则可
直接用它进行文件变声。

全部 CPU/CUDA 命令、不带模型的版本、软件包输出和数据目录见
[使用手册](docs/usage.zh-CN.md)。

## CPU 或 CUDA

CUDA 软件包的选择遵循
[锁定上游版本的硬件说明](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/blob/81eed5e8f68b6bed1789f682fe78cdd324495afc/README.md#按硬件选择依赖)：
RTX 50 系以前的 NVIDIA GPU 使用 CUDA 11.8，RTX 50 系列使用 CUDA 12.8。

Nix 提供所选版本的 CUDA Runtime、cuDNN 和 cuBLAS。宿主机只需要能够支持该
Runtime 的 NVIDIA 驱动，不需要安装相同版本的 CUDA Toolkit。使用所选软件包
中的 `rvc-doctor` 可以检查驱动和 GPU。

CUDA 11.8 已在 RTX 2070 Super Max-Q 上完成实际变声测试。CUDA 12.8 已通过
构建检查，但尚未在 RTX 50 系显卡上实测。

## 详细文档

- [使用手册](docs/usage.zh-CN.md)：全部命令、软件包、模型和数据目录。
- [NixOS 与 PipeWire](docs/nixos.zh-CN.md)：模块、WebUI 服务和虚拟麦克风。
- [安全说明](SECURITY.md)：模型加载和 WebUI 网络边界。
- [贡献指南](CONTRIBUTING.md)：仓库结构、测试和发布。

本项目根据 [MIT License](LICENSE) 发布。上游 RVC 和模型资源保留各自的许可证
与使用条款。
