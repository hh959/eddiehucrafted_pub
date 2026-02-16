---
title: "Day 1: My Hugo Blog Setup Journey"
date: 2026-02-14
slug: "day-1-hugo-blog-setup"
draft: false
description: "从零搭建 Hugo 博客并打通发布链路：仓库初始化、本地验证、发布脚本、Cloudflare Tunnel 与公网访问。"
summary: "Day 1 完成了 Hugo 博客从 0 到可公网访问的全流程，包含仓库初始化、脚本化发布、K3s 首次部署与 Tunnel/DNS 打通。"
cover: "/images/hugo-header.jpg"
---

Today I completed the first full pass of building and publishing my personal blog with Hugo.

This post records the setup flow as a clean reference for future me.

## What I finished today

### 1) Create new GitHub repositories
I created new repositories for blog workflow.

```bash
# Create repos in GitHub first, then verify from terminal
git ls-remote git@github.com:<your-user>/myblog_pub.git HEAD
git ls-remote git@github.com:<your-user>/myblog_pri.git HEAD
```

### 2) Initialize the Hugo project
I initialized a fresh project folder and added a minimal structure.

```bash
mkdir -p ~/myblog_com/{content/public/posts,content/draft,content/private,static/public/images,static/private/images,config,scripts}
cd ~/myblog_com
git init -b main
```

Then I added minimal config/content:

```bash
cat > config/public.yaml <<'EOF'
baseURL: "https://blog.mysite.com/"
languageCode: "en-us"
title: "My Blog"
EOF
```

### 3) Local debugging and verification
I installed Hugo and verified static site generation locally.

```bash
hugo --config config/public.yaml --destination /tmp/eddie-hugo-public
ls -la /tmp/eddie-hugo-public
```

Checks I used:
- Build site locally
- Confirm `index.html` is generated
- Confirm homepage title and post list render correctly

### 4) Push repository and verify publish flow
I used a publish script to keep public output clean and repeatable.

```bash
# private source push
git add .
git commit -m "Initialize Hugo workflow"
git push pri main

# publish-only flow
./scripts/publish-public.sh
```

### 5) Deploy Hugo on K3s (first attempt)
I deployed a blog service with namespace, deployment, service, and ingress.

```bash
kubectl apply -f deploy-k3s-hugo-blog.yaml
kubectl -n blog get pods,svc,ingress -o wide
```

### 6) Configure Cloudflare Tunnel
I added a blog route in cloudflared config and restarted the service.

```yaml
ingress:
  - hostname: blog.mysite.com
    service: http://localhost:8001
  - service: http_status:404
```

```bash
sudo systemctl restart cloudflared
```

### 7) Configure DNS
I added DNS record for the blog subdomain and verified HTTPS access.

```bash
curl -I https://blog.mysite.com
```

Final result: the blog became reachable over HTTPS.

## Key lessons from Day 1

1. Start with a minimal runnable Hugo layout first.
2. Verify locally before cluster/public routing.
3. Keep publish flow deterministic and script-driven.
4. Route chain must align: app -> local service -> tunnel -> DNS.

## Next Day Plan

1. Add a proper Hugo theme and basic navigation.
2. Improve homepage structure (About / Posts / Projects).
3. Harden publish automation and safety checks.
4. Improve runtime stability and monitoring.
5. Keep infra notes in out-of-repo worklog.

---

This is my Day 1 milestone: from zero to publicly reachable Hugo blog.
