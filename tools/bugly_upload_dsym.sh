#!/bin/sh
# Bugly dSYM 符号表上传（基于官方 buglyqq-upload-symbol V3.3.5）。
#
# 用法：
#   手动 / CI
#     tools/bugly_upload_dsym.sh --check
#     tools/bugly_upload_dsym.sh --path build/Release-iphoneos
#     tools/bugly_upload_dsym.sh --path XiangYang.xcarchive
#     tools/bugly_upload_dsym.sh --path /path/to/XiangYang.app.dSYM
#   可覆盖项：--version 2.1.8  --appid xxx  --jar /path/to/buglyqq-upload-symbol.jar
#
#   Xcode 构建阶段（工程里已挂好，默认不执行）
#     BUGLY_DSYM_UPLOAD=YES xcodebuild ... build
#
# 依赖：
#   - java（JDK/JRE 8+；macOS 自带 /usr/bin/java 只是提示桩）
#   - buglyqq-upload-symbol.jar：默认找 tools/buglyqq-upload-symbol.jar，
#     也可用 BUGLY_SYMBOL_JAR 指定
#   - AppKey：tools/bugly.env（已 gitignore）或环境变量 BUGLY_APP_KEY
#
# 官方参数（V3.3.5）：
#   -appid -appkey -version -platform IOS -inputSymbol <dSYM 所在目录>
#   其中 -version 必须与 Bugly 控制台里看到的 crash 版本号一致。
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_DIR=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

MODE="build"      # build | cli | check
TARGET=""
OPT_VERSION=""
OPT_APPID=""
OPT_JAR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --path)    MODE="cli";   TARGET="${2:-}"; shift 2 ;;
    --check)   MODE="check"; shift ;;
    --version) OPT_VERSION="${2:-}"; shift 2 ;;
    --appid)   OPT_APPID="${2:-}"; shift 2 ;;
    --jar)     OPT_JAR="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "error: 未知参数 $1（用 --help 看用法）" >&2; exit 2 ;;
  esac
done

# 构建阶段只告警、不打断构建；手动模式失败返回非 0
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

# ---- 凭据：环境变量优先，其次 tools/bugly.env（不入库） ----
if [ -z "${BUGLY_APP_KEY:-}" ]; then
  for envfile in "${SCRIPT_DIR}/bugly.env" "${REPO_DIR}/tools/bugly.env"; do
    if [ -f "${envfile}" ]; then
      . "${envfile}"
      break
    fi
  done
fi
KEY="${BUGLY_APP_KEY:-}"
APPID="${OPT_APPID:-${BUGLY_APP_ID:-4396644a23}}"

# ---- 工具 jar ----
if [ -n "${OPT_JAR}" ]; then
  JAR="${OPT_JAR}"
elif [ -n "${BUGLY_SYMBOL_JAR:-}" ]; then
  JAR="${BUGLY_SYMBOL_JAR}"
elif [ -f "${SCRIPT_DIR}/buglyqq-upload-symbol.jar" ]; then
  JAR="${SCRIPT_DIR}/buglyqq-upload-symbol.jar"
else
  JAR=$(ls "${SCRIPT_DIR}"/buglyqq-upload-symbol*.jar 2>/dev/null | head -1 || true)
  JAR="${JAR:-${SCRIPT_DIR}/buglyqq-upload-symbol.jar}"
fi

# ---- java：优先 JAVA_HOME / Homebrew，再看 PATH ----
JAVA=""
for cand in "${JAVA_HOME:-}/bin/java" \
            /opt/homebrew/opt/openjdk@17/bin/java \
            /opt/homebrew/opt/openjdk/bin/java \
            /usr/local/opt/openjdk/bin/java; do
  if [ -n "${cand}" ] && [ -x "${cand}" ] && "${cand}" -version >/dev/null 2>&1; then
    JAVA="${cand}"
    break
  fi
done
if [ -z "${JAVA}" ] && command -v java >/dev/null 2>&1 && java -version >/dev/null 2>&1; then
  JAVA=$(command -v java)
fi

