# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

Run RVC on Linux without assembling a Python environment, matching CUDA
dependencies, or arranging model directories by hand.

rvc.nix packages a pinned revision of
[RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)
for `x86_64-linux`. It provides the upstream Realtime GUI, WebUI, RVC CLI, and
PyMSS CLI as reproducible CPU, CUDA 11.8, and CUDA 12.8 packages. An optional
NixOS module adds a local WebUI service and PipeWire virtual microphone.

## Quick start

Install Nix with flake commands enabled; no repository checkout is required.
On the first run, Nix may ask to accept this flake's Cachix configuration.
Accepting it downloads CI-built packages when available. Declining it is also
supported, but may require a large local build.

Choose one command for the target machine:

```console
# CPU backend; also use this on systems with AMD or Intel graphics
nix run github:Ruixi-rebirth/rvc.nix

# CUDA 11.8 for supported NVIDIA GPUs before the RTX 50 series
nix run github:Ruixi-rebirth/rvc.nix#cuda118-with-models

# CUDA 12.8 for NVIDIA RTX 50-series GPUs
nix run github:Ruixi-rebirth/rvc.nix#cuda128-with-models
```

All three commands include HuBERT for content features and RMVPE for pitch
extraction. They do not include a target voice: select your own trusted `.pth`
voice model after Realtime GUI opens. A matching `.index` file is optional.

Realtime GUI requires X11; a Wayland session needs XWayland. AMD and Intel
systems use CPU inference because this project does not provide ROCm, Vulkan,
or Intel GPU acceleration.

## WebUI and command-line tools

```console
# WebUI with the inference models needed for file conversion
nix run github:Ruixi-rebirth/rvc.nix#web-with-models

# WebUI with the complete packaged model set (larger download)
nix run github:Ruixi-rebirth/rvc.nix#web-with-all-models

# RVC CLI
nix run github:Ruixi-rebirth/rvc.nix#cli-with-models -- --help

# PyMSS source-separation CLI with its packaged weights
nix run github:Ruixi-rebirth/rvc.nix#pymss-with-models -- infer --help
```

## Choose model assets

Model suffixes describe which assets are packaged. None of the variants
provides a finished target-voice model.

| Output | Assets | Use |
| --- | --- | --- |
| Default and RVC `-with-models` | HuBERT, RMVPE | RVC conversion |
| PyMSS `-with-models` | Five weights | Source separation |
| `-with-all-models` | All packaged assets | All WebUI workflows |
| Runtime outputs without a model suffix | None | Use existing models |

`web-with-all-models` is the all-in-one runnable command because the upstream
WebUI exposes file conversion, training, and source separation together. It
packages HuBERT, RMVPE, RVC v1/v2 pretrained weights, mute samples, and five
PyMSS weights. The v1/v2 weights initialize training; training still requires
target-voice recordings and produces the `.pth` model used for conversion.

The complete command, package, and standalone model-output matrix is in the
[usage guide](docs/usage.md).

## Choose CPU or CUDA

The CUDA package split follows the
[hardware guide from the pinned upstream revision](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/blob/81eed5e8f68b6bed1789f682fe78cdd324495afc/docs/en/README.en.md#choose-dependencies-by-hardware):
CUDA 11.8 for NVIDIA GPUs before the RTX 50 series and CUDA 12.8 for the RTX 50
series.

The packages provide RVC's Python environment and native user-space dependencies
from the Nix store. Their launchers discard the host's `LD_LIBRARY_PATH`; a CUDA
launcher adds only the configured NVIDIA driver directory. A separately
installed CUDA Toolkit is not required.

RVC Realtime GUI, WebUI, CLI, and `rvc-doctor` require at least 4 GiB of GPU
memory and CUDA compute capability 5.3 in a CUDA package. They fail instead of
silently falling back to CPU when no supported GPU is usable.

Run `rvc-doctor` from the selected package to check Torch, the RVC inference
device, binary extensions, ONNX Runtime, and cuDNN. CUDA 11.8 has completed real
conversion tests on an RTX 2070 Super Max-Q. CUDA 12.8 passes its package build
and hardware-independent checks but has not been tested on RTX 50-series
hardware.

On NixOS, CUDA packages use `/run/opengl-driver/lib` for the driver interface.
On another Linux distribution, set `RVC_DRIVER_LIBRARY_PATH` to the directory
containing `libcuda.so.1`.

## NixOS virtual microphone

The NixOS module can create `RVC-Output`, where Realtime GUI sends converted
audio, and `RVC-Microphone`, which voice applications use as their microphone.
It enables the required PipeWire integration only when
`programs.rvc.virtualMic.enable` is set. An optional WebRTC echo-cancelled input
supports physical speaker use without hard-coding ALSA device names. See the
[NixOS and PipeWire guide](docs/nixos.md) for the module configuration and exact
device selections.

## Documentation

- [Usage guide](docs/usage.md): all commands, packages, models, and data paths.
- [NixOS and PipeWire](docs/nixos.md): module, WebUI service, and virtual
  microphone.
- [Security](SECURITY.md): trusted-model rules and the WebUI network boundary.
- [Contributing](CONTRIBUTING.md): repository layout, checks, and release flow.

This project is distributed under the [MIT License](LICENSE). Upstream RVC and
model assets retain their own licenses and terms.
