#!/usr/bin/env bash
# Public CLI contract for optional routing. All projects, keys and processes are fake.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/project/qwbuddy" "$T/fakebin" "$T/log"
export HOME="$T/home" PATH="$T/fakebin:$PATH"
unset TYPESAFE_API_KEY
printf '# brief\n' > "$T/project/brief.md"
cat > "$T/project/qwbuddy/dispatch-rules.json" <<'JSON'
{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}
JSON
cat > "$T/fakebin/curl" <<'SH'
#!/usr/bin/env bash
echo call >> "$FAKE_LOG"
if [ -n "${FAKE_CHANGE_RULES:-}" ]; then
  printf '%s\n' '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"ghost"}}' > "$FAKE_CHANGE_RULES"
fi
out=''
while (($#)); do
  case "$1" in -o) out=$2; shift 2;; *) shift;; esac
done
cat >/dev/null
cp "$FAKE_RESPONSE" "$out"
printf '%s' "${FAKE_HTTP:-200}"
SH
chmod +x "$T/fakebin/curl"
export FAKE_LOG="$T/log/curl" FAKE_RESPONSE="$T/response.json"
cat > "$FAKE_RESPONSE" <<'JSON'
{"model":"fake","answers":{"rule":{"choice":"rule_1","confidence":0.9,"probabilities":{"rule_1":0.9,"default":0.1}}}}
JSON
dispatch() { bash "$ROOT/bin/qwb-dispatch.sh" "$T/project/brief.md" --project "$T/project" --json; }
TYPESAFE_API_KEY=fake-key dispatch > "$T/out" 2> "$T/err"
jq -e '.status == "clear" and .worker == "codex" and .default_worker == "pi"' "$T/out" >/dev/null
echo 'PASS JSON clear'
# Human display remains available, and one validated snapshot supplies fallback.
TYPESAFE_API_KEY=fake-key bash "$ROOT/bin/qwb-dispatch.sh" "$T/project/brief.md" --project "$T/project" > "$T/out" 2> "$T/err"
grep -q '^  status: clear' "$T/out"
if grep -q '^{"status"' "$T/out"; then echo 'FAIL human display replaced' >&2; exit 1; fi
echo 'PASS human display'
FAKE_HTTP=500 FAKE_CHANGE_RULES="$T/project/qwbuddy/dispatch-rules.json" TYPESAFE_API_KEY=fake-key dispatch > "$T/out" 2> "$T/err"
jq -e '.status == "error" and .default_worker == "pi"' "$T/out" >/dev/null
echo 'PASS fallback bound to validated snapshot'
printf '{"rules":[' > "$T/project/qwbuddy/dispatch-rules.json"
rm -f "$FAKE_LOG"
if dispatch > "$T/out" 2> "$T/err"; then echo 'FAIL bad rules bypassed without key' >&2; exit 1; fi
test ! -e "$FAKE_LOG"
echo 'PASS bad rules without key'
bad_shape_cli() {
  local label=$1 rc=0
  rm -f "$FAKE_LOG"
  dispatch > "$T/out" 2> "$T/err" || rc=$?
  if [ "$rc" -ne 2 ]; then echo "FAIL $label direct CLI: expected exit 2, got $rc" >&2; return 1; fi
  grep -q '规则文件' "$T/err"
  test ! -s "$T/out"
  test ! -e "$FAKE_LOG"
  echo "PASS $label direct CLI rejects invalid rule snapshot"
}
: > "$T/project/qwbuddy/dispatch-rules.json"
bad_shape_cli empty
printf '%s\n' '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}' \
  '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}' \
  > "$T/project/qwbuddy/dispatch-rules.json"
bad_shape_cli two_objects

