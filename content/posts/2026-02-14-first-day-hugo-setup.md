---
title: "Day 1: My Hugo Blog Setup Journey"
date: 2026-02-14
slug: "day-1-hugo-blog-setup"
draft: false
---

Today I completed the first full pass of building and publishing my personal blog with Hugo.

This post records the setup flow as a clean reference for future me.

## What I finished today

### 1) Create new GitHub repositories
I created a new public repository for blog publishing.

### 2) Initialize the Hugo project
I initialized a fresh project folder and added a minimal site structure:

- `content/`
- `layouts/`
- `config/`
- `scripts/`

Then I added a minimal homepage and one sample post.

### 3) Local debugging and verification
I installed Hugo locally and verified static site generation.

Checks I used:

- Build site locally
- Confirm `index.html` is generated
- Confirm homepage title and post list render correctly

### 4) Push repository and verify publish branch flow
I set up a publishing script that:

- keeps only public-safe content for publishing
- builds a clean publish branch source
- pushes to the public repository

This ensures the public site content stays clean and focused.

### 5) Deploy Hugo site to K3s
I deployed the blog as a containerized service on K3s with:

- a dedicated namespace
- deployment + service
- ingress host routing for blog domain

I verified service availability from inside the cluster and via ingress.

### 6) Configure Cloudflare Tunnel
In the tunnel config, I added a new hostname route for the blog domain to the blog ingress entry.

Then I restarted tunnel service and verified route response.

### 7) Configure DNS
I added the DNS record for the blog subdomain and confirmed external access.

Final result: the blog is now reachable from browser over HTTPS.

## Key lessons from Day 1

1. Start with a minimal runnable Hugo layout first.
2. Verify locally before deploying to K3s.
3. Keep publish flow deterministic and repeatable.
4. Ingress + tunnel + DNS must all align for public access.

## Next Day Plan

1. Add a proper Hugo theme and basic navigation.
2. Improve homepage structure (About / Posts / Projects).
3. Add a small CI/CD check for publish pipeline.
4. Add health checks and restart strategy for blog deployment.
5. Investigate and resolve the zombie process issue on the cluster server.

---

This is my Day 1 milestone: from zero to publicly reachable Hugo blog.
