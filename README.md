# 🐺 Q-Wolf Buddy (`qwbuddy`)

> **Stop babysitting your AI coding agents.**  
> Turn your existing Claude Code, Codex, Pi, and Devin into an **autonomous, self-verifying, sandbox-isolated engineering team** right inside your repository.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash%203.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/tests-405%20passed-brightgreen.svg)]()
[![Gates](https://img.shields.io/badge/quality%20gates-fast%200.7s%20%7C%20full%2045s-orange.svg)]()

<p align="center">
  🌐 <b>English</b> | <a href="README.zh.md">简体中文</a>
</p>

---

## 💡 What Pain Points & Core Problems Does It Solve?

When working with single-agent coding tools (Claude Code, Codex CLI, Cursor, Devin, etc.) in real codebases, developers face **4 fundamental blockers**:

1. **The "Human Polling Daemon" Trap**:  
   You assign a heavy task to a background worker and step away for coffee. 15 minutes later, the worker finished, but the **controller AI's interactive turn has ended and gone idle**. Nobody verifies the code, nobody merges the branch. The workflow freezes halfway. You are forced to babysit the terminal and manually type "Continue / Review". You become an organic message bus between two AI agents.
2. **The "Trashing the Working Tree" Risk**:  
   You ask an agent to fix a minor bug; it indiscriminately reformats 30 unrelated files, alters your package lockfiles, and pollutes your main branch. When running concurrent tasks, agents overwrite each other's uncommitted changes.
3. **The "False Green" AI Sycophancy Problem**:  
   Worker agents confidently boast: *"All tests pass, feature implemented!"* In reality, running the command reveals broken code, or worse, the agent generated a tautological test that always returns `true` to deceive the acceptance check.
4. **The "Grading Its Own Exam" Self-Review Fallacy**:  
   The same Claude or GPT session writes the implementation and then reviews its own code. Model-family blind spots mean that same-family reviews are superficial and miss critical vulnerabilities.

**The QW Buddy Solution: True AFK Coding (Away From Keyboard).**  
You specify requirements in Markdown. The system autonomously handles **task decomposition, dispatching into isolated sandboxes, automated wakeups upon completion, adversarial acceptance gates, and git landing**.

---

## 🥊 How Does It Compare to Grokbot & Traditional Coding Bots? What Improvements Were Made?

Unlike traditional coding bots, heavy multi-agent frameworks (CrewAI, AutoGPT), or cloud blackbox agents, QW Buddy was engineered with distinct design priorities and architectural improvements:

| Dimension | Traditional Coding Bots / Grokbot / Heavy Frameworks | QW Buddy Improvements & Advantages |
|---|---|---|
| **Architecture Weight & Dependencies** | Requires heavy Python environments, Docker containers, external databases, or cloud APIs; thousands of lines of code; complex setup. | **Ultra-Lightweight Zero Dependencies (98% Thinner)**: Just 8 POSIX Bash scripts (~1000 lines), zero external databases, installs into any project in 2 seconds. |
| **Workspace Isolation** | Most agents work directly in the active project directory; multi-tasking or rework pollutes the working tree; rollback is painful. | **Physical Git Worktree Isolation**: Every task gets a dedicated `.worktrees/<task-id>` sandbox automatically; main branch remains pristine. |
| **Completion Wakeup Loop** | Relies on manual polling or webhooks; sessions go idle and abandon the workflow. | **Millisecond Progress Fingerprint Sentinel (`qwb-wake.sh`)**: Tracks `sha1` progress fingerprints; automatically injects terminal prompts to wake the controller; 30-min timeout fallback. |
| **Acceptance Reliability** | Trusts worker self-reports or simple process exit codes; vulnerable to fake tests and sycophancy. | **Zero-Trust Independent Quality Gates**: Freezes Given/When/Then scenario fingerprints before dispatch; controller independently executes fast/full test suites at the repo root. |
| **Code Review Objectivity** | Same session prompts roles back-and-forth, or same-family models praise each other. | **Mandatory Cross-Model Family Auditing**: Implementation and review **must use different model families and distinct native session IDs** (e.g. Codex writes, Claude reviews); strictly enforced by `qwb-lint.sh`. |
| **Runtime Visibility** | Sealed inside Docker containers or remote web UIs; difficult to inspect or debug. | **Full Terminal Visibility (No Blackbox)**: Every agent runs in a real, interactive terminal pane (`herdr`); developers can inspect or take over at any second. |

---

## 🔀 Does It Solve "High-Concurrency Tasks"? — Multi-Agent Concurrency & Race Defense

> **Important Definition**: This is not about Web API "high QPS / network throughput". It specifically solves **"Concurrent Multi-Agent Engineering, Workspace Collision Defense, and Atomic State Accounting"** when multiple AI agents work on the same repository simultaneously.

When you dispatch multiple parallel tasks to different AI workers (e.g. one refactoring the backend, one building a frontend component, one revising documentation), QW Buddy provides industrial-grade concurrency guarantees:

1. **Worktree Parallelism (No Git Collisions)**:  
   Every task runs in its own Git Worktree. Multiple workers code simultaneously in independent physical directories without file locks, branch contention, or dirty git states.
2. **Atomic In-Place Ledger Updates (Eliminated Fatal Defect F2)**:  
   Multiple workers append status lines concurrently. Early prototypes suffered from snapshot overwrites erasing worker lines. QW Buddy was hardened through adversarial audits to use **in-place line replacement with post-write line count verification**, ensuring concurrent `done:` and evidence lines are never lost.
3. **TOCTOU Race Defense on Worktree Cleanup (Eliminated Fatal Defect H1)**:  
   When finalizing and removing a worktree, if a worker concurrently pushed a new commit, conventional scripts delete the new work. QW Buddy verifies the exact HEAD commit OID immediately prior to deletion; any concurrent commit triggers rejection and archives the tag safely.
4. **Controller Mutual Exclusion Lock (`qwb-lock.sh`)**:  
   Uses filesystem atomic primitives (`mkdir`) to prevent multiple controller sessions from issuing conflicting dispatch or acceptance commands simultaneously.
5. **Concurrent Event Waiting & Time Budgeting (`qwb-wake.sh`)**:  
   The sentinel daemon monitors multiple unclosed tasks concurrently, rotating wait events across active panes with millisecond time budgets to prevent busy-waiting loops.

---

## 🏗️ Technical Architecture

QW Buddy is organized into a clean 3-layer architecture, with the **plain-text Markdown ledger** serving as the Single Source of Truth:

```
+---------------------------------------------------------------------------------+
|                         1. Planning & Decision Layer                            |
|  - Developer: Specifies requirements in tasks/*.md using Given/When/Then format  |
|  - Controller AI: Runs in Herdr terminal; breaks down tasks, dispatches, & tests |
+---------------------------------------------------------------------------------+
           │                                                    ▲
           │ 1. qwb-run.sh dispatches task                      │ 4. qwb-wake.sh auto-wakes
           │    (locks scenarios-fp fingerprint)                │    (injects prompt: "Check ledger")
           ▼                                                    │
+---------------------------------------------------------------------------------+
|                         2. Isolated Execution Layer                             |
|  - Worker Agents (Codex / Devin / Pi): Run interactively in Herdr terminal tabs  |
|  - Physical Sandboxes (Git Worktrees): Each task runs in .worktrees/<task-id>/   |
|  - Restricted Behavior: Workers only write code & append working:/done:/blocked: |
+---------------------------------------------------------------------------------+
           │                                                    ▲
           │ 2. Appends status line & evidence                  │ 3. Scans unclosed tasks
           ▼                                                    │
+---------------------------------------------------------------------------------+
|                         3. State & Audit Layer                                  |
|  - Ledger (tasks/*.md): State machine (running / blocked / verified) & evidence  |
|  - Sentinel Daemon (qwb-wake.sh): Computes sha1(state + status_line) progress   |
|  - Quality Gates (qwb-test.sh / qwb-lint.sh): Enforces fast (~0.7s) / full (~45s)|
+---------------------------------------------------------------------------------+
```

---

## 🚀 Quickstart in 60 Seconds

### Step 1: Install into Your Project
Run the idempotent installer from the `qonnwolfbuddy` repository root:

```bash
bash bin/qwb-init.sh /path/to/your-project
```

### Step 2: Declare Quality Gates
Open `qwbuddy/config.sh` in your project and define your test commands (undeclared gates fail closed to prevent false greens):

```bash
# Example for a Node / TypeScript project:
QWB_GATE_FAST='npm run lint'
QWB_GATE_FULL='npm run lint && npm test'
```

### Step 3: Initialize Controller
Open your AI coding assistant (Claude Code, Pi, or Codex) inside your project root and send:

```text
You are now QW buddy. Read qwbuddy/QWBUDDY.md and assume the Controller role.
```

### Step 4: Dispatch a Task Ticket
Create your task ticket in `tasks/YYYY-MM-DD-<topic>.md` with an acceptance scenario block, then dispatch and start the sentinel:

```bash
# Dispatch into an isolated git worktree
bash qwbuddy/bin/qwb-run.sh --task 2026-09-16-feat --worker codex

# Start the sentinel daemon to watch the ledger and wake the controller
bash qwbuddy/bin/qwb-wake.sh --ensure --pane <controller-pane-id>
```
**Now you can step away from your keyboard.**

---

## 🛠️ Battle-Tested Quality Evidence

QW Buddy was built and hardened using its own mechanisms across multi-round adversarial audits:

- **405 Assertions (100% Green)**:
  - Fast Gate (`fast`, ~0.7s): Shell syntax (`bash -n`) + strict `shellcheck` with zero warnings.
  - Full Gate (`full`, ~45s): 405 assertions covering smoke tests, negative regression traps, contract validations, and lint.
- **Verified by Real Autonomous Agents**:
  - Validated end-to-end using real Devin (SWE-2 Max) workers, live Herdr terminal tabs, shell sentinel, and Claude controller (`docs/E2E-RUNBOOK.md`). Confirmed automated wakeup on completion, independent acceptance, deliberate sabotage detection, and clean worktree removal.
- **9 Adversarial Audit Reports + 1 Advisory**:
  - Hardened through multi-round independent reviews by different model families (GPT-6 Astra High/Medium, Claude Fable 5.1) documented in `docs/reviews/`, plus one architectural consultation.
- **Eliminated All 6 Critical Defects (Fatal 6 → 0)**:
  1. *F3 Wakeup deadlocks*: Replaced static state tracking with SHA1 progress fingerprints.
  2. *F4 Sentinel crashes*: Handled terminal delivery failures without exiting the main loop.
  3. *G1 Detached HEAD loss*: Replaced branch-name assumptions with explicit HEAD OID tracking.
  4. *H1 TOCTOU races*: Added pre-deletion HEAD checks to prevent wiping concurrent worker commits.
  5. *F1 Silent worker hangs*: Added timeout fallback re-wake (`QWB_REWAKE_MS`) when a worker hangs without new status lines.
  6. *F2 File clobbering*: Converted snapshot overwrites to atomic in-place ledger updates.

---

## 📂 Project Layout

```
qonnwolfbuddy/
├── README.md               # English documentation and project homepage
├── README.zh.md            # Chinese documentation and project homepage
├── docs/                   # Architecture specs, ADRs, E2E runbook, and 10 audit reports
├── templates/              # Assets installed into target repositories (QWBUDDY manual, templates, roles)
│   └── roles/              # Role playbooks: Controller, Reviewer, Executor, Consultant
├── bin/                    # Runtime executables (qwb-init, run, wake, status, worktree, test, lint)
├── tests/                  # 405-assertion test suite and real Herdr CLI fixtures
└── tasks/                  # Repository ledger and post-mortem lessons
```

---

## 🧭 Roadmap

- [x] Complete core architecture specification and ADR records (`docs/DESIGN.md`, `docs/DECISIONS.md`)
- [x] Implement in-repo templates, role playbooks, and POSIX bash runtime scripts
- [x] Build 405-assertion test suite with contract validation and negative assertions
- [x] Validate real-world closed loop with live agents in terminal panes (`docs/E2E-RUNBOOK.md`)
- [x] Pass final multi-round independent review sign-off (`docs/reviews/2026-09-15-fable-终审.md`)
- [ ] Dogfood in production open-source repositories to gather developer workflow feedback
- [ ] Automate workspace trust handshakes for first-time agent CLI initialization

---

## 📄 License

Distributed under the [MIT License](LICENSE).
