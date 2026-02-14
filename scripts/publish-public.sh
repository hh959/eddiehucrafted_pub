#!/usr/bin/env bash
set -euo pipefail

# publish-public.sh
# Purpose:
# - Generate/update public branch from private main workspace
# - Push filtered public content to public repo
#
# NOTE: This is a safe scaffold. Review before first real run.

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

PRI_REMOTE="pri"
PUB_REMOTE="pub"
PRIVATE_BRANCH="main"
PUBLIC_BRANCH="public"

WORKTREE_DIR=".worktree-public"
STAGE_DIR=".publish-stage"

echo "[1/8] Pre-checks..."
command -v git >/dev/null

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: Not a git repo: $ROOT_DIR"
  exit 1
}

if ! git remote get-url "$PRI_REMOTE" >/dev/null 2>&1; then
  echo "WARN: remote '$PRI_REMOTE' not found (expected private remote)"
fi
if ! git remote get-url "$PUB_REMOTE" >/dev/null 2>&1; then
  echo "WARN: remote '$PUB_REMOTE' not found (expected public remote)"
fi

echo "[2/8] Ensure clean working tree..."
if [[ -n "$(git status --porcelain)" ]]; then
  echo "ERROR: Working tree not clean. Commit/stash first."
  exit 1
fi

echo "[3/8] Build publish staging area..."
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"

# Copy ONLY public-safe content
mkdir -p "$STAGE_DIR/content" "$STAGE_DIR/static" "$STAGE_DIR/config"
[[ -d content/public ]] && cp -a content/public "$STAGE_DIR/content/"
[[ -d static/public ]] && cp -a static/public "$STAGE_DIR/static/"
[[ -f config/public.yaml ]] && cp -a config/public.yaml "$STAGE_DIR/config/"

# Optional: minimal README for public repo
cat > "$STAGE_DIR/README.md" <<'MD'
# eddiehucrafted_pub

Public website content only.
MD

echo "[4/8] Sensitive content guard checks..."
if find "$STAGE_DIR" -type f \( -name "*.env" -o -name "*secret*" -o -name "*token*" \) | grep -q .; then
  echo "ERROR: Sensitive-like files detected in stage. Abort."
  exit 1
fi

echo "[5/8] Prepare public worktree..."
rm -rf "$WORKTREE_DIR"
# Create/update local public branch reference
if git show-ref --verify --quiet "refs/heads/$PUBLIC_BRANCH"; then
  git worktree add "$WORKTREE_DIR" "$PUBLIC_BRANCH"
else
  git worktree add -b "$PUBLIC_BRANCH" "$WORKTREE_DIR"
fi

echo "[6/8] Replace public branch contents with staged public subset..."
cd "$WORKTREE_DIR"
# remove everything except .git
find . -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} +
cp -a "$ROOT_DIR/$STAGE_DIR/." .

git add -A
if git diff --cached --quiet; then
  echo "No public changes to commit."
else
  git commit -m "Publish public content from private source"
fi

echo "[7/8] Push public branch to public repo main..."
if git remote get-url "$PUB_REMOTE" >/dev/null 2>&1; then
  git push "$PUB_REMOTE" "$PUBLIC_BRANCH":main
else
  echo "WARN: Skipped push. Remote '$PUB_REMOTE' not configured."
fi

echo "[8/8] Cleanup..."
cd "$ROOT_DIR"
git worktree remove "$WORKTREE_DIR" --force
rm -rf "$STAGE_DIR"

echo "Done. Public publish pipeline completed."
