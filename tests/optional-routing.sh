#!/usr/bin/env bash
# Public CLI contract for optional routing. All projects, keys and processes are fake.
set -euo pipefail
export TMPDIR="${QWB_TEST_SCOPE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.qwb-tmp}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1
export TMPDIR="$T"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/home" "$T/project/qwbuddy" "$T/fakebin" "$T/log"
export HOME="$T/home" PATH="$T/fakebin:$PATH"
unset TYPESAFE_API_KEY
printf '# brief\n' > "$T/project/brief.md"
cat > "$T/project/qwbuddy/dispatch-rules.json" <<'JSON'
{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}
JSON
cat > "$T/fakebin/curl" <<'SH'
#!/usr/bin/env bash
echo call >> "$FAKE_LOG"
if [ -n "${FAKE_CHANGE_RULES:-}" ]; then
  printf '%s\n' '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"ghost"}}' > "$FAKE_CHANGE_RULES"
fi
out=''
while (($#)); do
  case "$1" in -o) out=$2; shift 2;; *) shift;; esac
done
cat > "$FAKE_REQUEST"
cp "$FAKE_RESPONSE" "$out"
printf '%s' "${FAKE_HTTP:-200}"
SH
chmod +x "$T/fakebin/curl"
export FAKE_LOG="$T/log/curl" FAKE_RESPONSE="$T/response.json" FAKE_REQUEST="$T/request.json"
cat > "$FAKE_RESPONSE" <<'JSON'
{"model":"fake","answers":{"rule":{"choice":"rule_1","confidence":0.9,"probabilities":{"rule_1":0.9,"default":0.1}}}}
JSON
dispatch() { bash "$ROOT/bin/qwb-dispatch.sh" "$T/project/brief.md" --project "$T/project" --json; }
TYPESAFE_API_KEY=fake-key dispatch > "$T/out" 2> "$T/err"
jq -e '.status == "clear" and .worker == "claude" and .default_worker == "pi"' "$T/out" >/dev/null
echo 'PASS JSON clear'
# 06 R1/R2: actual public requests, literal expected bytes; no parser-internal assertions.
QWB_ROUTING_TEST_ROOT="$ROOT" QWB_ROUTING_TEST_PROJECT="$T/project" python3 -B - <<'PY'
import json, os, subprocess
from pathlib import Path
root=Path(os.environ['QWB_ROUTING_TEST_ROOT']); project=Path(os.environ['QWB_ROUTING_TEST_PROJECT'])
cases=[
    ('nested intent/spec children',
     '## 原始意图\n用户需求\n### 输入输出\nMUST_KEEP_INPUT_OUTPUT\n## 工程规格\n实现内容\n### 安全边界\nMUST_KEEP_SECURITY\n## 必要约束\n不部署\n',
     '## 原始意图\n用户需求\n### 输入输出\nMUST_KEEP_INPUT_OUTPUT\n## 工程规格\n实现内容\n### 安全边界\nMUST_KEEP_SECURITY\n## 必要约束\n不部署\n'),
    ('history descendants cannot reopen',
     '## 原始意图\n当前需求\n## 工程规格\n当前规格\n## 历史报告\n旧报告\n### 工程规格复盘\nMUST_NOT_SEND_HISTORY\n#### 原始意图\nMUST_NOT_SEND_DEEP_HISTORY\n## 必要约束\n当前约束\n',
     '## 原始意图\n当前需求\n## 工程规格\n当前规格\n## 必要约束\n当前约束\n'),
    ('unselected descendants cannot reopen',
     '## 工程规格\n当前规格\n## 附加材料\nMUST_NOT_SEND_APPENDIX\n### 工程规格\nMUST_NOT_SEND_APPENDIX_CHILD\n## 硬约束\n不部署\n',
     '## 工程规格\n当前规格\n## 硬约束\n不部署\n'),
    ('document root and numbered sections',
     '# 任务书\nMUST_NOT_SEND_PREAMBLE\n## 0. 原始意图与范围\n当前意图\n### 工程规格（与原始意图区分）\n当前规格\n#### 安全边界\n当前边界\n## 1. 验收场景\nMUST_NOT_SEND_SCENARIOS\n### 原始意图\nMUST_NOT_SEND_SCENARIO_CHILD\n## 2. 硬约束\n不部署\n',
     '## 0. 原始意图与范围\n当前意图\n### 工程规格（与原始意图区分）\n当前规格\n#### 安全边界\n当前边界\n## 2. 硬约束\n不部署\n'),
    ('authorization metadata is not a runtime event',
     'scenarios-fp: 0000000000000000000000000000000000000000\n# routing\nstate: blocked\nimplementation-authorized: explicit fixture approval\ndispatch-budget: 20\ndispatch-permissions: read\n## 原始意图\n当前意图\n## 工程规格\n当前规格\n',
     '## 原始意图\n当前意图\n## 工程规格\n当前规格\n'),
    ('runtime events do not reopen through children',
     '## 工程规格\n当前规格\nworking: MUST_NOT_SEND_RUNTIME\n### 工程规格\nMUST_NOT_SEND_RUNTIME_CHILD\n## 必要约束\n当前约束\n',
     '## 工程规格\n当前规格\n## 必要约束\n当前约束\n'),
    ('closing ATX markers do not admit preamble',
     '# 任务书\nMUST_NOT_SEND_PREAMBLE\n## 工程规格 ##\n当前规格\n### 安全边界 ###\n当前边界\n## 旧报告 ##\nMUST_NOT_SEND_HISTORY\n',
     '## 工程规格 ##\n当前规格\n### 安全边界 ###\n当前边界\n'),
    ('selected code literal preserved',
     '## 工程规格\n当前规格\n```markdown\n## 历史报告\nworking: literal specification example\n```\n### 日志格式\n合法规格子节\n',
     '## 工程规格\n当前规格\n```markdown\n## 历史报告\nworking: literal specification example\n```\n### 日志格式\n合法规格子节\n'),
    ('excluded code headings cannot escape',
     '## 工程规格\n当前规格\n## 历史报告\n```markdown\n## 工程规格\nMUST_NOT_SEND_FENCED_HISTORY\n```\n~~~markdown\n## 原始意图\nMUST_NOT_SEND_TILDE_HISTORY\n~~~\n## 必要约束\n当前约束\n',
     '## 工程规格\n当前规格\n## 必要约束\n当前约束\n'),
    ('pure LF brief keeps trailing empty line',
     'original first line\nsecond line\n\n', 'original first line\nsecond line\n\n'),
    ('pure CRLF brief keeps trailing empty line',
     'original first line\r\nsecond line\r\n\r\n', 'original first line\r\nsecond line\r\n\r\n'),
    ('selected CRLF lines retain bytes',
     '## 原始意图\r\n当前需求\r\n### 输入输出\r\n当前接口\r\n\r\n## 历史报告\r\nMUST_NOT_SEND_HISTORY\r\n### 工程规格复盘\r\nMUST_NOT_SEND_HISTORY_CHILD\r\n',
     '## 原始意图\r\n当前需求\r\n### 输入输出\r\n当前接口\r\n\r\n'),
]
evidence=os.environ.get('QWB_ROUTING_INPUT_EVIDENCE_DIR')
if evidence:
    evidence=Path(evidence); evidence.mkdir(parents=True,exist_ok=False)
