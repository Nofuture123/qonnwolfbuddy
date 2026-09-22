"""Installed guide links and safe upgrade, run by smoke.sh."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
INIT = ROOT / "bin/qwb-init.sh"
DOCS = ("ci-guide.md", "host-watch-guide.md", "worker-launch-guide.md")


def run(project, init=INIT):
    return subprocess.run(["bash", str(init), str(project)], text=True, capture_output=True)


def check_links(project):
    guide = (project / "qwbuddy/QWBUDDY.md").read_text()
    targets = re.findall(r"\]\(([^)]+\.md)\)", guide)
    for doc in DOCS:
        assert doc in targets, f"missing link: {doc}"
        assert (project / "qwbuddy" / doc).is_file(), f"missing installed doc: {doc}"
    for link in targets:
        assert (project / "qwbuddy" / link).is_file(), f"broken link: {link}"
    role = project / "qwbuddy/roles/主控.md"
    for link in re.findall(r"\]\(([^)]+\.md)\)", role.read_text()):
        assert (role.parent / link).is_file(), f"broken role link: {link}"


with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    project = base / "project"
    project.mkdir()
    result = run(project)
    assert result.returncode == 0, result.stderr
    check_links(project)
    guide_path = project / "qwbuddy/QWBUDDY.md"
    original = guide_path.read_text()
    guide_path.write_text(original.replace("(ci-guide.md)", "(missing-ci-guide.md)"))
    try:
        check_links(project)
        raise AssertionError("wrong guide link passed")
    except AssertionError as err:
        assert "missing link" in str(err)
    guide_path.write_text(original)
    # Old installed copy is incomplete until explicit upgrade.
    (project / "qwbuddy" / DOCS[0]).unlink()
    try:
        check_links(project)
        raise AssertionError("missing installed guide passed")
    except AssertionError as err:
        assert "missing installed doc" in str(err)
    result = run(project)
    assert result.returncode == 0, result.stderr
    check_links(project)
    config = project / "qwbuddy/config.sh"
    config.write_text("# user configuration\n")
    result = run(project)
    assert result.returncode == 0 and config.read_text() == "# user configuration\n"
    # A symlink at the destination must never redirect an installed guide.
    outside = base / "outside.md"
    outside.write_text("sentinel")
    target = project / "qwbuddy" / DOCS[0]
    target.unlink()
    target.symlink_to(outside)
    result = run(project)
    assert result.returncode != 0 and outside.read_text() == "sentinel", result.stderr
    target.unlink()
    target.mkdir()
    result = run(project)
    assert result.returncode != 0 and not (target / DOCS[0]).exists(), result.stderr
    target.rmdir()
    os.link(outside, target)
    result = run(project)
    assert result.returncode == 0 and outside.read_text() == "sentinel", result.stderr
    assert target.read_text() != "sentinel"
    # Missing source must fail clearly, even for an existing target project.
    source = base / "source"
    (source / "bin").mkdir(parents=True)
    (source / "templates").mkdir()
    (source / "bin/qwb-init.sh").write_bytes(INIT.read_bytes())
    for doc in DOCS[1:]:
        (source / "templates" / doc).write_text("stub")
    result = run(project, source / "bin/qwb-init.sh")
    assert result.returncode != 0 and "缺少专项文档源文件" in result.stderr, result.stderr

print("on-demand-guide: installed links, upgrade, symlink and missing-source checks passed")
