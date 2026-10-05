# Q-Wolf Buddy (`qwbuddy`)

[简体中文](README.zh.md) · [MIT License](LICENSE)

Q-Wolf Buddy coordinates coding agents within a repository. Markdown task ledgers record requirements and progress, Git worktrees isolate worker changes, and Herdr provides visible agent sessions. The controller dispatches work, checks results independently, arranges review, and decides whether to land changes.

Five roles: controller, deputy controller (`规划`), worker (`执行者`), gatekeeper (`门禁`, coordinating review and tests), and adviser (`顾问`, consulted for major planning decisions). For the standing-role flow from intake through landing, read the installed `qwbuddy/roles/常驻流程.md` ([source](templates/roles/常驻流程.md)).

## Capabilities and limits

- `qwb-run.sh` checks Given/When/Then acceptance scenarios, records their fingerprint, and dispatches a worker into a task worktree by default.
- Workers append progress and evidence to the **main project's** ledger. The controller runs the project's declared checks before accepting work.
- `qwb-wake.sh` monitors unfinished tasks. Supported controllers are Claude Code with a Stop hook, Pi with the bundled extension.
- `qwb-status.sh` reports ledger and watch status; `qwb-lock.sh` maintains controller ownership.

A controller process that exits is not automatically restored. Individual tasks may need human input. Passing tests alone does not establish production readiness.

## Requirements and setup

Runtime scripts use Bash, Git, Herdr, Perl with standard modules, and common shell tools including `shasum`. The installer uses Python 3 to merge the Claude Code Stop hook into `.claude/settings.json`; it reports a missing hook if Python 3 is unavailable. Optional `--worker auto` routing uses `jq` and a configured Typesafe API key. The selected agent CLI and project gate commands must also be available. The checks below use ShellCheck; Pi's extension runs in Pi's Node environment. These are tool roles, not minimum-version claims. Linux support has not been verified here.

From this repository, install into an existing Git project:

```bash
bash bin/qwb-init.sh /path/to/project
```

The installer copies templates and runtime scripts into `<project>/qwbuddy/`, adds role and task files, and installs the Pi extension and Claude Code hook where possible. It preserves existing `qwbuddy/config.sh` and `qwbuddy/workers.sh`; check its output for partial installation. Each worker has one `qwb_worker name herdr harness -- arg...` or `qwb_worker name pane-run executable arg...` declaration in `workers.sh`; legacy `qwb_worker name herdr arg...` declarations use the worker name as the harness. Fixed Pi profiles must explicitly declare `--provider`, `--model`, and `--thinking`; all template Pi workers use Magpie; `pi-sol-high` uses `--provider magpie --model codex/gpt-6.1-sol --thinking high`. Independent review requires a different model and native session; switching roles in one session is not independent review. Model comparison ignores provider prefixes, letter case, and reasoning effort; `family` is optional metadata. Bash arguments retain spaces, empty strings, and literal special characters. Existing projects using `QWB_WORKER_LAUNCH` or `QWB_WORKER_ARGS` must explicitly run `bash bin/qwb-init.sh --migrate-worker-config /path/to/project` from this repository. Migration backs up `config.sh` and refuses old pane commands whose shell interpretation cannot be preserved. If an existing `config.sh` has no legacy launch keys but lacks `workers.sh`, ordinary init leaves it untouched and reports that workers must be declared manually before dispatch.

Declare checks in the target project's `qwbuddy/config.sh`. For an existing pnpm project, for example:

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

