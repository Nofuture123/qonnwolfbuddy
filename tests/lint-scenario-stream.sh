#!/usr/bin/env bash
# Real public lint, private fixture only. No network, model or Herdr calls.
set -euo pipefail
QWB_STREAM_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_STREAM_TEST_ROOT
python3 -u -B - <<'PY'
import hashlib, os, shutil, subprocess, tempfile
from pathlib import Path

root = Path(os.environ['QWB_STREAM_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-lint-stream-') as tmp:
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
PY