for index,(name,raw,expected) in enumerate(cases):
    task=project/'input-contract.md'; task.write_bytes(raw.encode())
    result=subprocess.run(['bash',str(root/'bin/qwb-dispatch.sh'),str(task),'--project',str(project),'--json'],
                          env=os.environ|{'TYPESAFE_API_KEY':'fake-input-key'},capture_output=True,timeout=10)
    request=Path(os.environ['FAKE_REQUEST']).read_bytes()
    sent=json.loads(request)['state']['task']['brief'].encode()
    print('RC input contract:',name,result.returncode)
    if evidence:
        prefix=f'{index:02}'
        (evidence/(prefix+'.input')).write_bytes(raw.encode()); (evidence/(prefix+'.expected')).write_bytes(expected.encode())
        (evidence/(prefix+'.request.json')).write_bytes(request)
        (evidence/(prefix+'.stdout')).write_bytes(result.stdout); (evidence/(prefix+'.stderr')).write_bytes(result.stderr)
    assert result.returncode==0 and json.loads(result.stdout)['status']=='clear',(name,result.returncode,result.stderr)
    assert sent==expected.encode(),(name,sent,expected.encode())
    assert task.read_bytes()==raw.encode(), 'router rewrote input'
    print('PASS input contract:',name)
PY
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
printf '%s\n' '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}' \
  '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}' \
  > "$T/project/qwbuddy/dispatch-rules.json"
