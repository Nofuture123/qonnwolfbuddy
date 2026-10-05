#!/usr/bin/env bash
# qwb-worktree.sh —— worktree 清点与收尾：list 标出残留；finish 按 --merged/--archive/--keep 收尾并记账
# 收尾前提：该 worktree 的写入者（工人/agent）已停止写入。删前复核与删除是两次 Git 调用，
# 之间的窗口在 Git 层面无法封死——无法确认写入者已停时，先确认再收尾。
set -euo pipefail
export LC_ALL=C  # 收尾账本记录按字节解析，损坏 UTF-8 不得误判 Space/分支身份。

usage() {
  cat <<'EOF'
用法: qwb-worktree.sh <list|land|finish> [参数] [选项]

  land <任务id> --op <本人claim> --auth-ref <明确授权引用>
                    复用04固定候选验收，prepared→main短锁ff固定C→读回→原finish；
                    同op恢复只补实际阶段，不跑门、不重merge。仅现有已获权主控。
                    授权先通过ledger land-authorize登记；不会自动授权gate或夜间。
                    main前进拒绝，退出后交隔离候选有界整合并补必要验收。

  list                      列出 <项目>/.worktrees/ 下的目录：
                            「未结项」= 对应任务书状态未结/异常、UTF-8 损坏，或已迁票仍有未结义务；
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
    --root-tab-missing  根 tab 已不在 Space 里时的显式兑底：仅与 --merged|--archive 同用；
                    其余身份证据（Space id 与 worktree-space: 记录吻合、路径吻合、无外来 tab、
                    全 pane 空闲）仍逐项核对，全部通过才放行，最终 worktree: 行追加
                    root-tab-missing=1 留痕。无该参数时根 tab 缺失仍拒绝。与 --keep 同传
                    时不报错也不留痕（行为与单独 --keep 一致）。
    --writer-proof-missing=<原因>  仅 --merged|--archive 的显式兑底，原因必填非空：
                    只认探针写下的身份未知且无 PID；该 pane 须已不存在或退回空闲 shell，
                    其余各代 PID 须已死且 lsof 无候选 cwd/FD。最终及 partial 行追加
                    writer-proof-missing=1，并另记主控 working 行说明 op、pane、原因与证据。
                    不带参数照旧拒绝；与 --keep 同传不报错、不留痕；land 不接受。
  --merged / --archive 先检查 worktree 有无未提交改动/未跟踪文件：有则拒绝（不做 --force，
  先提交或清理再来）；git status 本身失败也拒绝，不当干净放行。且每个删除动作前都复核
  worktree 实际 HEAD 仍是开头读到的那个提交；已被推进则拒绝（--archive 已打的 tag 保留）。
  共同删除接缝用真实lsof核候选cwd/FD，并逐一核全部dispatch/not-sent的PID/start死亡证据。
  缺证、旧代仍活或探针未知保留候选/分支；agent=null/前台回shell不代替死亡证明。
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
  list|land|finish) CMD="$1"; shift ;;
  *) echo "错误：需要子命令 list|finish" >&2; usage >&2; exit 2 ;;
esac

PROJECT_ROOT="$(pwd)"; TASK_ID=""; ACTION=""; REASON=""; ROOT_TAB_MISSING=0; ROOT_TAB_MISSING_APPLIED=0
LAND_OP=""; AUTH_REF=""
WRITER_PROOF_MISSING=""; WRITER_PROOF_MISSING_APPLIED=0; WRITER_PROOF_MISSING_FACTS=""; WRITER_PROOF_MISSING_NOTED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --op) LAND_OP="$2"; shift 2 ;;
    --auth-ref) AUTH_REF="$2"; shift 2 ;;
    --merged|--archive) ACTION="${1#--}"; shift ;;
    --keep) ACTION="keep"; shift ;;
    --keep=*) ACTION="keep"; REASON="${1#--keep=}"; shift ;;
    --root-tab-missing) ROOT_TAB_MISSING=1; shift ;;
    --writer-proof-missing=*)
      [[ "$CMD" == finish ]] || { echo "错误：未知参数 $1（仅 finish 的 --merged|--archive 支持）" >&2; usage >&2; exit 2; }
      WRITER_PROOF_MISSING="${1#--writer-proof-missing=}"
      [[ -n "${WRITER_PROOF_MISSING//[[:space:]]/}" ]] || { echo '错误：--writer-proof-missing 必须给出非空原因' >&2; exit 2; }
      shift ;;
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

# 精确任务 id → 未结/损坏或仍有持久未结义务的任务书（无则返回 1）
open_task_for() {
  local f st
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    [[ "$(basename "$f" .md | sed 's/^[0-9][0-9-]*-//')" == "$1" ]] || continue
    st="$(qwb_task_state "$f")"
    if ! qwb_ledger_utf8_ok "$f"; then printf '%s' "$f"; return 0; fi
    case "$st" in
      running|blocked|needs-decision) printf '%s' "$f"; return 0 ;;
      done|verified)
        if [[ -n "$(qwb_task_obligations "$PROJECT_ROOT" "$f")" ]]; then
          printf '%s' "$f"; return 0
        fi
        ;;
      *) printf '%s' "$f"; return 0 ;;
    esac
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
  [[ "$ROOT_TAB_MISSING" -eq 0 ]] \
    || { echo "错误：未知参数 --root-tab-missing（仅 finish 的 --merged|--archive 支持）" >&2; usage >&2; exit 2; }
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

