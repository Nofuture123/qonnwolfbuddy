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

echo
if [[ "$FAILS" -eq 0 ]]; then echo "SMOKE PASS"; exit 0; else echo "SMOKE FAIL（$FAILS 项）"; exit 1; fi
