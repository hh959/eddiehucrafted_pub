---
title: "Day 2: From InitContainer Runtime Build to Stable Git Pull + Build"
date: 2026-02-15
slug: "from-initcontainer-to-stable-git-pull-build"
draft: false
tags: ["hugo", "k3s", "ops", "automation"]
categories: ["engineering-notes"]
description: "How I moved my blog delivery from fragile runtime init builds to a stable pull-build-serve model."
---

Today I adjusted the blog runtime strategy to improve stability and reduce deployment friction.

![Day 1 setup snapshot](/static/public/images/k3s-logo.png)
## What changed

I moved away from a Kubernetes init-container-heavy runtime build pattern and switched to a simpler model:

- Git-managed source repository
- periodic `git pull` + `hugo build`
- local static file service via systemd
- cloud tunnel route to local service

In short, the blog now follows the same stable operating pattern as my documentation site.

## Why I changed it

The init-container approach worked initially, but became fragile when theme and Hugo runtime requirements changed.

Typical failure points included:

- image/tag availability mismatches
- theme/version compatibility differences
- rollout waiting due to failed new pods while old pods were still serving

I wanted a deterministic path with fewer moving parts.

## New stable runtime model

### 1) Source and build directories

```bash
/opt/blog         # git source
/opt/blog-public  # generated static output
```

### 2) Build script

```bash
#!/usr/bin/env bash
set -euo pipefail
cd /opt/blog
git pull --ff-only
hugo --config config/public.yaml --destination /opt/blog-public
```

### 3) systemd static service

```ini
[Service]
User=<local-user>
WorkingDirectory=/opt/blog-public
ExecStart=/usr/bin/python3 -m http.server 8001 --bind 127.0.0.1
Restart=always
```

### 4) Cron automation

```cron
*/5 * * * * /usr/local/bin/blog-build.sh >> /tmp/blog-build.log 2>&1
```

### 5) Tunnel route

```yaml
ingress:
  - hostname: blog.mysite.com.au
    service: http://localhost:8001
```

## Result

The blog update flow is now straightforward:

1. edit content
2. push repository
3. cron (or manual run) pulls and rebuilds
4. service keeps serving static files stably

This made operations much easier than repeatedly troubleshooting runtime init builds in-cluster.

## Lessons learned

1. Simpler runtime beats clever runtime for small personal sites.
2. Keep build/runtime assumptions explicit and version-compatible.
3. Prefer repeatable scripts over ad-hoc shell actions.
4. Operational consistency across projects lowers maintenance cost.

## Next improvements

- Add lightweight health checks and alerting
- Add a safer publish wrapper with preflight checks
- Add a small deploy status dashboard/log summary
