#!/usr/bin/env bash
# 公开 CLI：--block 多轮等待只交最终摘要；人读模式仍显示逐票跳过。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
PROJECT="$(mktemp -d "$TMPDIR/tmp.XXXXXXXX")" || exit 1
export TMPDIR="$PROJECT"
trap 'qwb_test_drain && rm -rf "$PROJECT" || exit 1' EXIT
bash "$ROOT/bin/qwb-init.sh" "$PROJECT" >/dev/null
if [[ -n "${QWB_TEST_WAKE_SOURCE:-}" ]]; then cp "$QWB_TEST_WAKE_SOURCE" "$PROJECT/qwbuddy/bin/qwb-wake.sh"; fi
printf 'QWB_WAKE_INTERVAL_MS=50\nQWB_REWAKE_MS=60000\n' >> "$PROJECT/qwbuddy/config.sh"
TICKET="$PROJECT/tasks/2099-01-01-output.md"
FP="$(printf 'running\n' | shasum | cut -d' ' -f1)"
printf '# output\nstate: running\nwake: %s state=running fp=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$FP" > "$TICKET"

once="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --once)"
[[ "$once" == *"跳过：2099-01-01-output.md"* ]] || { echo "FAIL --once 跳过日志变化" >&2; exit 1; }
dry="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --dry-run)"
[[ "$dry" == *"跳过：2099-01-01-output.md"* ]] || { echo "FAIL --dry-run 跳过日志变化" >&2; exit 1; }

# 业务间隔取一个50ms分片；假sleep推进同一假钟，读账耗时和fallback notice不消耗测试预算。
cat > "$PROJECT/now-hook.sh" <<'EOF'
#!/usr/bin/env bash
cat "$QWB_TEST_NOW"
EOF
cat > "$PROJECT/sleep-hook.sh" <<'EOF'
#!/usr/bin/env bash
now="$(cat "$QWB_TEST_NOW")"
now=$((now + $1))
printf '%s\n' "$now" > "$QWB_TEST_NOW"
printf '%s\n' "$1" >> "$QWB_TEST_SLICES"
n="$(cat "$QWB_TEST_COUNTER")"
n=$((n + 1))
printf '%s\n' "$n" > "$QWB_TEST_COUNTER"
if [[ "$n" -eq 2 ]]; then printf 'done: 多轮等待后完成\n' >> "$QWB_TEST_TICKET"; fi
EOF
chmod +x "$PROJECT/now-hook.sh" "$PROJECT/sleep-hook.sh"
start_ms=$(( $(date +%s) * 1000 ))
printf '%s\n' "$start_ms" > "$PROJECT/now-ms"
printf '0\n' > "$PROJECT/round-count"
: > "$PROJECT/slices"
set +e
out="$(env -u HERDR_PANE_ID QWB_NOW_MS_CMD="$PROJECT/now-hook.sh" QWB_SLEEP_CMD="$PROJECT/sleep-hook.sh" \
  QWB_TEST_NOW="$PROJECT/now-ms" QWB_TEST_SLICES="$PROJECT/slices" \
  QWB_TEST_COUNTER="$PROJECT/round-count" QWB_TEST_TICKET="$TICKET" \
  bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --block --max-ms 5000)"
rc=$?
set -e
[[ "$rc" -eq 2 && "$(cat "$PROJECT/round-count")" -eq 2 \
  && "$(cat "$PROJECT/now-ms")" -eq $((start_ms + 100)) \
  && "$(cat "$PROJECT/slices")" == $'50\n50' \
  && "$out" == *"看账本：1 张未结项有进展"* \
  && "$out" == *"done: 多轮等待后完成"* \
  && "$out" != *"跳过："* ]] \
  || { printf 'FAIL --block rc=%s rounds=%s slices=%s stdout=%s\n' "$rc" "$(cat "$PROJECT/round-count")" "$(cat "$PROJECT/slices")" "$out" >&2; exit 1; }

printf '# output\nstate: running\n' > "$TICKET"
set +e
out="$(env -u HERDR_PANE_ID bash "$PROJECT/qwbuddy/bin/qwb-wake.sh" --project "$PROJECT" --block --max-ms 5000)"
rc=$?
set -e
[[ "$rc" -eq 2 && "$out" == *"最近: 尚无状态行"* ]] \
  || { printf 'FAIL 空状态行 rc=%s stdout=%s\n' "$rc" "$out" >&2; exit 1; }