foreground_is_shell() {
  printf '%s' "$1" | perl -MJSON::PP -0777 -e 'my $p=decode_json(<STDIN>)->{result}{process_info}; exit 1 unless ref($p) eq "HASH" && defined($p->{foreground_process_group_id}) && defined($p->{shell_pid}) && $p->{foreground_process_group_id}==$p->{shell_pid};'
}

# Keep stderr separate: even whitespace on a successful query makes identity unknown.
pane_query() {
  python3 -B - "$1" <<'PY'
import subprocess,sys
reply=subprocess.run(['herdr','pane','get',sys.argv[1]],capture_output=True,text=True)
sys.stdout.write(reply.stdout+('\nstderr:'+reply.stderr if reply.returncode==0 and reply.stderr else reply.stderr))
sys.exit(reply.returncode)
PY
}

pane_without_agent() {
  local rc=0
  printf '%s' "$1" | perl -MJSON::PP -0777 -e '
    my $j=decode_json(<STDIN>); my $p=$j->{result}{pane};
    exit 2 unless ref($p) eq "HASH" && !$j->{error} && ($p->{pane_id}//"") eq $ARGV[0];
    exit 0 unless defined($p->{agent});
    exit(encode_json($p->{agent}) =~ /^".+"$/s ? 1 : 2);
  ' "$2" || rc=$?
  [[ "$rc" -eq 0 ]] && return 0
  if [[ "$rc" -eq 1 ]]; then echo "$3" >&2; else echo "$4" >&2; fi
  return 1
}

# 只探本票派发登记的端点；idle/done不是退出证明。端点未知保留候选。
land_writers_stopped() {
  [[ "$CMD" == land || -n "${LAND_PROOF:-}" ]] || return 0
  local data panes pane out rc proc
  data="$(qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" read)" || return 1
  panes="$(printf '%s' "$data" | python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["workers"]))')" || return 1
  [[ -n "$panes" ]] || return 0
  while IFS= read -r pane; do
    rc=0; out="$(pane_query "$pane")" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      printf '%s' "$out" | perl -MJSON::PP -0777 -e 'my $j=decode_json(<STDIN>); exit(($j->{error}{code}//"") eq "pane_not_found" ? 0 : 1);' \
        || { echo '拒绝：本票写入者端点未知，不能删除候选' >&2; return 1; }
      continue
    fi
    pane_without_agent "$out" "$pane" "拒绝：本票写入者尚未退出（idle/done不等于已停）；窗口=${pane}；确认工人已停后 herdr pane close ${pane}，再用同一操作号重跑" '拒绝：本票写入者端点未知，不能删除候选' || return 1
    proc="$(herdr pane process-info --pane "$pane" 2>&1)" || return 1
    foreground_is_shell "$proc" \
      || { echo '拒绝：本票写入者前台活动/未知' >&2; return 1; }
  done <<< "$panes"
}

# land复用原finish；验证/授权和落地发布仍由唯一MD writer承担。
if [[ "$CMD" == land ]]; then
  [[ -n "$LAND_OP" && -n "$AUTH_REF" && -z "$ACTION" ]] || { echo '拒绝：land需要本人op/明确auth-ref，不接受finish动作' >&2; exit 2; }
  TASK_FILE="$(unique_task_for "$TASK_ID")" || { echo '拒绝：找不到唯一任务书' >&2; exit 1; }
  state="$(qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" read)" || exit 1
  stage="$(printf '%s' "$state" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("land",{}).get("stage",""))')"
  if [[ "$stage" == closed ]]; then
    qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-close "$LAND_OP" "$AUTH_REF" >/dev/null || exit 1
    echo '已收尾（原land收据保留）'; exit 0
  fi
  land_writers_stopped || exit 1
  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-prepare "$LAND_OP" "$AUTH_REF" >/dev/null || exit 1
  if [[ "$stage" != landed ]]; then
    qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-apply "$LAND_OP" "$AUTH_REF" >/dev/null || exit 1
  fi
  argv=(finish "$TASK_ID" --merged --project "$PROJECT_ROOT" --op "$LAND_OP" --auth-ref "$AUTH_REF")
  [[ "$ROOT_TAB_MISSING" -eq 0 ]] || argv+=(--root-tab-missing)
  bash "${BASH_SOURCE[0]}" "${argv[@]}" || exit 1
  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-close "$LAND_OP" "$AUTH_REF" >/dev/null || exit 1
  echo '已本地落地、读回并收尾；tokens=unknown'
  exit 0
fi

