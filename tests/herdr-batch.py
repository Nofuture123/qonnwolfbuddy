#!/usr/bin/env python3
"""Run the independent default Herdr suites with isolated process ownership."""
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
source = (root / 'tests/collab-herdr.sh').read_text()
blocks = re.findall(r'^python3 -B - "\$ROOT" <<\x27PY\x27\n(.*?)^PY\n?', source, re.M | re.S)
assert len(blocks) == 8, 'update the explicit suite count when adding a Herdr suite'
scope = Path(os.environ['QWB_TEST_SCOPE_DIR'])

def run(index):
    script = scope / f'herdr-suite-{index}.sh'
    script.write_text('set -euo pipefail\n. ' + shlex.quote(str(root / 'tests/process-fixture.sh')) +
                      '\nqwb_test_scope "$@"\nexport TMPDIR="$QWB_TEST_SCOPE_DIR"\n'
                      'export GIT_CEILING_DIRECTORIES="$TMPDIR"\n'
                      'export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock\n'
                      'python3 -B - ' + shlex.quote(str(root)) + " <<'PY'\n" + blocks[index] + 'PY\n')
    output = scope / f'herdr-suite-{index}.log'
    with output.open('wb') as log:
        result = subprocess.run(['/bin/bash', str(script)], stdout=log, stderr=subprocess.STDOUT)
    return result.returncode, output

with ThreadPoolExecutor(max_workers=4) as pool:
    results = list(pool.map(run, range(len(blocks))))
rc = 0
for status, output in results:
    sys.stdout.buffer.write(output.read_bytes())
    if status:
        rc = 1
sys.exit(rc)
