# 真实 E2E 扩展到 Claude Code 与 pi 主控 r1

- **要求**：使用者 2026-09-24 要求真实 E2E 除 Codex 外，把 Claude Code 和 pi 也作为主控加入。花费已获使用者同意，同 r3。
- **审核与派工**：Claude Code（Opus 5.5，Herdr pane `wF2:p3`）。

## 背景

- 现在的 `tests/e2e-real.sh` 只支持 Codex 主控（`gpt-6-luna` / `max`）。
- 另外两条唤醒路径从没在真实闭环里跑过：Claude Code 的 Stop hook（asyncRewake）和 pi 的 `qwb-watch.ts` 扩展。2026-09-22 验收的「未覆盖」里写着 Claude Stop 与 Pi reload。
- 使用者会在 qonnwolf-sites 用这两种宿主当主控。
- 基线是 main `e2a3a80`。本分支 `qwb-e2e-controllers` 从它创建，worktree 在 Space `wHH`。

## 已核实的前提（审核者 2026-09-24 读帮助与读码）

### Claude Code 2.1.281

- **信任框**：交互模式下，只要目录未被信任就会弹工作区信任框；只有 `-p` 或 stdout 不是 TTY 时才跳过（见 `claude --help` 原文）。接受信任后，由 Claude Code 自己写入 `~/.claude.json`；它也会给每个运行过的目录记一条项目条目。
- **可用参数**：`--model`、`--effort`、`--permission-mode bypassPermissions`、`--dangerously-skip-permissions`、`--settings`、`--setting-sources`。
- **使用者的 `~/.claude/settings.json`**：
  - `effortLevel: high`；
  - `permissions.defaultMode: bypassPermissions`；
  - `skipDangerousModePermissionPrompt: true`；
  - 没有设 `model`；
  - 用户级 hooks 有 SessionStart 和 UserPromptSubmit。
- **使用者的全局 `~/.claude/CLAUDE.md` 会被加载**：它要求一律用中文，并且每次回复末尾附 `[RULES I BROKE]`。完成标记的判定必须容忍标记之后还跟着别的文字。
- **QWB 的 Stop hook**：
  - 安装器把它合并进项目的 `.claude/settings.json`：命令是 `bash "$CLAUDE_PROJECT_DIR"/qwbuddy/bin/qwb-hook-claude-stop.sh`，`asyncRewake: true`，`timeout: 7200`。
  - hook 只在主控锁的 owner 等于 `HERDR_PANE_ID` 时值守（见 `bin/qwb-hook-claude-stop.sh`）。

### pi 0.87.1

- **信任**：`--approve/-a` 的说明是「Trust project-local files for this run」。
- **可用参数**：`--provider`、`--model`、`--thinking`、`--session-dir`、`-e/--extension`。
- **使用者默认**：`zai-coding-cn` / `glm-5.3-flash` / thinking `high`（见 `~/.pi/agent/settings.json`）。
- **全局信任文件**：`~/.pi/agent/trust.json`。
- **QWB 扩展**：
  - 安装器把扩展装到项目的 `.pi/extensions/qwb-watch.ts`。
  - `templates/host-watch-guide.md` 要求验证两件事：扩展确实已加载，当前 `HERDR_PANE_ID` 持有锁。
  - 扩展用带 `[qwb-wake]` 前缀的 followUp 消息叫醒主控。

### 尚未实测（执行者先实测，再动手实现）

- Claude 信任框的确切文本；接受之后，项目 hook 是否立即生效。
- pi 加 `--approve` 后，是否会自动加载项目的 `.pi/extensions/`。
- 在 named session 里，Herdr 能否把两者识别为 agent。

## 交付物

### 1. `tests/e2e-real.sh` / `tests/e2e-real.py` 支持三种主控

- **新参数**：`--controller codex|claude|pi`，默认 codex，现有用法保持兼容。
- **默认模型与启动方式**：`--controller-model` 和 `--controller-effort` 按主控取不同默认值。

  | 主控 | 默认模型 / 推理档 | 交互启动命令 |
  |---|---|---|
  | codex | `gpt-6-luna` / `max`（不变） | 不变 |
  | claude | `opus` / `high` | `claude --model <m> --effort <e> --permission-mode bypassPermissions` |
  | pi | `zai-coding-cn/glm-5.3-flash` / `high` | `pi --approve --provider zai-coding-cn --model glm-5.3-flash --thinking high --session-dir <临时目录>`（参数的具体写法以 `pi --help` 为准） |

  禁用所有非交互形式：`claude -p`、`pi -p`、`pi --mode`、`codex exec`。
- **启动核对**：启动后核对 TUI 上显示的模型和推理档（或等价证据）；不符就判失败。
- **主控提示**：改成与宿主无关的写法：「按 qwbuddy/QWBUDDY.md 开局，按你所在宿主的唯一值守入口等待」。不得告诉 Claude 或 pi 主控自己去跑 `qwb-wake.sh --block`。要测的正是：文档能不能把每种宿主引到正确的入口。
- **完成判定**：沿用 DONE / BLOCKED 标记。Claude 和 pi 在等 hook 或扩展时会处于 idle，不能把「idle 但没有标记」当成结束。

