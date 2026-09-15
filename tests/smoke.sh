#!/usr/bin/env bash
# tests/smoke.sh —— QW buddy 冒烟测试（不需要 herdr，可在干净环境跑）
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0

ok()   { echo "PASS  $1"; }
bad()  { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
chk()  { if "$@" >/dev/null 2>&1; then ok "$*"; else bad "$*"; fi; }
assert_file() { [[ -f "$1" ]] && ok "存在 $1" || bad "缺文件 $1"; }
assert_dir()  { [[ -d "$1" ]] && ok "存在 $1" || bad "缺目录 $1"; }

echo "== 1. bash -n 语法检查 =="
for s in "$ROOT"/bin/qwb-*.sh; do chk bash -n "$s"; done

echo "== 2. shellcheck =="
if command -v shellcheck >/dev/null 2>&1; then
  for s in "$ROOT"/bin/qwb-*.sh; do chk shellcheck "$s"; done
else
  echo "SKIP  本机无 shellcheck，跳过"
fi

echo "== 3. qwb-init.sh 装进临时假项目 =="
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null || bad "qwb-init.sh 运行失败"

assert_file "$TMP/qwbuddy/QWBUDDY.md"
for r in 主控 审核者 执行者 咨询师; do assert_file "$TMP/qwbuddy/roles/$r.md"; done
assert_file "$TMP/qwbuddy/config.sh"
for s in init run wake status lock worktree; do assert_file "$TMP/qwbuddy/bin/qwb-$s.sh"; done
assert_dir  "$TMP/tasks"
assert_dir  "$TMP/tasks/lessons"
grep -qF 'qwbuddy/QWBUDDY.md' "$TMP/AGENTS.md" && ok "AGENTS.md 有钩子" || bad "AGENTS.md 无钩子"
grep -qF 'qwbuddy/QWBUDDY.md' "$TMP/CLAUDE.md" && ok "CLAUDE.md 有钩子" || bad "CLAUDE.md 无钩子"

# 幂等：再跑一次，钩子不得重复
bash "$ROOT/bin/qwb-init.sh" "$TMP" >/dev/null || bad "qwb-init.sh 二次运行失败"
for f in AGENTS.md CLAUDE.md; do
  n="$(grep -cF 'qwbuddy/QWBUDDY.md' "$TMP/$f" || true)"
  [[ "$n" == "1" ]] && ok "$f 钩子未重复" || bad "$f 钩子重复（$n 处）"
done

echo "== 4. qwb-status.sh 对空账本 =="
( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh ) >/dev/null && ok "status 空账本退出 0" || bad "status 空账本非 0"

echo "== 5. config.sh 可被 source 且值正确（G3）=="
if ( . "$TMP/qwbuddy/config.sh"; [[ "$QWB_WORKERS" == "codex pi claude" && "$QWB_AGENT_START_MS" == "30000" && "$QWB_WAKE_INTERVAL_MS" == "120000" ]] ); then
  ok "config.sh source 后三个配置值正确"
else
  bad "config.sh source 失败或配置值不对"
fi

echo "== 6. qwb-wake.sh --dry-run 未结项判定 =="
FAKE="$TMP/tasks/2099-01-01-fake.md"
printf '# 假任务\nstate: running\n' > "$FAKE"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '2099-01-01-fake' && ok "state=running 列为未结项" || bad "state=running 未列为未结项"
grep -q '^wake:' "$FAKE" && bad "dry-run 写了 wake 行" || ok "dry-run 无副作用（无 wake 行）"

printf '# 假任务\nstate: verified\n' > "$FAKE"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '2099-01-01-fake' && bad "state=verified 仍列为未结项" || ok "state=verified 不再列为未结项"

echo "== 7. stub herdr：qwb-wake.sh --once 有未结项退出 0（回归 Bug 2）=="
STUB="$TMP/stubbin"; STUBLOG="$TMP/herdr-calls.log"
FIXDIR="$ROOT/tests/fixtures/herdr"
mkdir -p "$STUB"
# 契约 stub：响应全部来自 tests/fixtures/herdr/ 真录样本（剔 # 注释行），不再硬编码 JSON。
# 可选行为：HERDR_FAIL=run|wait 让对应调用按真实错误形状失败；
#          HERDR_WAIT_BUMP_MS + QWB_FAKE_NOW_FILE 让 agent wait 把假时钟往前推（模拟等待耗时）。
cat > "$STUB/herdr" <<EOF
#!/usr/bin/env bash
echo "herdr \$*" >> "$STUBLOG"
fix() { sed '/^#/d' "\${HERDR_FIXDIR:-$FIXDIR}/\$1"; }
case "\${1:-} \${2:-}" in
  "pane run")   if [[ "\${HERDR_FAIL:-}" == *run* ]]; then fix pane-run-error.json >&2; exit 1; fi
                fix pane-run.json ;;
  "agent wait") if [[ "\${HERDR_FAIL:-}" == *wait* ]]; then fix agent-wait-timeout.json >&2; exit 1; fi
                if [[ -n "\${QWB_FAKE_NOW_FILE:-}" && "\${HERDR_WAIT_BUMP_MS:-0}" -gt 0 ]]; then
                  echo \$(( \$(cat "\$QWB_FAKE_NOW_FILE") + \${HERDR_WAIT_BUMP_MS} )) > "\$QWB_FAKE_NOW_FILE"
                fi
                fix agent-wait.json ;;
  "tab create") fix tab-create.json ;;
  "agent start") fix agent-start.json ;;
  "agent prompt") fix agent-prompt.json ;;
  "agent list") fix agent-list.json ;;
  *) fix agent-wait.json ;;
