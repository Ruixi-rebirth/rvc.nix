# rvc.nix 使用手册

[English](usage.md) | [简体中文](usage.zh-CN.md) |
[返回项目首页](../README.zh-CN.md)

本手册说明如何运行和安装 RVC、每个输出包含哪些模型，以及用户数据存放在哪里。
示例中的 `.` 表示当前仓库；没有克隆仓库时，将它换成
`github:Ruixi-rebirth/rvc.nix`。

## 先理解三种输出

rvc.nix 按用途公开三类输出：

| 输出 | 使用方式 | 适合谁 |
| --- | --- | --- |
| `apps` | `nix run` | 直接启动 Realtime GUI、WebUI 或 CLI |
| 运行软件包 | `nix build`、NixOS 模块 | 安装完整 RVC 环境 |
| `models-*` | 软件包的 `models` 参数 | 组合可复现的模型资源 |

普通用户只需使用应用或 6 个运行软件包。`models-*` 只有模型文件，没有 RVC
命令，不能直接赋给 `programs.rvc.package`。

## 直接运行

不带 CUDA 后缀的应用使用 CPU；在名称后添加 `-cuda118` 或 `-cuda128` 即可选择
NVIDIA 后端。每个应用都会自动带上完成该任务所需的模型资源。

启动 Realtime GUI：

```console
# CPU；AMD 或 Intel 显卡也选择此项
nix run .
nix run .#realtime

# RTX 50 系以前的 NVIDIA GPU
nix run .#realtime-cuda118

# RTX 50 系列 NVIDIA GPU
nix run .#realtime-cuda128
```

启动 WebUI：

```console
# 文件变声
nix run .#web
nix run .#web-cuda118
nix run .#web-cuda128

# 文件变声、训练和 PyMSS；下载量更大
nix run .#web-all
nix run .#web-all-cuda118
nix run .#web-all-cuda128
```

运行 RVC CLI：

```console
nix run .#cli -- --help
nix run .#cli-cuda118 -- --help
nix run .#cli-cuda128 -- --help
```

运行 PyMSS CLI：

```console
nix run .#pymss -- infer --help
nix run .#pymss-cuda118 -- infer --help
nix run .#pymss-cuda128 -- infer --help
```

`nix run .` 和 `nix run .#realtime` 启动同一个 CPU Realtime GUI。`--` 后面的
参数会传给 RVC 或 PyMSS；示例中的 `--help` 只显示帮助。

## 构建和安装软件包

运行软件包按两个维度命名：后端决定 CPU 或 CUDA，`-all` 决定是否加入训练和
PyMSS 资源。

| 后端 | 推理与实时变声 | 加入训练和 PyMSS 资源 |
| --- | --- | --- |
| CPU、AMD GPU 或 Intel GPU | `cpu`（默认） | `cpu-all` |
| RTX 50 系以前的 NVIDIA GPU | `cuda118` | `cuda118-all` |
| RTX 50 系列 | `cuda128` | `cuda128-all` |

例如：

```console
nix build .#cpu
nix build .#cpu-all
nix build .#cuda118
nix build .#cuda118-all
nix build .#cuda128
nix build .#cuda128-all
```

`nix build .` 和 `nix build .#default` 都等价于 `nix build .#cpu`。每个运行
软件包都包含以下命令：

```text
rvc-realtime  Realtime GUI
rvc-web       WebUI
rvc-cli       RVC CLI
pymss         PyMSS CLI
rvc-doctor    运行环境诊断
rvc-python    带完整依赖的 Python
```

因此 NixOS 只需选择一个 `programs.rvc.package`；命令行工具和可选 WebUI 服务
都会使用同一个软件包。高级用户也可以运行固定上游中的其他脚本：

```console
nix shell .#cpu -c rvc-python train/train.py --help
```

### 使用 overlay

需要从 nixpkgs 命名空间引用软件包时，可以启用默认 overlay：

```nix
{
  nixpkgs.overlays = [ rvc-nix.overlays.default ];
  environment.systemPackages = [ pkgs.rvc-cuda118 ];
}
```

overlay 中的 `pkgs.rvc` 等于 CPU 推理软件包。其余运行软件包使用
`pkgs.rvc-cpu`、`pkgs.rvc-cuda118`、`pkgs.rvc-cuda128` 及对应的 `-all` 名称；
模型输出使用 `pkgs.rvc-models-*`。这些软件包与 flake 的同名输出内容一致，并且
可以继续使用 `.override { models = ...; }`。

## 模型资源

RVC 变声涉及三类模型：

- HuBERT 从输入语音中提取内容特征。
- RMVPE 提取音高，Realtime GUI、WebUI 文件变声和 RVC CLI 默认使用它。
- 用户自己的 `.pth` 目标音色模型决定转换后的声音，配套 `.index` 文件可选。

`realtime`、`web` 和 `cli` 应用包含 HuBERT 与 RMVPE；`pymss` 应用包含 5 个
音源分离权重。`web-all` 额外包含训练使用的 RVC v1/v2 预训练权重、静音样本和
PyMSS 权重。训练预权重只用于初始化训练，不是已经完成的目标音色。

