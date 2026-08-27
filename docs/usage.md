# rvc.nix usage guide

[English](usage.md) | [简体中文](usage.zh-CN.md) | [Project home](../README.md)

This guide explains how to run and install RVC, which models each output
contains, and where user data is stored. In the examples, `.` means the current
repository. Replace it with `github:Ruixi-rebirth/rvc.nix` when running without
a checkout.

## Three kinds of output

rvc.nix exposes three kinds of output for different uses:

| Output | How it is used | Intended user |
| --- | --- | --- |
| `apps` | `nix run` | Start Realtime GUI, WebUI, or a CLI directly |
| Packages | `nix build`, NixOS module | Install RVC |
| `models-*` | Package `models` argument | Compose model assets |

Most users need only an app or one of the six runtime packages. A `models-*`
output contains model files but no RVC commands, so it is not a valid value for
`programs.rvc.package`.

## Run an application

Apps without a CUDA suffix use CPU. Append `-cuda118` or `-cuda128` to select
an NVIDIA backend. Every app includes the model assets required for its task.

Start Realtime GUI:

```console
# CPU; also use this for AMD or Intel graphics
nix run .
nix run .#realtime

# NVIDIA GPUs before the RTX 50 series
nix run .#realtime-cuda118

# NVIDIA RTX 50-series GPUs
nix run .#realtime-cuda128
```

Start WebUI:

```console
# File conversion
nix run .#web
nix run .#web-cuda118
nix run .#web-cuda128

# File conversion, training, and PyMSS; larger download
nix run .#web-all
nix run .#web-all-cuda118
nix run .#web-all-cuda128
```

Run RVC CLI:

```console
nix run .#cli -- --help
nix run .#cli-cuda118 -- --help
nix run .#cli-cuda128 -- --help
```

Run PyMSS CLI:

```console
nix run .#pymss -- infer --help
nix run .#pymss-cuda118 -- infer --help
nix run .#pymss-cuda128 -- infer --help
```

`nix run .` and `nix run .#realtime` start the same CPU Realtime GUI. Arguments
after `--` go to RVC or PyMSS; the `--help` examples only display help.

## Build and install a package

Runtime package names have two dimensions: the backend selects CPU or CUDA,
and `-all` adds the training and PyMSS assets.

| Hardware | Inference and realtime | Add training and PyMSS assets |
| --- | --- | --- |
| CPU, AMD GPU, or Intel GPU | `cpu` (default) | `cpu-all` |
| NVIDIA GPU before RTX 50 | `cuda118` | `cuda118-all` |
| NVIDIA RTX 50 series | `cuda128` | `cuda128-all` |

For example:

```console
nix build .#cpu
nix build .#cpu-all
nix build .#cuda118
nix build .#cuda118-all
nix build .#cuda128
nix build .#cuda128-all
```

`nix build .` and `nix build .#default` are both aliases for
`nix build .#cpu`. Every runtime package contains these commands:

```text
rvc-realtime  Realtime GUI
rvc-web       WebUI
rvc-cli       RVC CLI
pymss         PyMSS CLI
rvc-doctor    runtime diagnostics
rvc-python    Python with the complete environment
```

A NixOS configuration therefore selects one `programs.rvc.package`; command
line tools and the optional WebUI service use that same package. Advanced users
can also run other scripts from the pinned upstream tree:

```console
nix shell .#cpu -c rvc-python train/train.py --help
```

### Use the overlay

Enable the default overlay when packages should be referenced from the nixpkgs
namespace:

```nix
{
  nixpkgs.overlays = [ rvc-nix.overlays.default ];
  environment.systemPackages = [ pkgs.rvc-cuda118 ];
}
```

In the overlay, `pkgs.rvc` is the CPU inference package. The other runtime
packages are `pkgs.rvc-cpu`, `pkgs.rvc-cuda118`, `pkgs.rvc-cuda128`, and their
`-all` variants; model outputs use the `pkgs.rvc-models-*` prefix. They match
the corresponding flake outputs and continue to support
`.override { models = ...; }`.

## Model assets

Voice conversion involves three kinds of model:

- HuBERT extracts content features from the input speech.
- RMVPE extracts pitch and is the default for Realtime GUI, WebUI file
  conversion, and RVC CLI.
