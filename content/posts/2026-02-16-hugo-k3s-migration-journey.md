---
title: "从单机到集群：Hugo 博客的 K3s 迁移之旅"
date: 2026-02-16
draft: false
tags: ["kubernetes", "k3s", "hugo", "infrastructure", "homelab"]
categories: ["技术", "运维"]
description: "如何将 Hugo 博客从本地服务器迁移到 K3s 集群，以及这样做的收益"
summary: "一次从单机脚本到 K3s 声明式运维的迁移复盘：架构差异、关键决策、踩坑与收益。"
cover: "/images/hugo-cms.jpg"
---

## 前言

两周前，我的博客还跑在一台 ARM 服务器（reComputer 2011）上，通过 systemd 服务直接管理。最近，我把它迁移到了自建的 K3s 集群。这不仅仅是一次"搬家"，更是一次架构思维的升级。

这篇文章记录了迁移的全过程，以及为什么这样的改变值得做。

<!--more-->

---

## 第一部分：旧架构的痛点

### 单机管理的问题

**旧架构长这样：**
- Hugo 站点代码存在 Git 仓库
- 构建脚本在 master-node 上运行（crontab 每 5 分钟执行一次）
- 生成的静态文件存在 `/opt/blog-public`
- Nginx 直接从本地目录提供服务
- Cloudflare Tunnel 指向本地 Nginx

**看起来简单，但问题不少：**

1. **路径耦合** — 构建脚本、存储路径、服务配置都紧密绑定在一台机器上
   - 如果要迁移到另一台服务器，需要重新配置所有路径
   - 权限管理混乱（用户 crontab vs 系统服务）

2. **资源竞争** — master-node 既要跑 K3s control plane，又要跑 Hugo 构建
   - 构建时 CPU 峰值会影响集群管理
   - 没有资源隔离，难以监控

3. **扩展性差** — 想要高可用或负载均衡？很难
   - 单点故障风险
   - 无法轻松添加副本或故障转移

4. **运维复杂度** — 多套管理工具
   - systemd 管理 Nginx
   - crontab 管理构建
   - kubectl 管理 K3s
   - 没有统一的观测和控制面

---

## 第二部分：新架构设计

### 迁移目标

把 Hugo 完全纳入 K3s 管理：

```
旧架构：
master-node (systemd + crontab)
  ├─ Hugo build script (crontab)
  ├─ Static files (/opt/blog-public)
  └─ Nginx service (systemd)

新架构：
K3s Cluster
  └─ blog namespace
      ├─ Deployment: hugo-blog-k3s (nginx)
      ├─ PVC: hugo-public-pvc (hostPath)
      ├─ CronJob: hugo-build-sync (构建脚本)
      └─ Service: hugo-blog-k3s (ClusterIP)
```

### 关键决策

**1. 持久化存储用 hostPath**
- 简单快速，适合小型 homelab
- 路径：`/tmp/eddiehucrafted_com/public`（master-node 本地）
- 生产环境可升级到 NFS 或块存储

**2. 构建用 K3s CronJob**
- 替代 master-node 的 crontab
- 统一的日志和监控
- 可以轻松调整时间表或资源限制

**3. 服务用 Deployment + Service**
- Nginx Pod 提供静态文件
- 可以轻松扩展副本数
- 通过 Service 暴露给 Cloudflare Tunnel

**4. 保留 Cloudflare Tunnel**
- 只改变后端指向（从本地 Nginx → K3s Service）
- 公网 URL 不变

---

## 第三部分：迁移步骤

### 1. 数据准备

```bash
# 在 master-node 上
cp -r /opt/blog-public /tmp/eddiehucrafted_com/public
```

### 2. 创建 K3s 资源

**PV 和 PVC：**
```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: hugo-public-pv
spec:
  capacity:
    storage: 10Gi
  accessModes:
    - ReadWriteOnce
  hostPath:
    path: /tmp/eddiehucrafted_com/public
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - master-node

---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hugo-public-pvc
  namespace: blog
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  volumeName: hugo-public-pv
```

**Deployment（Nginx）：**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hugo-blog-k3s
  namespace: blog
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hugo-blog
  template:
    metadata:
      labels:
        app: hugo-blog
    spec:
      containers:
      - name: nginx
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: hugo-public
          mountPath: /usr/share/nginx/html
      volumes:
      - name: hugo-public
        persistentVolumeClaim:
          claimName: hugo-public-pvc
```

**Service：**
```yaml
apiVersion: v1
kind: Service
metadata:
  name: hugo-blog-k3s
  namespace: blog
spec:
  type: ClusterIP
  selector:
    app: hugo-blog
  ports:
  - port: 80
    targetPort: 80
