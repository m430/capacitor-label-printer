#!/usr/bin/env bash
#
# @m430/capacitor-label-printer 自动化发布脚本
#
# 用法:
#   npm run release                        交互式选择版本级别
#   npm run release -- patch               补丁版本 (0.0.x)
#   npm run release -- minor               次版本   (0.x.0)
#   npm run release -- major               主版本   (x.0.0)
#   npm run release -- prerelease          预发布版本
#   npm run release -- 1.2.3               指定具体版本号
#   npm run release -- patch --dry-run     干跑模式（不发布、不推送）
#   npm run release -- prerelease --preid beta  带预发布标识 (如 0.1.0-beta.0)
#
set -euo pipefail

cd "$(dirname "$0")/.."

# ---------- 输出工具 ----------
info()  { printf "\033[0;34mℹ\033[0m  %s\n" "$1"; }
ok()    { printf "\033[0;32m✓\033[0m  %s\n" "$1"; }
warn()  { printf "\033[1;33m⚠\033[0m  %s\n" "$1"; }
err()   { printf "\033[0;31m✗\033[0m  %s\n" "$1"; }

# ---------- 参数解析 ----------
BUMP=""
DRY_RUN=false
PREID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    patch|minor|major|prerelease)
      BUMP="$1"; shift ;;
    --dry-run)
      DRY_RUN=true; shift ;;
    --preid)
      PREID="$2"; shift 2 ;;
    --preid=*)
      PREID="${1#*=}"; shift ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
    --*)
      err "未知选项: $1"; exit 1 ;;
    *)
      if [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
        BUMP="$1"
      else
        err "未知参数: $1"; exit 1
      fi
      shift ;;
  esac
done

# ---------- 前置检查 ----------

# 1. npm 登录状态（dry-run 模式下跳过）
if [ "$DRY_RUN" = false ]; then
  info "检查 npm 登录状态..."
  if ! npm whoami >/dev/null 2>&1; then
    err "未登录 npm，请先执行: npm login"
    exit 1
  fi
  ok "npm 已登录: $(npm whoami)"
else
  warn "[dry-run] 跳过 npm 登录检查"
fi

# 2. git 工作区干净
info "检查 git 工作区..."
if [ -n "$(git status --porcelain)" ]; then
  if [ "$DRY_RUN" = false ]; then
    err "git 工作区不干净，请先提交或暂存(stash)改动:"
    git status --short
    exit 1
  else
    warn "[dry-run] git 工作区不干净（正式发布时需先提交改动）"
  fi
else
  ok "git 工作区干净"
fi

# 3. 当前分支
BRANCH=$(git rev-parse --abbrev-ref HEAD)
info "当前分支: $BRANCH"
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  warn "当前不在 main/master 分支"
  read -r -p "是否继续发布? (y/N) " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    err "已取消"; exit 1
  fi
fi

# 4. git 身份配置（正式发布时 npm version commit 需要）
if [ "$DRY_RUN" = false ]; then
  if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
    err "未配置 git user.name / user.email，提交版本号需要 git 身份信息"
    err "请执行: git config user.name \"Your Name\" && git config user.email \"you@example.com\""
    exit 1
  fi
  ok "git 身份: $(git config user.name) <$(git config user.email)>"
fi

# ---------- 确定版本号 ----------

CURRENT_VERSION=$(node -p "require('./package.json').version")
info "当前版本: $CURRENT_VERSION"

if [ -z "$BUMP" ]; then
  echo ""
  echo "请选择发布级别:"
  echo "  1) patch"
  echo "  2) minor"
  echo "  3) major"
  echo "  4) prerelease"
  read -r -p "输入数字 [1-4]: " choice
  case "$choice" in
    1) BUMP="patch" ;;
    2) BUMP="minor" ;;
    3) BUMP="major" ;;
    4) BUMP="prerelease" ;;
    *) err "无效选择"; exit 1 ;;
  esac
fi

# 计算下一个版本号
if [[ "$BUMP" =~ ^[0-9] ]]; then
  NEXT_VERSION="$BUMP"
else
  if [ "$DRY_RUN" = true ]; then
    # dry-run: 备份后计算再恢复，避免丢失未提交的改动
    cp package.json package.json.bak
    [ -f package-lock.json ] && cp package-lock.json package-lock.json.bak
    NEXT_VERSION=$(npm version "$BUMP" --no-git-tag-version $([ -n "$PREID" ] && echo "--preid $PREID") 2>/dev/null | sed 's/^v//')
    mv package.json.bak package.json
    [ -f package-lock.json.bak ] && mv package-lock.json.bak package-lock.json
  else
    NEXT_VERSION=$(npm version "$BUMP" --no-git-tag-version $([ -n "$PREID" ] && echo "--preid $PREID") 2>/dev/null | sed 's/^v//')
  fi
fi

if [ "$DRY_RUN" = true ]; then
  info "[dry-run] 目标版本: $CURRENT_VERSION -> $NEXT_VERSION"
else
  info "目标版本: $CURRENT_VERSION -> $NEXT_VERSION"
fi

# ---------- 运行测试与构建 ----------

info "运行单元测试..."
npm run test:unit
ok "单元测试通过"

info "运行构建 (clean + docgen + tsc + rollup)..."
npm run build
ok "构建完成"

# ---------- dry-run 模式 ----------

if [ "$DRY_RUN" = true ]; then
  echo ""
  info "[dry-run] 预览发布包内容:"
  npm pack --dry-run
  echo ""
  ok "[dry-run] 验证完成，未实际发布。去掉 --dry-run 即可正式发布。"
  exit 0
fi

# ---------- 正式发布 ----------

# 版本号已在上面通过 npm version --no-git-tag-version 更新到 package.json
# 现在提交版本变更并打 tag
info "提交版本变更并创建 git tag..."
git add package.json package-lock.json 2>/dev/null || git add package.json
git commit -m "chore(release): $NEXT_VERSION" >/dev/null 2>&1 || warn "版本提交可能已存在"
git tag -a "v$NEXT_VERSION" -m "Release $NEXT_VERSION" 2>/dev/null || warn "tag v$NEXT_VERSION 可能已存在"
ok "已创建 tag: v$NEXT_VERSION"

# 预览包内容
echo ""
info "预览发布包内容:"
npm pack --dry-run
echo ""

# 发布到 npm
info "发布 $NEXT_VERSION 到 npm..."
npm publish --access public
ok "已发布 $NEXT_VERSION 到 npm"

# 推送 git commit 与 tag
info "推送 git commit 与 tag..."
git push origin "$BRANCH"
git push origin "v$NEXT_VERSION"
ok "已推送到远程仓库"

echo ""
ok "================================================"
ok "  发布完成!  $CURRENT_VERSION -> $NEXT_VERSION"
ok "  npm: https://www.npmjs.com/package/@m430/capacitor-label-printer"
ok "================================================"
