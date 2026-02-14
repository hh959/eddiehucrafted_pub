# Private Repo SOP (eddiehucrafted_pri)

> 目标：私有仓库存全量内容；公开仓库只发布筛选后的 public 内容。

## 仓库角色
- `eddiehucrafted_pri`：完整源仓库（主工作仓）
- `eddiehucrafted_pub`：公开发布仓库（只放 public 子集）

## 分支规则
- `main`（private）：完整内容（public + draft + private）
- `public`（publish 分支）：仅公开内容，用于推送到 public repo

## 目录规则
- 可公开：
  - `content/public/**`
  - `static/public/**`
  - `config/public.yaml`
- 不可公开：
  - `content/draft/**`
  - `content/private/**`
  - `static/private/**`
  - 任意密钥、令牌、账号配置

## 日常写作（每次）
1. 在 `main` 分支写作（可放 public/draft/private）
2. 提交到 private 仓库：
   - `git add .`
   - `git commit -m "..."`
   - `git push pri main`

## 对外发布（需要公开时）
1. 在 `main` 确认内容已提交
2. 运行发布脚本（由 `scripts/publish-public.sh` 统一处理）
3. 脚本将：
   - 切换/更新 `public` 分支
   - 仅保留公开目录
   - 推送到 `pub` 仓库

## 发布前检查清单
- [ ] 本次要公开的文章都在 `content/public/`
- [ ] `draft/private` 中没有误放公开文章
- [ ] 未包含 `.env`、token、密码等敏感信息
- [ ] 图片链接仅指向 `static/public/`

## 严禁事项
- 不要手动往 public repo 推 `main`
- 不要在 public repo 存放运维文档和密钥
- 不要在 public 分支手工改内容（只通过发布脚本生成）
