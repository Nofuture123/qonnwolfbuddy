# 任务书：QW buddy MVP 实现（templates/ + bin/）

```
任务 id:  qwbuddy-mvp
state:    running
派发:     主控（pi / qonnwolfbuddy 会话）→ 执行者（Terra high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-15-qwbuddy-mvp.md（绝对路径，工人只追加，不改他人行）
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/qwbuddy-mvp/（隔离副本，代码改动只在这里）
分支:     qwbuddy-mvp
```

---

## 1. 背景

本仓 `qonnwolfbuddy` 是 **QW buddy 的母本仓**。设计已定稿并经过独立审核，**尚未写一行实现代码**（当前只有 `README.md` 与 `docs/` 三份文档）。

本票的任务：按设计写出 `templates/` 与 `bin/`，让 QW buddy 第一次可以真的装进一个项目。

**先读这三份文档，它是架构真相，冲突时以它为准：**

- `docs/DESIGN.md`——架构（机制、职责、布局、MVP 边界）
- `docs/DECISIONS.md`——每条结论的理由与**被否掉的替代方案**（被否掉的方案不要再实现）
- `docs/reviews/2026-09-15-astra-review.md`——独立审核（6 条修正已并入 DESIGN）

**本仓没有 package.json，不是 Node 项目。这是一个纯 shell + markdown 的仓库。**

---

## 2. 交付物

### 2.1 `templates/QWBUDDY.md`——主控总说明书

装进项目后就是主控的行为准则。必须覆盖：

- **开局点名**：读到这份文件后先做什么（读 `tasks/` 账本、列出未结项、报当前状态）
- **三层责任**：执行层（工人）/ 主控 / 运行时（脚本）——谁的保证由谁负责（DESIGN §2）
- **账本规矩**：`tasks/` 是唯一真相；任务书派发；工人往**主账本绝对路径**追加状态行
- **状态行约定**：`working:` / `done:` / `blocked:` / `needs-decision:`
- **任务书 `state:` 字段**（见 §4.1，这是唤醒机制的判定依据）
- **验货门**：不采信工人自述；主控独立跑项目自己的检查命令；把「跑了什么、结果、结论」写进账本（主控自干的小活同样留一行）
- **worktree 四步规范**（DESIGN §3.2）：开 / 收·成功 / 收·废弃（打 `archive/<任务id>` 标签）/ 留·例外（必须点名）
- **身份切换**：角色文件在哪、怎么切、只是行为约定不是权限隔离
- **零通知使用者**：不许做任何面向人的推送
- **MVP 边界**：只保证「存活且空闲的主控」能被唤醒；主控死了由使用者重启后从账本续接（DESIGN §10）

性质：**产品中立**——不假定主控是 Claude Code / Pi / Codex 中的哪一个。不写死任何一家的命令。

### 2.2 `templates/roles/` 四份角色文件

`主控.md` / `审核者.md` / `执行者.md` / `咨询师.md`

每份写三样（DESIGN §6）：

- **立场**：这个身份干什么
- **产出物**：产出什么、标什么
- **禁止事项**：不许干什么

要点：主控禁自己写实现（小活除外）；审核者只挑错不提方案、不改代码；执行者只干票内的事、不改白名单外文件；咨询师只给判断、不派活不改代码。并写明**根级 `QWBUDDY.md` 的禁令不可被角色文件推翻**、**同一会话换角色 ≠ 独立审核**（审核必须换模型家族）。

### 2.3 `templates/config.json`

工人表 + 派工规则 + 超时。至少：

- `workers`：codex / pi / claude 三家的启动命令、能力档、擅长（DESIGN §7.1）
- `routing`：派工规则（自然语言或结构化皆可，但必须能被主控读懂）
- `timeouts`：**超时一律毫秒**（`agent_wait_ms` 等；30 分钟 = `1800000`）——审核修正 ⑤，不要出现 `"30m"`
- `ledger`：账本相对路径（`tasks`）、状态行前缀
- `hard_rules`：工人一律 Herdr 窗口交互式运行、**禁 headless**；审核必须换模型家族；零通知