esac
exit 0
EOF
chmod +x "$STUB/herdr"

printf '# 假任务\nstate: running\n' > "$FAKE"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null \
  && ok "wake --once 有未结项退出 0" || bad "wake --once 有未结项非 0"
grep -q '^wake:' "$FAKE" && ok "已写 wake: 去重行" || bad "未写 wake: 去重行"
grep -q 'pane run' "$STUBLOG" && ok "stub 日志有 pane run 叫醒" || bad "stub 日志无 pane run"

echo "== 8. 变量后紧跟非 ASCII 字符扫描（回归 Bug 1）=="
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$ROOT"/bin/*.sh <<'PYEOF'
import re, sys
pat = re.compile(r'\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7F]')
bad = 0
for path in sys.argv[1:]:
    for i, line in enumerate(open(path, encoding='utf-8'), 1):
        for m in pat.finditer(line):
            print(f'{path}:{i}: {m.group(0)}')
            bad += 1
sys.exit(1 if bad else 0)
PYEOF
  then ok "bin/*.sh 无 \$VAR+非ASCII 写法"; else bad "bin/*.sh 存在 \$VAR+非ASCII 写法"; fi
else
  echo "SKIP  无 python3，跳过扫描"
fi

echo "== 9. qwb-run.sh 真实派发（stub herdr）=="
DISP="$TMP/tasks/2099-01-02-disp.md"
printf '# 派发测试\nstate: blocked\n' > "$DISP"
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null \
  && ok "qwb-run.sh 派发退出 0" || bad "qwb-run.sh 派发非 0"
grep -q '^state: running' "$DISP" && ok "任务书 state 变为 running" || bad "任务书 state 未变 running"
grep -q '^dispatch:' "$DISP" && ok "任务书末尾有 dispatch: 行" || bad "任务书无 dispatch: 行"
grep -q 'agent start' "$STUBLOG" && ok "stub 日志有 agent start" || bad "stub 日志无 agent start"
grep -q 'agent prompt' "$STUBLOG" && ok "stub 日志有 agent prompt" || bad "stub 日志无 agent prompt"
grep -qF "$DISP" "$STUBLOG" && ok "prompt 参数含任务书绝对路径" || bad "prompt 参数缺任务书绝对路径"

echo "== 10. F3 回归：工人追加 done: → 进展指纹变 → 再次叫醒 =="
F3F="$TMP/tasks/2099-01-03-f3.md"
printf '# F3\nstate: running\nwake: 2026-01-01T00:00:00Z state=running fp=0000oldfp\n' > "$F3F"
printf 'done: 工人完成，附检查证据\n' >> "$F3F"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-03-f3' \
  && ok "追加 done: 后再次列为未结项" || bad "追加 done: 后仍未列为未结项"
# 真跑一轮写下新指纹；之后账本不再变 → 不再叫
( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-03-f3' \
  && bad "进展未变仍重复叫" || ok "写下新指纹后进展未变→不再叫"
# 兼容旧格式：无 fp= 的 wake 行视为指纹不同 → 允许再叫
F3O="$TMP/tasks/2099-01-05-f3old.md"
printf '# 旧格式\nstate: running\nwake: 2026-01-01T00:00:00Z state=running\n' > "$F3O"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once )"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-05-f3old' \
  && ok "无 fp= 的旧 wake 行→仍列为未结项" || bad "无 fp= 的旧 wake 行被误跳过"

echo "== 11. F4 回归：投递失败不终止值守、不写 wake 行 =="
F4F="$TMP/tasks/2099-01-04-f4.md"
printf '# F4\nstate: running\n' > "$F4F"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_FAIL=run bash qwbuddy/bin/qwb-wake.sh --once --pane wtest:p9 ) >/dev/null 2>&1 \
  && ok "投递失败时 --once 退出码 0" || bad "投递失败时 --once 非 0"
grep -q '^wake:' "$F4F" && bad "投递失败仍写了 wake 行" || ok "投递失败未写 wake 行"