独立模型输出如下：

| 输出 | 内容 |
| --- | --- |
| `models-inference` | HuBERT 和 RMVPE |
| `models-pretrained-v1` | RVC v1 训练预权重 |
| `models-pretrained-v2` | RVC v2 训练预权重 |
| `models-mute` | 训练使用的静音样本 |
| `models-training` | v1/v2 训练预权重和静音样本 |
| `models-pymss` | 5 个 PyMSS 权重 |
| `models-all` | 上述全部资源 |

例如，`nix build .#models-inference` 只构建或下载推理资源。

### 组合模型输出

软件包的 `models` 参数接受一个模型包或模型包列表。列表会合并目录并继承各模型包
声明的构建检查。例如，下面的组合包含变声和 PyMSS 资源，但不包含训练资源：

```nix
let
  rvcPkgs = rvc-nix.packages.${pkgs.stdenv.hostPlatform.system};
in
{
  programs.rvc.package = rvcPkgs.cuda118.override {
    models = [
      rvcPkgs.models-inference
      rvcPkgs.models-pymss
    ];
  };
}
```

`models` 会替换软件包原有的整组模型，不是追加。以下两种写法等价：

```nix
package = rvcPkgs.cuda118-all;

package = rvcPkgs.cuda118.override {
  models = [ rvcPkgs.models-all ];
};
```

`models = [ ];` 与 `models = null;` 都表示不捆绑任何模型。此时程序仍在，但用户
必须自行提供 HuBERT 和 RMVPE，才能进行常规变声。

### 使用自己的目标音色

经常更新或不希望公开的 `.pth` 和 `.index` 应直接放入用户数据目录：

```text
$XDG_DATA_HOME/rvc/assets/weights/my-voice.pth
$XDG_DATA_HOME/rvc/assets/indices/my-voice.index
```

这种方式无需重建软件包，也不会把私人模型复制到本机其他用户可能读取的 Nix
store。

只有需要固定并共享的模型才适合打包成 derivation。例如，可以把 flake 源中的
两个模型文件加入软件包：

```nix
let
  rvcPkgs = rvc-nix.packages.${pkgs.stdenv.hostPlatform.system};
  myVoiceModels = pkgs.runCommand "rvc-my-voice-models" {
    passthru.modelChecks = [ ];
  } ''
    install -Dm444 ${./models/my-voice.pth} \
      "$out/assets/weights/my-voice.pth"
    install -Dm444 ${./models/my-voice.index} \
      "$out/assets/indices/my-voice.index"
  '';
in
{
  programs.rvc.package = rvcPkgs.cuda118.override {
    models = [
      rvcPkgs.models-inference
      myVoiceModels
    ];
  };
}
```

Git flake 只能读取属于 flake 源的本地文件，例如已被 Git 跟踪的文件。自定义模型
derivation 必须提供 `passthru.modelChecks`；没有额外软件包检查时使用 `[ ]`。没有
配套索引时删去第二条 `install` 即可。必须保留 `models-inference`，因为目标音色
不能替代 HuBERT 和 RMVPE。

## 用户数据目录

`$XDG_DATA_HOME` 默认是 `~/.local/share`。程序使用以下目录：

```text
$XDG_DATA_HOME/rvc/       模型、索引、日志和训练数据
$XDG_CONFIG_HOME/rvc/     Realtime GUI 设置
$XDG_CACHE_HOME/rvc/      临时音频、上传文件和库缓存
```

WebUI 训练生成的可用于推理的 `added_*.index` 位于
`$XDG_DATA_HOME/rvc/logs/<实验名>/`，同时会在 `assets/indices` 中创建入口。
自动匹配会搜索两个位置。推理应使用 `added_*.index`，不要使用中间产物
`trained_*.index`。

使用无模型软件包时，还需自行提供：

```text
$XDG_DATA_HOME/rvc/assets/hubert_base/   HuBERT 模型目录
$XDG_DATA_HOME/rvc/assets/rmvpe/rmvpe.pt RMVPE 模型
```

可通过 `RVC_DATA_DIR`、`RVC_CONFIG_DIR` 和 `RVC_CACHE_DIR` 修改三个根目录。启动器
只链接数据目录中尚不存在的打包资源，不会覆盖用户已有的同名文件。

## 检查运行环境

先构建所选软件包，再运行其中的 `rvc-doctor`：

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda118
./result/bin/rvc-doctor

nix build .#cuda128
./result/bin/rvc-doctor
```

`rvc-doctor` 检查 Torch、RVC 选择的设备、核心二进制扩展和 ONNX Runtime。CUDA
软件包还会检查 CUDA kernel 与 cuDNN，并要求显卡至少具有 4 GiB 显存和 CUDA
计算能力 5.3；不满足要求时不会回退到 CPU。CUDA 计算能力描述 GPU 硬件架构，
不是 CUDA Toolkit 或驱动版本。

NixOS 默认从 `/run/opengl-driver/lib` 加载 NVIDIA 驱动库。其他 Linux 发行版需要
将 `RVC_DRIVER_LIBRARY_PATH` 指向包含 `libcuda.so.1` 的目录。
