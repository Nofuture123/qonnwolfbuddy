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
assert_file "$TMP/qwbuddy/config.json"
for s in init run wake status lock; do assert_file "$TMP/qwbuddy/bin/qwb-$s.sh"; done
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

echo "== 5. config.json 合法 JSON =="
if command -v python3 >/dev/null 2>&1; then
  chk python3 -m json.tool "$TMP/qwbuddy/config.json"
elif command -v jq >/dev/null 2>&1; then
  chk jq . "$TMP/qwbuddy/config.json"
else
  echo "SKIP  无 python3/jq，跳过 JSON 校验"
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
mkdir -p "$STUB"
cat > "$STUB/herdr" <<EOF
#!/usr/bin/env bash
echo "herdr \$*" >> "$STUBLOG"
case "\${1:-} \${2:-}" in
  "pane run")   [[ "\${HERDR_FAIL:-}" == *run*  ]] && exit 1; printf '%s\n' '{"result":{"ok":true}}' ;;
  "agent wait") [[ "\${HERDR_FAIL:-}" == *wait* ]] && exit 1; printf '%s\n' '{"result":{"ok":true}}' ;;
  "tab create") printf '%s\n' '{"result":{"root_pane":{"pane_id":"wtest:p9"}}}' ;;
  *) printf '%s\n' '{"result":{"ok":true}}' ;;
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

echo "== 12. F2 回归：dispatch pane 失效 → 按 interval 退化等待，无忙循环 =="
: > "$STUBLOG"
( cd "$TMP" && PATH="$STUB:$PATH" HERDR_FAIL=wait exec bash qwbuddy/bin/qwb-wake.sh --pane wtest:p9 --interval 1000 ) >/dev/null 2>&1 &
WPID=$!
sleep 4
kill "$WPID" 2>/dev/null; wait "$WPID" 2>/dev/null || true
n="$(grep -c 'agent wait' "$STUBLOG" || true)"
[[ "$n" -ge 2 && "$n" -le 8 ]] \
  && ok "4 秒内 ${n} 次 agent wait（≈1 秒/轮，无忙循环）" || bad "4 秒内 ${n} 次 agent wait（忙循环或未等待）"

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

echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
