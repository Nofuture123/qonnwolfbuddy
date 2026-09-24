"""R4 regressions through installed public CLIs and a strict Herdr argv stub."""
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixture = runpy.run_path(str(ROOT / "tests/r2-cli.py"))["fixture"]


def call(*argv, env):
    return subprocess.run(argv, env=env, capture_output=True)


def strict_herdr(base):
    stub = base / "stub/herdr"
    script = stub.read_text()
    script = script.replace("a=sys.argv[1:]", """a=sys.argv[1:]
try:
    for arg in a: os.fsencode(arg).decode('utf-8')
except UnicodeDecodeError:
    print('error: argument is not valid UTF-8', file=sys.stderr); sys.exit(2)
""")
    stub.write_text(script)


def wake_case(label, line, expected=None):
    for mode in ("once", "block"):
        with tempfile.TemporaryDirectory(prefix=f"qwb-r4-wake-{label}-{mode}-") as d:
            base = Path(d)
            repo, ticket, env, log = fixture(base)
            strict_herdr(base)
            ticket.write_bytes(ticket.read_bytes() + line)
            if mode == "block":
                env.pop("HERDR_PANE_ID", None)
            args = ["bash", str(repo / "qwbuddy/bin/qwb-wake.sh"), "--project", str(repo)]
            args += ["--once", "--pane", "wRoot:p1"] if mode == "once" else ["--block"]
            result = call(*args, env=env)
            output = result.stdout.decode("utf-8")
            error = result.stderr.decode("utf-8", "replace")
            assert result.returncode == (0 if mode == "once" else 2), (label, mode, result.returncode, output, error)
            wake_lines = [row for row in ticket.read_bytes().splitlines() if row.startswith(b"wake:")]
            assert len(wake_lines) == 1, (label, mode, output, error)
            if mode == "once":
                calls = [json.loads(row) for row in log.read_text().splitlines()]
                delivered = [row[3] for row in calls if row[:3] == ["pane", "run", "wRoot:p1"]]
                assert len(delivered) == 1, (label, calls)
                summary = delivered[0]
            else:
                summary = output
            summary.encode("utf-8").decode("utf-8")
            assert "看账本：" in summary and "最近: " in summary, (label, mode, summary)
            if expected is not None:
                assert f"最近: {expected}" in summary, (label, mode, summary[-300:])


def wake_summary():
    long_line = ("working: " + "汉" * 200).encode("utf-8") + b"\n"
    assert len(long_line) > 160 and len(long_line[:160].decode("utf-8", "ignore").encode()) < 160
    wake_case("long", long_line, ("working: " + "汉" * 200)[:160])
    wake_case("invalid", b"done: SHA=\x80\x82 please verify\n")
    print("R4 WAKE PASS: strict Herdr accepts once; block output is valid UTF-8")


def dispatch_name(ticket_name, locale, explicit=None):
    with tempfile.TemporaryDirectory(prefix="qwb-r4-name-") as d:
        base = Path(d)
        repo, ticket, env, _ = fixture(base)
        renamed = ticket.with_name(f"2099-01-01-{ticket_name}.md")
        ticket.rename(renamed)
        env["LC_ALL"] = locale
        env["LANG"] = locale
        args = ["bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                "--task", str(renamed), "--worker", "pi", "--here"]
        if explicit:
            args += ["--name", explicit]
        result = call(*args, env=env)
        assert result.returncode == 0, (ticket_name, locale, result.stdout.decode("utf-8", "replace"), result.stderr.decode("utf-8", "replace"))
        dispatch = next(row.decode("utf-8") for row in renamed.read_bytes().splitlines() if row.startswith(b"dispatch:"))
        return next(item.split("=", 1)[1] for item in dispatch.split() if item.startswith("agent="))


def names():
    first = dispatch_name("真实闭环甲-e2e", "C")
    assert first == dispatch_name("真实闭环甲-e2e", "en_US.UTF-8")
    second = dispatch_name("真实闭环乙-e2e", "C")
    assert first != second, (first, second)
    for name in (first, second):
        assert len(name) <= 32 and name.startswith("qwb-") and all(c in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in name), name
    assert dispatch_name("ascii-task-42", "C") == "qwb-ascii-task-42"
    assert dispatch_name("ascii-task-42", "C", "Custom_42") == "custom_42"
    print(f"R4 NAME PASS: locale stable, distinct Chinese IDs, ASCII and explicit preserved ({first}, {second})")


if __name__ == "__main__":
    selected = sys.argv[1:] or ["wake", "name"]
    if "wake" in selected:
        wake_summary()
    if "name" in selected:
        names()
