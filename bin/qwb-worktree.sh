#!/usr/bin/env bash
# qwb-worktree.sh —— worktree 清点与收尾：list 标出残留；finish 按 --merged/--archive/--keep 收尾并记账
# 收尾前提：该 worktree 的写入者（工人/agent）已停止写入。删前复核与删除是两次 Git 调用，
# 之间的窗口在 Git 层面无法封死——无法确认写入者已停时，先确认再收尾。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-worktree.sh <list|finish> [参数] [选项]

  list                      列出 <项目>/.worktrees/ 下的目录：
                            「未结项」= 账本中有对应 state ∈ {running,blocked,needs-decision} 的任务书；
                            「残留」  = 账本中无对应未结项任务书（建议用 finish 收掉）。
  finish <任务id> <动作>    收尾 <项目>/.worktrees/<任务id>，并往该任务书追加
                            worktree: <动作> branch=<分支> tag=<标签> 记账行：
    --merged        先核实真落地（worktree 当前 HEAD OID 并入当前 HEAD，或顶端已含于某个
                    remote-tracking refs/remotes/*/<实际分支>）；核实不通过则拒绝，不盲删。
                    通过 → git worktree remove + git branch -d（detached HEAD 时无分支可删）。
    --archive       打 git tag archive/<任务id>（指向 worktree 当前 HEAD OID）
                    → git worktree remove + git branch -D；detached HEAD 时只打 tag、
                    删 worktree，不删同名分支（它指向别的东西，不指向本工作区）。
    --keep[=原因]   不动 git，只在任务书点名保留及原因（不做脏检查——规范允许留冲突待解的）。
  --merged / --archive 先检查 worktree 有无未提交改动/未跟踪文件：有则拒绝（不做 --force，
  先提交或清理再来）；git status 本身失败也拒绝，不当干净放行。且每个删除动作前都复核
  worktree 实际 HEAD 仍是开头读到的那个提交；已被推进则拒绝（--archive 已打的 tag 保留）。

前提：收尾前确认该 worktree 的写入者已停止——删前复核与删除是两次 Git 调用，之间
  仍有窗口（Git 层面无法封死）；窗口内的新提交会成为未引用对象（dangling），可用
  git fsck --lost-found 找回。无法确认写入者已停时，先确认再收尾。

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

# 任务id → 账本中唯一任务书（记账落点；0 或多份都返回 1）。
# 与 qwb-run.sh 同款：先找「文件名去日期前缀与 .md 后 == 给定 id」的精确命中，恰好一份就用它；
# 没有精确命中才退回子串匹配（否则 --task foo 会撞上 foo-bar 两份）。
unique_task_for() {
  local f exact=() hits=()
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f" .md | sed 's/^[0-9][0-9-]*-//')" == "$1" ]] && exact+=("$f")
  done
  if [[ ${#exact[@]} -eq 1 ]]; then
    printf '%s' "${exact[0]}"
    return 0
  fi
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

# 一切判断与归档以 worktree 当前 HEAD 的实际提交 OID 为准，不得拿同名分支当本工作区的工作
if ! BRANCH="$(git -C "$WT_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null)"; then
  # 分支身份读取失败不得回退成任务 id——身份未知不删东西（仅 --keep 不动 git，可继续记账）
  [[ "$ACTION" == "keep" ]] \
    || { echo "错误：无法读取 ${WT_DIR} 的分支身份（非 git worktree？），拒绝收尾" >&2; exit 1; }
  BRANCH=""
fi
HEAD_OID="$(git -C "$WT_DIR" rev-parse HEAD 2>/dev/null || true)"
DETACHED=0
if [[ "$BRANCH" == "HEAD" ]]; then
  DETACHED=1; BRANCH=""
elif [[ -z "$BRANCH" ]]; then
  BRANCH="$TASK_ID"
elif [[ "$BRANCH" != "$TASK_ID" ]]; then
  echo "提示：worktree 目录名 ${TASK_ID} 与实际分支 ${BRANCH} 不一致，以实际分支为准" >&2
fi

# 脏检查只对真要删东西的动作；--keep 不动 git，不做脏检查（规范允许留冲突待解的）
if [[ "$ACTION" != "keep" ]]; then
  [[ -n "$HEAD_OID" ]] || { echo "错误：无法读取 ${WT_DIR} 的 HEAD（非 git worktree 或无提交），拒绝收尾" >&2; exit 1; }
  if ! DIRTY="$(git -C "$WT_DIR" status --porcelain 2>&1)"; then
    echo "拒绝：git status 失败，无法确认 ${WT_DIR} 工作区状态，不当干净放行：" >&2
    printf '%s\n' "$DIRTY" >&2
    exit 1
  fi
  if [[ -n "$DIRTY" ]]; then
    echo "拒绝：${WT_DIR} 有未提交改动/未跟踪文件，先提交或清理（本脚本不做 --force）：" >&2
    printf '%s\n' "$DIRTY" >&2
    exit 1
  fi
fi

# 删除的正当性必须在「即将删除的那一刻」成立：每个破坏性动作前复核实际 HEAD
recheck_head() {   # 打印 worktree 当前实际 HEAD OID；读不到返回非 0
  git -C "$WT_DIR" rev-parse HEAD 2>/dev/null
}
check_unchanged() {
  local cur
  cur="$(recheck_head)" || { echo "错误：无法读取 ${WT_DIR} 的当前 HEAD，拒绝收尾" >&2; exit 1; }
  [[ "$cur" == "$HEAD_OID" ]] || {
    echo "拒绝：收尾期间 ${WT_DIR} 的实际 HEAD 已变化，工作已被推进。" >&2
    echo "  原 OID：  ${HEAD_OID}" >&2
    echo "  当前 OID：${cur}" >&2
    echo "${1:-未执行任何删除，}请重新收尾。" >&2
    exit 1
  }
}
# worktree 删掉之后复核分支：refs/heads/<分支> 仍指着已核实/已归档的 OID 才准删
branch_tip_unchanged() {
  local cur
  cur="$(git -C "$PROJECT_ROOT" rev-parse "refs/heads/$BRANCH" 2>/dev/null)" || return 1
  [[ "$cur" == "$HEAD_OID" ]] || {
    echo "提示：分支 ${BRANCH} 顶端已推进（${HEAD_OID} → ${cur}），不删该分支" >&2
    return 1
  }
}
# 删前复核与删除仍是两次独立 Git 调用，之间窗口在 Git 层面无法封死（detached HEAD 上的
# 新提交不更新任何 ref，任何检查都读不到）；但窗口内对象不消失，可 fsck 找回。
race_note() {
  echo "注意：删前复核与删除是两次 Git 调用，之间仍有窗口（Git 层面无法封死）；"
  echo "      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），"
  echo "      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。"
}

BL="$BRANCH"
if [[ "$DETACHED" -eq 1 ]]; then BL="detached"; fi
TAG="-"
case "$ACTION" in
  merged)
    landed=""
    if git -C "$PROJECT_ROOT" merge-base --is-ancestor "$HEAD_OID" HEAD 2>/dev/null; then
      landed="已合并进当前分支（HEAD）"
    elif [[ "$DETACHED" -eq 0 ]]; then
      while IFS= read -r rt; do
        if git -C "$PROJECT_ROOT" merge-base --is-ancestor "$HEAD_OID" "$rt" 2>/dev/null; then
          landed="已推送（分支顶端含于 ${rt}）"; break
        fi
      done < <(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname:short)' "refs/remotes/*/${BRANCH}")
    fi
    if [[ -z "$landed" ]]; then
      echo "拒绝：${WT_DIR} 当前 HEAD（${HEAD_OID}）未合并进当前分支${BRANCH:+，分支 ${BRANCH} 顶端也不在已知 remote-tracking 分支里}——无法核实已落地，不盲删。" >&2
      echo "确已落地请先 git fetch / 合并；要废弃请改用 --archive。" >&2
      exit 1
    fi
    check_unchanged    # 核实通过≠此刻仍是同一提交：删 worktree 前复核
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR"
    if [[ "$DETACHED" -eq 1 ]]; then
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（detached HEAD ${HEAD_OID}，无分支可删）"
    elif branch_tip_unchanged; then
      git -C "$PROJECT_ROOT" branch -d "$BRANCH"
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（删除依据 OID ${HEAD_OID}），分支 ${BRANCH} 已删"
    else
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（删除依据 OID ${HEAD_OID}）；保留分支 ${BRANCH}（收尾期间已被推进或不存在，未删）"
    fi
    race_note
    ;;
  archive)
    TAG="archive/$TASK_ID"
    # 标签打向「即将打的那一刻」的实际 HEAD：收尾期间若已被推进，以当前真实提交为准
    cur="$(recheck_head)" || { echo "错误：无法读取 ${WT_DIR} 的当前 HEAD，拒绝收尾" >&2; exit 1; }
    if [[ "$cur" != "$HEAD_OID" ]]; then
      echo "提示：收尾期间 ${WT_DIR} 的 HEAD 已推进（${HEAD_OID} → ${cur}），标签将指向当前提交" >&2
      HEAD_OID="$cur"
    fi
    git -C "$PROJECT_ROOT" tag "$TAG" "$HEAD_OID"
    check_unchanged "标签 ${TAG}（→ ${HEAD_OID}）已打且保留；"   # tag 后到删之前再被推进 → 只留标签不删
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR"
    if [[ "$DETACHED" -eq 1 ]]; then
      kept=""
      if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
        kept="；保留分支 ${TASK_ID}（它不指向本工作区）"
      fi
      echo "已归档：tag ${TAG} → detached HEAD ${HEAD_OID}；worktree 已删${kept}"
    elif branch_tip_unchanged; then
      git -C "$PROJECT_ROOT" branch -D "$BRANCH"
      echo "已归档：tag ${TAG} → ${HEAD_OID}（分支 ${BRANCH} 顶端）；worktree 已删，分支已删（-D）"
    else
      echo "已归档：tag ${TAG} → ${HEAD_OID}；worktree 已删；保留分支 ${BRANCH}（收尾期间已被推进或不存在，未删）"
    fi
    race_note
    ;;
  keep)
    echo "已保留：worktree ${WT_DIR} 原样不动，原因记入任务书${REASON:+：${REASON}}"
    ;;
esac

line="worktree: ${ACTION} branch=${BL} tag=${TAG}"
[[ -n "$REASON" ]] && line="${line} reason=${REASON}"
printf '%s\n' "$line" >> "$TASK_FILE"
echo "已记账：$(basename "$TASK_FILE") ← ${line}"
