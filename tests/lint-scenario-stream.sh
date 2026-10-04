#!/usr/bin/env bash
# Real public lint/run, private fixtures and fake Herdr only. No network or model calls.
set -euo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
QWB_STREAM_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_STREAM_TEST_ROOT
python3 -u -B - <<'PY'
import hashlib, json, os, shutil, subprocess, tempfile
from pathlib import Path

root = Path(os.environ['QWB_STREAM_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-lint-stream-') as tmp:
    os.environ["TMPDIR"] = tmp
    project = Path(tmp).resolve()
    (project/'templates').mkdir(); (project/'tasks').mkdir()
    shutil.copytree(root/'bin', project/'bin')
    shutil.copy(root/'templates/QWBUDDY.md', project/'templates/QWBUDDY.md')
    shutil.copy(root/'qwb.config.sh', project/'qwb.config.sh')
    task = project/'tasks/stream.md'
    # Bigger than the pipe buffer: grep -q exits while printf is still writing.
    block = ('## 验收场景\n### user_stream\nGiven valid frozen fixture\n'
             'When public lint reads it\nThen failure is reported\n'
             + ('fixture context ' + 'x'*240 + '\n')*4096).rstrip('\n')

    def check(name, text, expected_rc, expected_failure=None, fingerprint=None):
        digest = fingerprint or hashlib.sha1(text.encode()).hexdigest()
        task.write_text('# stream fixture\nstate: running\nscenarios-fp: '+digest+'\n'+text+'\n## End\n')
        before = task.read_bytes()
        result = subprocess.run(['bash', str(root/'bin/qwb-lint.sh'), '--project', str(project)],
                                capture_output=True, text=True)
        failures = [line for line in result.stdout.splitlines() if line.startswith('FAIL')]
        print(f'RC {name}: {result.returncode} expected={expected_rc}')
        for line in failures: print(line)
        assert result.returncode == expected_rc, (name, result.stdout, result.stderr)
        assert task.read_bytes() == before, 'lint rewrote frozen fixture'
        if expected_failure:
            assert len(failures) == 1 and expected_failure in failures[0], (name, failures)
        else:
            assert not failures and 'LINT PASS' in result.stdout, (name, failures)
        print('PASS', name)

    check('valid large frozen block', block, 0)
    check('missing Given still rejected', block.replace('Given valid frozen fixture', 'Setup valid frozen fixture'), 1, '无可识别场景')
    check('missing failure path still rejected', block.replace('Then failure is reported', 'Then success is reported'), 1, '无失败路径场景')
    check('changed fingerprint still rejected', block, 1, '验收场景在派发后被改动', fingerprint='0'*40)

    # Exercise the public dispatch gate, including actual frozen ticket writes.
    dispatch = project/'dispatch'; (dispatch/'tasks').mkdir(parents=True)
    shutil.copytree(root/'bin', dispatch/'qwbuddy/bin')
    (dispatch/'qwbuddy/config.sh').write_text("QWB_WORKERS='fixture'\nQWB_WORKSPACE='fixture-ws'\n")
    (dispatch/'qwbuddy/workers.sh').write_text('qwb_worker fixture herdr pi -- --thinking high\n')
    stub = project/'stub'; stub.mkdir(); calls = project/'herdr.jsonl'
    herdr = stub/'herdr'
    herdr.write_text('''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
with open(os.environ['STREAM_HERDR_LOG'], 'a') as log:
    log.write(json.dumps(args, ensure_ascii=False)+'\\n')
if args[:2] == ['agent', 'get']:
    print(json.dumps({'error': {'code': 'agent_not_found'}})); sys.exit(1)
if args[:2] == ['workspace', 'list']:
    result = {'workspaces': [{'workspace_id': 'fixture-ws'}]}
elif args[:2] == ['tab', 'create']:
    result = {'root_pane': {'pane_id': 'fixture-worker', 'tab_id': 'fixture-tab'}}
elif args[:2] == ['pane', 'get']:
    result = {'pane': {'pane_id': args[2]}}
elif args[:2] == ['pane', 'process-info']:
    result = {'process_info': {'pane_id': args[-1], 'shell_pid': 42,
              'foreground_process_group_id': 42,
              'foreground_processes': [{'pid': 42, 'argv0': 'bash'}]}}
elif args[:2] in (['agent', 'start'], ['agent', 'prompt']):
    result = {'type': 'ok'}
else:
    print('unexpected fixture call: '+repr(args), file=sys.stderr); sys.exit(9)
print(json.dumps({'result': result}))
''')
    herdr.chmod(0o755)
    env = os.environ | {'PATH': str(stub)+os.pathsep+os.environ['PATH'],
                        'HERDR_PANE_ID': 'fixture-ctl', 'STREAM_HERDR_LOG': str(calls)}
    run_task = dispatch/'tasks/dispatch.md'

    def check_dispatch(name, text, expected_rc, expected_failure=None):
        run_task.write_text('# dispatch fixture\nstate: running\n'
                            'implementation-authorized: private fixture\ndispatch-budget: 3\n'
                            +text+'\n## End\n')
        before = run_task.read_bytes(); calls.write_text('')
        result = subprocess.run(['bash', str(dispatch/'qwbuddy/bin/qwb-run.sh'),
                                 '--project', str(dispatch), '--task', str(run_task),
                                 '--worker', 'fixture', '--here'], env=env,
                                capture_output=True, text=True)
        print(f'RC {name}: {result.returncode} expected={expected_rc}')
        assert result.returncode == expected_rc, (name, result.stdout, result.stderr)
        commands = [json.loads(line) for line in calls.read_text().splitlines()]
        if expected_failure:
            assert expected_failure in result.stderr, (name, result.stdout, result.stderr)
            assert run_task.read_bytes() == before, 'rejected dispatch rewrote ticket'
            assert not commands, 'rejected dispatch called Herdr'
        else:
            after = run_task.read_text()
            digest = hashlib.sha1(text.encode()).hexdigest()
            assert 'scenarios-fp: '+digest+'\n' in after, 'dispatch froze incorrect block'
            assert after.count('\ndispatch:') == 1, 'dispatch receipt missing or duplicated'
            assert [cmd[:2] for cmd in commands] == [
                ['agent', 'get'], ['workspace', 'list'], ['tab', 'create'],
                ['agent', 'start'], ['pane', 'get'], ['pane', 'process-info'],
                ['agent', 'prompt']], commands
        print('PASS', name)

    check_dispatch('valid large block dispatches', block, 0)
    check_dispatch('missing block dispatch still rejected', '', 1, '任务书没有「验收场景」块')
    check_dispatch('missing failure path dispatch still rejected',
                   block.replace('Then failure is reported', 'Then success is reported'),
                   1, '验收场景里没有失败路径场景')
PY
