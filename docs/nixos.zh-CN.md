# NixOS 与 PipeWire

[English](nixos.md) | [简体中文](nixos.zh-CN.md) |
[返回项目首页](../README.zh-CN.md)

本手册说明如何通过 NixOS 模块安装 RVC、启动本机 WebUI 服务，以及创建供语音
软件使用的 PipeWire 虚拟麦克风。

## 添加模块

先让 rvc.nix 与主机共用同一个 nixpkgs：

```nix
{
  inputs.rvc-nix = {
    url = "github:Ruixi-rebirth/rvc.nix";
    inputs.nixpkgs.follows = "nixpkgs";
  };
}
```

再把模块和配置加入目标主机的 `modules` 列表：

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

`nixosModules.default` 与示例中的 `nixosModules.rvc` 是同一个模块；前者是 flake
惯用入口，后者便于辨认。

## 选择一个软件包

下表中的名称均位于 `rvc-nix.packages.x86_64-linux`。先按硬件选择一行；只有
需要训练资源或 PyMSS 权重时才选择第三列。

| 硬件 | 推理与实时变声 | 加入训练和 PyMSS 资源 |
| --- | --- | --- |
| CPU、AMD GPU 或 Intel GPU | `cpu`（默认） | `cpu-all` |
| RTX 50 系以前的 NVIDIA GPU | `cuda118` | `cuda118-all` |
| RTX 50 系列 | `cuda128` | `cuda128-all` |

这是模块中唯一的软件包选择。所选软件包会安装到系统环境；启用 WebUI 服务后，
服务也会从同一个软件包启动 `rvc-web`。

`cpu`、`cuda118` 和 `cuda128` 已经包含文件变声和 Realtime GUI 使用的 HuBERT
与 RMVPE。`-all` 在此基础上加入 RVC v1/v2 训练预权重、静音样本和 5 个 PyMSS
权重。两种软件包都不提供用户自己的目标音色 `.pth`。

`models-*` 输出只有模型文件，没有 RVC 命令，不能直接赋给
`programs.rvc.package`。模型列表和自定义音色的组合方式见
[使用手册](usage.zh-CN.md)。

## 模块选项

| 选项 | 默认值 | 用途 |
| --- | --- | --- |
| `programs.rvc.enable` | `false` | 安装 RVC |
| `programs.rvc.package` | `packages.cpu` | RVC 与 WebUI 共用的软件包 |
| `programs.rvc.chinese.enable` | `false` | 使用简体中文界面 |
| `programs.rvc.webui.enable` | `false` | 图形登录后启动 WebUI |
| `programs.rvc.webui.host` | `127.0.0.1` | WebUI 监听地址 |
| `programs.rvc.webui.port` | `7865` | WebUI 起始端口 |
| `programs.rvc.virtualMic.enable` | `false` | 创建虚拟输出和麦克风 |
| `programs.rvc.virtualMic.echoCancellation.enable` | `false` | 创建回声消除输入 |

只安装 RVC 不会修改音频服务。只有启用 `virtualMic.enable` 后，模块才会启用
PipeWire、WirePlumber、ALSA、PulseAudio 兼容层和 rtkit。

## WebUI 用户服务

以下配置会在每次图形登录后启动 `rvc-web --noautoopen`：

```nix
programs.rvc.webui = {
  enable = true;
  host = "127.0.0.1";
  port = 7865;
};
```

如果 `programs.rvc.package` 是 `cuda118`，服务就使用 CUDA 11.8 和推理模型；如果
是 `cuda118-all`，同一个服务还可以直接使用打包的训练和 PyMSS 资源。

查看服务状态和日志：

```console
systemctl --user status rvc-webui.service
journalctl --user -u rvc-webui.service -f
```

起始端口被占用时，上游 WebUI 会尝试下一个可用端口。模块不会自动打开防火墙。
WebUI 能访问文件系统并控制训练，只适合可信的本机用户；即使反向代理提供身份
验证，也不应将它开放给不受信任的用户或公网。完整边界见
[安全说明](../SECURITY.md)。

## 创建虚拟麦克风

启用 PipeWire 集成：

```nix
programs.rvc.virtualMic.enable = true;
```

模块会创建两个设备：

- `RVC-Output`：Realtime GUI 写入变声音频的虚拟输出。
- `RVC-Microphone`：`RVC-Output` 的监听源，供语音软件作为麦克风读取。

