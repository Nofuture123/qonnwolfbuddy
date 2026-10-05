#!/usr/bin/env bash
# 定向运行时负例；由 smoke.sh 调用，也可单独运行。
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1
export TMPDIR="$TMP"
trap 'qwb_test_drain && rm -rf "$TMP" || exit 1' EXIT
FAILS=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
PROJECT="$TMP/project"
LOCK="$PROJECT/qwbuddy/.controller.lock"
mkdir -p "$PROJECT/qwbuddy" "$PROJECT/tasks" "$TMP/bin"
bash "$ROOT/bin/qwb-init.sh" "$PROJECT" >/dev/null
rm -f "$PROJECT/qwbuddy/brief-include.md" # 保持验收场景确为任务书末节

# A 判死后在 rm 前暂停；B 同时 acquire。同步点固定，不靠随机竞争。
cat > "$TMP/bin/rm" <<'EOF'
#!/usr/bin/env bash
if [[ "${QWB_HOLD_RM:-}" == 1 && "$*" == *'.controller.lock'* ]]; then
  if [[ -n "${QWB_GUARD_PID_FILE:-}" ]]; then
    ps -o ppid= -p "$PPID" | tr -d ' ' > "$QWB_GUARD_PID_FILE"
  fi
  : > "$QWB_RM_READY"
  read -r _ < "$QWB_RM_GATE"
fi
exec /bin/rm "$@"
EOF
chmod +x "$TMP/bin/rm"
mkfifo "$TMP/gate"
mkdir "$LOCK"
printf '2020-01-01T00:00:00Z pid:999999\n' > "$LOCK/owner"
(
  PATH="$TMP/bin:$PATH" QWB_HOLD_RM=1 QWB_RM_READY="$TMP/ready" QWB_RM_GATE="$TMP/gate" \
    bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$"
) > "$TMP/A.out" 2>&1 &
ap=$!
for _ in {1..200}; do [[ -e "$TMP/ready" ]] && break; sleep 0.01; done
if [[ ! -e "$TMP/ready" ]]; then
  bad "死锁竞争：A 未到达受控回收点"
  cat "$TMP/A.out"
else
  (
    bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:1"
    echo $? > "$TMP/B.rc"
  ) > "$TMP/B.out" 2>&1 &
  bp=$!
  # 旧实现里 B 可在 A 暂停时完成；互斥实现里 B 等 A 离开临界区。
  for _ in {1..100}; do [[ -e "$TMP/B.rc" ]] && break; sleep 0.01; done
  printf 'go\n' > "$TMP/gate"
  wait "$ap"; arc=$?
  wait "$bp"; brc="$(cat "$TMP/B.rc")"
  successes=0
  [[ "$arc" -eq 0 ]] && successes=$((successes+1))
  [[ "$brc" -eq 0 ]] && successes=$((successes+1))
  [[ "$successes" -eq 1 ]] && ok "死锁双竞争者：恰一人获锁" \
    || { bad "死锁双竞争者：A rc=${arc} B rc=${brc}（期望恰一人）"; cat "$TMP/A.out" "$TMP/B.out"; }
fi
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" --owner "pid:$$" >/dev/null
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -eq 0 && -f "$LOCK/owner" ]] && ok "无锁可获" || bad "无锁获取失败：$out"
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -eq 0 && "$(cat "$LOCK/owner")" == *"pid:$$" ]] \
  && ok "同一锁主在 flock 内重入成功" || bad "同一锁主重入失败：$out"
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:999999" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(cat "$LOCK/owner")" == *"pid:$$" ]] \
  && ok "活锁拒绝且 owner 不变" || bad "活锁被夺：$out"
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" --owner "pid:$$" >/dev/null
mkdir "$LOCK"; printf '2020-01-01T00:00:00Z pid:invalid\n' > "$LOCK/owner"
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(cat "$LOCK/owner")" == *"pid:invalid" ]] \
  && ok "无法判活的锁 fail-closed" || bad "未知锁被回收：$out"
cp "$LOCK/owner" "$TMP/unknown-owner.before"
out="$(bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -ne 0 ]] && cmp -s "$LOCK/owner" "$TMP/unknown-owner.before" \
  && ok "release 拒绝未知 owner 且原字节保持" || bad "release 未安全拒绝未知 owner：$out"
# 仅清本测试创建的临时夹具，不把清理伪称为release成功。
rm "$LOCK/owner"; rmdir "$LOCK"
# 正常入口的 Perl 父进程被杀时，仍在 rm 等待的内层回收必须继续持锁。
mkdir "$LOCK"; printf '2020-01-01T00:00:00Z pid:999999\n' > "$LOCK/owner"
mkfifo "$TMP/parent-death-gate"
PATH="$TMP/bin:$PATH" QWB_HOLD_RM=1 QWB_RM_READY="$TMP/parent-death-ready" \
  QWB_RM_GATE="$TMP/parent-death-gate" QWB_GUARD_PID_FILE="$TMP/parent-death-guard-pid" \
  bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" \
  > "$TMP/parent-death-A.out" 2>&1 &
parent_death_a=$!
for _ in {1..200}; do [[ -s "$TMP/parent-death-guard-pid" && -e "$TMP/parent-death-ready" ]] && break; sleep 0.01; done
if [[ ! -s "$TMP/parent-death-guard-pid" || ! -e "$TMP/parent-death-ready" ]]; then
  bad "父进程死亡交错：A 未到达受控回收点"
