#!/usr/bin/env bash
# Pi档位与项目家族声明；公开安装/派发入口，系统边界仅用失效关闭的假Herdr。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="$QWB_TEST_SCOPE_DIR" GIT_CEILING_DIRECTORIES="$QWB_TEST_SCOPE_DIR"
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
export QWB_PROFILE_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 -B - <<'PY'
from process_fixture import TemporaryDirectory
import io, json, os, shutil, subprocess, tarfile
from pathlib import Path

root=Path(os.environ['QWB_PROFILE_ROOT'])
with TemporaryDirectory(prefix='pi-profile-') as tmp:
    tmp=Path(tmp).resolve(); os.environ['TMPDIR']=str(tmp)
    stub=tmp/'stub';stub.mkdir();log=tmp/'calls.jsonl'
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
a=sys.argv[1:]
with open(os.environ['PROFILE_LOG'],'a') as f:f.write(json.dumps(a)+'\\n')
if a[:2]==['workspace','list']:r={'workspaces':[]}
elif a[:2]==['agent','get']:
 if a[2]!='test:p7': print(json.dumps({'error':{'code':'agent_not_found'}}),file=sys.stderr);sys.exit(1)
 r={'type':'agent_info','agent':{'pane_id':a[2],'agent_status':'working','state_change_seq':185}}
