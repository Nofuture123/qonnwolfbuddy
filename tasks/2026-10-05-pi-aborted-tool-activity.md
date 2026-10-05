# 任务书：Pi 工人被打断后活动判定一直报忙

```
任务 id:  pi-aborted-tool-activity
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 第六轮真机演练的故障注入（主控实测）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-pi-aborted-tool-activity.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/pi-aborted-tool-activity（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：工人收工不回票时要很快有人被叫醒；活动判定不能把已经停下的工人当成还在忙。

### 缺陷（主控真机实测，两份脱敏样本只读）

`bin/qwb-herdr.sh` 的 `activity` 里 Pi 分支（约第 189–206 行）把当前分支上所有助手消息里的 `toolCall` 记为未完成，直到出现同号的 `toolResult`。真机上有一种情形永远等不到结果：

- **模型正在输出、工具调用还没开始执行时按 esc**（样本 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/pi-session-aborted-tool-then-clean-turn.jsonl`）：Pi 写下一条 `stopReason` 为 `aborted` 的助手消息，里面带一个 `toolCall`，之后没有任何对应的 `toolResult`。随后使用者再发一条消息，助手正常答完（`stopReason` 为 `stop`）。此时 Herdr 报 `done`、进程活着、会话末条是正常结束的助手消息，但 `activity` 返回 `busy`，`pending_tools` 里是那条被中止的调用，而且此后永远如此。后果：一分钟「收工未报告」门铃不触发、原工人续派被拒、依赖空闲判定的收尾都卡住。
- **工具已经在执行时按 esc**（样本 `…/pi-session-aborted-during-tool-run.jsonl`）：Pi 会写一条 `isError` 为真的 `toolResult`，再写一条 `stopReason` 为 `error` 的空助手消息。这种情形调用是配对的，现有判定没有问题，不要改坏。

### 要做的事

`stopReason` 为 `aborted` 的助手消息里的 `toolCall` 不计入未完成（它们没有被执行）。其余口径不变：`stopReason` 为 `toolUse` 的消息里没有结果的调用仍算未完成；Herdr 报 `working` 或 `blocked` 仍算忙；身份、进程、会话核对一律不动。只改 Pi 分支；Claude 分支不动（Claude 打断后自己补写配对结果，见 `docs/reviews/2026-10-05-claude-code-herdr-probe.md` 第 16 条）。

除这一条以外，如果你认为还有别的会留下悬空调用的情形，只写进 `done:` 行说明，不要凭推断改判定（没有真机样本的情形由主控去实测）。

白名单：`bin/qwb-herdr.sh`（仅 `activity` 的 Pi 分支）、`tests/` 下覆盖 Pi 活动判定的已接入测试文件（先搜 `pending_tools` 与 `session-branch` 找到它）。

## 1. 验收场景

1. 用第一份样本的记录结构构造会话（中止的助手消息带调用、其后使用者消息、助手正常结束）：Herdr 报 `idle` 或 `done` 时 `activity` 为 `idle`，`pending_tools` 为空。这条断言在起点提交上必须是红的，先跑出红并留证。
2. 第二份样本的结构（执行中被打断、结果配对、助手 `error` 结束）：判定与改动前逐字节相同。
3. `stopReason` 为 `toolUse` 且没有结果的调用：仍为 `busy`，与改动前相同。
4. 中止的助手消息是分支末条（之后没有任何消息）、Herdr 报 `idle` 或 `done`：`activity` 为 `idle`（末条 `aborted` 本来就算已结束，现有第 204 行）。
5. 其余既有用例全部照旧通过。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时有另一张票 `worker-silent-end` 在改 `bin/qwb-wake.sh`、`bin/qwb-run.sh`、`bin/qwb-lib.sh`，`roles-r5-docs` 在改说明书；本票只碰 `bin/qwb-herdr.sh` 的 `activity` 里 Pi 分支与对应测试。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`。
- 定向：你改动或新增用例所在的测试文件单独跑一次，另单独跑 `tests/collab-roles.sh` 与 `tests/collab-herdr.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**。在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的测试文件名，写死了通过条数或清单的地方同步改，并在 `done:` 行写明。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
