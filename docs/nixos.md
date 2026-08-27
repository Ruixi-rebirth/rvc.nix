# NixOS and PipeWire

[English](nixos.md) | [简体中文](nixos.zh-CN.md) |
[Project home](../README.md)

This guide explains how to install RVC through the NixOS module, start a local
WebUI service, and create a PipeWire virtual microphone for voice applications.

## Add the module

First make rvc.nix follow the host's nixpkgs input:

```nix
{
  inputs.rvc-nix = {
    url = "github:Ruixi-rebirth/rvc.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

Then add the module and configuration to the target host's `modules` list:

```nix
modules = [
  rvc-nix.nixosModules.rvc
  {
    programs.rvc = {
      enable = true;
      package = rvc-nix.packages.x86_64-linux.cuda118;
      chinese.enable = true;
    };
  }
];
```

`nixosModules.default` and `nixosModules.rvc` refer to the same module. The
first is the conventional flake entry, while the second is easier to identify.

## Choose one package

Every name below is under `rvc-nix.packages.x86_64-linux`. First choose a row
for the hardware. Use the third column only when training assets or PyMSS
weights are needed.

| Hardware | Inference and realtime | Add training and PyMSS assets |
| --- | --- | --- |
| CPU, AMD GPU, or Intel GPU | `cpu` (default) | `cpu-all` |
| NVIDIA GPU before RTX 50 | `cuda118` | `cuda118-all` |
| NVIDIA RTX 50 series | `cuda128` | `cuda128-all` |

This is the module's only package selection. The selected package is installed
system-wide; when the WebUI service is enabled, it starts `rvc-web` from the
same package.

`cpu`, `cuda118`, and `cuda128` already include HuBERT and RMVPE for file
conversion and Realtime GUI. Their `-all` variants add RVC v1/v2 training
weights, mute samples, and five PyMSS weights. Neither kind supplies a user's
target voice `.pth`.

The `models-*` outputs contain model files but no RVC commands, so they are not
valid values for `programs.rvc.package`. See the [usage guide](usage.md) for
model lists and custom target voices.

## Module options

| Option | Default | Purpose |
| --- | --- | --- |
| `programs.rvc.enable` | `false` | Install RVC |
| `programs.rvc.package` | `packages.cpu` | Shared RVC and WebUI package |
| `programs.rvc.chinese.enable` | `false` | Use Simplified Chinese interfaces |
| `programs.rvc.webui.enable` | `false` | Start WebUI after graphical login |
| `programs.rvc.webui.host` | `127.0.0.1` | WebUI bind address |
| `programs.rvc.webui.port` | `7865` | WebUI starting port |
| `programs.rvc.virtualMic.enable` | `false` | Create virtual audio devices |

Installing RVC alone does not change audio services. PipeWire, WirePlumber,
ALSA, PulseAudio compatibility, and rtkit are enabled only when
`virtualMic.enable` is true.

`programs.rvc.virtualMic.echoCancellation.enable` also defaults to `false` and
creates the optional echo-cancelled input described below.

## WebUI user service

This configuration starts `rvc-web --noautoopen` after every graphical login:

```nix
programs.rvc.webui = {
  enable = true;
  host = "127.0.0.1";
  port = 7865;
};
```

If `programs.rvc.package` is `cuda118`, the service uses CUDA 11.8 and the
inference assets. With `cuda118-all`, the same service can also use the
packaged training and PyMSS assets.

Inspect its status and logs with:

```console
systemctl --user status rvc-webui.service
journalctl --user -u rvc-webui.service -f
```

If the starting port is occupied, upstream WebUI tries the next available
port. The module does not open the firewall. WebUI has filesystem and training
controls and is suitable only for a trusted local user. Reverse-proxy
authentication does not make it safe for untrusted users or the public
Internet. See [Security](../SECURITY.md) for the complete boundary.

## Create a virtual microphone

Enable the PipeWire integration:

```nix
programs.rvc.virtualMic.enable = true;
```

The module creates two devices:

- `RVC-Output`: a virtual output where Realtime GUI writes converted audio.
- `RVC-Microphone`: the monitor source of `RVC-Output`, read by voice apps as a
  microphone.

The signal path is:

```text
PipeWire default input -> Realtime GUI -> RVC-Output
                                            |
                                            +-> RVC-Microphone -> voice app