# ---- 版本号 ----
VERSION="${OPT_VERSION:-${BUGLY_VERSION:-}}"
if [ -z "${VERSION}" ] && [ -n "${MARKETING_VERSION:-}" ] && [ -n "${CURRENT_PROJECT_VERSION:-}" ]; then
  VERSION="${MARKETING_VERSION}.${CURRENT_PROJECT_VERSION}"
fi

# ---- dSYM 目录 ----
SYMBOL_DIR=""
case "${MODE}" in
  cli)
    [ -n "${TARGET}" ] || { echo "error: --path 需要目录、.xcarchive 或 .dSYM 路径" >&2; exit 2; }
    [ -e "${TARGET}" ] || { echo "error: 路径不存在：${TARGET}" >&2; exit 1; }
    case "${TARGET}" in
      *.dSYM) SYMBOL_DIR=$(dirname "${TARGET}") ;;
      *)      SYMBOL_DIR="${TARGET}" ;;
    esac
    ;;
  build) SYMBOL_DIR="${DWARF_DSYM_FOLDER_PATH:-}" ;;
esac

# 版本号兜底：从同级 .app 的 Info.plist 读（2.1 + 8 = 2.1.8）
if [ -z "${VERSION}" ] && [ -n "${SYMBOL_DIR}" ]; then
  APP=$(ls -d "${SYMBOL_DIR}"/*.app 2>/dev/null | head -1 || true)
  if [ -n "${APP}" ] && [ -f "${APP}/Info.plist" ]; then
    SHORT=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP}/Info.plist" 2>/dev/null || true)
    BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP}/Info.plist" 2>/dev/null || true)
    [ -n "${SHORT}" ] && VERSION="${SHORT}${BUILD:+.$BUILD}"
  fi
fi

# ---- 自检 ----
echo "== Bugly 符号表上传自检 =="
echo "java     : ${JAVA:-未找到（需要 JDK/JRE；macOS 自带 /usr/bin/java 只是提示桩）}"
echo "jar      : ${JAR} $([ -f "${JAR}" ] && echo '' || echo '（未找到）')"
echo "AppID    : ${APPID}"
echo "AppKey   : $([ -n "${KEY}" ] && echo "${KEY}" || echo '未配置（tools/bugly.env 或 BUGLY_APP_KEY）')"
echo "version  : ${VERSION:-未确定（用 --version 指定，需与控制台 crash 版本一致）}"
[ -n "${SYMBOL_DIR}" ] && echo "symbolDir: ${SYMBOL_DIR}"
echo

if [ "${MODE}" = "check" ]; then
  [ -n "${JAVA}" ] && [ -f "${JAR}" ] && [ -n "${KEY}" ] \
    && { echo "结果：就绪。"; exit 0; } \
    || { echo "结果：上述缺失项补齐后才能上传。"; exit 1; }
fi

[ -n "${JAVA}" ] || fail "缺少可用的 java（可用 brew install openjdk@17 安装）"
[ -f "${JAR}" ] || fail "缺少符号表工具 buglyqq-upload-symbol.jar（${JAR}）"
[ -n "${KEY}" ] || fail "缺少 AppKey（tools/bugly.env 或 BUGLY_APP_KEY）"
[ -n "${SYMBOL_DIR}" ] && [ -d "${SYMBOL_DIR}" ] || fail "找不到 dSYM 所在目录"
[ -n "${VERSION}" ] || fail "未确定版本号，请用 --version 指定"
ls -d "${SYMBOL_DIR}"/*.dSYM >/dev/null 2>&1 || fail "${SYMBOL_DIR} 里没有 .dSYM"

echo "==> 上传 ${SYMBOL_DIR} 下的 dSYM（version=${VERSION}, platform=IOS）"
"${JAVA}" -jar "${JAR}" \
  -appid "${APPID}" \
  -appkey "${KEY}" \
  -version "${VERSION}" \
  -platform IOS \
  -inputSymbol "${SYMBOL_DIR}"
RC=$?

if [ "${RC}" -eq 0 ]; then
  echo
  echo "完成：符号表已上传（version=${VERSION}）。"
  exit 0
fi

if [ "${MODE}" = "build" ]; then
  echo "warning: 符号表上传失败（exit ${RC}），不影响本次构建"
  exit 0
fi
echo "error: 符号表上传失败（exit ${RC}）" >&2
exit "${RC}"
