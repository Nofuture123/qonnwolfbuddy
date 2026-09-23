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

    # Core templates and parent directories must not redirect installation outside the project.
    unsafe = base / "unsafe-core"
    (unsafe / "qwbuddy").mkdir(parents=True)
    core_sentinel = base / "core-sentinel.md"
    core_sentinel.write_text("keep core\n")
    (unsafe / "qwbuddy/QWBUDDY.md").symlink_to(core_sentinel)
    result = run(unsafe)
    assert result.returncode != 0 and core_sentinel.read_text() == "keep core\n", result.stderr

    unsafe_dir = base / "unsafe-directory"
    (unsafe_dir / "qwbuddy").mkdir(parents=True)
    external_bin = base / "external-bin"
    external_bin.mkdir()
    (unsafe_dir / "qwbuddy/bin").symlink_to(external_bin, target_is_directory=True)
    result = run(unsafe_dir)
    assert result.returncode != 0 and not list(external_bin.iterdir()), result.stderr

    dangling = base / "dangling-config"
    (dangling / "qwbuddy").mkdir(parents=True)
    outside_config = base / "outside-config.sh"
    (dangling / "qwbuddy/config.sh").symlink_to(outside_config)
    result = run(dangling)
    assert result.returncode != 0 and not outside_config.exists(), result.stderr

    unsafe_backup = base / "unsafe-pi-backup"
    (unsafe_backup / ".pi/extensions").mkdir(parents=True)
    (unsafe_backup / ".pi/extensions/qwb-watch.ts").write_text("old extension\n")
    backup_sentinel = base / "pi-backup-sentinel"
    backup_sentinel.write_text("keep backup\n")
    (unsafe_backup / ".pi/extensions/qwb-watch.ts.bak").symlink_to(backup_sentinel)
    result = run(unsafe_backup)
    assert result.returncode != 0 and backup_sentinel.read_text() == "keep backup\n", result.stderr

    safe_temp = base / "settings-temp"
    (safe_temp / ".claude").mkdir(parents=True)
    settings_sentinel = base / "settings-temp-sentinel"
    settings_sentinel.write_text("keep settings\n")
    (safe_temp / ".claude/settings.json.qwbtmp").symlink_to(settings_sentinel)
    result = run(safe_temp)
    assert result.returncode == 0 and settings_sentinel.read_text() == "keep settings\n", result.stderr

    linked_hook = base / "linked-hook"
    linked_hook.mkdir()
    (linked_hook / "CLAUDE.md").write_text("shared\n")
    (linked_hook / "AGENTS.md").symlink_to(linked_hook / "CLAUDE.md")
    result = run(linked_hook)
    assert result.returncode != 0 and (linked_hook / "CLAUDE.md").read_text() == "shared\n", result.stderr

    linked = base / "hardlinked-files"
    (linked / "qwbuddy").mkdir(parents=True)
    outside_core = base / "outside-core.md"
    outside_core.write_text("keep hardlink\n")
    os.link(outside_core, linked / "qwbuddy/QWBUDDY.md")
    outside_ignore = base / "outside-ignore"
    outside_ignore.write_text("keep ignore\n")
    os.link(outside_ignore, linked / ".gitignore")
    result = run(linked)
    assert result.returncode == 0, result.stderr
    assert outside_core.read_text() == "keep hardlink\n"
    assert outside_ignore.read_text() == "keep ignore\n"
    assert (linked / "qwbuddy/QWBUDDY.md").read_text() != "keep hardlink\n"

print("on-demand-guide: installed links, upgrade, symlink and missing-source checks passed")