```

The module does not choose a physical microphone or change system defaults.
The `pipewire` input in Realtime GUI follows PipeWire's current default source,
so first select the physical microphone in the desktop audio settings.

## Realtime GUI device selection

Start Realtime GUI:

```console
rvc-realtime
```

Choose these settings in Realtime GUI:

| Setting | Selection |
| --- | --- |
| Device type | `ALSA` |
| Input | `pipewire` |
| Output | `RVC-Output` |

Do not select hardware endpoints such as `PCH`, `HDA`, or `HDMI` directly.
They may already be owned by PipeWire or may not support a duplex stream. `OSS`
also has no selectable input or output when no OSS device is available. The
stable PipeWire/ALSA endpoints above avoid these device-open failures.

Then choose these settings in Discord, a game, or streaming software:

| Setting | Selection |
| --- | --- |
| Input (microphone) | `RVC-Microphone` |
| Output (speaker) | real headphones or speakers |

The two applications have different roles. Realtime GUI reads the physical
microphone and writes to `RVC-Output`; the voice application reads converted
audio from `RVC-Microphone` but still sends playback to real headphones or
speakers.

`RVC-Microphone` contains only audio written by RVC. It is silent while
Realtime GUI is stopped or produces no output. PipeWire negotiates sample rate,
channel count, and channel mapping. The module does not force an audio format
or automatically play converted audio back to the local user.

When the virtual microphone is enabled, the module sets the PulseAudio
compatibility layer's default capture fragment to `1024/48000` (about 21 ms).
PipeWire's built-in default is two seconds, and some voice applications use it
when they do not provide their own capture fragment, causing multi-second delay.
Applications that explicitly request a fragment size keep their own setting.
The smaller default increases the audio service's processing frequency slightly.
After rebuilding, an already-open voice call must recreate its capture stream to
pick up the new buffer setting.

## Use speakers without acoustic feedback

When a physical microphone picks up speaker output, that audio enters RVC
again and creates an echo or feedback loop. Realtime GUI input and output noise
reduction are not acoustic echo cancellation. Headphones remain the
lowest-latency and most reliable solution.

When physical speakers are required, enable PipeWire's WebRTC echo canceller:

```nix
programs.rvc.virtualMic = {
  enable = true;
  echoCancellation.enable = true;
};
```

This adds `RVC-Echo-Cancelled-Input`. It compares the current PipeWire default
microphone with the monitor of the default output, so no physical ALSA name
such as PCH is hard-coded. First select the default microphone and speakers in
the desktop audio settings, then configure Realtime GUI for the intended use:

| Purpose | Realtime GUI input | Realtime GUI output |
| --- | --- | --- |
| Voice application | `RVC-Echo-Cancelled-Input` | `RVC-Output` |
| Local speaker test | `RVC-Echo-Cancelled-Input` | `pipewire` |

For a voice application, keep its microphone set to `RVC-Microphone` and its
playback output set to the physical speakers. For a local test, `pipewire`
plays the converted result through the speakers but does not also write it to
`RVC-Microphone`.

Echo cancellation removes only audio observed on the default output monitor.
Applications routed elsewhere are outside the reference path. AEC also adds
processing and cannot compensate perfectly for every room, volume, or device
placement, so it remains optional.

## Inspect PipeWire devices

Confirm that the virtual devices exist:

```console
pactl list short sinks | grep rvc_output
pactl list short sources | grep rvc_mic
```

Inspect the default input and complete audio graph:

```console
wpctl status
pactl info
```

The module creates virtual devices through `pipewire-pulse`. Its user service
restarts when generated configuration changes. If the current session retains
old devices, log in again or run:

```console
systemctl --user restart pipewire-pulse.service
```