else
  guard_pid="$(cat "$TMP/parent-death-guard-pid")"
  [[ "$(ps -o comm= -p "$guard_pid" 2>/dev/null)" == *perl* ]] \
    || bad "父进程死亡交错：目标不是正常入口的 Perl 持锁父进程"
  kill -9 "$guard_pid" 2>/dev/null
  (
    bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:1"
    echo $? > "$TMP/parent-death-B.rc"
  ) > "$TMP/parent-death-B.out" 2>&1 &
  parent_death_b=$!
  for _ in {1..100}; do [[ -e "$TMP/parent-death-B.rc" ]] && break; sleep 0.01; done
  [[ ! -e "$TMP/parent-death-B.rc" ]] && ok "父死后内层回收仍持内核锁" \
    || bad "父死后 B 在 A 回收完成前进入临界区：$(cat "$TMP/parent-death-B.rc")"
  printf 'go\n' > "$TMP/parent-death-gate"
  wait "$parent_death_a" 2>/dev/null
  wait "$parent_death_b"
  brc="$(cat "$TMP/parent-death-B.rc")"
  for _ in {1..200}; do [[ -f "$LOCK/owner" ]] && break; sleep 0.01; done
  final_owner="$(cat "$LOCK/owner" 2>/dev/null)"
  [[ "$brc" -ne 0 && "$final_owner" == *"pid:$$" ]] \
    && ok "父死交错后活锁未被夺" \
    || bad "父死交错后 owner 被覆盖：B rc=$brc owner=$final_owner"
fi
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" --owner "pid:$$" >/dev/null