```

### 3. 创建构建 CronJob

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: hugo-build-sync
  namespace: blog
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: hugo-builder
          containers:
          - name: builder
            image: alpine:latest
            command:
            - /bin/sh
            - -c
            - |
              apk add --no-cache git hugo
              cd /tmp/build
              git clone https://github.com/[user]/[blog-repo].git .
              hugo -d /output
            volumeMounts:
            - name: output
              mountPath: /output
          volumes:
          - name: output
            persistentVolumeClaim:
              claimName: hugo-public-pvc
          restartPolicy: OnFailure
```

### 4. 更新 Cloudflare Tunnel

```bash
# 获取 K3s Service 的 ClusterIP
kubectl -n blog get svc hugo-blog-k3s
# 输出：10.43.255.202

# 更新 cloudflared 配置
# blog.eddiehucrafted.com.au → http://10.43.255.202:80

systemctl restart cloudflared
```

### 5. 清理旧资源

```bash
# 停止 master-node 上的 Nginx
systemctl stop nginx
systemctl disable nginx

# 删除旧的构建脚本 crontab 条目
crontab -e

# 删除旧的静态文件目录
rm -rf /opt/blog-public
```

---

## 第四部分：迁移的收益

### 1. 架构清晰

- **单一控制面** — 所有资源都通过 kubectl 管理
- **声明式配置** — YAML 文件即文档，版本控制友好
- **可重现** — 新增节点时，直接应用 YAML 即可

### 2. 运维简化

**旧方式查看日志：**
```bash
# 需要 SSH 到 master-node
ssh master-node
tail -f /var/log/syslog | grep hugo
```

**新方式查看日志：**
```bash
# 直接用 kubectl
kubectl -n blog logs -f deployment/hugo-blog-k3s
kubectl -n blog logs job/hugo-build-sync-xxxxx
```

### 3. 资源隔离

- Hugo 构建不再争抢 control plane 的 CPU
- 可以为 CronJob 设置资源限制
- 便于监控和告警

### 4. 扩展性

想要高可用？改一行配置：
```yaml
replicas: 3  # 从 1 改成 3
```

想要更频繁的构建？改一行：
```yaml
schedule: "*/2 * * * *"  # 从 5 分钟改成 2 分钟
```

### 5. 故障恢复

- Pod 崩溃时，K3s 自动重启
- 节点故障时，可以迁移到其他节点
- 无需手动干预

---

## 第五部分：迁移中的坑

### 1. 权限问题

CronJob 需要访问 PVC，确保 ServiceAccount 有权限：
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: hugo-builder
  namespace: blog

---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: hugo-builder
  namespace: blog
rules:
- apiGroups: [""]
  resources: ["persistentvolumeclaims"]
  verbs: ["get", "list"]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: hugo-builder
  namespace: blog
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: hugo-builder
subjects:
- kind: ServiceAccount
  name: hugo-builder
  namespace: blog
```

### 2. 镜像大小

第一次构建时，alpine + git + hugo 的镜像会比较大。可以预先 pull：
```bash
kubectl -n blog run debug --image=alpine:latest -- sleep 3600
# 等待 Pod 就绪，镜像会被 pull 到节点
```

### 3. 网络延迟

Git clone 可能很慢。考虑：
- 使用本地 Git 镜像
- 或者在 CronJob 中缓存代码

---

## 第六部分：后续优化

### 短期

- [ ] 添加构建失败告警
- [ ] 监控 PVC 存储使用
- [ ] 定期备份静态文件

### 中期

- [ ] 将 Hugo 主题和配置也纳入 K3s ConfigMap
- [ ] 实现蓝绿部署（新旧版本并行）
- [ ] 添加健康检查（curl 首页验证）

### 长期

- [ ] 升级到 NFS 存储（支持多节点）
- [ ] 实现 CDN 缓存策略
- [ ] 集成 CI/CD 流水线（GitHub Actions → K3s）

---

## 总结

从单机到集群，Hugo 博客的迁移看似简单，但背后反映的是运维思维的升级：

- **从命令式到声明式** — 从手动配置到 YAML 定义
- **从单点到分布式** — 从单机依赖到集群管理
- **从被动到主动** — 从故障排查到主动监控

这次迁移花了大约 2 小时，但带来的长期收益远超这个投入。如果你也在运维小型 homelab，这个模式值得参考。

---

## 参考资源

- [K3s 官方文档](https://docs.k3s.io/)
- [Kubernetes PersistentVolumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/)
- [Hugo 官方文档](https://gohugo.io/documentation/)
- [Cloudflare Tunnel 文档](https://developers.cloudflare.com/cloudflare-one/connections/connect-apps/)

---

**下一步？** 如果你有类似的服务也想迁移到 K3s，欢迎留言讨论。