# —— 假时钟装置（QWB_NOW_MS_CMD / QWB_SLEEP_CMD 注入）：预算断言不再真 sleep ——
# now.sh 每次调用 +STEP；sleep.sh 记参数不真睡，满 N 次杀掉 wake.sh 截断循环；看门狗防死循环。
FKN="$TMP/fake-now"; FKS="$TMP/fake-sleep.log"
mk_fakeclock() { # $1=STEP $2=截断次数
  echo 0 > "$FKN"; : > "$FKS"
  cat > "$TMP/now.sh" <<EOF
#!/usr/bin/env bash
cur="\$(( \$(cat "$FKN") + $1 ))"; echo "\$cur" > "$FKN"; echo "\$cur"
EOF
  cat > "$TMP/sleep.sh" <<EOF
#!/usr/bin/env bash
echo "\$1" >> "$FKS"
[[ "\$(wc -l < "$FKS" | tr -d ' ')" -ge $2 ]] && kill "\$PPID" 2>/dev/null
exit 0
EOF
  chmod +x "$TMP/now.sh" "$TMP/sleep.sh"
}
run_wake_fakeclock() { # 调用方以 `VAR=x run_wake_fakeclock` 形式传额外环境变量
  ( cd "$TMP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$TMP/now.sh" QWB_SLEEP_CMD="$TMP/sleep.sh" \
      QWB_FAKE_NOW_FILE="$FKN" HERDR_FAIL="${HERDR_FAIL:-}" HERDR_WAIT_BUMP_MS="${HERDR_WAIT_BUMP_MS:-0}" \
      exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
  WPID=$!
  ( sleep 5; kill "$WPID" 2>/dev/null ) & WD=$!
  wait "$WPID" 2>/dev/null || true
  kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null || true
}
# 等待预算需要一个带 dispatch: pane 的未结项
FCF="$TMP/tasks/2099-01-20-fakeclock.md"
printf '# fc\nstate: running\ndispatch: 2026-01-01T00:00:00Z worker=codex agent=qwb-fc pane=wtest:p9 dir=/tmp\n' > "$FCF"
all_eq() { # 全部行 == $1 且非空
  local want="$1" l
  [[ -s "$FKS" ]] || return 1
  while IFS= read -r l; do [[ "$l" == "$want" ]] || return 1; done < "$FKS"; return 0
}

echo "== 12. F2 回归（假时钟）：agent wait 失败 → 每轮恰 1 次 wait + 补睡满 1×interval，无忙循环 =="
mk_fakeclock 250 3
: > "$STUBLOG"
HERDR_FAIL=wait run_wake_fakeclock
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 agent wait + 3 次补睡（每轮恰一次）" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 750 && ok "每轮补睡 750ms（interval 1000 − wait 已耗 250 = 恰 1×interval）" \
  || { bad "补睡值不对（应全 750）:"; cat "$FKS"; }

echo "== 12b. G2 回归（假时钟）：agent wait 耗时计入预算，超时路径不重复 sleep =="
mk_fakeclock 50 3
: > "$STUBLOG"
HERDR_WAIT_BUMP_MS=600 run_wake_fakeclock   # wait 烧掉 600ms → dt=650 → 应补睡 350，旧实现会再睡 1000
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 wait + 3 次补睡" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 350 && ok "wait 耗 650ms 后只补睡 350ms（已耗计入预算；旧实现会睡满 1000）" \
  || { bad "补睡值不对（应全 350）:"; cat "$FKS"; }
grep -qx '1000' "$FKS" && bad "出现整睡 1000——超时路径仍重复 sleep（G2 未修）" \
  || ok "无整睡 1000：超时路径未重复 sleep"

echo "== 12c. H2 回归（假时钟）：agent wait 立即成功也计入预算，无忙循环 =="
mk_fakeclock 1 3                          # 每次读钟仅 +1ms → wait 视为瞬时 → 应补睡 999
: > "$STUBLOG"
run_wake_fakeclock
nsl="$(wc -l < "$FKS" | tr -d ' ')"; nwt="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$nsl" == "3" && "$nwt" == "3" ]] \
  && ok "3 轮 = 3 次 wait + 3 次补睡（不真睡也不忙循环）" || bad "轮次不符：wait=${nwt} sleep=${nsl}"
all_eq 999 && ok "瞬时 wait 每轮补睡 999ms ≈1×interval（修复前实测 4.9 秒 91 轮）" \
  || { bad "补睡值不对（应全 999）:"; cat "$FKS"; }

echo "== 12d. 无 dispatch pane 路径：整睡一个 interval =="
NP="$TMP/nopane"; mkdir -p "$NP/tasks" "$NP/qwbuddy"
printf '# np\nstate: running\n' > "$NP/tasks/2099-01-21-np.md"
cp "$TMP/qwbuddy/config.sh" "$NP/qwbuddy/config.sh"
mk_fakeclock 100 2
( cd "$NP" && PATH="$STUB:$PATH" QWB_NOW_MS_CMD="$TMP/now.sh" QWB_SLEEP_CMD="$TMP/sleep.sh" \
    exec bash "$TMP/qwbuddy/bin/qwb-wake.sh" --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
WPID=$!
( sleep 5; kill "$WPID" 2>/dev/null ) & WD=$!
wait "$WPID" 2>/dev/null || true
kill "$WD" 2>/dev/null; wait "$WD" 2>/dev/null || true
all_eq 1000 && ok "无可用 pane 时每轮整睡 1000ms（=1×interval 退化等待）" \
  || { bad "整睡值不对（应全 1000）:"; cat "$FKS"; }

echo "== 12e. 真时钟轻量冒烟：真跑一轮 =="
: > "$STUBLOG"
( cd "$TMP" && PATH="$STUB:$PATH" exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 600 ) >/dev/null 2>&1 &
WPID=$!
sleep 1.3
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null || true
n="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$n" -ge 1 && "$n" -le 4 ]] \
  && ok "1.3 秒内 ${n} 次 agent wait（真时钟真跑，节奏正常）" || bad "1.3 秒内 ${n} 次 agent wait（异常）"

echo "== 13. F1 回归：主控锁 =="
LOCKD="$TMP/qwbuddy/.controller.lock"
rm -rf "$LOCKD"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "acquire 成功" || bad "acquire 失败"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p8 ) >/dev/null 2>&1 \
  && bad "第二次 acquire 竟成功" || ok "持锁时第二次 acquire 被拒"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh status ) | grep -q 'wtest:p9' \
  && ok "status 显示锁主" || bad "status 未显示锁主"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh release ) >/dev/null \
  && ok "release 成功" || bad "release 失败"
( cd "$TMP" && bash qwbuddy/bin/qwb-lock.sh acquire --owner wtest:p9 ) >/dev/null \
  && ok "release 后可再 acquire" || bad "release 后 acquire 失败"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:p7 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null 2>&1 \
  && bad "他人持锁时 qwb-run.sh 仍派发" || ok "他人持锁时 qwb-run.sh 拒绝派发"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_PANE_ID=wtest:p9 bash qwbuddy/bin/qwb-run.sh --task disp --worker codex --worktree "$TMP" ) >/dev/null \
  && ok "自持锁时可派发" || bad "自持锁时派发被拒"
