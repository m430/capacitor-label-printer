#!/usr/bin/env bash
#
# @m430/capacitor-label-printer 自动化发布脚本
#
# 用法:
#   npm run release                    交互式选择发布方式
#   npm run release -- --dry-run       干跑模式（不发布、不推送）
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_JSON="${ROOT_DIR}/package.json"
PACKAGE_LOCK="${ROOT_DIR}/package-lock.json"

cd "${ROOT_DIR}"

# ---------- 参数解析 ----------
DRY_RUN=false

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) echo "未知参数: $arg"; exit 1 ;;
  esac
done

# ---------- 输出工具 ----------
info()  { printf "\033[0;34m>> [Release]\033[0m %s\n" "$1"; }
ok()    { printf "\033[0;32m>> [Release]\033[0m %s\n" "$1"; }
warn()  { printf "\033[1;33m>> [Release]\033[0m %s\n" "$1"; }
err()   { printf "\033[0;31m>> [Release]\033[0m %s\n" "$1"; }

# ---------- 同步版本号到 package.json / package-lock.json ----------
sync_version_files() {
  local target_version="$1"
  node --input-type=commonjs - "${PACKAGE_JSON}" "${PACKAGE_LOCK}" "${target_version}" <<'EOF'
const fs = require('fs');
const packageJsonPath = process.argv[2];
const packageLockPath = process.argv[3];
const targetVersion = process.argv[4];
const writeJson = (filePath, data) => {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n');
};
const pkg = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
pkg.version = targetVersion;
writeJson(packageJsonPath, pkg);
if (fs.existsSync(packageLockPath)) {
  const lock = JSON.parse(fs.readFileSync(packageLockPath, 'utf8'));
  lock.version = targetVersion;
  if (lock.packages && lock.packages['']) {
    lock.packages[''].version = targetVersion;
  }
  writeJson(packageLockPath, lock);
}
EOF
}

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
info "当前分支: ${BRANCH}"
if [ "$BRANCH" != "main" ] && [ "$BRANCH" != "master" ]; then
  warn "当前不在 main/master 分支"
  read -r -p "是否继续发布? (y/N) " confirm
  if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    err "已取消"; exit 0
  fi
fi

# 4. git 身份配置（正式发布时需要）
if [ "$DRY_RUN" = false ]; then
  if [ -z "$(git config user.name)" ] || [ -z "$(git config user.email)" ]; then
    err "未配置 git user.name / user.email，提交版本号需要 git 身份信息"
    err "请执行: git config user.name \"Your Name\" && git config user.email \"you@example.com\""
    exit 1
  fi
  ok "git 身份: $(git config user.name) <$(git config user.email)>"
fi

# ---------- 版本号选择 ----------

CURRENT_VERSION="$(node -p "require('${PACKAGE_JSON}').version")"

if [ -z "${CURRENT_VERSION}" ]; then
  err "未能从 package.json 中解析到 version 字段"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "${CURRENT_VERSION}"

if [ -z "${MAJOR:-}" ] || [ -z "${MINOR:-}" ] || [ -z "${PATCH:-}" ]; then
  err "当前版本号格式不合法: ${CURRENT_VERSION}"
  exit 1
fi

if ! [[ "${MAJOR}" =~ ^[0-9]+$ && "${MINOR}" =~ ^[0-9]+$ && "${PATCH}" =~ ^[0-9]+$ ]]; then
  err "当前版本号格式不合法: ${CURRENT_VERSION}"
  exit 1
fi

NEXT_PATCH=$((PATCH + 1))
NEXT_VERSION="${MAJOR}.${MINOR}.${NEXT_PATCH}"

echo ""
echo "当前版本: ${CURRENT_VERSION}"
echo "建议下一个版本: ${NEXT_VERSION}"
echo ""
echo "请选择本次发布方式:"
echo "1. 升级到 ${NEXT_VERSION} 并继续发布"
echo "2. 保持 ${CURRENT_VERSION} 并继续发布"
echo "3. 取消发布"

while true; do
  printf "请输入 [1/2/3]: "
  read -r CHOICE

  case "${CHOICE}" in
    1)
      RELEASE_VERSION="${NEXT_VERSION}"
      echo "版本已更新为: ${NEXT_VERSION}"
      break
      ;;
    2)
      RELEASE_VERSION="${CURRENT_VERSION}"
      echo "保留当前版本: ${CURRENT_VERSION}"
      break
      ;;
    3)
      echo "已取消本次发布"
      exit 0
      ;;
    *)
      echo "无效输入，请输入 1、2 或 3"
      ;;
  esac
done

# ---------- 同步版本号 ----------

if [ "$DRY_RUN" = true ]; then
  info "[dry-run] 目标版本: ${RELEASE_VERSION}（不修改文件）"
else
  if [ "${RELEASE_VERSION}" != "${CURRENT_VERSION}" ]; then
    sync_version_files "${RELEASE_VERSION}"
    info "版本号已同步: ${CURRENT_VERSION} -> ${RELEASE_VERSION}"
  else
    info "保持当前版本: ${CURRENT_VERSION}"
  fi
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

info "本次发布版本: ${RELEASE_VERSION}"

# 预览包内容
echo ""
info "预览发布包内容:"
npm pack --dry-run
echo ""

# git commit + tag
info "提交版本变更并创建 git tag..."
git add package.json package-lock.json 2>/dev/null || git add package.json
if git diff --cached --quiet; then
  warn "当前没有可提交内容，跳过 Git 提交"
else
  git commit -m "chore(release): ${RELEASE_VERSION}" >/dev/null 2>&1
  ok "已创建提交: chore(release): ${RELEASE_VERSION}"
fi
git tag -a "v${RELEASE_VERSION}" -m "Release ${RELEASE_VERSION}" 2>/dev/null || warn "tag v${RELEASE_VERSION} 可能已存在"
ok "已创建 tag: v${RELEASE_VERSION}"

# 发布到 npm
info "发布 ${RELEASE_VERSION} 到 npm registry..."
npm publish --access public
ok "已发布 ${RELEASE_VERSION} 到 npm"

# 推送 git commit 与 tag
info "推送 git commit 与 tag..."
git push origin "${BRANCH}"
git push origin "v${RELEASE_VERSION}"
ok "已推送到远程仓库"

echo ""
ok "================================================"
ok "  发布完成!  ${CURRENT_VERSION} -> ${RELEASE_VERSION}"
ok "  npm: https://www.npmjs.com/package/@m430/capacitor-label-printer"
ok "================================================"