# finish
[[ -n "$TASK_ID" ]] || { echo "错误：finish 需要 <任务id>" >&2; usage >&2; exit 2; }
[[ -n "$ACTION" ]] || { echo "错误：finish 需要动作 --merged|--archive|--keep[=原因]" >&2; exit 2; }
[[ -z "$WRITER_PROOF_MISSING" || ( -z "$LAND_OP" && -z "$AUTH_REF" ) ]] \
  || { echo '拒绝：land收尾不接受 --writer-proof-missing' >&2; exit 2; }
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
qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" check >/dev/null || exit 1
FINISH_OP=""; LAND_PROOF=""
if [[ -n "$LAND_OP" || -n "$AUTH_REF" ]]; then
  [[ "$ACTION" == merged && -n "$LAND_OP" && -n "$AUTH_REF" ]] || { echo '拒绝：land收尾参数不齐/动作不符' >&2; exit 1; }
  LAND_PROOF="$(qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" land-proof "$LAND_OP" "$AUTH_REF")" || exit 1
elif grep -q '^<!-- qwb-collab-v1$' "$TASK_FILE"; then
  if [[ "$ACTION" == merged ]] && grep -q '"gate":' "$TASK_FILE"; then
    echo '拒绝：协作候选须先经land证明精确本地main，不接受remote/任意HEAD包含' >&2; exit 1
  fi
  FINISH_OP="$(qwb_op_id)"
  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" claim "$FINISH_OP" >/dev/null || exit 1
fi
# 两处 land 收尾各只读一次同一份已验证的 branch/after 证明。
parse_land_proof() {
  local fields
  fields="$(printf '%s' "$LAND_PROOF" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["branch"]); print(d["after"])')" || return 1
  proof_branch="${fields%$'\n'*}"
  proof_oid="${fields##*$'\n'}"
}