echo "WAKE BLOCK OUTPUT PASS: multi-round summary only; once/dry-run unchanged; empty status explicit"

# 收紧叫醒的七个场景；复用本文件已接入的进程与失效关闭夹具。
python3 -B - "$PROJECT" "${QWB_TEST_WAKE_BASELINE:-}" <<'PY'
import hashlib, json, os, re, subprocess, sys, time
from pathlib import Path
p=Path(sys.argv[1]); baseline=Path(sys.argv[2]) if sys.argv[2] else None
wake=p/'qwbuddy/bin/qwb-wake.sh'; current=wake.read_bytes()
ticket=p/'tasks/2099-01-01-output.md'
clock=p/'regression-clock'; calls=p/'regression-calls'; stub=p/'regression-bin'; stub.mkdir()
lock=p/'qwbuddy/.controller.lock'; lock.mkdir(); (lock/'owner').write_text('fixture ctl\n')
(stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['REG_CALLS'],'a') as f: f.write(json.dumps(a)+'\\n')
if a[:2]==['pane','get']:
    if os.environ.get('REG_LOST')=='1':
        print('{"error":{"code":"pane_not_found"}}');sys.exit(1)
    print(json.dumps({'result':{'pane':{'pane_id':a[2],'agent':'pi'}}}))
