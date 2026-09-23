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
                    通过 → 安全关闭本票 Herdr Space、git worktree remove、按旧 OID 原子删分支。
    --archive       打 git tag archive/<任务id>（指向 worktree 当前 HEAD OID）
                    → 安全关闭本票 Space、git worktree remove、按旧 OID 原子删分支；detached HEAD 时只打 tag、
                    删 worktree，不删同名分支（它指向别的东西，不指向本工作区）。
    --keep[=原因]   不动 git，只在任务书点名保留及原因（不做脏检查——规范允许留冲突待解的）。
  --merged / --archive 先检查 worktree 有无未提交改动/未跟踪文件：有则拒绝（不做 --force，
  先提交或清理再来）；git status 本身失败也拒绝，不当干净放行。且每个删除动作前都复核
  worktree 实际 HEAD 仍是开头读到的那个提交；已被推进则拒绝（--archive 已打的 tag 保留）。
  有本票登记的 Herdr Space 时，须确认无活动工人或外来 tab 才关闭；查询未知或关闭失败不删 Git。

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
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
LEDGER="$PROJECT_ROOT/tasks"
WT_BASE="$PROJECT_ROOT/.worktrees"

LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整，请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

# 任务id → 账本中有未结项 state 的任务书（无则返回 1）
open_task_for() {
  local f st
  for f in "$LEDGER"/*"$1"*.md; do
    [[ -e "$f" ]] || continue
    st="$(qwb_task_state "$f")"
    case "$st" in running|blocked|needs-decision) printf '%s' "$f"; return 0 ;; esac
  done
  return 1
}

# 收尾记账只接受文件名去日期前缀与 .md 后恰好等于任务 id 的唯一任务书。
# 子串匹配可用于派发查找，但收尾不能借用相似名称的另一张任务书。
unique_task_for() {
  local f exact=()
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f" .md | sed 's/^[0-9][0-9-]*-//')" == "$1" ]] && exact+=("$f")
  done
  [[ ${#exact[@]} -eq 1 ]] || return 1
  printf '%s' "${exact[0]}"
}

if [[ "$CMD" == "list" ]]; then
  found=0
  for d in "$WT_BASE"/*; do
    [[ -d "$d" ]] || continue
    found=1
    id="$(basename "$d")"
    if tf="$(open_task_for "$id")"; then
      printf '未结项  %s  ← %s state=%s\n' "$d" "$(basename "$tf")" "$(qwb_task_state "$tf")"
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
case "$TASK_ID" in
  .|..|*/*|*\\*) echo "错误：任务 id 必须是单个目录名，不得含路径分隔符：${TASK_ID}" >&2; exit 2 ;;
esac

[[ -d "$LEDGER" && ! -L "$LEDGER" && -d "$WT_BASE" && ! -L "$WT_BASE" ]] \
  || { echo "错误：tasks 或 .worktrees 不存在或为符号链接，拒绝收尾" >&2; exit 1; }
LEDGER_PHYS="$(cd "$LEDGER" && pwd -P)"
WT_BASE_PHYS="$(cd "$WT_BASE" && pwd -P)"
[[ "$LEDGER_PHYS" == "$PROJECT_ROOT/tasks" && "$WT_BASE_PHYS" == "$PROJECT_ROOT/.worktrees" ]] \
  || { echo "错误：tasks 或 .worktrees 物理位置不在项目根下，拒绝收尾" >&2; exit 1; }

TASK_FILE="$(unique_task_for "$TASK_ID")" \
  || { echo "错误：任务 '${TASK_ID}' 在 ${LEDGER} 匹配不到唯一任务书，记账无处可写" >&2; exit 1; }
WT_DIR="$WT_BASE/$TASK_ID"
[[ -d "$WT_DIR" ]] || { echo "错误：worktree 不存在：${WT_DIR}" >&2; exit 1; }
[[ ! -L "$TASK_FILE" && ! -L "$WT_DIR" ]] \
  || { echo "错误：任务书或 worktree 是符号链接，拒绝收尾" >&2; exit 1; }
