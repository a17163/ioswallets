#!/bin/bash
# 把 Xcode 导出的 XiangYang.ipa 重命名为 向阳.ipa。
#
# 工程里 PRODUCT_NAME 用 ASCII（XiangYang），是为了让 zsign / 爱思 / 轻松签
# 这类重签工具能正常处理包内路径；桌面显示名仍然由 CFBundleDisplayName 决定，
# 是「向阳」。这个脚本只改外层文件名，包内容不动。
#
# 用法：
#   tools/rename_ipa.sh                  # 自动找最近一次导出的 IPA
#   tools/rename_ipa.sh <导出目录或 ipa>  # 指定目标
set -euo pipefail

SOURCE_NAME="XiangYang.ipa"
TARGET_NAME="向阳.ipa"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -ge 1 ]; then
  target="$1"
else
  target="$(find "$ROOT" -maxdepth 2 -name "$SOURCE_NAME" -print 2>/dev/null \
    | while IFS= read -r f; do stat -f '%m %N' "$f"; done \
    | sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [ -z "${target:-}" ]; then
  echo "未找到 $SOURCE_NAME，请指定导出目录：tools/rename_ipa.sh <目录>" >&2
  exit 1
fi

if [ -d "$target" ]; then
  src="$target/$SOURCE_NAME"
else
  src="$target"
fi

if [ ! -f "$src" ]; then
  echo "找不到文件：$src" >&2
  exit 1
fi

dst="$(dirname "$src")/$TARGET_NAME"
mv -f "$src" "$dst"
echo "已重命名：$dst"
