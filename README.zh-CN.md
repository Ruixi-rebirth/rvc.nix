# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

为 [RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)
提供可复现的 Nix 软件包。

本项目将上游源码、Python 环境、CPU 和 CUDA 运行时、原生库、启动器以及
可选的推理模型打包为 Nix 派生项。它不会创建 virtualenv，不会在运行时调用
`pip`，也不会将应用源码复制到可变的工作目录中。

> **项目状态：** CPU 和 CUDA 软件包均已在 `x86_64-linux` 上成功构建；
> `nix flake check` 已覆盖 CLI 参数解析、完整 WebUI 构建以及实时模块的
> 导入和配置。CUDA 运行时也已在配备 NVIDIA 驱动 610.57.04 的 RTX 2070
> Super Max-Q 上完成验证，其中包括真实的 HuBERT 和 RMVPE CUDA 前向计算。
> 离线 CLI 和实时合成路径也已使用从固定版本官方 v2 资源安全提取的同一
> 检查点完成验证。CUDA 包在没有受支持的 NVIDIA 设备时会拒绝启动。实时
> PipeWire 虚拟设备路由已在 PipeWire 1.6.8
> 上完成实测。使用社区训练的纳西妲 v2 模型的端到端转换也已在 CPU 和 CUDA
> 上完成。

## 功能特性

- 基于 `flake-parts` 的 flake，提供软件包、应用、overlay 和 NixOS 模块
- 使用 `uv2nix` 和 `pyproject.nix` 锁定的 Python 3.12 环境
- 以 CPU 作为便携的默认选项；CUDA 11.8 始终需要显式选择
- 固定的上游 RVC 修订版本
- 可选的 HuBERT 和 RMVPE 模型软件包，使用不可变的修订版本与哈希
- WebUI、实时 GUI、离线 RVC CLI 和上游 PyMSS CLI 入口
- 使用 XDG 数据、配置和缓存目录；源码在 Nix store 中保持只读
- 实时 Tk GUI 需要 X11；Wayland 会话需要 XWayland
- 提供 PipeWire 虚拟麦克风的 NixOS 模块

## 快速开始

直接从 GitHub 运行 CPU 版实时 RVC，并使用已固定版本的 HuBERT 和 RMVPE
模型：

```console
nix run github:Ruixi-rebirth/rvc.nix
```

在项目检出目录中，对应的简短命令是：

```console
nix run .
```

`nix run` 启动的是应用（默认是**包含**固定版本推理模型的 CPU 实时 GUI），
而 `nix build` 构建的是软件包：`nix build .` 产出的是**不含**模型资源的
精简 CPU 软件包。完整的组合见下方输出表格。

