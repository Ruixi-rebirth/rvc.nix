# rvc.nix 使用手册

[English](usage.md) | [简体中文](usage.zh-CN.md) | [返回项目首页](../README.zh-CN.md)

本手册说明该运行哪个命令、命令包含哪些模型，以及 RVC 把用户文件放在哪里。
命令中的 `.` 表示当前仓库；不下载仓库时，将它换成
`github:Ruixi-rebirth/rvc.nix`。

## 先选要运行的程序

启动 Realtime GUI：

```console
# CPU、AMD GPU 或 Intel GPU
nix run .

# RTX 50 系以前的 NVIDIA GPU
nix run .#cuda118-with-models

# RTX 50 系列 NVIDIA GPU
nix run .#cuda128-with-models
```

启动 WebUI：

```console
# 使用 HuBERT 和 RMVPE 进行文件变声
nix run .#web-with-models

# 文件变声、训练和音乐源分离
nix run .#web-with-all-models

# WebUI 不附带软件包提供的模型
nix run .#web
```

运行 RVC CLI：

```console
nix run .#cli-with-models -- --help
nix run .#cli -- --help
```

运行 PyMSS CLI：

```console
nix run .#pymss-with-models -- infer --help
nix run .#pymss -- infer --help
```

运行上游 Python 脚本：

```console
nix run .#python -- train/train.py --help
nix run .#cuda118-python -- train/train.py --help
nix run .#cuda128-python -- train/train.py --help
```

每组命令的第一条使用 CPU。将入口名前加上 `cuda118-` 或 `cuda128-` 可以使用
对应 CUDA 版本。`nix run .` 是默认的 CPU 命令，等同于
`nix run .#with-models`。

`--` 后面的参数会传给 RVC、PyMSS 或 Python 脚本。示例中的 `--help` 只显示参数，
不会处理音频或开始训练。

下面列出完整的模型版本和 CUDA 版本。

### Realtime GUI

```console
nix run .#realtime
nix run .#with-models
nix run .#cuda118
nix run .#cuda118-with-models
nix run .#cuda128
nix run .#cuda128-with-models
```

### WebUI

```console
nix run .#web
nix run .#web-with-models
nix run .#web-with-all-models
nix run .#cuda118-web
nix run .#cuda118-web-with-models
nix run .#cuda118-web-with-all-models
nix run .#cuda128-web
nix run .#cuda128-web-with-models
nix run .#cuda128-web-with-all-models
```

### RVC CLI

```console
nix run .#cli
nix run .#cli-with-models -- --help
nix run .#cuda118-cli
nix run .#cuda118-cli-with-models -- --help
nix run .#cuda128-cli
nix run .#cuda128-cli-with-models -- --help
```

### PyMSS CLI

```console
nix run .#pymss
nix run .#pymss-with-models -- infer --help
nix run .#cuda118-pymss
nix run .#cuda118-pymss-with-models -- infer --help
nix run .#cuda128-pymss
nix run .#cuda128-pymss-with-models -- infer --help
```

### Python 和维护命令

```console
nix run .#python -- train/train.py --help
nix run .#cuda118-python -- train/train.py --help
nix run .#cuda128-python -- train/train.py --help
nix run .#generate-patches
```

`rvc-python` 会从 Nix store 中的软件包查找 `train/train.py` 等上游脚本，不需要
先下载 rvc.nix 或上游 RVC 仓库。`generate-patches` 供仓库维护者重新生成补丁，
不是运行 RVC 的命令。

## 模型怎么分工

RVC 使用三类模型文件：

- HuBERT 从输入语音中提取内容特征。
- RMVPE 提取音高。Realtime GUI、WebUI 文件变声和 RVC CLI 默认使用它。
- 用户自己的 `.pth` 语音模型决定转换后的音色，配套的 `.index` 文件可选。