# 假 Herdr 只提供本票会调用的 API，不创建真窗口。
cat > "$TMP/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$QWB_STUB_LOG"
status="$(cat "$QWB_STUB_PROMPT_STATE" 2>/dev/null || echo idle)"
seq="$(cat "$QWB_STUB_PROMPT_SEQ" 2>/dev/null || echo 185)"
prompt_transition() {
  printf '%s\n' "$1" > "$QWB_STUB_PROMPT_STATE"
  printf '%s\n' "$((seq + 1))" > "$QWB_STUB_PROMPT_SEQ"
}
case "$1 $2" in
  "agent get")
    if [[ "${QWB_STUB_FAIL:-}" == agent-query ]]; then
      echo '{"error":{"code":"io_error"}}' >&2; exit 7
    fi
    if [[ "$3" == wT:p1 ]]; then
      if [[ "${QWB_STUB_FAIL:-}" == state-query ]]; then
        cat "$QWB_STUB_AGENT_MISSING" >&2; exit 1
      fi
      if [[ -n "${QWB_STUB_REAL_AGENT_FILE:-}" ]]; then
        cat "$QWB_STUB_REAL_AGENT_FILE"
        [[ "$QWB_STUB_REAL_AGENT_FILE" != *agent-get-missing-real.json ]] || exit 1
        exit 0
      fi
      if [[ -n "${QWB_STUB_ENTER_DELAY_MS:-}" && -s "$QWB_STUB_ENTER_AT" && "$seq" -eq 185 ]] \
        && (( $(cat "$QWB_STUB_NOW") - $(cat "$QWB_STUB_ENTER_AT") >= QWB_STUB_ENTER_DELAY_MS )); then
        prompt_transition working
        seq=186; status=working
      fi
      if [[ -n "${QWB_STUB_CHANGE_AT_MS:-}" && "$(cat "$QWB_STUB_NOW")" -ge "$QWB_STUB_CHANGE_AT_MS" && "$seq" -eq 185 ]]; then
        prompt_transition done
        seq=186; status=done
      fi
      printf 'state-query status=%s seq=%s\n' "$status" "$seq" >> "$QWB_STUB_LOG"
    elif [[ "${QWB_STUB_REUSE:-0}" != 1 ]]; then
      cat "$QWB_STUB_AGENT_MISSING" >&2; exit 1
    fi
    printf '{"id":"cli:agent:get","result":{"type":"agent_info","agent":{"name":"qwb-case","agent_status":"%s","state_change_seq":%s,"pane_id":"wT:p1","agent":"%s","foreground_cwd":"%s","workspace_id":"%s"}}}\n' \
      "$status" "$seq" "${QWB_STUB_WORKER:-pi}" "$QWB_STUB_CWD" "${QWB_STUB_WS:-wT}" |
      jq --arg fault "${QWB_STUB_STATE_FAULT:-}" '
        if $fault=="missing-seq" then del(.result.agent.state_change_seq)
        elif $fault=="string-seq" then .result.agent.state_change_seq="185"
        elif $fault=="null-seq" then .result.agent.state_change_seq=null
        elif $fault=="missing-status" then del(.result.agent.agent_status)
        else . end' ;;
  "pane get")
    if [[ "${QWB_STUB_SHELL:-0}" == 1 ]]; then
      printf '{"result":{"pane":{"foreground_cwd":"%s","workspace_id":"wT","pane_id":"wT:p1"}}}\n' "$QWB_STUB_CWD"
    else
      printf '{"result":{"pane":{"agent":"%s","foreground_cwd":"%s","workspace_id":"%s","pane_id":"wT:p1"}}}\n' \
        "${QWB_STUB_WORKER:-pi}" "$QWB_STUB_CWD" "${QWB_STUB_WS:-wT}" |
        jq --arg session "$QWB_STUB_SESSION" '.result.pane.agent_session={source:"herdr:pi",kind:"path",value:$session}'
    fi | jq --arg status "$status" '.result.pane.agent_status=$status' ;;
  "pane process-info")
    if [[ "${QWB_STUB_SHELL:-0}" == 1 ]]; then
      echo '{"result":{"process_info":{"pane_id":"wT:p1","foreground_process_group_id":42,"shell_pid":42,"foreground_processes":[{"pid":42,"argv0":"zsh"}]}}}'
      exit 0
    fi
    jq -cn --arg dir "$QWB_STUB_CWD" --argjson pid "$QWB_STUB_PID" \
      '{result:{process_info:{pane_id:"wT:p1",foreground_process_group_id:$pid,shell_pid:42,foreground_processes:[{pid:$pid,argv0:"pi",cwd:$dir}]}}}' ;;
  "pane run")
    if [[ "$4" == "'mock-agent'" ]] && {
      ! grep -q '^state: running$' "$QWB_STUB_TASK" ||
      ! grep -q '^scenarios-fp:' "$QWB_STUB_TASK" ||
      ! grep -q '^dispatch:' "$QWB_STUB_TASK"; }; then
      echo '{"error":{"code":"prelaunch_contract_missing"}}' >&2; exit 7
    fi
    if [[ "${QWB_STUB_FAIL:-}" == pane-prompt && "$4" != "'mock-agent'" ]]; then
      echo '{"error":{"code":"inject_failed"}}' >&2; exit 9
    fi
    if [[ "$4" != "'mock-agent'" && "${QWB_STUB_PROMPT_KEEP:-0}" != 1 && "${QWB_STUB_PROMPT_STATUS:-working}" != idle ]]; then
      prompt_transition "${QWB_STUB_PROMPT_STATUS:-working}"
    fi
    echo '{"result":{"type":"ok"}}' ;;
  "workspace list")
    printf '{"result":{"workspaces":[{"workspace_id":"wT","focused":true,"worktree":{"repo_root":"%s"}}]}}\n' "$QWB_STUB_CWD" ;;
  "tab create") echo '{"result":{"root_pane":{"pane_id":"wT:p1","tab_id":"wT:t1","workspace_id":"wT"}}}' ;;
  "agent start")
    if ! grep -q '^state: running$' "$QWB_STUB_TASK" ||
      ! grep -q '^scenarios-fp:' "$QWB_STUB_TASK" ||
      ! grep -q '^dispatch:' "$QWB_STUB_TASK"; then
      echo '{"error":{"code":"prelaunch_contract_missing"}}' >&2; exit 7
    fi
    if [[ "${QWB_STUB_FAIL:-}" == start ]]; then echo '{"error":{"code":"start_failed"}}' >&2; exit 8; fi
    echo '{"result":{"type":"agent_started"}}' ;;
  "agent prompt")
    [[ -z "${QWB_STUB_APPEND:-}" ]] || printf 'working: concurrent-marker\n' >> "$QWB_STUB_APPEND"
    if [[ "${QWB_STUB_FAIL:-}" == prompt ]]; then echo '{"error":{"code":"inject_failed"}}' >&2; exit 9; fi
    if [[ "${QWB_STUB_PROMPT_KEEP:-0}" != 1 && "${QWB_STUB_PROMPT_STATUS:-working}" != idle ]]; then
      prompt_transition "${QWB_STUB_PROMPT_STATUS:-working}"
    fi
    echo '{"result":{"type":"ok"}}' ;;
  "agent wait")
    case "$status" in
      working|done|blocked)
        [[ "$*" == *"--until $status"* ]] || exit 1
        printf '{"result":{"type":"agent_info","agent":{"agent_status":"%s"}}}\n' "$status" ;;
      *) echo '{"error":{"code":"timeout"}}' >&2; exit 1 ;;
    esac ;;
  "pane send-keys")
    [[ "$3 $4" == 'wT:p1 enter' ]] || exit 7
    cat "$QWB_STUB_NOW" > "$QWB_STUB_ENTER_AT"
    [[ "${QWB_STUB_ENTER_STARTS:-0}" != 1 ]] || prompt_transition "${QWB_STUB_ENTER_STATUS:-working}"
    echo '{"result":{"type":"ok"}}' ;;
  "tab close") echo '{"result":{"type":"ok"}}' ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
EOF
chmod +x "$TMP/bin/herdr"
cat > "$PROJECT/qwbuddy/config.sh" <<'EOF'
QWB_WORKERS="pi codex"
QWB_AGENT_START_MS=1000
QWB_WORKSPACE=""
QWB_WORKTREE_SETUP=""
QWB_GATE_FAST=':'
QWB_GATE_FULL=':'
EOF
printf '%s\n' 'qwb_worker pi herdr' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
TASK="$PROJECT/tasks/2099-01-01-case.md"
write_ticket() {
  cat > "$TASK" <<'EOF'
# case
state: blocked
implementation-authorized: explicit fixture scope approval
dispatch-budget: 20

## 1. 验收场景
### 正常
Given 工人可用
When 派发
Then 投递成功
### 失败
Given 投递失败
When 派发
Then 无成功 dispatch
EOF
  if [[ -n "${QWB_STUB_PROMPT_STATE:-}" ]]; then
    echo idle > "$QWB_STUB_PROMPT_STATE"
    echo 185 > "$QWB_STUB_PROMPT_SEQ"
  fi
}
write_ticket
export QWB_STUB_LOG="$TMP/herdr.log" QWB_STUB_CWD="$PROJECT" QWB_STUB_TASK="$TASK"
export QWB_STUB_PID="$$" QWB_STUB_SESSION="$TMP/pi-session.jsonl"
export QWB_STUB_PROMPT_STATE="$TMP/prompt-state" QWB_STUB_PROMPT_SEQ="$TMP/prompt-seq"
export QWB_STUB_AGENT_MISSING="$ROOT/tests/fixtures/herdr/agent-get-missing-real.json"
export QWB_STUB_NOW="$TMP/prompt-now" QWB_STUB_SLEEP_LOG="$TMP/prompt-sleep.log" QWB_STUB_ENTER_AT="$TMP/prompt-enter-at"
RUNTIME_BIN="$TMP/runtime-bin"
cp -R "$ROOT/bin" "$RUNTIME_BIN"
if [[ "${QWB_PROMPT_START_BASELINE:-0}" == 1 ]]; then
  git -C "$ROOT" show 44ab8ac:bin/qwb-run.sh > "$RUNTIME_BIN/qwb-run.sh"
