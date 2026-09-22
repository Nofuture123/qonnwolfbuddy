# Q-Wolf Buddy (`qwbuddy`)

[简体中文](README.zh.md) · [MIT License](LICENSE)

Q-Wolf Buddy coordinates coding agents within a repository. Markdown task ledgers record requirements and progress, Git worktrees isolate worker changes, and Herdr provides visible agent sessions. The controller dispatches work, checks results independently, arranges review, and decides whether to land changes.

## Capabilities and limits

- `qwb-run.sh` checks Given/When/Then acceptance scenarios, records their fingerprint, and dispatches a worker into a task worktree by default.
- Workers append progress and evidence to the **main project's** ledger. The controller runs the project's declared checks before accepting work.
- `qwb-wake.sh` monitors unfinished tasks. Claude Code uses a Stop hook, Pi an extension, Codex a foreground checkpoint, and other harnesses may use a visible Herdr tab.
- `qwb-status.sh` reports ledger and watch status; `qwb-lock.sh` maintains controller ownership.

A controller process that exits is not automatically restored. Individual tasks may need human input. Passing tests alone does not establish production readiness.

## Requirements and setup

Runtime scripts use Bash, Git, Herdr, Perl with standard modules, and common shell tools including `shasum`. The installer uses Python 3 to merge the Claude Code Stop hook into `.claude/settings.json`; it reports a missing hook if Python 3 is unavailable. Optional `--worker auto` routing uses `jq` and a configured Typesafe API key. The selected agent CLI and project gate commands must also be available. The checks below use ShellCheck; Pi's extension runs in Pi's Node environment. These are tool roles, not minimum-version claims. Linux support has not been verified here.

From this repository, install into an existing Git project:

```bash
bash bin/qwb-init.sh /path/to/project
```

The installer copies templates and runtime scripts into `<project>/qwbuddy/`, adds role and task files, and installs the Pi extension and Claude Code hook where possible. It preserves an existing `qwbuddy/config.sh`; check its output for partial installation.

Declare checks in the target project's `qwbuddy/config.sh`. For an existing pnpm project, for example:

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

Start the controller in the project root and have it read `qwbuddy/QWBUDDY.md`. It acquires the controller lock, checks unfinished tasks, and selects one watch path for its harness. Create `tasks/YYYY-MM-DD-topic.md` from `qwbuddy/TASK.md`, with normal and failure-path acceptance scenarios. The controller can dispatch it with:

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker codex
```

The controller runs the relevant project gate and records the result; a worker's completion claim is not acceptance. See [the controller guide](templates/QWBUDDY.md) for lock, review, and worktree procedures.

## One watch path per controller

Claude Code uses its installed Stop hook. Pi uses `.pi/extensions/qwb-watch.ts`: after acquiring the controller lock on **each** startup, run `/reload`, then use `bash qwbuddy/bin/qwb-status.sh` to confirm a live `pi-ext` watch process. Loading the extension before acquiring the lock does not start its watch. Codex loops a bounded `qwb-wake.sh --block --max-ms 180000` foreground tool call. Other harnesses use the visible-tab fallback:

```bash
bash qwbuddy/bin/qwb-wake.sh --ensure --pane "$HERDR_PANE_ID"
```

The fallback needs a Herdr pane context. `--ensure` does not infer the target pane from `HERDR_PANE_ID`; pass `--pane` at invocation or deliberately configure a stable `QWB_CONTROLLER_PANE`. Do not persist a transient pane ID at every startup. `--block` checks controller-lock ownership against `HERDR_PANE_ID` and needs no target `--pane`.

New worker and watch tabs use `QWB_WORKSPACE` from the target project's `qwbuddy/config.sh`, then a `herdr workspace list` entry whose `worktree.repo_root` matches the project root, then the caller's workspace with a warning. An unknown configured workspace is rejected. Across projects with no root match, deliberately configure the target project's workspace ID in that file; do not copy the controller's current ID blindly. The scripts source `config.sh`, so setting `QWB_WORKSPACE` only in the command environment does not override its assignment there. The visible-tab `--ensure` path is only known to reuse a watch when the controller and watch tab are in the same workspace. When they differ, a later `--ensure` can reject the watch registered in the other workspace; cross-workspace reuse needs a runtime fix.

## Evidence and roadmap

At source commit `1c500b38c014be9e55aa33fede2735ebaaf17d16`, the controller recorded on macOS: `fast` 1.38 s, `full` 88.35 s, smoke 567 PASS, review-identity PASS, and lint PASS. Its environment had Node v26.8.1, ShellCheck 0.11.0, Python 3.14.6, and Herdr 0.9.1. These are observations for that source and machine, not speed targets, minimum versions, or proof for this documentation commit. This ticket's executor runs only fast and lint.

[The E2E runbook](docs/E2E-RUNBOOK.md) covers an earlier `e917008` baseline and records manual intervention on first dispatch. It does not verify an unattended current-source run. Production use remains under review. Current-source unattended device verification, first-run trust handling, long-running watch and restart behavior, and production dogfooding remain open.

Repository layout: `bin/` has installer and runtime scripts (11 shell files at the cited baseline); `templates/` has the guide, task and role templates, configuration, and Pi extension; `tests/` has smoke and contract checks; `docs/` has design, review, and historical E2E records; `tasks/` is the ledger.
