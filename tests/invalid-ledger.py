"""Public CLI regression for invalid UTF-8 in a live task ledger."""
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
fixture = runpy.run_path(str(ROOT / "tests/r2-cli.py"))["fixture"]


def cli(*args, env):
    result = subprocess.run(args, env=env, capture_output=True)
    return result.returncode, result.stdout.decode("utf-8", "replace"), result.stderr.decode("utf-8", "replace")


for location in ("state", "after-state", "done", "working", "scenario", "spec-defect", "verified-invalid"):
    with tempfile.TemporaryDirectory(prefix=f"qwb-invalid-{location}-") as d:
        repo, ticket, env, log = fixture(Path(d))
        body = ticket.read_bytes().replace(b"state: blocked", b"state: running")
        if location == "state":
            body = body.replace(b"state: running", b"state: run\x80ning")
        elif location == "verified-invalid":
            body = body.replace(b"state: running", b"state: verified") + b"done: SHA=\x80\x82 invalid\n"
        elif location == "after-state":
            body = body.replace(b"state: running\n", b"state: running\ncomment: \x80\x82\n")
        elif location == "scenario":
            body = body.replace(b"Given ", b"Given \x80", 1)
        elif location == "spec-defect":
            body += b"blocked: spec-defect: \x80\x82 unresolved\n"
        else:
            body += location.encode() + b": SHA=\x80\x82 invalid\n"
        ticket.write_bytes(body)
        (repo / ".worktrees/case").mkdir(parents=True)
        rc, status, err = cli("bash", str(repo / "qwbuddy/bin/qwb-status.sh"),
                              "--project", str(repo), env=env)
        assert rc == 0 and "[未结]" in status and ticket.name in status, (location, rc, status, err)
        rc, wake, err = cli("bash", str(repo / "qwbuddy/bin/qwb-wake.sh"), "--dry-run",
                           "--project", str(repo), env=env)
        assert rc == 0 and "未结项（将叫醒）" in wake and ticket.name in wake, (location, rc, wake, err)
        rc, listed, err = cli("bash", str(repo / "qwbuddy/bin/qwb-worktree.sh"), "list",
                              "--project", str(repo), env=env)
        assert rc == 0 and "未结项" in listed and "case" in listed, (location, rc, listed, err)
        rc, lint, err = cli("bash", str(repo / "qwbuddy/bin/qwb-lint.sh"),
                           "--project", str(repo), env=env)
        assert rc != 0 and "非法 UTF-8" in lint + err and "LINT FAIL" in lint, (location, rc, lint, err)
        if location == "verified-invalid":
            continue
        before = ticket.read_bytes()
        rc, out, err = cli("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                           "--task", "case", "--worker", "pi", "--here", env=env)
        if location == "spec-defect":
            assert rc != 0 and "未决规格疑点" in err and ticket.read_bytes() == before, (rc, out, err)
        elif location == "state":
            assert rc != 0 and "state" in err and ticket.read_bytes() == before, (rc, out, err)
        else:
            assert rc == 0 and "scenarios-fp:" in ticket.read_text(encoding="utf-8", errors="replace"), (rc, out, err)
            fp = next(line for line in ticket.read_bytes().splitlines() if line.startswith(b"scenarios-fp:"))
            rc2, _, err2 = cli("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                               "--task", "case", "--worker", "pi", "--here", env=env)
            assert rc2 == 0 and ticket.read_bytes().count(fp) == 1, (location, rc2, err2)
print("INVALID LEDGER PASS: status/wake keep ticket visible, lint fails clearly, run gates remain stable")
