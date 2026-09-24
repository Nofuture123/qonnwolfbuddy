#!/usr/bin/env bash
# 真实主控/工人闭环；人工按候选 SHA 触发，不纳入 fast/full。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: bash tests/e2e-real.sh --worker devin|cmdc [--controller-model gpt-6-luna] [--controller-effort max] [--timeout-ms 2700000] [--report <新文件>] [--keep]

前提：Herdr pane 内运行；codex 与所选工人 CLI 已登录。会真实调用模型并产生花费。
脚本在隔离 /tmp Git 项目与新 named Herdr session 运行；可在另一终端用
  herdr --session <脚本输出的会话名>
附着旁观。默认结束时 stop/delete 会话；--keep 保留会话供排障。报告文件必须不存在。
EOF
}

WORKER=""; MODEL=gpt-6-luna; EFFORT=max; TIMEOUT_MS=2700000; REPORT=""; KEEP=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --worker) WORKER="${2:-}"; shift 2 ;;
    --controller-model) MODEL="${2:-}"; shift 2 ;;
    --controller-effort) EFFORT="${2:-}"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="${2:-}"; shift 2 ;;
    --report) REPORT="${2:-}"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ "$WORKER" == devin || "$WORKER" == cmdc ]] || { echo "错误：--worker 只接受 devin|cmdc" >&2; exit 2; }
[[ "$TIMEOUT_MS" =~ ^[1-9][0-9]*$ ]] || { echo "错误：--timeout-ms 须为正整数" >&2; exit 2; }
[[ "${HERDR_ENV:-}" == 1 ]] || { echo "错误：须从 Herdr pane 运行真实 E2E" >&2; exit 1; }
command -v herdr >/dev/null && command -v codex >/dev/null && command -v "$WORKER" >/dev/null \
  || { echo "错误：缺少 Herdr、Codex 或所选工人 CLI" >&2; exit 1; }

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SHA="$(git -C "$ROOT" rev-parse HEAD)"
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "错误：候选工作区不干净，先冻结 SHA" >&2; exit 1; }
if [[ -z "$REPORT" ]]; then REPORT="/tmp/qwb-e2e-${WORKER}-${SHA:0:7}-$(date +%s).md"; fi
[[ ! -e "$REPORT" && ! -L "$REPORT" && -d "$(dirname "$REPORT")" ]] \
  || { echo "错误：报告路径必须尚不存在且父目录存在：$REPORT" >&2; exit 2; }
REPORT="$(cd "$(dirname "$REPORT")" && pwd -P)/$(basename "$REPORT")"
BASE="$(mktemp -d "/tmp/qwb-e2e-${WORKER}.XXXXXXXX")"
SESSION="qwb-e2e-${WORKER}-$(date +%s)-$$"
SOCKET="$HOME/.config/herdr/sessions/$SESSION/herdr.sock"
SERVER_PID=""
case "$WORKER" in
  devin) WORKER_MODEL=swe-2-max ;;
  cmdc) WORKER_MODEL=deepseek/deepseek-v4-flash ;;
esac
CODEX_VERSION="$(codex --version)" || { echo "错误：当前 Herdr pane 无法读取 Codex 版本" >&2; exit 1; }
echo "真实 E2E：worker=${WORKER}；主控 ${MODEL}/${EFFORT}；工人模型=${WORKER_MODEL}"
echo "会话：${SESSION}（旁观：herdr --session ${SESSION}）"
echo "候选：${SHA}；临时目录：${BASE}；报告：${REPORT}"

cleanup() {
  local rc=$? stop_rc=0 delete_rc=0
  trap - EXIT
  if [[ "$KEEP" -eq 0 ]]; then
    if [[ -n "$SERVER_PID" ]]; then
      status="$(herdr status server 2>/dev/null || true)"
      [[ "$status" == *"socket: $SOCKET"* ]] || echo "警告：会话 socket 身份未能确认，仍按名字只清理本次会话 ${SESSION}" >&2
      herdr session stop "$SESSION" > "$BASE/session-stop.log" 2>&1 || stop_rc=$?
      herdr session delete "$SESSION" > "$BASE/session-delete.log" 2>&1 || delete_rc=$?
      wait "$SERVER_PID" 2>/dev/null || true
    fi
    echo "会话清理：stop rc=${stop_rc}，delete rc=${delete_rc}"
    [[ "$stop_rc" -eq 0 && "$delete_rc" -eq 0 ]] || rc=1
  else
    echo "会话保留：${SESSION}（--keep）"
  fi
  if [[ -f "$REPORT" ]]; then
    printf '\n- 会话清理：%s；stop rc=%s；delete rc=%s\n' \
      "$(if [[ "$KEEP" -eq 1 ]]; then echo 保留; else echo 已请求停止和删除; fi)" "$stop_rc" "$delete_rc" >> "$REPORT"
  fi
  exit "$rc"
}
trap cleanup EXIT

# 子进程只看 named session；不复用当前 pane 的动态身份。
unset HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID
export HERDR_SOCKET_PATH="$SOCKET"
herdr --session "$SESSION" server > "$BASE/server.log" 2>&1 &
SERVER_PID=$!
ready=0
for _ in {1..80}; do
  status="$(herdr status server 2>/dev/null || true)"
  if [[ "$status" == *"status: running"* && "$status" == *"socket: $SOCKET"* ]]; then ready=1; break; fi
  sleep 0.25
done
[[ "$ready" -eq 1 ]] || { echo "错误：named Herdr server 未就绪：$SOCKET" >&2; exit 1; }

export QWB_E2E_ROOT="$ROOT" QWB_E2E_SHA="$SHA" QWB_E2E_BASE="$BASE"
export QWB_E2E_SESSION="$SESSION" QWB_E2E_SOCKET="$SOCKET" QWB_E2E_WORKER="$WORKER"
export QWB_E2E_MODEL="$MODEL" QWB_E2E_EFFORT="$EFFORT" QWB_E2E_TIMEOUT_MS="$TIMEOUT_MS" QWB_E2E_REPORT="$REPORT"
export QWB_E2E_CODEX_VERSION="$CODEX_VERSION"
python3 -B "$ROOT/tests/e2e-real.py"
