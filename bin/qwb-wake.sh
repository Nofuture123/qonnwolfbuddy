#!/usr/bin/env bash
# qwb-wake.sh —— 值守：以账本未结项为准，叫醒主控窗口；同一项进展未变不重复叫
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-wake.sh [选项]

循环：读账本列未结项 → 有未结项且进展指纹已变 → herdr pane run 叫醒主控 → 等事件或超时 → 再来。
未结项 = 任务书头部 state ∈ {running, blocked, needs-decision}。
去重：fp = sha1(state 值 + "\n" + 最后一条 working:/done:/blocked:/needs-decision: 行原文，无则空串)；
     叫醒后写 wake: <时间戳> state=<值> fp=<sha1>。fp 未变不再叫；无 fp= 的旧 wake 行视为指纹不同。
投递失败：不写 wake 行、报 stderr、继续处理下一项；值守主循环不因单次投递失败退出。
等待：只取未结项任务书里时间戳最新的 dispatch: pane 做 agent wait；一轮预算 = 1×interval，
     等待耗时计入预算——超时路径（已耗 ≥半个 interval）直接下轮再扫；仅立即失败（耗时≈0）
     或无可用 pane 才 sleep 一个间隔，不得忙循环。

选项:
  --project <根>      项目根（默认：当前目录）
  --pane <pane_id>    主控 pane（默认：$QWB_CONTROLLER_PANE 或 config.sh QWB_CONTROLLER_PANE）
  --interval <毫秒>   事件等待的超时（默认：config.sh QWB_WAKE_INTERVAL_MS，否则 120000）
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
CONF="$PROJECT_ROOT/qwbuddy/config.sh"

if [[ "$DRY" -eq 0 ]]; then
  command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令，无法叫醒主控" >&2; exit 1; }
fi
# 配置唯一来源是 bash 文件：直接 source（PANE 已被 --pane/环境变量占上则不覆盖）
# shellcheck source=/dev/null
if [[ -f "$CONF" ]]; then . "$CONF"; fi
INTERVAL="${INTERVAL:-${QWB_WAKE_INTERVAL_MS:-120000}}"
PANE="${PANE:-${QWB_CONTROLLER_PANE:-}}"

# 未结项：输出「文件<TAB>state」。state 不在 5 值域 → stderr 警告（不算未结项，但必须说出来）。
# 无 state: 字段行的文件（如 tasks/lessons.md）不算任务书，跳过不警告。
open_items() {
  local f st
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    grep -q '^state:' "$f" || continue
    st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
    case "$st" in
      running|blocked|needs-decision) printf '%s\t%s\n' "$f" "$st" ;;
      done|verified) ;;
      *) echo "警告：$(basename "$f") state=${st} 非法（不在 5 值域内），不会被叫醒" >&2 ;;
    esac
  done
}

# 进展指纹 = sha1(state 值 + "\n" + 最后一条状态行原文，无则空串)
progress_fp() {
  local last
  last="$(grep -E '^(working|done|blocked|needs-decision):' "$1" 2>/dev/null | tail -1 || true)"
  printf '%s' "$2
${last}" | shasum | cut -d' ' -f1
}

# 最近一次 wake 行里的 fp（无 wake 行或解析不到 fp= 则为空 → 视为指纹不同）
last_wake_fp() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/.*fp=\([^[:space:]]*\).*/\1/p' || true
}

check_round() {
  local f st fp lwf ids=""
  while IFS=$'\t' read -r f st; do
    ids="$ids $(basename "$f" .md)($st)"
    fp="$(progress_fp "$f" "$st")"
    lwf="$(last_wake_fp "$f")"
    if [[ -n "$lwf" && "$lwf" == "$fp" ]]; then
      echo "跳过：$(basename "$f") state=${st}（已叫过，进展未变）"
      continue
    fi
    if [[ "$DRY" -eq 1 ]]; then
      echo "未结项（将叫醒）: $(basename "$f") state=$st"
    else
      [[ -n "$PANE" ]] || { echo "错误：有未结项但不知道主控 pane（--pane / QWB_CONTROLLER_PANE / config.sh QWB_CONTROLLER_PANE）" >&2; exit 1; }
      if herdr pane run "$PANE" "看账本：未结项待处理 →$(printf '%s' "$ids")。请读 tasks/ 继续处理。"; then
        printf 'wake: %s state=%s fp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$st" "$fp" >> "$f"
        echo "已叫醒：$(basename "$f") state=${st} → pane ${PANE}"
      else
        echo "错误：投递失败（pane ${PANE}）：$(basename "$f") 不写 wake 行、保持未叫，下轮重试" >&2
      fi
    fi
  done < <(open_items)
  if [[ -z "$ids" ]]; then
    echo "账本无未结项"
  fi
  return 0
}

sleep_interval() {
  sleep "$(( INTERVAL / 1000 > 0 ? INTERVAL / 1000 : 1 ))"
}

wait_round() {
  # 事件：只对未结项任务书取 dispatch 行、用时间戳最新的一条做 agent wait；
  # 无可用 pane → 按 interval sleep 退化等待，不得忙循环
  local f st disp p=""
  disp="$(
    while IFS=$'\t' read -r f st; do
      grep -h '^dispatch:' "$f" 2>/dev/null || true
    done < <(open_items) | sort | tail -1
  )"
  if [[ -n "$disp" ]]; then
    p="$(printf '%s' "$disp" | grep -o 'pane=[^[:space:]]*' | head -1 | cut -d= -f2)"
  fi
  if [[ -n "$p" ]]; then
    # 一轮预算 = 1×interval：等待本身耗掉的时间计入预算。
    # 耗掉 ≥ 半个 interval 视为超时路径 → 直接下轮扫描不再 sleep；
    # 只有立即失败（耗时≈0，如 pane 不存在）才 sleep 一个间隔防忙循环。
    local t0 dt
    t0="$(date +%s)"
    if ! herdr agent wait "$p" --timeout "$INTERVAL" >/dev/null 2>&1; then
      dt=$(( $(date +%s) - t0 ))
      if (( dt * 2000 < INTERVAL )); then sleep_interval; fi
    fi
  else
    sleep_interval
  fi
}

while :; do
  check_round
  if [[ "$ONCE" -eq 1 || "$DRY" -eq 1 ]]; then
    exit 0
  fi
  wait_round
done
