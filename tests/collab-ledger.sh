#!/usr/bin/env bash
# 真实公开入口 + 临时项目/fake Herdr；不接触真实endpoint、安装目录或主票。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1
export TMPDIR="$TMP"
trap 'qwb_test_drain && rm -rf "$TMP" || exit 1' EXIT
P="$TMP/project"; mkdir -p "$P" "$TMP/bin"
bash "$ROOT/bin/qwb-init.sh" "$P" >/dev/null
rm -f "$P/qwbuddy/brief-include.md"
export HERDR_PANE_ID=test:ctl
printf 'QWB_WORKERS="pi"\nQWB_AGENT_START_MS=1000\nQWB_GATE_FAST=":"\nQWB_GATE_FULL=":"\n' > "$P/qwbuddy/config.sh"
printf 'qwb_worker pi herdr\n' > "$P/qwbuddy/workers.sh"
mkdir -p "$P/qwbuddy/.controller.lock"
printf '2026-01-01T00:00:00Z test:ctl\n' > "$P/qwbuddy/.controller.lock/owner"
export TEST_PROJECT="$P" TEST_ROOT="$ROOT" TEST_LOG="$TMP/herdr.log"
REAL_LSOF="$(command -v lsof)"; export REAL_LSOF
cat > "$TMP/bin/herdr" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$TEST_LOG"
case "$1 $2" in
  'workspace list') printf '{"result":{"workspaces":[{"workspace_id":"test","focused":true,"worktree":{"repo_root":"%s"}}]}}\n' "$TEST_PROJECT" ;;
  'agent get') printf '{"error":{"code":"agent_not_found"}}\n'; exit 1 ;;
  'tab create') printf '{"result":{"root_pane":{"pane_id":"test:worker","tab_id":"test:tab"}}}\n' ;;
  'agent start') printf '{"result":{"type":"agent_started"}}\n' ;;
  'agent prompt')
    if [[ "${TEST_FAIL_PROMPT:-0}" == 1 ]]; then
      HERDR_PANE_ID=test:worker bash "$TEST_ROOT/bin/qwb-ledger.sh" append --project "$TEST_PROJECT" --task "$TEST_TASK" --event-id worker-during-prompt -- 'working: 在失败投递前真实回报'
      printf 'injected prompt failure\n' >&2; exit 9
    fi
    printf '{"result":{"type":"ok"}}\n' ;;
  'pane get')
    [[ "$3" != test:unknown ]] || { printf '{"error":{"code":"unavailable"}}\n' >&2; exit 1; }
    if [[ "$3" == test:oldpane && -e "$TEST_PROJECT/pane-gone" ]]; then
      reply='{"error":{"code":"pane_not_found"}}'
      case "${TEST_NATIVE_STREAM:-stderr}" in
        stdout) printf '%s\n' "$reply" ;;
        stderr) printf '%s\n' "$reply" >&2 ;;
        bad-stdout) printf 'not-json\n'; printf '%s\n' "$reply" >&2 ;;
        bad-stderr) printf '%s\n' "$reply"; printf 'not-json\n' >&2 ;;
        both-json) printf '%s\n' "$reply"; printf '%s\n' "$reply" >&2 ;;
        empty) : ;;
        unknown) printf '{"error":{"code":"unavailable"}}\n' >&2 ;;
        zero) printf '%s\n' "$reply" >&2; exit 0 ;;
        *) exit 77 ;;
      esac
      exit 1
    fi
    printf '{"result":{"pane":{"pane_id":"%s","agent":"pi","workspace_id":"test","cwd":"%s"}}}\n' "$3" "$TEST_PROJECT" ;;
  'pane list') printf '{"result":{"panes":[{"pane_id":"test:watch","workspace_id":"test"}]}}\n' ;;
  'pane process-info')
    [[ "${TEST_UNKNOWN_WATCH:-0}" != 1 ]] || exit 1
    python3 - "$PPID" <<'PY'
import json,os,subprocess,shlex,sys
if os.environ.get('TEST_ENSURE')=='1':
    pid=42; argv=['bash',os.environ['TEST_ROOT']+'/bin/qwb-wake.sh','--project',os.environ['TEST_PROJECT'],'--pane','test:ctl']
else:
    pid=int(subprocess.check_output(['ps','-o','ppid=','-p',sys.argv[1]]))
    argv=shlex.split(subprocess.check_output(['ps','-o','command=','-p',str(pid)],text=True).strip())