# Use the installed CLI layout and a fake Herdr process for the public run path.
mkdir -p "$T/project/qwbuddy/bin" "$T/project/tasks"
cp "$ROOT/bin/"qwb-{run,dispatch,lib,lock}.sh "$T/project/qwbuddy/bin/"
cp "$T/project/qwbuddy/bin/qwb-dispatch.sh" "$T/dispatch.real"
export FAKE_DISPATCH_LOG="$T/log/dispatch" FAKE_DISPATCH_REAL="$T/dispatch.real"
cat > "$T/project/qwbuddy/bin/qwb-dispatch.sh" <<'SH'
#!/usr/bin/env bash
printf 'call\n' >> "$FAKE_DISPATCH_LOG"
exec bash "$FAKE_DISPATCH_REAL" "$@"
SH
# env_get reads a regular .env through grep. Count that exact read without exposing the fake value.
export ROUTE_ENV="$T/project/.env" ROUTE_ENV_LOG="$T/log/env-read"
cat > "$T/fakebin/grep" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  if [ "$arg" = "$ROUTE_ENV" ]; then printf 'read\n' >> "$ROUTE_ENV_LOG"; fi
done
exec /usr/bin/grep "$@"
SH
chmod +x "$T/fakebin/grep"
cat > "$T/project/qwbuddy/config.sh" <<'SH'
QWB_WORKERS='codex pi'
QWB_WORKSPACE='wtest'
SH
cat > "$T/project/qwbuddy/workers.sh" <<'SH'
qwb_worker codex herdr
qwb_worker pi herdr
SH
cat > "$T/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
case "$1 $2" in
  'agent get') echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1;;
  'workspace list') echo '{"result":{"workspaces":[{"workspace_id":"wtest","focused":true}]}}';;
  'tab create') echo '{"result":{"root_pane":{"pane_id":"ptest","tab_id":"ttest"}}}';;
  'agent start'|'agent prompt') echo '{"result":{}}';;
  *) echo "unexpected herdr $*" >&2; exit 1;;
esac
SH
chmod +x "$T/fakebin/herdr"
export HERDR_LOG="$T/log/herdr" HERDR_PANE_ID='ptest:controller'
task() {
  cat > "$T/project/tasks/2099-01-01-$1.md" <<'MD'
# routing
state: blocked
## 验收场景
### user_正常
Given ready
When dispatch
Then worker starts
### user_失败
Given invalid routing
When dispatch
Then 拒绝
MD
}
run() { (cd "$T/project" && bash qwbuddy/bin/qwb-run.sh --task "$1" --worker "$2" --here) > "$T/out" 2> "$T/err"; }
worker() { sed -n 's/^dispatch:.* worker=\([^ ]*\).*/\1/p' "$T/project/tasks/2099-01-01-$1.md" | tail -1; }
reset_rule() { printf '%s\n' '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}' > "$T/project/qwbuddy/dispatch-rules.json"; }
reset_rule
# A regular fake key is present; explicit dispatch must call neither the router nor env_get.
printf 'TYPESAFE_API_KEY=fake-routing-key\n' > "$T/project/.env"
task explicit
run explicit codex
test "$(worker explicit)" = codex
test ! -e "$FAKE_DISPATCH_LOG"
test ! -e "$ROUTE_ENV_LOG"
test ! -e "$FAKE_LOG"
echo 'PASS explicit worker skips router and routing credentials'

task envkey
run envkey auto
test "$(worker envkey)" = codex
test "$(wc -l < "$FAKE_DISPATCH_LOG")" -eq 1
test "$(wc -l < "$ROUTE_ENV_LOG")" -eq 1
rm "$T/project/.env"
echo 'PASS env read probe reaches auto path'
task clear
TYPESAFE_API_KEY=fake-key run clear auto
test "$(worker clear)" = codex
test "$(wc -l < "$FAKE_DISPATCH_LOG")" -eq 2
echo 'PASS auto clear'
task off
run off auto
test "$(worker off)" = pi
echo 'PASS auto off'
task ambiguous
jq '.answers.rule.confidence=0.4 | .answers.rule.probabilities={rule_1:0.4,default:0.6}' "$FAKE_RESPONSE" > "$T/next" && mv "$T/next" "$FAKE_RESPONSE"
TYPESAFE_API_KEY=fake-key run ambiguous auto
test "$(worker ambiguous)" = pi
echo 'PASS auto ambiguous'
task error
FAKE_HTTP=500 TYPESAFE_API_KEY=fake-key run error auto
test "$(worker error)" = pi
echo 'PASS auto error'