# 复用09固定40c8761的PID/start与全部启动代协议，不搬其订阅/展示平台。
# shell/null只是端点前置条件；所有删树调用再核本票真实资源及历史死亡义务。
writers_stopped() {
  [[ "$ACTION" != keep ]] || return 0
  local facts
  facts="$(python3 -B - "$TASK_FILE" "$WT_DIR" "${1:-}" "$WRITER_PROOF_MISSING" "$(dirname "$LIB")" "$LAND_PROOF" <<'PY'
import json, re, subprocess, sys
from pathlib import Path
try:
    task, directory, rows=sys.argv[1:4]
    options=sys.argv[4:]; override=bool(options and options[0] and not options[2])
    missing=[]; checked=0
    def require(ok,why):
        if not ok: raise ValueError(why)
    # 保守拒绝任何候选cwd/打开文件（包括只读FD）；只读误拒可等实际退出再恢复。
    if Path(directory).is_dir():
        probe=subprocess.run(['lsof','-nP','-Fpcfan','+D',directory],capture_output=True,text=True,timeout=10)
        require(probe.returncode in (0,1) and not probe.stderr.strip(),'候选写入者资源探针未知')
        if probe.stdout.strip():
            processes={}; pid=None
            for row in probe.stdout.splitlines():
                if row.startswith('p') and row[1:].isdigit():
                    pid=row[1:]; processes.setdefault(pid,'未知命令')
                elif row.startswith('c') and pid is not None: processes[pid]=row[1:]
            occupied='、'.join(pid+'('+name+')' for pid,name in list(processes.items())[:5])
            if len(processes)>5: occupied+='等 '+str(len(processes))+' 个'
            panes=list(dict.fromkeys(re.findall(r'^dispatch:.*?\spane=(\S+) dir=',Path(task).read_text(),re.M)))
            if panes:
                route='确认工人已交付、不再需要它的会话后，关闭本票登记的工人 pane 再重试：'+'；'.join('herdr pane close '+pane for pane in panes)
            else: route='让这些进程退出或离开副本目录后重试'
            raise ValueError('候选写入者仍持cwd/FD，保留成果\n提示：'+occupied+'；'+route)
        require(probe.returncode==1,'候选写入者资源探针空响应未知')
    text=Path(task).read_text(); attempts={}; bound={}
    for line in re.findall(r'^(?:dispatch|not-sent):.*$',text,re.M):
        match=re.search(r'\spane=(\S+) dir=(.+)$',line)
        op=re.search(r'\sop_id=(\S+)',line)
        require(match and op,'启动代死亡证据缺失；保留候选')
        require(str(Path(match[2]).resolve())==directory,'启动代目录不符；保留候选')
        attempts.setdefault(match[1],set()).add(op[1])
    for op,pane,raw in re.findall(r'^working: worker-activity op=(\S+) pane=(\S+) evidence=(.+)$',text,re.M):
        # 同op收据必须始终指向同一代，不能用后来的死PID遮掉旧活代。
        evidence=json.loads(raw); key=(pane,op)
        if override and isinstance(evidence,dict):
            require(len(json.loads(raw,object_pairs_hook=list))==len(evidence),'旧启动代PID/start未知')
        require(key not in bound or bound[key]==evidence,'启动代死亡证据冲突')
        bound[key]=evidence
    def ended(evidence):
        pid=evidence.get('pid'); start=evidence.get('pid_start')
        require(type(pid) is int and pid>0 and isinstance(start,str) and start,'旧启动代PID/start未知')
        # 不使用模型状态或测试用owner ps替身证明工具死亡。
        v=subprocess.run(['/bin/ps','-p',str(pid),'-o','lstart='],capture_output=True,text=True,timeout=2)
        require(not v.stderr.strip() and ((v.returncode==1 and not v.stdout.strip()) or
                (v.returncode==0 and v.stdout.strip() and v.stdout.strip()!=start)),
                '旧启动代仍活或死亡未知')
    for pane,ops in attempts.items():
        require(all((pane,op) in bound for op in ops),'启动代死亡证据缺失；保留候选')
    for (pane,op),evidence in bound.items():
        unknown=(isinstance(evidence,dict) and set(evidence)=={'activity','proof','conflict'} and
                 evidence['activity']=='unknown' and evidence['proof']=='unverified' and
                 isinstance(evidence['conflict'],str) and bool(evidence['conflict'].strip()))
        if override and unknown and op in attempts.get(pane,set()):
            # Reuse the existing native activity adapter for the foreground-shell proof.
            pane_query=subprocess.run(['herdr','pane','get',pane],capture_output=True,text=True,timeout=2)
            if pane_query.returncode:
                raw=pane_query.stdout if pane_query.stdout.strip() else pane_query.stderr
                other=pane_query.stderr if pane_query.stdout.strip() else pane_query.stdout
                try: reply=json.loads(raw)
                except ValueError: reply={}
                require(not other.strip() and isinstance(reply,dict) and isinstance(reply.get('error'),dict) and
                        reply['error'].get('code')=='pane_not_found','缺PID兑底：pane '+pane+' 查询失败或身份未知')
                proof='pane-not-found'
            else:
                try: reply=json.loads(pane_query.stdout); info=reply.get('result',{}).get('pane',{})
                except (ValueError,AttributeError): info={}; reply={}
                require(not pane_query.stderr.strip() and not reply.get('error') and isinstance(info,dict) and
                        info.get('pane_id')==pane and (info.get('agent') is None or isinstance(info.get('agent'),str) and bool(info['agent'])),'缺PID兑底：pane '+pane+' 身份未知')
                require(info.get('agent') is None,'缺PID兑底：pane '+pane+' 仍有agent，保留成果')
                observed=subprocess.run(['bash',str(Path(options[1])/'qwb-herdr.sh'),'activity','--project',str(Path(task).parent.parent),
                                         '--pane',pane,'--dir',directory],capture_output=True,text=True,timeout=10)
                try: observation=json.loads(observed.stdout)
                except ValueError: observation={}
                require(observed.returncode==0 and not observed.stderr.strip() and observation.get('activity')=='idle' and
                        observation.get('proof')=='foreground-shell' and observation.get('pane')==pane,
                        '缺PID兑底：pane '+pane+' 前台不是空闲shell或查询未知')
                proof='foreground-shell'
            missing.append(dict(op=op,pane=pane,pane_proof=proof))
        else:
            ended(evidence); checked+=1
    panes=set(attempts)|{key[0] for key in bound}|{r.split('\t')[0] for r in rows.splitlines()}
    for record in (Path(task).parent.parent/'qwbuddy/.roles').glob('*.json'):
        require(not record.is_symlink(),'角色退出身份未知')
        d=json.loads(record.read_text())
        if d.get('pane') in panes:
            require(d.get('version')==1 and d.get('root')==str(Path(task).parent.parent),'角色归属未知')
            candidate=d.get('pending') or d
            if candidate.get('attempted',d.get('phase') not in ('prepared','pane-ready')): ended(candidate)
    if missing:
        print(json.dumps(dict(generations=missing,known_generations_ended=checked,
                              resource_proof='lsof-clean' if Path(directory).is_dir() else 'directory-absent; partial-OID-required')))
except (OSError,ValueError,KeyError,TypeError,subprocess.TimeoutExpired) as e:
    print('拒绝：'+str(e),file=sys.stderr); sys.exit(1)
PY
)" || return 1
  if [[ -n "$facts" ]]; then
    WRITER_PROOF_MISSING_APPLIED=1
    WRITER_PROOF_MISSING_FACTS="$facts"
  fi
}

# No note is written until all guards and the Space close have succeeded.
note_writer_proof_missing() {
  [[ "$WRITER_PROOF_MISSING_APPLIED" -eq 1 && "$WRITER_PROOF_MISSING_NOTED" -eq 0 ]] || return 0
  local notes note
  notes="$(python3 -B - "$WRITER_PROOF_MISSING" "$WRITER_PROOF_MISSING_FACTS" <<'PY'
import json,sys
reason,facts=sys.argv[1:]; facts=json.loads(facts)
for generation in facts['generations']:
    print('working: writer-proof-missing op='+generation['op']+' pane='+generation['pane']+
          ' reason='+json.dumps(reason,ensure_ascii=False)+' evidence='+json.dumps(dict(generation,resource_proof=facts['resource_proof'],
          known_generations_ended=facts['known_generations_ended'],later_live_generation='none'),ensure_ascii=False))
PY
)" || return 1
  while IFS= read -r note; do qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" append "$note" >/dev/null || return 1; done <<< "$notes"
  WRITER_PROOF_MISSING_NOTED=1
}

