#!/usr/bin/env bash
# qwb-worktree.sh —— worktree 清点与收尾：list 标出残留；finish 按 --merged/--archive/--keep 收尾并记账
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-worktree.sh <list|finish> [参数] [选项]

  list                      列出 <项目>/.worktrees/ 下的目录：
                            「未结项」= 账本中有对应 state ∈ {running,blocked,needs-decision} 的任务书；
                            「残留」  = 账本中无对应未结项任务书（建议用 finish 收掉）。
  finish <任务id> <动作>    收尾 <项目>/.worktrees/<任务id>，并往该任务书追加
                            worktree: <动作> branch=<分支> tag=<标签> 记账行：
    --merged        先核实真落地（分支并入当前 HEAD，或顶端已含于某个 remote-tracking
                    refs/remotes/*/<分支>）；核实不通过则拒绝，不盲删。
                    通过 → git worktree remove + git branch -d。
    --archive       打 git tag archive/<任务id>（指向分支顶端）
                    → git worktree remove + git branch -D。
    --keep[=原因]   不动 git，只在任务书点名保留及原因。
  三种动作都先检查 worktree 有无未提交改动/未跟踪文件：有则拒绝（不做 --force，
  先提交或清理再来）。--keep 也一样：留下的 worktree 不该藏看不见的未提交改动。

选项:
  --project <根>    项目根（默认：当前目录）
  -h, --help        显示本帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  list|finish) CMD="$1"; shift ;;
  *) echo "错误：需要子命令 list|finish" >&2; usage >&2; exit 2 ;;
esac

PROJECT_ROOT="$(pwd)"; TASK_ID=""; ACTION=""; REASON=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --merged|--archive) ACTION="${1#--}"; shift ;;
    --keep) ACTION="keep"; shift ;;
    --keep=*) ACTION="keep"; REASON="${1#--keep=}"; shift ;;
    -*) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
    *) if [[ -z "$TASK_ID" ]]; then TASK_ID="$1"; else echo "错误：多余参数 $1" >&2; exit 2; fi; shift ;;
  esac
done

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
WT_BASE="$PROJECT_ROOT/.worktrees"

task_state() { sed -n 's/^state:[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]'; }

# 任务id → 账本中有未结项 state 的任务书（无则返回 1）
open_task_for() {
  local f st
  for f in "$LEDGER"/*"$1"*.md; do
    [[ -e "$f" ]] || continue
    st="$(task_state "$f")"
    case "$st" in running|blocked|needs-decision) printf '%s' "$f"; return 0 ;; esac
  done
  return 1
}

# 任务id → 账本中唯一任务书（记账落点；0 或多份都返回 1）
unique_task_for() {
  local f hits=()
  for f in "$LEDGER"/*"$1"*.md; do [[ -e "$f" ]] && hits+=("$f"); done
  [[ ${#hits[@]} -eq 1 ]] || return 1
  printf '%s' "${hits[0]}"
}

if [[ "$CMD" == "list" ]]; then
  found=0
  for d in "$WT_BASE"/*; do
    [[ -d "$d" ]] || continue
    found=1
    id="$(basename "$d")"
    if tf="$(open_task_for "$id")"; then
      printf '未结项  %s  ← %s state=%s\n' "$d" "$(basename "$tf")" "$(task_state "$tf")"
    else
      printf '残留    %s（账本中无对应未结项任务书；建议 qwb-worktree.sh finish %s --merged|--archive|--keep）\n' "$d" "$id"
    fi
  done
  [[ "$found" -eq 0 ]] && echo "（${WT_BASE} 为空或不存在）"
  exit 0
fi

# finish
[[ -n "$TASK_ID" ]] || { echo "错误：finish 需要 <任务id>" >&2; usage >&2; exit 2; }
[[ -n "$ACTION" ]] || { echo "错误：finish 需要动作 --merged|--archive|--keep[=原因]" >&2; exit 2; }

TASK_FILE="$(unique_task_for "$TASK_ID")" \
  || { echo "错误：任务 '${TASK_ID}' 在 ${LEDGER} 匹配不到唯一任务书，记账无处可写" >&2; exit 1; }
WT_DIR="$WT_BASE/$TASK_ID"
[[ -d "$WT_DIR" ]] || { echo "错误：worktree 不存在：${WT_DIR}" >&2; exit 1; }

BRANCH="$(git -C "$WT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || BRANCH="$TASK_ID"

DIRTY="$(git -C "$WT_DIR" status --porcelain 2>/dev/null || true)"
if [[ -n "$DIRTY" ]]; then
  echo "拒绝：${WT_DIR} 有未提交改动/未跟踪文件，先提交或清理（本脚本不做 --force）：" >&2
  printf '%s\n' "$DIRTY" >&2
  exit 1
fi

TAG="-"
case "$ACTION" in
  merged)
    landed=""
    if git -C "$PROJECT_ROOT" merge-base --is-ancestor "$BRANCH" HEAD 2>/dev/null; then
      landed="已合并进当前分支（HEAD）"
    else
      while IFS= read -r rt; do
        if git -C "$PROJECT_ROOT" merge-base --is-ancestor "$BRANCH" "$rt" 2>/dev/null; then
          landed="已推送（分支顶端含于 ${rt}）"; break
        fi
      done < <(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' "refs/remotes/*/${BRANCH}")
    fi
    if [[ -z "$landed" ]]; then
      echo "拒绝：分支 ${BRANCH} 未合并进当前分支，顶端也不在已知 remote-tracking 分支里——无法核实已落地，不盲删。" >&2
      echo "确已落地请先 git fetch / 合并；要废弃请改用 --archive。" >&2
      exit 1
    fi
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR"
    git -C "$PROJECT_ROOT" branch -d "$BRANCH"
    echo "已收尾（${landed}）：worktree ${WT_DIR} 已删，分支 ${BRANCH} 已删"
    ;;
  archive)
    TAG="archive/$TASK_ID"
    git -C "$PROJECT_ROOT" tag "$TAG" "$BRANCH"
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR"
    git -C "$PROJECT_ROOT" branch -D "$BRANCH"
    echo "已归档：tag ${TAG} → 分支 ${BRANCH} 顶端；worktree 已删，分支已删（-D）"
    ;;
  keep)
    echo "已保留：worktree ${WT_DIR} 原样不动，原因记入任务书${REASON:+：${REASON}}"
    ;;
esac

line="worktree: ${ACTION} branch=${BRANCH} tag=${TAG}"
[[ -n "$REASON" ]] && line="${line} reason=${REASON}"
printf '%s\n' "$line" >> "$TASK_FILE"
echo "已记账：$(basename "$TASK_FILE") ← ${line}"
