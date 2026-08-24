# rvc.nix

[English](README.md) | [简体中文](README.zh-CN.md)

[![CI](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml/badge.svg)](https://github.com/Ruixi-rebirth/rvc.nix/actions/workflows/ci.yml)

Reproducible Nix packages for
[RVC WebUI](https://github.com/RVC-Project/Retrieval-based-Voice-Conversion-WebUI).

The project packages the upstream source, Python environment, CPU and CUDA
runtimes, native libraries, launchers, and optional inference models as Nix
derivations. It does not create a virtualenv, invoke `pip` at runtime, or copy
the application source into a mutable working tree.

> **Project status:** CPU and CUDA packages build successfully on
> `x86_64-linux`; CLI parsing, complete WebUI construction, and realtime module
> import/configuration are covered by `nix flake check`. The CUDA runtime has
> also been verified on an RTX 2070 Super Max-Q with NVIDIA driver 610.57.04,
> including real HuBERT and RMVPE CUDA forwards, an offline CLI conversion, and
> the realtime synthesis path with the same pinned checkpoint. The CUDA package
> refuses to start when no supported NVIDIA device is available.
> Live PipeWire virtual-device routing was verified on PipeWire 1.6.8.
> End-to-end conversion with a community-trained Nahida v2 model completed on
> both CPU and CUDA.

## Features

- `flake-parts` flake with packages, apps, an overlay, and a NixOS module
- Python 3.12 environments locked with `uv2nix` and `pyproject.nix`
- CPU as the portable default; CUDA 11.8 is always selected explicitly
- fixed upstream RVC revision
- optional HuBERT and RMVPE model package with immutable revision and hashes
- WebUI, realtime GUI, offline RVC CLI, and upstream PyMSS CLI entry points
- XDG data, config, and cache directories; source remains read-only in the store
- realtime Tk GUI requires X11; Wayland sessions require XWayland
- PipeWire virtual microphone NixOS module

## Quick start

Run realtime RVC directly from GitHub on CPU with the pinned HuBERT and RMVPE
models:

```console
nix run github:Ruixi-rebirth/rvc.nix
```

From a checkout, the shorter equivalent is:

```console
nix run .
```

`nix run` starts an application (the default is the CPU realtime GUI *with*
pinned inference models), while `nix build` builds a package: `nix build .`
produces the lean CPU package *without* model assets. See the output tables
below for the full matrix.

The flake declares the project's [Cachix](https://www.cachix.org/) binary
cache (`ruixi-rebirth`). Nix asks once whether to accept this flake
configuration on first use — answer yes, and the CPU/CUDA closures pushed by
CI are substituted instead of built locally. To pre-approve it from the
command line, pass `--accept-flake-config`.

Run it with an NVIDIA GPU supported by the CUDA 11.8 PyTorch build. RVC requires
at least 4 GiB of GPU memory and CUDA compute capability 5.3:

```console
nix run .#cuda-with-models
```

The first build is large. Nix downloads each dependency and model once and
reuses it from the store afterwards.

Personal voice models are mutable user data. Put their `.pth` files in
`$XDG_DATA_HOME/rvc/assets/weights` and `.index` files in
`$XDG_DATA_HOME/rvc/logs`, which is where the realtime GUI looks for indices.
`$XDG_DATA_HOME` is normally `~/.local/share`, so the default paths are
`~/.local/share/rvc/assets/weights` and `~/.local/share/rvc/logs`.

## Outputs

| Output | Purpose |
| --- | --- |
| `.#default`, `.#cpu` | CPU package without large model assets |
| `.#cuda` | CUDA 11.8 package without model assets |
| `.#cpu-with-models` | CPU package with pinned HuBERT and RMVPE |
| `.#cuda-with-models` | CUDA package with pinned HuBERT and RMVPE |
| `.#models-inference` | Standalone pinned inference model tree |
| `.#models-pretrained-v1` | Official RVC v1 training checkpoints |
| `.#models-pretrained-v2` | Official RVC v2 training checkpoints |
| `.#models-mute` | Training silence samples |
| `.#models-training` | Both training generations plus silence samples |
| `.#models-all` | Inference and training assets |
| `.#cpu-with-all-models` | CPU package with every model set packaged here |
| `.#cuda-with-all-models` | CUDA package with every model set packaged here |

Measured at the pinned revision with `nix path-info -Sh`; approximate, and Nix
shares store paths already present on the host:

| Output | CPU | CUDA |
| --- | ---: | ---: |
| Lean package | 3.4 GiB | 7.8 GiB |
| With inference models | 3.7 GiB | 8.1 GiB |
| With all models | 6.0 GiB | 10.3 GiB |

Model sets alone: `models-inference` 0.34 GiB, `models-training` 2.2 GiB,
`models-all` 2.6 GiB.

The default overlay builds against the consumer's final nixpkgs package set. It
exports `rvc`/`rvc-cpu`, `rvc-cuda`, their `*-with-models` and
`*-with-all-models` variants, plus `rvc-models-inference`,
`rvc-models-training`, and `rvc-models-all`.

Available application entry points:

| Command | Entry point |
| --- | --- |
| `nix run .` | CPU realtime GUI with pinned inference models |
| `nix run .#realtime` | CPU realtime GUI without packaged models |
| `nix run .#web` | CPU WebUI |
| `nix run .#cli -- --help` | CPU offline CLI |
| `nix run .#pymss -- list` | CPU upstream PyMSS CLI |
| `nix run .#cuda` | CUDA realtime GUI |
| `nix run .#cuda-web` | CUDA WebUI |
| `nix run .#cuda-cli -- --help` | CUDA offline CLI |
| `nix run .#cuda-pymss -- list` | CUDA upstream PyMSS CLI |
| `nix run .#generate-patches` | Regenerate locked-source patches |
| `nix run .#with-models` | Explicit alias for the default CPU app |
| `nix run .#web-with-models` | CPU WebUI with inference models |
| `nix run .#web-with-all-models` | CPU WebUI with all model assets |
| `nix run .#cli-with-models -- --help` | CPU CLI with inference models |
| `nix run .#cuda-with-models` | CUDA realtime GUI with inference models |
| `nix run .#cuda-web-with-models` | CUDA WebUI with inference models |
| `nix run .#cuda-web-with-all-models` | CUDA WebUI with all model assets |
| `nix run .#cuda-cli-with-models -- --help` | CUDA CLI with inference models |

Inspect the packaged runtime:

```console
nix build .#cpu
./result/bin/rvc-doctor

nix build .#cuda
./result/bin/rvc-doctor
```

`rvc-doctor` reports the Torch build, CUDA runtime, selected device, core binary
imports, a real ONNX Runtime CPU-provider session, and (for the CUDA output) a
cuDNN loader check. The CUDA doctor exits unsuccessfully if PyTorch cannot use
an NVIDIA device or if no visible GPU meets RVC's minimum of 4 GiB of memory and
CUDA compute capability 5.3, so the explicit CUDA variant never silently falls
back to CPU during device selection. Real CPU and CUDA HuBERT, RMVPE, offline
CLI, and realtime synthesis forwards are covered separately. `nvidia-smi`
should also succeed on the target machine.

NixOS exposes NVIDIA userspace libraries at `/run/opengl-driver/lib`, which is
the launcher's default. On another Linux distribution, set
`RVC_DRIVER_LIBRARY_PATH` to the directory containing that host's `libcuda.so.1`.
The CUDA path has currently been hardware-tested on NixOS; non-NixOS driver
integration is supported as an explicit override but is not yet acceptance
tested.

## Persistent data

Launchers create only mutable runtime state:

```text
$XDG_DATA_HOME/rvc/       models, indices, logs, and training data
$XDG_CONFIG_HOME/rvc/     realtime GUI settings
$XDG_CACHE_HOME/rvc/      temporary audio, uploads, and library caches
```

Override them with `RVC_DATA_DIR`, `RVC_CONFIG_DIR`, and `RVC_CACHE_DIR`.
Packaged model files are linked from the Nix store only when their destination
does not already exist, so user files always take precedence.
Each model output also carries its immutable source revision and the pinned
repository model card under `share/doc/rvc-models`.

The WebUI listens on `127.0.0.1:7865` by default and advances to the next free
port when needed. `RVC_WEBUI_HOST`, `RVC_WEBUI_PORT`, and the upstream `--port`
argument can override those defaults. This is a trusted single-user interface
with filesystem and training controls. Authentication at a reverse proxy does
not make it safe for untrusted users.

## PipeWire virtual microphone

Add the flake and module to a NixOS configuration:

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

            # Optional: start rvc-web for each graphical login.
            webui.enable = false;
          };
        }
      ];
    };
  };
}
```

The module always installs RVC. It enables PipeWire, WirePlumber, ALSA,
PulseAudio compatibility, and rtkit only when `virtualMic.enable = true`, then
creates:

```text
PipeWire default microphone -> RVC -> RVC-Output -> RVC-Microphone -> voice application
```

After rebuilding NixOS, open the realtime GUI and choose the devices yourself.
For the tested NixOS path, select `ALSA` as the device type, `pipewire` as the
GUI input, and `RVC-Output` as the GUI output. The `pipewire` input follows
PipeWire's current default source, so choose the physical microphone in your
system audio settings. Then select `RVC-Microphone` as the input in Discord, a
game, or another voice application. The module does not filter, preselect, or
hide devices; the GUI displays what its audio backend enumerates.

Each side picks its own device by role; do not cross them:

| Interface | Device | Selection |
| --- | --- | --- |
| Realtime GUI | device type | `ALSA` |
| Realtime GUI | input | `pipewire` |
| Realtime GUI | output | `RVC-Output` |
| QQ/Discord etc. | input (microphone) | `RVC-Microphone` |
| QQ/Discord etc. | output (speaker) | your real speaker/headphones |

`RVC-Microphone` is the monitor of `RVC-Output`, so it is silent while RVC is not
writing converted audio. PipeWire negotiates sample rate, channel count, and
channel map; the module does not force an audio format or select any physical
device. It also does not monitor the converted audio locally, add echo
cancellation, or change system defaults.

| Option | Type | Default | Purpose |
| --- | --- | --- | --- |
| `programs.rvc.enable` | boolean | `false` | Install RVC |
| `programs.rvc.package` | package | CPU, models | Select the RVC package |
| `programs.rvc.chinese.enable` | boolean | `false` | Use Simplified Chinese |
| `programs.rvc.webui.enable` | boolean | `false` | Start WebUI on login |
| `programs.rvc.webui.host` | string | `127.0.0.1` | WebUI bind address |
| `programs.rvc.webui.port` | port | `7865` | Starting WebUI port |
| `programs.rvc.virtualMic.enable` | boolean | `false` | Create a virtual mic |

The WebUI user service does not open the firewall. If `webui.host` is changed
from loopback, firewall and access control remain explicit administrator
decisions.

## Development

```console
nix develop
nix fmt
nix flake check
nix build .#cpu
nix build .#cuda
```

The development shell includes the same `treefmt` wrapper used by `nix fmt`, so
repository-wide formatting needs no global tools. The wrapper formats Nix,
TOML, and standalone shell files, runs ShellCheck, and checks Markdown without
reflowing prose. CI invokes the same wrapper in `--ci` mode. Packaged launchers
are checked by `writeShellApplication` during their Nix build.

Python dependencies are declared separately for CPU and CUDA because the
official PyTorch indexes publish different wheel graphs. Native wheel fixes are
kept in `nix/python-overrides.nix`; each override should describe a real build
or ELF dependency and remain scoped to the affected package.
`checks.pyproject-sync` fails the build when the two manifests drift in an
undocumented way.

Upstream source changes are ordinary patch files under `nix/patches/`. The
per-file substitution patches are generated from `nix/patches/rules.py`
by `nix/patches/generate_patches.py`; the cross-file training subprocess
patch is maintained directly. Every patch starts with its purpose and
maintenance metadata. After updating the `rvc-src` input, regenerate and
review the set directly from the locked Nix store source:

```console
nix flake update rvc-src
nix run .#generate-patches
```

The generator applies every patch to a clean upstream copy, byte-compares the
result against the build pipeline, and re-runs the installCheck assertions, so
a patch that no longer matches fails here instead of inside a multi-gigabyte
build. CI re-runs this pipeline against the pinned source with
`checks.patches-in-sync`, so the checked-in patch files can never drift from
`flake.lock`.

Live acceptance scripts under `nix/tests/` cover what `nix flake check` cannot
because they need real audio hardware, a display, or a running PipeWire graph:
`cli-e2e-live.sh`, `realtime-infer-live.sh`,
`realtime-gui-live.sh`, `realtime-gui-click-live.sh`, `webui-live.sh`, and
`pipewire-live.sh`. Run them on the target machine; each prints its usage line
when called without arguments.

When working with newly created, untracked files in a Git checkout, use
`nix flake check path:.` until the files are added to Git. Git-backed `.` flakes
intentionally ignore untracked files.

## Troubleshooting

- **CUDA reports no usable device.** Run `nvidia-smi`; on NixOS the driver
  libraries default to `/run/opengl-driver/lib`, and on other distributions
  point `RVC_DRIVER_LIBRARY_PATH` at the directory containing `libcuda.so.1`.
  `rvc-doctor` is the first stop — it distinguishes "PyTorch has no CUDA" from
  "no GPU meets RVC's 4 GiB / compute 5.3 minimum".
- **The realtime GUI opens no window on Wayland.** The Tk GUI needs X11; enable
  XWayland.
- **Audio pitch or speed is off.** PipeWire negotiates the virtual-device
  format. Check the device type and sample-rate mode selected in the realtime
  GUI; the module deliberately does not override them.
- **The WebUI cannot be reached from another machine.** It binds `127.0.0.1`
  by default for a reason: the interface has filesystem and training controls,
  and the pinned Gradio 3.x has known CVEs that are only mitigated by the
  localhost binding. Treat `RVC_WEBUI_HOST` as a last resort, never expose the
  port publicly, and see the security model in [`SECURITY.md`](SECURITY.md).
- **Model downloads fail.** Packaged model assets come from the
  `lj1995/VoiceConversionWebUI` Hugging Face repository at an immutable
  revision (see `nix/models.nix`). If that repository ever moves, the pinned
  hashes still verify, but the URLs must be updated.

## Scope and limitations

- Only `x86_64-linux` is currently declared.
- The CPU and CUDA realtime GUIs use Tk/X11; Wayland sessions require XWayland.
  CPU/CUDA computation, WebUI, CLI, and PipeWire integration are otherwise
  display-server neutral.
- The default package excludes large model assets to keep its closure smaller.
- Training assets are split by RVC generation so users only fetch what they
  need; `models-all` remains an explicit, large output.
- `models-all` means every model set packaged by this flake: HuBERT, RMVPE,
  RVC v1/v2 pretrained checkpoints, and mute samples. PyMSS
  source-separation weights are not currently packaged.
- User-trained voice models and indices are deliberately not Nix store assets.
- PyTorch 2.7.1 provides weights-only loading by default for core RVC and
  ordinary PyMSS checkpoints. The package rejects unclassified explicit
  unrestricted loads; the underlying pickle risk is described in PyTorch's
  [serialization documentation](https://pytorch.org/docs/stable/notes/serialization.html).
  Explicit legacy PyMSS Demucs, TasNet, HTDemucs, and Apollo formats still use
  Python pickle for compatibility and must come from a trusted source.
- CUDA requires a working host NVIDIA driver, at least 4 GiB of GPU memory, and
  CUDA compute capability 5.3 or newer.

## TODO

- [ ] Add a NixOS option for custom voice models.

Contributions should follow [`CONTRIBUTING.md`](CONTRIBUTING.md). This project
is distributed under the
[MIT License](LICENSE); upstream RVC and model assets retain their own licenses
and terms.