bad_shape_cli two_objects

# Use the installed CLI layout and a fake Herdr process for the public run path.
mkdir -p "$T/project/qwbuddy/bin" "$T/project/tasks"
cp "$ROOT/bin/"qwb-{run,dispatch,lib,lock,ledger,herdr}.sh "$T/project/qwbuddy/bin/"
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
QWB_WORKERS='claude pi'
QWB_WORKSPACE='wtest'
SH
cat > "$T/project/qwbuddy/workers.sh" <<'SH'
qwb_worker claude herdr
qwb_worker pi herdr
SH
cat > "$T/fakebin/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HERDR_LOG"
python3 -c 'import json,os,sys; open(os.environ["HERDR_LOG"]+".jsonl","a").write(json.dumps(sys.argv[1:])+"\n")' "$@"
case "$1 $2" in
  'agent get') if [[ -n "${FAKE_REUSE_AGENT:-}" ]]; then cat "$FAKE_REUSE_AGENT"; exit 0; fi; echo '{"error":{"code":"agent_not_found"}}' >&2; exit 1;;
  'pane get')
    seq=$((185 + $(grep -c '^agent prompt ' "$HERDR_LOG" || true)))
    if [[ -n "${FAKE_REUSE_PANE:-}" ]]; then
      jq --argjson seq "$seq" '.result.pane.agent_status //= "idle" | .result.pane.state_change_seq=$seq' "$FAKE_REUSE_PANE"
    else
      printf '{"result":{"pane":{"pane_id":"ptest","agent_status":"working","state_change_seq":%s}}}\n' "$seq"
    fi;;
  'pane process-info') jq -cn --arg dir "$FAKE_REUSE_DIR" --argjson pid "$FAKE_REUSE_PID" \
    '{result:{process_info:{pane_id:"ptest",shell_pid:42,foreground_process_group_id:$pid,foreground_processes:[{pid:$pid,argv0:"claude",cwd:$dir}]}}}';;
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
implementation-authorized: explicit fixture scope approval
dispatch-budget: 20
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
reset_rule() { printf '%s\n' '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}' > "$T/project/qwbuddy/dispatch-rules.json"; }
reset_rule
# A regular fake key is present; explicit dispatch must call neither the router nor env_get.
printf 'TYPESAFE_API_KEY=fake-routing-key\n' > "$T/project/.env"
task explicit
run explicit claude
test "$(worker explicit)" = claude
test ! -e "$FAKE_DISPATCH_LOG"
test ! -e "$ROUTE_ENV_LOG"
test ! -e "$FAKE_LOG"
echo 'PASS explicit worker skips router and routing credentials'

task envkey
run envkey auto
test "$(worker envkey)" = claude
test "$(wc -l < "$FAKE_DISPATCH_LOG")" -eq 1
test "$(wc -l < "$ROUTE_ENV_LOG")" -eq 1
rm "$T/project/.env"
echo 'PASS env read probe reaches auto path'
task clear
TYPESAFE_API_KEY=fake-key run clear auto
test "$(worker clear)" = claude
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
printf '%s\n' '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}' \
  '{"rules":[{"when":"build","worker":"claude"}],"default":{"worker":"pi"}}' \
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
printf '%s\n' '{"status":"clear","worker":"claude","default_worker":"pi"}' '{"status":"error","default_worker":"pi"}'
SH
reject_unchanged malformed 2 '结构化结果非法'
cp "$T/dispatch.save" "$T/project/qwbuddy/bin/qwb-dispatch.sh"
echo 'PASS auto rejects multiple JSON values'
task missingstatus
cat > "$T/project/qwbuddy/bin/qwb-dispatch.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"worker":"claude","default_worker":"pi"}'
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

# Named agent identity is distinct from the Herdr harness; argv remains an array.
printf "QWB_WORKERS='claude pi sol-high fable-high'\n" >> "$T/project/qwbuddy/config.sh"
cat >> "$T/project/qwbuddy/workers.sh" <<'SH'
qwb_worker sol-high herdr codex -- --model gpt-6-sol -c model_reasoning_effort=high --example 'a b' ''
qwb_worker fable-high herdr claude -- --model claude-fable-5 --effort high
SH
cp "$T/project/qwbuddy/workers.sh" "$T/named-workers"
task named
run named sol-high
test "$(worker named)" = sol-high
jq -se '[.[] | select(.[0:2] == ["agent","start"])] | last |
  .[3:5] == ["--kind","codex"] and
  .[9:] == ["--","--model","gpt-6-sol","-c","model_reasoning_effort=high","--example","a b",""]' "$HERDR_LOG.jsonl" >/dev/null