fi
printf '#!/usr/bin/env bash\ncat "$QWB_STUB_NOW"\n' > "$TMP/now-ms.sh"
printf '#!/usr/bin/env bash\necho "$1" >> "$QWB_STUB_SLEEP_LOG"\necho $(( $(cat "$QWB_STUB_NOW") + ${QWB_STUB_SLEEP_BUMP:-5000} )) > "$QWB_STUB_NOW"\n' > "$TMP/sleep-ms.sh"
chmod +x "$TMP/now-ms.sh" "$TMP/sleep-ms.sh"
echo 0 > "$QWB_STUB_NOW"
: > "$QWB_STUB_SLEEP_LOG"
jq -cn --arg dir "$(cd "$PROJECT" && pwd -P)" '{type:"session",cwd:$dir}' > "$QWB_STUB_SESSION"
reuse_proof() {
  jq -cn --arg session "$QWB_STUB_SESSION" --arg start "$(ps -p "$$" -o lstart= | perl -pe 's/^\s+|\s+$//g')" --argjson pid "$$" \
    '{pid:$pid,pid_start:$start,session:$session}' | sed 's/^/working: worker-activity op=fixture pane=wT:p1 evidence=/' >> "$TASK"
}
run_case() {
  (cd "$PROJECT" && PATH="$TMP/bin:$PATH" HERDR_PANE_ID=wT:ctl \
    QWB_NOW_MS_CMD="$TMP/now-ms.sh" QWB_SLEEP_CMD="$TMP/sleep-ms.sh" \
    "$BASH" "$RUNTIME_BIN/qwb-run.sh" --task case --worker pi --here --accept-new-scenarios "$@")
}
mkdir -p "$LOCK"
printf '2020-01-01T00:00:00Z wT:ctl\n' > "$LOCK/owner"
cp "$PROJECT/qwbuddy/bin/qwb-lock.sh" "$TMP/qwb-lock.original"
printf '#!/usr/bin/env bash\nexit 7\n' > "$PROJECT/qwbuddy/bin/qwb-lock.sh"
: > "$QWB_STUB_LOG"
out="$(cd "$PROJECT" && PATH="$TMP/bin:$PATH" HERDR_PANE_ID=wT:ctl \
  bash "$PROJECT/qwbuddy/bin/qwb-run.sh" --task case --worker pi --here --accept-new-scenarios 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^state: blocked$' "$TASK" && ! grep -q 'tab create' "$QWB_STUB_LOG"; then
  ok "锁命令失败即拒绝，即使 owner 文本等于当前 pane"
else
  bad "锁失败仍派发：rc=$rc"; printf '%s\n' "$out"
fi
cp "$TMP/qwb-lock.original" "$PROJECT/qwbuddy/bin/qwb-lock.sh"
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" --owner wT:ctl >/dev/null
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_FAIL=prompt QWB_STUB_APPEND="$TASK" run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^working: concurrent-marker$' "$TASK" \
  && grep -q '^blocked: .*派发投递失败' "$TASK" \
  && grep -q '^scenarios-fp:' "$TASK" \
  && grep -q '^state: running$' "$TASK" \
  && grep -q 'agent prompt qwb-case ' "$QWB_STUB_LOG" \
  && grep -q '^not-sent:' "$TASK" && ! grep -q 'tab close' "$QWB_STUB_LOG"; then
  ok "新建工人提示词失败：非零、撤销 dispatch；活进程/缺证的新 tab 保留"
else
  bad "新建工人提示词失败：rc=$rc dispatch=$(grep -c '^dispatch:' "$TASK" || true)"
  printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi
fp_before="$(sed -n 's/^scenarios-fp: //p' "$TASK" | head -1)"
lint_out="$(bash "$ROOT/bin/qwb-lint.sh" --project "$PROJECT" 2>&1)"; lint_rc=$?
retry_out="$(run_case 2>&1)"; retry_rc=$?
fp_after="$(sed -n 's/^scenarios-fp: //p' "$TASK" | head -1)"
if [[ "$lint_rc" -eq 0 && "$retry_rc" -eq 0 && "$fp_before" == "$fp_after" ]] \
  && [[ -n "$fp_before" ]] && grep -q '^dispatch:' "$TASK"; then
  ok "场景是末节：失败 not-sent 后 lint 与重派认可原冻结指纹"
else
  bad "末节场景兼容：lint rc=$lint_rc retry rc=$retry_rc fp=$fp_before->$fp_after"
  printf '%s\n' "$lint_out" | grep -E '^(FAIL|LINT|错误)' || true
  printf '%s\n' "$lint_out" | sed -n '/FAIL  发现该写法/,+3p'
  printf '%s\n' "$retry_out" | tail -n 5
fi