elif a[:2]==['tab','create']:r={'root_pane':{'pane_id':'test:p7','tab_id':'test:t7'}}
elif a[:2]==['pane','get']:r={'pane':{'pane_id':a[2],'agent_status':'working'}}
else:r={'type':'ok'}
print(json.dumps({'result':r}))
''');(stub/'herdr').chmod(0o755)
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'PROFILE_LOG':str(log),'HERDR_PANE_ID':'test:ctl','HERDR_WORKSPACE_ID':'test'}
    env.pop('TYPESAFE_API_KEY',None)
    def run(argv,ok=True):
        r=subprocess.run(list(map(str,argv)),env=env,capture_output=True,text=True)
        assert (r.returncode==0)==ok,(argv,r.returncode,r.stdout,r.stderr)
        return r
    def lib(fn,*args,ok=True):
        return run(['/bin/bash','-c','. "$1"; shift; "$@"','test',root/'bin/qwb-lib.sh',fn,*args],ok)
    pins=['--approve','--provider','magpie','--model','codex/gpt-6.1-sol','--thinking','high']
    for purpose in ('role','gate'):
        assert json.loads(lib('qwb_pi_profile',purpose,'herdr','pi',*pins).stdout)==dict(provider='magpie',model='codex/gpt-6.1-sol',effort='high')
        for flag in ('--provider','--model','--thinking'):
            i=pins.index(flag)
            for argv in (pins[:i]+pins[i+2:],pins+[flag,pins[i+1]],pins[:i+1]+['']+pins[i+2:],pins[:i+1],pins+[flag+'='+pins[i+1]]):
                lib('qwb_pi_profile',purpose,'herdr','pi',*argv,ok=False)
        for mode,harness,argv in [('pane-run','pi',pins),('herdr','claude',pins),('herdr','pi',pins+['--fast']),('herdr','pi',pins+['--service-tier=priority'])]:
            lib('qwb_pi_profile',purpose,mode,harness,*argv,ok=False)
    lib('qwb_pi_profile','role','herdr','pi',*pins,'--session','foreign',ok=False)
    assert not log.exists()
    print('PASS Bash3.2共享解析：含斜杠model保真，三项缺失/重复/空值/末尾缺值/混合等号与adapter/fast/角色覆盖均拒绝')

    p=tmp/'project';p.mkdir()
    run(['/bin/bash',root/'bin/qwb-init.sh',p])
    config=p/'qwbuddy/config.sh';workers=p/'qwbuddy/workers.sh'
    assert sum(line.startswith('qwb_worker pi-sol-high ') for line in workers.read_text().splitlines())==1
    config.write_text(config.read_text()+"\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    assert 'LINT PASS' in run(['/bin/bash',p/'qwbuddy/bin/qwb-lint.sh','--project',p]).stdout
    registry=run(['/bin/bash','-c','. "$1"; . "$2"; qwb_load_workers "$3"; printf "%s\\n" "${QWB_CONFIG_NAMES[@]}"','test',p/'qwbuddy/bin/qwb-lib.sh',config,p]).stdout.splitlines()
    assert 'pi-sol-high' in registry and len(registry)==7 and not any('/' in w for w in registry),registry
    task=p/'tasks/2099-profile.md'
    body='# profile\nstate: blocked\nimplementation-authorized: explicit fixture scope approval\ndispatch-budget: 20\n\n## 1. 验收场景\n### user_正常\nGiven 工人配置\nWhen 派发\nThen 参数保真\n### user_失败\nGiven 未知\nWhen 核对\nThen 拒绝\n'
    task.write_text(body);log.write_text('')
    run(['/bin/bash',p/'qwbuddy/bin/qwb-run.sh','--project',p,'--task',task,'--worker','pi-sol-high','--here'])
    starts=[json.loads(line) for line in log.read_text().splitlines() if json.loads(line)[:2]==['agent','start']]
    assert len(starts)==1 and starts[0][starts[0].index('--')+1:]==pins,starts
    assert 'worker=pi-sol-high' in task.read_text()
    # off模式仍执行真实registry与default候选核对，零网络/Herdr。
    (p/'qwbuddy/dispatch-rules.json').write_text(json.dumps({'agents':{'implement':['pi-sol-high']},'rules':[],'default':{'worker':'implement'}}))
    before=log.read_bytes()
    dispatch=json.loads(run(['/bin/bash',p/'qwbuddy/bin/qwb-dispatch.sh',task,'--project',p,'--json']).stdout)
    assert dispatch['default_worker']=='pi-sol-high' and log.read_bytes()==before,dispatch
    print('PASS 新装sol唯一声明/QWB_WORKERS、真实run逐项argv、lint与dispatch候选清单均通过且家族不充当工人')
    for key,wanted in [('magpie/codex/gpt-6.1-sol','gpt'),('magpie/codex/gpt-6-astra','gpt'),('anthropic/claude-opus-5-5','claude'),('anthropic/claude-fable-5-1','claude')]:
        assert lib('qwb_model_family',p,key).stdout.strip()==wanted
    assert sum(line.startswith('qwb_family ') for line in workers.read_text().splitlines())==4
    # 旧多渠道quota/family兼容夹具自行声明，不依赖新模板带GLM或其他工具。
    config.write_text(config.read_text()+"\nQWB_WORKERS=\"$QWB_WORKERS pi-glm-high\"\n")
    workers.write_text(workers.read_text()+'qwb_worker pi-glm-high herdr pi -- --approve --provider zai-coding-cn --model glm-5.3 --thinking high\n'
                       'qwb_family zai-coding-cn/glm-5.3 glm\n'
                       'qwb_family anthropic/claude-fable-5 claude\n'
                       'qwb_family openai-codex/gpt-6-sol gpt\n'
                       'qwb_family google-antigravity/gemini-3.1-pro gemini\n'
                       'qwb_family devin/swe-2-high swe\n'
                       'qwb_family openai-codex/gpt-6.1-sol gpt\n'
                       'qwb_family openai-codex/gpt-6-astra gpt\n'
                       'qwb_family anthropic/claude-opus-4-6 claude\n')
    # 真dispatch额度核对：两种显式渠道都不能从model首段/默认账户取宽松余量。
    quota=tmp/'quota.json';quota_calls=tmp/'quota-curl-calls'
    (stub/'quota-axi').write_text("#!/usr/bin/env python3\nimport os\nfrom pathlib import Path\nprint(Path(os.environ['PROFILE_QUOTA']).read_text())\n")
    (stub/'curl').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
Path(os.environ['PROFILE_CURL_CALLS']).write_text('called')
Path(sys.argv[sys.argv.index('-o')+1]).write_text(json.dumps({'model':'fixture','answers':{'rule':{'choice':'default','confidence':1,'probabilities':{'default':1}}}}))
print('200',end='')
''')
    for name in ('quota-axi','curl'):(stub/name).chmod(0o755)
    env.update(PROFILE_QUOTA=str(quota),PROFILE_CURL_CALLS=str(quota_calls),QUOTA_AXI_SNAPSHOT=str(quota),TYPESAFE_API_KEY='fixture-only')
    quota.write_text(json.dumps({'schemaVersion':6,'providers':[{'provider':'pi','accountKey':lane,'windows':[{'kind':'weekly','percentRemaining':left}]} for lane,left in [('magpie',0),('codex',80),('zai-coding-cn',80),('default',80)]]}))
    rules=p/'qwbuddy/dispatch-rules.json'
    rules.write_text(json.dumps({'agents':{'implement':['pi-sol-high','pi-glm-high']},'rules':[],'default':{'worker':'implement'}}))
    result=json.loads(run(['/bin/bash',p/'qwbuddy/bin/qwb-dispatch.sh',task,'--project',p,'--json']).stdout)
    assert result['worker']==result['default_worker']=='pi-glm-high' and quota_calls.exists(),result
    quota_calls.unlink()
    q=json.loads(quota.read_text());q['providers'][2]['windows'][0]['percentRemaining']=0;quota.write_text(json.dumps(q))
    rules.write_text(json.dumps({'agents':{'implement':['pi-glm-high']},'rules':[],'default':{'worker':'implement'}}))
    refused=run(['/bin/bash',p/'qwbuddy/bin/qwb-dispatch.sh',task,'--project',p,'--json'],ok=False)
    assert 'quota weekly 0%' in refused.stderr and not quota_calls.exists(),refused.stderr
    env.pop('TYPESAFE_API_KEY')
    print('PASS 显式provider额度lane：Sol按magpie拒绝不用codex余量，GLM按zai-coding-cn拒绝不用default余量；HTTP只用本地curl桩')

    original=workers.read_bytes()
    for key,wanted in [('magpie/codex/gpt-6.1-sol','gpt'),('zai-coding-cn/glm-5.3','glm'),('anthropic/claude-fable-5','claude'),('openai-codex/gpt-6-sol','gpt'),('google-antigravity/gemini-3.1-pro','gemini'),('devin/swe-2-high','swe'),('openai-codex/gpt-6.1-sol','gpt'),('openai-codex/gpt-6-astra','gpt'),('anthropic/claude-opus-4-6','claude')]:
        assert lib('qwb_model_family',p,key).stdout.strip()==wanted
    key='magpie/'+'codex/'+'gpt-6.1-sol'
    for extra in ['', 'qwb_family '+key+' gpt\nqwb_family '+key+' gpt\n','qwb_family '+key+' pi\n','qwb_family '+key+' unknown\n','qwb_family '+key+' bogus\n','qwb_family '+key+' gpt extra\n']:
        workers.write_bytes(b''.join(line for line in original.splitlines(keepends=True) if not line.startswith(b'qwb_family '))+extra.encode())
        assert lib('qwb_model_family',p,key).stdout.strip()=='unknown',extra
        run(['/bin/bash','-c','. "$1"; . "$2"; qwb_load_workers "$3"','test',root/'bin/qwb-lib.sh',config,p])
    workers.write_bytes(original)
    print('PASS 模板四个模型与显式旧兼容家族来自完整键声明；缺失/重复/非法/多参数均unknown，普通加载不拒绝')

    # 真起点安装再升级；只读git archive获取旧安装器依赖，所有文件仍在本scope。
    baseline=tmp/'baseline';baseline.mkdir()
    archive=subprocess.check_output(['git','-C',str(root),'archive','bea487d','bin','templates'])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tar:
        for member in tar.getmembers():
            assert (member.name in ('bin','templates') or member.name.startswith(('bin/','templates/'))) and '..' not in Path(member.name).parts and not member.issym() and not member.islnk()
        tar.extractall(baseline,filter='data')
    old=tmp/'old-project';old.mkdir()
    run(['/bin/bash',baseline/'bin/qwb-init.sh',old])
    old_config=old/'qwbuddy/config.sh';old_workers=old/'qwbuddy/workers.sh'
    old_config.write_text(old_config.read_text()+"\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    frozen=(old_config.read_bytes(),old_workers.read_bytes())
    run(['/bin/bash',root/'bin/qwb-init.sh',old])
    assert frozen==(old_config.read_bytes(),old_workers.read_bytes())
    old_task=old/'tasks/2099-old.md';old_task.write_text(body);log.write_text('')
    run(['/bin/bash',old/'qwbuddy/bin/qwb-run.sh','--project',old,'--task',old_task,'--worker','pi','--here'])
    assert any(json.loads(line)[:2]==['agent','start'] for line in log.read_text().splitlines())
    assert lib('qwb_model_family',old,'openai-codex/gpt-6.1-sol').stdout.strip()=='unknown'
    run(['/bin/bash',root/'bin/qwb-init.sh','--migrate-worker-config',old])
    assert frozen==(old_config.read_bytes(),old_workers.read_bytes())
    print('PASS 起点安装后重装与迁移幂等：workers/config逐字节保留；普通派发成功，旧配置家族unknown')
PY