p={'pid':pid,'argv':argv,'argv0':argv[0],'cmdline':' '.join(argv)}
print(json.dumps({'result':{'process_info':{'foreground_processes':[p]}}}))
PY
    ;;
  'pane run'|'tab close'|'agent list') printf '{"result":{"type":"ok"}}\n' ;;
  *) echo "unexpected fake Herdr API: $*" >&2; exit 77 ;;
esac
SH
cat > "$TMP/bin/mv" <<'SH'
#!/usr/bin/env bash
set -eu
if [[ "${TEST_FAIL_MV:-0}" == 1 ]]; then exit 19; fi
if [[ -n "${TEST_MV_READY:-}" ]]; then
  printf '%s\n' "$PPID" > "$TEST_MV_READY"
  read -r _ < "$TEST_MV_GATE"
fi
exec /bin/mv "$@"
SH
cat > "$TMP/bin/lsof" <<'SH'
#!/usr/bin/env bash
if [[ "${TEST_UNKNOWN_PROBE:-0}" == 1 ]]; then echo 'lsof access unknown' >&2; exit 1; fi
exec "$REAL_LSOF" "$@"
SH
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
L="$ROOT/bin/qwb-ledger.sh"; T="$P/tasks/2099-01-01-case.md"
write_ticket() {
  cat > "$1" <<'EOF'
# 原始意图：保留使用者原话
state: running
implementation-authorized: explicit fixture scope approval
dispatch-budget: 20
## 工程规格
只做被授权的切片。
## 1. 验收场景
### user_正常
Given 临时项目
When 派发
Then 完整持久读回
### user_失败
Given 写入失败
When 发布
Then 拒绝且原字节不变
EOF
}
ledger() { bash "$L" "$1" --project "$P" --task "$T" "${@:2}"; }
manifest() {
  python3 - "$1" "$2" <<'PY'
import hashlib,json,sys
names=['run','wake','worktree','worker','controller','old-fds','external-actions']
m={'task_sha256':hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest(),
   'confirm':{k:'临时项目测试中已停写/核对，无真实派工' for k in names}}
json.dump(m,open(sys.argv[2],'w'),ensure_ascii=False)
PY
}
expect_fail() { if "$@" > "$TMP/rejected.log" 2>&1; then echo "FAIL: unexpected success $*"; exit 1; fi; }
unchanged() { cmp -s "$1" "$2" || { echo 'FAIL: 原完整版本变动'; exit 1; }; }
wait_file() {
  for _ in {1..400}; do [[ -s "$1" ]] && return 0; sleep 0.01; done
  echo "FAIL: barrier未就绪 $1"; exit 1
}
native_reply_checks() {
  local R="$P/tasks/2099-02-02-native-stream.md"
  write_ticket "$R"; manifest "$R" "$TMP/native-manifest.json"
  bash "$L" migrate --project "$P" --task "$R" -- "$TMP/native-manifest.json" >/dev/null
  python3 - "$P" "$R" "$L" "$ROOT" "$TMP" <<'PY'
import hashlib,json,os,subprocess,sys
P,T,L,ROOT,TMP=sys.argv[1:]; failures=[]
def run(cmd,actor,stream='stderr'):
    return subprocess.run(cmd,env=dict(os.environ,HERDR_PANE_ID=actor,TEST_NATIVE_STREAM=stream),capture_output=True,text=True)
def ledger(cmd,*args,actor='test:newctl',opts=(),stream='stderr'):
    return run(['bash',L,cmd,'--project',P,'--task',T,*opts,'--',*args],actor,stream)
def lock(cmd,actor): return run(['bash',ROOT+'/bin/qwb-lock.sh',cmd,'--project',P],actor)
def content(): return open(T,'rb').read()
def read():
    r=ledger('read'); assert r.returncode==0,r.stderr; return json.loads(r.stdout)
def require(ok,msg):
    if not ok: failures.append(msg); print('FAIL native-reply:',msg)
assert lock('release','test:ctl').returncode==0
assert lock('acquire','test:oldpane').returncode==0
assert ledger('claim','pane-op',actor='test:oldpane').returncode==0
snapshot=content(); before=read()
require(lock('acquire','test:newctl').returncode!=0 and content()==snapshot,'live pane blocks actual lock takeover')
ep=TMP+'/pane-evidence.json'
json.dump({'task_sha256':hashlib.sha256(snapshot).hexdigest(),'op_id':'pane-op','previous_owner':'test:oldpane','reconciled':'fake pane closed; no dispatch; retain original claim/history'},open(ep,'w'))
opts=['--expect',str(before['rev'])]
# 合法主动移交锁也不证明原pane已死：真实入口仍须拒绝接手claim。
assert lock('release','test:oldpane').returncode==0
assert lock('acquire','test:newctl').returncode==0
r=ledger('recover-claim','pane-op',ep,opts=opts)
require(r.returncode!=0 and content()==snapshot,'live pane recovery rejected')
assert lock('release','test:newctl').returncode==0
assert lock('acquire','test:oldpane').returncode==0
# fake端点消失后由真实qwb-lock探针接手，错误JSON放stderr，与真实Herdr一致。
open(P+'/pane-gone','w').close()
assert lock('acquire','test:newctl').returncode==0
for command,args,options in [('release',['pane-op'],()),('claim',['next-op'],()),('recover-claim',['pane-op',ep],['--expect',str(before['rev']-1)])]:
    require(ledger(command,*args,opts=options).returncode!=0 and content()==snapshot,'no arbitrary release/claim/stale recovery '+command)
for stream in ['bad-stdout','bad-stderr','both-json','empty','unknown','zero']:
    open(T,'wb').write(snapshot)
    r=ledger('recover-claim','pane-op',ep,opts=opts,stream=stream)
    require(r.returncode!=0 and content()==snapshot,'invalid/unknown reply rejected '+stream)
# 同一临时快照分别检查stdout兼容和真实stderr；不执行真实端点或其他返修请求。
for stream in ['stdout','stderr']:
    open(T,'wb').write(snapshot)
    r=ledger('recover-claim','pane-op',ep,opts=opts,stream=stream)
    require(r.returncode==0,'dead pane recovery '+stream+' rc='+str(r.returncode)+' '+r.stderr)
    if r.returncode==0:
        after=read()
        require(after['claim']=={'op_id':'pane-op','owner':'test:newctl'} and after['ops']['pane-op']['owner']=='test:newctl' and after['events'][:-1]==before['events'] and after['events'][-1]['kind']=='recover-claim' and after['events'][-1]['op_id']=='pane-op','persistent original claim/op/history '+stream)
        require(ledger('release','pane-op').returncode==0,'explicit release after recovery '+stream)
        print('PASS native-reply: dead pane recovery '+stream)
assert lock('release','test:newctl').returncode==0
assert lock('acquire','test:ctl').returncode==0
os.unlink(P+'/pane-gone')
for path in [T,T+'.qwb-lock',T+'.qwb-original']: os.unlink(path)
if failures: raise SystemExit(1)
print('NATIVE REPLY PASS: stderr/stdout, live/unknown/malformed, persistent claim/history')
PY
}
native_reply_checks
[[ "${TEST_NATIVE_REPLY_ONLY:-0}" != 1 ]] || exit 0
repair_checks() {
  local R="$P/tasks/2099-02-01-repair.md"
  write_ticket "$R"; manifest "$R" "$TMP/repair-manifest.json"
  bash "$L" migrate --project "$P" --task "$R" -- "$TMP/repair-manifest.json" >/dev/null
  python3 - "$P" "$R" "$L" "$ROOT" "$TMP" <<'PY'
import hashlib,json,os,re,subprocess,sys
P,T,L,ROOT,TMP=sys.argv[1:]; failures=[]
def run(cmd,actor='test:ctl',**env):
    return subprocess.run(cmd,env=dict(os.environ,HERDR_PANE_ID=actor,HERDR_WORKSPACE_ID='test',**env),capture_output=True,text=True)
def ledger(cmd,*args,actor='test:ctl',opts=()):
    return run(['bash',L,cmd,'--project',P,'--task',T,*opts,'--',*args],actor)
def require(cond,msg):
    if not cond: failures.append(msg); print('FAIL repair:',msg)
def read():
    r=ledger('read'); assert r.returncode==0,r.stderr; return json.loads(r.stdout)
def content(): return open(T,'rb').read()
def owner(s): open(P+'/qwbuddy/.controller.lock/owner','w').write('2026-01-01T00:00:00Z '+s+'\n')
original=content(); require(read()['schema']==1,'normal schema')
for bad in ['null','false','0','[]','"bad"','true','1']:
    b=re.sub(rb'(?<=<!-- qwb-collab-v1\n)[^\n]+',bad.encode(),original)
    open(T,'wb').write(b)
    r=ledger('read'); w=ledger('append','working: bad downgrade',actor='unbound',opts=['--legacy'])
    require(r.returncode!=0 and w.returncode!=0 and content()==b,'invalid top-level '+bad+' fails closed')
open(T,'wb').write(original)
# 真正ensure登记与不同watch pane的两次once，不把HERDR_PANE_ID伪装为主控。
r=run(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--ensure','--pane','test:ctl'],TEST_ENSURE='1')
require(r.returncode==0,'controller ensure '+r.stderr)
before=len(read()['events']); log=os.environ['TEST_LOG']; open(log,'w').close()
cmd=['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--once','--pane','test:ctl']
a=run(cmd,'test:watch'); b=run(cmd,'test:watch')
x=read(); wakes=[e for e in x['events'][before:] if e['kind']=='wake']
sends=[l for l in open(log) if l.startswith('pane run ')]
require(a.returncode==b.returncode==0 and len(wakes)==len(sends)==1,'registered watch dedupe rc='+str((a.returncode,b.returncode))+' events/sends='+str((len(wakes),len(sends))))
ledger('append','working: next watch progress'); snap=content()
for actor,target,unknown in [('unbound','test:ctl','0'),('test:watch','test:other','0'),('test:watch','test:ctl','1')]:
    open(log,'w').close()
    r=run(cmd[:-1]+[target],actor,TEST_UNKNOWN_WATCH=unknown)
    require(r.returncode!=0 and content()==snap and 'pane run ' not in open(log).read(),'watch boundary '+actor+'/'+target+'/'+unknown)
for action,args in [('state',['done']),('append',['working: watch may not write arbitrary progress']),('claim',['watch-op']),('wake',['test:ctl','running','a'*40])]:
    r=ledger(action,*args,actor='test:watch')
    require(r.returncode!=0 and content()==snap,'watch cannot directly '+action)
# 实际qwb-lock alive否决→进程死→acquire接管；不是仅编辑owner模拟后置状态。
lock=lambda c,a: run(['bash',ROOT+'/bin/qwb-lock.sh',c,'--project',P],a)
assert lock('release','test:ctl').returncode==0
child=subprocess.Popen(['sleep','120']); old='pid:'+str(child.pid)
try:
    assert lock('acquire',old).returncode==0
    assert ledger('claim','orphan-op',actor=old).returncode==0
    require(lock('acquire','test:newctl').returncode!=0,'alive owner cannot be taken')
    child.terminate(); child.wait()
    assert lock('acquire','test:newctl').returncode==0
    x=read(); snap=content()
    require(ledger('release','orphan-op',actor='test:newctl').returncode!=0 and ledger('claim','new-op',actor='test:newctl').returncode!=0 and content()==snap,'ordinary release/claim keep orphan')
    evidence={'task_sha256':hashlib.sha256(snap).hexdigest(),'op_id':'orphan-op','previous_owner':old,'reconciled':'temporary process killed/waited; no external dispatch; retain claim until explicit release'}
    ep=TMP+'/recovery.json'; json.dump(evidence,open(ep,'w'))
    for actor,rev in [('unbound',x['rev']),('test:newctl',x['rev']-1)]:
        r=ledger('recover-claim','orphan-op',ep,actor=actor,opts=['--expect',str(rev)])
        require(r.returncode!=0 and content()==snap,'recover identity/version fails closed')
    for key,value in [('task_sha256','0'*64),('op_id','wrong-op'),('previous_owner','test:other'),('reconciled','')]:
        bad=dict(evidence); bad[key]=value; json.dump(bad,open(ep,'w'))
        r=ledger('recover-claim','orphan-op',ep,actor='test:newctl',opts=['--expect',str(x['rev'])])
        require(r.returncode!=0 and content()==snap,'recover evidence '+key+' fails closed')
    json.dump(evidence,open(ep,'w'))
    r=ledger('recover-claim','orphan-op',ep,actor='test:newctl',opts=['--expect',str(x['rev'])])
    require(r.returncode==0,'dead claim recovery '+r.stderr)
    if r.returncode==0:
        y=read(); require(y['claim']=={'owner':'test:newctl','op_id':'orphan-op'} and y['events'][:-1]==x['events'] and y['events'][-1]['kind']=='recover-claim','recovery retains claim/history')
        require(ledger('release','orphan-op',actor='test:newctl').returncode==0 and ledger('claim','new-op',actor='test:newctl').returncode==0,'recovered owner can explicitly continue')
        assert ledger('release','new-op',actor='test:newctl').returncode==0
finally:
    if child.poll() is None: child.terminate(); child.wait()
    assert lock('release','test:newctl').returncode==0
    assert lock('acquire','test:ctl').returncode==0
# 现主控也不能凭对账文件接管活/未知旧owner；显式锁交接不等于死亡证明。
for previous in ['pid:'+str(os.getpid()),'test:unknown']:
    x=read()
    if x['claim']:
        assert ledger('release',x['claim']['op_id'],actor='test:ctl').returncode==0
    assert lock('release','test:ctl').returncode==0
    assert lock('acquire',previous).returncode==0
    oid='live-op' if previous.startswith('pid:') else 'unknown-op'
    assert ledger('claim',oid,actor=previous).returncode==0
    assert lock('release',previous).returncode==0
    assert lock('acquire','test:ctl').returncode==0
    snap=content(); x=read()
    ep=TMP+'/recovery.json'
    json.dump({'task_sha256':hashlib.sha256(snap).hexdigest(),'op_id':oid,'previous_owner':previous,'reconciled':'explicit transfer but not proof of death'},open(ep,'w'))
    r=ledger('recover-claim',oid,ep,opts=['--expect',str(x['rev'])])
    require(r.returncode!=0 and content()==snap,'recover live/unknown old owner rejected '+previous)
    # 清理仅临时测试：合法交还仍活原owner，由原owner自己release。
    assert lock('release','test:ctl').returncode==0
    assert lock('acquire',previous).returncode==0
    assert ledger('release',oid,actor=previous).returncode==0
    assert lock('release',previous).returncode==0
    assert lock('acquire','test:ctl').returncode==0
# 不把repair票/登记带进原场景，原来的精确event_id断言保持不变。
for path in [T,T+'.qwb-lock',T+'.qwb-original',P+'/qwbuddy/.watch']:
    if os.path.exists(path): os.unlink(path)
if failures: raise SystemExit(1)
print('PASS repair: falsy schema拒绝、独立watch最小授权/去重、真实死亡claim接管')
PY
}
repair_checks
[[ "${TEST_REPAIR_ONLY:-0}" != 1 ]] || exit 0
write_ticket "$T"; cp "$T" "$TMP/old"
ledger metrics > "$TMP/old-metrics.json"
python3 - "$TMP/old-metrics.json" <<'PY'
import json,sys
assert json.load(open(sys.argv[1]))['done_at']=='unknown'
PY
expect_fail ledger append -- 'working: 未迁票只读'
manifest "$T" "$TMP/manifest.json"
python3 - "$TMP/manifest.json" "$TMP/missing.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); m['confirm']['worker']=''
json.dump(m,open(sys.argv[2],'w'))
PY
expect_fail ledger migrate -- "$TMP/missing.json"
grep -q 'worker' "$TMP/rejected.log"; unchanged "$T" "$TMP/old"
expect_fail env TEST_UNKNOWN_PROBE=1 bash "$L" migrate --project "$P" --task "$T" -- "$TMP/manifest.json"
grep -q '无法确认' "$TMP/rejected.log"; unchanged "$T" "$TMP/old"
# 保持旧写FD打开，即使确认JSON齐全仍必须否决；不靠源代码grep。
exec 9>> "$T"
expect_fail ledger migrate -- "$TMP/manifest.json"
grep -q '写FD' "$TMP/rejected.log"; unchanged "$T" "$TMP/old"
exec 9>&-
ledger migrate --event-id migration -- "$TMP/manifest.json" >/dev/null
unchanged "$T.qwb-original" "$TMP/old"
# 失败迁移发布可重试同一原字节备份，不重新写/覆盖历史备份。
RETRY="$P/tasks/2099-01-03-retry.md"; write_ticket "$RETRY"; cp "$RETRY" "$TMP/retry-old"
manifest "$RETRY" "$TMP/retry-manifest.json"
expect_fail env TEST_FAIL_MV=1 bash "$L" migrate --project "$P" --task "$RETRY" -- "$TMP/retry-manifest.json"
unchanged "$RETRY" "$TMP/retry-old"
bash "$L" migrate --project "$P" --task "$RETRY" -- "$TMP/retry-manifest.json" >/dev/null
unchanged "$RETRY.qwb-original" "$TMP/retry-old"
# 未完成的另一票不能影响已迁票，也绝不能迁成开放多角色。
OTHER="$P/tasks/2099-01-02-other.md"; write_ticket "$OTHER"; cp "$OTHER" "$TMP/other-old"
expect_fail bash "$L" migrate --project "$P" --task "$OTHER" -- "$TMP/missing.json"
unchanged "$OTHER" "$TMP/other-old"
# shellcheck source=bin/qwb-lib.sh
. "$ROOT/bin/qwb-lib.sh"
FP="$(printf '%s' "$(qwb_scenario_block "$T")" | shasum | cut -d' ' -f1)"
ledger prepare --event-id prepared -- "$FP" >/dev/null
ledger claim --event-id claimed -- dispatch-op >/dev/null
ledger dispatch --event-id dispatched -- dispatch-op test:worker "dispatch: 2026-01-01T00:00:00Z op_id=dispatch-op worker=pi agent=qwb-case pane=test:worker dir=$P" >/dev/null
expect_fail ledger dispatch -- dispatch-op test:worker "dispatch: 2026-01-01T00:00:00Z op_id=dispatch-op worker=pi agent=qwb-case pane=test:worker dir=$P"
# 保存只读旧FD，然后暂停修订writer于完整快照/发布边界；第二writer必须等锁。
exec 8< "$T"
LOCK_INODE="$(perl -e 'print((stat($ARGV[0]))[1])' "$T.qwb-lock")"
mkfifo "$TMP/publish-gate"
TEST_MV_READY="$TMP/publish-ready" TEST_MV_GATE="$TMP/publish-gate" \
  ledger revise --event-id revision -- "$FP" "$FP" '显式修订留痕，原场景不变' > "$TMP/revise.log" 2>&1 &
a=$!; wait_file "$TMP/publish-ready"
(
  HERDR_PANE_ID=test:worker ledger append --event-id worker-progress -- 'working: 屏障并发回报' > "$TMP/progress.log" 2>&1
  printf '%s\n' "$?" > "$TMP/progress.rc"
) &
b=$!
sleep 0.1
[[ ! -e "$TMP/progress.rc" ]] || { echo 'FAIL: writer未等待稳定短锁'; exit 1; }
printf 'go\n' > "$TMP/publish-gate"
wait "$a"; wait "$b"
[[ "$(cat "$TMP/progress.rc")" == 0 ]]
[[ "$(perl -e 'print((stat($ARGV[0]))[1])' "$T.qwb-lock")" == "$LOCK_INODE" ]]
# 同时发布多个成功事件，补偿必须按op_id定位，在rename后的原路径重读。
for i in {1..12}; do HERDR_PANE_ID=test:worker ledger append --event-id "parallel-$i" -- "working: 并发事件$i" >/dev/null & done
wait
ledger not-sent --event-id compensation -- dispatch-op 'blocked: 投递失败补偿' >/dev/null
[[ "$(qwb_scenario_block "$T")" == "$(qwb_scenario_block "$TMP/old")" ]]
cat <&8 > "$TMP/old-fd-snapshot"; exec 8<&-
if grep -q 'worker-progress' "$TMP/old-fd-snapshot"; then echo 'FAIL: 旧FD意外读到rename后事件'; exit 1; fi
grep -q '^not-sent:' "$T"
if grep -q '^dispatch:' "$T"; then echo 'FAIL: 补偿未撤销正确派发'; exit 1; fi
python3 - "$TMP/old" "$T" <<'PY'
import sys
assert open(sys.argv[1],'rb').read().rstrip(b'\n') in open(sys.argv[2],'rb').read()
PY
ledger read > "$TMP/events.json"
python3 - "$TMP/events.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); ids=[e['event_id'] for e in x['events']]
expected=['migration','prepared','claimed','dispatched','revision','worker-progress','compensation']+[f'parallel-{i}' for i in range(1,13)]
assert sorted(ids)==sorted(expected) and len(ids)==len(set(ids))
assert [e['seq'] for e in x['events']]==list(range(1,len(ids)+1))
assert all(e['at'].endswith('Z') for e in x['events'])
assert x['ops']['dispatch-op']['status']=='not-sent'
assert x['claim']['op_id']=='dispatch-op' and x['spec_rev']==1
PY
echo 'PASS user_并发修订与回报完整：event_id逐个恰一次，跨FD/rename补偿无丢失'
# 发布失败、真实候选写失败（ulimit使SIGXFSZ）均不动已有完整票。
cp "$T" "$TMP/before-failure"
expect_fail env TEST_FAIL_MV=1 HERDR_PANE_ID=test:ctl bash "$L" append --project "$P" --task "$T" --event-id failed-publish -- 'working: 发布失败'
unchanged "$T" "$TMP/before-failure"
# shellcheck disable=SC2016 # 子bash需要原样的位置实参
expect_fail bash -c 'ulimit -f 1; exec bash "$1" append --project "$2" --task "$3" --event-id failed-write -- "working: 写失败"' _ "$L" "$P" "$T"
unchanged "$T" "$TMP/before-failure"
# 真杀持短锁进程：原票完整，内核锁释放，但逻辑claim不清。
rm -f "$TMP/publish-ready"; mkfifo "$TMP/death-gate"
TEST_MV_READY="$TMP/publish-ready" TEST_MV_GATE="$TMP/death-gate" \
  ledger append --event-id killed -- 'working: 被终止的发布' > "$TMP/death.log" 2>&1 &
d=$!; wait_file "$TMP/publish-ready"
writer_pid="$(cat "$TMP/publish-ready")"
kill -TERM "$writer_pid"
printf 'go\n' > "$TMP/death-gate"
wait "$d" 2>/dev/null || true
# 已开始的原子发布可以完成：子发布程序继承同一短锁，下一reader不能越过它。
# 终止窗口允许旧完整版本或新完整版本，不能只因调用方死亡就假称未发布。
ledger read > "$TMP/after-death.json"
cp "$T" "$TMP/before-failure"
python3 - "$TMP/after-death.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['claim']['op_id']=='dispatch-op'
assert len([e for e in x['events'] if e['event_id']=='killed'])<=1
assert any(e['event_id']=='worker-progress' for e in x['events'])
PY
# 工人越权不靠提示词，legacy开关也不能绕过已迁票。
for cmd in state revise claim release answer resume migrate; do
  expect_fail env HERDR_PANE_ID=test:worker bash "$L" "$cmd" --project "$P" --task "$T" --legacy -- denied
  unchanged "$T" "$TMP/before-failure"
done
expect_fail env HERDR_PANE_ID=test:worker bash "$L" append --project "$P" --task "$T" -- 'working: spec-resolved: impl；伪处置'
expect_fail env HERDR_PANE_ID=secondmate bash "$L" append --project "$P" --task "$T" -- 'working: 其他角色'
expect_fail ledger append --expect 0 -- 'working: 过期版本'
expect_fail ledger append --event-id prepared -- 'working: 重复event'
unchanged "$T" "$TMP/before-failure"
# 未知owner release不可破坏主控锁；显式本人及死亡证据可释放。
printf '2026-01-01T00:00:00Z pid:invalid\n' > "$P/qwbuddy/.controller.lock/owner"
expect_fail bash "$ROOT/bin/qwb-lock.sh" release --project "$P"
grep -q 'pid:invalid' "$P/qwbuddy/.controller.lock/owner"
printf '2026-01-01T00:00:00Z test:ctl\n' > "$P/qwbuddy/.controller.lock/owner"
echo 'PASS user_写入故障与越权拒绝：实际失败发布/候选写/进程终止/权限与claim保留'
# 问题稳定key，working/done遮不住；旧票done时间unknown，显式答复才可恢复。
ledger release -- dispatch-op >/dev/null
# 已绑定工人仍能提出规格疑点；普通进展不解除，只有主控处置。
# 新派发前恢复一个有效绑定（此前not-sent的回报身份已封闭）。
ledger claim -- spec-op >/dev/null
ledger dispatch -- spec-op test:worker "dispatch: 2026-01-01T00:00:00Z op_id=spec-op worker=pi agent=qwb-case pane=test:worker dir=$P" >/dev/null
ledger release -- spec-op >/dev/null
HERDR_PANE_ID=test:worker ledger append -- 'blocked: spec-defect: 反例证据' >/dev/null
ledger append -- 'working: 普通进展不解除疑点' >/dev/null
expect_fail ledger prepare -- "$FP"
ledger append -- 'working: spec-resolved: impl；逐项回应反例证据' >/dev/null
ledger prepare -- "$FP" >/dev/null
ledger question --event-id opened -- budget '需要使用者明确预算' >/dev/null
ledger append --event-id plain-done -- 'done: 临时命令退出码0，未宣称验收' >/dev/null
ledger state -- "done" >/dev/null
bash "$ROOT/bin/qwb-status.sh" --project "$P" > "$TMP/status"
grep -q '\[未结\].*case' "$TMP/status"; grep -q 'key=budget 未答' "$TMP/status"
expect_fail ledger resume -- budget '无答复就恢复'
ledger answer --event-id answered -- budget '用户答复及证据：测试固定授权10' >/dev/null
ledger resume --event-id resumed -- budget '按真实答复恢复，测试证据' >/dev/null
bash "$ROOT/bin/qwb-status.sh" --metrics --project "$P" > "$TMP/metrics"
grep -q 'done_at.*T.*Z' "$TMP/metrics"; grep -q 'unknown' "$TMP/metrics"
[[ "$(qwb_scenario_block "$T")" == "$(qwb_scenario_block "$TMP/old")" ]]
# 真正qwb-run单主控链（临时项目/fake Herdr），失败并发回报依然存在。
ledger state -- running >/dev/null
export TEST_TASK="$T"
expect_fail env TEST_FAIL_PROMPT=1 bash "$ROOT/bin/qwb-run.sh" --project "$P" --task "$T" --worker pi --here
ledger read > "$TMP/run-readback.json"
python3 - "$TMP/run-readback.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert any(e['event_id']=='worker-during-prompt' for e in x['events'])
assert x['claim'] and x['ops'][x['claim']['op_id']]['status']=='not-sent'
PY
ledger release -- "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["claim"]["op_id"])' "$TMP/run-readback.json")" >/dev/null
bash "$ROOT/bin/qwb-run.sh" --project "$P" --task "$T" --worker pi --here > "$TMP/run-success.log"
ledger read > "$TMP/run-success.json"
python3 - "$TMP/run-success.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['claim'] is None and any(o['status']=='sent' for o in x['ops'].values())
PY
bash "$ROOT/bin/qwb-wake.sh" --project "$P" --once --pane test:ctl > "$TMP/wake.log"
ledger read > "$TMP/wake-readback.json"
python3 - "$TMP/wake-readback.json" <<'PY'
import json,sys
assert any(e['kind']=='wake' for e in json.load(open(sys.argv[1]))['events'])
PY
# 已迁票worktree --keep也走同一writer/持久claim；只建临时独立Git仓，不碰本任务pool。
git -C "$P" init -q; git -C "$P" config user.email test@example.invalid; git -C "$P" config user.name Test
printf 'temporary base\n' > "$P/base"; git -C "$P" add base; git -C "$P" commit -qm base
mkdir -p "$P/.worktrees"; git -C "$P" worktree add -q -b case "$P/.worktrees/case" HEAD
bash "$ROOT/bin/qwb-worktree.sh" finish case --keep=测试保留 --project "$P" > "$TMP/finish.log"
ledger read > "$TMP/finish-readback.json"
python3 - "$TMP/finish-readback.json" <<'PY'
import json,sys
x=json.load(open(sys.argv[1])); assert x['claim'] is None
assert any(e['kind']=='worktree' and 'keep' in e['line'] for e in x['events'])
assert any(o['status']=='released' for o in x['ops'].values())
PY
echo 'PASS user_单主控兼容时间线：真实run/wake/worktree入口、持久问题、metrics与场景冻结'
# UTF-8/schema/重复key/符号链接边界通过公开reader/writer实际拒绝。
cp "$T" "$TMP/valid-ticket"
python3 - "$T" <<'PY'
import sys
p=sys.argv[1]; b=open(p,'rb').read().replace(b'"schema":1',b'"schema":1,"schema":1'); open(p,'wb').write(b)
PY
expect_fail ledger read
cp "$TMP/valid-ticket" "$T"
python3 - "$T" <<'PY'
import sys
p=sys.argv[1]; b=open(p,'rb').read().replace(b'"schema":1',b'"schema":99'); open(p,'wb').write(b)
PY
expect_fail ledger read
cp "$TMP/valid-ticket" "$T"
printf '\xff' >> "$T"; expect_fail ledger append -- 'working: bad utf8'
cp "$TMP/valid-ticket" "$T"
ln -s "$T" "$P/tasks/link.md"
expect_fail bash "$L" append --project "$P" --task "$P/tasks/link.md" -- 'working: symlink'
expect_fail bash "$L" append --project "$P" --task "$TMP/old" -- 'working: outside'
# corrupt zone不能当legacy降级，原主意图原字节仍在备份。
unchanged "$T.qwb-original" "$TMP/old"
echo 'PASS user_拒绝未完成writer迁移：确认缺项/旧写FD/其他票隔离/协议边界'
echo 'COLLAB LEDGER PASS'