echo 'PASS named agent starts explicit harness with exact model/effort argv'
# Even herdr has a fixed kind list; invalid explicit syntax must fail before side effects.
for definition in 'qwb_worker sol-high herdr -bad -- --model gpt-6-sol' \
                  'qwb_worker sol-high herdr "bad harness" -- --model gpt-6-sol' \
                  'qwb_worker sol-high herdr "" --'; do
  sed '/^qwb_worker sol-high /d' "$T/named-workers" > "$T/project/qwbuddy/workers.sh"
  printf '%s\n' "$definition" >> "$T/project/qwbuddy/workers.sh"
  task badharness
  reject_unchanged badharness 1 'harness'
  echo 'PASS malformed explicit harness rejected before side effects'
done
cp "$T/named-workers" "$T/project/qwbuddy/workers.sh"
# Explicit harness must also drive trust preseed, not the alias.
printf '{"projects":{}}' > "$HOME/.claude.json"
task namedclaude
run namedclaude fable-high
jq -e --arg dir "$T/project" '.projects[$dir].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null
grep -q 'agent start qwb-namedclaude --kind claude' "$HERDR_LOG"
echo 'PASS named Claude harness drives start and trust preseed'

# Reuse compares the runtime harness while the receipt still binds the named agent.
export FAKE_REUSE_AGENT="$T/reuse-agent.json" FAKE_REUSE_PANE="$T/reuse-pane.json" FAKE_REUSE_PID="$$" FAKE_REUSE_DIR="$T/project"
jq -cn --arg dir "$T/project" '{result:{agent:{name:"qwb-named",agent_status:"idle",pane_id:"ptest",agent:"codex",cwd:$dir,workspace_id:"wtest"}}}' > "$FAKE_REUSE_AGENT"
jq -cn --arg dir "$T/project" '{result:{pane:{pane_id:"ptest",agent:"codex",cwd:$dir,workspace_id:"wtest"}}}' > "$FAKE_REUSE_PANE"
: > "$HERDR_LOG"
before=$(shasum "$T/project/tasks/2099-01-01-named.md")
if run named sol-high; then echo 'FAIL unverified Codex idle reused' >&2; exit 1; fi
grep -q '本代真实活动为 unknown' "$T/err"
test "$(shasum "$T/project/tasks/2099-01-01-named.md")" = "$before"
! grep -q 'agent prompt\|agent start' "$HERDR_LOG"
echo 'PASS named Codex native idle without activity proof refuses reuse'
jq '.result.pane.agent="claude"' "$FAKE_REUSE_PANE" > "$T/next" && mv "$T/next" "$FAKE_REUSE_PANE"
before=$(shasum "$T/project/tasks/2099-01-01-named.md")
: > "$HERDR_LOG"
if run named sol-high; then echo 'FAIL wrong harness reused' >&2; exit 1; fi
grep -q '拒绝复用' "$T/err"
test "$(shasum "$T/project/tasks/2099-01-01-named.md")" = "$before"
! grep -q 'agent prompt\|agent start' "$HERDR_LOG"
echo 'PASS named agent refuses a different runtime harness'
jq '.result.pane.agent="codex"' "$FAKE_REUSE_PANE" > "$T/next" && mv "$T/next" "$FAKE_REUSE_PANE"
printf "QWB_WORKERS='claude pi sol-high fable-high sol-medium'\n" >> "$T/project/qwbuddy/config.sh"
printf 'qwb_worker sol-medium herdr codex -- --model gpt-6-sol -c model_reasoning_effort=medium\n' >> "$T/project/qwbuddy/workers.sh"
: > "$HERDR_LOG"
if run named sol-medium; then echo 'FAIL different named triplet reused' >&2; exit 1; fi
grep -q '没有匹配本票的既有 dispatch 身份' "$T/err"
test "$(shasum "$T/project/tasks/2099-01-01-named.md")" = "$before"
! grep -q 'agent prompt\|agent start' "$HERDR_LOG"
echo 'PASS same harness cannot reuse a different named triplet'
unset FAKE_REUSE_AGENT FAKE_REUSE_PANE

