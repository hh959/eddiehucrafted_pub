---
title: "AI 蓝牙排障实战：模型选择决定能否完成任务"
date: 2026-02-21
draft: false
tags: ["ai", "bluetooth", "troubleshooting", "claude", "embedded", "homelab"]
categories: ["Tech"]
description: "三个 AI 模型尝试为一块无头 ARM 开发板连接蓝牙音响。两个花了数小时重试命令和写脚本。一个用 15 分钟读对了日志，找到了根因。"
summary: "三个 AI 模型，同一个蓝牙问题。问题不是哪个模型更便宜，而是哪个模型能真正完成任务。两个不行，一个行。模型选择不是成本决策，是能力决策。"
cover: "/images/2026-02-21-ai-bluetooth-troubleshooting-cover.png"
---

三个 AI 模型。同一个蓝牙问题。只有一个解决了。

这不是一个关于 token 成本或 API 定价的故事。这是关于一个模型能不能真正完成你需要它做的事。两个模型花了数小时产出了大量输出——脚本、命令、建议——看起来像是在推进，但从未触及真正的问题。第三个模型用 15 分钟找到了根因。

选模型做系统排障，问题不是"哪个最便宜？"而是"哪个能真正搞定？"

<!--more-->

## 问题

一块 Quark-N 开发板（ARM Cortex-A7，Ubuntu 20.04，内核 4.14），板载 Realtek RTL8723B 蓝牙芯片，需要通过 A2DP 连接蓝牙音响。约束条件从一开始就很明确：

- 音响**没有配对按钮**——从主机端发起连接即可
- 同一网络上的树莓派 4 连接同一个音响**毫无问题**
- 所有操作都通过 **SSH 远程执行**——没有物理控制台

同一个音响。同一个协议。一台能连，一台不能。问题显然在 Quark 这边。

## 环境

```
Quark-N
├── CPU: 4× Cortex-A7 (armv7l)
├── OS: Ubuntu 20.04.6 LTS
├── Kernel: 4.14.111
├── BT 芯片: RTL8723B (HCI 4.0, LMP 4.0)
├── bluez: 5.53
└── PulseAudio: 13.99.1

音响: Radiooo-series1
├── 芯片: Realtek (Actions Semiconductor)
├── LMP: 4.1
└── 协议: A2DP Sink, AVRCP
```

所有排障工作由 AI Agent（OpenClaw）通过 SSH 编排，先后使用了三个不同的 Claude 模型：Codex、Haiku 和 Opus。

## 阶段 0：Codex——围绕一个从未诊断的问题写代码

Codex 模型（research agent）是第一个接手 Quark 蓝牙集成的。在大约 16 小时内（2月20日 08:57 → 2月21日 00:06），它产出了 **12 个文件**：

```
quark_voice_integration.py
quark_complete_integration.py
quark_voice_wakeup_integration.py
quark_optimize.py
quark_monitor.py
quark_audio_player.py
quark_complete_voice_system.py
quark_bluetooth_player.py
test_bluetooth.py
quark_enhanced_audio_player.py
test_bluetooth_playback.py
quark_bluetooth_setup.sh
```

每一个文件都假设 `bluetoothctl connect` 能直接工作。setup 脚本执行 `pair → trust → connect → exit`，然后打印"✅ 配对完成"——不管连接是否真的成功。Python 文件用类封装了 `subprocess.run(["bluetoothctl", ...])`，加了重试逻辑、错误处理和回退策略——但从未调查**为什么**连接会失败。

### Codex 的模式

Codex 的策略本质上是**代码导向**的：连接不工作？写一个更好的封装。构建一个 `BluetoothAudioPlayer` 类。加扫描。加重试循环。加回退音频方法。写测试脚本。写增强版。写完整集成系统。

结果：约 60KB 的 Python 代码，零诊断。

这是编码模型的盲区。它擅长生成软件，但当问题不在软件层——而在底层系统配置时——它只会在一个有裂缝的地基上越建越高。

## 阶段 1：Haiku——90 分钟的重试

Claude Haiku（4.5）接手了直接排障工作。它很快发现了两个真实问题：

1. **hci0 开机未启动** → 创建了 systemd 服务 ✅
2. **缺失固件文件 `rtl8723b_config.bin`** → 下载并部署 ✅