WT_DIR="$WT_BASE/$TASK_ID"
land_writers_stopped || exit 1
# 已删树的partial也须核历史启动代；尚在的目录先核物理身份再探资源。
if [[ ! -d "$WT_DIR" ]]; then writers_stopped || exit 1; fi
cleanup_branch_config() {
  local keys key found=0 command_text
  if ! keys="$(git -C "$PROJECT_ROOT" config --local --list --name-only 2>/dev/null)"; then
    found=1
  else
    while IFS= read -r key; do
      [[ "$key" == "branch.$BRANCH."* ]] && found=1
    done <<< "$keys"
  fi
  [[ "$found" -eq 1 ]] || return 0
  if ! git -C "$PROJECT_ROOT" config --local --remove-section "branch.$BRANCH"; then
    printf -v command_text 'git -C %q config --local --remove-section %q' "$PROJECT_ROOT" "branch.$BRANCH"
    echo "警告：分支 ${BRANCH} 的配置节清理失败；请执行 ${command_text}（分支 ref 已删除，不回滚）" >&2
  fi
}

# worktree 已删后的唯一可续做阶段：只接受本票最后一条带旧 OID 的 branch-delete 收据。
if [[ ! -d "$WT_DIR" ]]; then
  [[ "$ACTION" != keep && ! -L "$TASK_FILE" && ! -L "$WT_DIR" ]] \
    || { echo "错误：worktree 不存在或任务书是符号链接：${WT_DIR}" >&2; exit 1; }
  if [[ -n "$LAND_PROOF" ]]; then
    parse_land_proof
    refs="$(git -C "$PROJECT_ROOT" for-each-ref --format='%(refname)' "refs/heads/$proof_branch")" || exit 1
    if [[ -z "$refs" ]]; then
      listing="$(git -C "$PROJECT_ROOT" worktree list --porcelain)" || exit 1
      if printf '%s\n' "$listing" | grep -Fxq "worktree $WT_DIR"; then echo '拒绝：worktree元数据仍在，现实不明' >&2; exit 1; fi
      qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" append "worktree: merged branch=${proof_branch} tag=-" >/dev/null || exit 1
      echo "已按本地land收据补记收尾 OID=$proof_oid"; exit 0
    fi
  fi
  partial="$(grep '^worktree:' "$TASK_FILE" | tail -1 || true)"
  if [[ ! "$partial" =~ ^worktree:\ partial\ action=(merged|archive)\ branch=([^[:space:]]+)\ tag=([^[:space:]]+)\ stage=branch-delete\ space=([^[:space:]]+)\ oid=([0-9a-f]{40,64})( root-tab-missing=1)?( writer-proof-missing=1)?$ ]]; then
    echo "错误：worktree 不存在且没有可续做的 branch-delete 记录：${WT_DIR}" >&2; exit 1
  fi
  partial_rtm=""; [[ "$partial" == *" root-tab-missing=1"* ]] && partial_rtm=" root-tab-missing=1"
  partial_wpm=""; [[ "$partial" == *" writer-proof-missing=1" ]] && partial_wpm=" writer-proof-missing=1"
  [[ "${BASH_REMATCH[1]}" == "$ACTION" ]] \
    || { echo "拒绝：续做动作与 partial 记录不符" >&2; exit 1; }
  BRANCH="${BASH_REMATCH[2]}"; TAG="${BASH_REMATCH[3]}"; HEAD_OID="${BASH_REMATCH[5]}"
  if [[ -n "$LAND_PROOF" ]]; then
    [[ "$BRANCH" == "$proof_branch" && "$HEAD_OID" == "$proof_oid" ]] || { echo '拒绝：partial分支/OID与land身份不符' >&2; exit 1; }
  fi
  [[ "$BRANCH" != detached ]] || { echo "拒绝：detached 收据不能续做分支删除" >&2; exit 1; }
  if [[ "$ACTION" == archive ]]; then
    [[ "$TAG" == "archive/$TASK_ID" && "$(git -C "$PROJECT_ROOT" rev-parse "refs/tags/$TAG^{commit}" 2>/dev/null || true)" == "$HEAD_OID" ]] \
      || { echo "拒绝：归档标签与 partial OID 不符" >&2; exit 1; }
  else
    [[ "$TAG" == - ]] || { echo "拒绝：合并收据标签身份不符" >&2; exit 1; }
  fi
  [[ "$(git -C "$PROJECT_ROOT" rev-parse "refs/heads/$BRANCH" 2>/dev/null || true)" == "$HEAD_OID" ]] \
    || { echo "拒绝：分支 ${BRANCH} 顶端与 partial OID 不符，不删引用" >&2; exit 1; }
  listing="$(git -C "$PROJECT_ROOT" worktree list --porcelain)" \
    || { echo "拒绝：无法核对 Git worktree 登记" >&2; exit 1; }
  if printf '%s\n' "$listing" | grep -Fxq "worktree $WT_DIR" \
    || printf '%s\n' "$listing" | grep -Fxq "branch refs/heads/$BRANCH"; then
    echo "拒绝：目标目录或分支仍被 worktree 检出" >&2; exit 1
  fi
  note_writer_proof_missing || exit 1
  git -C "$PROJECT_ROOT" update-ref -d "refs/heads/$BRANCH" "$HEAD_OID" \
    || { echo "错误：按 partial OID 续删分支失败，原记录保留" >&2; exit 1; }
  cleanup_branch_config
  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" append "worktree: ${ACTION} branch=${BRANCH} tag=${TAG}${partial_rtm}${partial_wpm}" >/dev/null \
    || { echo "错误：分支已删但最终记账失败，请手工核对：$TASK_FILE" >&2; exit 1; }
  [[ -z "$FINISH_OP" ]] || qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" release "$FINISH_OP" >/dev/null
  echo "已续做：按 partial OID ${HEAD_OID} 删除分支 ${BRANCH}，并记账 worktree: ${ACTION}"
  exit 0