# Install the actual templates, then verify each named candidate at the process boundary.
cp "$ROOT/templates/config.sh" "$T/project/qwbuddy/config.sh"
printf 'QWB_WORKSPACE="wtest"\n' >> "$T/project/qwbuddy/config.sh"
cp "$ROOT/templates/workers.sh" "$T/project/qwbuddy/workers.sh"
bash "$ROOT/bin/qwb-init.sh" "$T/project" > "$T/init.out"
cp "$T/project/qwbuddy/workers.sh" "$T/installed-workers"
bash "$ROOT/bin/qwb-init.sh" "$T/project" > "$T/init-again.out"
cmp -s "$T/installed-workers" "$T/project/qwbuddy/workers.sh"
echo 'PASS named template installation is idempotent'
for spec in 'pi pi codex/gpt-6.1-sol high' \
            'claude claude claude-opus-5-5 medium' \
            'pi-sol-high pi codex/gpt-6.1-sol high' \
            'pi-astra-high pi codex/gpt-6-astra high' \
            'pi-astra-low pi codex/gpt-6-astra low' \
            'claude-opus-medium claude claude-opus-5-5 medium' \
            'claude-fable-low claude claude-fable-5-1 low'; do
  read -r agent harness model effort <<< "$spec"
  id="template-$agent"
  task "$id"
  run "$id" "$agent"
  test "$(worker "$id")" = "$agent"
  jq -se --arg harness "$harness" --arg model "$model" --arg effort "$effort" '
    [.[] | select(.[0:2] == ["agent","start"])] | last |
    .[3:5] == ["--kind",$harness] and
    ([.[] | select(. == "--")] | length) == 1 and
    (index("--model")) as $m | $m != null and .[$m+1] == $model and
    (index(if $harness == "pi" then "--thinking" else "--effort" end)) as $e |
    $e != null and .[$e+1] == $effort and
    (if $harness == "pi" then (index("--provider")) as $p |
      $p != null and .[$p+1] == "magpie" and index("--approve") != null
     else index("--dangerously-skip-permissions") != null end)' "$HERDR_LOG.jsonl" >/dev/null
  if [[ "$harness" == claude ]]; then
    jq -se --arg root "$(cd "$T/project" && pwd -P)" '
      [.[] | select(.[0:2] == ["agent","start"])] | last |
      (index("--add-dir")) as $i | $i != null and .[$i+1] == $root' "$HERDR_LOG.jsonl" >/dev/null
  fi
  echo "PASS installed $agent uses $harness and fixed provider/model/effort/permissions"
done
# Actual template rules are validated through the public auto-dispatch path.
cp "$ROOT/templates/dispatch-rules.json" "$T/project/qwbuddy/dispatch-rules.json"
cp "$T/project/qwbuddy/dispatch-rules.json" "$T/roster-rules.json"
jq -e '.agents.review == ["pi-astra-low"] and
  (.rules[] | select(.worker == "review") | .when | contains("astra 时改用 pi-sol-high")) and
  ([.agents[][]] | index("claude-opus-medium") | not)' "$T/roster-rules.json" >/dev/null
roster_response() {
  jq -n --arg choice "$1" --slurpfile rules "$T/roster-rules.json" '
    ($rules[0].rules | to_entries | map("rule_" + ((.key + 1) | tostring)) + ["default"]) as $keys |
    {model:"fake",answers:{rule:{choice:$choice,confidence:0.9,
      probabilities:(reduce $keys[] as $k ({}; .[$k] = (if $k == $choice then 0.9 else 0.1 / ($keys | length - 1) end)))}}}' > "$FAKE_RESPONSE"
}
for mapping in 'default pi-sol-high' 'rule_1 pi-astra-high' 'rule_4 pi-astra-low' 'rule_5 claude-fable-low'; do
  read -r choice expected <<< "$mapping"
  roster_response "$choice"
  id="roster-$choice"
  task "$id"
  TYPESAFE_API_KEY=fake-key run "$id" auto
  test "$(worker "$id")" = "$expected"
  echo "PASS roster auto $choice selects $expected"