write_ticket
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q 'agent prompt' "$QWB_STUB_LOG"; then
  ok "同名无本票历史：投递前拒绝"
else
  bad "同名无本票历史：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

write_ticket
printf 'dispatch: historical worker=codex agent=qwb-case pane=wT:p1 dir=%s\n' \
  "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q 'agent prompt' "$QWB_STUB_LOG"; then
  ok "同名但本票历史 worker 不符：投递前拒绝"
else
  bad "本票历史身份不符：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

write_ticket
printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
for mismatch in worker cwd workspace; do
  : > "$QWB_STUB_LOG"
  case "$mismatch" in
    worker) out="$(QWB_STUB_WORKER=codex QWB_STUB_REUSE=1 run_case 2>&1)" ;;
    cwd) out="$(QWB_STUB_CWD="$TMP/wrong" QWB_STUB_REUSE=1 run_case 2>&1)" ;;
    workspace) out="$(QWB_STUB_WS=wOther QWB_STUB_REUSE=1 run_case 2>&1)" ;;
  esac
  rc=$?
  if [[ "$rc" -ne 0 ]] && ! grep -q 'agent prompt' "$QWB_STUB_LOG"; then
    ok "复用 $mismatch 不符：投递前拒绝"
  else
    bad "复用 $mismatch 不符：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
  fi
done

: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 QWB_STUB_FAIL=agent-query run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q 'agent prompt' "$QWB_STUB_LOG" \
  && ! grep -q 'tab create' "$QWB_STUB_LOG"; then
  ok "复用身份查询未知：投递前 fail-closed"
else
  bad "复用查询未知：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

before="$(grep -c '^dispatch:' "$TASK")"
reuse_proof
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 QWB_STUB_FAIL=prompt QWB_STUB_APPEND="$TASK" run_case 2>&1)"; rc=$?
after="$(grep -c '^dispatch:' "$TASK")"
if [[ "$rc" -ne 0 && "$after" -eq "$before" ]] && grep -q 'agent prompt' "$QWB_STUB_LOG" \
  && grep -q '^working: concurrent-marker$' "$TASK" \
  && ! grep -q 'tab close' "$QWB_STUB_LOG"; then
  ok "复用工人提示词失败：历史保留、本次回滚、既有窗口保留"
else
  bad "复用工人提示词失败：rc=$rc dispatch=$before->$after"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

# 显式 --pane 由调用者授权复用，投递失败只撤销本次记录，不关闭既有 pane。
write_ticket
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_SHELL=1 QWB_STUB_FAIL=prompt run_case --pane wT:p1 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^not-sent:' "$TASK" && grep -q 'agent prompt qwb-case ' "$QWB_STUB_LOG" \
  && ! grep -q 'tab close' "$QWB_STUB_LOG"; then
  ok "--pane 提示词失败：既有窗口保留、本次 dispatch 撤销"
else
  bad "--pane 提示词失败：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

# pane-run 使用 pane run 投递提示词；失败非零，未知退出的新 tab 保留。
write_ticket
printf '%s\n' 'qwb_worker pi pane-run mock-agent' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 QWB_STUB_FAIL=pane-prompt run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^not-sent:' "$TASK" && grep -q 'agent rename wT:p1 qwb-case' "$QWB_STUB_LOG" \
  && grep -q 'pane run wT:p1 你是本任务' "$QWB_STUB_LOG" \
  && ! grep -q 'tab close' "$QWB_STUB_LOG"; then
  ok "pane-run 提示词失败：非零、撤销 dispatch，未确认退出的新 tab 保留"
else
  bad "pane-run 提示词失败：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

# 同一假 Herdr 状态机验证三条投递路径；现有时钟/睡眠注入推进等待，不真睡。
prepare_prompt_case() {
  write_ticket
  : > "$QWB_STUB_LOG"
  echo idle > "$QWB_STUB_PROMPT_STATE"
  echo 185 > "$QWB_STUB_PROMPT_SEQ"
  echo 0 > "$QWB_STUB_NOW"
  : > "$QWB_STUB_SLEEP_LOG"
  : > "$QWB_STUB_ENTER_AT"
  printf '%s\n' 'qwb_worker pi herdr' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
}
check_prompt_success() {
  local label="$1" enters="$2" waits="$3" op
  op="$(sed -n 's/^dispatch: .*op_id=\([^ ]*\).*/\1/p' "$TASK" | tail -1)"
  if [[ "$rc" -eq 0 && -n "$op" ]] && grep -q '^已派发：' "$TMP/prompt.out" \
    && [[ "$(grep -c '^pane send-keys wT:p1 enter$' "$QWB_STUB_LOG" || true)" -eq "$enters" ]] \
    && ! grep -q '^agent wait' "$QWB_STUB_LOG" \
    && [[ "$(wc -l < "$QWB_STUB_SLEEP_LOG")" -eq "$((waits - 1))" ]] \
    && ! grep -q 'prompt-submit-enter' "$TASK" \
    && [[ "$(grep -c '^prompt-submit-enter ' "$TMP/prompt.out" || true)" -eq "$enters" ]] \
    && { [[ "$enters" -eq 0 ]] || grep -q "^prompt-submit-enter op=$op pane=wT:p1$" "$TMP/prompt.out"; }; then
    ok "$label"
  else
    bad "${label}：rc=$rc"
    cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG" "$TASK"
  fi
}
# 固定观察副本中的随机op和日期；不过滤输出，逐字节比较同路径同夹具。
python3 -B - "$ROOT" "$TMP" <<'PY'
import subprocess,sys
from pathlib import Path
root,tmp=map(Path,sys.argv[1:])
for version,raw in [('old',subprocess.check_output(['git','-C',str(root),'show','44ab8ac:bin/qwb-run.sh'])),('new',(root/'bin/qwb-run.sh').read_bytes())]:
    needle=b'RUN_OP="$(qwb_op_id)"'
    assert raw.count(needle)==1
    (tmp/('prompt-byte-'+version+'.sh')).write_bytes(raw.replace(needle,b'RUN_OP="0123456789abcdef0123456789abcdef"'))