fi
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
  if [[ -n "$LAND_PROOF" && "$(git -C "$PROJECT_ROOT" rev-parse refs/heads/main)" != "$HEAD_OID" ]]; then
    echo '拒绝：收尾期间精确本地main已变，保留候选/分支待对账' >&2; return 1
  fi
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
  if [[ -n "$LAND_PROOF" && "$(git -C "$PROJECT_ROOT" rev-parse refs/heads/main)" != "$HEAD_OID" ]]; then
    echo '拒绝：main已变，不删保留分支' >&2; return 1
  fi
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
  local stage="$1" recovery="" script_path
  partial_rtm=""; [[ "$ROOT_TAB_MISSING_APPLIED" -eq 1 ]] && partial_rtm=" root-tab-missing=1"
  partial_wpm=""; [[ "$WRITER_PROOF_MISSING_APPLIED" -eq 1 ]] && partial_wpm=" writer-proof-missing=1"
  qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" append "worktree: partial action=${ACTION} branch=${BRANCH:-detached} tag=${TAG:--} stage=${stage} space=${SPACE_ID:--} oid=${HEAD_OID}${partial_rtm}${partial_wpm}" >/dev/null \
    || echo "警告：部分收尾记录写入失败：$TASK_FILE" >&2
  echo "错误：收尾停在 ${stage}（OID ${HEAD_OID}）；核对 Git worktree/分支与 Herdr Space 后再恢复" >&2
  if [[ "$stage" == "branch-delete" && "$DETACHED" -eq 0 ]]; then
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-worktree.sh"
    # shellcheck disable=SC2016
    printf -v recovery 'test "$(git -C %q rev-parse %q)" = %q && bash %q finish %q --%s --project %q' \
      "$PROJECT_ROOT" "refs/heads/$BRANCH" "$HEAD_OID" "$script_path" "$TASK_ID" "$ACTION" "$PROJECT_ROOT"
  elif [[ "$stage" == "worktree-remove" ]]; then
    script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-worktree.sh"
    if [[ "$ACTION" == "archive" ]]; then
      # shellcheck disable=SC2016
      printf -v recovery 'test "$(git -C %q rev-parse HEAD)" = %q && test "$(git -C %q rev-parse %q)" = %q && bash %q finish %q --archive --project %q' \
        "$WT_DIR" "$HEAD_OID" "$PROJECT_ROOT" "refs/tags/$TAG^{commit}" "$HEAD_OID" \
        "$script_path" "$TASK_ID" "$PROJECT_ROOT"
    else
      # shellcheck disable=SC2016
      printf -v recovery 'test "$(git -C %q rev-parse HEAD)" = %q && bash %q finish %q --merged --project %q' \
        "$WT_DIR" "$HEAD_OID" "$script_path" "$TASK_ID" "$PROJECT_ROOT"
    fi
  fi
  if [[ -n "$recovery" && "$WRITER_PROOF_MISSING_APPLIED" -eq 1 ]]; then
    printf -v recovery '%s %q' "$recovery" "--writer-proof-missing=$WRITER_PROOF_MISSING"
  fi
  [[ -z "$recovery" ]] || echo "恢复命令：${recovery}" >&2
  exit 1
}

# worktree 删除后的分支清理；调用方保留各动作自己的提示文案。
delete_finished_branch() {
  if git -C "$PROJECT_ROOT" worktree list --porcelain | grep -Fxq "branch refs/heads/$BRANCH"; then
    partial_fail branch-checked-out-elsewhere
  fi
  git -C "$PROJECT_ROOT" update-ref -d "refs/heads/$BRANCH" "$HEAD_OID" \
    || partial_fail branch-delete
  cleanup_branch_config
}