TASK_PHYS="$(cd "$(dirname "$TASK_FILE")" && pwd -P)/$(basename "$TASK_FILE")"
WT_PHYS="$(cd "$WT_DIR" && pwd -P)"
[[ "$TASK_PHYS" == "$LEDGER_PHYS/"* && "$WT_PHYS" == "$WT_BASE_PHYS/$TASK_ID" ]] \
  || { echo "错误：任务书或 worktree 物理位置越界，拒绝收尾" >&2; exit 1; }
WT_GIT_ROOT="$(git -C "$WT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [[ "$WT_GIT_ROOT" != "$WT_PHYS" ]] \
  || ! git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fxq "worktree $WT_PHYS"; then
  echo "错误：目标不是本项目登记的对应 worktree，拒绝收尾" >&2
  exit 1
fi

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
  cur="$(recheck_head)" || { echo "错误：无法读取 ${WT_DIR} 的当前 HEAD，拒绝收尾" >&2; return 1; }
  [[ "$cur" == "$HEAD_OID" ]] || {
    echo "拒绝：收尾期间 ${WT_DIR} 的实际 HEAD 已变化，工作已被推进。" >&2
    echo "  原 OID：  ${HEAD_OID}" >&2
    echo "  当前 OID：${cur}" >&2
    echo "${1:-未执行任何删除，}请重新收尾。" >&2
    return 1
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
branch_only_here() {
  [[ "$DETACHED" -eq 1 ]] && return 0
  local listing count
  listing="$(git -C "$PROJECT_ROOT" worktree list --porcelain)" \
    || { echo "拒绝：无法核对其他 worktree 是否检出分支 ${BRANCH}" >&2; return 1; }
  count="$(printf '%s\n' "$listing" | grep -Fxc "branch refs/heads/$BRANCH" || true)"
  [[ "$count" -eq 1 ]] \
    || { echo "拒绝：分支 ${BRANCH} 的 worktree 归属不唯一，删除前停止" >&2; return 1; }
}
# 删前复核与删除仍是两次独立 Git 调用，之间窗口在 Git 层面无法封死（detached HEAD 上的
# 新提交不更新任何 ref，任何检查都读不到）；但窗口内对象不消失，可 fsck 找回。
race_note() {
  echo "注意：删前复核与删除是两次 Git 调用，之间仍有窗口（Git 层面无法封死）；"
  echo "      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），"
  echo "      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。"
}

SPACE_ID=""
partial_fail() {
  local stage="$1"
  printf 'worktree: partial action=%s branch=%s tag=%s stage=%s space=%s\n' \
    "$ACTION" "${BRANCH:-detached}" "${TAG:--}" "$stage" "${SPACE_ID:--}" >> "$TASK_FILE" \
    || echo "警告：部分收尾记录写入失败：$TASK_FILE" >&2
  echo "错误：收尾停在 ${stage}；核对 Git worktree/分支与 Herdr Space 后再恢复，已保留现有引用" >&2
  exit 1
}

# Git 前置检查先于任何 Space 关闭；只关闭本票登记且没有活动写入者的 Space。
prepare_space_close() {
  local record root_tab record_path last_dispatch dispatch_path task_pane pane_out pane_meta worker_tab
  local tabs_out tab_ids tab_id panes_out pane_rows pane_id state proc
  SPACE_ID="$(qwb_worktree_space "$PROJECT_ROOT" "$WT_DIR")" || return 1
  [[ -n "$SPACE_ID" ]] || return 0
  record="$(grep '^worktree-space:' "$TASK_FILE" | tail -1 || true)"
  [[ -n "$record" ]] || { echo "拒绝：worktree Space ${SPACE_ID} 没有本票所有权记录；请手工关闭后重试" >&2; return 1; }
  [[ "$record" == "worktree-space: id=${SPACE_ID} root-tab="*" path="* ]] \
    || { echo "拒绝：worktree Space 所有权记录与当前 Space 不符" >&2; return 1; }
  root_tab="$(printf '%s\n' "$record" | sed -n 's/^worktree-space: id=[^ ]* root-tab=\([^ ]*\) path=.*/\1/p')"
  record_path="${record#* path=}"
  record_path="$(cd "$record_path" 2>/dev/null && pwd -P)" || record_path=""
  [[ -n "$root_tab" && "$record_path" == "$WT_PHYS" ]] \
    || { echo "拒绝：worktree Space 根 tab 或路径身份不符" >&2; return 1; }
  last_dispatch="$(grep '^dispatch:' "$TASK_FILE" | tail -1 || true)"
  worker_tab=""
  if [[ -n "$last_dispatch" ]]; then
    task_pane="$(printf '%s\n' "$last_dispatch" | sed -n 's/.* pane=\([^ ]*\) dir=.*/\1/p')"
    dispatch_path="$(cd "${last_dispatch##* dir=}" 2>/dev/null && pwd -P)" || dispatch_path=""
    [[ -n "$task_pane" && "$dispatch_path" == "$WT_PHYS" ]] \
      || { echo "拒绝：任务派发 pane/目录身份不符" >&2; return 1; }
    pane_out="$(herdr pane get "$task_pane" 2>&1)" \
      || { echo "拒绝：工人 pane 无法查询：$pane_out" >&2; return 1; }
    pane_meta="$(printf '%s' "$pane_out" | perl -MJSON::PP=decode_json -0777 -e '
      my $j=eval{decode_json(<STDIN>)}; my $p=$j->{result}{pane};
      exit 1 unless ref $p eq "HASH";
      printf "%s\t%s",$p->{workspace_id},$p->{tab_id} if $p->{workspace_id} && $p->{tab_id};' || true)"
    [[ "${pane_meta%%$'\t'*}" == "$SPACE_ID" && "$pane_meta" == *$'\t'* ]] \
      || { echo "拒绝：工人 pane 不在本票 Space" >&2; return 1; }
    worker_tab="${pane_meta#*$'\t'}"
  fi
  tabs_out="$(herdr tab list --workspace "$SPACE_ID" 2>&1)" \
    || { echo "拒绝：Space tab 查询失败：$tabs_out" >&2; return 1; }
  tab_ids="$(printf '%s' "$tabs_out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j=eval{decode_json(<STDIN>)}; my $a=$j->{result}{tabs};
    exit 1 unless ref $a eq "ARRAY";
    for my $t (@$a) { exit 1 unless ref $t eq "HASH" && $t->{tab_id}; print "$t->{tab_id}\n" }' || true)"
  [[ -n "$tab_ids" ]] || { echo "拒绝：Space tab 列表无法解析" >&2; return 1; }
  while IFS= read -r tab_id; do
    [[ "$tab_id" == "$root_tab" || ( -n "$worker_tab" && "$tab_id" == "$worker_tab" ) ]] \
      || { echo "拒绝：Space 中有非本票 tab ${tab_id}" >&2; return 1; }
  done <<< "$tab_ids"
  printf '%s\n' "$tab_ids" | grep -Fxq "$root_tab" \
    || { echo "拒绝：本票根 tab 已不存在" >&2; return 1; }
  panes_out="$(herdr pane list --workspace "$SPACE_ID" 2>&1)" \
    || { echo "拒绝：Space pane 查询失败：$panes_out" >&2; return 1; }
  pane_rows="$(printf '%s' "$panes_out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j=eval{decode_json(<STDIN>)}; my $a=$j->{result}{panes};
    exit 1 unless ref $a eq "ARRAY";
    for my $p (@$a) { exit 1 unless ref $p eq "HASH" && $p->{pane_id}; printf "%s\t%s\n",$p->{pane_id},($p->{agent_status}//"unknown") }' || true)"
  [[ -n "$pane_rows" ]] || { echo "拒绝：Space pane 列表无法解析" >&2; return 1; }
  while IFS=$'\t' read -r pane_id state; do
    case "$state" in
      working|blocked) echo "拒绝：Space pane ${pane_id} 的 agent 仍在 ${state}" >&2; return 1 ;;
      idle|done) ;;
      *)
        proc="$(herdr pane process-info --pane "$pane_id" 2>&1)" \
          || { echo "拒绝：pane ${pane_id} 前台状态未知：$proc" >&2; return 1; }
        printf '%s' "$proc" | perl -MJSON::PP=decode_json -0777 -e '
          my $j=eval{decode_json(<STDIN>)}; my $p=$j->{result}{process_info};
          exit 1 unless ref $p eq "HASH" && defined $p->{foreground_process_group_id}
            && defined $p->{shell_pid} && $p->{foreground_process_group_id} == $p->{shell_pid};' \
          || { echo "拒绝：pane ${pane_id} 前台仍有工作或无法确认" >&2; return 1; }
        ;;
    esac
  done <<< "$pane_rows"
}

close_task_space() {
  [[ -n "$SPACE_ID" ]] || return 0
  local out
  out="$(herdr workspace close "$SPACE_ID" 2>&1)" \
    || { echo "拒绝：Herdr Space ${SPACE_ID} 关闭失败，Git 未动：$out" >&2; return 1; }
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
    branch_only_here || exit 1
    prepare_space_close || exit 1
    close_task_space || exit 1
    check_unchanged || partial_fail head-changed-after-space-close
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR" || partial_fail worktree-remove
    if [[ "$DETACHED" -eq 1 ]]; then
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（detached HEAD ${HEAD_OID}，无分支可删）"
    elif branch_tip_unchanged; then
      if git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fxq "branch refs/heads/$BRANCH"; then
        partial_fail branch-checked-out-elsewhere
      fi
      git -C "$PROJECT_ROOT" update-ref -d "refs/heads/$BRANCH" "$HEAD_OID" \
        || partial_fail branch-delete
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（删除依据 OID ${HEAD_OID}），分支 ${BRANCH} 已删"
    else
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（删除依据 OID ${HEAD_OID}）；保留分支 ${BRANCH}（收尾期间已被推进或不存在，未删）"
    fi
    race_note
    ;;
  archive)
    TAG="archive/$TASK_ID"
    tag_rc=0
    git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/tags/$TAG" || tag_rc=$?
    if [[ "$tag_rc" -eq 0 ]]; then
      echo "拒绝：归档标签 ${TAG} 已存在，未关闭 Space 或删除 Git worktree" >&2
      exit 1
    fi
    [[ "$tag_rc" -eq 1 ]] || { echo "拒绝：无法核对归档标签 ${TAG}" >&2; exit 1; }
    # 标签打向「即将打的那一刻」的实际 HEAD：收尾期间若已被推进，以当前真实提交为准
    cur="$(recheck_head)" || { echo "错误：无法读取 ${WT_DIR} 的当前 HEAD，拒绝收尾" >&2; exit 1; }
    if [[ "$cur" != "$HEAD_OID" ]]; then
      echo "提示：收尾期间 ${WT_DIR} 的 HEAD 已推进（${HEAD_OID} → ${cur}），标签将指向当前提交" >&2
      HEAD_OID="$cur"
    fi
    branch_only_here || exit 1
    prepare_space_close || exit 1
    close_task_space || exit 1
    git -C "$PROJECT_ROOT" tag "$TAG" "$HEAD_OID" || partial_fail tag-create
    check_unchanged "标签 ${TAG}（→ ${HEAD_OID}）已打且保留；" || partial_fail head-changed-after-tag
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR" || partial_fail worktree-remove
    if [[ "$DETACHED" -eq 1 ]]; then
      kept=""
      if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
        kept="；保留分支 ${TASK_ID}（它不指向本工作区）"
      fi
      echo "已归档：tag ${TAG} → detached HEAD ${HEAD_OID}；worktree 已删${kept}"
    elif branch_tip_unchanged; then
      if git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fxq "branch refs/heads/$BRANCH"; then
        partial_fail branch-checked-out-elsewhere
      fi
      git -C "$PROJECT_ROOT" update-ref -d "refs/heads/$BRANCH" "$HEAD_OID" \
        || partial_fail branch-delete
      echo "已归档：tag ${TAG} → ${HEAD_OID}（分支 ${BRANCH} 顶端）；worktree 已删，分支已删"
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
