# Q-Wolf Buddy (`qwbuddy`)

[简体中文](README.zh.md) · [MIT License](LICENSE)

Q-Wolf Buddy coordinates coding agents within a repository. Markdown task ledgers record requirements and progress, Git worktrees isolate worker changes, and Herdr provides visible agent sessions. The controller dispatches work, checks results independently, arranges review, and decides whether to land changes.

## Capabilities and limits

- `qwb-run.sh` checks Given/When/Then acceptance scenarios, records their fingerprint, and dispatches a worker into a task worktree by default.
- Workers append progress and evidence to the **main project's** ledger. The controller runs the project's declared checks before accepting work.
- `qwb-wake.sh` monitors unfinished tasks. Supported controllers are Claude Code with a Stop hook, Pi with the bundled extension, and Codex with a foreground checkpoint.
- `qwb-status.sh` reports ledger and watch status; `qwb-lock.sh` maintains controller ownership.

A controller process that exits is not automatically restored. Individual tasks may need human input. Passing tests alone does not establish production readiness.

## Requirements and setup

Runtime scripts use Bash, Git, Herdr, Perl with standard modules, and common shell tools including `shasum`. The installer uses Python 3 to merge the Claude Code Stop hook into `.claude/settings.json`; it reports a missing hook if Python 3 is unavailable. Optional `--worker auto` routing uses `jq` and a configured Typesafe API key. The selected agent CLI and project gate commands must also be available. The checks below use ShellCheck; Pi's extension runs in Pi's Node environment. These are tool roles, not minimum-version claims. Linux support has not been verified here.

From this repository, install into an existing Git project:

```bash
bash bin/qwb-init.sh /path/to/project
```

The installer copies templates and runtime scripts into `<project>/qwbuddy/`, adds role and task files, and installs the Pi extension and Claude Code hook where possible. It preserves existing `qwbuddy/config.sh` and `qwbuddy/workers.sh`; check its output for partial installation. Each worker has one `qwb_worker name herdr arg...` or `qwb_worker name pane-run executable arg...` declaration in `workers.sh`. Bash arguments retain spaces, empty strings, and literal special characters. Existing projects using `QWB_WORKER_LAUNCH` or `QWB_WORKER_ARGS` must explicitly run `bash bin/qwb-init.sh --migrate-worker-config /path/to/project` from this repository. Migration backs up `config.sh` and refuses old pane commands whose shell interpretation cannot be preserved. If an existing `config.sh` has no legacy launch keys but lacks `workers.sh`, ordinary init leaves it untouched and reports that workers must be declared manually before dispatch.

Declare checks in the target project's `qwbuddy/config.sh`. For an existing pnpm project, for example:

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

Start the controller in the project root and have it read all of `qwbuddy/QWBUDDY.md`. It identifies Claude Code, Codex, or Pi before acquiring the controller lock; an unknown harness stops without taking the lock. A supported controller then acquires the lock, checks unfinished tasks, and selects its watch path. Create `tasks/YYYY-MM-DD-topic.md` from `qwbuddy/TASK.md`, with normal and failure-path acceptance scenarios. The controller can dispatch it with:

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker codex
```

The controller runs the relevant project gate and records the result; a worker's completion claim is not acceptance. See [the controller guide](templates/QWBUDDY.md) for lock, review, and worktree procedures.

## One watch path per controller

Claude Code checks the installed `.claude/settings.json` Stop hook and resumes through its next Stop event. Pi's bundled source `templates/pi-extensions/qwb-watch.ts` installs to the target project's `.pi/extensions/qwb-watch.ts`; restart Pi or run `/reload` after installation. Its `session_start` or a later `turn_end` after acquiring the controller lock starts the watch; progress arrives as a `[qwb-wake]` follow-up. Codex keeps `bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000` in a foreground tool-call loop: exit 2 handles progress, 124 starts another wait, and 0 ends this watch round. On 0, check the output, controller-lock owner, and ledger before concluding no task is open; an orphan-watch message or unclear ownership requires the lock recovery steps in the controller guide. An interrupted loop requires a new startup. An unknown controller harness is unsupported; identify it before taking the lock or starting a watch.

Use `bash qwbuddy/bin/qwb-status.sh` to inspect the ledger and watch diagnostics. A health result of “unknown” requires investigation of the failed query, installation, and controller lock; it does not authorize another watch path. The status output alone cannot prove that a Codex foreground call is still waiting or that a Claude hook is missing between Stop events. A controller that exits must be started again. The runtime retains visible-tab commands for manual diagnosis; they are outside the controller startup path.

Project-root and watch tabs use `QWB_WORKSPACE` from the target project's `qwbuddy/config.sh`, then a non-linked `herdr workspace list` entry matching the project root, then the caller's workspace with a warning. Worker tabs for linked Git worktrees use that worktree's own Herdr Space, which must be visible before dispatch. An unknown configured workspace or a linked task Space is rejected. Across projects with no root match, deliberately configure the target project's main workspace ID in that file; do not copy the controller's current ID blindly. The scripts source `config.sh`, so setting `QWB_WORKSPACE` only in the command environment does not override its assignment there.

## Evidence and roadmap

At source commit `1c500b38c014be9e55aa33fede2735ebaaf17d16`, the controller recorded on macOS: `fast` 1.38 s, `full` 88.35 s, smoke 567 PASS, review-identity PASS, and lint PASS. Its environment had Node v26.8.1, ShellCheck 0.11.0, Python 3.14.6, and Herdr 0.9.1. These are observations for that source and machine, not speed targets, minimum versions, or proof for this documentation commit. This ticket's executor runs only fast and lint.

[The E2E runbook](docs/E2E-RUNBOOK.md) covers an earlier `e917008` baseline and records manual intervention on first dispatch. It does not verify an unattended current-source run. Production use remains under review. Current-source unattended device verification, first-run trust handling, long-running watch and restart behavior, and production dogfooding remain open.

Repository layout: `bin/` has installer and runtime scripts (11 shell files at the cited baseline); `templates/` has the guide, task and role templates, configuration, and Pi extension; `tests/` has smoke and contract checks; `docs/` has design, review, and historical E2E records; `tasks/` is the ledger.
