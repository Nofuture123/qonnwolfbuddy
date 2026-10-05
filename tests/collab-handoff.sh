#!/usr/bin/env bash
# 真实公开入口，唯一临时项目与 fake Herdr；不接触现场会话。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
TMP="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1; trap 'qwb_test_drain && rm -rf "$TMP" || exit 1' EXIT
export TMPDIR="$TMP"
P="$TMP/project"; mkdir -p "$P/tasks" "$P/qwbuddy/.controller.lock" "$TMP/bin"
cp -R "$ROOT/bin" "$P/qwbuddy/bin"
cp -R "$ROOT/templates/roles" "$P/qwbuddy/roles"
cp "$ROOT/templates/"{TASK,QWBUDDY}.md "$P/qwbuddy/"
printf '2026-01-01T00:00:00Z test:ctl\n' > "$P/qwbuddy/.controller.lock/owner"
printf 'QWB_WAKE_INTERVAL_MS=10\nQWB_REWAKE_MS=20\n' > "$P/qwbuddy/config.sh"
printf '# fixture\nstate: running\n## 验收场景\nGiven temporary project\nWhen delivery crashes\nThen durable handoff is retained, failure is explicit\n' > "$P/tasks/case.md"
export HERDR_PANE_ID=test:ctl
L="$ROOT/bin/qwb-ledger.sh"; S="$ROOT/bin/qwb-send.sh"; T="$P/tasks/case.md"
ledger() { bash "$L" "$1" --project "$P" --task "$T" "${@:2}"; }
send() { bash "$S" "$1" --project "$P" --task "$T" "${@:2}"; }
python3 - "$T" "$TMP/migration.json" <<'PY'
import json,hashlib,sys
json.dump({'task_sha256':hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest(), 'confirm':{k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}},open(sys.argv[2],'w'))
PY
# lsof 是外部边界；fixture无旧writer，确定返回无FD。
printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/lsof"
export TEST_HERDR_LOG="$TMP/herdr.log"
cat > "$TMP/bin/herdr" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_HERDR_LOG"
if [[ "${TEST_TRANSPORT_FAIL:-0}" == 1 && "$1 $2" == 'pane run' ]]; then exit 9; fi
printf '{"result":{"type":"ok"}}\n'
SH
chmod +x "$TMP/bin/"*; export PATH="$TMP/bin:$PATH"
ledger migrate -- "$TMP/migration.json" >/dev/null
ledger append --event-id completion -- 'done: 成果E待交接' >/dev/null
# 宿主在 --block 返回后、交付前死；旧wake指纹不能吞掉成果。
rc=0; bash "$ROOT/bin/qwb-wake.sh" --project "$P" --block --max-ms 1 > "$TMP/first" || rc=$?
[[ "$rc" == 2 ]]
send pending > "$TMP/pending.json"
python3 - "$TMP/pending.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1])); assert any(e['source_event']=='completion' and not e['handled'] for e in p), '交付前崩溃丢待办'
PY
echo 'PASS 跨交付崩溃仍有持久待办'
python3 - "$P" "$S" "$L" "$ROOT" <<'PY'
import json,os,subprocess,sys,hashlib,time,signal,re
from pathlib import Path
from process_fixture import register, release
P,S,L,ROOT=sys.argv[1:]; T=P+'/tasks/case.md'
def call(cmd,*args,actor='test:ctl',rc=0,extra=None):
    p=subprocess.run(cmd+list(args),env={**os.environ,'HERDR_PANE_ID':actor,**(extra or {})},capture_output=True,text=True)
    assert p.returncode==rc,(cmd,args,p.returncode,p.stdout,p.stderr)
    return p.stdout.strip()
def send(cmd,*args,**kw): return call(['bash',S,cmd,'--project',P,'--task',T],*args,**kw)
def ledger(cmd,*args,**kw): return call(['bash',L,cmd,'--project',P,'--task',T],*args,**kw)
def pending(**kw): return json.loads(send('pending',**kw))
def read(): return json.loads(ledger('read'))
def reject(cmd):
    before=Path(T).read_bytes(); r=subprocess.run(cmd,capture_output=True,text=True)
    assert r.returncode!=0,(cmd,r.stdout,r.stderr)
    assert Path(T).read_bytes()==before,'拒绝请求改变票'
