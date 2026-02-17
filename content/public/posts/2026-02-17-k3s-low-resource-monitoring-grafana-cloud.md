---
title: "Day 4: 低资源 K3s 监控实战：日志与指标上送 Grafana Cloud"
date: 2026-02-17
draft: false
tags: ["k3s", "kubernetes", "grafana", "loki", "prometheus", "monitoring", "homelab"]
categories: ["Tech"]
description: "用最小组件把 K3s 的关键日志与核心指标接入 Grafana Cloud，兼顾可观测性与资源控制。"
summary: "这篇记录 Day 4 的监控改造：为什么选 Grafana Cloud、如何连接日志与指标、看板查询与当前方案局限。"
cover: "/images/day4-cover-k8s-grafana-loki-prometheus.jpg"
---

今天这篇是 Day 4 复盘：我把 K3s 集群的日志与系统指标，做成了一个“低资源、可维护、可追踪”的监控方案。

核心目标：
- 指标只看 CPU / Memory / Disk
- 日志只看关键业务命名空间
- 本地少存储，把持久化压力交给 Cloud

<!--more-->

## 为什么选 Grafana Cloud，而不是本地自建全套

先说结论：**不是云更高级，而是更适合当前规模。**

我这次选 Grafana Cloud，主要是因为：

1. **省本地资源**
   - Loki/Prometheus 本地长期存储会吃磁盘和内存
   - 我当前更希望把资源留给业务应用

2. **部署复杂度低**
   - 本地只保留采集组件（Promtail、Node Exporter、Prometheus）
   - 展示与存储在 Cloud，维护面更小

3. **免费层可快速起步**
   - 对中小集群来说，先跑通可观测性闭环比一步到位更重要

---

## 设计目标：够用优先，而不是全家桶

这次方案聚焦四件事：

1. **低资源占用**：采样周期 60s，减少本地组件数量
2. **低存储压力**：日志与指标上送 Grafana Cloud，本地不做长期留存
3. **低复杂度**：只采关键范围，不做全集群无差别采集
4. **可维护**：全部 YAML 化，并进入 Git 追踪

---

## K3s 安装了哪些应用

### 日志链路（Logs）
- `promtail`（DaemonSet）
  - **作用**：负责从节点读取容器日志（stdout/stderr），加上 namespace / pod / app 等标签后，推送到 Loki。在 K8s 里通常用 DaemonSet 部署，确保每个节点都有采集能力。
  - **为什么用 DaemonSet**：每个节点都有一份采集器，天然覆盖全节点日志源
- 采集范围（按业务收敛）：
  - `ehc` 下 `hugo`、`mkdocs`
  - `sws` 业务日志

### 指标链路（Metrics）
- `node-exporter`（DaemonSet）
  - **作用**：负责暴露主机级指标，如 CPU、内存、磁盘、负载、网络等。这是 Prometheus 生态里最常用的节点监控组件，轻量且标准化。
  - **特点**：轻量、标准化，适合做底层资源健康监控
- `prometheus`（Deployment，remote_write 模式）
  - **作用**：负责按周期抓取指标（scrape）、存储时序数据并支持 PromQL 查询。在本方案中使用的是 Prometheus remote_write 模式：保留抓取与转发能力，把长期存储交给 Grafana Cloud，降低本地资源占用。
  - **价值**：减少本地存储压力，保留 Prometheus 生态查询能力

### Cloud 端
- Grafana Cloud Loki：接收日志
- Grafana Cloud Prometheus：接收 metrics
- Grafana Dashboard：统一展示

### 这些工具在工业场景的典型用法

1. **边缘工厂/门店集群**
   - 本地节点资源有限，通常不适合全量本地监控存储
   - 采用“边缘轻采集 + 云端集中观测”更易维护

2. **多站点分布式部署**
   - 每个站点只跑 Promtail / Node Exporter / Prometheus（remote_write）
   - 云端做统一看板与跨站点对比，减少现场运维成本

3. **运维值班与故障回溯**
   - 节点资源指标用于提前识别容量风险
   - 业务日志用于快速定位发布异常、接口错误或依赖故障

4. **中小团队的 MVP 监控建设**
   - 先把“核心指标 + 关键日志”跑通
   - 后续再逐步加告警、SLO、长期留存与成本优化

---

## Grafana Cloud 配置与连接要点

配置过程很直接：

1. 创建最小权限 token（logs/metrics write）
2. 在 Promtail 配置 logs endpoint + username + token
3. 在 Prometheus Agent 配置 metrics endpoint + username + token
4. 验证链路：
   - Logs：按 namespace/app 查询
   - Metrics：`up{job="node-exporter"}` 查询

> 安全原则：token 不入库，YAML 使用占位符，真实密钥走 Secret 注入。

---

## 日志与指标是否真的上云了？

### Logs 验证

![Error Logs (ehc)](/images/day4-ehc-error-logs.jpg)
*图 1：Error Logs (ehc) 为 0，当前窗口未出现错误日志。*

![Logs Volume (ehc)](/images/day4-ehc-logs-volume.jpg)
*图 2：Logs Volume (ehc) 持续有数据，说明日志采集与上送链路正常。*

### Metrics 验证

![Node CPU 使用率](/images/day4-node-cpu-usage.jpg)
*图 3：Node CPU 使用率趋势。*

![Node Memory 使用率](/images/day4-node-memory-usage.jpg)
*图 4：Node Memory 使用率趋势。*

![Node Disk 使用率](/images/day4-node-disk-usage.jpg)
*图 5：Node Disk 使用率趋势。*

![Node Load Core (1m)](/images/day4-node-load-core.jpg)
*图 6：Node Load Core (1m) 趋势（注意 load 不是百分比）。*

---

## Monitor Board 设计（最小可用）

我最终保留的面板：
- Node CPU 使用率（%）
- Node Memory 使用率（%）
- Node Disk 使用率（%）
- Node Load (1m)
- Logs Volume（ehc / sws）
- Error Logs（ehc / sws）

这样做的好处：
- 一眼看到系统健康度
- 一眼看到业务日志是否异常
- 面板数量少，维护成本低

---

## 当前方案的局限性

这套方案够轻，但不是没有代价：

1. **免费计划有保留周期与额度限制**
   - 日志保留天数有限
   - 超过免费额度后需要升级或收敛采集

2. **日志量大时会增加网络上行压力**
   - 尤其在高并发或 debug 日志较多时明显
   - 需要持续做日志降噪与采样控制

3. **Cloud 依赖增强**
   - 外网异常时，Cloud 可视化会受影响
   - 本地需要保留最小排障能力（kubectl logs 等）



## 含常用查询

### 1) 固化 Dashboard 与查询

**CPU 使用率（%）**
```promql
100 - (avg by (node) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Memory 使用率（%）**
```promql
(1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)) * 100
```

**Disk 使用率（%）**
```promql
100 * (1 - (node_filesystem_avail_bytes{mountpoint="/",fstype!=""} / node_filesystem_size_bytes{mountpoint="/",fstype!=""}))
```

**Load1**
```promql
node_load1
```

**ehc 错误日志计数（5m）**
```logql
sum(count_over_time({namespace="ehc"} |= "error" [5m]))
```

**sws 日志量（5m）**
```logql
sum(count_over_time({namespace="sws"}[5m]))
```

### 2) 增加基础告警
- CPU/Mem/Disk 阈值告警
- Logs error 突增告警

### 3) 继续收敛日志噪声
- 过滤健康检查
- 控制 debug 日志比例

如果你也在用小型 K3s 集群，这套“轻采集 + Cloud 托管”的组合，值得先从 MVP 跑起来。