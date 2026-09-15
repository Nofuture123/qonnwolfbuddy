#!/usr/bin/env bash
# qwb-test.sh —— 快门/全门执行器：读项目声明的 QWB_GATE_FAST/QWB_GATE_FULL，原样执行
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-test.sh <fast|full> [--project <根>]

执行项目声明的质量门：
  fast  快门（QWB_GATE_FAST）：快、无外部依赖，改一行跑它
  full  全门（QWB_GATE_FULL）：完整检查，合并前跑

配置来源（按序取第一个存在的）：
  <项目>/qwbuddy/config.sh    装过 QW buddy 的项目
  <项目>/qwb.config.sh        母本仓自用回退（母本仓是模板源，不给自己装 qwbuddy/）

门命令以 bash -c 在**项目根目录**下执行；stdout/stderr 原样转发，退出码透传。
门未声明时报错并给出正确写法；门失败时额外打印一行「门失败」到 stderr。

选项:
  --project <根>    项目根（默认：当前目录）
  -h, --help        显示本帮助
EOF
}

GATE=""; PROJECT_ROOT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    fast|full)
      [[ -z "$GATE" ]] || { echo "错误：门只能选一个（fast|full）" >&2; exit 2; }
      GATE="$1"; shift ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$GATE" ]] || { echo "错误：需要 <fast|full>" >&2; usage >&2; exit 2; }
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

CONF="$PROJECT_ROOT/qwbuddy/config.sh"
[[ -f "$CONF" ]] || CONF="$PROJECT_ROOT/qwb.config.sh"
[[ -f "$CONF" ]] || { echo "错误：找不到配置（试过 qwbuddy/config.sh 与 qwb.config.sh）：${PROJECT_ROOT}" >&2; exit 1; }

QWB_GATE_FAST=""; QWB_GATE_FULL=""
# shellcheck source=/dev/null
. "$CONF"

if [[ "$GATE" == "fast" ]]; then VAR="QWB_GATE_FAST"; CMD="$QWB_GATE_FAST"; else VAR="QWB_GATE_FULL"; CMD="$QWB_GATE_FULL"; fi

if [[ -z "$CMD" ]]; then
  cat >&2 <<EOF
错误：本项目尚未声明质量门（${CONF} 的 ${VAR} 为空/缺失）——请编辑 ${CONF} 填写 QWB_GATE_FAST / QWB_GATE_FULL（示例写法，命令在项目根下执行，按项目布局调路径）：
  QWB_GATE_FAST='for f in bin/*.sh tests/smoke.sh; do bash -n "\$f" || exit 1; done && shellcheck bin/*.sh'
  QWB_GATE_FULL="bash tests/smoke.sh && bash bin/qwb-lint.sh"
EOF
  exit 1
fi

cd "$PROJECT_ROOT"
rc=0
bash -c "$CMD" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "门失败（${GATE}）：${CMD} 退出码=${rc}" >&2
fi
exit "$rc"
