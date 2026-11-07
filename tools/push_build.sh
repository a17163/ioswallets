#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ "$(git branch --show-current)" != main ]]; then
  echo "请先切换到 main 分支，再运行此脚本。" >&2
  exit 1
fi

# 先检查远程进度，不自动合并或覆盖远程提交。
git fetch origin main
if ! git merge-base --is-ancestor origin/main HEAD; then
  echo "远程 main 有本地尚未包含的提交，请先同步后重试。" >&2
  exit 1
fi

message="${1:-ci: build XiangYang IPA}"
git add -A
if ! git diff --cached --quiet; then
  git commit -m "$message"
elif [[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]]; then
  git commit --allow-empty -m "$message"
fi

git push origin main
echo
echo "已推送，GitHub Actions 将自动编译 XiangYang.ipa。"
echo "提交：$(git rev-parse --short HEAD)"
echo "构建页面：https://github.com/a17163/ioswallets/actions/workflows/build-ipa.yml"
echo "编译完成后登录 GitHub，下载 Artifacts → XiangYang，解压获取 IPA。"
