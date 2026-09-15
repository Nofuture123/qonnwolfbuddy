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
for s in init run wake status; do assert_file "$TMP/qwbuddy/bin/qwb-$s.sh"; done
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
case "\${1:-}" in
  tab) printf '%s\n' '{"result":{"root_pane":{"pane_id":"wtest:p9"}}}' ;;
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

echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
