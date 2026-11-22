#!/usr/bin/env bash
# 绑哪儿 · 一键构建：版本号替换 → JS 语法检查 → 回归测试 → 组装 dist → 打包
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(tr -d '[:space:]' < VERSION)"
if [ -z "$VERSION" ]; then echo "✗ VERSION 文件为空" >&2; exit 1; fi
echo "==> 绑哪儿 build v$VERSION"

FILES="index.html manifest.webmanifest icon.svg icon-192.png icon-512.png apple-touch-icon.png favicon.png favicon.ico"

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# 1) 组装 staging：src 原样拷入，index.html 替换版本占位符
for f in $FILES; do
  if [ ! -f "src/$f" ]; then echo "✗ src/ 缺文件：$f" >&2; exit 1; fi
  cp "src/$f" "$STAGE/$f"
done
sed -i "s/__VERSION__/v$VERSION/g" "$STAGE/index.html"
if grep -q "__VERSION__" "$STAGE/index.html"; then echo "✗ 版本占位符未替换干净" >&2; exit 1; fi
echo "✓ 版本号已写入：v$VERSION（src 里仍是 __VERSION__ 占位符）"

# 2) JS 语法检查：抽 <script> 做 node --check
python3 - "$STAGE/index.html" "$STAGE/app-check.js" <<'PY'
import re, sys
html = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r"<script>(.*)</script>", html, re.S)
if not m:
    print("✗ index.html 里没找到 <script>"); sys.exit(1)
open(sys.argv[2], "w", encoding="utf-8").write(m.group(1))
PY
node --check "$STAGE/app-check.js"
echo "✓ node --check 通过"

# 3) 回归测试（tests/ 存在就跑；需要 jsdom，缺了就明确报错，不假装通过）
if [ -d tests ] && ls tests/*.js >/dev/null 2>&1; then
  echo "==> 跑回归测试…"
  for t in tests/*.js; do
    echo "--- $t"
    OUT="$(node "$t" 2>&1)" && RC=0 || RC=$?
    echo "$OUT" | tail -5
    if [ "$RC" -ne 0 ]; then echo "✗ 测试失败：$t（退出码 $RC）" >&2; exit 1; fi
    if echo "$OUT" | grep -q "_FAIL"; then echo "✗ 测试报告失败：$t" >&2; exit 1; fi
  done
  echo "✓ 回归测试全过"
else
  echo "· 无测试（tests/ 不存在或为空），跳过"
fi

# 4) 组装 dist/（8 个文件）
rm -rf dist
mkdir -p dist
for f in $FILES; do cp "$STAGE/$f" "dist/$f"; done
echo "✓ dist/ 已组装（8 个文件）"

# 5) 打包：部署用固定名 + 存档带版本号，内容相同
( cd dist && zip -q -X atlas-web.zip $FILES )
cp "dist/atlas-web.zip" "dist/atlas-web-v$VERSION.zip"
echo "==> 构建完成"
for z in "dist/atlas-web.zip" "dist/atlas-web-v$VERSION.zip"; do
  printf '%s  md5=%s  size=%s bytes\n' "$z" "$(md5sum "$z" | awk '{print $1}')" "$(stat -c %s "$z")"
done