这些是真正的修复。但之后，事情开始跑偏。

### 死循环

表层问题解决后，核心问题依然存在：`bluetoothctl connect` 能配对成功但始终无法建立稳定连接。接下来发生了什么：

```
hcitool cc → hcitool con → 空 → 重试
bluetoothctl connect → 失败 → 重试
hcitool cc → hcitool con → 空 → 重试
bluetoothctl connect → 失败 → 换参数重试
...重复 5 次以上...
```

关键错误 `a2dp-sink profile connect failed: Protocol not available` 在这个阶段早期就出现在蓝牙日志中。但 Haiku 没有去调查"Protocol not available"在 bluez 协议栈中到底意味着什么，而是把它当作背景噪音，继续重试同样的连接命令。

### 错误的结论

在用尽了所有连接尝试后，Haiku 得出结论：

> "问题可能是硬件问题，或者音响需要手动确认配对。"

两个都不对。用户已经明确说过——不止一次——音响没有配对按钮，树莓派连它完全没问题。但 Haiku 反复建议"从音响端尝试配对"，尽管被告知这不可能。

它还往 `/etc/bluetooth/main.conf` 里塞了一堆无效配置项（`AlwaysPairable`、`NoInputNoOutput`、`JustWorksRepairing`、`Role`、`Controller`、`OffMode`），bluez 5.53 根本不认识这些键，导致后续每次读日志都多了一堆警告噪音。

### Codex 和 Haiku 的共同模式

两个模型有同样的根本局限：它们都是**行动优先**的。Codex 的行动是写代码，Haiku 的行动是跑命令。两者都不会停下来问"这到底为什么在系统层面失败？"

当 `bluetoothctl connect` 失败时，Codex 写一个带重试的 Python 封装。Haiku 换个参数再跑一遍命令。两者都没有仔细读日志，没有注意到错误不在连接尝试本身——而在底层的 IPC 通信。

## 阶段 2：Opus——15 分钟定位根因

Claude Opus（4.6）接手时已经有了之前所有尝试的完整上下文。它的第一步不是尝试连接，而是**理解错误**。

### 追踪依赖链

```
"Protocol not available"
  → 这在 bluez 里是什么意思？
    → A2DP profile handler 没有注册 endpoint
      → 谁负责注册 A2DP endpoint？
        → PulseAudio (module-bluez5-discover)
          → PulseAudio 在运行吗？在。
            → 蓝牙模块加载了吗？加载了。
              → 那为什么没注册？
```

### 第一步：检查 PulseAudio

```bash
$ pactl info | grep "Default Sink"
Default Sink: auto_null
```

PulseAudio 在运行，蓝牙模块也加载了，但 `Default Sink: auto_null`——没有真正的音频设备注册。蓝牙模块加载了但没有正常工作。

### 第二步：清理残局

删除 `main.conf` 中所有无效配置项，清理 PulseAudio 中冲突的蓝牙模块（旧版 `module-bluetooth-discover` 和 `module-bluez5-discover` 冲突），按正确顺序重启服务。

### 第三步：读对日志

这是关键洞察。`sudo journalctl -u bluetooth` 只显示 bluetoothd 的视角——它只说"Protocol not available"。真正的错误在 **PulseAudio 的用户日志**里：

```bash
$ journalctl --user
```

```
GetManagedObjects() failed: org.freedesktop.DBus.Error.AccessDenied
  sender=":1.71" (uid=1000 pid=1044
    comm="/usr/bin/pulseaudio --daemonize=no --log-target=jo")
  destination="org.bluez" (uid=0 pid=1162
    comm="/usr/lib/bluetooth/bluetoothd")
```

**PulseAudio 被 D-Bus 策略拒绝访问 bluetoothd。**

### 第四步：找到策略文件

```bash
$ cat /etc/dbus-1/system.d/bluetooth.conf
```

```xml
<policy user="root">
  <allow send_destination="org.bluez"/>
  <!-- ... root 完全访问 ... -->
</policy>

<policy at_console="true">
  <allow send_destination="org.bluez"/>
</policy>

<policy context="default">
  <deny send_destination="org.bluez"/>
</policy>
```

找到了。只有 `root` 和"在控制台"的用户才能通过 D-Bus 访问 bluez。SSH 会话不算"在控制台"。运行 PulseAudio 的 `pi` 用户（uid=1000）命中了默认的 deny 规则。

