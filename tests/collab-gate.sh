#!/usr/bin/env bash
# 真入口+临时Git；仅Herdr/ps/lsof系统边界替身，不调用现场端点。
set -euo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
QWB_GATE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_GATE_TEST_ROOT
python3 -u -B - <<'PY'
from process_fixture import TemporaryDirectory
import hashlib, json, os, shutil, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_GATE_TEST_ROOT'])
with TemporaryDirectory(prefix='qwb-gate-') as tmp:
    os.environ["TMPDIR"] = tmp
    tmp=Path(tmp).resolve(); p=tmp/'project'; p.mkdir(); stub=tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for n in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/n,p/'qwbuddy'/n)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer astra unknown-reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\nqwb_worker astra herdr pi -- --provider openai-codex --model gpt-6-astra --thinking low\nqwb_worker unknown-reviewer herdr pi -- --provider anthropic --model claude-unconfirmed --thinking low\n')
    (p/'safety.sh').write_text('#!/bin/sh\n# fixture defect: unresolved request wrongly accepted\nexit 0\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\ntasks/\n')
    def git(*args): return subprocess.check_output(['git','-C',str(p),*args],text=True).strip()
    git('init','-q'); git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    # 仅本测试私有Git的候选，不是共享lane/池；TemporaryDirectory随测试回收。
    ca=tmp/'candidate-A'; cb=tmp/'candidate-B'; cc=tmp/'candidate-C'; cl=tmp/'candidate-long-A'; cd=tmp/'candidate-changing'; cr=tmp/'candidate-replay'
    for candidate in [ca,cb,cc,cl,cd,cr]: git('worktree','add','-q','--detach',str(candidate))
    state=tmp/'native.json'
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'ps').write_text('''#!/bin/sh
for last do :; done
[ "${last:-}" != 'ppid=' ] || exec /bin/ps "$@"
printf '%s\\n' 'Thu Oct 1 00:00:00 2099'
''')
    (stub/'herdr').write_text(r'''#!/usr/bin/env perl
use strict;
use warnings;
use utf8;
use Encode qw(decode);
use JSON::PP;
binmode STDOUT, ':encoding(UTF-8)';
my @a = map { decode('UTF-8', $_) } @ARGV;
my $json = JSON::PP->new->ascii;
my $file = $ENV{GATE_NATIVE_STATE};
my $s = {};
if (-e $file) { open my $input, '<', $file or die $!; local $/; $s = $json->decode(<$input>); }
open my $log, '>>', $ENV{GATE_NATIVE_LOG} or die $!;
print $log $json->encode(\@a), "\n";
close $log;
my $project = decode('UTF-8', $ENV{GATE_PROJECT});
my $pid = 0 + $ENV{GATE_NATIVE_PID};
my $verb = @a >= 2 ? join(' ', @a[0,1]) : '';
sub out { print $json->encode({result => $_[0]}), "\n"; }
sub after { my ($key) = @_; for (my $i=0; $i<@a; $i++) { return $a[$i+1] if $a[$i] eq $key; } die "missing $key"; }
if ($verb eq 'workspace list') {
    my @spaces = ({workspace_id=>'ws',worktree=>{repo_root=>$project,is_linked_worktree=>JSON::PP::false}});
    my $candidates = $json->decode($ENV{GATE_CANDIDATES});
    for (my $i=0; $i<@$candidates; $i++) { push @spaces, {workspace_id=>'ws'.$i,worktree=>{repo_root=>$project,is_linked_worktree=>JSON::PP::true,checkout_path=>$candidates->[$i]}}; }
    out({workspaces=>\@spaces});
} elsif ($verb eq 'tab create') {
    my $label=after('--label');my $gate=$label eq '门禁';$s->{tabs}=($s->{tabs}//0)+1;my $slug=$label.'-'.$s->{tabs};
    out({root_pane=>{pane_id=>$gate?'gate-pane':'worker-'.$slug,tab_id=>$gate?'gate-tab':'tab-'.$slug,terminal_id=>'gate-terminal'}});
} elsif ($verb eq 'agent get') {
    print $json->encode({error=>{code=>'agent_not_found'}}),"\n";exit 1;
} elsif ($verb eq 'agent prompt') {
    out({type=>'prompt_sent'});
} elsif ($verb eq 'agent start') {
    if (grep { $_ eq '--session-id' } @a) { my $sid=after('--session-id');$s={session=>after('--session-dir').'/2099_'.$sid.'.jsonl',sid=>$sid}; }
    out({type=>'agent_started'});
} elsif ($verb eq 'pane get') {
    my $gate=$a[2] eq 'gate-pane';my $d={pane_id=>$a[2],workspace_id=>'ws',terminal_id=>$gate?'gate-terminal':'ctl-terminal',foreground_cwd=>$project};
    if (!$gate || exists $s->{session}) { $d->{agent}='pi';$d->{agent_status}='idle';$d->{agent_session}={agent=>'pi',source=>'herdr:pi',kind=>'path',value=>$gate?$s->{session}:'ctl-session'}; }
    out({pane=>$d});
} elsif ($verb eq 'pane process-info') {
    my $live=$a[-1] ne 'gate-pane' || exists $s->{session};my $id=$live?$pid:42;
    out({process_info=>{pane_id=>$a[-1],shell_pid=>42,foreground_process_group_id=>$id,foreground_processes=>[{pid=>$id,argv0=>$live?'pi':'zsh',argv=>['pi'],cwd=>$project}]}});
} elsif ($verb eq 'pane read') {
    print "(openai-codex) gpt-6.1-sol • high\n";exit 0;
} elsif ($verb eq 'pane run' || $verb eq 'tab close') {
    out({type=>'input_sent'});
} else { exit 9; }
open my $output, '>', $file or die $!;
print $output $json->encode($s);
close $output;
''')
    for f in stub.iterdir(): f.chmod(0o755)
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','GATE_PROJECT':str(p),'GATE_NATIVE_PID':str(os.getpid()),'GATE_NATIVE_STATE':str(state),'GATE_NATIVE_LOG':str(tmp/'native-calls.jsonl'),'GATE_CANDIDATES':json.dumps(list(map(str,[ca,cb,cc])))}
    def call(script,verb,*args,actor='ctl',ok=True,extra=None):
        argv=['bash',str(ROOT/'bin'/script)]
        argv += ['--project',str(p),verb,*map(str,args)] if script=='qwb-run.sh' else [verb,'--project',str(p),*map(str,args)]
        r=subprocess.run(argv,env=env|{'HERDR_PANE_ID':actor}|(extra or {}),capture_output=True,text=True)
        assert (r.returncode==0)==ok,(script,verb,r.returncode,r.stdout,r.stderr)
        return r
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',p)
    t=p/'tasks/A.md'; t.write_text('# A\nstate: running\n## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure\n')
    m=tmp/'migration.json';m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',t,'--',m)
    frozen='## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure'
    call('qwb-ledger.sh','prepare','--task',t,'--',hashlib.sha1(frozen.encode()).hexdigest())
    call('qwb-ledger.sh','claim','--task',t,'--','impl-A')
    call('qwb-ledger.sh','dispatch','--task',t,'--','impl-A','worker-A',f'dispatch: 2099 op_id=impl-A worker=sol agent=impl-A pane=worker-A dir={ca}')
    call('qwb-ledger.sh','release','--task',t,'--','impl-A')
    call('qwb-ledger.sh','append','--task',t,'--','done: 候选A交回',actor='worker-A')
    call('qwb-send.sh','send','--task',t,'--corr','result-A','--attempt','1','--text','done: 候选A交回',actor='worker-A')
    bt=p/'tasks/B.md';bt.write_text('# B\nstate: running\n## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(bt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',bt,'--',m)
    call('qwb-ledger.sh','prepare','--task',bt,'--',hashlib.sha1(frozen.encode()).hexdigest())
    call('qwb-ledger.sh','claim','--task',bt,'--','impl-B')
    call('qwb-ledger.sh','dispatch','--task',bt,'--','impl-B','worker-B',f'dispatch: 2099 op_id=impl-B worker=sol agent=impl-B pane=worker-B dir={cb}')
    call('qwb-ledger.sh','release','--task',bt,'--','impl-B')
    call('qwb-ledger.sh','append','--task',bt,'--','done: 候选B交回',actor='worker-B')
    call('qwb-send.sh','send','--task',bt,'--corr','result-B','--attempt','1','--text','done: 候选B交回',actor='worker-B')
    # 第一纵向切片：主控授权已登记门禁，claim真实绑定且跨调用保留。
    request=tmp/'assignment.json'; environment=tmp/'environment'; environment.write_text('fixture dependency v1\n')
    request.write_text(json.dumps({'candidate':str(ca),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}))
    call('qwb-ledger.sh','gate-assign','--task',t,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',t,'--','accept-A',actor='gate-pane')
    brequest=json.loads(request.read_text());brequest['candidate']=str(cb);request.write_text(json.dumps(brequest))
    call('qwb-ledger.sh','gate-assign','--task',bt,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',bt,'--','accept-B',actor='gate-pane')
    # 现有03唯一监督直接给被claim门禁一条A/B摘要，不先唤主控逐票转发。
    (tmp/'native-calls.jsonl').write_text('')
    call('qwb-wake.sh','--once','--pane','ctl')
    calls=[json.loads(line) for line in (tmp/'native-calls.jsonl').read_text().splitlines()]
    delivery=[a for a in calls if a[:2]==['pane','run']]
    assert len(delivery)==1 and delivery[0][2]=='gate-pane' and 'A(running)' in delivery[0][3] and 'B(running)' in delivery[0][3], delivery
    print('PASS 现有唯一监督一批A/B成果直接门铃门禁，不自动received/handled')
    (tmp/'native-calls.jsonl').write_text('')
    routed=call('qwb-wake.sh','--block','--max-ms','1',ok=False,extra={'QWB_REWAKE_MS':'1'})
    calls=[json.loads(line) for line in (tmp/'native-calls.jsonl').read_text().splitlines()]
    delivery=[a for a in calls if a[:2]==['pane','run']]
    assert routed.returncode==124 and len(delivery)==1 and delivery[0][2]=='gate-pane', (routed.returncode,delivery,routed.stderr)
    print('PASS Pi宿主block同样路由门禁，不以rc2逐轮唤主控；唯一监督与有界重投不变')
    if os.environ.get('QWB_GATE_ROUTES_ONLY')=='1':
        print('PASS 仅04/06直接门铃接缝窄验；未执行后段candidate/full fixture检查')
        raise SystemExit(0)
    batch=[]
    for ticket in [t,bt]:batch+=json.loads(call('qwb-send.sh','pending','--task',ticket,actor='gate-pane').stdout)
    assert any(h['payload']=='done: 候选A交回' for h in batch) and any(h['payload']=='done: 候选B交回' for h in batch)
    print('PASS 03批量持久交接直接读回A/B成果，未逐轮转主控')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['claim']=={'owner':'gate-pane','op_id':'accept-A'}
    before=t.read_bytes()
    call('qwb-ledger.sh','claim','--task',t,'--','second',ok=False)
    call('qwb-ledger.sh','answer','--task',t,'--','budget','yes',actor='gate-pane',ok=False)
    assert t.read_bytes()==before
    print('PASS 单票角色授权、持久claim和越权拒绝')
    # 第二切片：真实qwb-test成功只产收据，不能自动accepted；旧对象/dirty拒绝复用。
    report=tmp/'A-full.json'
    r=call('qwb-test.sh','full','--project',ca,'--task',t,'--ledger-project',p,'--op','accept-A','--report',report,actor='gate-pane')
    receipt=json.loads(report.read_text()); assert receipt['rc']==0 and receipt['before']['head']==git('rev-parse','HEAD')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='pending' and d['phase']=='running' and len(d['gate']['receipts'])==1
    (ca/'dirty.txt').write_text('uncommitted\n')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    (ca/'dirty.txt').unlink()
    changed=dict(receipt); changed['before']=dict(receipt['before'],head='0'*40)
    old=tmp/'old.json';old.write_text(json.dumps(changed))
    call('qwb-ledger.sh','gate-receipt','--task',t,'--','accept-A',old,actor='gate-pane',ok=False)
    print('PASS candidate-bound收据，rc0不等于accepted，dirty/旧head拒绝')
    # 第三切片：独立会话证据、原finding保留、偏好不阻断、未决不放行。
    def session(name,model,sid=None,provider=None,effort=None):
        sid=sid or name
        provider=provider or ('openai-codex' if model.startswith('gpt-') else 'anthropic')
        effort=effort or ('high' if model=='gpt-6.1-sol' else 'low')
        f=tmp/(name+'.jsonl'); f.write_text(json.dumps({'type':'session','id':sid,'cwd':str(p)})+'\n'+json.dumps({'type':'model_change','provider':provider,'modelId':model})+'\n'+json.dumps({'type':'thinking_level_change','thinkingLevel':effort})+'\n')
        return {'model':model,'family':'gpt' if model.startswith('gpt-') else 'claude','session':sid,'evidence':str(f)}
    impl=session('implementation','gpt-6.1-sol'); reviewer=session('review','claude-opus-4-6')
    reviewfile=tmp/'review.json'
    review={'context':receipt['after'],'implementer':impl,'reviewer':reviewer,'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[{'id':'F1','original':'真实安全缺陷：允许未决放行','classification':'unresolved','root':'safety','evidence':'反例已复现'}]}
    # 本轮例外复用真实question/answer/resume；仅stub系统边界，不能冒充原生现场。
    et=p/'tasks/Scoped-review.md';et.write_text('# 本轮审核授权\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(et.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',et,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cc),workers={'review':'astra','rework':'sol'})))
    call('qwb-ledger.sh','gate-assign','--task',et,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',et,'--','accept-scoped',actor='gate-pane')
    ctx=json.loads(call('qwb-ledger.sh','gate-context','--task',et,'--','accept-scoped',actor='gate-pane').stdout)
    scoped={'context':ctx,'implementer':impl,'reviewer':session('scoped-astra','gpt-6-astra'),'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[]}
    scopedfile=tmp/'scoped-review.json';scopedfile.write_text(json.dumps(scoped))
    assert not any(line.startswith('qwb_family ') for line in (p/'qwbuddy/workers.sh').read_text().splitlines())
    call('qwb-ledger.sh','gate-review','--task',et,'--','accept-scoped',scopedfile,actor='gate-pane')
    print('PASS Sol/Astra同家族不同模型，无qwb_family声明且无authorization，公开gate-review接受')
    if os.environ.get('QWB_GATE_MODEL_RULE_ONLY')=='1':
        raise SystemExit(0)
    grant={'schema':'qwb-sol-astra-review-v1','context':ctx,'implementer_session':impl['session'],'reviewer_session':scoped['reviewer']['session'],'owner_fp':hashlib.sha256((p/'qwbuddy/.controller.lock/owner').read_bytes()).hexdigest(),'approval':'fixture user explicitly approved only this object and independent Sol/Astra sessions'}
    call('qwb-ledger.sh','question','--task',et,'--','scoped-review','本对象Sol/Astra独立会话同family审核是否获批？')
    call('qwb-ledger.sh','answer','--task',et,'--','scoped-review',json.dumps(grant))
    call('qwb-ledger.sh','resume','--task',et,'--','scoped-review','恢复此对象审核；不授予land')
    scoped['authorization']='scoped-review';scopedfile.write_text(json.dumps(scoped))
    call('qwb-ledger.sh','gate-review','--task',et,'--','accept-scoped',scopedfile,actor='gate-pane')
    stored=json.loads(call('qwb-ledger.sh','read','--task',et).stdout)
    assert stored['gate']['reviews'][-1]['review']['authorization']=='scoped-review'
    assert stored['gate']['reviews'][-1]['review']['reviewer']['family']=='gpt' and stored['gate']['verdict']=='pending'
    print('PASS 可选精确Sol/Astra批准合法时仍核验并保留授权引用；非自动accepted')
    def denied_review(r,reason):
        snapshot=et.read_bytes();scopedfile.write_text(json.dumps(r))
        result=call('qwb-ledger.sh','gate-review','--task',et,'--','accept-scoped',scopedfile,actor='gate-pane',ok=False)
        assert reason in result.stderr and et.read_bytes()==snapshot,result.stderr
    denied_review(dict(scoped,authorization='absent'), '审核无本票用户授权')
    noauth=dict(scoped);noauth.pop('authorization')
    scopedfile.write_text(json.dumps(noauth))
    call('qwb-ledger.sh','gate-review','--task',et,'--','accept-scoped',scopedfile,actor='gate-pane')
    denied_review(dict(scoped,authorization='bad/key'),'审核授权key非法')
    call('qwb-ledger.sh','question','--task',et,'--','not-resumed','待批准本对象')
    denied_review(dict(scoped,authorization='not-resumed'),'审核批准尚未答复/恢复')
    call('qwb-ledger.sh','answer','--task',et,'--','not-resumed',json.dumps(grant))
    denied_review(dict(scoped,authorization='not-resumed'),'审核批准尚未答复/恢复')
    call('qwb-ledger.sh','resume','--task',et,'--','not-resumed','测试后恢复问题；不授予land')
    for key,changed in [
        ('wrong-object',dict(grant,context=dict(ctx,head='0'*40,tree='0'*40))),
        ('wrong-task',dict(grant,context=dict(ctx,task=str(bt)))),
        ('wrong-attempt',dict(grant,context=dict(ctx,attempt='other-round'))),
        ('wrong-controller',dict(grant,owner_fp='0'*64)),
    ]:
        call('qwb-ledger.sh','question','--task',et,'--',key,'fixture mismatch must fail')
        call('qwb-ledger.sh','answer','--task',et,'--',key,json.dumps(changed))
        call('qwb-ledger.sh','resume','--task',et,'--',key,'恢复问题不代表匹配审核')
        denied_review(dict(scoped,authorization=key),'审核批准范围/对象/身份不匹配')
    denied_review(dict(scoped,reviewer=session('different-astra','gpt-6-astra')),'审核批准范围/对象/身份不匹配')
    denied_review(dict(scoped,implementer=session('different-sol','gpt-6.1-sol')),'审核批准范围/对象/身份不匹配')
    denied_review(dict(scoped,reviewer=session('same-native','gpt-6-astra',sid=impl['session'])),'同原生会话审核冲突')
    denied_review(dict(scoped,reviewer=session('gate-native','gpt-6-astra',sid=stored['gate']['identity']['session_id'])),'同原生会话审核冲突')
    for family in [None,'unknown','arbitrary']:
        ids={kind:dict(noauth[kind]) for kind in ['implementer','reviewer']}
        for identity in ids.values():
            if family is None:identity.pop('family')
            else:identity['family']=family
        scopedfile.write_text(json.dumps(dict(noauth,**ids)))
        call('qwb-ledger.sh','gate-review','--task',et,'--','accept-scoped',scopedfile,actor='gate-pane')
    print('PASS family缺失/unknown/任意附记均不影响真实模型与会话核验')
    denied_review(dict(noauth,reviewer=dict(scoped['reviewer'],model='gpt-6.1-sol')),'审核/实现型号不是主控准确授权配置')
    for field,value in [('modelId','gpt-6.1-sol'),('provider','anthropic'),('thinkingLevel','high'),('id','wrong-native'),('cwd',str(tmp/'foreign'))]:
        bad=session('mismatched-'+field,'gpt-6-astra')
        evidence=Path(bad['evidence']);records=[json.loads(line) for line in evidence.read_text().splitlines()]
        record=records[1] if field in ['modelId','provider'] else records[2] if field=='thinkingLevel' else records[0]
        record[field]=value;evidence.write_text(''.join(json.dumps(row)+'\n' for row in records))
        denied_review(dict(noauth,reviewer=bad),'会话目录不是候选/本项目' if field=='cwd' else '原生session/model证据不匹配（当前仅Pi JSONL）')
    denied_review(dict(noauth,reviewer=dict(scoped['reviewer'],session='unknown')),'审核身份unknown/字段不全')
    denied_review(dict(noauth,reviewer=dict(scoped['reviewer'],evidence=str(tmp/'missing.jsonl'))),'No such file or directory')
    for field in ['model','session','evidence']:
        bad=dict(scoped['reviewer']);bad.pop(field)
        denied_review(dict(noauth,reviewer=bad),'schema缺键 '+field)
    call('qwb-ledger.sh','answer','--task',et,'--','absent','yes',actor='gate-pane',ok=False)
    call('qwb-ledger.sh','gate-verdict','--task',et,'--','accept-scoped','accepted',actor='gate-pane',ok=False)
    print('PASS 可选批准非法/范围错/会话错拒绝；型号配置、原生model/provider/effort/session/cwd及缺证据守卫零写入；无质量收据仍拒绝accepted')
    # 同一型号不同档位/渠道/大小写，即使有完整批准也零写入拒绝。
    model_workers=p/'qwbuddy/workers.sh';saved_models=model_workers.read_bytes()
    for label,imodel,iprovider,rmodel,rprovider in [
        ('Exact','gpt-6-astra','openai-codex','gpt-6-astra','openai-codex'),
        ('Channel','codex/gpt-6-astra','magpie','gpt-6-astra','openai-codex'),
        ('Case','GPT-6-ASTRA','openai-codex','gpt-6-astra','openai-codex'),
    ]:
        changed=saved_models.decode().replace('--provider openai-codex --model gpt-6.1-sol',f'--provider {iprovider} --model {imodel}')
        model_workers.write_text(changed.replace('--provider openai-codex --model gpt-6-astra --thinking low',f'--provider {rprovider} --model {rmodel} --thinking low'))
        same_task=p/('tasks/Same-model-'+label+'.md');same_task.write_text('# 同模型审核\nstate: running\n'+frozen+'\n')
        m.write_text(json.dumps({'task_sha256':hashlib.sha256(same_task.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        call('qwb-ledger.sh','migrate','--task',same_task,'--',m)
        request.write_text(json.dumps(dict(brequest,candidate=str(cc),workers={'review':'astra','rework':'sol'})))
        call('qwb-ledger.sh','gate-assign','--task',same_task,'--','gate',request)
        call('qwb-ledger.sh','claim','--task',same_task,'--','same-model',actor='gate-pane')
        context=json.loads(call('qwb-ledger.sh','gate-context','--task',same_task,'--','same-model',actor='gate-pane').stdout)
        proposal=dict(noauth,context=context,implementer=session('same-impl-'+label,imodel,provider=iprovider,effort='high'),reviewer=session('same-review-'+label,rmodel,provider=rprovider,effort='low'))
        approval=dict(grant,context=context,implementer_session=proposal['implementer']['session'],reviewer_session=proposal['reviewer']['session'])
        call('qwb-ledger.sh','question','--task',same_task,'--','same-approval','同模型不可被批准放行')
        call('qwb-ledger.sh','answer','--task',same_task,'--','same-approval',json.dumps(approval))
        call('qwb-ledger.sh','resume','--task',same_task,'--','same-approval','仅测试批准不能豁免同模型')
        for authorization in [None,'same-approval']:
            attempt=dict(proposal)
            if authorization:attempt['authorization']=authorization
            scopedfile.write_text(json.dumps(attempt));before=same_task.read_bytes()
            result=call('qwb-ledger.sh','gate-review','--task',same_task,'--','same-model',scopedfile,actor='gate-pane',ok=False)
            assert '同模型审核冲突' in result.stderr and same_task.read_bytes()==before,result.stderr
        model_workers.write_bytes(saved_models)
    print('PASS Astra high/low同模型：相同型号、不同渠道、大小写三组，无批准/完整批准均同模型冲突且零写入')
    if os.environ.get('QWB_GATE_REVIEW_AUTH_ONLY')=='1':
        print('PASS 仅授权公开入口窄验；不是现场模型/E2E/full')
        raise SystemExit(0)
    assert subprocess.run(['bash',str(ca/'safety.sh'),'unresolved']).returncode==0, 'A真实fixture缺陷未复现（预期拒绝7，实际接受0）'
    reviewfile.write_text(json.dumps(review))
    call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    review['findings'][0]['classification']='must-fix';reviewfile.write_text(json.dumps(review))
    call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='rework' and d['gate']['findings']['F1']['original']=='真实安全缺陷：允许未决放行'
    assert d['claim']['owner']=='gate-pane'
    # A原票公开run返修，验收claim不释放、不换规格；B独立accepted。
    call('qwb-run.sh','--task',t,'--worker','sol','--worktree',ca,'--gate-op','accept-A','--gate-kind','rework','--name','rework-a',actor='gate-pane')
    dispatched=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert dispatched['claim']['op_id']=='accept-A'
    child=next(iter(dispatched['gate']['dispatches'])); pane=dispatched['ops'][child]['pane']
    assert f'working: worker-activity op={child} pane={pane} evidence=' in t.read_text()
    before=t.read_bytes()
    for line in ['working: arbitrary gate append',
                 f'working: worker-activity op=impl-A pane=worker-A evidence={{}}',
                 f'working: worker-activity op={child} pane=foreign-pane evidence={{}}']:
        refused=call('qwb-ledger.sh','append','--task',t,'--',line,actor='gate-pane',ok=False)
        assert '门禁仅可写本人已派child活动绑定' in refused.stderr and t.read_bytes()==before,refused.stderr
    print('PASS 门禁run先持久记录本人child活动；任意append/他人op/错pane零写入拒绝')
    br=tmp/'B-full.json';call('qwb-test.sh','full','--project',cb,'--task',bt,'--ledger-project',p,'--op','accept-B','--report',br,actor='gate-pane')
    call('qwb-run.sh','--task',bt,'--worker','reviewer','--worktree',cb,'--gate-op','accept-B','--gate-kind','review','--name','review-b',actor='gate-pane')
    breview=tmp/'B-review.json';breview.write_text(json.dumps(dict(review,context=json.loads(br.read_text())['after'],findings=[])))
    call('qwb-ledger.sh','gate-review','--task',bt,'--','accept-B',breview,actor='gate-pane')
    bstate=json.loads(call('qwb-ledger.sh','read','--task',bt).stdout);bchild=next(iter(bstate['gate']['dispatches']))
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False)
    call('qwb-ledger.sh','append','--task',bt,'--','done: Standards+Spec独立审核完成；真实JSONL fixture已交回',actor=bstate['ops'][bchild]['pane'])
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane')
    assert json.loads(call('qwb-ledger.sh','read','--task',t).stdout)['gate']['verdict']=='rework'
    assert json.loads(call('qwb-ledger.sh','read','--task',bt).stdout)['gate']['verdict']=='accepted'
    print('PASS 两票不同结论：A公开run原范围返修，B accepted，未自动verified/合并')
    # F1单条件红测：配置/对象不变，真实0→真实7→原成功重放，不能洗掉失败。
    failure_marker=tmp/'replay-fail'
    with (cr/'qwbuddy/config.sh').open('a') as f:f.write(f"QWB_GATE_FULL='test ! -e {failure_marker} || exit 7'\n")
    subprocess.run(['git','-C',str(cr),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cr),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','replay command fixture'],check=True)
    rt=p/'tasks/Replay.md';rt.write_text('# 收据重放\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(rt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',rt,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cr))))
    call('qwb-ledger.sh','gate-assign','--task',rt,'--','gate',request);call('qwb-ledger.sh','claim','--task',rt,'--','accept-R',actor='gate-pane')
    def replay_test(name,ok=True):
        f=tmp/name
        result=call('qwb-test.sh','full','--project',cr,'--task',rt,'--ledger-project',p,'--op','accept-R','--report',f,actor='gate-pane',ok=ok)
        return f,result
    def import_replay(f):return call('qwb-ledger.sh','gate-receipt','--task',rt,'--','accept-R',f,actor='gate-pane')
    def replay_verdict(ok=True):return call('qwb-ledger.sh','gate-verdict','--task',rt,'--','accept-R','accepted',actor='gate-pane',ok=ok)
    first,_=replay_test('Replay-original-success.json')
    replay_review=tmp/'Replay-review.json';replay_review.write_text(json.dumps(dict(review,context=json.loads(first.read_text())['after'],findings=[])))
    call('qwb-ledger.sh','gate-review','--task',rt,'--','accept-R',replay_review,actor='gate-pane');replay_verdict()
    failure_marker.touch();failed_report,failed_result=replay_test('Replay-newer-failure.json',ok=False)
    assert failed_result.returncode==7
    replay_verdict(ok=False)
    import_replay(first)
    replay_verdict(ok=False)
    assert [r['receipt']['rc'] for r in json.loads(call('qwb-ledger.sh','read','--task',rt).stdout)['gate']['receipts']]==[0,7]
    # 等待严格跨秒边界，不用导入顺序或同秒并列推断执行先后。
    while int(time.time())<=json.loads(failed_report.read_text())['ended_at']:time.sleep(0.05)
    failure_marker.unlink();fresh,_=replay_test('Replay-fresh-success.json');replay_verdict()
    snapshot=rt.read_bytes();import_replay(first);import_replay(failed_report);import_replay(fresh)
    # 另一报告路径、JSON排版不同仍是同一执行；幂等不能重置verdict/rev/事件。
    duplicate=tmp/'Replay-duplicate-format.json';duplicate.write_text(json.dumps(json.loads(first.read_text()),indent=2))
    import_replay(duplicate);assert rt.read_bytes()==snapshot
    # 协议乱序/模糊时间夹具只改变真实收据时间，不冒充额外真实执行。
    later=json.loads(fresh.read_text());earlier=json.loads(failed_report.read_text())
    older=tmp/'Replay-older-failure.json';earlier.update(started_at=later['started_at']-2,ended_at=later['started_at']-2,elapsed_seconds=0);older.write_text(json.dumps(earlier))
    import_replay(older);replay_verdict() # 较晚成功仍可用，不能按数组尾失败判定。
    tied=tmp/'Replay-ambiguous-failure.json';earlier.update(started_at=later['started_at'],ended_at=later['ended_at'],elapsed_seconds=later['elapsed_seconds']);tied.write_text(json.dumps(earlier))
    import_replay(tied);replay_verdict(ok=False);import_replay(fresh);replay_verdict(ok=False)
    malformed=tmp/'Replay-invalid-time.json';invalid=dict(later,started_at=later['ended_at']+1);malformed.write_text(json.dumps(invalid))
    call('qwb-ledger.sh','gate-receipt','--task',rt,'--','accept-R',malformed,actor='gate-pane',ok=False)
    while int(time.time())<=later['ended_at']:time.sleep(0.05)
    replay_test('Replay-after-ambiguity-success.json');replay_verdict()
    history=json.loads(call('qwb-ledger.sh','read','--task',rt).stdout)['gate']['receipts']
    assert [r['receipt']['rc'] for r in history]==[0,7,0,7,7,0]
    print('PASS F1真实0→7→旧0仍拒绝；重复执行幂等、乱序保历史、同秒不猜先后、明确新成功恢复')
    # 原票工人修复真实缺陷，新attempt重验；旧必须修复意见保留在原版本历史。
    ca.joinpath('safety.sh').write_text('#!/bin/sh\n[ "${1:-}" != unresolved ] || exit 7\nexit 0\n')
    subprocess.run(['git','-C',str(ca),'add','safety.sh'],check=True)
    subprocess.run(['git','-C',str(ca),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','fix original-scope defect'],check=True)
    astate=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    child=next(iter(astate['gate']['dispatches']))
    call('qwb-ledger.sh','append','--task',t,'--','done: 原范围安全缺陷已修复，unresolved返回7',actor=astate['ops'][child]['pane'])
    call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A','2',ca,git('rev-parse','HEAD'),actor='gate-pane')
    assert subprocess.run(['bash',str(ca/'safety.sh'),'unresolved']).returncode==7
    repaired=tmp/'A-repaired.json';call('qwb-test.sh','full','--project',ca,'--task',t,'--ledger-project',p,'--op','accept-A','--report',repaired,actor='gate-pane')
    review['context']=json.loads(repaired.read_text())['after']
    # 对当前已修候选的意见不再成立；原must-fix仍绑定原head，不洗历史。
    review['findings'][0].update(classification='not-founded',evidence='修复复核：当前safety.sh unresolved实际返回7；原缺陷在旧head成立，历史保留')
    review['findings'].append({'id':'P1','original':'命名偏好','classification':'suggestion','root':'style','evidence':'未违反契约'})
    reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    review['covered']=[];reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    review['covered']=['user_good','user_failure'];reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='accepted' and d['phase']=='running' and len(d['gate']['receipts'])==2
    assert len(d['gate']['findings']['F1']['history'])==5
    print('PASS 独立审核、原意见分类闭环、缺场景拒绝、偏好不阻断且复用同对象收据')
    # 第四切片：独立op里的长门不持writer锁；B复用，C新成果可处理。
    # 并行场景独立fixture：Long-A仍有同一真实缺陷，不修改已accepted的A/B候选。
    t=p/'tasks/Long-A.md';t.write_text('# Long A\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',t,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cl))))
    call('qwb-ledger.sh','gate-assign','--task',t,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',t,'--','accept-A',actor='gate-pane')
    call('qwb-send.sh','send','--task',t,'--corr','result-A','--attempt','1','--text','done: Long-A候选有真实安全缺陷')
    longseed=tmp/'Long-A-seed.json';call('qwb-test.sh','full','--project',cl,'--task',t,'--ledger-project',p,'--op','accept-A','--report',longseed,actor='gate-pane')
    review['context']=json.loads(longseed.read_text())['after']
    review['findings'][0].update(classification='must-fix',evidence='公开safety.sh unresolved返回0，预期拒绝7')
    assert subprocess.run(['bash',str(cl/'safety.sh'),'unresolved']).returncode==0
    reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
    ca=cl
    started=tmp/'long-started';finish=tmp/'long-finish'; cfg=ca/'qwbuddy/config.sh'
    with cfg.open('a') as f:f.write(f"QWB_GATE_FULL='touch {started}; while [ ! -e {finish} ]; do sleep 0.1; done'\n")
    subprocess.run(['git','-C',str(ca),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(ca),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','original-scope rework'],check=True)
    call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A','2',ca,git('rev-parse','HEAD'),actor='gate-pane')
    diff=json.loads(call('qwb-ledger.sh','gate-diff','--task',t,'--','accept-A','','qwbuddy/config.sh',actor='gate-pane').stdout)
    assert diff['reviewed_head']==receipt['after']['head'] and 'long-started' in diff['reviewed_diff'] and 'qwbuddy/config.sh' in diff['contexts']
    call('qwb-ledger.sh','gate-receipt','--task',t,'--','accept-A',report,actor='gate-pane',ok=False)
    # 03处理阶段确认+prepared/activity保留，在长门执行前占不同的持久op。
    h=next(h for h in json.loads(call('qwb-send.sh','pending','--task',t,actor='gate-pane').stdout) if h['corr']=='result-A')
    for verb,args in [('received',[]),('accept',['--op','long-A']),('prepared',['--op','long-A']),('activity',['--wait-ms','180000','--reason','等待候选外long-finish'])]:
        call('qwb-send.sh',verb,'--task',t,'--event',h['event_id'],*args,actor='gate-pane')
    longreport=tmp/'A-long.json'
    wait_start=time.monotonic()
    process=subprocess.Popen(['bash',str(ROOT/'bin/qwb-test.sh'),'full','--project',str(ca),'--ledger-project',str(p),'--task',str(t),'--op','accept-A','--report',str(longreport)],env=env|{'HERDR_PANE_ID':'gate-pane'},stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+30
        while not started.exists():
            assert process.poll() is None,'长门提前失败'
            assert time.monotonic()<deadline,'长门未启动';time.sleep(.05)
        # B同对象/条件可信full直接复用，A仍真正在等。
        call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane')
        assert process.poll() is None
        ct=p/'tasks/C.md';ct.write_text('# C\nstate: running\n'+frozen+'\n')
        m.write_text(json.dumps({'task_sha256':hashlib.sha256(ct.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        call('qwb-ledger.sh','migrate','--task',ct,'--',m)
        crequest=dict(brequest,candidate=str(cc));request.write_text(json.dumps(crequest))
        call('qwb-ledger.sh','gate-assign','--task',ct,'--','gate',request)
        call('qwb-ledger.sh','claim','--task',ct,'--','accept-C',actor='gate-pane')
        ce=call('qwb-send.sh','send','--task',ct,'--corr','result-C','--attempt','1','--text','done: C的新结果').stdout.strip()
        call('qwb-send.sh','received','--task',ct,'--event',ce,actor='gate-pane')
        call('qwb-send.sh','accept','--task',ct,'--event',ce,'--op','handle-C',actor='gate-pane')
        call('qwb-send.sh','prepared','--task',ct,'--event',ce,'--op','handle-C',actor='gate-pane')
        proof=p/'tasks/C-result.json';proof.write_text(json.dumps({'event_id':ce,'op_id':'handle-C','outcome':'applied','evidence':'C真实公开读回；A长门仍运行'}))
        call('qwb-send.sh','handled','--task',ct,'--event',ce,'--op','handle-C','--result-ref',proof,actor='gate-pane')
        assert process.poll() is None
        bd=json.loads(call('qwb-ledger.sh','read','--task',bt).stdout)
        assert len(bd['gate']['receipts'])==1 and bd['gate']['verdict']=='accepted'
        print(f'PASS A持久prepared/wait长门中B复用C handled；处理耗时={time.monotonic()-wait_start:.2f}s tokens=unknown')
    finally:
        finish.touch();out,err=process.communicate(timeout=30)
    assert process.returncode==0,(out,err)
    ad=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert ad['gate']['binding']['attempt']=='2' and ad['gate']['receipts'][0]['receipt']['before']['attempt']=='1' and ad['gate']['verdict']=='pending'
    assert ad['gate']['receipts'][-1]['receipt']['elapsed_seconds']>0
    # 三轮必须实际新attempt+独立复核，不把重复同轮调用计成三轮。
    for attempt in ['2','3']:
        if attempt=='3':call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A',attempt,ca,git('rev-parse','HEAD'),actor='gate-pane')
        review['context']=json.loads(call('qwb-ledger.sh','gate-context','--task',t,'--','accept-A',actor='gate-pane').stdout)
        reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
        call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
        if attempt=='2':
            snapshot=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
            call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
            assert json.loads(call('qwb-ledger.sh','read','--task',t).stdout)['rev']==snapshot['rev']
    ad=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert ad['gate']['verdict']=='rediagnose' and len(ad['gate']['rounds'])==3 and not ad['questions']
    call('qwb-ledger.sh','gate-dispatch','--task',t,'--','accept-A','bad-rework','rework','sol',actor='gate-pane',ok=False)
    print('PASS 三轮同根因无新证据转主控技术重诊，不默认询问用户、不清旧意见')
    # family为附记；真实身份未知及越权仍必须代码拒绝。
    unknown=dict(review,context=json.loads(br.read_text())['after'],findings=[],reviewer=dict(reviewer,session='unknown'))
    reviewfile.write_text(json.dumps(unknown));call('qwb-ledger.sh','gate-review','--task',bt,'--','accept-B',reviewfile,actor='gate-pane',ok=False)
    et=p/'tasks/Same-family.md';et.write_text('# 同family不同模型\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(et.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',et,'--',m)
    erequest=dict(brequest,candidate=str(cc),workers={'review':'astra','rework':'sol'});request.write_text(json.dumps(erequest))
    call('qwb-ledger.sh','gate-assign','--task',et,'--','gate',request);call('qwb-ledger.sh','claim','--task',et,'--','accept-E',actor='gate-pane')
    same=dict(unknown,context=json.loads(call('qwb-ledger.sh','gate-context','--task',et,'--','accept-E',actor='gate-pane').stdout),reviewer=session('same-family','gpt-6-astra'))
    reviewfile.write_text(json.dumps(same));call('qwb-ledger.sh','gate-review','--task',et,'--','accept-E',reviewfile,actor='gate-pane')
    print('PASS Sol high/Astra low不同模型独立session均GPT；无批准接受')
    ut=p/'tasks/Unknown-native-model.md';ut.write_text('# 未知真实型号不猜family\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(ut.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ut,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cc),workers={'review':'unknown-reviewer','rework':'sol'})))
    call('qwb-ledger.sh','gate-assign','--task',ut,'--','gate',request);call('qwb-ledger.sh','claim','--task',ut,'--','accept-U',actor='gate-pane')
    unverified=dict(unknown,context=json.loads(call('qwb-ledger.sh','gate-context','--task',ut,'--','accept-U',actor='gate-pane').stdout),reviewer=session('unconfirmed-native','claude-unconfirmed'))
    reviewfile.write_text(json.dumps(unverified));call('qwb-ledger.sh','gate-review','--task',ut,'--','accept-U',reviewfile,actor='gate-pane')
    print('PASS 原生未知家族型号按准确授权profile与JSONL接受，不猜family')
    # 每种声明在授权前冻结；拒绝不改票，新增型号只改项目配置。
    family_workers=p/'qwbuddy/workers.sh';saved_workers=family_workers.read_bytes()
    for label,extra in [
        ('Missing',''),
        ('Duplicate','qwb_family anthropic/claude-unconfirmed claude\nqwb_family anthropic/claude-unconfirmed claude\n'),
        ('Invalid','qwb_family anthropic/claude-unconfirmed imaginary\n'),
        ('Configured','qwb_family anthropic/claude-unconfirmed claude\n'),
    ]:
        changed=saved_workers.decode().replace('--provider openai-codex --model gpt-6.1-sol','--provider magpie --model codex/gpt-6.1-sol')
        family_workers.write_text(changed+'qwb_family magpie/codex/gpt-6.1-sol gpt\n'+extra)
        ft=p/('tasks/Family-'+label+'.md');ft.write_text('# 项目家族声明\nstate: running\n'+frozen+'\n')
        m.write_text(json.dumps({'task_sha256':hashlib.sha256(ft.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        call('qwb-ledger.sh','migrate','--task',ft,'--',m)
        request.write_text(json.dumps(dict(brequest,candidate=str(cc),workers={'review':'unknown-reviewer','rework':'sol'})))
        call('qwb-ledger.sh','gate-assign','--task',ft,'--','gate',request)
        call('qwb-ledger.sh','claim','--task',ft,'--','family-'+label,actor='gate-pane')
        context=json.loads(call('qwb-ledger.sh','gate-context','--task',ft,'--','family-'+label,actor='gate-pane').stdout)
        assert context['worker_profiles']['rework']==dict(provider='magpie',model='codex/gpt-6.1-sol',effort='high')
        evidence=tmp/('family-'+label+'.jsonl')
        evidence.write_text(json.dumps({'type':'session','id':'family-'+label,'cwd':str(p)})+'\n'+json.dumps({'type':'model_change','provider':'magpie','modelId':'codex/gpt-6.1-sol'})+'\n'+json.dumps({'type':'thinking_level_change','thinkingLevel':'high'})+'\n')
        proposal=dict(unverified,context=context,implementer=dict(model='codex/gpt-6.1-sol',family='gpt',session='family-'+label,evidence=str(evidence)))
        reviewfile.write_text(json.dumps(proposal));before=ft.read_bytes()
        call('qwb-ledger.sh','gate-review','--task',ft,'--','family-'+label,reviewfile,actor='gate-pane')
        stored=json.loads(call('qwb-ledger.sh','read','--task',ft).stdout)
        assert stored['gate']['binding']['workers_sha256']==hashlib.sha256(family_workers.read_bytes()).hexdigest()
        assert stored['gate']['reviews'][-1]['review']['implementer']['family']=='gpt'
        # 附记声明仍属于冻结配置，改声明后必须重新授权。
        family_workers.write_text(family_workers.read_text().replace('qwb_family magpie/codex/gpt-6.1-sol gpt','qwb_family magpie/codex/gpt-6.1-sol claude'))
        frozen_ticket=ft.read_bytes()
        refused=call('qwb-ledger.sh','gate-review','--task',ft,'--','family-'+label,reviewfile,actor='gate-pane',ok=False)
        assert '工人型号/effort配置已变' in refused.stderr and ft.read_bytes()==frozen_ticket,refused.stderr
        family_workers.write_bytes(saved_workers)
    print('PASS 含斜杠型号与缺失/重复/非法family声明均不影响审核；修改workers字节仍使冻结授权失效')
    call('qwb-ledger.sh','revise-scenarios','--task',bt,'--expect',str(bd['rev']),'--',frozen,'新产品',actor='gate-pane',ok=False)
    call('qwb-run.sh','--task',bt,'--worker','sol','--worktree',cb,actor='gate-pane',ok=False)
    call('qwb-run.sh','--task',bt,'--worker','sol','--worktree',cb,'--gate-op','accept-B','--gate-kind','review','--revise-scenarios=新产品',actor='gate-pane',ok=False)
    oldenv=environment.read_bytes();environment.write_text('fixture dependency v2\n')
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False)
    environment.write_bytes(oldenv)
    print('PASS 越权/真实身份unknown拒绝，依赖环境变化不能复用旧收据')
    # 原始post-run对象必须留证：命令rc0期间产生新commit不能采信运行前HEAD。
    changing=cd/'qwbuddy/config.sh'
    with changing.open('a') as f:f.write("QWB_GATE_FULL='printf fixed >> safety.sh; git add safety.sh; git -c user.name=Test -c user.email=test@invalid commit -qm during-test'\n")
    subprocess.run(['git','-C',str(cd),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cd),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','changing command fixture'],check=True)
    dt=p/'tasks/Changing.md';dt.write_text('# 运行后变化\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(dt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',dt,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cd))))
    call('qwb-ledger.sh','gate-assign','--task',dt,'--','gate',request);call('qwb-ledger.sh','claim','--task',dt,'--','accept-D',actor='gate-pane')
    call('qwb-test.sh','full','--project',cd,'--task',dt,'--ledger-project',p,'--op','accept-D','--report',cd/'in-candidate.json',actor='gate-pane',ok=False)
    changingreport=tmp/'Changing.json';result=call('qwb-test.sh','full','--project',cd,'--task',dt,'--ledger-project',p,'--op','accept-D','--report',changingreport,actor='gate-pane',ok=False)
    observed=json.loads(changingreport.read_text())
    assert result.returncode==3 and observed['rc']==0 and observed['before']['head']!=observed['after']['head'] and observed['before']['tree']!=observed['after']['tree']
    assert not json.loads(call('qwb-ledger.sh','read','--task',dt).stdout)['gate']['receipts']
    # 当前spec改变，即便HEAD/门成功不变也不能ready；恢复临时票原字节。
    before=bt.read_bytes();bt.write_bytes(before.replace(b'## ',b'changed original spec\n## ',1))
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False);bt.write_bytes(before)
    print('PASS 候选外报告、原spec变化、运行前后真实commit/tree差异拒绝；rc0原始证据仍保留')
    # 门失败后元信息失败，仍透传真实7，不能被set -e改成1或写可信收据。
    with changing.open('a') as f:f.write("QWB_GATE_FULL='exit 7'\n")
    subprocess.run(['git','-C',str(cd),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cd),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','failed gate metadata fixture'],check=True)
    ft=p/'tasks/Metadata.md';ft.write_text('# 元信息失败\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(ft.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ft,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cd))))
    call('qwb-ledger.sh','gate-assign','--task',ft,'--','gate',request);call('qwb-ledger.sh','claim','--task',ft,'--','accept-F',actor='gate-pane')
    (stub/'date').write_text('#!/bin/sh\nn=$(cat "$QWB_DATE_COUNT" 2>/dev/null || echo 0); n=$((n+1)); printf %s "$n" > "$QWB_DATE_COUNT"\n[ "$n" != 2 ] || exit 1\nexec /bin/date "$@"\n');(stub/'date').chmod(0o755)
    badtime=tmp/'metadata-failure.json'
    failed=call('qwb-test.sh','full','--project',cd,'--task',ft,'--ledger-project',p,'--op','accept-F','--report',badtime,actor='gate-pane',ok=False,extra={'QWB_DATE_COUNT':str(tmp/'date-count')})
    assert failed.returncode==7 and not badtime.exists(),(failed.returncode,failed.stderr)
    print('PASS 按票门真实7后元信息失败仍返回7，无可信收据')
    evidence=os.environ.get('QWB_GATE_EVIDENCE_DIR')
    if evidence:
        dest=Path(evidence).resolve();dest.mkdir(parents=True,exist_ok=False)
        for file in tmp.iterdir():
            if file.is_file() and file.suffix in ('.json','.jsonl'):shutil.copy(file,dest/file.name)
        for ticket in (p/'tasks').glob('*.md'):
            (dest/(ticket.stem+'-ledger.json')).write_text(call('qwb-ledger.sh','read','--task',ticket).stdout)
            shutil.copy(ticket,dest/ticket.name)
        (dest/'README.md').write_text('这些是临时Git+fakeHerdr的行为证据，路径/PID/模型会话是fixture，不是现场原生审核身份；临时副本已回收。不能据此声称真实Herdr交互已验。\n')
        print('fixture原始收据/审核/账本/Herdr调用保存：'+str(dest))
PY