# Git 前置检查先于任何 Space 关闭；只关闭本票登记且没有活动写入者的 Space。
prepare_space_close() {
  local record root_tab record_path last_dispatch dispatch_path task_pane pane_out pane_meta worker_tab
  local tabs_out tab_ids tab_id panes_out pane_rows pane_id state proc pane_rc absent
  writers_stopped || return 1
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
  last_dispatch="$(grep -E '^(dispatch|not-sent):' "$TASK_FILE" | tail -1 || true)"
  worker_tab=""
  if [[ -n "$last_dispatch" ]]; then
    task_pane="$(printf '%s\n' "$last_dispatch" | sed -n 's/.* pane=\([^ ]*\) dir=.*/\1/p')"
    dispatch_path="$(cd "${last_dispatch##* dir=}" 2>/dev/null && pwd -P)" || dispatch_path=""
    [[ -n "$task_pane" && "$dispatch_path" == "$WT_PHYS" ]] \
      || { echo "拒绝：任务派发 pane/目录身份不符" >&2; return 1; }
    pane_rc=0
    pane_out="$(herdr pane get "$task_pane" 2>&1)" || pane_rc=$?
    if [[ "$pane_rc" -ne 0 ]]; then
      absent=1
      if [[ "$WRITER_PROOF_MISSING_APPLIED" -eq 1 ]]; then
        printf '%s' "$pane_out" | perl -MJSON::PP -0777 -e 'my $j=decode_json(<STDIN>); exit(($j->{error}{code}//"") eq "pane_not_found" ? 0 : 1);' \
          && python3 -B - "$WRITER_PROOF_MISSING_FACTS" "$task_pane" <<'PY' && absent=0
import json,sys
facts=json.loads(sys.argv[1]); sys.exit(0 if any(x['pane']==sys.argv[2] and x['pane_proof']=='pane-not-found' for x in facts['generations']) else 1)
PY
      fi
      [[ "$absent" -eq 0 ]] || { echo "拒绝：工人 pane 无法查询：$pane_out" >&2; return 1; }
    else
      pane_meta="$(printf '%s' "$pane_out" | perl -MJSON::PP=decode_json -0777 -e '
        my $j=eval{decode_json(<STDIN>)}; my $p=$j->{result}{pane};
        exit 1 unless ref $p eq "HASH";
        printf "%s\t%s",$p->{workspace_id},$p->{tab_id} if $p->{workspace_id} && $p->{tab_id};' || true)"
      [[ "${pane_meta%%$'\t'*}" == "$SPACE_ID" && "$pane_meta" == *$'\t'* ]] \
        || { echo "拒绝：工人 pane 不在本票 Space" >&2; return 1; }
      worker_tab="${pane_meta#*$'\t'}"
    fi
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
    || {
         if [[ "$ROOT_TAB_MISSING" -eq 1 ]]; then
           ROOT_TAB_MISSING_APPLIED=1
           echo "提示：本票根 tab ${root_tab} 已不在 Space；--root-tab-missing 兑底放行（其余身份证据已逐项核对，收尾将留痕 root-tab-missing=1）" >&2
         else
           echo "拒绝：本票根 tab 已不存在（Space 与工人 tab 仍在；确认无需恢复后可用 --root-tab-missing 兑底收尾）" >&2
           return 1
         fi
       }
  panes_out="$(herdr pane list --workspace "$SPACE_ID" 2>&1)" \
    || { echo "拒绝：Space pane 查询失败：$panes_out" >&2; return 1; }
  pane_rows="$(printf '%s' "$panes_out" | perl -MJSON::PP=decode_json -0777 -e '
    my $j=eval{decode_json(<STDIN>)}; my $a=$j->{result}{panes};
    exit 1 unless ref $a eq "ARRAY";
    for my $p (@$a) { exit 1 unless ref $p eq "HASH" && $p->{pane_id}; printf "%s\t%s\n",$p->{pane_id},($p->{agent_status}//"unknown") }' || true)"
  [[ -n "$pane_rows" ]] || { echo "拒绝：Space pane 列表无法解析" >&2; return 1; }
  while IFS=$'\t' read -r pane_id state; do
    if [[ -n "$LAND_PROOF" ]]; then
      # idle/done是模型状态，不是退出证明；land不关闭仍挂Pi的pane。
      pane_out="$(pane_query "$pane_id")" || { echo '拒绝：land写入者身份未知' >&2; return 1; }
      pane_without_agent "$pane_out" "$pane_id" "拒绝：land写入者尚未退出（idle/done不等于已停）；窗口=${pane_id}；确认工人已停后 herdr pane close ${pane_id}，再用同一操作号重跑" '拒绝：land写入者身份未知' || return 1
      proc="$(herdr pane process-info --pane "$pane_id" 2>&1)" || { echo '拒绝：land前台未知' >&2; return 1; }
      foreground_is_shell "$proc" \
        || { echo '拒绝：land前台仍有活动写入者' >&2; return 1; }
    fi
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
  writers_stopped "$pane_rows" || return 1
}

close_task_space() {
  [[ -n "$SPACE_ID" ]] || return 0
  local out
  local argv=(close --project "$PROJECT_ROOT" --task "$TASK_FILE" --space "$SPACE_ID")
  [[ "$WRITER_PROOF_MISSING_APPLIED" -eq 0 ]] || argv+=("--writer-proof-missing=$WRITER_PROOF_MISSING")
  out="$(bash "$(dirname "$LIB")/qwb-herdr.sh" "${argv[@]}" 2>&1)" \
    || { echo "拒绝：Herdr Space ${SPACE_ID} 关闭/焦点读回未确认，Git 未动：$out" >&2; return 1; }
  printf '%s\n' "$out"
}

BL="$BRANCH"
if [[ "$DETACHED" -eq 1 ]]; then BL="detached"; fi
TAG="-"
case "$ACTION" in
  merged)
    landed=""
    if [[ -n "$LAND_PROOF" ]]; then
      parse_land_proof
      [[ "$DETACHED" -eq 0 && "$BRANCH" == "$proof_branch" && "$HEAD_OID" == "$proof_oid" && "$(git -C "$PROJECT_ROOT" rev-parse refs/heads/main)" == "$proof_oid" ]] || { echo '拒绝：本地main/候选不是land精确C' >&2; exit 1; }
      landed="精确本地main land收据（${proof_oid}）"
    elif git -C "$PROJECT_ROOT" merge-base --is-ancestor "$HEAD_OID" HEAD 2>/dev/null; then
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
    land_writers_stopped || exit 1
    prepare_space_close || exit 1
    close_task_space || exit 1
    note_writer_proof_missing || partial_fail writer-proof-note
    check_unchanged || partial_fail head-changed-after-space-close
    writers_stopped || partial_fail writers-not-stopped
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR" || partial_fail worktree-remove
    if [[ "$DETACHED" -eq 1 ]]; then
      echo "已收尾（${landed}）：worktree ${WT_DIR} 已删（detached HEAD ${HEAD_OID}，无分支可删）"
    elif branch_tip_unchanged; then
      delete_finished_branch
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
    [[ "$tag_rc" -le 1 ]] || { echo "拒绝：无法核对归档标签 ${TAG}" >&2; exit 1; }
    # 标签打向「即将打的那一刻」的实际 HEAD：收尾期间若已被推进，以当前真实提交为准
    cur="$(recheck_head)" || { echo "错误：无法读取 ${WT_DIR} 的当前 HEAD，拒绝收尾" >&2; exit 1; }
    if [[ "$cur" != "$HEAD_OID" ]]; then
      echo "提示：收尾期间 ${WT_DIR} 的 HEAD 已推进（${HEAD_OID} → ${cur}），标签将指向当前提交" >&2
      HEAD_OID="$cur"
    fi
    if [[ "$tag_rc" -eq 0 ]]; then
      tag_oid="$(git -C "$PROJECT_ROOT" rev-parse "refs/tags/$TAG^{commit}" 2>/dev/null)" || tag_oid=""
      [[ "$tag_oid" == "$HEAD_OID" ]] || {
        echo "拒绝：归档标签 ${TAG} 已存在且不指向当前实际 HEAD ${HEAD_OID}，未关闭 Space 或删除 Git worktree" >&2
        exit 1
      }
    fi
    branch_only_here || exit 1
    prepare_space_close || exit 1
    close_task_space || exit 1
    note_writer_proof_missing || partial_fail writer-proof-note
    if [[ "$tag_rc" -eq 1 ]]; then
      git -C "$PROJECT_ROOT" tag "$TAG" "$HEAD_OID" || partial_fail tag-create
    fi
    check_unchanged "标签 ${TAG}（→ ${HEAD_OID}）已打且保留；" || partial_fail head-changed-after-tag
    writers_stopped || partial_fail writers-not-stopped
    git -C "$PROJECT_ROOT" worktree remove "$WT_DIR" || partial_fail worktree-remove
    if [[ "$DETACHED" -eq 1 ]]; then
      kept=""
      if git -C "$PROJECT_ROOT" show-ref --verify --quiet "refs/heads/$TASK_ID"; then
        kept="；保留分支 ${TASK_ID}（它不指向本工作区）"
      fi
      echo "已归档：tag ${TAG} → detached HEAD ${HEAD_OID}；worktree 已删${kept}"
    elif branch_tip_unchanged; then
      delete_finished_branch
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
# partial（如 worktree-remove 失败）已带留痕、Space 已关后重跑：沿用收据留痕；
# 防陈旧 partial 污染：收据 oid 必须等于本次实际 HEAD_OID 才认。
if [[ "$ROOT_TAB_MISSING_APPLIED" -eq 0 ]] && grep -q "^worktree: partial action=${ACTION} .* oid=${HEAD_OID} root-tab-missing=1\\( writer-proof-missing=1\\)\{0,1\}$" "$TASK_FILE"; then
  ROOT_TAB_MISSING_APPLIED=1
fi
[[ "$ROOT_TAB_MISSING_APPLIED" -eq 1 ]] && line="${line} root-tab-missing=1"
[[ "$WRITER_PROOF_MISSING_APPLIED" -eq 1 && "$ACTION" != keep ]] && line="${line} writer-proof-missing=1"
qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" append "$line" >/dev/null
[[ -z "$FINISH_OP" ]] || qwb_ledger "$PROJECT_ROOT" "$TASK_FILE" release "$FINISH_OP" >/dev/null
echo "已记账：$(basename "$TASK_FILE") ← ${line}"