RVC 入口名中的 `-with-models` 表示包含 HuBERT 和 RMVPE。
`-with-all-models` 还包含 WebUI 训练用的 RVC v1/v2 预训练权重和静音样本，以及
5 个 PyMSS 权重。PyMSS 入口中的 `-with-models` 只表示包含这 5 个 PyMSS 权重。

不带模型的版本不会自动下载 HuBERT 或 RMVPE，适合已经自行准备这些文件，或只需
打开界面、查看 `--help` 和检查环境的情况。没有 HuBERT 时不能进行 RVC 变声，
训练也不能提取特征。没有 RMVPE 时，Realtime GUI 和 WebUI 可改用 `pm` 或
`fcpe`，RVC CLI 可改用 `pm`；HuBERT 仍然是必需的。普通用户应选择
`-with-models`。

## 构建软件包

`nix build` 只构建或下载软件包，不启动程序：

```console
nix build .#cpu
nix build .#cpu-with-models
nix build .#cpu-with-all-models
nix build .#cuda118
nix build .#cuda118-with-models
nix build .#cuda118-with-all-models
nix build .#cuda128
nix build .#cuda128-with-models
nix build .#cuda128-with-all-models
```

`nix build .` 和 `.#default` 都是 `.#cpu-with-models` 的别名。

以下输出只包含模型，不包含 RVC 程序：

```console
nix build .#models-inference
nix build .#models-pretrained-v1
nix build .#models-pretrained-v2
nix build .#models-mute
nix build .#models-training
nix build .#models-pymss
nix build .#models-all
```

`models-all` 包含 HuBERT、RMVPE、v1/v2 预训练权重、静音样本和 5 个 PyMSS 权重，
主要供 overlay 和自定义软件包组合使用。

## 用户文件和数据目录

用户文件默认放在：

```text
$XDG_DATA_HOME/rvc/assets/weights/   .pth 语音模型
$XDG_DATA_HOME/rvc/assets/indices/   外部 .index 索引
```

使用不带模型的软件包时，还需自行提供：

```text
$XDG_DATA_HOME/rvc/assets/hubert_base/   HuBERT 模型目录
$XDG_DATA_HOME/rvc/assets/rmvpe/rmvpe.pt RMVPE 模型
```

`$XDG_DATA_HOME` 默认是 `~/.local/share`。WebUI 训练生成的可用于推理的
`added_*.index` 位于 `$XDG_DATA_HOME/rvc/logs/<实验名>/`，同时会在
`assets/indices` 中创建入口。自动匹配索引时会搜索这两个位置。推理使用
`added_*.index`，不要使用中间产物 `trained_*.index`。

程序还会使用以下目录：

```text
$XDG_DATA_HOME/rvc/       模型、索引、日志和训练数据
$XDG_CONFIG_HOME/rvc/     Realtime GUI 设置
$XDG_CACHE_HOME/rvc/      临时音频、上传文件和库缓存
```

可使用 `RVC_DATA_DIR`、`RVC_CONFIG_DIR` 和 `RVC_CACHE_DIR` 修改这些位置。启动器
把软件包中的模型链接到数据目录时，会保留已有的同名文件。

## 检查运行环境

先构建要检查的软件包，再运行其中的 `rvc-doctor`：

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda118
./result/bin/rvc-doctor

nix build .#cuda128
./result/bin/rvc-doctor
```

`rvc-doctor` 检查 Torch、所选设备、核心二进制扩展和 ONNX Runtime。CUDA 软件包
还会检查 cuDNN，并要求可用的 NVIDIA GPU 至少具有 4 GiB 显存和 CUDA 计算能力
5.3；不满足时不会回退到 CPU。CUDA 计算能力表示 GPU 的硬件架构，不是 CUDA
Toolkit 或驱动的版本号。

NixOS 默认从 `/run/opengl-driver/lib` 加载 NVIDIA 驱动库。其他 Linux 发行版需要
将 `RVC_DRIVER_LIBRARY_PATH` 指向包含 `libcuda.so.1` 的目录。
