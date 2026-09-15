#!/usr/bin/env bash
# qwb-status.sh —— 点名 + 汇报：读账本列出全部任务与状态，合并 herdr 窗口/状态输出
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-status.sh [选项]

读 tasks/ 账本，逐份任务书打印 state 与最近一条状态行；若本机有 herdr，
附带 agent / pane 窗口状态。账本为空也正常退出（退出码 0）。

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
    name="$(basename "$f")"
    st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
    st="${st:-无state字段}"
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
  done
fi

echo
echo "== Herdr 窗口 =="
if command -v herdr >/dev/null 2>&1; then
  herdr agent list 2>/dev/null || echo "（herdr agent list 失败：无运行中的 server 或无 agent）"
else
  echo "（herdr 不在 PATH，仅列账本）"
fi
exit 0
