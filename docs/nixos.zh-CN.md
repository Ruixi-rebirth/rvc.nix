# NixOS 与 PipeWire

[English](nixos.md) | [简体中文](nixos.zh-CN.md) |
[返回项目首页](../README.zh-CN.md)

本手册说明 rvc.nix 的 NixOS 模块、WebUI 用户服务和 PipeWire 虚拟麦克风。

## 配置模块

先添加本仓库的 flake 输入：

```nix
{
  inputs.rvc-nix.url = "github:Ruixi-rebirth/rvc.nix";
}
```

再在目标主机 `nixosSystem` 的 `modules` 列表中加入模块和配置：

```nix
modules = [
  rvc-nix.nixosModules.rvc
  {
    programs.rvc = {
      enable = true;
      package = rvc-nix.packages.x86_64-linux.cuda118-with-models;
      chinese.enable = true;
      virtualMic.enable = true;
    };
  }
];
```

示例选择 CUDA 11.8。请按目标机器修改 `package`：

| 硬件 | `programs.rvc.package` |
| --- | --- |
| CPU、AMD GPU 或 Intel GPU | `rvc-nix.packages.x86_64-linux.cpu-with-models` |
| RTX 50 系以前的 NVIDIA GPU | `rvc-nix.packages.x86_64-linux.cuda118-with-models` |
| RTX 50 系列 | `rvc-nix.packages.x86_64-linux.cuda128-with-models` |

`programs.rvc.enable = true` 始终会安装所选 RVC 软件包。默认软件包是带 HuBERT
和 RMVPE 的 CPU 版；CUDA 包必须通过 `programs.rvc.package` 显式选择。模块
不会提供目标音色的 `.pth` 语音模型，仍需参照[使用手册](usage.zh-CN.md)放入
用户数据目录。

## 模块选项

| 选项 | 默认值 | 用途 |
| --- | --- | --- |
| `programs.rvc.enable` | `false` | 安装 `programs.rvc.package` |
| `programs.rvc.package` | CPU + HuBERT/RMVPE | 选择 CPU 或 CUDA 软件包 |
| `programs.rvc.chinese.enable` | `false` | 使用简体中文界面 |
| `programs.rvc.webui.enable` | `false` | 图形登录后启动 WebUI |
| `programs.rvc.webui.host` | `127.0.0.1` | WebUI 监听地址 |
| `programs.rvc.webui.port` | `7865` | WebUI 起始端口 |
| `programs.rvc.virtualMic.enable` | `false` | 创建虚拟输出和虚拟麦克风 |

`programs.rvc.virtualMic.echoCancellation.enable` 同样默认为 `false`，用于在
使用物理扬声器时创建 WebRTC 回声消除输入。

只有启用 `virtualMic.enable` 后，模块才会启用 PipeWire、WirePlumber、ALSA、
PulseAudio 兼容层和 rtkit。只安装 RVC 不会改变已有的音频服务设置。

## 虚拟麦克风的音频链路

模块创建两个设备：

- `RVC-Output`：Realtime GUI 写入变声音频的虚拟输出。
- `RVC-Microphone`：`RVC-Output` 的监听源，供语音应用作为麦克风读取。

完整链路是：

```text
PipeWire 默认输入 -> Realtime GUI -> RVC-Output
                                       |
                                       +-> RVC-Microphone -> QQ/Discord/游戏
```

模块不会选择物理麦克风，也不会修改系统默认输入或输出。Realtime GUI 中的
`pipewire` 输入会跟随 PipeWire 当前的默认输入源，因此物理麦克风应在桌面环境
的声音设置中选择。

## Realtime GUI 设备设置

启用虚拟麦克风后，启动 Realtime GUI：

```console
rvc-realtime
```

在 Realtime GUI 中选择：

| 设置 | 选择 |
| --- | --- |
| 设备类型 | `ALSA` |
| 输入 | `pipewire` |
| 输出 | `RVC-Output` |

然后在 QQ、Discord、游戏或直播软件中选择：

| 设置 | 选择 |
| --- | --- |
| 输入（麦克风） | `RVC-Microphone` |
| 输出（扬声器） | 实际使用的耳机或扬声器 |

这两组设备承担不同角色，不能对调：

- Realtime GUI 从真实麦克风读取声音，并写入 `RVC-Output`。
- 语音应用从 `RVC-Microphone` 读取已经变声的声音。
- 语音应用的播放输出仍然是用户实际使用的耳机或扬声器。

`RVC-Microphone` 只反映 RVC 写入的音频。Realtime GUI 没有运行或没有输出时，
它保持静音。采样率、声道数和声道映射由 PipeWire 协商，模块不会强行固定音频
格式，也不会自动把变声后的声音播放给本机用户。

## 不用耳机时消除声学回声

物理麦克风收到扬声器播放的声音后，这部分声音会再次进入 RVC，形成回声或反馈
环路。Realtime GUI 中的输入降噪和输出降噪并不是声学回声消除。耳机仍是延迟
最低、效果最稳定的方案。

需要使用物理扬声器时，可以启用 PipeWire 的 WebRTC 回声消除器：

```nix
programs.rvc.virtualMic = {
  enable = true;
  echoCancellation.enable = true;
};
```

启用后会出现 `RVC-Echo-Cancelled-Input`。它会比较 PipeWire 当前默认麦克风和
当前默认输出的监听信号，因此不需要硬编码 PCH 等物理 ALSA 设备名。先在桌面声音
设置中选好默认麦克风和扬声器，再按用途选择 RVC 设备：

| 用途 | Realtime GUI 输入 | Realtime GUI 输出 |
| --- | --- | --- |
| 语音软件 | `RVC-Echo-Cancelled-Input` | `RVC-Output` |
| 本机扬声器试听 | `RVC-Echo-Cancelled-Input` | `pipewire` |

用于语音软件时，软件的麦克风仍选择 `RVC-Microphone`，播放输出选择物理扬声器。
本机试听时，通用 `pipewire` 输出会把变声结果播放到扬声器，但不会同时写入
`RVC-Microphone`。

回声消除只能去除默认输出监听信号中实际出现的声音；如果某个程序被路由到其他
输出设备，它就不在回声参考链路中。AEC 还会增加少量处理，并且无法完全补偿所有
房间声学、音量、麦克风和扬声器摆放情况，因此该功能保持可选，不会默认启用。

## WebUI 用户服务

设置以下选项后，模块会在每次图形登录时启动 `rvc-web --noautoopen`：

```nix
programs.rvc.webui = {
  enable = true;
  host = "127.0.0.1";
  port = 7865;
};
```

查看服务状态和日志：

```console
systemctl --user status rvc-webui.service
journalctl --user -u rvc-webui.service -f
```

如果起始端口被占用，上游 WebUI 会尝试下一个可用端口。模块不会自动打开
防火墙。WebUI 能访问文件系统并控制训练，只适合可信的本机用户；即使反向代理
提供身份验证，也不应把它开放给不受信任的用户或公网。详细安全边界见
[SECURITY.md](../SECURITY.md)。

## 检查 PipeWire 设备

确认两个虚拟设备存在：

```console
pactl list short sinks | grep rvc_output
pactl list short sources | grep rvc_mic
```

查看当前默认输入和音频节点：

```console
wpctl status
pactl info
```

模块通过 `pipewire-pulse` 创建虚拟设备。生成的配置变化时，
`pipewire-pulse.service` 会重启；如果当前会话仍保留旧设备，可重新登录或手动
重启：

```console
systemctl --user restart pipewire-pulse.service
```