Start the controller in the project root and have it read all of `qwbuddy/QWBUDDY.md`. It identifies Claude Code or Pi before acquiring the controller lock; an unknown harness stops without taking the lock. A supported controller then acquires the lock, checks unfinished tasks, and selects its watch path. Create `tasks/YYYY-MM-DD-topic.md` from `qwbuddy/TASK.md`, with normal and failure-path acceptance scenarios. The template grants no startup authorization: before first dispatch of a legacy task, the controller must explicitly record the authorization in an `implementation-authorized:` header and a positive integer `dispatch-budget:` header. The controller can dispatch it with:

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker pi-sol-high
```

The controller runs the relevant project gate and records the result; a worker's completion claim is not acceptance. See [the controller guide](templates/QWBUDDY.md) for lock, review, and worktree procedures.

**Testing notes:** Offline repository tests fail closed against real Herdr if a stub disappears. Their temporary files stay under the repository's `.qwb-tmp/`. The repository root path must fit within 89 bytes, or socket-based tests reject it at startup. New test files must be explicitly connected to a test entry point.

## One watch path per controller

Claude Code checks the installed `.claude/settings.json` Stop hook and resumes through its next Stop event. Pi's bundled source `templates/pi-extensions/qwb-watch.ts` installs to the target project's `.pi/extensions/qwb-watch.ts`; restart Pi or run `/reload` after installation. Its `session_start` or, after acquiring the controller lock later, `agent_settled` (when Pi will no longer continue automatically) starts the watch; actionable changes arrive as a `[qwb-wake]` follow-up; for legacy running tasks whose worker is not lost, `working:` records progress without waking the controller, and timer retries start from the later of the ticket modification time and latest wake timestamp (disabled in quiet mode). After an exit 2 follow-up for a legacy task, the watch restarts only at `agent_settled`; for migrated tasks, a `[qwb-handoff]` summary resumes the single code supervisor as soon as the delivery API accepts it. An unknown controller harness is unsupported; identify it before taking the lock or starting a watch.

Use `bash qwbuddy/bin/qwb-status.sh` to inspect the ledger and watch diagnostics. A health result of “unknown” requires investigation of the failed query, installation, and controller lock; it does not authorize another watch path. The status output alone cannot prove that a Claude hook is missing between Stop events. A controller that exits must be started again. The runtime retains visible-tab commands for manual diagnosis; they are outside the controller startup path.

Project-root and watch tabs use `QWB_WORKSPACE` from the target project's `qwbuddy/config.sh`, then a non-linked `herdr workspace list` entry matching the project root, then the caller's workspace with a warning. Worker tabs for linked Git worktrees use that worktree's own Herdr Space, which must be visible before dispatch. An unknown configured workspace or a linked task Space is rejected. Across projects with no root match, deliberately configure the target project's main workspace ID in that file; do not copy the controller's current ID blindly. The scripts source `config.sh`, so setting `QWB_WORKSPACE` only in the command environment does not override its assignment there.

## Evidence and roadmap

On this macOS machine (Darwin 27.0.0), the controller measured commit `20ea2cc`: `fast` at 2.85 s; smoke alone at 190.13 s and 191.28 s across two runs, 804 PASS / 0 FAIL, with 95 section headings (the final numbered section is 88, including lettered subsections); and the then-sequential full gate at 574.34 s (456.58 s on an earlier run the same day), 844 PASS / 0 FAIL. After the four stages were made concurrent, the full gate at commit `c2079f0` took 502 s at a machine load of about 55, 844 PASS / 0 FAIL; before merging, the candidate passed five consecutive runs in an isolated worktree at 385–502 s (load 5–47), while the sequential version took 769 s and 1044 s in two runs the same night (load 13–23). At commit `4bdd2fd` the full gate took 429 s, 859 PASS / 0 FAIL. The full gate starts smoke, review-identity, lint, and `tests/collab-all.sh` (15 checks) concurrently, then prints each stage's complete output in that order. This environment had Herdr 0.9.3, Pi 1.0.2, and Bash 5.3.20 (with `/bin/bash` 3.2.57 used for syntax and compatibility checks). Per-ticket evidence and the comparison with the starting point are in [the audit report](docs/reviews/2026-10-03-qwb-full-audit-r1.md). These are records for the cited source and machine, not speed guarantees, minimum versions, or test evidence for later commits.

[The E2E runbook](docs/E2E-RUNBOOK.md) records an earlier baseline with manual intervention. Historical controller runs and cleanup drills are kept under `docs/reviews/`. The new worker roster passed one real run at commit `4bdd2fd`: a Claude Code controller (`claude-opus-5-5` / `medium`) with a Pi worker (Sol / `high`), all 14 assertions PASS. A Pi controller with a Claude Code worker completed the flow at `2183765` but failed one watch assertion and was not rerun after the fix. The same pairing passed again at `57d6e7a`, where dispatch now confirms that the worker started. Standing roles (planning, gate) were drilled once on a real machine on 2026-10-05: role start, authorization, ticket creation and dispatch worked, the chain broke after the worker delivered, and gate review was never reached; the fixes are merged at `44ab8ac`, which passed another real run. A second drill at `59f6734` reached gate approval, landing and cleanup, but the controller had to read the source and bypass the official landing wrapper; those fixes are merged at `adfb7b4` (full gate and the single-worker real run pass). A third drill at `adfb7b4` completed the whole chain in 15 minutes with no manual intervention and no bypass, but the controller still had to read script source in two places to learn the authorization payload shapes; documentation and refusal-message improvements are in progress. First-run trust handling, long-running watch and restart recovery, land cleanup for migrated collaboration tickets, and production trials remain to be done. The real E2E entry accepts Pi and Claude Code workers and controllers; Claude Code defaults to `claude-opus-5-5` / `medium`, and Pi to `magpie/codex/gpt-6.1-sol` / `high`. Workers use Pi Sol / `high` or Claude Opus 5.5 / `medium`. Only the controller runs real E2E.

Repository layout: `bin/` has installer and runtime scripts (16 shell files in this source); `templates/` has the guide, task and role templates, configuration, and Pi extension; `tests/` has smoke and contract checks; `docs/` has design, review, and historical E2E records; `tasks/` is the ledger.
