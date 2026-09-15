# Q-Wolf Buddy (`qwbuddy`)

[English](README.md) | [简体中文](README.zh.md)

> Lightweight, in-repo AI controller manual and runtime for single projects. Specify requirements; QW buddy manages task dispatching, worker isolation, automated wakeups, acceptance gates, and ledger accounting.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash%203.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/tests-405%20passed-brightgreen.svg)]()
[![Gates](https://img.shields.io/badge/quality%20gates-fast%200.7s%20%7C%20full%2045s-orange.svg)]()

---

## What and Why

Working with coding agents (Claude Code, Codex, Pi, Devin) inside real repositories reveals three recurring friction points:

| Problem | Symptom | How QW Buddy Solves It |
|---|---|---|
| **Controller Goes Silent** | Assign a task to a background worker. When the worker finishes 10 minutes later, the controller's interactive turn has ended. The controller never wakes up to verify or land changes. | Deploys a thin sentinel script (`qwb-wake.sh`) that monitors ledger state and re-prompts the idle controller via terminal multiplexing (`herdr`). |
| **No Identity Switching** | Single sessions drift between architecting, reviewing, implementing, and consulting without boundaries, leaking context and expanding scope. | Codifies explicit role playbooks (`qwbuddy/roles/`). Enforces that reviews require a different model family and separate native session. |
| **No Dispatch Standards** | Tasks get dumped into arbitrary agent sessions without explicit acceptance criteria, isolated workspaces, or failure scenarios. | Enforces task tickets (`tasks/YYYY-MM-DD-*.md`) with Given/When/Then scenarios, frozen baselines, and automatic git worktree isolation. |

**Developer role**: Specify requirements. Delegate planning, execution, verification, and landing to the controller.

---

## How It Works

### Architecture

```
+-------------------------------------------------------------------------+
|                            Developer (User)                             |
|                        Specify requirements only                        |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                     Controller (AI Session in Herdr)                    |
|  - Creates task ticket (tasks/YYYY-MM-DD-<topic>.md)                    |
|  - Runs qwb-run.sh to dispatch worker into isolated git worktree        |
|  - Independently executes acceptance checks upon wakeup                 |
+-------------------------------------------------------------------------+
            ^                                                |
            | Wakeup prompt                                  | Dispatch task
            | ("Check ledger")                               v
+-----------------------+                        +------------------------+
|   Sentinel / Daemon   |                        |     Worker (Agent)     |
|     (qwb-wake.sh)     |                        |      (Herdr Pane)      |
|  - Inspects ledger    |                        |  - Runs in worktree    |
|  - SHA1 fingerprint   |                        |  - Appends status lines|
|  - Fallback re-wake   |                        |    (working:/done:)    |
+-----------------------+                        +------------------------+
            |                                                |
            | Reads unclosed tasks                           | Appends status
            v                                                v
+-------------------------------------------------------------------------+
|                           Ledger (tasks/*.md)                           |
|        Single source of truth: task specs, evidence, and audit logs      |
+-------------------------------------------------------------------------+
```

### Core Mechanisms

| Mechanism | Component | Enforced Behavior |
|---|---|---|
| **Fingerprint Wake & Fallback** | `qwb-wake.sh` | Computes progress fingerprint `sha1(state + last_status_line)`. Skips re-waking if fingerprint is unchanged. Re-wakes unconditionally after `QWB_REWAKE_MS` (default 30 min) to catch crashed workers. |
| **Suspicion Gate & Revision** | `qwb-run.sh` | Traps specification defects via `blocked: spec-defect:`. Blocks redispatch until controller documents `working: spec-resolved:`. Requires `--revise-scenarios=<reason>` to update frozen specs. |
| **Scenario Freezing** | `qwb-run.sh`, `qwb-lint.sh` | Requires BDD acceptance scenarios (Given/When/Then + at least one failure path). Embeds `scenarios-fp:` at dispatch. Fails lint if scenarios are edited post-dispatch. |
| **Worktree Lifecycle** | `qwb-worktree.sh` | Dispatches work into isolated `.worktrees/<task-id>/` by default. Provides 3 clean exit paths: `--merged` (rebase/merge), `--archive` (tag and remove), or `--keep` (explicit conflict holding). Validates HEAD OID before deletion. |
| **Review Identity Audit** | `qwb-lint.sh` | Verifies independent review tickets (`review-required: yes`). Checks that `review-impl` and `review-rev` use different model families and distinct native session IDs. Rejects same-family audits. |
| **Dual Quality Gates** | `qwb-test.sh` | Executes project-defined fast gate (`QWB_GATE_FAST`, ~0.7s) on single changes and full gate (`QWB_GATE_FULL`, ~45s) before merge. Fails closed if gates are undefined. |

---

## Quickstart

### 1. Install into a Target Project

Execute the installer from the `qonnwolfbuddy` repository root:

```bash
# Idempotent: copies templates, initializes tasks/ ledger, and writes hooks
bash bin/qwb-init.sh /path/to/target-project
```

### 2. Declare Quality Gates

Open `/path/to/target-project/qwbuddy/config.sh` and specify your project's test commands:

```bash
# Example for a Node / TypeScript project:
QWB_GATE_FAST='npm run lint'
QWB_GATE_FULL='npm run lint && npm test'
```

Verify that the gates execute cleanly:

```bash
cd /path/to/target-project
bash qwbuddy/bin/qwb-test.sh fast    # Runs fast gate (must exit 0)
bash qwbuddy/bin/qwb-test.sh full    # Runs full gate (must exit 0)
```

### 3. Initialize Controller and Run Roll Call

Open your preferred coding assistant (Claude Code, Pi, or Codex) inside the target project directory and instruct it:

```text
You are now QW buddy. Read qwbuddy/QWBUDDY.md and assume the Controller role.
```

Inspect active tasks, worker panes, and sentinel status:

```bash
bash qwbuddy/bin/qwb-status.sh
```

### 4. Dispatch a Task Ticket

Write a task specification in `tasks/YYYY-MM-DD-<topic>.md` with an acceptance scenario block:

```markdown
## 验收场景

Scenario: user_successful_export
  Given valid data in the database
  When the export endpoint is triggered
  Then an export artifact is written to disk

Scenario: user_export_invalid_format_fails (Failure path)
  Given an unsupported export format parameter
  When the export endpoint is triggered
  Then return exit code 1 with an informative error
```

Dispatch the ticket to a background worker in an isolated worktree:

```bash
# Worker must be declared in qwbuddy/config.sh QWB_WORKERS (default: codex pi claude).
# To use Devin, add it first:  QWB_WORKERS="codex pi claude devin"
bash qwbuddy/bin/qwb-run.sh \
  --project . \
  --task YYYY-MM-DD-<topic> \
  --worker codex \
  --name feat-export
```

Launch the sentinel daemon to watch the ledger and re-prompt the controller:

```bash
bash qwbuddy/bin/qwb-wake.sh --ensure --pane <controller-pane-id>
```

---

## Design Principles

### Three Yardsticks

1. **Whose state is it? (谁的状态归谁)**  
   Keep vendor-specific state (context windows, session caches, token buffers) inside the vendor harness. Store project state (task tickets, execution progress, verification logs, lessons learned) outside the AI model in plain Markdown (`tasks/*.md`).
2. **Thin is future-proof (薄即抗淘汰)**  
   Harnesses evolve rapidly and will absorb prompting and basic waiting routines. QW buddy only implements what single-vendor harnesses cannot: cross-model task routing, persistent project memory, and adversarial acceptance discipline.
3. **Rules aren't written on paper (规范不写在纸上)**  
   Replace written guidelines with executable test assertions. Every policy is checked by `qwb-lint.sh`, verified by negative tests in `tests/smoke.sh`, and validated through automated gates.

### What We Explicitly Do Not Do

| Non-Goal | Decision Rationale |
|---|---|
| **No Central Registries or Multi-Repo Sync** | Designed for self-contained single projects. The repository boundary is absolute. |
| **No Human Notifications** | Sends zero notifications to Slack, DingTalk, or desktop alerts. Controllers wake up; humans sleep. |
| **No Background Databases or Message Queues** | Markdown files in `tasks/` serve as persistent queue, state ledger, and audit log. |
| **No Headless-Only Workers** | Workers run in interactive terminal panes (`herdr`) to preserve human visibility and debuggability. |
| **No Auto-Restart of Dead Controller Processes** | Wakes running, idle controllers. If a machine reboots, the user restarts the session from the ledger. |
| **No Vendor Plugins or Proprietary Hooks** | Pure POSIX / Bash implementation with zero proprietary extensions. |

---

## Project Layout

```
qonnwolfbuddy/
├── README.md               # Project documentation and specifications
├── qwb.config.sh           # Quality gate declaration for this repository
├── docs/                   # Architecture, runbooks, and audit reports
│   ├── DESIGN.md           # Authoritative system architecture design
│   ├── DECISIONS.md        # Architecture Decision Records (ADRs)
│   ├── E2E-RUNBOOK.md      # Real end-to-end closed-loop runbook
│   └── reviews/            # 10 independent audit & advisory reports
├── templates/              # Assets installed into target repositories
│   ├── QWBUDDY.md          # Primary controller handbook
│   ├── TASK.md             # Task specification template with scenario blocks
│   ├── config.sh           # Worker table, timeouts, and gate definitions (Bash source)
│   ├── roles/              # Role playbooks: Controller, Reviewer, Executor, Consultant
│   ├── agents-hook.md      # Integration hook for AGENTS.md
│   └── claude-hook.md      # Integration hook for CLAUDE.md
├── bin/                    # Runtime executables (copied to <project>/qwbuddy/bin/)
│   ├── qwb-init.sh         # Installer (idempotent; copies templates and hooks)
│   ├── qwb-run.sh          # Dispatcher (scenario gate, worktree creation, logging)
│   ├── qwb-wake.sh         # Sentinel daemon (fingerprint dedup, fallback re-wake)
│   ├── qwb-status.sh       # Roll call, inspection, and status reporting
│   ├── qwb-lock.sh         # Atomic directory lock for controller
│   ├── qwb-worktree.sh     # Worktree lifecycle manager (list / finish)
│   ├── qwb-test.sh         # Fast & full quality gate test runner
│   └── qwb-lint.sh         # Repo linter (state domains, dead configs, ASCII traps)
├── tests/                  # Verification test suites and fixtures
│   ├── smoke.sh            # Smoke test suite with negative regression assertions
│   ├── review-identity.sh  # Independent reviewer identity verification tests
│   └── fixtures/herdr/     # Real captured Herdr CLI baseline fixtures
└── tasks/                  # Repository ledger and post-mortem lessons
    └── lessons/            # Post-mortem incident analysis and countermeasures
```

---

## Testing and Real Agent Verification

### Test Suite Performance

Every commit is gated through executable tests. Undeclared gates fail with exit code 1.

| Gate | Execution Time | Scope | Command |
|---|---|---|---|
| **Fast Gate** | `~0.7s` | Shell syntax (`bash -n`) on all scripts + strict `shellcheck` with zero warnings | `bash bin/qwb-test.sh fast` |
| **Full Gate** | `~45s` | 405 assertions: smoke tests, contract validation, negative traps, identity checks, and lint | `bash bin/qwb-test.sh full` |

### Verified by Real Agents

- **Real Closed-Loop E2E**: Verified end-to-end using real Devin (SWE-2 Max) workers, live Herdr terminal tabs, shell sentinel, and Claude controller (`docs/E2E-RUNBOOK.md`). Confirmed automated wakeup on completion, independent acceptance, deliberate sabotage detection, and clean worktree removal.
- **9 Adversarial Audit Reports + 1 Advisory**: Hardened across multi-round independent reviews by different model families (GPT-6 Astra High/Medium, Claude Fable 5.1) documented in `docs/reviews/`, plus one model-family consultation that reshaped the spec-defect gate.
- **Critical Defects 6 → 0**: Eliminated all 6 critical vulnerabilities discovered during adversarial audits:
  1. *F3 Wakeup deadlocks*: Replaced static state tracking with SHA1 progress fingerprints.
  2. *F4 Sentinel crashes*: Handled terminal delivery failures without exiting the main loop.
  3. *G1 Detached HEAD loss*: Replaced branch-name assumptions with explicit HEAD OID tracking.
  4. *H1 TOCTOU races*: Added pre-deletion HEAD checks to prevent wiping concurrent worker commits.
  5. *F1 Silent worker hangs*: Added timeout fallback re-wake (`QWB_REWAKE_MS`) when a worker hangs without new status lines.
  6. *F2 File clobbering*: Converted snapshot overwrites to atomic in-place ledger updates.

---

## Roadmap

- [x] Complete core architecture specification and ADR records (`docs/DESIGN.md`, `docs/DECISIONS.md`)
- [x] Implement in-repo templates, role playbooks, and POSIX bash runtime scripts
- [x] Build 405-assertion test suite with contract validation and negative assertions
- [x] Validate real-world closed loop with live agents in terminal panes (`docs/E2E-RUNBOOK.md`)
- [x] Pass final multi-round independent review sign-off (`docs/reviews/2026-09-15-fable-终审.md`)
- [ ] Dogfood in production open-source repositories to gather developer workflow feedback
- [ ] Automate workspace trust handshakes for first-time agent CLI initialization

---

## License

Distributed under the [MIT License](LICENSE).