JSON 必须 `python3 -m json.tool` 能解析（或 `jq` 可用时 `jq .`）。

### 2.4 `templates/agents-hook.md` / `templates/claude-hook.md`

分别是要追加进目标项目 `AGENTS.md` / `CLAUDE.md` 的钩子片段。内容：几行、告诉 AI「本项目用 QW buddy，说『你现在是 QW buddy』就读 `qwbuddy/QWBUDDY.md`」并指向账本。**短**（每份不超过 15 行），不要复制整本书。

### 2.5 `bin/` 四个脚本

风格：POSIX `sh` 或 `bash` 皆可，但**四个脚本保持一致**；`#!/usr/bin/env bash`；`set -euo pipefail`；无外部依赖（只用 coreutils + git + herdr）；中文注释与中文输出。

| 脚本 | 职责 | 规模 |
|---|---|---|
| `qwb-init.sh` | 装进新项目：复制 `templates/QWBUDDY.md` + `roles/` 到 `<项目>/qwbuddy/`、把 `bin/` 复制成 `<项目>/qwbuddy/bin/`、建 `tasks/` 与 `tasks/lessons/`、把钩子片段追加进 `AGENTS.md` / `CLAUDE.md`（**幂等：已装过不重复追加**） | ~60 行 |
| `qwb-run.sh` | 派发 + 记账：给定任务 id 与工人，在指定 worktree/窗口里派活，并把任务、窗口、派发时间、`state: running` 写进任务书 | ~110 行 |
| `qwb-wake.sh` | 值守：以**账本未结项**为准循环（DESIGN §4.3），有未结项就 `herdr` 叫醒主控窗口；同一项不重复叫；`--dry-run` 只报告不叫 | ~60 行 |
| `qwb-status.sh` | 点名 + 汇报：读账本列出全部任务与状态，合并 `herdr` 的窗口/状态输出，打印给人看 | ~80 行 |

**四个脚本都必须支持 `--help`。**

---

## 3. 硬约束（违反即验收不通过）

1. **零通知使用者**：任何消息队列、桌面通知、钉钉、弹窗、邮件——一律不做。唯一的"叫人"动作是 `herdr` 把主控窗口叫醒（DESIGN §4.4、DECISIONS §6）。
2. **无队列、无 ACK 协议、无数据库、无守护进程、无 cron**——账本承担该职责（DECISIONS §13）。
3. **只用 Herdr**，不出现 tmux / zellij / orca / cmux。
4. **超时单位毫秒**，任何地方不许写 `30m` 之类。
5. **禁用 headless 工人**：启动命令里不得出现 `-p` / `--print` / `--exec` / `codex exec` 之类的非交互标志。
6. 不许引入 Node / Python 运行时依赖（`qwb-*.sh` 必须纯 shell；`python3` 只允许在测试里用于校验 JSON）。
7. 不修改 `docs/` 下的任何文件。
8. 不修改本仓 `README.md` 里的设计内容（`README.md` 的"下一步/布局"章节可以在完工后由主控更新，**你不要动它**）。

---

## 4. 主控已定的设计决策（不要自己另发明，直接照做）

### 4.1 任务书里的 `state:` 字段——唤醒机制的判定依据

DESIGN §4.3 要求"读账本列出未结项"，但没有定义**机器怎么认出来**。现规定：

- 每份任务书（`tasks/YYYY-MM-DD-<主题>.md`）**头部有一个字段行**：`state: <值>`
- 值域固定五个：`running` / `blocked` / `needs-decision` / `done` / `verified`
- **未结项** = `state` ∈ {`running`, `blocked`, `needs-decision`}
- **工人不改 `state:`**（工人只追加 `working:` / `done:` / `blocked:` 状态行）
- **`done` → `verified` 只能由主控改**（因为不采信工人自述，DESIGN §3.2）
- `qwb-wake.sh` 与 `qwb-status.sh` 都按这个字段工作