本 flake 声明了项目的 [Cachix](https://www.cachix.org/) 二进制缓存
（`ruixi-rebirth`）。首次使用时 Nix 会询问是否接受该 flake 配置——选是，
CI 推送的 CPU/CUDA 闭包就会直接替换下载，而不是本地构建。也可以在命令行
预先批准：传入 `--accept-flake-config`。

使用 CUDA 11.8 PyTorch 构建所支持的 NVIDIA GPU 运行。RVC 至少需要 4 GiB
显存和 CUDA 计算能力（Compute Capability）5.3：

```console
nix run .#cuda-with-models
```

首次构建体积较大。Nix 只会下载每个依赖和模型一次，之后会从 store 中复用。

个人语音模型属于可变的用户数据。请将 `.pth` 文件放入
`$XDG_DATA_HOME/rvc/assets/weights`，将 `.index` 文件放入
`$XDG_DATA_HOME/rvc/logs`，实时 GUI 会在这个目录里找索引。`$XDG_DATA_HOME`
默认是 `~/.local/share`，所以实际路径通常是
`~/.local/share/rvc/assets/weights` 和 `~/.local/share/rvc/logs`。

## 输出

| 输出 | 用途 |
| --- | --- |
| `.#default`, `.#cpu` | 不含大型模型资源的 CPU 软件包 |
| `.#cuda` | 不含模型资源的 CUDA 11.8 软件包 |
| `.#cpu-with-models` | 包含固定版本 HuBERT 和 RMVPE 的 CPU 软件包 |
| `.#cuda-with-models` | 包含固定版本 HuBERT 和 RMVPE 的 CUDA 软件包 |
| `.#models-inference` | 独立的固定版本推理模型目录树 |
| `.#models-pretrained-v1` | 官方 RVC v1 训练检查点 |
| `.#models-pretrained-v2` | 官方 RVC v2 训练检查点 |
| `.#models-mute` | 训练用静音样本 |
| `.#models-training` | 两代训练检查点和静音样本 |
| `.#models-all` | 推理和训练资源 |
| `.#cpu-with-all-models` | 包含本项目打包的全部模型集的 CPU 软件包 |
| `.#cuda-with-all-models` | 包含本项目打包的全部模型集的 CUDA 软件包 |

在固定的修订版本下用 `nix path-info -Sh` 测得（近似值，且 Nix 会共享主机上
已有的 store 路径）：

| 输出 | CPU | CUDA |
| --- | ---: | ---: |
| 精简软件包 | 3.4 GiB | 7.8 GiB |
| 含推理模型 | 3.7 GiB | 8.1 GiB |
| 含全部模型 | 6.0 GiB | 10.3 GiB |

模型集本身：`models-inference` 0.34 GiB，`models-training` 2.2 GiB，
`models-all` 2.6 GiB。

默认 overlay 基于使用者最终的 nixpkgs 软件包集进行构建。它导出
`rvc`/`rvc-cpu`、`rvc-cuda`、各自的 `*-with-models` 和
`*-with-all-models` 变体，以及 `rvc-models-inference`、
`rvc-models-training` 和 `rvc-models-all`。

可用的应用入口：

| 命令 | 入口 |
| --- | --- |
| `nix run .` | 包含固定版本推理模型的 CPU 实时 GUI |
| `nix run .#realtime` | 不含打包模型的 CPU 实时 GUI |
| `nix run .#web` | CPU WebUI |
| `nix run .#cli -- --help` | CPU 离线 CLI |
| `nix run .#pymss -- list` | CPU 上游 PyMSS CLI |
| `nix run .#cuda` | CUDA 实时 GUI |
| `nix run .#cuda-web` | CUDA WebUI |
| `nix run .#cuda-cli -- --help` | CUDA 离线 CLI |
| `nix run .#cuda-pymss -- list` | CUDA 上游 PyMSS CLI |
| `nix run .#generate-patches` | 从锁定的上游源码重新生成补丁 |
| `nix run .#with-models` | 默认 CPU 应用的显式别名 |
| `nix run .#web-with-models` | 包含推理模型的 CPU WebUI |
| `nix run .#web-with-all-models` | 包含推理和训练资源的 CPU WebUI |
| `nix run .#cli-with-models -- --help` | 包含推理模型的 CPU CLI |
| `nix run .#cuda-with-models` | 包含推理模型的 CUDA 实时 GUI |
| `nix run .#cuda-web-with-models` | 包含推理模型的 CUDA WebUI |
| `nix run .#cuda-web-with-all-models` | 包含推理和训练资源的 CUDA WebUI |
| `nix run .#cuda-cli-with-models -- --help` | 包含推理模型的 CUDA CLI |

检查打包后的运行时：

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda
./result/bin/rvc-doctor
```

`rvc-doctor` 会报告 Torch 构建、CUDA 运行时、所选设备、核心二进制扩展
的导入结果、真实的 ONNX Runtime CPU provider 会话，并且针对 CUDA 输出
执行 cuDNN 加载检查。如果 PyTorch 无法使用 NVIDIA 设备，或可见 GPU 均不
满足 RVC 的最低要求（至少 4 GiB 显存、CUDA 计算能力 5.3），CUDA doctor
会以失败状态退出，因此显式选择的 CUDA 变体绝不会悄然回退到 CPU。目标机器
上的 `nvidia-smi` 也应当能够成功运行。真实的 CPU/CUDA HuBERT、RMVPE、
离线 CLI 和实时合成前向测试分别覆盖实际设备执行。

NixOS 会在 `/run/opengl-driver/lib` 暴露 NVIDIA 用户空间库，这也是启动器的
默认值。在其他 Linux 发行版上，请将 `RVC_DRIVER_LIBRARY_PATH` 设为包含
该主机 `libcuda.so.1` 的目录。CUDA 路径目前已在 NixOS 上完成硬件测试；
非 NixOS 的驱动集成可通过显式覆盖获得支持，但尚未进行验收测试。

## 持久化数据

启动器只会创建可变的运行时状态：

```text
$XDG_DATA_HOME/rvc/       模型、索引、日志和训练数据
$XDG_CONFIG_HOME/rvc/     实时 GUI 设置
$XDG_CACHE_HOME/rvc/      临时音频、上传文件和库缓存
```

可以通过 `RVC_DATA_DIR`、`RVC_CONFIG_DIR` 和 `RVC_CACHE_DIR` 覆盖这些目录。
只有在目标不存在时，打包的模型文件才会从 Nix store 链接过去，因此用户
文件始终具有更高优先级。每个模型输出还会在 `share/doc/rvc-models` 下包含
其不可变的源码修订版本和已固定的仓库模型卡。

WebUI 默认从 `127.0.0.1:7865` 开始监听，端口占用时会尝试下一个可用端口。
`RVC_WEBUI_HOST`、`RVC_WEBUI_PORT` 和上游 `--port` 参数可以覆盖这些默认值。
这是一个能够访问文件系统和训练控制功能、仅供可信单用户使用的界面。在
反向代理处添加身份验证，也不能让它安全地供不受信任的用户使用。

## PipeWire 虚拟麦克风

将 flake 和模块添加到 NixOS 配置中：

```nix
{
  inputs.rvc-nix.url = "github:Ruixi-rebirth/rvc.nix";

  nixConfig = {
    extra-substituters = [ "https://ruixi-rebirth.cachix.org" ];
    extra-trusted-public-keys = [
      "ruixi-rebirth.cachix.org-1:ypGqoIU9MfXwv/fE02ZGg8mutJqmcYHgLTR1DMoPGac="
    ];
  };

  outputs = inputs@{ nixpkgs, rvc-nix, ... }: {
    nixosConfigurations.my-host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        rvc-nix.nixosModules.rvc
        {
          programs.rvc = {
            enable = true;
            package = rvc-nix.packages.x86_64-linux.cuda-with-models;
            chinese.enable = true;
            virtualMic.enable = true;

            # 可选：每个图形登录会话自动启动 rvc-web。
            webui.enable = false;
          };
        }
      ];
    };
  };
}
```

该模块始终会安装 RVC；只有设置 `virtualMic.enable = true` 时才会启用
PipeWire、WirePlumber、ALSA、PulseAudio 兼容层和 rtkit，并创建以下音频链路：

```text
PipeWire 默认麦克风 -> RVC -> RVC-Output -> RVC-Microphone -> 语音应用
```

重新构建 NixOS 后，打开实时 GUI 并由你自己选择设备。已验证的 NixOS 路径
是：设备类型选择 `ALSA`，GUI 输入选择 `pipewire`，GUI 输出选择
`RVC-Output`。`pipewire` 会跟随 PipeWire 当前的默认输入，实际物理麦克风由
你在系统音频设置中选择。然后在 Discord、游戏或其他语音应用中把输入设为
`RVC-Microphone`。模块不会过滤、预选或隐藏设备，GUI 会显示音频后端实际
枚举到的内容。

两边各选各的设备，按角色对应即可，不要交叉：

| 界面 | 设备 | 选择 |
| --- | --- | --- |
| 实时 GUI | 设备类型 | `ALSA` |
| 实时 GUI | 输入 | `pipewire` |
| 实时 GUI | 输出 | `RVC-Output` |
| QQ/Discord 等 | 输入（麦克风） | `RVC-Microphone` |
| QQ/Discord 等 | 输出（扬声器） | 真实的扬声器/耳机 |

`RVC-Microphone` 是 `RVC-Output` 的监听源，因此 RVC 没有写入变声音频时它会
保持静音。采样率、声道数和声道映射由 PipeWire 协商；模块不会固定音频格式，
也不会选择任何物理设备。它同样不会在本机监听变声结果、添加回声消除或修改
系统默认设备。

| 选项 | 类型 | 默认值 | 用途 |
| --- | --- | --- | --- |
| `programs.rvc.enable` | 布尔 | `false` | 安装 RVC |
| `programs.rvc.package` | 软件包 | 含模型的 CPU 包 | RVC 包；CUDA 需显式选择 |
| `programs.rvc.chinese.enable` | 布尔 | `false` | 使用简体中文界面 |
| `programs.rvc.webui.enable` | 布尔 | `false` | 图形登录时启动 `rvc-web --noautoopen` |
| `programs.rvc.webui.host` | 字符串 | `127.0.0.1` | WebUI 默认监听地址 |
| `programs.rvc.webui.port` | 端口 | `7865` | WebUI 起始端口 |
| `programs.rvc.virtualMic.enable` | 布尔 | `false` | RVC-Output、RVC-Microphone |

WebUI 用户服务不会自动开放防火墙。若把 `webui.host` 改为非回环地址，防火墙
和访问控制仍由管理员显式决定。

## 开发

```console
nix develop
nix fmt
nix flake check
nix build .#cpu
nix build .#cuda
```

开发 shell 内含 `nix fmt` 使用的同一套 `treefmt` wrapper，因此全仓库格式化
不依赖全局工具。该 wrapper 会格式化 Nix、TOML 和独立 shell 文件，运行
ShellCheck，并在不重排正文的前提下检查 Markdown；CI 会以 `--ci` 模式调用
同一 wrapper。打包的启动器则由 `writeShellApplication` 在 Nix 构建期间检查。

CPU 和 CUDA 的 Python 依赖分别声明，因为官方 PyTorch 索引发布的是不同的
wheel 依赖图。原生 wheel 修复集中在 `nix/python-overrides.nix`；每个
override 都应描述真实的构建或 ELF 依赖，并且仅作用于受影响的软件包。
`checks.pyproject-sync` 会在两份 manifest 出现未记录的分歧时使构建失败。

对上游源码的改动以普通补丁文件的形式存放在 `nix/patches/`。逐文件替换补丁
由 `nix/patches/rules.py` 中的规格经
`nix/patches/generate_patches.py` 生成；跨文件的训练子进程补丁直接维护。
每个补丁开头都说明用途和维护来源。更新 `rvc-src` 输入后，可直接使用 Nix
store 中锁定的源码重新生成并审阅：

```console
nix flake update rvc-src
nix run .#generate-patches
```

生成器会把每个补丁应用到干净的上游副本上，与构建流水线的结果做字节级
比对，并重跑 installCheck 断言——不再匹配的补丁会在这里失败，而不是等到
动辄数 GiB 的构建里才发现。CI 会用 `checks.patches-in-sync` 针对固定版本
源码重跑同一流水线，确保入库的补丁文件永远不会与 `flake.lock` 脱节。

`nix/tests/` 下另有需要真实声卡、显示器或运行中 PipeWire 图才能跑的实机
验收脚本，`nix flake check` 无法覆盖：`cli-e2e-live.sh`、
`realtime-infer-live.sh`、`realtime-gui-live.sh`、
`realtime-gui-click-live.sh`、`webui-live.sh` 和 `pipewire-live.sh`。请在
目标机器上运行；不带参数调用时会打印用法。

在 Git 检出目录中处理新建且尚未跟踪的文件时，请使用
`nix flake check path:.`，直至这些文件被加入 Git。以 Git 为后端的 `.`
flake 会有意忽略未跟踪文件。

## 故障排查

- **CUDA 报告没有可用设备。** 先运行 `nvidia-smi`；在 NixOS 上驱动库默认
  位于 `/run/opengl-driver/lib`，其他发行版请把 `RVC_DRIVER_LIBRARY_PATH`
  指向包含 `libcuda.so.1` 的目录。`rvc-doctor` 是第一步——它能区分
  “PyTorch 没有 CUDA”和“没有 GPU 达到 RVC 的 4 GiB / 计算能力 5.3 门槛”。
- **Wayland 下实时 GUI 打不开窗口。** Tk GUI 需要 X11；请启用 XWayland。
- **音高或语速不对。** 虚拟设备格式由 PipeWire 协商。检查实时 GUI 中选择
  的设备类型和采样率模式；模块不会覆盖这些设置。
- **其他机器访问不了 WebUI。** 默认绑定 `127.0.0.1` 是有意为之：该界面
  拥有文件系统和训练控制能力，且固定版本的 Gradio 3.x 存在已知 CVE，只有
  本地回环绑定才能缓解。把 `RVC_WEBUI_HOST` 当作最后手段，切勿将端口暴露
  到公网；安全模型见 [`SECURITY.md`](SECURITY.md)。
- **模型下载失败。** 打包的模型资源来自 Hugging Face 上
  `lj1995/VoiceConversionWebUI` 仓库的不可变 revision（见 `nix/models.nix`）。
  若该仓库迁移，哈希校验仍然有效，但需要更新 URL。

## 范围与限制

- 目前只声明了 `x86_64-linux`。
- CPU 和 CUDA 实时 GUI 使用 Tk/X11；Wayland 会话需要 XWayland。除此之外，
  CPU/CUDA 计算、WebUI、CLI 和 PipeWire 集成都不依赖具体显示服务器。
- 默认软件包不含大型模型资源，以减小其闭包。
- 训练资源按 RVC 代际拆分，让用户只获取所需内容；`models-all` 仍是一个
  需要显式选择的大型输出。
- `models-all` 指本 flake 打包的全部模型集：HuBERT、RMVPE、RVC v1/v2
  预训练检查点和静音样本。目前尚未打包 PyMSS 音源分离权重。
- 用户训练的语音模型和索引有意不作为 Nix store 资源。
- PyTorch 2.7.1 默认以仅权重模式加载 RVC 核心和普通 PyMSS 检查点；软件包
  会拒绝未分类的显式非受限加载。背后的 pickle 风险见 PyTorch 的
  [序列化文档](https://pytorch.org/docs/stable/notes/serialization.html)。
  为保持兼容性，显式使用旧版 PyMSS Demucs、TasNet、HTDemucs 和 Apollo
  格式时仍会使用 Python pickle，因此它们必须来自可信来源。
- CUDA 需要正常工作的主机 NVIDIA 驱动、至少 4 GiB 显存，以及 CUDA 计算能力
  （Compute Capability）5.3 或更高。

## 待办事项

- [ ] 支持自定义语音模型的 NixOS 选项。

贡献请遵循 [`CONTRIBUTING.md`](CONTRIBUTING.md)。本项目根据 [MIT License](LICENSE) 发布；
上游 RVC 和模型资源保留其各自的许可证与条款。