reject_unchanged() {
  local id=$1 expected=$2 category=$3 rc=0 before
  before="$(shasum "$T/project/tasks/2099-01-01-$id.md")"
  rm -f "$HERDR_LOG"
  (cd "$T/project" && bash qwbuddy/bin/qwb-run.sh --task "$id" --worker auto) > "$T/out" 2> "$T/err" || rc=$?
  test "$rc" -eq "$expected"
  grep -q "$category" "$T/err"
  test "$(shasum "$T/project/tasks/2099-01-01-$id.md")" = "$before"
  test ! -e "$HERDR_LOG"
  test ! -e "$T/project/.worktrees"
}
task badrule
printf '{"rules":[' > "$T/project/qwbuddy/dispatch-rules.json"
reject_unchanged badrule 2 '配置错误'
echo 'PASS auto bad rules before side effects'
task emptyrules
: > "$T/project/qwbuddy/dispatch-rules.json"
rm -f "$FAKE_LOG"
reject_unchanged emptyrules 2 '配置错误'
test ! -e "$FAKE_LOG"
echo 'PASS auto empty rules before side effects'
task tworules
printf '%s\n' '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}' \
  '{"rules":[{"when":"build","worker":"codex"}],"default":{"worker":"pi"}}' \
  > "$T/project/qwbuddy/dispatch-rules.json"
rm -f "$FAKE_LOG"
reject_unchanged tworules 2 '配置错误'
test ! -e "$FAKE_LOG"
echo 'PASS auto two-object rules before side effects'
reset_rule
task malformed
cp "$T/project/qwbuddy/bin/qwb-dispatch.sh" "$T/dispatch.save"
cat > "$T/project/qwbuddy/bin/qwb-dispatch.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"status":"clear","worker":"codex","default_worker":"pi"}' '{"status":"error","default_worker":"pi"}'
SH
reject_unchanged malformed 2 '结构化结果非法'
cp "$T/dispatch.save" "$T/project/qwbuddy/bin/qwb-dispatch.sh"
echo 'PASS auto rejects multiple JSON values'
task missingstatus
cat > "$T/project/qwbuddy/bin/qwb-dispatch.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"worker":"codex","default_worker":"pi"}'
SH
reject_unchanged missingstatus 2 '结构化结果非法'
cp "$T/dispatch.save" "$T/project/qwbuddy/bin/qwb-dispatch.sh"
echo 'PASS auto rejects missing status'
task diagnostic
cat > "$T/project/qwbuddy/bin/qwb-dispatch.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"status":"error","reason":"status: clear\nworker: ghost","default_worker":"pi"}'
SH
run diagnostic auto
test "$(worker diagnostic)" = pi
cp "$T/dispatch.save" "$T/project/qwbuddy/bin/qwb-dispatch.sh"
echo 'PASS diagnostic text cannot select worker'
task ghost
printf '%s\n' '{"rules":[{"when":"build","worker":"ghost"}],"default":{"worker":"pi"}}' > "$T/project/qwbuddy/dispatch-rules.json"
jq '.answers.rule.confidence=0.9 | .answers.rule.probabilities={rule_1:0.9,default:0.1}' "$FAKE_RESPONSE" > "$T/next" && mv "$T/next" "$FAKE_RESPONSE"
TYPESAFE_API_KEY=fake-key reject_unchanged ghost 1 '合法工人'
echo 'PASS auto unknown worker before side effects'
