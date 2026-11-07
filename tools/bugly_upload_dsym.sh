#!/bin/sh
# Bugly dSYM 符号表上传。
#
# 两种用法：
#   A) 手动 / CI（推荐）
#        tools/bugly_upload_dsym.sh --check                      # 只做环境自检
#        tools/bugly_upload_dsym.sh --path build/Release-iphoneos
#        tools/bugly_upload_dsym.sh --path XiangYang.xcarchive
#        tools/bugly_upload_dsym.sh --path /path/to/XiangYang.app.dSYM
#
#   B) 作为 Xcode 构建阶段（已挂在工程里，默认不执行）
#        BUGLY_DSYM_UPLOAD=YES xcodebuild ... build
#
# 依赖：
#   - java：JDK/JRE 8+（macOS 自带 /usr/bin/java 只是个提示桩，需要真正装一个）
#   - buglySymboliOS.jar：Bugly 控制台「符号表 → 工具下载」，
#     默认找 tools/buglySymboliOS.jar，也可用 BUGLY_SYMBOL_JAR 指定
#   - AppKey：tools/bugly.env（已 gitignore）或环境变量 BUGLY_APP_KEY
#
# 注意：upload_one() 里的 java 参数按 Bugly 官方工具的常见写法编排；
#       若官方参数有变，只改那几行即可，其余逻辑不用动。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

MODE="build"      # build | cli | check
TARGET=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path)  MODE="cli";   TARGET="${2:-}"; shift 2 ;;
    --check) MODE="check"; shift ;;
    -h|--help)
      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: 未知参数 $1（用 --help 看用法）" >&2
      exit 2
      ;;
  esac
done

# 构建阶段里任何问题都只告警、不打断构建；手动模式下直接失败并返回非 0
fail() {
  if [ "${MODE}" = "build" ]; then
    echo "warning: $1"
    exit 0
  fi
  echo "error: $1" >&2
  exit 1
}

if [ "${MODE}" = "build" ] && [ "${BUGLY_DSYM_UPLOAD:-}" != "YES" ]; then
  echo "note: 跳过 Bugly dSYM 上传（未开启 BUGLY_DSYM_UPLOAD）"
  exit 0
fi

# ---- AppKey：环境变量优先，其次 tools/bugly.env（不入库） ----
if [ -z "${BUGLY_APP_KEY:-}" ]; then
  for envfile in "${SCRIPT_DIR}/bugly.env" "${REPO_DIR}/tools/bugly.env"; do
    if [ -f "${envfile}" ]; then
      . "${envfile}"
      break
    fi
  done
fi
KEY="${BUGLY_APP_KEY:-}"

JAR="${BUGLY_SYMBOL_JAR:-${SCRIPT_DIR}/buglySymboliOS.jar}"
PKG="${BUGLY_BUNDLE_ID:-com.apple.mobile.MobileHouseArrest}"
VER="${BUGLY_VERSION:-}"
CH="${BUGLY_CHANNEL:-Direct}"

# ---- dSYM 列表 ----
DSYMS=""
case "${MODE}" in
  cli)
    if [ -z "${TARGET}" ]; then
      echo "error: --path 需要一个目录、.xcarchive 或 .dSYM 路径" >&2
      exit 2
    fi
    if [ ! -e "${TARGET}" ]; then
      echo "error: 路径不存在：${TARGET}" >&2
      exit 1
    fi
    case "${TARGET}" in
      *.dSYM) DSYMS="${TARGET}" ;;
      *) DSYMS=$(find "${TARGET}" -maxdepth 4 -name '*.dSYM' -type d 2>/dev/null | sort) ;;
    esac
    [ -n "${DSYMS}" ] || fail "在 ${TARGET} 里没找到 .dSYM"
    ;;
  build)
    DSYMS=$(ls -d "${DWARF_DSYM_FOLDER_PATH:-}"/*.dSYM 2>/dev/null || true)
    [ -n "${DSYMS}" ] || fail "找不到 dSYM 目录（DWARF_DSYM_FOLDER_PATH）"
    ;;
  check)
    DSYMS=""
    ;;
esac

# ---- 自检 ----
echo "== Bugly 符号表上传自检 =="
echo "java     : $(command -v java 2>/dev/null || echo '未找到')"
if ! java -version >/dev/null 2>&1; then
  JAVA_OK=no
  echo "           ↳ 不可用（macOS 的 /usr/bin/java 只是提示桩，需要安装 JDK）"
else
  JAVA_OK=yes
  echo "           ↳ $(java -version 2>&1 | head -1)"
fi
echo "jar      : ${JAR}"
[ -f "${JAR}" ] && JAR_OK=yes || JAR_OK=no
echo "           ↳ $([ "${JAR_OK}" = yes ] && echo '已找到' || echo '未找到（从 Bugly 控制台下载后放到 tools/ 下）')"
echo "AppKey   : $([ -n "${KEY}" ] && echo "${KEY}" || echo '未配置（tools/bugly.env 或 BUGLY_APP_KEY）')"
echo "Bundle ID: ${PKG}"
echo "channel  : ${CH}"
echo

if [ "${MODE}" = "cli" ]; then
  echo "待上传的 dSYM："
  echo "${DSYMS}" | while IFS= read -r d; do
    [ -n "${d}" ] || continue
    echo "  - ${d}  UUID=$(dwarfdump --uuid "${d}" 2>/dev/null | awk '{print $2; exit}')"
  done
  echo
fi

if [ "${MODE}" = "check" ]; then
  [ "${JAVA_OK}" = yes ] && [ "${JAR_OK}" = yes ] && [ -n "${KEY}" ] \
    && { echo "结果：就绪，可以用 --path 上传。"; exit 0; } \
    || { echo "结果：上述缺失项补齐后才能上传。"; exit 1; }
fi

if [ "${JAVA_OK}" != yes ]; then
  fail "缺少可用的 java，无法上传 dSYM"
fi
if [ "${JAR_OK}" != yes ]; then
  fail "缺少符号表工具 buglySymboliOS.jar（${JAR}）"
fi
if [ -z "${KEY}" ]; then
  fail "缺少 AppKey（tools/bugly.env 或 BUGLY_APP_KEY）"
fi

UPLOADED=0
FAILED=0
upload_one() {
  _dsym="$1"
  _uuid=$(dwarfdump --uuid "${_dsym}" 2>/dev/null | awk '{print $2; exit}')
  echo "==> 上传 ${_dsym}"
  echo "    UUID: ${_uuid:-unknown}"
  set -- -jar "${JAR}" -i "${_dsym}" -u -id "${KEY}" -package "${PKG}"
  [ -n "${VER}" ] && set -- "$@" -version "${VER}"
  set -- "$@" -channel "${CH}"
  java "$@"
}

while IFS= read -r dsym; do
  [ -n "${dsym}" ] || continue
  if upload_one "${dsym}"; then
    UPLOADED=$((UPLOADED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done <<EOF
${DSYMS}
EOF

echo
echo "完成：成功 ${UPLOADED} 个，失败 ${FAILED} 个"
if [ "${FAILED}" -gt 0 ]; then
  if [ "${MODE}" = "build" ]; then
    echo "warning: 有 dSYM 上传失败，但不影响本次构建"
    exit 0
  fi
  exit 1
fi
exit 0