PY
cat > "$TMP/bin/date" <<'EOF'
#!/bin/sh
if [ "${QWB_PROMPT_FIXED_DATE:-0}" = 1 ] && [ "$*" = '-u +%Y-%m-%dT%H:%M:%SZ' ]; then
  printf '2099-01-01T00:00:00Z\n'
else
  exec /bin/date "$@"
fi
EOF
chmod +x "$TMP/bin/date"
cp "$RUNTIME_BIN/qwb-run.sh" "$TMP/prompt-run.saved"
for mode in first reuse pane-run; do
  for version in old new; do
    prepare_prompt_case
    reuse=0
    if [[ "$mode" == reuse ]]; then
      reuse=1
      printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
      reuse_proof
    elif [[ "$mode" == pane-run ]]; then
      reuse=1
      printf '%s\n' 'qwb_worker pi pane-run mock-agent' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
    fi
    cp "$TMP/prompt-byte-$version.sh" "$RUNTIME_BIN/qwb-run.sh"
    QWB_PROMPT_FIXED_DATE=1 QWB_STUB_REUSE="$reuse" run_case > "$TMP/byte-$mode-$version.out" 2> "$TMP/byte-$mode-$version.err"; rc=$?
    printf '%s\n' "$rc" > "$TMP/byte-$mode-$version.rc"
    cp "$TASK" "$TMP/byte-$mode-$version.ticket"
    cp "$QWB_STUB_LOG" "$TMP/byte-$mode-$version.herdr"
    cp "$QWB_STUB_SLEEP_LOG" "$TMP/byte-$mode-$version.sleep"
  done
  same=1
  for field in out err rc ticket herdr sleep; do
    cmp -s "$TMP/byte-$mode-old.$field" "$TMP/byte-$mode-new.$field" || { same=0; diff -u "$TMP/byte-$mode-old.$field" "$TMP/byte-$mode-new.$field"; }
  done
  if [[ "$same" -eq 1 && "$(cat "$TMP/byte-$mode-new.rc")" -eq 0 && "$(cat "$QWB_STUB_NOW")" -eq 0 ]] \
    && [[ ! -s "$QWB_STUB_SLEEP_LOG" ]] && ! grep -q '^pane send-keys' "$QWB_STUB_LOG"; then
    ok "user_立即开工字节对照 ${mode}：stdout/stderr/rc/票/Herdr与44ab8ac完全相同，零等待"
  else
    bad "user_立即开工字节对照 ${mode} 不一致或发生等待"
  fi
done
cp "$TMP/prompt-run.saved" "$RUNTIME_BIN/qwb-run.sh"

for status in working done blocked; do
  prepare_prompt_case
  QWB_STUB_PROMPT_STATUS="$status" run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  check_prompt_success "prompt-submit 首次立即${status}：一次确认、不补Enter" 0 1
done
for reuse in 0 1; do
  prepare_prompt_case
  if [[ "$reuse" -eq 1 ]]; then
    printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
    reuse_proof
  fi
  QWB_STUB_REUSE="$reuse" QWB_STUB_PROMPT_STATUS=idle QWB_STUB_ENTER_STARTS=1 \
    run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  check_prompt_success "prompt-submit reuse=${reuse}：卡住补一次Enter后二次确认" 1 2
  if [[ "$reuse" -eq 1 ]] && grep -q '^agent start\|^tab create' "$QWB_STUB_LOG"; then
    bad 'prompt-submit 续派错误新建端点'
  fi
done
# 回车之后20秒才working；首次、续派、pane-run共用同一时钟和确认契约。
for mode in first reuse pane-run; do
  prepare_prompt_case
  reuse=0
  if [[ "$mode" == reuse ]]; then
    reuse=1
    printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
    reuse_proof
  elif [[ "$mode" == pane-run ]]; then
    reuse=1
    printf '%s\n' 'qwb_worker pi pane-run mock-agent' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
  fi
  QWB_STUB_REUSE="$reuse" QWB_STUB_PROMPT_STATUS=idle QWB_STUB_ENTER_DELAY_MS=20000 QWB_STUB_SLEEP_BUMP=1000 \
    run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  if [[ "$rc" -eq 0 && "$(cat "$QWB_STUB_ENTER_AT")" -eq 5000 && "$(cat "$QWB_STUB_NOW")" -eq 25000 ]] \
    && [[ "$(grep -c '^pane send-keys wT:p1 enter$' "$QWB_STUB_LOG" || true)" -eq 1 ]] \
    && grep -q '^已派发：' "$TMP/prompt.out" && grep -q '^state-query status=working seq=186$' "$QWB_STUB_LOG" \
    && ! grep -q 'prompt-submit-enter' "$TASK"; then
    ok "user_补回车后二十秒开工 ${mode}：5秒补一次Enter，25秒立即成功"
  else
    bad "user_补回车后二十秒开工 ${mode}：rc=$rc clock=$(cat "$QWB_STUB_NOW") enter=$(cat "$QWB_STUB_ENTER_AT")"
    cat "$TMP/prompt.out" "$TMP/prompt.err"
  fi