### 4.2 叫醒动作的确切写法

用 `herdr pane run <主控pane_id> "<提示文本>"`，提示文本固定为一句指向账本的话 + 未结项的任务 id 列表（不要长篇大论）。主控 pane id 从 `config.json` 或 `qwb-run.sh` 记账时记录的窗口信息里读。

### 4.3 同一项不重复叫

值守脚本必须把"已经叫过哪一项"记在某处，直到该项 `state` 变化才允许再叫。最简做法：叫过一次就在账本该任务书里追加一行 `wake: <时间戳> state=<值>`；下次发现该项的 `state` 与最近一次 `wake:` 行的 `state` 相同时不再叫。**不要另建状态文件。**

---

## 5. 验收门（你必须先自己跑通，主控会独立重跑）

写一个 `tests/smoke.sh`（可以 bash 写），它必须：

1. 对 `bin/` 四个脚本跑 **`bash -n`** 语法检查
2. 若本机有 `shellcheck`，跑 **`shellcheck`** 且零告警（没有就跳过并在输出里说明跳过）
3. 在 `mktemp -d` 的**临时目录**里当假项目，跑 `qwb-init.sh`，断言：
   - `qwbuddy/QWBUDDY.md`、`qwbuddy/roles/*.md`（4 个）、`qwbuddy/config.json`、`qwbuddy/bin/qwb-*.sh`（4 个）都存在
   - `tasks/` 与 `tasks/lessons/` 存在
   - `AGENTS.md` 与 `CLAUDE.md` 里出现了钩子
   - **再跑一次 `qwb-init.sh`，断言钩子没有重复追加**（幂等）
4. 跑 `qwb-status.sh` 对空账本 → 不报错、退出码 0
5. 断言 `config.json` 是合法 JSON（用 `python3 -m json.tool`）
6. 造一份假任务书（`state: running`），跑 `qwb-wake.sh --dry-run`，断言它把这份任务列为**未结项**；把 `state` 改成 `verified` 再跑，断言不再列为未结项
7. **不真的去启动 herdr 窗口、不真的叫醒任何东西**（冒烟测试必须能在没有 herdr 的干净环境里跑）

`tests/smoke.sh` 最后打印一行 `SMOKE PASS` 或 `SMOKE FAIL`，并**用退出码表达结果**（0 通过 / 非 0 失败）。

**注意**：脚本要能在 Herdr 之外运行时不炸（用于测试）。`qwb-wake.sh` 在没有 `herdr` 命令时必须给出清晰错误并退出非 0，而不是静默假成功。

---

## 6. 报告要求

每完成一个阶段，往**主账本绝对路径**追加一行状态行：

```
/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-15-qwbuddy-mvp.md
```

格式（只追加，不改别人的行）：

```
working: 已完成 templates/QWBUDDY.md 与 roles/×4
done: 全部交付物完成。<跑了什么检查> → <结果>。<同时给出关键文件路径与行数>
blocked: <卡在哪，需要什么>
needs-decision: <需要主控判断的选项>
```

最后一条必须是 `done:`，并附上**你实际跑过的命令与原始结果**（不许只说"测试通过"）。

---

## 7. 禁止事项

- 不要扩大范围：不做 DESIGN §11「明确不做」里的任何东西
- 不要动 `docs/`、不要动本仓 `README.md`、不要动主工作区的代码（只在 worktree 里干）
- 不要为了"以后可能需要"加抽象层、配置文件、插件系统
- 不要写守护进程、循环轮询主循环、状态数据库
- 不要在任务书里改 `state:` 字段

---

## 8. 主控验收方式（预告）

主控会在主工作区独立重跑：`bash -n` ×4、`shellcheck` ×4、`bash tests/smoke.sh`（检查退出码），并**亲自读一遍**四个脚本与 `QWBUDDY.md`，确认没有 `30m`、没有 headless、没有通知通道、没有队列。通过后才合并落地。