done
jq '.agents_disabled=["pi-astra-high"]' "$T/roster-rules.json" > "$T/project/qwbuddy/dispatch-rules.json"
roster_response rule_1
task roster-fallback
TYPESAFE_API_KEY=fake-key run roster-fallback auto
test "$(worker roster-fallback)" = claude-fable-low
echo 'PASS roster disabled architect falls through to Fable low'
jq '.agents_disabled=["pi-sol-high"]' "$T/roster-rules.json" > "$T/project/qwbuddy/dispatch-rules.json"
roster_response default
task roster-disabled
TYPESAFE_API_KEY=fake-key reject_unchanged roster-disabled 2 '全部候选不可用'
echo 'PASS roster singleton disabled refuses without side effects'
cp "$T/roster-rules.json" "$T/project/qwbuddy/dispatch-rules.json"
printf '%s\n' '{"schemaVersion":6,"providers":[{"provider":"pi","accountKey":"magpie","windows":[{"kind":"weekly","percentRemaining":0}]}]}' > "$T/roster-quota.json"
cat > "$T/fakebin/quota-axi" <<'SH'
#!/usr/bin/env bash
[[ "$*" == '--json --no-credential-refresh' ]] || exit 2
cat "$QUOTA_AXI_SNAPSHOT"
SH
chmod +x "$T/fakebin/quota-axi"
task roster-quota
QUOTA_AXI_SNAPSHOT="$T/roster-quota.json" TYPESAFE_API_KEY=fake-key reject_unchanged roster-quota 2 'quota weekly 0%'
echo 'PASS roster singleton exhausted refuses without side effects'
for removed in codex devin; do
  task "removed-$removed"
  before="$(shasum "$T/project/tasks/2099-01-01-removed-$removed.md")"
  : > "$HERDR_LOG"
  if run "removed-$removed" "$removed"; then echo "FAIL removed $removed dispatched" >&2; exit 1; fi
  grep -q '合法工人' "$T/err"
  test "$(shasum "$T/project/tasks/2099-01-01-removed-$removed.md")" = "$before"
  test ! -s "$HERDR_LOG"
  echo "PASS roster removed $removed refuses without side effects"
done

# 冻结06第四场景：仅意图/规格/必要约束外发；技术模糊不用用户决策，权限缺口不default扩权。
reset_rule
task narrow
cat >> "$T/project/tasks/2099-01-01-narrow.md" <<'MD'
## 原始意图
原话：修复接口，保留指定型号。
### 工程规格
只改api.sh，返回版本v1。
## 必要约束
单机；不自动合并；没有联网部署授权。
## 历史报告
working: SECRET-HISTORY-SENTINEL
延续历史：CONTINUATION-SENTINEL
MD
jq '.answers.rule.choice="rule_1" | .answers.rule.confidence=0.4 | .answers.rule.probabilities={rule_1:0.4,default:0.6}' "$FAKE_RESPONSE" > "$T/next" && mv "$T/next" "$FAKE_RESPONSE"
cp "$T/project/qwbuddy/workers.sh" "$T/pinned-before"
TYPESAFE_API_KEY=fake-key run narrow auto
test "$(worker narrow)" = pi
cmp -s "$T/pinned-before" "$T/project/qwbuddy/workers.sh"
jq -e '.state.task.brief | contains("原话：修复接口") and contains("只改api.sh") and contains("没有联网部署授权") and (contains("SENTINEL") | not) and (contains("dispatch:") | not) and (contains("qwb-collab-") | not)' "$FAKE_REQUEST" >/dev/null
echo 'PASS user_路由模糊不扩权：窄输入无累计日志，技术ambiguous默认继续，指定模型/effort配置不变'
# 同一低置信度候选若缺权限，不得落默认；clear也不能越权。
printf '%s\n' '{"rules":[{"when":"deploy","worker":"claude","requires":["deploy"]}],"default":{"worker":"pi"}}' > "$T/project/qwbuddy/dispatch-rules.json"
for confidence in 0.4 0.9; do
  task permission-gap
  jq --argjson confidence "$confidence" '.answers.rule.confidence=$confidence | .answers.rule.probabilities={rule_1:$confidence,default:(1-$confidence)}' "$FAKE_RESPONSE" > "$T/next" && mv "$T/next" "$FAKE_RESPONSE"
  TYPESAFE_API_KEY=fake-key reject_unchanged permission-gap 2 '权限'
done
# off也不能绕过default本身明确需要的权限。
printf '%s\n' '{"rules":[],"default":{"worker":"pi","requires":["deploy"]}}' > "$T/project/qwbuddy/dispatch-rules.json"
task default-gap
reject_unchanged default-gap 2 '权限'
echo 'PASS 权限缺口clear/ambiguous/off均非零且无Herdr/dispatch副作用'