done
# 对照原agent prompt失败：检查票、冻结指纹、并发行与端点保留，而非只看返回码。
prepare_prompt_case
QWB_STUB_FAIL=prompt QWB_STUB_APPEND="$TASK" run_case > "$TMP/failure.out" 2> "$TMP/failure.err"; failure_rc=$?
cp "$TASK" "$TMP/failure.ticket"
for mode in herdr pane-run; do
  prepare_prompt_case
  reuse=0
  if [[ "$mode" == pane-run ]]; then
    reuse=1
    printf '%s\n' 'qwb_worker pi pane-run mock-agent' 'qwb_worker codex herdr' > "$PROJECT/qwbuddy/workers.sh"
  fi
  QWB_STUB_REUSE="$reuse" QWB_STUB_PROMPT_STATUS=idle QWB_STUB_APPEND="$TASK" \
    run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  if [[ "$rc" -ne 0 && "$failure_rc" -ne 0 && -d "$PROJECT" ]] \
    && grep -q '提示词已投递但工人未开工.*pane=wT:p1' "$TMP/prompt.err" \
    && grep -q 'herdr pane read wT:p1' "$TMP/prompt.err" \
    && ! grep -q '^已派发：' "$TMP/prompt.out" \
    && [[ "$(grep -c '^pane send-keys wT:p1 enter$' "$QWB_STUB_LOG" || true)" -eq 1 ]] \
    && ! grep -q '^agent wait' "$QWB_STUB_LOG" \
    && grep -q '补回车后仍超时 60000ms' "$TMP/prompt.err" \
    && grep -q 'herdr pane read wT:p1 --source visible；herdr pane process-info --pane wT:p1；herdr agent get wT:p1' "$TMP/prompt.err" \
    && [[ "$rc" -eq 1 && "$(cat "$QWB_STUB_NOW")" -eq 65000 && "$(cat "$QWB_STUB_ENTER_AT")" -eq 5000 \
      && "$(wc -l < "$QWB_STUB_SLEEP_LOG")" -eq 13 ]] \
    && ! grep -q 'prompt-submit-enter' "$TASK" \
    && [[ "$(grep -c '^prompt-submit-enter op=.* pane=wT:p1$' "$TMP/prompt.out" || true)" -eq 1 ]] \
    && grep -q '^not-sent:' "$TASK" && ! grep -q '^dispatch:' "$TASK" \
    && grep -q '^blocked: .*派发投递失败' "$TASK" \
    && grep -q '^state: running$' "$TASK" && grep -q '^scenarios-fp:' "$TASK" \
    && ! grep -q '^tab close' "$QWB_STUB_LOG"; then
    ok "prompt-submit ${mode}：补Enter仍idle则失败，沿用not-sent与端点保留"
  else
    bad "prompt-submit ${mode}：idle被当成功或处置不符 rc=$rc"
    cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG" "$TASK"
  fi
  if [[ "$mode" == herdr ]]; then
    # 归一仅限随机op、时间、不同失败step/rc和新增补Enter记录，其余逐字节比。
    for source in failure.ticket prompt-ticket; do
      [[ "$source" != prompt-ticket ]] || cp "$TASK" "$TMP/$source"
      perl -pe 's/20\d\d-[\dT:Z-]+/TIME/g; s/(?<=op_id=)[a-f0-9]{32}/OP/g; s/(?<=op=)[a-f0-9]{32}/OP/g; s/step=.* rc=\d+/step=FAILURE rc=FAILURE/; $_="" if /prompt-submit-enter/' \
        "$TMP/$source" > "$TMP/$source.normalized"
    done
    cmp -s "$TMP/failure.ticket.normalized" "$TMP/prompt-ticket.normalized" \
      && ok 'prompt-submit 首次idle与agent prompt失败票处置字节一致（动态字段与新增记录除外）' \
      || { bad 'prompt-submit 首次idle与prompt失败处置不同'; diff -u "$TMP/failure.ticket.normalized" "$TMP/prompt-ticket.normalized"; }
  fi
done

# 续派必须观察本轮活动，上一轮done不算提交。原生状态序号来自同一pane响应。
for behavior in enter unchanged new-done; do
  prepare_prompt_case
  echo done > "$QWB_STUB_PROMPT_STATE"
  printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
  reuse_proof
  case "$behavior" in
    enter) QWB_STUB_REUSE=1 QWB_STUB_PROMPT_KEEP=1 QWB_STUB_ENTER_STARTS=1 QWB_STUB_ENTER_STATUS=done run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?; expected_enters=1 ;;
    unchanged) QWB_STUB_REUSE=1 QWB_STUB_PROMPT_KEEP=1 run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?; expected_enters=1 ;;
    new-done) QWB_STUB_REUSE=1 QWB_STUB_PROMPT_STATUS=done run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?; expected_enters=0 ;;
  esac
  if [[ "$(grep -c '^pane send-keys wT:p1 enter$' "$QWB_STUB_LOG" || true)" -eq "$expected_enters" ]] \
    && { if [[ "$behavior" == unchanged ]]; then
      [[ "$rc" -ne 0 && "$(cat "$QWB_STUB_PROMPT_SEQ")" -eq 185 ]] \
        && ! grep -q '^已派发：' "$TMP/prompt.out" \
        && grep -q '提示词已投递但工人未开工' "$TMP/prompt.err" \
        && [[ "$(grep -c '^dispatch:' "$TASK")" -eq 1 ]] && grep -q '^not-sent:' "$TASK"
    else
      [[ "$rc" -eq 0 && "$(cat "$QWB_STUB_PROMPT_SEQ")" -eq 186 ]] \
        && grep -q '^已派发：' "$TMP/prompt.out" \
        && grep -q '^state-query status=done seq=186$' "$QWB_STUB_LOG"
    fi; }; then
    ok "prompt-submit 续派前done ${behavior}：按本轮序号判定"
  else
    bad "prompt-submit 续派前done ${behavior}：rc=$rc"
    cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG" "$TASK"
  fi