- A user-provided `.pth` target voice determines the converted sound. Its
  matching `.index` file is optional.

The `realtime`, `web`, and `cli` apps include HuBERT and RMVPE. The `pymss` app
includes five source-separation weights. `web-all` additionally includes RVC
v1/v2 pretrained weights, mute samples, and PyMSS weights. Training weights
only initialize training; they are not finished target voices.

Standalone model outputs are:

| Output | Contents |
| --- | --- |
| `models-inference` | HuBERT and RMVPE |
| `models-pretrained-v1` | RVC v1 training weights |
| `models-pretrained-v2` | RVC v2 training weights |
| `models-mute` | Mute samples used by training |
| `models-training` | v1/v2 training weights and mute samples |
| `models-pymss` | Five PyMSS weights |
| `models-all` | All assets listed above |

For example, `nix build .#models-inference` builds or downloads only the
inference assets.

### Combine model outputs

The runtime package `models` argument accepts one model package or a list of
model packages. A list merges their directory trees and inherits the package
checks declared by each model package. This example includes conversion and
PyMSS assets without the training assets:

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

`models` replaces the package's existing bundle; it does not append to it.
These two forms are equivalent:

```nix
package = rvcPkgs.cuda118-all;

package = rvcPkgs.cuda118.override {
  models = [ rvcPkgs.models-all ];
};
```

Both `models = [ ];` and `models = null;` create a package without bundled
models. The commands remain present, but ordinary conversion then requires the
user to supply HuBERT and RMVPE.

### Use a custom target voice

Place frequently updated or private `.pth` and `.index` files directly in the
user data directory:

```text
$XDG_DATA_HOME/rvc/assets/weights/my-voice.pth
$XDG_DATA_HOME/rvc/assets/indices/my-voice.index
```

This avoids rebuilding the package and avoids copying private models into the
Nix store, where other local users may be able to read them.

Only assets that need reproducible sharing should become derivations. For
example, package two files from the flake source:

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

A Git flake can read only local files that belong to its source, such as files
tracked by Git. A custom model derivation must expose `passthru.modelChecks`;
use `[ ]` when it needs no extra package check. Remove the second `install`
when no index exists. Keep `models-inference`, because a target voice does not
replace HuBERT and RMVPE.

## User data directories

`$XDG_DATA_HOME` normally resolves to `~/.local/share`. The applications use:

```text
$XDG_DATA_HOME/rvc/       models, indices, logs, and training data
$XDG_CONFIG_HOME/rvc/     Realtime GUI settings
$XDG_CACHE_HOME/rvc/      temporary audio, uploads, and library caches
```

WebUI training writes the inference-ready `added_*.index` under
`$XDG_DATA_HOME/rvc/logs/<experiment>/` and also creates an entry under
`assets/indices`. Automatic matching searches both locations. Use
`added_*.index` for inference, not the intermediate `trained_*.index`.

A model-free package also requires:

```text
$XDG_DATA_HOME/rvc/assets/hubert_base/   HuBERT model directory
$XDG_DATA_HOME/rvc/assets/rmvpe/rmvpe.pt RMVPE model
```

Override the three roots with `RVC_DATA_DIR`, `RVC_CONFIG_DIR`, and
`RVC_CACHE_DIR`. The launcher links only packaged assets that do not already
exist in the data directory, so it does not replace user files with the same
name.

## Check the environment

Build the selected package, then run its `rvc-doctor` command:

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda118
./result/bin/rvc-doctor

nix build .#cuda128
./result/bin/rvc-doctor
```

`rvc-doctor` checks Torch, the RVC-selected device, core binary extensions,
and ONNX Runtime. CUDA packages also check a CUDA kernel and cuDNN, and require
at least 4 GiB of GPU memory and CUDA compute capability 5.3. Failure does not
fall back to CPU. CUDA compute capability describes the GPU hardware
architecture, not the CUDA Toolkit or driver version.

NixOS loads NVIDIA driver libraries from `/run/opengl-driver/lib` by default.
On another Linux distribution, point `RVC_DRIVER_LIBRARY_PATH` at the directory
containing `libcuda.so.1`.
