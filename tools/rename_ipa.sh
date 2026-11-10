#!/bin/bash
# 历史包改名：把旧版本导出的 XiangYang.ipa 重命名为 coinokx.ipa。
#
# 工程 PRODUCT_NAME 现在就是 ASCII 的 coinokx，新构建会直接产出 coinokx.ipa，
# 一般不需要跑这个脚本；它只用于处理改名之前留下的旧包。只改外层文件名，包内容不动。
#
# 用法：
#   tools/rename_ipa.sh                  # 自动找最近一次导出的 IPA
#   tools/rename_ipa.sh <导出目录或 ipa>  # 指定目标
set -euo pipefail

SOURCE_NAME="XiangYang.ipa"
TARGET_NAME="coinokx.ipa"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

if [ $# -ge 1 ]; then
  target="$1"
else
  target="$(find "$ROOT" -maxdepth 2 -name "$SOURCE_NAME" -print 2>/dev/null \
    | while IFS= read -r f; do stat -f '%m %N' "$f"; done \
    | sort -rn | head -1 | cut -d' ' -f2-)"
fi

if [ -z "${target:-}" ]; then
  echo "未找到旧的 $SOURCE_NAME（新构建已直接产出 $TARGET_NAME），如为历史包请指定目录：tools/rename_ipa.sh <目录>" >&2
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