done
prepare_prompt_case
printf 'dispatch: historical worker=pi agent=qwb-case pane=wT:p1 dir=%s\n' "$(cd "$PROJECT" && pwd -P)" >> "$TASK"
reuse_proof
echo done > "$QWB_STUB_PROMPT_STATE"
QWB_STUB_REUSE=1 QWB_STUB_PROMPT_KEEP=1 QWB_STUB_CHANGE_AT_MS=100 QWB_STUB_SLEEP_BUMP=100 \
  run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
if [[ "$rc" -eq 0 && "$(cat "$QWB_STUB_NOW")" -eq 100 && "$(cat "$QWB_STUB_PROMPT_SEQ")" -eq 186 ]] \
  && ! grep -q '^pane send-keys' "$QWB_STUB_LOG" && grep -q '^state-query status=done seq=186$' "$QWB_STUB_LOG"; then
  ok 'prompt-submit 续派前done：时限内下一次轮询发现新done，不误补Enter'
else
  bad 'prompt-submit 续派前done：没有在原时限内轮询新序号'
  cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG"
fi
for fault in missing-seq string-seq null-seq missing-status query-failed; do
  prepare_prompt_case
  if [[ "$fault" == query-failed ]]; then
    QWB_STUB_FAIL=state-query run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  else
    QWB_STUB_STATE_FAULT="$fault" run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  fi
  if [[ "$rc" -ne 0 ]] && ! grep -q '^agent prompt\|^pane send-keys' "$QWB_STUB_LOG" \
    && ! grep -q '^已派发：' "$TMP/prompt.out"; then
    ok "prompt-submit 投递前${fault}：无提示词/Enter、失败关闭"
  else
    bad "prompt-submit 投递前${fault}：rc=$rc"
    cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG"
  fi
done

# 离线真实样本契约：pane没有序号，Pi终态和Claude working的agent应答都可解析。
python3 -B - "$ROOT/tests/fixtures/herdr" <<'PY'
import json,sys
from pathlib import Path
p=Path(sys.argv[1])
pi=json.loads((p/'agent-get-pi-done-real.json').read_text())['result']['agent']
claude=json.loads((p/'agent-get-claude-working-real.json').read_text())['result']['agent']
pane=json.loads((p/'pane-get-pi-done-real.json').read_text())['result']['pane']
missing=json.loads((p/'agent-get-missing-real.json').read_text())
assert pi['agent_status']=='done' and pi['state_change_seq']==453
assert claude['agent_status']=='working' and claude['state_change_seq']==454 and 'completion_seq' not in claude
assert 'state_change_seq' not in pane and missing['error']['code']=='agent_not_found'
PY
[[ "$?" -eq 0 ]] && ok '真实应答契约：序号仅agent get提供，completion_seq不是共同必需字段' || bad '真实应答形状不符'
for sample in agent-get-pi-done agent-get-claude-working agent-get-missing; do
  prepare_prompt_case
  QWB_STUB_REAL_AGENT_FILE="$ROOT/tests/fixtures/herdr/$sample-real.json" \
    run_case > "$TMP/prompt.out" 2> "$TMP/prompt.err"; rc=$?
  case "$sample" in
    agent-get-pi-done)
      [[ "$rc" -ne 0 ]] && grep -q '提示词已投递但工人未开工' "$TMP/prompt.err" \
        && [[ "$(grep -c '^pane send-keys wT:p1 enter$' "$QWB_STUB_LOG" || true)" -eq 1 ]] ;;
    agent-get-claude-working)
      [[ "$rc" -eq 0 ]] && grep -q '^已派发：' "$TMP/prompt.out" && ! grep -q '^pane send-keys' "$QWB_STUB_LOG" ;;
    agent-get-missing)
      [[ "$rc" -ne 0 ]] && grep -q 'agent_not_found' "$TMP/prompt.err" && ! grep -q '^agent prompt\|^pane send-keys' "$QWB_STUB_LOG" ;;
  esac
  if [[ "$?" -eq 0 ]]; then
    ok "真实agent get回放 ${sample}：按实际契约确认或拒绝"
  else
    bad "真实agent get回放 ${sample}：rc=$rc"
    cat "$TMP/prompt.out" "$TMP/prompt.err" "$QWB_STUB_LOG"
  fi
done
# 所有模拟pane应答都没有序号，首次/续派/pane-run仍应正常确认。
PATH="$TMP/bin:$PATH" "$TMP/bin/herdr" pane get wT:p1 > "$TMP/pane-shape.json"
if jq -e '.result.pane | has("state_change_seq") | not' "$TMP/pane-shape.json" >/dev/null; then
  ok '模拟pane get不携带state_change_seq'
else
  bad '模拟pane get错误携带state_change_seq'
fi

[[ "$FAILS" -eq 0 ]] && echo "RUNTIME READINESS PASS" || { echo "RUNTIME READINESS FAIL ($FAILS)"; exit 1; }