rm -rf "$LOCKD"

echo "== 14. R2：config.sh 无死配置 =="
ckeys="$(sed -n 's/^\(QWB_[A-Z_]*\)=.*/\1/p' "$TMP/qwbuddy/config.sh")"
[[ -n "$ckeys" ]] || bad "config.sh 未提取到 QWB_* 键"
for k in $ckeys; do
  if grep -q "$k" "$ROOT"/bin/qwb-*.sh; then ok "$k 有脚本读取"; else bad "$k 是死配置（bin/ 无引用）"; fi
done

echo "== 15. R3+G3：--worker 非法名被拒（整词精确匹配）=="
r3out=""
for wname in workers '(codex)' note; do
  : > "$STUBLOG"
  if r3out="$( cd "$TMP" && PATH="$STUB:$PATH" bash qwbuddy/bin/qwb-run.sh --task disp --worker "$wname" 2>&1 )"; then
    bad "--worker ${wname} 竟被接受"
  else
    ok "--worker ${wname} 被拒绝（退出码非 0）"
  fi
  grep -q 'agent start' "$STUBLOG" && bad "--worker ${wname} 仍调用了 herdr agent start" || ok "--worker ${wname} 未调用 agent start"
done
printf '%s' "$r3out" | grep -q 'codex pi claude' && ok "报错列出全部合法工人名" || bad "报错未列出合法工人名"

echo "== 16. R4：非法 state 变可见 =="
ILF="$TMP/tasks/2099-01-06-illegal.md"
printf '# 非法状态\nstate: pending\n' > "$ILF"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-status.sh 2>&1 )"
printf '%s' "$out" | grep -q '非法' && ok "status 对 state=pending 显示非法标记" || bad "status 未标非法 state"
out="$( cd "$TMP" && bash qwbuddy/bin/qwb-wake.sh --dry-run --once 2>&1 )"
printf '%s' "$out" | grep -q 'state=pending 非法' && ok "wake 对 state=pending 发 stderr 警告" || bad "wake 未警告非法 state"
printf '%s' "$out" | grep -q '未结项（将叫醒）: 2099-01-06-illegal' \
  && bad "非法 state 被列为未结项" || ok "非法 state 不算未结项"

echo "== 17. R1：qwb-worktree.sh 端到端（临时 git 项目）=="
GP="$TMP/gitp"
mkdir -p "$GP/tasks" "$GP/.worktrees" "$GP/qwbuddy"
cp "$TMP/qwbuddy/config.sh" "$GP/qwbuddy/config.sh"
git -C "$GP" init -q
git -C "$GP" -c user.email=t@t.t -c user.name=t commit -qm init --allow-empty
WTB="$TMP/qwbuddy/bin/qwb-worktree.sh"

WTID="wtdemo"; WTF="$GP/tasks/2099-01-07-${WTID}.md"
printf '# demo\nstate: running\n' > "$WTF"
git -C "$GP" worktree add -q -b "$WTID" "$GP/.worktrees/$WTID"
out="$(bash "$WTB" list --project "$GP")"
printf '%s' "$out" | grep -q "未结项.*${WTID}" && ok "list 标出未结项 worktree" || bad "list 未标出未结项"
mkdir -p "$GP/.worktrees/orphan"
out="$(bash "$WTB" list --project "$GP")"
printf '%s' "$out" | grep -q '残留.*orphan' && ok "list 标出残留目录" || bad "list 未标出残留"

# --merged 对未合并分支拒绝（先在分支上做个 commit 让它领先 HEAD）
git -C "$GP/.worktrees/$WTID" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
if bash "$WTB" finish "$WTID" --merged --project "$GP" >/dev/null 2>&1; then
  bad "--merged 对未合并分支竟放行"
else
  ok "--merged 对未合并分支拒绝"