### 2. 全局状态规则（按主控区分）

- **通用**：
  - 临时项目仍然放在 `mktemp -d` 里。
  - 每一次 herdr 调用都强制用本会话的 socket。
  - default 会话只读。
  - harness 自己不写任何全局配置文件。
- **codex**：沿用 r3 的做法：用 `-c` 覆盖信任，跑前跑后比对 `~/.codex/config.toml`，必须不变。
- **pi**：
  - 用 `--approve`，不写 `~/.pi/agent/trust.json`；跑前跑后比对这个文件，字节必须不变。
  - 会话文件用 `--session-dir` 放进临时目录。
- **claude**：
  - 交互模式下信任框一定会弹，绕不开。只允许在识别出确定的信任框文本时按一次 Enter；识别不了就失败退出，不盲按。
  - 由此 Claude Code 写入 `~/.claude.json`，这是它自身的行为，允许。
  - harness 既不预置也不删除 `~/.claude.json` 的内容。原因：使用者的其他 Claude 会话正在同时写这个文件，外部改写有并发丢更新的风险。
  - 报告里只列出跑前跑后 `projects` 新增的键。

### 3. 新断言

- 原有的 a–h 和 devin 名字断言全部保留，三种主控都要成立。
- **新增「宿主唤醒证据」**：证明工人 done 之后，主控是经由本宿主的正式入口被叫醒的。

  | 主控 | 需要的证据 |
  |---|---|
  | claude | Stop hook 投递的摘要出现在主控会话里，并且主控没有自己在前台运行 `qwb-wake.sh --block` |
  | pi | 会话里出现带 `[qwb-wake]` 前缀的 followUp 消息 |
  | codex | 主控在前台运行了 `qwb-wake.sh --block` |

  具体用什么取证，由执行者实测后决定。可选的来源有：主控转录、Claude 会话 JSONL、`qwbuddy/.watch`、`.hook.err`。要求取证确定、可复核，并写进报告。
- 报告里写明：主控类型、主控 CLI 的版本和所用模型。

### 4. 文档

- 在 `--help` 和 `docs/DECISIONS.md` 的「真实 E2E」条目里补充：三种主控、各自的全局状态规则、各自的默认模型。
- 同一条目里再写明：装生产项目之前，要用该项目实际会用的主控宿主跑一遍。

## 验收

- **三轮 E2E**：在代码定稿的 SHA 上串行跑三轮，每轮都得到一份报告，且 rc=0。
  1. `--controller codex --worker devin`：回归，确认这次改造没破坏 Codex 路径。
  2. `--controller claude --worker devin`。
  3. `--controller pi --worker cmdc`。
- **失败分类**（同 r3）：
  - **QWB 缺陷**：修复后，重跑受影响的轮次。改动如果涉及 `bin/` 或 `templates/`，要配公开 CLI 回归和反转验证。
  - **脚本缺陷**：修复后重跑。
  - **外部工具限制**：比如某个 CLI 无人值守时过不了启动对话框，或者 Herdr 识别不了它。不得绕开，也不得伪造通过，如实报 BLOCKED 或「部分通过」，由主控裁决。
  - **模型能力问题**：主控模型能力不够、没照文档做事，也如实记为该模型的结果，不要改提示词去「帮」它。
- **门**：fast/full 在最终 SHA 上跑，格式同 r3/r4。E2E 之后的提交只允许改 `docs/reviews/`，用 `git diff --stat` 证明。

## 执行任务（执行者：Codex，gpt-6-sol / high）

- **工作环境**：
  - 工作目录 `/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-e2e-controllers`，分支 `qwb-e2e-controllers`，起点 `e2a3a80`。
  - 不开新分支，不 push，不合并。
  - 本任务书随第一笔提交入库。
- **顺序**：
  1. 先实测上面「尚未实测」的三项，并记录结果。
  2. 再改脚本和文档。
  3. 最后跑三轮 E2E。
- **做法**（同 r3/r4）：
  - 先读后写，最小实现，中文注释和报错。
  - 做公开 CLI 层回归。
  - smoke 新节加在「新节必须加在本行之前」那一行之前。
- **约束**：
  - E2E 在 Space `wHH` 里新开 tab 前台运行，方便使用者旁观；不用 nohup、launchd。
  - 不碰其他项目；default 会话只读。
  - cmdc 自动升级已获允许；其他 CLI 不主动升级。
  - 真实花费只限这三轮，加上必要的重跑。每次运行前打印将用的主控和模型。
- **报告**：
  - 写 `docs/reviews/2026-09-24-qwb-e2e-controllers-execution.md`，和改动一起提交。
  - 报告内容：逐项改动、实测记录、测试名、红/绿证据、三轮 E2E 的报告路径与 rc、`~/.claude.json` 新增的键、未验证项。
  - 最后单独输出一行 `QWB_E2E_CONTROLLERS DONE <完整SHA>` 或 `QWB_E2E_CONTROLLERS BLOCKED <原因>`。
