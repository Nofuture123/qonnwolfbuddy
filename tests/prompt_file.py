"""Read native message argv and the complete instruction files they reference."""
import hashlib
import json
from pathlib import Path


def native_calls(lines, project):
    calls = [json.loads(line) for line in lines]
    for row in calls:
        if row[:2] != ['pane', 'run'] or not row[3].startswith('QW buddy ') or '完整指令文件：' not in row[3]:
            continue
        text = row[3]
        assert len(text) <= 600 and '\n' not in text and '\r' not in text, text
        name, _ = json.JSONDecoder().raw_decode(text.split('完整指令文件：', 1)[1])
        path = Path(name)
        if not path.is_absolute(): path = Path(project) / path
        path = path.resolve()
        assert Path(project).resolve() / 'qwbuddy/.roles/.prompts' in path.parents, path
        raw = path.read_bytes()
        assert path.stem == hashlib.sha256(raw).hexdigest(), 'instruction file does not match its digest'
        row[3] = raw.decode('utf-8')
    return calls
