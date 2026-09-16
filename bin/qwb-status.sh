#!/usr/bin/env bash
# qwb-status.sh —— 点名 + 汇报：读账本列出全部任务与状态，合并 herdr 窗口/状态输出
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-status.sh [选项]

读 tasks/ 账本，逐份任务书打印 state 与最近一条状态行；有未决规格疑点
（最后一个 spec-defect:/spec-resolved: 相关事件是 blocked: spec-defect:，与
qwb-run.sh 疑点门同判定）的额外标注一行「规格疑点未处理」——后续普通状态行
遮不住它。若本机有 herdr，附带 agent / pane 窗口状态。账本为空也正常退出（退出码 0）。

选项:
  --project <根>    项目根（默认：当前目录）
  -h, --help        显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"

echo "== 账本：$LEDGER =="
shopt -s nullglob
files=("$LEDGER"/*.md)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "（无任务书）"
else
  for f in "${files[@]}"; do
    grep -q '^state:' "$f" || continue   # 无 state 字段行 → 非任务书（如 lessons.md），跳过
    name="$(basename "$f")"
    st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
    case "$st" in
      running|blocked|needs-decision) mark="未结" ;;
      done|verified) mark="已结" ;;
      *) mark="非法" ;;
    esac
    last="$(grep -E '^(working|done|blocked|needs-decision|wake|dispatch):' "$f" 2>/dev/null | tail -1 || true)"
    if [[ "$mark" == "非法" ]]; then
      printf '[非法] %-40s state=%s —— 该任务不会被值守叫醒\n' "$name" "$st"
    else
      printf '[%s] %-40s state=%s\n' "$mark" "$name" "$st"
    fi
    [[ -n "$last" ]] && printf '       最近: %s\n' "$last"
    # 规格疑点未处理：与 qwb-run.sh 疑点门同判定——最后一个相关事件（spec-defect:/spec-resolved:）
    # 是 spec-defect: 即未决；普通状态行不参与判定，疑点不会被后续 working:/done:/dispatch: 行遮住
    spev="$(grep -E '^blocked:[[:space:]]*spec-defect:|^working:[[:space:]]*spec-resolved:' "$f" 2>/dev/null | tail -1 || true)"
    if printf '%s' "$spev" | grep -qE '^blocked:[[:space:]]*spec-defect:'; then
      printf '       规格疑点未处理: %s\n' "$spev"
    fi
  done
fi

echo
echo "== 值守 =="
# 值守健康复用 qwb-wake.sh --check 的同一判定：真查 herdr 前台进程，pane 存在不算健康，查不到明说未知
WAKE_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-wake.sh"
if [[ -f "$WAKE_BIN" ]]; then
  bash "$WAKE_BIN" --project "$PROJECT_ROOT" --check
else
  echo "值守：未知（缺 qwb-wake.sh，无法判定）"
fi

echo
echo "== Herdr 窗口 =="
if command -v herdr >/dev/null 2>&1; then
  herdr agent list 2>/dev/null || echo "（herdr agent list 失败：无运行中的 server 或无 agent）"
else
  echo "（herdr 不在 PATH，仅列账本）"
fi
exit 0
