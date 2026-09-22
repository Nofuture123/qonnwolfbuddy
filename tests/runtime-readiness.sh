#!/usr/bin/env bash
# 定向运行时负例；由 smoke.sh 调用，也可单独运行。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
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
    bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$"
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
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" >/dev/null
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -eq 0 && -f "$LOCK/owner" ]] && ok "无锁可获" || bad "无锁获取失败：$out"
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:999999" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(cat "$LOCK/owner")" == *"pid:$$" ]] \
  && ok "活锁拒绝且 owner 不变" || bad "活锁被夺：$out"
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" >/dev/null
mkdir "$LOCK"; printf '2020-01-01T00:00:00Z pid:invalid\n' > "$LOCK/owner"
out="$(bash "$ROOT/bin/qwb-lock.sh" acquire --project "$PROJECT" --owner "pid:$$" 2>&1)"; rc=$?
[[ "$rc" -ne 0 && "$(cat "$LOCK/owner")" == *"pid:invalid" ]] \
  && ok "无法判活的锁 fail-closed" || bad "未知锁被回收：$out"
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" >/dev/null
[[ ! -d "$LOCK" ]] && ok "release 清理锁目录" || bad "release 未清理锁目录"
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
bash "$ROOT/bin/qwb-lock.sh" release --project "$PROJECT" >/dev/null

# 假 Herdr 只提供本票会调用的 API，不创建真窗口。
cat > "$TMP/bin/herdr" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$QWB_STUB_LOG"
case "$1 $2" in
  "agent get")
    if [[ "${QWB_STUB_FAIL:-}" == agent-query ]]; then
      echo '{"error":{"code":"io_error"}}' >&2; exit 7
    fi
    if [[ "${QWB_STUB_REUSE:-0}" == 1 ]]; then
      printf '{"result":{"agent":{"name":"qwb-case","agent_status":"idle","pane_id":"wT:p1","agent":"%s","foreground_cwd":"%s","workspace_id":"%s"}}}\n' \
        "${QWB_STUB_WORKER:-pi}" "$QWB_STUB_CWD" "${QWB_STUB_WS:-wT}"
    else
      echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1
    fi ;;
  "pane get")
    if [[ "${QWB_STUB_SHELL:-0}" == 1 ]]; then
      printf '{"result":{"pane":{"foreground_cwd":"%s","workspace_id":"wT","pane_id":"wT:p1"}}}\n' "$QWB_STUB_CWD"
    else
      printf '{"result":{"pane":{"agent":"%s","foreground_cwd":"%s","workspace_id":"%s","pane_id":"wT:p1"}}}\n' \
        "${QWB_STUB_WORKER:-pi}" "$QWB_STUB_CWD" "${QWB_STUB_WS:-wT}"
    fi ;;
  "pane process-info")
    echo '{"result":{"process_info":{"foreground_process_group_id":42,"shell_pid":42}}}' ;;
  "pane run")
    if [[ "$4" == mock-agent ]] && {
      ! grep -q '^state: running$' "$QWB_STUB_TASK" ||
      ! grep -q '^scenarios-fp:' "$QWB_STUB_TASK" ||
      ! grep -q '^dispatch:' "$QWB_STUB_TASK"; }; then
      echo '{"error":{"code":"prelaunch_contract_missing"}}' >&2; exit 7
    fi
    if [[ "${QWB_STUB_FAIL:-}" == pane-prompt && "$4" != mock-agent ]]; then
      echo '{"error":{"code":"inject_failed"}}' >&2; exit 9
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
    echo '{"result":{"type":"ok"}}' ;;
  "tab close") echo '{"result":{"type":"ok"}}' ;;
  *) echo '{"result":{"type":"ok"}}' ;;
esac
EOF
chmod +x "$TMP/bin/herdr"
cat > "$PROJECT/qwbuddy/config.sh" <<'EOF'
QWB_WORKERS="pi codex"
QWB_WORKER_LAUNCH=""
QWB_WORKER_ARGS=""
QWB_AGENT_START_MS=1000
QWB_WORKSPACE=""
QWB_WORKTREE_SETUP=""
QWB_GATE_FAST=':'
QWB_GATE_FULL=':'
EOF
TASK="$PROJECT/tasks/2099-01-01-case.md"
write_ticket() {
  cat > "$TASK" <<'EOF'
# case
state: blocked

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
}
write_ticket
export QWB_STUB_LOG="$TMP/herdr.log" QWB_STUB_CWD="$PROJECT" QWB_STUB_TASK="$TASK"
run_case() {
  (cd "$PROJECT" && PATH="$TMP/bin:$PATH" HERDR_PANE_ID=wT:ctl \
    bash "$ROOT/bin/qwb-run.sh" --task case --worker pi --here --accept-new-scenarios "$@")
}
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_FAIL=prompt QWB_STUB_APPEND="$TASK" run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^working: concurrent-marker$' "$TASK" \
  && grep -q '^blocked: .*派发投递失败' "$TASK" \
  && grep -q '^scenarios-fp:' "$TASK" \
  && grep -q '^state: running$' "$TASK" \
  && grep -q 'agent prompt qwb-case ' "$QWB_STUB_LOG" \
  && grep -q 'tab close wT:t1' "$QWB_STUB_LOG"; then
  ok "新建工人提示词失败：非零、回滚 dispatch 与新 tab"
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

# pane-run 使用 pane run 投递提示词；失败同样非零并关闭本次新 tab。
write_ticket
printf 'QWB_WORKER_LAUNCH="pi=pane-run:mock-agent"\n' >> "$PROJECT/qwbuddy/config.sh"
: > "$QWB_STUB_LOG"
out="$(QWB_STUB_REUSE=1 QWB_STUB_FAIL=pane-prompt run_case 2>&1)"; rc=$?
if [[ "$rc" -ne 0 ]] && ! grep -q '^dispatch:' "$TASK" \
  && grep -q '^not-sent:' "$TASK" && grep -q 'agent rename wT:p1 qwb-case' "$QWB_STUB_LOG" \
  && grep -q 'pane run wT:p1 你是本任务' "$QWB_STUB_LOG" \
  && grep -q 'tab close wT:t1' "$QWB_STUB_LOG"; then
  ok "pane-run 提示词失败：非零、撤销 dispatch 与本次 tab"
else
  bad "pane-run 提示词失败：rc=$rc"; printf '%s\n' "$out"; cat "$QWB_STUB_LOG"
fi

[[ "$FAILS" -eq 0 ]] && echo "RUNTIME READINESS PASS" || { echo "RUNTIME READINESS FAIL ($FAILS)"; exit 1; }
