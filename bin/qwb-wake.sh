#!/usr/bin/env bash
# qwb-wake.sh —— 值守：以账本未结项为准，叫醒主控窗口；同一项不重复叫
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-wake.sh [选项]

循环：读账本列未结项 → 有未结项且未叫过 → herdr pane run 叫醒主控 → 等事件或超时 → 再来。
未结项 = 任务书头部 state ∈ {running, blocked, needs-decision}。
去重：叫过一次在任务书追加 wake: <时间戳> state=<值>；state 未变不再叫。

选项:
  --project <根>      项目根（默认：当前目录）
  --pane <pane_id>    主控 pane（默认：$QWB_CONTROLLER_PANE 或 config.json controller.pane_id）
  --interval <毫秒>   事件等待的超时（默认：config.json timeouts.wake_interval_ms，否则 120000）
  --once              只检查一轮就退出
  --dry-run           只报告未结项，不叫、不写 wake 行
  -h, --help          显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"; PANE="${QWB_CONTROLLER_PANE:-}"; INTERVAL=""; ONCE=0; DRY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --pane) PANE="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
CONF="$PROJECT_ROOT/qwbuddy/config.json"

if [[ "$DRY" -eq 0 ]]; then
  command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令，无法叫醒主控" >&2; exit 1; }
fi
if [[ -z "$INTERVAL" && -f "$CONF" ]]; then
  INTERVAL="$(sed -n 's/.*"wake_interval_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$CONF" | head -1)"
fi
INTERVAL="${INTERVAL:-120000}"
if [[ -z "$PANE" && -f "$CONF" ]]; then
  PANE="$(sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$CONF" | head -1)"
fi

# 未结项：输出「文件<TAB>state」
open_items() {
  local f st
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
    case "$st" in
      running|blocked|needs-decision) printf '%s\t%s\n' "$f" "$st" ;;
    esac
  done
}

# 最近一次 wake 行记录的 state（没有则为空）
last_wake_state() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/.*state=\([^[:space:]]*\).*/\1/p' || true
}

check_round() {
  local f st lw need=0 ids=""
  while IFS=$'\t' read -r f st; do
    ids="$ids $(basename "$f" .md)($st)"
    lw="$(last_wake_state "$f")"
    if [[ "$lw" == "$st" ]]; then
      echo "跳过：$(basename "$f") state=${st}（已叫过，状态未变）"
      continue
    fi
    need=1
    if [[ "$DRY" -eq 1 ]]; then
      echo "未结项（将叫醒）: $(basename "$f") state=$st"
    else
      [[ -n "$PANE" ]] || { echo "错误：有未结项但不知道主控 pane（--pane / QWB_CONTROLLER_PANE / config.json controller.pane_id）" >&2; exit 1; }
      herdr pane run "$PANE" "看账本：未结项待处理 →$(printf '%s' "$ids")。请读 tasks/ 继续处理。"
      printf 'wake: %s state=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$st" >> "$f"
      echo "已叫醒：$(basename "$f") state=${st} → pane ${PANE}"
    fi
  done < <(open_items)
  [[ "$need" -eq 0 && -z "$ids" ]] && echo "账本无未结项"
}

wait_round() {
  # 事件：对未结项 dispatch 行里记录的工人 pane 做 agent wait；没有则纯超时兜底
  local p
  p="$(grep -h '^dispatch:' "$LEDGER"/*.md 2>/dev/null | grep -o 'pane=[^[:space:]]*' | head -1 | cut -d= -f2 || true)"
  if [[ -n "$p" ]]; then
    herdr agent wait "$p" --timeout "$INTERVAL" >/dev/null 2>&1 || true
  else
    sleep "$(( INTERVAL / 1000 > 0 ? INTERVAL / 1000 : 1 ))"
  fi
}

while :; do
  check_round
  [[ "$ONCE" -eq 1 || "$DRY" -eq 1 ]] && exit 0
  wait_round
done
