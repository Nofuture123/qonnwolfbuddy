#!/usr/bin/env bash
# qwb-run.sh —— 派发 + 记账：在指定 worktree/窗口里派活，把窗口、派发时间、state: running 写进任务书
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-run.sh --task <任务id或任务书路径> --worker <工人名> [选项]

必选:
  --task <id|路径>      任务书 id（如 qwbuddy-mvp）或文件路径
  --worker <名>         工人名（对应 config.json workers 表，如 codex/pi/claude）

选项:
  --project <根>        项目根（默认：当前目录）
  --worktree <路径>     在既有 worktree 目录里派活（新窗口的 cwd）
  --create-worktree     先开 <根>/.worktrees/<任务id>（git worktree add）
  --pane <pane_id>      复用既有 pane（须为交互 shell），否则新开 herdr tab
  --name <agent名>      工人 agent 名（默认：qwb-<任务id>）
  -h, --help            显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"; TASK=""; WORKER=""; WORKTREE=""; CREATE_WT=0; PANE=""; NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --task) TASK="$2"; shift 2 ;;
    --worker) WORKER="$2"; shift 2 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --worktree) WORKTREE="$2"; shift 2 ;;
    --create-worktree) CREATE_WT=1; shift ;;
    --pane) PANE="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$TASK" && -n "$WORKER" ]] || { echo "错误：--task 与 --worker 必选" >&2; usage >&2; exit 2; }
command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令" >&2; exit 1; }
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
CONF="$PROJECT_ROOT/qwbuddy/config.json"

# 定位任务书：路径直接用；id 在 tasks/ 里唯一匹配
if [[ -f "$TASK" ]]; then
  TASK_FILE="$(cd "$(dirname "$TASK")" && pwd)/$(basename "$TASK")"
else
  hits=()
  for f in "$LEDGER"/*"$TASK"*.md; do [[ -e "$f" ]] && hits+=("$f"); done
  [[ ${#hits[@]} -eq 1 ]] || { echo "错误：任务 '${TASK}' 在 ${LEDGER} 匹配到 ${#hits[@]} 份（要唯一）" >&2; exit 1; }
  TASK_FILE="${hits[0]}"
fi
# 任务 id = 文件名去日期前缀与扩展名
TASK_ID="$(basename "$TASK_FILE" .md | sed 's/^[0-9][0-9-]*-//')"
[[ -n "$TASK_ID" ]] || TASK_ID="$(basename "$TASK_FILE" .md)"

# 工人须在 config.json workers 表里（herdr kind 与工人同名）
[[ -f "$CONF" ]] || { echo "错误：找不到 ${CONF}（先跑 qwb-init.sh）" >&2; exit 1; }
grep -q "\"$WORKER\"" "$CONF" || { echo "错误：工人 '$WORKER' 不在 config.json workers 表里" >&2; exit 1; }
START_MS="$(sed -n 's/.*"agent_start_ms"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$CONF" | head -1)"
START_MS="${START_MS:-30000}"

# 主控锁：防两个主控同时动手。无锁→获取；他人持锁→拒绝派发；自己持有的锁可重复派发。
LOCK_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lock.sh"
LOCK_DIR="$PROJECT_ROOT/qwbuddy/.controller.lock"
SELF="${HERDR_PANE_ID:-pid:$$}"
[[ -f "$LOCK_BIN" ]] || { echo "错误：找不到 ${LOCK_BIN}" >&2; exit 1; }
if ! bash "$LOCK_BIN" acquire --project "$PROJECT_ROOT" --owner "$SELF" >/dev/null 2>&1; then
  holder_id="$(sed -n 's/^[^ ]* //p' "$LOCK_DIR/owner" 2>/dev/null | head -1)"
  if [[ "$holder_id" != "$SELF" ]]; then
    echo "错误：主控锁被占用，锁主：$(cat "$LOCK_DIR/owner" 2>/dev/null || echo '（锁目录存在但无 owner 文件）')" >&2
    echo "确认是残留锁后手动释放：bash ${LOCK_BIN} release --project ${PROJECT_ROOT}" >&2
    exit 1
  fi
fi

# worktree：指定的必须存在；--create-worktree 则新建 <根>/.worktrees/<id>
if [[ "$CREATE_WT" -eq 1 ]]; then
  WORKTREE="$PROJECT_ROOT/.worktrees/$TASK_ID"
  mkdir -p "$PROJECT_ROOT/.worktrees"
  if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
    git -C "$PROJECT_ROOT" worktree add "$WORKTREE" "$TASK_ID"
  else
    git -C "$PROJECT_ROOT" worktree add -b "$TASK_ID" "$WORKTREE"
  fi
fi
DIR="$PROJECT_ROOT"
if [[ -n "$WORKTREE" ]]; then
  [[ -d "$WORKTREE" ]] || { echo "错误：worktree 不存在：$WORKTREE" >&2; exit 1; }
  DIR="$(cd "$WORKTREE" && pwd)"
fi

# 窗口：复用 --pane 或新开 tab（tab create 返回 JSON，pane id 在 .result.root_pane.pane_id）
if [[ -z "$PANE" ]]; then
  out="$(herdr tab create --cwd "$DIR" --label "$TASK_ID" --no-focus)"
  PANE="$(printf '%s' "$out" | sed -n 's/.*"pane_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$PANE" ]] || { echo "错误：herdr tab create 未返回 pane_id：$out" >&2; exit 1; }
fi

NAME="${NAME:-qwb-$TASK_ID}"
NAME="$(printf '%s' "$NAME" | cut -c1-32 | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9_-')"

herdr agent start "$NAME" --kind "$WORKER" --pane "$PANE" --timeout "$START_MS"

# 提示词：任务书绝对路径 + 主账本绝对路径 + 状态行规矩
herdr agent prompt "$NAME" "你是本任务的执行者。唯一规格来源：${TASK_FILE}（先完整读它，再读它点名的文档）。工作目录=${DIR}，代码改动只留在本目录。每完成一个阶段往主账本追加状态行（working:/done:/blocked:/needs-decision:），主账本=${TASK_FILE}——只追加，不改别人的行，不改 state: 字段。done: 必须附跑了什么检查与原始结果。写完状态行再收工。"

# 记账：state: running 写进头部字段行（只改第一处）；派发记录追加在末尾
tmp="$TASK_FILE.qwb.tmp"
if grep -q '^state:' "$TASK_FILE"; then
  awk '{ if (!done && $0 ~ /^state:/) { print "state: running"; done=1 } else print }' "$TASK_FILE" > "$tmp"
else
  { echo "state: running"; echo; cat "$TASK_FILE"; } > "$tmp"
fi
mv "$tmp" "$TASK_FILE"
printf 'dispatch: %s worker=%s agent=%s pane=%s dir=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WORKER" "$NAME" "$PANE" "$DIR" >> "$TASK_FILE"

echo "已派发：${TASK_ID} → ${WORKER}（agent=${NAME} pane=${PANE} dir=${DIR}）"