def proof(e,op,name='result.json',outcome='applied'):
    path=P+'/'+name; Path(path).write_text(json.dumps(dict(event_id=e,op_id=op,outcome=outcome,evidence='fixture public readback; no external action'))); return path
E=next(h['event_id'] for h in pending() if h['source_event']=='completion')
send('received','--event',E); send('received','--event',E)
assert not next(h for h in pending() if h['event_id']==E)['handled']
send('accept','--event',E,'--op','handle-E'); send('accept','--event',E,'--op','handle-E')
# C uses a private installed writer clock; never wait twenty real minutes.
notify_snapshot=Path(T).read_bytes(); notify_runtime=Path(P)/'qwbuddy/bin'
notify_scripts={s:(notify_runtime/s).read_bytes() for s in ['qwb-ledger.sh','qwb-lib.sh','qwb-send.sh','qwb-wake.sh']}
notify_L,notify_S=L,S
clock=Path(P)/'notify-clock';clock.write_text('4102444800000')
now=Path(P)/'notify-now';now.write_text('#!/bin/sh\ncat "$NOTIFY_CLOCK"\n');now.chmod(0o755)
try:
    if os.environ.get('QWB_NOTIFY_BASELINE')=='1':
        for s in notify_scripts:(notify_runtime/s).write_bytes(subprocess.check_output(['git','-C',ROOT,'show','4b1f2e2:bin/'+s]))
    script=notify_runtime/'qwb-ledger.sh'
    script.write_text(script.read_text().replace('my $now=int(time()*1000);','my $now=0+read_file($ENV{NOTIFY_CLOCK});'))
    L=str(script);S=str(notify_runtime/'qwb-send.sh')
    os.environ['NOTIFY_CLOCK']=str(clock);os.environ['QWB_NOW_MS_CMD']=str(now)
    # Suppress unrelated actions while leaving the exact E claim/op and counts intact.
    for h in pending():
        if h['event_id']==E:continue
        eid=h['event_id'];hop='notify-'+hashlib.sha256(eid.encode()).hexdigest()
        send('received','--event',eid);send('accept','--event',eid,'--op',hop);send('prepared','--event',eid,'--op',hop)
        send('handled','--event',eid,'--op',hop,'--result-ref',proof(eid,hop,hop+'.json'))
    base=Path(T).read_bytes()
    Path(P+'/qwbuddy/config.sh').write_text('QWB_REWAKE_MS=1800000\n')
    def wake():
        native=Path(os.environ['TEST_HERDR_LOG']);native.write_text('')
        call(['bash',str(notify_runtime/'qwb-wake.sh'),'--project',P,'--once','--pane','test:ctl'])
        return [line for line in native.read_text().splitlines() if line.startswith('pane run ') and E in line]
    for exhausted in [False,True]:
        Path(T).write_bytes(base);clock.write_text('4102444800000')
        if exhausted:
            for _ in range(3):send('transport','--event',E)
        send('activity','--event',E,'--wait-ms','1200000','--reason','fixture twenty minute wait')
        clock.write_text(str(4102444800000+19*60000));assert not wake(), 'nineteen minutes woke early'
        clock.write_text(str(4102444800000+21*60000))
        bells=wake();print('EVIDENCE notify C minute21',exhausted,bells,flush=True)
        assert len(bells)==1, 'expired wait still blocked by retry/count'
        assert not wake(), 'restart repeats expired wait immediately'
        clock.write_text(str(4102444800000+50*60000));assert not wake()
        clock.write_text(str(4102444800000+51*60000));assert len(wake())==1
        assert read()['handoffs'][E]['transport_count']<=3 and read()['handoffs'][E]['accepted']=='test:ctl'
        send('activity','--event',E,'--wait-ms','1200000','--reason','new real tool activity')
        assert not wake(), 'new bounded wait lost protection'
    print('PASS notify C：19分钟静默、21分钟立即重叫、已封顶仍到期、重启不重叫、30分钟频率上限、新活动保护',flush=True)