elif a[:2]==['pane','run']: print('{"result":{"type":"ok"}}')
else: sys.exit(1)
''')
(stub/'lsof').write_text('#!/usr/bin/env bash\nexit 1\n')
now=p/'regression-now.sh'; sleep=p/'regression-sleep.sh'
now.write_text('#!/usr/bin/env bash\ncat "$REG_CLOCK"\n')
sleep.write_text('#!/usr/bin/env bash\nn=$(cat "$REG_CLOCK"); printf "%s\\n" "$((n + $1))" > "$REG_CLOCK"\n')
for f in [stub/'herdr',stub/'lsof',now,sleep]: f.chmod(0o755)
env={**os.environ,'HERDR_PANE_ID':'ctl','PATH':str(stub)+':'+os.environ['PATH'],
     'REG_CALLS':str(calls),'REG_CLOCK':str(clock),'QWB_NOW_MS_CMD':str(now),'QWB_SLEEP_CMD':str(sleep)}
env.pop('QWB_TEST_TICKET',None)
conf=p/'qwbuddy/config.sh'; start=int(time.time())*1000
calls.write_bytes(b'')
def config(value=1800000):
    conf.write_text('QWB_WAKE_INTERVAL_MS=50\n'+('' if value is None else f'QWB_REWAKE_MS={value}\n'))
def reset(last='working: 正在推进',fp_last='working: 先前进度',stamp='2000-01-01T00:00:00Z',state='running'):
    config(); clock.write_text(str(start)); calls.write_bytes(b'')
    fp=hashlib.sha1((state+'\n'+fp_last).encode()).hexdigest()
    ticket.write_text(f'state: {state}\ndispatch: fixture pane=worker dir={p}\n{last}\n'
                      +(f'wake: {stamp} state={state} fp={fp}\n' if stamp is not None else ''))
def append(line):
    with ticket.open('a') as f: f.write(line+'\n')
def run(*args,rc=0,extra=None):
    r=subprocess.run(['bash',str(wake),'--project',str(p),*args],env=env|(extra or {}),capture_output=True,timeout=30)
    print('COMMAND '+json.dumps(list(args),ensure_ascii=False)+' RC='+str(r.returncode),flush=True)
    print('STDOUT '+repr(r.stdout)+'\nSTDERR '+repr(r.stderr),flush=True)
    assert r.returncode==rc,(args,r.returncode,r.stdout,r.stderr)
    return r
def count(): return len(re.findall(rb'^wake:',ticket.read_bytes(),re.M))
def delivered(): return [json.loads(x) for x in calls.read_text().splitlines() if json.loads(x)[:2]==['pane','run']]
def timeout():
    r=run('--block','--max-ms','100',rc=124)
    assert not r.stdout and b'--block' in r.stderr,(r.stdout,r.stderr)
    return r
# 返修1: 首次进度尚无 wake 行，mtime 新鲜；所有入口都不叫、不写行。
reset(stamp=None); before=ticket.read_bytes()
r=run('--once','--pane','ctl'); assert '进度行不叫醒'.encode() in r.stdout
assert '进度行不叫醒'.encode() in run('--dry-run').stdout
timeout(); assert count()==0 and ticket.read_bytes()==before and not delivered()
print('PASS repair_无wake新鲜进度不叫醒: once/dry-run/block; zero delivery/write')
# 返修2: 尚无 wake 行但 mtime 已超期，兜底只叫一次。
reset(stamp=None); subprocess.run(['touch','-t','200001010000',str(ticket)],check=True)
run('--once','--pane','ctl'); assert count()==1 and len(delivered())==1
before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before and len(delivered())==1
print('PASS repair_无wake超期进度兜底一次: old mtime; first wake then dedup')
# 返修3: 确实存在 wake 行但时间戳非法（含空值），mtime 新鲜仍立即叫。
for stamp in ['GARBAGE','']:
    reset(stamp=stamp); run('--once','--pane','ctl'); assert count()==2 and len(delivered())==1
    before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before
print('PASS repair_已有wake非法时间仍超期: invalid/empty timestamp; immediate wake then dedup')
# 1: 连续三次进度；once、dry-run、block 均保留原票字节和投递数。
reset(stamp=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(start//1000)))
for n in range(3):
    append(f'working: 第{n+1}阶段'); before=ticket.read_bytes()
    r=run('--once','--pane','ctl'); assert '工人在推进，进度行不叫醒'.encode() in r.stdout
    assert '进度行不叫醒'.encode() in run('--dry-run').stdout
    timeout(); assert ticket.read_bytes()==before and not delivered()
print('PASS user_正常路径_进度行不叫醒: three progress writes; once/dry-run/block; zero delivery/write')
# 2: 结果或阻塞立即交回；紧接再次等待不重复消费。
for kind in ['done','blocked','needs-decision']:
    reset(); append(kind+': 需要主控处理')
    r=run('--block','--max-ms','100',rc=2)
    assert (kind+': 需要主控处理').encode() in r.stdout and count()==2
    before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before and not delivered()
print('PASS user_正常路径_做完或卡住立刻叫醒: done/blocked/needs-decision each exit 2 then 124')
# 3: 两个时钟都过期叫一次；写 wake 后立刻再次调用不叫；再次拨旧才重叫。
reset(); subprocess.run(['touch','-t','200001010000',str(ticket)],check=True)
run('--once','--pane','ctl'); assert count()==2 and len(delivered())==1
before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before
raw=ticket.read_text(); ticket.write_text(re.sub(r'^wake: \S+', 'wake: 2000-01-01T00:00:00Z',raw,flags=re.M))
subprocess.run(['touch','-t','200001010000',str(ticket)],check=True)
run('--block','--max-ms','100',rc=2); assert count()==3
print('PASS user_失败路径_工人挂起由兜底叫醒一次: old mtime+wake; dedup; repeat only after both clocks expire')
# 4: 新心跳推迟旧 wake；相同指纹分支同样使用较晚时钟；新 wake 也盖过旧 mtime。
for fp_last in ['working: 先前进度','working: 正在推进']:
    reset(fp_last=fp_last); before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before
reset(stamp=time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime(start//1000)))
subprocess.run(['touch','-t','200001010000',str(ticket)],check=True)
before=ticket.read_bytes(); timeout(); assert ticket.read_bytes()==before
# 解析失败仍按超期，文件刚写也不能掩盖。
reset(stamp='GARBAGE'); run('--block','--max-ms','100',rc=2); assert count()==2
print('PASS user_失败路径_心跳在则不兜底: changed/unchanged fp and newer wake; invalid wake timestamp stays overdue')
# 5: 丢失段优先；新 working 也立刻叫，回读摘要与指纹去重。
reset(); r=run('--block','--max-ms','100',rc=2,extra={'REG_LOST':'1'})
assert '工人丢失'.encode() in r.stdout and count()==2
before=ticket.read_bytes(); r=run('--block','--max-ms','100',rc=124,extra={'REG_LOST':'1'})
assert ticket.read_bytes()==before
print('PASS user_失败路径_工人丢失照旧立刻叫醒: working+lost exit 2, unchanged lost deduplicates')
# 6: 关闭、未设和 quiet；旧时钟加新进度仍不叫，done 均立刻叫。
for value in [0,None,'quiet']:
    reset(); config(1800000 if value=='quiet' else value)
    if value=='quiet':
        r=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','enter','--project',str(p),'--','quiet','fixture-auth','静音','不增加授权'],env=env,capture_output=True,timeout=30)
        assert r.returncode==0,(r.stdout,r.stderr)
    append('working: 关闭兜底仍推进'); subprocess.run(['touch','-t','200001010000',str(ticket)],check=True)
    before=ticket.read_bytes(); r=run('--once','--pane','ctl'); assert '进度行不叫醒'.encode() in r.stdout
    timeout(); assert ticket.read_bytes()==before and not delivered()
    append('done: 关闭兜底仍须验收'); run('--block','--max-ms','100',rc=2); assert count()==2
    if value=='quiet':
        r=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','exit','--project',str(p),'--','explicit','结束静音测试'],env=env,capture_output=True,timeout=30)
        assert r.returncode==0,(r.stdout,r.stderr)
print('PASS user_失败路径_兜底关闭与静默模式: zero/unset/quiet suppress progress, done remains immediate')
# 7: 同一安装路径依次跑固定旧脚本和当前脚本，保留原始字节，只归一 wake 时间戳。
if baseline:
    def normalized(raw):
        if b'<!-- qwb-collab-v1\n' in raw:
            # 本场景比较公开 wake 行；协作区内部 event_id/时钟由 writer 每次独立生成。
            raw=b'\n'.join(line for line in raw.splitlines() if line.startswith(b'wake:'))
        return re.sub(rb'(?m)^wake: \S+',b'wake: TIME',raw)
    samples=[('new',b'state: running\n'),
             ('blocked',b'state: blocked\nworking: waiting\n'),
             ('decision',b'state: needs-decision\nworking: waiting\n'),
             ('invalid',b'state: ILLEGAL\nworking: waiting\n'),
             ('utf8',b'state: running\nworking: bad\xff\n'),
             ('lost',b'state: running\ndispatch: fixture pane=worker\nworking: progressing\n')]
    for name,raw in samples:
        config(0); results=[]
        for source in [baseline.read_bytes(),current]:
            wake.write_bytes(source); ticket.write_bytes(raw); clock.write_text(str(start)); calls.write_bytes(b'')
            r=run('--once','--pane','ctl',extra={'REG_LOST':'1'} if name=='lost' else None)
            results.append((r.stdout,r.stderr,r.returncode,normalized(ticket.read_bytes()),calls.read_bytes()))
        assert results[0]==results[1],(name,results)
        print('BYTE_COMPARE '+name+' stdout/stderr/rc/wake/calls identical')
    # 已迁协作票：公开迁移、真实 working/done handoff 均由固定旧脚本与新脚本分别读写。
    ticket.write_text('state: running\n'); proof=p/'migration-regression.json'
    proof.write_text(json.dumps({'task_sha256':hashlib.sha256(ticket.read_bytes()).hexdigest(),
       'confirm':{k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    def ledger(*args):
        r=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-ledger.sh'),args[0],'--project',str(p),'--task',str(ticket),*args[1:]],env=env,capture_output=True,timeout=30)
        assert r.returncode==0,(args,r.stdout,r.stderr)
    ledger('migrate','--',str(proof))
    ledger('append','--event-id','progress','--','working: 已迁票保留持久交接')
    ledger('append','--event-id','completion','--','done: 已迁票完整成果')
    raw=ticket.read_bytes(); results=[]
    for source in [baseline.read_bytes(),current]:
        wake.write_bytes(source); ticket.write_bytes(raw); clock.write_text(str(start)); calls.write_bytes(b'')
        r=run('--block','--max-ms','100',rc=2)
        results.append((r.stdout,r.stderr,r.returncode,normalized(ticket.read_bytes()),calls.read_bytes()))
    assert results[0]==results[1],('collab',results)
    assert b'progress' in results[1][0] and b'completion' in results[1][0]
    # 已迁票 dry-run 仍沿基线判定，末行 working 不适用本票新规则。
    ledger('append','--event-id','tail-progress','--','working: 成果后仍有进展')
    raw=ticket.read_bytes(); dry_results=[]
    for source in [baseline.read_bytes(),current]:
        wake.write_bytes(source); ticket.write_bytes(raw); calls.write_bytes(b'')
        r=run('--dry-run'); dry_results.append((r.stdout,r.stderr,r.returncode,ticket.read_bytes(),calls.read_bytes()))
    assert dry_results[0]==dry_results[1], 'collab dry-run changed'
    wake.write_bytes(current)
    print('PASS user_正常路径_其余情况逐字节不变: new/blocked/needs-decision/invalid/UTF8/collab stdout/stderr/rc/wake/calls')
else:
    print('SKIP fixed-baseline byte comparison; set QWB_TEST_WAKE_BASELINE for acceptance')
PY
