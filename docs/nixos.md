# NixOS and PipeWire

[English](nixos.md) | [简体中文](nixos.zh-CN.md) |
[Project home](../README.md)

This guide describes the rvc.nix NixOS module, WebUI user service, and PipeWire
virtual microphone.

## Configure the module

First add this repository as a flake input:

```nix
{
  inputs.rvc-nix.url = "github:Ruixi-rebirth/rvc.nix";
}
```

Then add the module and its configuration to the target host's `modules` list
inside `nixosSystem`:

```nix
modules = [
  rvc-nix.nixosModules.rvc
  {
    programs.rvc = {
      enable = true;
      package = rvc-nix.packages.x86_64-linux.cuda118-with-models;
      virtualMic.enable = true;
    };
  }
];
```

The example selects CUDA 11.8. Change `package` for the target machine:

| Hardware | `programs.rvc.package` |
| --- | --- |
| CPU, AMD GPU, or Intel GPU | `rvc-nix.packages.x86_64-linux.cpu-with-models` |
| Pre-RTX 50 NVIDIA | `rvc-nix.packages.x86_64-linux.cuda118-with-models` |
| RTX 50 series | `rvc-nix.packages.x86_64-linux.cuda128-with-models` |

`programs.rvc.enable = true` always installs the selected RVC package. The
default is the CPU package with HuBERT and RMVPE. Select a CUDA package
explicitly through `programs.rvc.package`. The module does not supply a target
voice `.pth` model; place one in the user data directory as described in the
[usage guide](usage.md).

## Module options

| Option | Default | Purpose |
| --- | --- | --- |
| `programs.rvc.enable` | `false` | Install `programs.rvc.package` |
| `programs.rvc.package` | CPU + HuBERT/RMVPE | Select a CPU or CUDA package |
| `programs.rvc.chinese.enable` | `false` | Use Simplified Chinese interfaces |
| `programs.rvc.webui.enable` | `false` | Start WebUI after graphical login |
| `programs.rvc.webui.host` | `127.0.0.1` | WebUI bind address |
| `programs.rvc.webui.port` | `7865` | WebUI starting port |
| `programs.rvc.virtualMic.enable` | `false` | Create virtual audio devices |

`programs.rvc.virtualMic.echoCancellation.enable` also defaults to `false`. It
adds a WebRTC echo-cancelled input for physical speaker use.

PipeWire, WirePlumber, ALSA, PulseAudio compatibility, and rtkit are enabled
only when `virtualMic.enable` is true. Installing RVC alone does not change the
existing audio services.

## Virtual microphone signal path

The module creates two devices:

- `RVC-Output`: a virtual output where Realtime GUI writes converted audio.
- `RVC-Microphone`: the monitor source of `RVC-Output`, read by voice apps as a
  microphone.

The full path is:

```text
PipeWire default input -> Realtime GUI -> RVC-Output
                                            |
                                            +-> RVC-Microphone -> voice app
```

The module does not choose a physical microphone or change system defaults.
The `pipewire` input in Realtime GUI follows PipeWire's current default source,
so select the physical microphone in the desktop audio settings.

## Realtime GUI device settings

After enabling the virtual microphone, start Realtime GUI:

```console
rvc-realtime
```

Choose these settings in Realtime GUI:

| Setting | Selection |
| --- | --- |
| Device type | `ALSA` |
| Input | `pipewire` |
| Output | `RVC-Output` |

Then choose these settings in Discord, a game, or streaming software:

| Setting | Selection |
| --- | --- |
| Input (microphone) | `RVC-Microphone` |
| Output (speaker) | real headphones or speakers |

The two applications use different devices by design:

- Realtime GUI reads the real microphone and writes to `RVC-Output`.
- The voice application reads converted audio from `RVC-Microphone`.
- The voice application's playback output remains the real headphones or
  speakers.

`RVC-Microphone` contains only audio written by RVC. It stays silent when
Realtime GUI is stopped or produces no output. PipeWire negotiates sample rate,
channel count, and channel mapping. The module does not force an audio format
or play converted audio back to the local user.

## Use speakers without acoustic feedback

When a physical microphone picks up speaker output, that audio can enter RVC
again and create an echo or feedback loop. The Realtime GUI input/output noise
reduction switches are not acoustic echo cancellation. Headphones remain the
lowest-latency and most reliable solution.

To use physical speakers, enable PipeWire's WebRTC echo canceller:

```nix
programs.rvc.virtualMic = {
  enable = true;
  echoCancellation.enable = true;
};
```

This adds `RVC-Echo-Cancelled-Input`. It correlates the current PipeWire default
microphone with the monitor of the current default output, so no physical ALSA
device name is hard-coded. Choose the physical microphone and speakers as the
PipeWire defaults, then use one of these RVC configurations:

| Purpose | Realtime GUI input | Realtime GUI output |
| --- | --- | --- |
| Voice application | `RVC-Echo-Cancelled-Input` | `RVC-Output` |
| Local speaker test | `RVC-Echo-Cancelled-Input` | `pipewire` |

For a voice application, keep its microphone set to `RVC-Microphone` and its
playback output set to the physical speakers. For a local speaker test, the
generic `pipewire` output plays the converted voice locally but does not feed
`RVC-Microphone`.

Echo cancellation only removes audio observed on the default output monitor.
Applications routed to another sink are outside that reference path. AEC also
adds processing and cannot fully compensate for every room, volume, microphone,
or speaker placement, which is why it is optional rather than enabled by
default.

## WebUI user service

This configuration starts `rvc-web --noautoopen` after every graphical login:

```nix
programs.rvc.webui = {
  enable = true;
  host = "127.0.0.1";
  port = 7865;
};
```

Inspect its status and logs with:

```console
systemctl --user status rvc-webui.service
journalctl --user -u rvc-webui.service -f
```

If the starting port is occupied, upstream WebUI tries the next available port.
The module does not open the firewall. WebUI has filesystem and training
controls and is only suitable for a trusted local user. Reverse-proxy
authentication does not make it safe for untrusted users or the public
Internet. See [SECURITY.md](../SECURITY.md) for the full boundary.

## Inspect PipeWire devices

Confirm that both virtual devices exist:

```console
pactl list short sinks | grep rvc_output
pactl list short sources | grep rvc_mic
```

Inspect the current default source and audio graph:

```console
wpctl status
pactl info
```

The module creates the devices through `pipewire-pulse`. Its user service
restarts when the generated configuration changes. If a session retains old
devices, log in again or restart it manually:

```console
systemctl --user restart pipewire-pulse.service
```
