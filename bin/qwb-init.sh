#!/usr/bin/env bash
# qwb-init.sh —— 把 QW buddy 装进一个项目（幂等：已装过不重复追加）
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-init.sh <项目根目录>

把 templates/ 与 bin/ 装进 <项目>/qwbuddy/，建 tasks/ 与 tasks/lessons/，
并把钩子片段追加进 AGENTS.md / CLAUDE.md（幂等，可重复运行）。

选项:
  -h, --help    显示本帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

[[ -d "$1" ]] || { echo "错误：项目目录不存在：$1" >&2; exit 1; }
ROOT="$(cd "$1" && pwd)"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SRC/../templates"

[[ -d "$TPL" ]] || { echo "错误：找不到模板目录 ${TPL}（请从 QW buddy 母本仓运行本脚本）" >&2; exit 1; }

mkdir -p "$ROOT/qwbuddy/roles" "$ROOT/qwbuddy/bin" "$ROOT/tasks/lessons"

cp "$TPL/QWBUDDY.md" "$ROOT/qwbuddy/QWBUDDY.md"
cp "$TPL"/roles/*.md "$ROOT/qwbuddy/roles/"

# config.json 可能被主控填过 controller.pane_id——已存在就不覆盖
if [[ -f "$ROOT/qwbuddy/config.json" ]]; then
  echo "保留：qwbuddy/config.json 已存在，不覆盖"
else
  cp "$TPL/config.json" "$ROOT/qwbuddy/config.json"
fi

cp "$SRC"/qwb-*.sh "$ROOT/qwbuddy/bin/"
chmod +x "$ROOT/qwbuddy/bin"/qwb-*.sh

# 钩子：已含 qwbuddy/QWBUDDY.md 引用视为已装，跳过
append_hook() {
  local target="$1" hook="$2"
  if [[ -f "$target" ]] && grep -qF 'qwbuddy/QWBUDDY.md' "$target"; then
    echo "跳过：$(basename "$target") 已有 QW buddy 钩子"
  else
    { echo; cat "$TPL/$hook"; } >> "$target"
    echo "写入：$(basename "$target") 追加 QW buddy 钩子"
  fi
}

append_hook "$ROOT/AGENTS.md" agents-hook.md
append_hook "$ROOT/CLAUDE.md" claude-hook.md

echo "完成：QW buddy 已装进 ${ROOT}（账本：${ROOT}/tasks/）"