音频链路是：

```text
PipeWire 默认输入 -> Realtime GUI -> RVC-Output
                                       |
                                       +-> RVC-Microphone -> 语音软件
```

模块不会选择物理麦克风，也不会修改系统默认输入或输出。Realtime GUI 中的
`pipewire` 输入会跟随 PipeWire 当前的默认输入源，因此应先在桌面声音设置中选择
真正使用的物理麦克风。

## Realtime GUI 设备选择

启动 Realtime GUI：

```console
rvc-realtime
```

在 Realtime GUI 中选择：

| 设置 | 选择 |
| --- | --- |
| 设备类型 | `ALSA` |
| 输入 | `pipewire` |
| 输出 | `RVC-Output` |

不要直接选择 `PCH`、`HDA`、`HDMI` 等硬件端点；它们可能被 PipeWire 占用，或
根本不支持全双工流。`OSS` 在没有可用 OSS 设备时也不会提供输入或输出。使用上表
中的稳定 PipeWire/ALSA 入口可以避免这些设备打开错误。

然后在 QQ、Discord、游戏或直播软件中选择：

| 设置 | 选择 |
| --- | --- |
| 输入（麦克风） | `RVC-Microphone` |
| 输出（扬声器） | 实际使用的耳机或扬声器 |

两组设置承担不同角色：Realtime GUI 从真实麦克风读取声音并写入
`RVC-Output`；语音软件从 `RVC-Microphone` 读取变声结果，但仍把播放声音发送到
真实耳机或扬声器。

`RVC-Microphone` 只包含 RVC 写入的声音。Realtime GUI 没有运行或没有输出时，
它就是静音的。PipeWire 会协商采样率、声道数和声道映射；模块不会强制音频格式，
也不会自动把变声结果播放给本机用户。

启用虚拟麦克风时，模块会把 PulseAudio 兼容层对未指定录音分片的默认值设为
`1024/48000`（约 21 ms）。PipeWire 的原始默认值是 2 秒，部分语音软件会直接
使用它，从而让变声声音延迟数秒。应用明确指定自己的录音分片时不受此默认值影响；
降低默认缓冲会略微增加音频服务的处理频率。重建后已经打开的语音通话需要重新建立
录音流，才能使用新的缓冲设置。

## 使用扬声器时消除回声

物理麦克风收到扬声器播放的声音后，声音会再次进入 RVC，形成回声或反馈环路。
Realtime GUI 中的输入、输出降噪并不是声学回声消除。耳机仍是延迟最低、效果最
稳定的方案。

必须使用物理扬声器时，可以启用 PipeWire 的 WebRTC 回声消除器：

```nix
programs.rvc.virtualMic = {
  enable = true;
  echoCancellation.enable = true;
};
```

启用后会出现 `RVC-Echo-Cancelled-Input`。它会比较 PipeWire 当前默认麦克风与
默认输出的监听信号，不需要硬编码 PCH 等物理 ALSA 名称。先在桌面声音设置中选好
默认麦克风和扬声器，再按用途配置 Realtime GUI：

| 用途 | Realtime GUI 输入 | Realtime GUI 输出 |
| --- | --- | --- |
| 语音软件 | `RVC-Echo-Cancelled-Input` | `RVC-Output` |
| 本机扬声器试听 | `RVC-Echo-Cancelled-Input` | `pipewire` |

用于语音软件时，软件的麦克风仍选择 `RVC-Microphone`，播放输出选择物理扬声器。
本机试听时，`pipewire` 输出会把变声结果播放到扬声器，但不会同时写入
`RVC-Microphone`。

回声消除只能去除默认输出监听信号中实际出现的声音；被路由到其他输出设备的程序
不在参考链路中。AEC 也会增加处理量，而且无法完全补偿所有房间、音量和设备摆放，
所以保持可选而不会默认启用。

## 检查 PipeWire 设备

确认虚拟设备存在：

```console
pactl list short sinks | grep rvc_output
pactl list short sources | grep rvc_mic
```

查看默认输入和完整音频图：

```console
wpctl status
pactl info
```

模块通过 `pipewire-pulse` 创建虚拟设备。生成的配置发生变化时，其用户服务会重启。
如果当前会话仍保留旧设备，可以重新登录或手动运行：

```console
systemctl --user restart pipewire-pulse.service
```
