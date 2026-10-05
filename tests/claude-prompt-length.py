"""Offline Claude prompt formatting through real dispatch and wake entries."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

sys.dont_write_bytecode = True
from process_fixture import TemporaryDirectory, run
from prompt_file import native_calls

ROOT = Path(sys.argv[1]).resolve()
if 'QWB_TEST_SOCKET_DIRS' not in os.environ:
    sys.exit(run([sys.executable, __file__, str(ROOT)]).returncode)
os.environ.setdefault('QWB_TEST_GROUP', str(os.getpgrp()))
prefix = (ROOT / 'tests/worktree-space.py').read_text().split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]', 'ROOT = Path(sys.argv[1]).resolve()'))
BASELINE = os.environ.get('QWB_PROMPT_BASELINE') == '1'


def strip_shape(raw):
    if b'# CLAUDE_PROMPT_SHAPE_BEGIN' not in raw:
        return raw
    text = re.sub(r'^# CLAUDE_PROMPT_SHAPE_BEGIN\n.*?^# CLAUDE_PROMPT_SHAPE_END\n', '', raw.decode(), flags=re.M | re.S)
    text = text.replace('"$NAME" "$SEND_PROMPT"', '"$NAME" "$PROMPT"', 1)
    # The first send is the reused worker and has always had this prefix.
    text = text.replace('herdr agent prompt "$NAME" "$PROMPT"', 'herdr agent prompt "$NAME" "这是返工/续派，读主账本末尾主控最新一条 working: 行。${PROMPT}"', 1)
    text = text.replace('"$NAME" "$SEND_PROMPT"', '"$NAME" "$PROMPT"')
    text = text.replace('"$PANE" "$SEND_PROMPT"', '"$PANE" "$PROMPT"')
    # Before the fix, reuse already contains the prefix; do not add it twice.
    text = text.replace('这是返工/续派，读主账本末尾主控最新一条 working: 行。这是返工/续派，读主账本末尾主控最新一条 working: 行。', '这是返工/续派，读主账本末尾主控最新一条 working: 行。')
    return text.encode()


def pointer(message, repo, cwd):
    assert '\n' not in message and '\r' not in message and len(message) <= 600, (len(message), message)
    assert '完整指令文件：' in message and '先完整读取' in message, message
    name, _ = json.JSONDecoder().raw_decode(message.split('完整指令文件：', 1)[1])
    path = Path(name)
    if not path.is_absolute():
        path = (repo if '项目根内' in message else cwd) / path
    path = path.resolve()
    assert path.is_file() and repo / 'qwbuddy/.roles/.prompts' in path.parents, path
    raw = path.read_bytes()
    assert path.stem == hashlib.sha256(raw).hexdigest(), path
    return raw


with TemporaryDirectory(prefix='s-') as d:
    os.environ['TMPDIR'] = d
    b = Path(d)
    # Deliberately long but each filesystem component stays within NAME_MAX.
    long = b / ('长路径' * 35) / ('deep-' * 30) / ('more-' * 30) / ('leaf-' * 20)
    long.mkdir(parents=True)
    repo, ticket, state, log, env = project(long)
    runtime = repo / 'qwbuddy/bin'
    original = {name: (runtime / name).read_bytes() for name in ('qwb-run.sh', 'qwb-wake.sh', 'qwb-lib.sh')}
    native = STUB.replace('if args[:2] == ["status", "--json"]:', '''if args[:2] == ['agent','get']:
    if args[2]=='qwb-case' and os.environ.get('PROMPT_REUSE')!='1': err('agent_not_found')
    out({'agent':dict(name='qwb-case',pane_id='wRoot:p1',agent=os.environ['PROMPT_TOOL'],
        agent_status='idle',workspace_id='wRoot',cwd=str(root))})
elif args[:2]==['pane','get'] and args[2]=='wRoot:p1':
    out({'pane':dict(pane_id='wRoot:p1',agent=os.environ['PROMPT_TOOL'],workspace_id='wRoot',cwd=str(root))})
elif args[:2]==['tab','create']:
    out({'root_pane':dict(pane_id='wRoot:p1',tab_id='wRoot:t1')})
elif args[:2] == ["status", "--json"]:''')
    (long / 'stub/herdr').write_text(native)
    # Formatting is independent of native activity adapters: grant an isolated idle boundary for reuse.
    # The production Claude adapter at this base still refuses unknown; no real CLI/session is started.
    (runtime / 'qwb-herdr.sh').write_text('#!/bin/bash\nprintf \'{"activity":"idle","proof":"formatting-fixture","pane":"wRoot:p1"}\\n\'\n')
    date = long / 'stub/date'
    date.write_text('#!/bin/sh\ncase "$*" in *%s*) printf "1791169873\\n";; *) printf "2026-10-05T03:11:13Z\\n";; esac\n')
    date.chmod(0o755)
    ledger = runtime / 'qwb-ledger.sh'
    ledger.write_bytes(ledger.read_bytes().replace(b',gmtime)', b',gmtime(1791169873))'))
    env.update(PROMPT_TOOL='claude', QWB_TEST_WT=str(repo))
    dispatch = ['/bin/bash', str(runtime / 'qwb-run.sh'), '--project', str(repo), '--task', 'case', '--worker', 'pi', '--here']
    def install(old=False):
        for name, raw in original.items():
            (runtime / name).write_bytes(strip_shape(raw) if old else raw)
        with (runtime / 'qwb-lib.sh').open('a') as f:
            f.write('\nqwb_op_id() { printf prompt-fixture; }\n')
    def reset(tool='claude', mode='herdr'):
        ticket.write_text(TASK)
        log.write_text('')
        state.write_text(str(repo))
        (repo / 'qwbuddy/config.sh').write_text("QWB_WORKERS='pi'\nQWB_WORKSPACE='wRoot'\n")
        (repo / 'qwbuddy/workers.sh').write_text('qwb_worker pi ' + ('herdr ' + tool + ' --' if mode == 'herdr' else ("pane-run " + tool + " --fixture")) + '\n')
        env['PROMPT_TOOL'] = tool
        env.pop('PROMPT_REUSE', None)
    def messages():
        return [row[-1] for row in map(json.loads, log.read_text().splitlines()) if row[:2] == ['agent', 'prompt'] or (row[:2] == ['pane', 'run'] and row[-1] not in ("'pi' '--fixture'", "'claude' '--fixture'"))]
    def run_dispatch():
        result = subprocess.run(dispatch, env=env, capture_output=True)
        assert result.returncode == 0, (result.stdout, result.stderr)
        return result

    install(True)
    reset()
    run_dispatch()
    full = messages()[-1].encode()
    assert len(full.decode()) > 600
    install(BASELINE)
    reset()
    run_dispatch()
    sent = messages()[-1]
    assert pointer(sent, repo, repo) == full
    assert native_calls([json.dumps(['pane', 'run', 'worker', sent])], repo)[0][3].encode() == full
    print('PASS user_正常路径_给Claude工人的长派工提示词改为指路', flush=True)

    # Compare the full public Pi run: stdout/stderr/rc, ticket and native argv, not just text.
    for mode in ('herdr', 'pane-run'):
        results = []
        before_files = sorted((repo / 'qwbuddy/.roles/.prompts').iterdir())
        for old in (True, False):
            install(old)
            reset('pi', mode)
            result = run_dispatch()
            results.append((result.returncode, result.stdout, result.stderr, ticket.read_bytes(), log.read_bytes()))
        assert results[0] == results[1], (mode, 'Pi public dispatch changed bytes')
        assert before_files == sorted((repo / 'qwbuddy/.roles/.prompts').iterdir()), 'Pi created a file'
    install()
    lib = runtime / 'qwb-lib.sh'
    shape = ['bash', '-c', '. "$1"; qwb_shape_prompt "$2" "$3" "$4" "$5" "$6" "${7:-}"', 'shape', str(lib), str(repo)]
    for tool, text in [('claude', '短消息\t原字节'), ('claude', '中' * 600), ('pi', '长' * 1000 + '\n\n')]:
        before = sorted((repo / 'qwbuddy/.roles/.prompts').iterdir())
        result = subprocess.run(shape + [tool, '主控派工', str(repo), text], capture_output=True, env=env)
        assert result.returncode == 0 and result.stdout == text.encode(), result.stderr
        assert before == sorted((repo / 'qwbuddy/.roles/.prompts').iterdir())
    print('PASS user_正常路径_短提示词与Pi工人不变（600中文字符按字符数，尾换行保真，无新文件）', flush=True)
    for tool, text in [('claude', 'a' * 601), ('claude', '短\n多行\n'), ('claude', '短\r内容'), ('', '长' * 601)]:
        result = subprocess.run(shape + [tool, '主控派工', str(repo), text], capture_output=True, env=env)
        assert result.returncode == 0, result.stderr
        assert pointer(result.stdout.decode(), repo, repo) == text.encode()
    print('PASS user_正常路径_多行和unknown保守指路（原文尾换行不丢）', flush=True)
    worker_dir = repo / '.worktrees/worker'
    worker_dir.mkdir(parents=True)
    text = '隔离目录长指令' * 100
    result = subprocess.run(shape + ['claude', '主控派工', str(worker_dir), text], capture_output=True, env=env)
    assert result.returncode == 0 and '当前工作目录内' in result.stdout.decode(), result.stderr
    assert pointer(result.stdout.decode(), repo, worker_dir) == text.encode()
    identity = dict(actor='planner', pane='role-pane', incarnation='incarnation', owner_fp='owner', session_id='session')
    record = repo / 'qwbuddy/.roles/planner.json'
    for tool in ('pi', 'claude'):
        record.write_text(json.dumps(identity | {'tool': tool}))
        result = subprocess.run(shape + ['', '值守交接门铃', str(repo), text, json.dumps(identity)], capture_output=True, env=env)
        assert result.returncode == 0, result.stderr
        if tool == 'pi': assert result.stdout == text.encode()
        else: assert pointer(result.stdout.decode(), repo, repo) == text.encode()
    record.write_text(json.dumps(identity | {'tool': 'pi', 'incarnation': 'old'}))
    result = subprocess.run(shape + ['', '值守交接门铃', str(repo), text, json.dumps(identity)], capture_output=True, env=env)
    assert result.returncode == 0 and pointer(result.stdout.decode(), repo, repo) == text.encode()
    print('PASS user_正常路径_超长路径可相对寻址、既有Pi角色不变、旧代tool不能绕过上限', flush=True)
    text = '碰撞时不能覆盖另一操作' * 100
    collision = repo / 'qwbuddy/.roles/.prompts' / (hashlib.sha256(text.encode()).hexdigest() + '.md')
    collision.write_bytes(b'another operation')
    result = subprocess.run(shape + ['claude', '主控派工', str(repo), text], capture_output=True, env=env)
    assert result.returncode != 0 and not result.stdout and collision.read_bytes() == b'another operation'
    assert not list(collision.parent.glob('.publish-*')), 'partial publication left behind'
    print('PASS user_失败路径_摘要文件冲突拒绝覆盖且无半成品', flush=True)

    # Fresh repeated requests reuse identical content without ever overwriting another operation's bytes.
    reset()
    run_dispatch()
    env['PROMPT_REUSE'] = '1'
    log.write_text('')
    run_dispatch()
    reuse_full = ('这是返工/续派，读主账本末尾主控最新一条 working: 行。' + full.decode()).encode()
    assert pointer(messages()[-1], repo, repo) == reuse_full
    count = len(list((repo / 'qwbuddy/.roles/.prompts').iterdir()))
    log.write_text('')
    run_dispatch()
    assert pointer(messages()[-1], repo, repo) == reuse_full
    assert count == len(list((repo / 'qwbuddy/.roles/.prompts').iterdir()))
    print('PASS user_正常路径_返工与续派同样受控（idle边界夹具；同内容文件复用不覆盖）', flush=True)

    reset(mode='pane-run')
    run_dispatch()
    assert pointer(messages()[-1], repo, repo) == full
    print('PASS user_正常路径_pane-run提示词受控', flush=True)

    # An unwritable runtime parent (a regular file) deterministically fails even under root.
    reset()
    prompts = repo / 'qwbuddy/.roles/.prompts'
    saved = prompts.with_name('saved-prompts')
    prompts.rename(saved)
    prompts.write_text('cannot be a directory')
    try:
        for mode in ('herdr', 'pane-run'):
            reset(mode=mode)
            result = subprocess.run(dispatch, env=env, capture_output=True)
            assert result.returncode != 0 and '已派发'.encode() not in result.stdout
            assert not messages() and not re.search(r'^dispatch:', ticket.read_text(), re.M), (mode, messages(), ticket.read_text())
            assert '指令文件' in result.stderr.decode(), result.stderr
    finally:
        prompts.unlink()
        saved.rename(prompts)
    print('PASS user_失败路径_指令文件写不进去时不发残缺指令', flush=True)

    # Wake many legacy tickets with a deterministic clock/date; compare complete wake receipts.
    ticket.unlink()
    tasks = [repo / f'tasks/2099-01-01-ticket-{i}.md' for i in range(8)]
    wake = ['/bin/bash', str(runtime / 'qwb-wake.sh'), '--project', str(repo), '--once', '--pane', 'wRoot:pCtl']
    snapshots = []
    full_wake = None
    for old in (True, False):
        install(old)
        for i, t in enumerate(tasks):
            t.write_text('state: blocked\nblocked: ' + str(i) + '需裁决' * 40 + '\n')
        log.write_text('')
        result = subprocess.run(wake, env=env, capture_output=True)
        assert result.returncode == 0, (result.stdout, result.stderr)
        rows = list(map(json.loads, log.read_text().splitlines()))
        sent = [row[3] for row in rows if row[:2] == ['pane', 'run']]
        assert len(sent) == 1 and not any(row[:2] == ['pane', 'get'] for row in rows), rows
        if old:
            full_wake = sent[0].encode()
            assert len(sent[0]) > 600
        else:
            assert pointer(sent[0], repo, repo) == full_wake
        snapshots.append((result.returncode, result.stdout, result.stderr, [t.read_bytes() for t in tasks]))
    assert snapshots[0] == snapshots[1], 'wake receipts changed'
    print('PASS user_正常路径_叫醒Claude主控的多票消息不超限（票字节及wake记录不变，无新增查询）', flush=True)
