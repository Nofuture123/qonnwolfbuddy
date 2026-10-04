"""Copy the pristine smoke installation and detect changes to its contents."""
from pathlib import Path
import hashlib
import json
import os
import stat
import subprocess
import sys


def snapshot(root):
    result = {}
    for path in sorted(root.rglob('*')):
        info = path.lstat()
        if path.is_symlink():
            value = ['link', os.readlink(path)]
        elif path.is_file():
            value = ['file', hashlib.sha256(path.read_bytes()).hexdigest()]
        elif path.is_dir():
            value = ['dir']
        else:
            raise ValueError(f'unexpected installation entry: {path}')
        result[str(path.relative_to(root))] = [stat.S_IMODE(info.st_mode), *value]
    return result


def quote(value):
    return "'" + value.replace("'", "'\\''") + "'"


mode, directory, *args = sys.argv[1:]
root = Path(directory)
if mode == 'snapshot':
    Path(args[0]).write_text(json.dumps(snapshot(root), sort_keys=True))
elif mode == 'check':
    if snapshot(root) != json.loads(Path(args[0]).read_text()):
        print('黄金安装在使用期间被修改', file=sys.stderr)
        sys.exit(1)
elif mode == 'copy':
    original, target = args
    target = Path(target).resolve()
    target.mkdir(parents=True, exist_ok=True)
    subprocess.run(['cp', '-R', str(root) + '/.', str(target)], check=True)
    workers = target / 'qwbuddy/workers.sh'
    content = workers.read_bytes()
    source_arg = quote(str(Path(original).resolve())).encode()
    target_arg = quote(str(target)).encode()
    if source_arg not in content:
        raise ValueError('pristine workers.sh has no original project argument')
    workers.write_bytes(content.replace(source_arg, target_arg))
elif mode == 'verify':
    import shutil
    import tempfile

    with tempfile.TemporaryDirectory(prefix='smoke-copy-', dir=root / '.qwb-tmp') as temporary:
        base = Path(temporary)
        home = base / 'home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), TMPDIR=str(base),
                   HERDR_SOCKET_PATH='/dev/null/qwb-test.sock')
        seed = base / 'seed'
        seed.mkdir()
        subprocess.run(['bash', str(root / 'bin/qwb-init.sh'), str(seed)],
                       env=env, check=True, stdout=subprocess.DEVNULL)
        golden = base / 'golden'
        subprocess.run(['cp', '-R', str(seed), str(golden)], check=True)
        manifest = base / 'manifest.json'
        helper = str(Path(__file__).resolve())

        def invoke(*argv):
            return subprocess.run([sys.executable, '-B', helper, *map(str, argv)],
                                  env=env, capture_output=True)

        def bytes_and_modes(project):
            result = {}
            for path in project.rglob('*'):
                result[str(path.relative_to(project))] = (
                    stat.S_IMODE(path.stat().st_mode),
                    path.read_bytes() if path.is_file() else None)
            return result

        assert invoke('snapshot', golden, manifest).returncode == 0
        for name in ('plain', 'space project', "quote'project", '中文项目'):
            project = base / name
            project.mkdir()
            subprocess.run(['bash', str(root / 'bin/qwb-init.sh'), str(project)],
                           env=env, check=True, stdout=subprocess.DEVNULL)
            expected = bytes_and_modes(project)
            shutil.rmtree(project)
            copied = invoke('copy', golden, seed, project)
            assert copied.returncode == 0, copied.stderr
            assert bytes_and_modes(project) == expected, name
            subprocess.run(['/bin/bash', '-n', str(project / 'qwbuddy/workers.sh')], check=True)
            (project / 'copy-only').write_text('local change')
            assert invoke('check', golden, manifest).returncode == 0
        pollution = golden / 'contamination'
        pollution.write_text('changed golden')
        assert invoke('check', golden, manifest).returncode == 1
        pollution.unlink()
        assert invoke('check', golden, manifest).returncode == 0
        print('COPY VERIFY OK: four real installations match byte-for-byte and by mode; copies are isolated; golden pollution is detected')
else:
    raise ValueError(f'unknown operation: {mode}')
