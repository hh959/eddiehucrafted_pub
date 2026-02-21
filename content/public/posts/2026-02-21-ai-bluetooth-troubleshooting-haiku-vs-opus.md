---
title: "AI 蓝牙排查实战：Haiku 快速行动 vs Opus 深层分析"
date: 2026-02-21
draft: false
tags: ["bluetooth", "troubleshooting", "ai", "haiku", "opus"]
categories: ["Tech"]
description: "用 Haiku 和 Opus 两个 AI 模型排查 Quark 边缘节点蓝牙连接问题，对比它们在故障诊断中的优劣。"
summary: "用两个不同的 AI 模型排查蓝牙连接问题，对比 Haiku 的快速行动式排查和 Opus 的深层依赖链分析。"
cover: "/images/ai-bluetooth-troubleshooting.jpg"
---

用两个不同的 AI 模型排查蓝牙连接问题，对比 Haiku 的快速行动式排查和 Opus 的深层依赖链分析。

<!--more-->

---

## 背景

Quark 边缘节点（树莓派衍生品，armv7l）需要连接蓝牙音响播放音频。初期尝试失败，出现 `Protocol not available` 错误。这次用两个不同的 AI 模型来排查，看看它们各自的优势。

## 问题症状

- `bluetoothctl` 能扫描到设备，但连接失败
- `pactl list` 看不到 A2DP sink
- 日志显示 `Protocol not available`
- PulseAudio 未注册 A2DP endpoint

## Haiku 的方法：快速行动式排查

Haiku（轻量模型）的特点是**快速迭代、直接尝试**。

### 第一轮：系统检查

Haiku 建议：
1. 检查 bluetoothd 是否运行
2. 查看 `journalctl --user` 的 PulseAudio 日志
3. 验证 D-Bus 权限

**执行结果：** 发现 D-Bus policy 拒绝非 root 用户访问 bluez。

### 第二轮：快速修复

Haiku 直接给出修复步骤：
- 添加 D-Bus policy 允许 `pi` 用户访问 bluez
- 重启 bluetoothd
- 测试连接

**执行结果：** 连接成功！A2DP 工作。

**Haiku 的优势：**
- ✅ 快速定位问题（3-4 轮对话）
- ✅ 给出可直接执行的命令
- ✅ 适合已知问题类型的排查

**Haiku 的局限：**
- ❌ 不深入解释为什么会出现这个问题
- ❌ 对复杂依赖链的理解有限
- ❌ 容易遗漏根本原因

## Opus 的方法：深层依赖链分析

Opus（高能模型）的特点是**系统思考、全局视角**。

### 第一轮：问题分解

Opus 问：
- 这是 headless 部署吗？
- 用的是什么蓝牙芯片？
- PulseAudio 和 bluez 的版本？
- 之前在其他系统上成功过吗？

**收获：** 意识到 headless 部署的 D-Bus 权限问题是**系统级设计缺陷**，不只是配置问题。

### 第二轮：根本原因分析

Opus 指出：
- D-Bus 的 `at_console` 权限在 SSH 会话中无效
- 需要显式添加用户 policy，而不是依赖系统默认
- A2DP endpoint 注册失败的根本原因是 PulseAudio 无法访问 bluez

**收获：** 理解了为什么 Haiku 的快速修复有效——它解决了权限问题，而权限问题是整个链条的瓶颈。

### 第三轮：预防性建议

Opus 建议：
- 为 headless 部署编写标准化的 D-Bus policy 模板
- 记录这个问题，避免在其他边缘节点重复
- 考虑用 systemd user service 而不是依赖 D-Bus 权限

**收获：** 不仅解决了当前问题，还为未来的部署提供了架构指导。

**Opus 的优势：**
- ✅ 深入理解问题的根本原因
- ✅ 提供系统级的解决方案
- ✅ 预见潜在的后续问题
- ✅ 适合复杂、跨域的故障诊断

**Opus 的局限：**
- ❌ 对话轮数多（5-7 轮才能完全理解）
- ❌ 有时过度分析，延迟快速修复
- ❌ 成本更高（token 消耗多）

## 对比总结

| 维度 | Haiku | Opus |
|------|-------|------|
| **速度** | ⚡ 快（3-4 轮） | 🐢 慢（5-7 轮） |
| **直接性** | ✅ 给命令 | ❌ 先分析 |
| **根本原因** | ❌ 浅 | ✅ 深 |
| **预防性** | ❌ 无 | ✅ 强 |
| **成本** | 💰 低 | 💸 高 |
| **适用场景** | 已知问题类型 | 复杂/新问题 |

## 最佳实践

**用 Haiku 当：**
- 问题类型已知（网络、权限、配置）
- 需要快速恢复服务
- 时间紧张

**用 Opus 当：**
- 问题复杂、跨多个系统
- 需要理解根本原因
- 要为未来的部署提供架构指导
- 有重复出现的风险

**混合策略：**
1. 用 Haiku 快速诊断和临时修复
2. 用 Opus 分析根本原因和长期方案
3. 记录到 MEMORY.md，避免重复

## 后续

这次蓝牙排查的完整记录已保存到 `memory/quark-bluetooth-troubleshooting.md`，包括：
- 完整的日志输出
- 每一步的命令和结果
- D-Bus policy 配置文件
- 系统架构图

下次遇到类似问题，可以直接参考这个文档。

---

**关键收获：** AI 模型各有所长。快速问题用轻量模型，复杂问题用高能模型。组合使用效果最佳。