finally:
    Path(T).write_bytes(notify_snapshot);L,S=notify_L,notify_S
    for s,raw in notify_scripts.items():(notify_runtime/s).write_bytes(raw)
    for key in ['NOTIFY_CLOCK','QWB_NOW_MS_CMD']:os.environ.pop(key,None)
    Path(P+'/qwbuddy/config.sh').write_text('QWB_WAKE_INTERVAL_MS=10\nQWB_REWAKE_MS=20\n')
if os.environ.get('QWB_NOTIFY_ONLY')=='C':raise SystemExit(0)
send('activity','--event',E,'--wait-ms','60000','--reason','等待fixture工具返回，最长一分钟')
time.sleep(.04)
assert E not in [h['event_id'] for h in json.loads(send('pending','--due','--retry-ms','20'))], '已接手合理wait被误催'
ledger('question','--event-id','question','--','budget','用户预算未答')
ledger('append','--event-id','second-done','--','done: 中间成果必须保留')
ledger('append','--event-id','new-working','--','working: 后续进展不得遮住前面问题或成果')
p=pending(); sources={h['source_event'] for h in p}
assert {'completion','question','second-done','new-working'}<=sources
# 第二票仍交接，不由第一票claim等待挡住；完整旧批次与新事件分别确认。
B=P+'/tasks/other.md'; Path(B).write_text('# other\nstate: running\n')
m=P+'/migration-other.json'; Path(m).write_text(json.dumps(dict(task_sha256=hashlib.sha256(Path(B).read_bytes()).hexdigest(),confirm={k:'fixture stopped' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
call(['bash',L,'migrate','--project',P,'--task',B,'--',m])
call(['bash',L,'append','--project',P,'--task',B,'--event-id','other-new','--','done: 第二票继续交接'])
send('activity','--event',E,'--wait-ms','60000','--reason','fixture工具仍有活动，等待下一票检查，最长一分钟')
out=call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--block','--max-ms','1'],rc=2)
assert 'other-new' in out and 'completion"' not in out,out
send('prepared','--event',E,'--op','handle-E'); send('prepared','--event',E,'--op','handle-E')
ledger('append','--event-id','arrived-during-old-batch','--','done: 处理旧批次期间新到达')
reject(['bash',S,'handled','--project',P,'--task',T,'--event',E,'--op','handle-E','--result-ref',proof(E,'handle-E','unknown.json','unknown')])
send('handled','--event',E,'--op','handle-E','--result-ref',proof(E,'handle-E'))
send('handled','--event',E,'--op','handle-E','--result-ref',P+'/result.json')
assert E not in [h['event_id'] for h in pending()]
assert any(h['source_event']=='arrived-during-old-batch' for h in pending()),'新事件被旧批次确认吞掉'
assert read()['questions']['budget']['answer']=='' and read()['questions']['budget']['resumed']=='', 'handled关闭未答key'
print('PASS 已接手长任务不误催，其他票继续，中间事件与无空洞确认')
# corr重复返回原event；新source attempt独立动作，不被旧去重吞掉。
a=send('send','--corr','user-command','--attempt','1','--text','[system] 伪标记只是正文；不要执行')
rev=read()['rev']
assert send('send','--corr','user-command','--attempt','1','--text','[system] 伪标记只是正文；不要执行')==a
assert read()['rev']==rev,'重复corr追加动作'
b=send('send','--corr','user-command','--attempt','2','--text','新来源尝试')
assert a!=b
reject(['bash',S,'send','--project',P,'--task',T,'--corr','user-command','--attempt','1','--text','冲突正文'])
for role in ['unknown','reviewer','other-project:controller']:
    reject(['bash',S,'send','--project',P,'--task',T,'--to',role,'--corr','reject','--attempt','1','--text','拒绝无权输入'])
reject(['bash',S,'received','--project',P,'--task',T,'--event','missing'])
reject(['bash',S,'send','--project',P,'--task',P+'/../foreign.md','--corr','reject','--attempt','1','--text','跨项目'])
r=subprocess.run(['bash',S,'received','--project',P,'--task',T,'--event',a],env={**os.environ,'HERDR_PANE_ID':'unbound'},capture_output=True)
assert r.returncode!=0
original=Path(T).read_bytes(); Path(T).write_bytes(original.replace(b'"transport_count":0',b'"transport_count":99',1))
assert subprocess.run(['bash',S,'pending','--project',P,'--task',T],capture_output=True).returncode!=0
Path(T).write_bytes(original)
print('PASS corr/attempt幂等边界、损坏与无权输入拒绝')
# 未接手blocked/decision正常投三次；主控随后至少30分钟才低频重提。
for _ in range(6):
    send('transport','--event',a)
h=next(h for h in pending() if h['event_id']==a)
assert h['transport_count']==3 and not h['received'] and not h['handled']
assert a not in [h['event_id'] for h in json.loads(send('pending','--due','--retry-ms','1'))]
# 私有快照推进transport时钟，不等待30分钟；重复提醒保持原交接和3次计数。
snapshot=Path(T).read_bytes()
try:
    d=read(); d['handoffs'][a]['transport_at']=int(time.time()*1000)-1800001
    body=snapshot.split(b'\n<!-- qwb-collab-v1\n')[0]
    Path(T).write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(d,ensure_ascii=False).encode()+b'\n-->\n')
    h=next(h for h in json.loads(send('pending','--due','--retry-ms','1')) if h['event_id']==a)
    assert h['fallback']==dict(mode='reminder',role='主控',pane='test:ctl',retry_ms=1)
    send('transport','--event',a,'--mode','reminder','--route-role','主控','--route-pane','test:ctl','--retry-ms','1')
    h=next(h for h in pending() if h['event_id']==a)
    assert h['transport_count']==3 and not h['received'] and not h['handled']
    assert a not in [h['event_id'] for h in json.loads(send('pending','--due','--retry-ms','1'))]
finally: Path(T).write_bytes(snapshot)
print('PASS transport正常预算封顶3，耗尽后30分钟重提原交接，API/门铃不冒充处理')
# transport失败保留原event；status展示未答key和预算耗尽，不洗状态。
c_fail=send('send','--corr','transport-fail','--attempt','1','--text','宿主传输失败不得吞掉正文')
call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--once','--pane','test:ctl'],extra={'TEST_TRANSPORT_FAIL':'1'})
h=next(h for h in pending() if h['event_id']==c_fail)
assert h['transport_count']==1 and not h['received'] and not h['handled']
ledger('state','--','done')
status_run=subprocess.run(['bash',ROOT+'/bin/qwb-status.sh','--project',P],env=os.environ,capture_output=True,text=True)
assert status_run.returncode==0 and 'syntax error' not in status_run.stderr,(status_run.stdout,status_run.stderr)
status=status_run.stdout
assert re.search(r'\[未结\].*case.md.*state=done',status), 'done吞未答问题或未handled义务'
ledger('state','--','running')
assert '重投预算耗尽' in status and '问题未结: key=budget' in status
assert not any(x.startswith(('tab create','session ','server ')) for x in Path(os.environ['TEST_HERDR_LOG']).read_text().splitlines()), '正文导致生命周期控制'
print('PASS transport失败保留待办，status不把received当handled')
# 真实两种入口竞争：先耗尽fixture门铃预算，监督循环持续等待；第二owner明确拒绝。
for task in [T,B]:
    arr=json.loads(call(['bash',S,'pending','--project',P,'--task',task]))
    for h in arr:
        for _ in range(3): call(['bash',S,'transport','--project',P,'--task',task,'--event',h['event_id']])
watch=subprocess.Popen(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--block','--max-ms','500'],env=os.environ,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
register(watch.pid)
try:
    time.sleep(.15)
    assert watch.poll() is None, 'first监督owner没有等待'
    call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--once','--pane','test:ctl'],rc=75)
    out,err=watch.communicate(timeout=20)
    assert watch.returncode==124,(out,err)
    call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--once','--pane','test:ctl'])
    print('PASS 内核单一监督owner，第二适配器拒绝，周期退出后可正常接班')
finally:
    if watch.poll() is None: os.killpg(watch.pid,signal.SIGTERM); watch.wait(timeout=20)
    release(watch.pid)
# 真实进程死亡后的prepared接班：移交同一op，不重发副作用。
old=subprocess.Popen(['sleep','60']); owner=Path(P+'/qwbuddy/.controller.lock/owner')
oldactor='pid:'+str(old.pid)
try:
    owner.write_text('old '+oldactor+'\n')
    c=send('send','--corr','crash-action','--attempt','1','--text','prepared后崩溃',actor=oldactor)
    send('received','--event',c,actor=oldactor); send('accept','--event',c,'--op','crash-op',actor=oldactor); send('prepared','--event',c,'--op','crash-op',actor=oldactor)
    owner.write_text('new test:ctl\n')
    snapshot=Path(T).read_bytes(); d=read(); recovery=P+'/recovery.json'
    Path(recovery).write_text(json.dumps(dict(task_sha256=hashlib.sha256(snapshot).hexdigest(),op_id='crash-op',previous_owner=oldactor,reconciled='副作用未知，移交后先结果读回，不重发')))
    reject(['bash',S,'reconcile','--project',P,'--task',T,'--event',c,'--proof',recovery,'--expect',str(d['rev'])])
    old.terminate(); old.wait()
    send('reconcile','--event',c,'--proof',recovery,'--expect',str(d['rev']))
    h=next(h for h in pending() if h['event_id']==c)
    assert h['prepared']==1 and h['op_id']=='crash-op' and h['reconcile']==1 and not h['handled']
    send('handled','--event',c,'--op','crash-op','--result-ref',proof(c,'crash-op','recovered-result.json','not-applied'))
    print('PASS prepared崩溃先对账，确认旧owner确死再移交同一op')
finally:
    if old.poll() is None: old.terminate(); old.wait()

# 首轮P2-1：问题已交出并handled，真实答复持久化后宿主结束；新reader恢复交接。
def new_ticket(name):
    global T
    T=P+'/tasks/'+name+'.md'; Path(T).write_text('# '+name+'\nstate: running\n')
    m=P+'/'+name+'-migration.json'
    Path(m).write_text(json.dumps(dict(task_sha256=hashlib.sha256(Path(T).read_bytes()).hexdigest(),confirm={k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
    ledger('migrate','--',m)
def handled(h,op):
    e=h['event_id']; send('received','--event',e); send('accept','--event',e,'--op',op)
    send('prepared','--event',e,'--op',op)
    send('handled','--event',e,'--op',op,'--result-ref',proof(e,op,op+'-result.json'))
new_ticket('answered-question')
ledger('question','--event-id','Q','--','budget','Need budget')
for i,h in enumerate(pending()): handled(h,'question-delivery-'+str(i))
assert pending()==[] and read()['questions']['budget']['answer']==''
ledger('answer','--event-id','A','--','budget','Approved 100')
# 这里不调用收到答复的原宿主；每次CLI都是重新启动，只有同票持久内容可用。
answers=pending()
assert any(h['source_event']=='A' and h['payload']=='working: answer key=budget Approved 100' for h in answers), 'handled问题后，新answer来源漏交'
out=call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--block','--max-ms','1'],rc=2)
assert 'source:A' in out and 'Approved 100' in out
assert read()['questions']['budget']['resumed']==''
handled(next(h for h in pending() if h['source_event']=='A'),'answer-delivery')
ledger('resume','--event-id','R','--','budget','按真实答复继续')
ledger('state','--','done')
# 问题key已恢复，尚未补建resume来源；status/open_items仍须识别真实新义务。
status_run=subprocess.run(['bash',ROOT+'/bin/qwb-status.sh','--project',P],env=os.environ,capture_output=True,text=True)
assert status_run.returncode==0 and 'syntax error' not in status_run.stderr
assert re.search(r'\[未结\].*answered-question.md.*state=done',status_run.stdout), 'lib漏掉已结key之后的真实resume来源'
assert any(h['source_event']=='R' for h in pending()), 'resume真实行动来源漏交'
handled(next(h for h in pending() if h['source_event']=='R'),'resume-delivery')
assert pending()==[]
rev=read()['rev']; assert pending()==[] and pending()==[] and read()['rev']==rev, 'receipt/wake来源自激循环'
ledger('claim','--','failed-dispatch-op')
ledger('dispatch','--','failed-dispatch-op','test:failed-worker',f'dispatch: 2026-01-01T00:00:00Z op_id=failed-dispatch-op worker=pi agent=fixture pane=test:failed-worker dir={P}')
ledger('not-sent','--event-id','delivery-failed','--','failed-dispatch-op','blocked: fixture transport failed')
ledger('release','--','failed-dispatch-op')
assert any(h['source_event']=='delivery-failed' for h in pending()), 'not-sent真实失败来源漏交'
handled(next(h for h in pending() if h['source_event']=='delivery-failed'),'failure-delivery')
assert pending()==[], 'dispatch/release/receipt造成自激'
print('PASS P2-1 answer中断恢复、resume/not-sent真实来源，receipt/wake无自激')

# 首轮P2-2：同票唯一op命名空间，分别覆盖handoff先占与原claim先占。
new_ticket('op-handoff-first')
e=send('send','--corr','action','--attempt','1','--text','需要prepared的动作')
send('received','--event',e); send('accept','--event',e,'--op','shared-op'); send('prepared','--event',e,'--op','shared-op')
reject(['bash',L,'claim','--project',P,'--task',T,'--','shared-op'])
dispatch=f'dispatch: 2026-01-01T00:00:00Z op_id=shared-op worker=pi agent=fixture pane=test:op-worker dir={P}'
reject(['bash',L,'dispatch','--project',P,'--task',T,'--','shared-op','test:op-worker',dispatch])
assert 'shared-op' not in read()['ops'] and next(h for h in pending() if h['event_id']==e)['prepared']==1
new_ticket('op-claim-first')
ledger('claim','--','shared-op')
e=send('send','--corr','action','--attempt','1','--text','原claim后不能复用op')
send('received','--event',e)
reject(['bash',S,'accept','--project',P,'--task',T,'--event',e,'--op','shared-op'])
ledger('dispatch','--','shared-op','test:op-worker',dispatch)
assert read()['ops']['shared-op']['status']=='dispatch' and next(h for h in pending() if h['event_id']==e)['op_id']==''
print('PASS P2-2 op双向互斥，拒绝不改原claim/dispatch/prepared归属')

# 首轮P2-3：source:保留给自动来源；拒绝发生在写入边界，不留合法请求互相毒化的状态。
for source_first in [False,True]:
    new_ticket('corr-source-first' if source_first else 'corr-send-first')
    if source_first:
        ledger('append','--event-id','future','--','done: legitimate completion')
        assert any(h['source_event']=='future' for h in pending())
    reject(['bash',S,'send','--project',P,'--task',T,'--corr','source:future','--attempt','1','--text','done: legitimate completion'])
    if not source_first: ledger('append','--event-id','future','--','done: legitimate completion')
    # 普通用户corr允许正文提到保留名字，不会被当作自动来源控制。
    user=send('send','--corr','user:source:future','--attempt','1','--text','source:future只是正文')
    p=pending(); assert any(h['source_event']=='future' for h in p) and any(h['event_id']==user for h in p)
    rev=read()['rev']; assert pending()==p and read()['rev']==rev
out=call(['bash',ROOT+'/bin/qwb-wake.sh','--project',P,'--block','--max-ms','1'],rc=2)
assert 'corr-send-first' in out and 'corr-source-first' in out, '保留corr边界拖住其他票交接'
print('PASS P2-3 corr保留边界双顺序拒绝，真实来源/普通用户corr与其他票继续交接')
PY
