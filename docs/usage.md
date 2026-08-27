# rvc.nix usage guide

[English](usage.md) | [简体中文](usage.zh-CN.md) | [Project home](../README.md)

This guide explains which command to run, which models it includes, and where
RVC stores user data. In the examples, `.` means the current repository. To run
without downloading the repository, replace `.` with
`github:Ruixi-rebirth/rvc.nix`.

## Choose a command

Start Realtime GUI:

```console
# CPU, AMD GPU, or Intel GPU
nix run .

# NVIDIA GPU before the RTX 50 series
nix run .#cuda118-with-models

# NVIDIA RTX 50 series
nix run .#cuda128-with-models
```

Start WebUI:

```console
# File conversion with HuBERT and RMVPE
nix run .#web-with-models

# File conversion, training, and music source separation
nix run .#web-with-all-models

# WebUI without packaged models
nix run .#web
```

Run RVC CLI:

```console
nix run .#cli-with-models -- --help
nix run .#cli -- --help
```

Run PyMSS CLI:

```console
nix run .#pymss-with-models -- infer --help
nix run .#pymss -- infer --help
```

Run an upstream Python script:

```console
nix run .#python -- train/train.py --help
nix run .#cuda118-python -- train/train.py --help
nix run .#cuda128-python -- train/train.py --help
```

The first command in each group uses CPU. Add `cuda118-` or `cuda128-` to the
entry-point name for the CUDA variant. `nix run .` is the default CPU command
and is the same as `nix run .#with-models`.

Arguments after `--` go to RVC, PyMSS, or the Python script. The `--help`
examples only display options; they do not process audio or start training.

The complete list, including model-free and CUDA variants, is below.

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

### Python and maintenance

```console
nix run .#python -- train/train.py --help
nix run .#cuda118-python -- train/train.py --help
nix run .#cuda128-python -- train/train.py --help
nix run .#generate-patches
```

`rvc-python` resolves paths such as `train/train.py` from the upstream source in
the Nix store. It does not require a local copy of rvc.nix or the upstream RVC
repository. `generate-patches` is for repository maintainers and is not a runtime
command.

## Models

RVC uses three different kinds of model files:

- HuBERT extracts content features from the input speech.
- RMVPE extracts pitch. Realtime GUI, WebUI file conversion, and RVC CLI use it
  by default.
- A user-provided `.pth` voice model determines the converted voice. Its
  matching `.index` file is optional.

`-with-models` supplies HuBERT and RMVPE for RVC commands. `-with-all-models`
also supplies RVC v1/v2 pretrained weights and mute samples for WebUI training,
plus five PyMSS weights. PyMSS commands use `-with-models` for those five PyMSS
weights only.

Model-free packages do not download HuBERT or RMVPE. They are useful when those
files already exist in the data directory, or when only the UI, `--help`, or
environment checks are needed. Without HuBERT, RVC conversion and training
feature extraction cannot run. Without RMVPE, use `pm` (or `fcpe` in Realtime
GUI/WebUI) instead. Most users should choose `-with-models`.

## Build packages

`nix build` builds or downloads a package without starting it:

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

`nix build .` and `.#default` are aliases for `.#cpu-with-models`.

Standalone model outputs contain models without the RVC program:

```console
nix build .#models-inference
nix build .#models-pretrained-v1
nix build .#models-pretrained-v2
nix build .#models-mute
nix build .#models-training
nix build .#models-pymss
nix build .#models-all
```

`models-all` contains HuBERT, RMVPE, v1/v2 pretrained weights, mute samples,
and five PyMSS weights. These outputs are intended for overlays and custom
package composition.

## User files and data directories

By default, put user files here:

```text
$XDG_DATA_HOME/rvc/assets/weights/   .pth voice models
$XDG_DATA_HOME/rvc/assets/indices/   external .index files
```

For a model-free package, also provide:

```text
$XDG_DATA_HOME/rvc/assets/hubert_base/   HuBERT model directory
$XDG_DATA_HOME/rvc/assets/rmvpe/rmvpe.pt RMVPE model
```

`$XDG_DATA_HOME` normally resolves to `~/.local/share`. WebUI training writes
the inference-ready `added_*.index` under
`$XDG_DATA_HOME/rvc/logs/<experiment>/` and creates an entry under
`assets/indices`. Automatic matching searches both locations. Use
`added_*.index` for inference, not the intermediate `trained_*.index`.

Other mutable data uses:

```text
$XDG_DATA_HOME/rvc/       models, indices, logs, and training data
$XDG_CONFIG_HOME/rvc/     Realtime GUI settings
$XDG_CACHE_HOME/rvc/      temporary audio, uploads, and library caches
```

Override these locations with `RVC_DATA_DIR`, `RVC_CONFIG_DIR`, and
`RVC_CACHE_DIR`. The launcher preserves existing files with the same name when
it links packaged models into the data directory.

## Check the environment

Build the package to check, then run its `rvc-doctor` command:

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda118
./result/bin/rvc-doctor

nix build .#cuda128
./result/bin/rvc-doctor
```

`rvc-doctor` checks Torch, the selected device, core binary extensions, and ONNX
Runtime. CUDA packages also check cuDNN and require a usable NVIDIA GPU with at
least 4 GiB of memory and CUDA compute capability 5.3. Failure does not fall
back to CPU. CUDA compute capability describes the GPU hardware architecture,
not the CUDA Toolkit or driver version.

NixOS loads NVIDIA driver libraries from `/run/opengl-driver/lib` by default.
On another Linux distribution, point `RVC_DRIVER_LIBRARY_PATH` at the directory
containing `libcuda.so.1`.
