# 任务书：让 Claude Code 能当副主控（规划常驻职责）

```
任务 id:  claude-role-adapter
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     Rocky 2026-10-05 五角色裁决（副主控：Claude Code opus 5.5 或 Pi astra low）；真机实测 docs/reviews/2026-10-05-claude-code-herdr-probe.md
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-claude-role-adapter.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky，2026-10-05）：副主控是主控的直接下属，能开票也能派工，可以由 Claude Code（opus 5.5 medium）或 Pi（astra low）担任。现状：`bin/qwb-role.sh` 只能把常驻职责启动成 Pi，帮助里写着「Claude/Codex控制未验证，拒绝」。

本票只做一件事：`qwb-role.sh start --role 规划` 可以选一个 Claude Code 工人（工人表里 harness 为 `claude` 的条目），启动、身份核对、状态、中断、退出、恢复、退休与 Pi 担任时同样可靠；账本对规划身份的各项校验照常生效。门禁、测试体系、CI 三个职责仍只支持 Pi（Rocky：门控优先 gpt 模型），选了 Claude 工人照旧拒绝。

### 真机事实（主控实测，先完整读 `docs/reviews/2026-10-05-claude-code-herdr-probe.md`；样本在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/` 与 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/probe-claude-role/out/`，只读）

- 启动参数：`--session-id 标准UUID` 与 `--append-system-prompt 文字` 可同用；`--session-id` 必须是带连字符的 UUID；对已存在的会话号再用 `--session-id` 会报 `already in use` 并让 `agent start` 超时失败；续接用 `--resume 会话号`，会话号不变、会话文件续写。
- 身份：Herdr 报 `{"agent":"claude","kind":"id","source":"herdr:claude","value":"会话号"}`；已信任目录里 `agent start` 的成功响应就带它。前台进程 `argv0` 为 `claude`，对话后前台还会多一个 `caffeinate`。
- 未信任目录：`agent start` 返回退出码 1、`agent_not_ready`，窗口 `agent_status` 为 `blocked`、无 `agent_session`；人工选信任后转 `idle` 并报出会话。
- 会话文件：`~/.claude/projects/目录名/会话号.jsonl`，在项目之外；**第一条消息之前不存在**；目录名规则只观察到 `/`、`.`、`_`、空格都变成 `-`，不要依赖这条规则去拼路径，按会话号找唯一文件并核对记录里的 `sessionId` 与 `cwd`。
- 模型证明：每条 `assistant` 记录有 `message.model` 与顶层 `effort`；只有答过一轮才有。窗口底部状态行是使用者自配的，不能当证据。
- 运行态：`idle` → 收到提示约 0.6 秒 `working` → 答完 `idle`；退出命令 `/exit`，退出后窗口 `agent` 为空、`agent_status` 为 `unknown`。
- 输入框：答过至少一轮之后，空输入框在可见内容里是两条横线之间单独一行 `❯`（后面可有空白）；全新会话还没对话时，同一位置显示 `❯ Try "…"` 这样的占位提示。
- 发给 Claude Code 的文字含换行或单行超过 800 字符会被当成粘贴内容，模型可能要求人确认后才执行。

### 设计方向（主控定的；标「主控推断」的没有在真机上试过，你核对代码后认为走不通就写 `needs-decision:`）

1. **按工具分身份适配，不放宽判定。** `qwb-role.sh` 里与 Pi 绑定的点（启用开关与集成文件检查、`current()` 的会话与页脚证明、`launch()` 的启动参数、退出命令与输入框检查、`relaunch` 的会话文件头检查、`tool='pi'`、`qwb_pi_profile`）各自给出 Claude Code 的对应实现。Pi 的行为逐字节不变。
2. **启用开关**：`QWB_ROLE_CLAUDE_CONTROL="verified"`（写进 `templates/config.sh`，默认空）。未启用时选 Claude 工人拒绝，并写明怎么启用。
3. **档位解析**：Claude 工人的 argv 里 `--model`、`--effort` 各显式出现一次；允许 `--dangerously-skip-permissions`；其余参数拒绝（与 Pi 的白名单同一态度）。
4. **启动**：工人 argv 加 `--session-id` 新生成的标准 UUID，加 `--append-system-prompt` 一行不超过 600 字符的指路文字（说明它是哪个项目的哪个职责、职责文件的绝对路径、开工前先完整读它）。不把整份职责文本塞进命令行（主控推断：多行长参数经 `herdr agent start` 敲进 shell 没有在真机上试过）。
5. **握手取得模型证明**：启动确认会话身份后，发一条单行短提示让它读职责文件并回复就绪；在有限时间内等到会话文件出现、其中最新一条 `assistant` 记录的 `message.model` 与 `effort` 等于工人表配置，才发布为 `active`。等不到或对不上：保留现场与记录，状态如实，不认作可用身份。此后每次 `current()` 都以最新一条 `assistant` 记录核对模型与档位（使用者在界面里切了模型就会对不上，应当拒绝）。
6. **未信任目录**：不替使用者按信任。启动返回 `agent_not_ready` 时，记录保留为可恢复状态，拒绝信息写明：到那个窗口里确认信任，然后 `reconcile`。`reconcile` 能把这种情况接上（含补做握手）。
7. **活动判定**：`bin/qwb-herdr.sh` 的 `activity` 对 Claude Code 目前不给出可用结论（代码注释写着其余适配器保持 unknown/busy）。给出 Claude Code 的判定：进程号与启动时间为本代、Herdr 运行态为 `idle`，且会话文件最新一轮没有未配对的工具调用，才算 `idle`；其余如实报忙或未知。绝不把 `working` 判成 `idle`。
8. **退出**：只在证实空闲、输入框证实为空（上面「输入框」一条的第一种样子）时发 `/exit`；占位提示那种样子不算已证实为空（握手之后不应再出现）。退出后以旧进程结束为准。
9. **恢复**：会话文件存在且记录的 `sessionId`、`cwd` 与登记一致时用 `--resume` 续接；否则按现有规则拒绝或开新会话（与 Pi 的分支对应）。
10. **会话文件位置可注入**：默认 `~/.claude/projects`，测试用环境变量指到临时目录；路径检查沿用现有的拒绝符号链接等规则。
11. **叫到它的门铃**：发给 Claude 职责窗口的文字须单行且不超过 600 字符。另一张票 `claude-prompt-length` 在给 `bin/qwb-wake.sh` 的发送处加统一整形；本票不改 `bin/qwb-wake.sh`，只要保证本票自己新发出的文字（握手提示）合规。
12. **账本与派工侧**：查 `bin/qwb-ledger.sh`、`bin/qwb-run.sh`、`bin/qwb-send.sh`、`bin/qwb-wake.sh` 里是否有把规划身份或规划窗口写死成 Pi 的地方（例如 `qwb_gate_identity` 的调用者祖先进程检查、规划派出的工人限定、门铃目标）。规划身份校验对 Claude 担任者照常成立所需的最小改动列入本票；规划派出的工人仍按现有规则（不因规划换成 Claude 而放宽）。发现需要改 `bin/qwb-wake.sh` 的，写 `needs-decision:`。
13. 帮助文字、`templates/roles/规划.md` 与 `templates/QWBUDDY.md` 里「常驻职责只支持 Pi」一类的话同步改准（只改相关的一两句）。

白名单：`bin/qwb-role.sh`、`bin/qwb-lib.sh`（仅 `qwb_pi_profile` 旁新增 Claude 档位解析、`qwb_gate_identity` 的最小改动）、`bin/qwb-herdr.sh`（仅 `activity`）、`bin/qwb-ledger.sh` 与 `bin/qwb-run.sh` 与 `bin/qwb-send.sh`（仅第 12 条查出的最小改动）、`templates/config.sh`、`templates/roles/规划.md`、`templates/QWBUDDY.md`、`tests/` 下为验收所需的已接入文件（Claude 的假 Herdr 应答按上面的真机样本造）。

## 1. 验收场景

### user_正常路径_Claude工人启动为规划并取得身份

Given 项目启用了 `QWB_ROLE_CLAUDE_CONTROL`，工人表有 `claude-opus-medium`，目录已信任
When  主控 `qwb-role.sh start --actor planner --role 规划 --worker claude-opus-medium --dir 项目根`
Then  启动参数含新会话号与单行指路提示；握手后记录为 `active`，`status` 给出实际模型与档位（来自会话文件）；`qwb_planner_identity` 对它成立；这条用例在起点提交上是红的，先跑出红并留证

### user_失败路径_未启用或选错职责时拒绝

Given 未启用开关，或 `--role 门禁` 配 Claude 工人
When  start
Then  拒绝且不建窗口、不留角色记录；信息写明原因与出路

### user_失败路径_目录未信任时保留现场并可接上

Given 假 Herdr 对启动返回 `agent_not_ready`、窗口 `blocked`
When  start，随后窗口转为 `idle` 并报出会话，再 `reconcile`
Then  start 拒绝并写明去窗口确认信任后 reconcile；reconcile 补做握手并发布 `active`；全程没有重发启动

### user_失败路径_模型或档位对不上时不认身份

Given 会话文件最新一条 `assistant` 记录的模型或档位与工人表不同，或握手超时没有任何记录
When  start 或 status
Then  不发布为可用身份（`qwb_planner_identity` 拒绝），现场与记录保留，原因如实

### user_失败路径_迟到或别代的会话不被采信

Given 窗口里的会话号不是本代登记的会话号，或进程号不是本代
When  status 或任一控制操作
Then  拒绝，与 Pi 担任时对应用例的结论一致

### user_正常路径_退出与恢复

Given 活动中的 Claude 规划，空闲且输入框为空
When  `qwb-control.sh exit`，再 `relaunch`
Then  发出 `/exit` 并以旧进程结束确认；relaunch 用 `--resume` 原会话号，代次加一，会话号不变；输入框非空或显示占位提示时 exit 拒绝

### user_失败路径_忙时不认闲不退出

Given 会话文件最新一轮有未配对的工具调用，或 Herdr 运行态为 `working`
When  status 与 exit
Then  status 报忙；exit 拒绝

### user_正常路径_Claude规划走通开票与派工

Given Claude 担任的规划已 `active`，主控 `plan-assign` 授权
When  规划身份执行 `new` 与派工（假 Herdr）
Then  与 Pi 担任时相同的结果；规划派出的工人限定不变

### user_正常路径_Pi路径逐字节不变

Given 起点提交与改后的脚本
When  用 Pi 工人跑角色的全套既有用例
Then  标准输出、标准错误、退出码、角色记录内容新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时可能有另一张票 `claude-prompt-length` 在改 `bin/qwb-run.sh`、`bin/qwb-wake.sh` 的提示词发出处并在 `bin/qwb-lib.sh` 新增一个独立函数；本票不改 `bin/qwb-wake.sh`。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 九个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-roles.sh`（或角色用例所在的实际入口，说明是哪个）、`tests/collab-planning.sh`、`tests/collab-gate.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了通过条数、用例组数或文件清单的地方同步改成新值；这些行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不放宽任何身份、代次、归属校验；不替使用者确认信任；不让门禁、测试体系、CI 用 Claude 工人。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
