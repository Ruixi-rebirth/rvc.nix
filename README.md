# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

rvc.nix provides reproducible Nix packages for
[RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI)
on `x86_64-linux`. It packages the upstream Realtime GUI, WebUI, RVC CLI, and
PyMSS CLI, with NixOS and PipeWire integration.

## Start Realtime GUI

Choose one command for your hardware:

```console
# CPU, AMD GPU, or Intel GPU
nix run github:Ruixi-rebirth/rvc.nix

# NVIDIA GPU before the RTX 50 series
nix run github:Ruixi-rebirth/rvc.nix#cuda118-with-models

# NVIDIA RTX 50 series
nix run github:Ruixi-rebirth/rvc.nix#cuda128-with-models
```

These commands include HuBERT and RMVPE. HuBERT extracts content features from
the input speech, RMVPE extracts pitch, and your `.pth` voice model determines
the converted voice. A matching `.index` file is optional.

After Realtime GUI opens, choose the voice model, microphone, and output device.
It uses Tk/X11 and runs through XWayland in a Wayland session.

## Start WebUI or a CLI

```console
# WebUI: convert audio files
nix run github:Ruixi-rebirth/rvc.nix#web-with-models

# WebUI: convert files, train models, and separate music sources
nix run github:Ruixi-rebirth/rvc.nix#web-with-all-models

# RVC CLI: show command-line options
nix run github:Ruixi-rebirth/rvc.nix#cli-with-models -- --help

# PyMSS CLI: show separation options
nix run github:Ruixi-rebirth/rvc.nix#pymss-with-models -- infer --help
```

`web-with-all-models` adds the RVC v1/v2 pretrained weights, mute samples, and
five PyMSS weights to the file-conversion package. To train a voice model,
provide recordings of the target voice. If you already have a `.pth` voice
model, use it directly for file conversion.

Use the [usage guide](docs/usage.md) for every CPU/CUDA command, model-free
variant, package output, and data directory.

## CPU or CUDA

The CUDA package choice follows the
[locked upstream hardware guide](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI/blob/81eed5e8f68b6bed1789f682fe78cdd324495afc/docs/en/README.en.md#choose-dependencies-by-hardware):
CUDA 11.8 for NVIDIA GPUs before the RTX 50 series and CUDA 12.8 for the RTX 50
series.

Nix supplies the selected CUDA runtime, cuDNN, and cuBLAS. The host only needs
an NVIDIA driver that supports that runtime; a matching CUDA Toolkit is not
required. `rvc-doctor` in the selected package checks the driver and GPU.

CUDA 11.8 has passed conversion tests on an RTX 2070 Super Max-Q. CUDA 12.8 has
passed build checks but has not been tested on RTX 50-series hardware.

## More information

- [Usage guide](docs/usage.md): all commands, packages, models, and data paths.
- [NixOS and PipeWire](docs/nixos.md): module, WebUI service, and virtual
  microphone.
- [Security](SECURITY.md): model loading and the WebUI network boundary.
- [Contributing](CONTRIBUTING.md): repository layout, tests, and releases.

This project is distributed under the [MIT License](LICENSE). Upstream RVC and
model assets retain their own licenses and terms.