fi
[[ -d "$GP/.worktrees/$WTID" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 被删"

# --keep：不动 git，只记账
bash "$WTB" finish "$WTID" --keep=等使用者裁决 --project "$GP" >/dev/null \
  && ok "finish --keep 退出 0" || bad "finish --keep 失败"
grep -q '^worktree: keep' "$WTF" && ok "任务书追加了 worktree: keep 行" || bad "任务书无 worktree: 行"
[[ -d "$GP/.worktrees/$WTID" ]] && ok "--keep 未删 worktree" || bad "--keep 删了 worktree"

# --archive：打 tag → 删 worktree → branch -D → 记账
bash "$WTB" finish "$WTID" --archive --project "$GP" >/dev/null \
  && ok "finish --archive 退出 0" || bad "finish --archive 失败"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTID" >/dev/null \
  && ok "产生 archive/$WTID 标签" || bad "无 archive 标签"
[[ -d "$GP/.worktrees/$WTID" ]] && bad "archive 后 worktree 仍在" || ok "archive 后 worktree 已删"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTID" && bad "archive 后分支仍在" || ok "archive 后分支已删"
grep -q 'tag=archive/' "$WTF" && ok "worktree: 行含 tag" || bad "worktree: 行缺 tag"

# 脏 worktree：--archive 拒绝，不动
WTD="wtdirty"; WTDF="$GP/tasks/2099-01-08-${WTD}.md"
printf '# dirty\nstate: running\n' > "$WTDF"
git -C "$GP" worktree add -q -b "$WTD" "$GP/.worktrees/$WTD"
echo x > "$GP/.worktrees/$WTD/dirty.txt"
if bash "$WTB" finish "$WTD" --archive --project "$GP" >/dev/null 2>&1; then
  bad "脏 worktree --archive 竟放行"
else
  ok "脏 worktree --archive 拒绝"
fi
[[ -d "$GP/.worktrees/$WTD" ]] && ok "拒绝后脏 worktree 未动" || bad "脏 worktree 被删"

# G4：--keep 不做脏检查——同一脏 worktree 上 --keep 退出 0 且记账
bash "$WTB" finish "$WTD" --keep=有冲突待解 --project "$GP" >/dev/null \
  && ok "脏 worktree --keep 退出 0（G4）" || bad "脏 worktree --keep 被拒（G4 未修）"
grep -q '^worktree: keep' "$WTDF" && ok "--keep 记账成功" || bad "--keep 未记账"
[[ -d "$GP/.worktrees/$WTD" ]] && ok "--keep 后脏 worktree 未动" || bad "--keep 动了 worktree"

# --merged 放行路径：分支合并进 HEAD 后正常收尾
WTM="wtmerged"; WTMF="$GP/tasks/2099-01-09-${WTM}.md"
printf '# merged\nstate: running\n' > "$WTMF"
git -C "$GP" worktree add -q -b "$WTM" "$GP/.worktrees/$WTM"
git -C "$GP/.worktrees/$WTM" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
git -C "$GP" -c user.email=t@t.t -c user.name=t merge -qm m "$WTM"
bash "$WTB" finish "$WTM" --merged --project "$GP" >/dev/null \
  && ok "已合并分支 --merged 放行" || bad "已合并分支 --merged 被拒"
[[ -d "$GP/.worktrees/$WTM" ]] && bad "merged 后 worktree 仍在" || ok "merged 后 worktree 已删"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTM" && bad "merged 后分支仍在" || ok "merged 后分支已删"

# qwb-run.sh --create-worktree：有残留 → 警告但不阻塞
printf '# new\nstate: running\n' > "$GP/tasks/2099-01-10-wtnew.md"
r1out="$( cd "$GP" && PATH="$STUB:$PATH" bash "$TMP/qwbuddy/bin/qwb-run.sh" --task wtnew --worker codex --create-worktree 2>&1 )"
printf '%s' "$r1out" | grep -q '残留' && ok "--create-worktree 对残留打警告" || bad "--create-worktree 无残留警告"
[[ -d "$GP/.worktrees/wtnew" ]] && ok "警告不阻塞：worktree 已建" || bad "--create-worktree 被阻塞"

echo "== 18. G1：detached HEAD 下归档/落地以实际 HEAD OID 为准 =="
# 场景：分支 wtdet 在 A；checkout --detach 后提交 B（分支仍指 A）
WTG="wtdet"; WTGF="$GP/tasks/2099-01-12-${WTG}.md"
printf '# det\nstate: running\n' > "$WTGF"
git -C "$GP" worktree add -q -b "$WTG" "$GP/.worktrees/$WTG"
AOID="$(git -C "$GP/.worktrees/$WTG" rev-parse HEAD)"
git -C "$GP/.worktrees/$WTG" checkout -q --detach
git -C "$GP/.worktrees/$WTG" -c user.email=t@t.t -c user.name=t commit -qm wip --allow-empty
BOID="$(git -C "$GP/.worktrees/$WTG" rev-parse HEAD)"
[[ "$AOID" != "$BOID" ]] && ok "G1 场景就绪（A=${AOID:0:7} B=${BOID:0:7}）" || bad "G1 场景构造失败（A==B）"

# --merged 对未合并的 detached B 拒绝（旧实现会拿同名分支 A 放行）
if bash "$WTB" finish "$WTG" --merged --project "$GP" >/dev/null 2>&1; then
  bad "detached 未合并 --merged 竟放行（G1 未修）"
else
  ok "detached 未合并 --merged 拒绝"
fi
[[ -d "$GP/.worktrees/$WTG" ]] && ok "拒绝后 detached worktree 未动" || bad "拒绝后 detached worktree 被删"

# --archive：tag 必须指向 B（实际 HEAD OID），且同名分支保留
bash "$WTB" finish "$WTG" --archive --project "$GP" >/dev/null \
  && ok "detached --archive 退出 0" || bad "detached --archive 失败"
tagoid="$(git -C "$GP" rev-parse "archive/$WTG" 2>/dev/null || true)"
[[ "$tagoid" == "$BOID" ]] && ok "archive/${WTG} 指向 detached 提交 B" || bad "archive tag 指向 ${tagoid} 而非 B（${BOID}）"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTG" \
  && ok "同名分支 ${WTG} 保留（它不指向本工作区）" || bad "同名分支 ${WTG} 被误删（G1 未修）"
[[ -d "$GP/.worktrees/$WTG" ]] && bad "archive 后 worktree 仍在" || ok "archive 后 worktree 已删"
grep -q 'branch=detached' "$WTGF" && ok "worktree: 行记 branch=detached" || bad "worktree: 行未标 detached"

echo "== 19. G1b：git status 失败（非 0）→ 拒绝而非放行 =="
REAL_GIT="$(command -v git)"
GSTUB="$TMP/gitstub"; mkdir -p "$GSTUB"
cat > "$GSTUB/git" <<EOF
#!/usr/bin/env bash
if [[ "\${3:-}" == "status" ]]; then echo "fatal: mocked status failure" >&2; exit 128; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GSTUB/git"
WTS="wtstf"; WTSF="$GP/tasks/2099-01-13-${WTS}.md"
printf '# stf\nstate: running\n' > "$WTSF"
git -C "$GP" worktree add -q -b "$WTS" "$GP/.worktrees/$WTS"
if PATH="$GSTUB:$PATH" bash "$WTB" finish "$WTS" --archive --project "$GP" >/dev/null 2>&1; then
  bad "git status 失败时 --archive 竟放行（G1b 未修）"
else
  ok "git status 失败 → --archive 拒绝"
fi
[[ -d "$GP/.worktrees/$WTS" ]] && ok "status 失败拒绝后 worktree 未动" || bad "status 失败后 worktree 被删"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTS" >/dev/null \
  && bad "status 失败仍打了 archive tag" || ok "status 失败未打 tag"

echo "== 20. G3：init 与 config.sh =="
PRES="$TMP/presproj"; mkdir -p "$PRES/qwbuddy"
printf 'QWB_CONTROLLER_PANE="wtest:mine"\n' > "$PRES/qwbuddy/config.sh"
bash "$ROOT/bin/qwb-init.sh" "$PRES" >/dev/null
grep -q 'wtest:mine' "$PRES/qwbuddy/config.sh" \
  && ok "init 不覆盖已存在 config.sh" || bad "init 覆盖了已存在 config.sh"
MIG="$TMP/migproj"; mkdir -p "$MIG/qwbuddy"
echo '{}' > "$MIG/qwbuddy/config.json"
migout="$(bash "$ROOT/bin/qwb-init.sh" "$MIG" 2>&1)"
printf '%s' "$migout" | grep -q '旧版' && ok "init 对旧版 JSON 配置打迁移提示" || bad "init 未打迁移提示"
assert_file "$MIG/qwbuddy/config.sh"

echo "== 21. G3：旧配置文件名仅允许见于 qwb-init.sh 迁移逻辑，且为可读字面量 =="
if grep -rn 'config\.json' "$ROOT/bin" | grep -v 'qwb-init\.sh' | grep -q .; then
  bad "bin/ 中除 qwb-init.sh 外仍出现旧配置文件名："
  grep -rn 'config\.json' "$ROOT/bin" | grep -v 'qwb-init\.sh' || true
else
  ok "bin/ 中旧配置文件名仅见于 qwb-init.sh"
fi
grep -q 'config\.json' "$ROOT/bin/qwb-init.sh" \
  && ok "qwb-init.sh 迁移逻辑含旧名可读字面量" || bad "qwb-init.sh 缺旧名可读字面量"
if grep -rnE "jso(\"\"|'')n" "$ROOT/bin" "$ROOT/tests" >/dev/null 2>&1; then
  bad "bin/ tests/ 仍有拼接构造旧配置名的写法"
  grep -rnE "jso(\"\"|'')n" "$ROOT/bin" "$ROOT/tests" || true
else
  ok "bin/ tests/ 无拼接构造旧配置名"
fi

echo "== 22. H1 回归：git 替身注入并发推进/读取失败 =="
GITLOG="$TMP/git-inj.log"; : > "$GITLOG"
GSTUB2="$TMP/gitstub2"; mkdir -p "$GSTUB2"
cat > "$GSTUB2/git" <<EOF
#!/usr/bin/env bash
echo "git \$*" >> "$GITLOG"
sub="\${3:-}"; a4="\${4:-}"
if [[ "\$sub" == "rev-parse" && "\$a4" == "--abbrev-ref" && "\${INJ_MODE:-}" == "branchread" ]]; then
  echo "fatal: mocked branch read failure" >&2; exit 128
fi
if [[ "\$sub" == "tag" && "\${INJ_MODE:-}" == "posttag" ]]; then
  "$REAL_GIT" "\$@" || exit \$?
  "$REAL_GIT" -C "\$INJ_WT" -c user.email=t@t.t -c user.name=t commit -qm inject --allow-empty
  exit 0
fi
if [[ "\$sub" == "merge-base" && "\$a4" == "--is-ancestor" && "\${INJ_MODE:-}" == "postmerge" ]]; then
  "$REAL_GIT" -C "\$INJ_WT" -c user.email=t@t.t -c user.name=t commit -qm inject --allow-empty
  exit 0
fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$GSTUB2/git"

# 22a：--archive 打标签之后、remove 之前 HEAD 被推进 → 拒绝删除，已打标签保留
WTI="wtinj"; WTIF="$GP/tasks/2099-01-14-${WTI}.md"
printf '# inj\nstate: running\n' > "$WTIF"
git -C "$GP" worktree add -q -b "$WTI" "$GP/.worktrees/$WTI"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=posttag INJ_WT="$GP/.worktrees/$WTI" bash "$WTB" finish "$WTI" --archive --project "$GP" >/dev/null 2>&1; then
  bad "打标签后 HEAD 被推进 --archive 竟放行（H1 未修）"
else
  ok "打标签后 HEAD 被推进 → --archive 拒绝删除"
fi
[[ -d "$GP/.worktrees/$WTI" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -q 'worktree remove' "$GITLOG" && bad "仍调用了 worktree remove" || ok "未调用 worktree remove"
grep -q 'branch -D' "$GITLOG" && bad "仍调用了 branch -D" || ok "未调用 branch -D"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTI" >/dev/null \
  && ok "已打的 archive tag 保留" || bad "已打 tag 丢失"
git -C "$GP" show-ref --verify --quiet "refs/heads/$WTI" && ok "分支保留" || bad "分支被误删"

# 22b：--merged 核实通过之后、remove 之前 HEAD 被推进 → 同样拒绝
WTJ="wtinjm"; WTJF="$GP/tasks/2099-01-15-${WTJ}.md"
printf '# injm\nstate: running\n' > "$WTJF"
git -C "$GP" worktree add -q -b "$WTJ" "$GP/.worktrees/$WTJ"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=postmerge INJ_WT="$GP/.worktrees/$WTJ" bash "$WTB" finish "$WTJ" --merged --project "$GP" >/dev/null 2>&1; then
  bad "--merged 核实通过后 HEAD 被推进竟放行（H1 未修）"
else
  ok "--merged 核实通过后 HEAD 被推进 → 拒绝删除"
fi
[[ -d "$GP/.worktrees/$WTJ" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -q 'worktree remove' "$GITLOG" && bad "仍调用了 worktree remove" || ok "未调用 worktree remove"

# 22c：分支身份读取失败 → 拒绝，不回退成任务 id 继续删
WTK="wtinjb"; WTKF="$GP/tasks/2099-01-16-${WTK}.md"
printf '# injb\nstate: running\n' > "$WTKF"
git -C "$GP" worktree add -q -b "$WTK" "$GP/.worktrees/$WTK"
: > "$GITLOG"
if PATH="$GSTUB2:$PATH" INJ_MODE=branchread bash "$WTB" finish "$WTK" --archive --project "$GP" >/dev/null 2>&1; then
  bad "分支名读取失败 --archive 竟放行（H1 未修）"
else
  ok "分支名读取失败 → 拒绝（不回退成任务 id）"
fi
[[ -d "$GP/.worktrees/$WTK" ]] && ok "拒绝后 worktree 未动" || bad "拒绝后 worktree 仍被删"
grep -qE 'worktree remove|branch -D| tag ' "$GITLOG" \
  && bad "身份未知仍执行了打标/删除" || ok "未打标未删除"
git -C "$GP" rev-parse --verify --quiet "refs/tags/archive/$WTK" >/dev/null \
  && bad "分支身份未知仍打了 tag" || ok "未打 tag"

echo "== 23. A：qwb-test.sh 快门/全门 =="
assert_file "$ROOT/qwb.config.sh"
bash "$ROOT/bin/qwb-test.sh" --help >/dev/null && ok "qwb-test.sh --help 退出 0" || bad "--help 非 0"
bash "$ROOT/bin/qwb-test.sh" fast --project "$ROOT" >/dev/null 2>&1 \
  && ok "母本仓 fast 门退出 0" || bad "母本仓 fast 门非 0"
# 门命令覆盖：往临时项目配置追加可用门
printf 'QWB_GATE_FAST="echo fastgate-ok"\nQWB_GATE_FULL="exit 7"\n' >> "$TMP/qwbuddy/config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$TMP" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'fastgate-ok' \
  && ok "fast 门原样转发输出且退出 0" || bad "fast 门输出/退出码不对（rc=${rc}）"
out="$(bash "$ROOT/bin/qwb-test.sh" full --project "$TMP" 2>&1)"; rc=$?
[[ "$rc" -eq 7 ]] && ok "full 门失败退出码透传（7）" || bad "退出码未透传（rc=${rc}，应 7）"
printf '%s' "$out" | grep -qF '门失败（full）：exit 7 退出码=7' \
  && ok "门失败行格式正确且到 stderr/输出可见" || bad "缺「门失败（full）：…退出码=7」行"
# qwb.config.sh 回退（无 qwbuddy/ 的母本仓形态）
FB="$TMP/fallback"; mkdir -p "$FB"
printf 'QWB_GATE_FAST="echo fb-fast-ok"\n' > "$FB/qwb.config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$FB" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$out" | grep -q 'fb-fast-ok' \
  && ok "无 qwbuddy/ 时回退 qwb.config.sh" || bad "qwb.config.sh 回退失效（rc=${rc}）"
# 优先级：qwbuddy/config.sh 先于 qwb.config.sh
mkdir -p "$FB/qwbuddy"; printf 'QWB_GATE_FAST="echo qwbuddy-wins"\n' > "$FB/qwbuddy/config.sh"
out="$(bash "$ROOT/bin/qwb-test.sh" fast --project "$FB" 2>&1)"
printf '%s' "$out" | grep -q 'qwbuddy-wins' \
  && ok "qwbuddy/config.sh 优先于 qwb.config.sh" || bad "配置优先级不对"
# 未声明门：报错并给出正确写法
out="$(bash "$ROOT/bin/qwb-test.sh" full --project "$FB" 2>&1)"; rc=$?
{ [[ "$rc" -ne 0 ]] && printf '%s' "$out" | grep -q 'QWB_GATE_FULL' && printf '%s' "$out" | grep -q 'QWB_GATE_FULL="bash tests/smoke.sh'; } \
  && ok "未声明门时报错并给出声明写法" || bad "未声明门处理不对（rc=${rc}）"
# 无配置项目：报错
MT="$TMP/empty-proj"; mkdir -p "$MT"
bash "$ROOT/bin/qwb-test.sh" fast --project "$MT" >/dev/null 2>&1 \
  && bad "无配置项目 fast 竟成功" || ok "无配置项目报错非 0"

echo "== 24. B：先场景后代码（模板 + 规范）=="
assert_file "$ROOT/templates/TASK.md"
assert_file "$TMP/qwbuddy/TASK.md"
for kw in '验收场景' 'Given' 'When' 'Then' '失败路径' '验收门'; do
  grep -q "$kw" "$ROOT/templates/TASK.md" && ok "TASK.md 含「${kw}」" || bad "TASK.md 缺「${kw}」"
done
grep -q '先场景后代码' "$TMP/qwbuddy/QWBUDDY.md" && ok "QWBUDDY.md 有先场景后代码规范" || bad "QWBUDDY.md 缺规范节"
grep -q '场景冻结' "$TMP/qwbuddy/QWBUDDY.md" && ok "QWBUDDY.md 有场景冻结条款" || bad "缺场景冻结"
grep -q 'QWB_GATE_FAST' "$TMP/qwbuddy/config.sh" && grep -q 'QWB_GATE_FULL' "$TMP/qwbuddy/config.sh" \
  && ok "安装的 config.sh 含快门/全门声明" || bad "config.sh 缺门声明"
grep -q '自证' "$TMP/qwbuddy/roles/执行者.md" && grep -q '契约校验' "$TMP/qwbuddy/roles/执行者.md" \
  && ok "执行者.md 新增两条禁止事项" || bad "执行者.md 缺新禁止事项"

echo "== 25. C：qwb-lint.sh 自身 lint =="
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$ROOT" 2>&1)"; rc=$?
[[ "$rc" -eq 0 ]] && printf '%s' "$lintout" | grep -q 'LINT PASS' \
  && ok "母本仓 lint 全过（LINT PASS）" || { bad "母本仓 lint FAIL（rc=${rc}）:"; printf '%s\n' "$lintout"; }
printf '%s' "$lintout" | grep -c '^PASS' | grep -qE '^[4-9]' \
  && ok "lint 逐项 PASS 输出可见" || bad "lint 无逐项 PASS 输出"
HL="$TMP/healthy"; mkdir -p "$HL"; bash "$ROOT/bin/qwb-init.sh" "$HL" >/dev/null
bash "$ROOT/bin/qwb-lint.sh" --project "$HL" >/dev/null 2>&1 \
  && ok "健康安装项目 lint 退出 0" || bad "健康项目 lint 非 0"
# 坏项目：四条检查各踩一条
BD="$TMP/badproj"; mkdir -p "$BD/qwbuddy/bin" "$BD/tasks"
printf '# doc\nqwb-ghost.sh 必须在\n' > "$BD/qwbuddy/QWBUDDY.md"
printf '# t\nstate: pending\n' > "$BD/tasks/2099-01-30-bad.md"
printf 'QWB_DEAD_KEY=1\n' > "$BD/qwbuddy/config.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo $X你好' > "$BD/qwbuddy/bin/qwb-foo.sh"
lintout="$(bash "$ROOT/bin/qwb-lint.sh" --project "$BD" 2>&1)"; rc=$?
[[ "$rc" -eq 1 ]] && ok "坏项目 lint 退出 1" || bad "坏项目 lint 未失败（rc=${rc}）"
printf '%s' "$lintout" | grep -q 'qwb-ghost.sh' && ok "检出文档承诺缺失脚本" || bad "未检出缺失脚本"
printf '%s' "$lintout" | grep -q 'pending' && ok "检出非法 state" || bad "未检出非法 state"
printf '%s' "$lintout" | grep -q 'QWB_DEAD_KEY' && ok "检出血配置死键" || bad "未检出死键"
printf '%s' "$lintout" | grep -q 'qwb-foo.sh' && ok "检出 \$VAR+非ASCII 写法" || bad "未检出变量写法"

echo "== 26. D：herdr fixture 契约基线 =="
for fx in tab-create agent-start agent-prompt agent-wait agent-wait-timeout agent-list pane-run pane-run-error; do
  assert_file "$FIXDIR/$fx.json"
done
tc="$(sed '/^#/d' "$FIXDIR/tab-create.json")"
{ printf '%s' "$tc" | grep -q '"result"' && printf '%s' "$tc" | grep -q '"root_pane"' && printf '%s' "$tc" | grep -q '"pane_id"'; } \
  && ok "tab-create fixture 含 .result.root_pane.pane_id 契约字段" || bad "tab-create 契约字段缺失"
for fx in agent-start agent-prompt agent-wait agent-list; do
  sed '/^#/d' "$FIXDIR/$fx.json" | grep -q '"result"' \
    && ok "$fx fixture 含 .result 字段" || bad "$fx fixture 缺 .result"
done
sed '/^#/d' "$FIXDIR/agent-wait-timeout.json" | grep -q '"error"' \
  && ok "agent-wait-timeout fixture 为真实 error 形状" || bad "timeout fixture 非 error 形状"
[[ -z "$(sed '/^#/d' "$FIXDIR/pane-run.json")" ]] \
  && ok "pane-run fixture 契约=空输出（与真录一致）" || bad "pane-run fixture 非空，与真录契约不符"
# 行为证明：stub 确实读 fixture——换掉 fixture 内容，派发结果跟着变
FIXDIR2="$TMP/fix2"; mkdir -p "$FIXDIR2"; cp "$FIXDIR"/*.json "$FIXDIR2/"
sed 's/"pane_id":"[^"]*"/"pane_id":"contract:p99"/' "$FIXDIR/tab-create.json" > "$FIXDIR2/tab-create.json"
DISP2="$TMP/tasks/2099-01-22-disp2.md"; printf '# d2\nstate: blocked\n' > "$DISP2"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_FIXDIR="$FIXDIR2" bash qwbuddy/bin/qwb-run.sh --task disp2 --worker codex --worktree "$TMP" ) >/dev/null 2>&1
grep -qF 'pane=contract:p99' "$DISP2" \
  && ok "改 fixture 后派发 pane 跟着变（stub 真读 fixture，非硬编码）" || bad "stub 未读 fixture（pane 未变）"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