这是一个**无头部署特有的配置问题**——在桌面 Linux 上完全正常，因为有人登录在物理控制台。

### 第五步：修复

```xml
<!-- 在默认 deny 之前添加 -->
<policy user="pi">
  <allow send_destination="org.bluez"/>
</policy>
```

重启。连接。搞定。

```bash
$ pactl list sinks short
1  bluez_sink.F4_4E_FD_AB_F3_B8.a2dp_sink  module-bluez5-device.c  s16le 2ch 44100Hz  SUSPENDED

$ speaker-test -t sine -f 440 -l 1 -p 3
# 440Hz 正弦波通过音响播放 ✅
```

## 三层叠加的问题

这个问题之所以难，是因为**三个问题叠在一起**：

```
第一层：hci0 开机未启动
  → 修复：systemd 服务（Haiku 发现）

第二层：缺失 rtl8723b_config.bin 固件
  → 修复：部署配置文件（Haiku 发现）

第三层：D-Bus 策略拒绝 PulseAudio → bluetoothd 的 IPC 通信
  → 修复：添加用户策略（Opus 发现）
```

Codex 连表面都没碰到——它假设连接能工作，在一个坏掉的地基上搭了一整套应用。Haiku 快速剥掉了第一层和第二层，但碰到第三层时，无法从"试东西"切换到"理解东西"。Opus 跳过了重试循环，读错误、追依赖链，几步精准操作就找到了策略文件。

## 核心差异：能力，不是成本

很容易把模型选择当成成本优化问题。轻量模型每 token 更便宜，能用就用。但这个案例说明，成本不是系统排障的正确视角。**正确的问题是：这个模型能不能真正完成任务？**

| 模型 | 策略 | 耗时 | 结果 | 完成任务？ |
|------|------|------|------|-----------|
| **Codex** | 围绕问题写代码 | ~16 小时 | 12 个脚本，零诊断 | ❌ 否 |
| **Haiku** | 重试命令加变体 | ~90 分钟 | 找到 3 个问题中的 2 个，结论错误 | ❌ 否 |
| **Opus** | 追踪依赖链 | ~15 分钟 | 找到根因，一行修复 | ✅ 是 |

两个模型产出了数小时看起来像工作的输出，但没有解决问题。"更便宜"的选项其实一点都不便宜——它们消耗了时间、token 和人的注意力，却没有交付结果。按 token 最贵的模型在实践中反而最便宜，因为它真正完成了任务。

编码模型碰到系统问题，写更多代码。行动导向模型碰到墙，做更多同样的事。推理模型碰到墙，换策略：停止行动，开始阅读，追踪依赖链。

这不是说什么都用 Opus。初步排查——扫描明显问题、检查服务状态、部署缺失文件——轻量模型完全够用。但当同样的操作反复产生同样的结果时，问题已经从"有什么明显的错"变成了"组件之间的交互有什么微妙的错"。那就是该升级的时刻。不是因为大模型泛泛地更好，而是因为只有它能真正到达那里。

## 无头蓝牙的经验

**`at_console="true"` 是隐形杀手。** 在通过 SSH 访问的无头开发板上，没有用户算"在控制台"。如果你的 D-Bus 策略依赖这个来授权蓝牙访问，PulseAudio 会静默地无法注册 A2DP endpoint。检查 `/etc/dbus-1/system.d/bluetooth.conf`。

**读两份日志。** `sudo journalctl -u bluetooth` 显示 bluetoothd 的视角——它只说"Protocol not available"。真正的错误在 PulseAudio 的用户日志（`journalctl --user`）里。两份交叉对比才能定位。

**"Protocol not available"意味着 profile handler 没有注册。** 在 bluez 协议栈中，这永远不是最终答案。永远要追问：为什么 PulseAudio 没有注册它的 A2DP endpoint？

## 最终状态

Quark-N 现在开机自动连接蓝牙音响，A2DP 音频流正常，重启后依然工作。总共的修复：一行 D-Bus 策略、一个固件文件、一个 systemd 服务、一份清理过的 main.conf。

一个模型写了 12 个脚本。一个模型重试了 90 分钟命令。一个模型读了 15 分钟日志。日志赢了。
