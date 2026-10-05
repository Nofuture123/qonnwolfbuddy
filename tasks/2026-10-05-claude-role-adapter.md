# 任务书：让 Claude Code 能当副主控（规划常驻职责）

```
任务 id:  claude-role-adapter
state: verified
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
working: 2026-10-05T07:53:17Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-claude-role-adapter pane=w14Z:p1D dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter base=0a230b7
working: 2026-10-05T07:54:45Z 执行者已完整读规格与真机报告；核对 qwb_planner_identity/账本/派工/发送入口均沿通用角色身份，暂不需修改这些入口或 qwb-wake。适配集中在 role 生命周期、activity 与 Claude 档位解析；准备先红后绿隔离夹具。
working: 2026-10-05T08:03:20Z 阶段一：新增Claude正常启动断言在原实现rc1（原入口仅Pi拒绝），证据=.worktrees/claude-role-adapter/.qwb-tmp/claude-role-evidence/red.log；当前隔离测试已通过短握手、模型档位/身份漂移拒绝、忙态与输入框、退出resume、未信任reconcile及握手失败恢复；真实plan-assign/new/qwb-run规划派工切片rc0，仍拒绝未授权工人与超预算。
needs-decision: 2026-10-05T08:03:20Z activity的工具配对目前按Claude通用JSONL content.tool_use(id)/tool_result(tool_use_id)做保守解析；提供的真机样本没有工具调用JSONL。请主控补一份脱敏实测assistant工具调用、user工具结果、打断后新一轮的样本，裁定“最新一轮”遇到上一轮未配对工具时是否可认闲；执行者继续独立完成其余门禁，不触碰真实Claude目录或Herdr。
working: 2026-10-05T08:05:26Z 主控裁决（已在真机补测，见 docs/reviews/2026-10-05-claude-code-herdr-probe.md 第 15–18 条；脱敏样本在 /Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/ 下 claude-session-tool-running.jsonl、claude-session-interrupted.jsonl、claude-session-after-new-turn.jsonl，文档在主仓工作区，尚未进你的基点，直接读绝对路径）：实测打断后 Claude Code 自己补写配对的 tool_result（is_error 为真）与一条「Request interrupted by user for tool use」的 user 文本记录，没有留下悬空 tool_use。裁定按保守处理：当前会话文件里只要存在任何未配对的 tool_use（不分是不是最新一轮），一律不认闲，报忙或未知；认闲须同时满足 Herdr 运行态 idle、进程为本代、无未配对 tool_use。不为「上一轮悬空而最新一轮正常」开特例，实测里没出现过这种文件。另一条已知限制如实写进注释与 done 行即可、不用处理：Claude Code 可以在 idle 时仍有后台命令在跑并在其结束时自己再开一轮（第 18 条）。
working: 2026-10-05T08:07:16Z 已完整读主控08:05:26裁决及报告15–18/三份脱敏JSONL；按整份会话任何未配对tool_use均拒绝认闲，不为旧轮次开特例。将三份结构样本接入tests/collab-roles.sh，并识别已配对的工具打断user标记；后台命令可能idle后再开轮的限制已入代码注释，最终done会注明。快门rc0，账本LINT PASS rc0；Pi逐字节重放与规划/门禁/Herdr定向门正在运行。
working: 2026-10-05T08:10:55Z 阶段二：按最新裁决收敛后，bash tests/collab-roles.sh rc0 PASS31 FAIL0（含3份真机JSONL与旧悬空反例）；bash tests/collab-gate.sh rc0 PASS27 FAIL0；fast-final rc0。原始输出在本副本.qwb-tmp/claude-role-evidence/{roles-final,gate,fast-final}.log。规划/Herdr门和Pi字节对照仍在跑；未跑全门。
working: 2026-10-05T08:16:09Z 阶段三：冻结11个候选文件后复核，roles-verified rc0 PASS31 FAIL0；planning rc0 PASS37 FAIL0；gate rc0 PASS27 FAIL0；herdr rc0 PASS96 FAIL0；fast-verified rc0；lint-verified rc0 PASS9 FAIL0且LINT PASS。哈希与开测时一致；仅Pi逐字节对照待结束。此前边测边改Bash导致的rc127已废弃不计通过，原始日志保留，当前重跑全程不改执行中文件。日志均在本副本.qwb-tmp/claude-role-evidence/。
done: 2026-10-05T08:18:41Z commit=b3e587ae86774122230323d52fc2eb5da443493e；白名单11文件已提交，隔离副本工作区clean。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter/.qwb-tmp/claude-role-evidence/，汇总verification-summary.json，候选字节candidate-hashes.json。全程未操作真Herdr、未启动模型、未读写真实Claude会话目录；未建分支或push。
done: 2026-10-05T08:18:41Z 场景1–7：bash tests/collab-roles.sh → rc0 PASS31 FAIL0，roles-verified.log。①Claude规划UUID/短指路/握手实际模型与档位/身份通过（先红red.log rc1=旧实现仅Pi拒绝）；②未启用、非规划、坏argv零Herdr/零记录拒绝；③未信任保留现场，reconcile补握手且不重启；④模型/档位错误和无回复超时不发布active；⑤旧session、错PID/cwd、符号链接/重复文件拒绝；⑥/exit、原session --resume、代次递增、退休通过，草稿/占位/历史viewport拒绝退出；⑦working或任一历史未配对tool_use不认闲，真机打断配对与新一轮样本通过。
done: 2026-10-05T08:18:41Z 场景8：bash tests/collab-planning.sh → rc0 PASS37 FAIL0（planning.log），含Claude真实祖先进程身份下plan-assign/new/qwb-run；未授权工人及超预算仍拒绝。场景9：QWB_ROLE_PI_BYTE_BASELINE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter/.qwb-tmp/claude-role-evidence/pi-baseline-verified/bin bash tests/collab-roles.sh → rc0 PASS31 FAIL0（pi-bytes-verified.log）；78次公开Pi调用的stdout/stderr/rc、角色与native记录字节一致；基线由当前脚本反向撤掉ticket-product-verified.patch构成，未钉历史提交。
done: 2026-10-05T08:18:41Z 独立定向门：bash tests/collab-gate.sh → rc0 PASS27 FAIL0（gate.log）；bash tests/collab-herdr.sh → rc0 PASS96 FAIL0（herdr.log）。bash bin/qwb-test.sh fast → rc0，无shellcheck告警（fast-verified.log）；bash bin/qwb-lint.sh → rc0 PASS9 FAIL0、LINT PASS（lint-verified.log）。PASS/FAIL均用grep -a -c列首计数；/bin/bash -n两份改动测试通过，所有最终退出回执齐全，开测/收尾候选哈希一致，测试进程无本票残留。未跑全门。
done: 2026-10-05T08:18:41Z 已在tests/smoke.sh和tests/collab-all.sh逐名搜索collab-roles.sh、collab-planning.sh及三个claude-session JSONL；前两文件已在collab-all默认清单/ORDER，PASS计数动态，默认仍15项；smoke无写死对应条数，新样本由既有角色入口加载，需改计数/清单0处。账本/派工/发送/门铃的规划身份原本通用，不需修改qwb-ledger/run/send/wake。已知限制按主控裁决保留：Claude可能idle时仍有后台命令，结束后自行再开一轮；代码已注明，不把idle当后台任务全部结束。
working: 2026-10-05T08:28:33Z 主控验收退回两处，原范围返修（其余读过，认可）：（一）会话记录的 cwd 检查过严。真机事实：Claude Code 在 Bash 里 cd 之后，后续 user/assistant 记录的 cwd 字段会跟着变（主控核对了自己这个会话的记录文件：同一会话号下有 3286 条记录 cwd 为项目根、183 条为某个 .worktrees 子目录，等等）。现在 activity 与 relaunch 都要求每一条记录的 cwd 等于职责目录，规划只要 cd 过一次，身份就永久对不上。改为：只要求会话里第一条 user/assistant 记录的 cwd 等于职责目录（会话是在这里开的），sessionId 仍要求全部一致；原生进程 cwd 的检查保留不动。activity 与 relaunch 两处同改，加一条先红后绿的用例（后续记录 cwd 为职责目录下的子目录时身份、活动、恢复照常成立；第一条记录 cwd 不符仍拒绝）。（二）握手等待上限 10 秒在真机上不够：握手要先读职责文件再回复，真机实测带一次工具调用的一轮约 20 秒、纯回复约 2.4 秒。上限改为 120 秒，轮询间隔可放宽到 0.5 秒；测试继续用你已有的私有假钟，不许真等。改完重跑 collab-roles、collab-planning、fast、lint，追加一次提交，写新的 done 行。
working: 2026-10-05T08:31:16Z 执行者已完整读08:28:33返修裁决；仅修activity/relaunch的首条消息cwd锚点及120秒握手上限。已先加后续cwd切子目录的公开status/规划身份/relaunch回归，并保留首条cwd与后续sessionId反例；准备在未修产品上跑红。沿用私有假钟，不操作真Herdr；本轮测试期间冻结全部执行文件。
working: 2026-10-05T08:36:29Z 返修先红已成立：cwd-red.log rc1同时证实后续cwd变化使status/规划身份及relaunch拒绝；修cwd后handshake-red-valid.log rc1明确止于旧10秒握手上限（非查询异常）。已改为120秒/0.5秒，私有假钟先导入subprocess以保留系统查询真钟，并加强所有超时反例的原因断言。准备冻结3文件重跑主控指定四门；不扩跑全门。日志目录=本副本.qwb-tmp/claude-role-repair/。
working: 2026-10-05T08:40:07Z 返修角色全套已自然退出rc0 PASS34 FAIL0（roles.log）；新增后续cwd切子目录/恢复、首条cwd与后续sessionId拒绝、假钟延迟握手均通过。fast rc0、lint rc0 PASS9 FAIL0且LINT PASS；collab-planning仍在执行，待完整回执后提交。原始输出均在本副本.qwb-tmp/claude-role-repair/，当前执行文件继续冻结。
done: 2026-10-05T08:46:12Z 返修完成 commit=d5dc99e901b9016419c98c52399e624e517a665e（在b3e587a之上追加一次提交，3个白名单文件，工作区clean）。activity与relaunch只核第一条user/assistant的cwd；后续cwd变化不再拒绝，全部sessionId约束及原生进程cwd检查保留。Claude握手上限120秒、轮询0.5秒，Pi路径未改。
done: 2026-10-05T08:46:12Z 先红后绿证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter/.qwb-tmp/claude-role-repair/。cwd-red.log rc1同时复现后续cwd导致身份/活动和恢复拒绝；handshake-red-valid.log rc1确因旧10秒握手上限截断。roles.log验证后续user/assistant切子目录时身份/活动/resume成立，首条cwd错误及后续sessionId冲突仍拒绝；假钟延迟回复可active，无回复/错模型/错档位仍按握手超时拒绝。私有假钟先导入subprocess保留查询真钟，初次夹具污染日志handshake-red.log未作有效红证据。
done: 2026-10-05T08:46:12Z 按最新返修范围重跑：bash tests/collab-roles.sh → rc0 PASS34 FAIL0（roles.log）；bash tests/collab-planning.sh → rc0 PASS37 FAIL0（planning.log）；bash bin/qwb-test.sh fast → rc0、无新增shellcheck告警（fast.log）；bash bin/qwb-lint.sh → rc0 PASS9 FAIL0、LINT PASS（lint.log）。原始日志、独立退出回执、verification-summary.json及candidate-hashes.json均在上述证据目录；PASS/FAIL用grep -a -c列首计数，最终哈希与开测时一致，无本票测试进程残留；未跑全门。
done: 2026-10-05T08:46:12Z 已在tests/smoke.sh/tests/collab-all.sh搜索本轮改动的collab-roles.sh：既有默认清单与ORDER均已接入，无写死PASS数；默认15项不变，需同步计数/清单0处。/bin/bash -n tests/collab-roles.sh及git diff --check通过。未触碰真Herdr、未启动模型、未访问真实Claude会话目录，未建分支或push。
working: 2026-10-05T09:32:41Z 主控真机验收退回（第五轮演练现场）：`qwb-role.sh start --role 规划 --worker claude-opus-medium` 在真实安装的项目里被拒，原文「工人身份拒绝: Claude角色仅允许--model/--effort与--dangerously-skip-permissions」。原因：安装器写出的 workers.sh 里 Claude 工人的声明带 `--add-dir 项目根`（例：qwb_worker claude-opus-medium herdr claude -- --add-dir 项目根绝对路径 --dangerously-skip-permissions --model claude-opus-5-5 --effort medium），而 qwb_claude_profile 的白名单不认 --add-dir。任务书第 3 条「其余参数拒绝」是主控没核对安装器产物就写下的，是主控的错。返修：（一）qwb_claude_profile 接受 `--add-dir 路径`（可出现多次，值须为非空且不以 - 开头），其余仍拒绝；（二）拒绝时点名是哪个参数不被允许；（三）加一条用例：用本副本的 bin/qwb-init.sh 真实安装出来的 workers.sh（不手写声明）启动 Claude 规划能通过档位解析，先红后绿；顺带核对安装器对 Claude 工人还会写入哪些参数，全部纳入判断，有拿不准的写 needs-decision。握手、身份等其余逻辑不动。改完重跑 collab-roles、collab-planning、fast、lint，追加一次提交，写新的 done 行。注意主干已前进，你的副本基点不变，照旧在副本里追加提交即可。
working: 2026-10-05T09:35:01Z 已读09:32:41返修裁决并核对qwb-init.sh和模板；默认Claude声明只有dangerously-skip-permissions/model/effort，安装器另注入add-dir项目根，未发现其他自动写入参数。已改角色测试为读取真实安装生成的完整workers.sh，并先走公开Claude规划start，准备在旧解析器上跑红。仅修档位解析及测试，握手/身份逻辑不动。
working: 2026-10-05T09:37:13Z 真安装回归先红成立：本副本bin/qwb-init.sh生成的完整workers.sh未手写Claude声明，公开start在旧解析器rc1拒绝，证据=.qwb-tmp/claude-role-add-dir/red.log。现只修改qwb_claude_profile支持重复add-dir及严格值校验，未知参数点名；补真实安装start/argv保留、重复含空格/引号目录、缺值/空值/选项值/未知参数反例。冻结2文件跑collab-roles、collab-planning、fast、lint；身份与握手代码未动。
working: 2026-10-05T09:40:40Z 主控真机验收再退回两处（第五轮演练现场，与上一条 --add-dir 的返修合并做）：（四）Herdr 对「回合已结束但窗口不在前台」的 Claude Code 报 agent_status=done，不是 idle（主控对着演练里活着的副主控窗口实测：pane get 为 done、focused=false；同一时刻 qwb-herdr.sh activity 返回 activity=unknown、pending_tools 为空、actual_model 与 actual_effort 都对、会话文件末条是 stop_reason=end_turn 的 assistant 记录）。现在 activity 的 Claude 分支只认 idle，握手前置检查也只认 idle，于是真机上握手永远「真实活动未知」。任务书与实测记录里只写了 idle 是主控探测时窗口恰在前台造成的遗漏。改为 idle 与 done 都算回合已结束（与 Pi 分支一致），其余条件不变；加先红后绿的用例。（五）`reconcile` 缺 --expect-gen 时拒绝原文是「旧代际/缺expect-gen」，演练主控不读源码猜不出该填几。拒绝信息写明当前代次与该怎么带参数（例如：当前代次为 0，请加 --expect-gen 0）；qwb-role.sh 里未信任与握手未确认两处提示「reconcile」的文字同样带上完整命令形态。只改提示文字，不改代次校验。五处返修一起提交。
working: 2026-10-05T09:43:51Z 已读09:40:40追加裁决，与add-dir合并为本轮一次提交。原add-dir角色全套已rc0，规划旧轮仍运行；暂不改其执行中的产品文件。现先加done/focused=false/end_turn的status与握手启动回归，在旧判定上留红；随后合并idle/done判定与缺代次、未信任、握手未确认的完整恢复提示，代次校验表达式不变。
working: 2026-10-05T09:49:25Z done回归先红：done-red.log rc1同时复现未聚焦done/end_turn被判unknown及握手前置拒绝。旧add-dir规划轮经本票监督器TERM正常清理，planning.rc=143，不计通过；监督器身份与原因存previous-planning-interruption.json，已核无残留。现已合并idle/done、当前代次提示、未信任/握手失败完整reconcile命令及反例；冻结4文件重跑完整四门，最终与add-dir一起提交。
working: 2026-10-05T09:54:41Z 合并返修角色全套rc0 PASS39 FAIL0：真实安装add-dir、重复/坏参数、done活动/握手/退出、done下未配对工具与模型错误拒绝、gen0/gen1缺失及过期代次提示、未信任/握手失败完整命令均通过。fast rc0、lint rc0 PASS9 FAIL0且LINT PASS；最终planning仍在跑。日志=.qwb-tmp/claude-role-combined/，冻结4文件未再改动，五处会一起提交。
done: 2026-10-05T10:09:03Z 五处返修一次提交 commit=e0bcd3c0d7fabb92e136377c470d48d9cd58d2eb（父提交d5dc99e，4个白名单文件，工作区clean）。①支持重复--add-dir，逐值非空且不以-开头；②未知参数点名拒绝；③直接使用qwb-init真实安装的完整workers.sh验证规划start及实际argv；④Claude activity与握手前置均接受idle/done，PID/session/模型/工具配对条件不变；⑤reconcile拒绝提示当前代次，未信任/握手失败附含project/actor/expect-gen的完整命令，代次校验表达式未改。
done: 2026-10-05T10:09:03Z 先红后绿：.qwb-tmp/claude-role-add-dir/red.log rc1复现安装注入add-dir被旧解析器拒绝；.qwb-tmp/claude-role-combined/done-red.log rc1复现focused=false且end_turn的done被判unknown及握手前置拒绝。最终roles.log覆盖真实安装启动、重复/空值/缺值/选项值/未知参数、done活动/握手/退出及其未配对工具/模型错误反例、gen0/gen1缺失与旧代次拒绝、完整恢复命令参数。安装器核对结论：默认Claude参数为dangerously-skip-permissions/model/effort，另注入add-dir；未发现其他自动新增参数。
done: 2026-10-05T10:09:03Z 最终证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/claude-role-adapter/.qwb-tmp/claude-role-combined/。bash tests/collab-roles.sh → rc0 PASS39 FAIL0（roles.log）；bash tests/collab-planning.sh → rc0 PASS37 FAIL0（planning.log）；bash bin/qwb-test.sh fast → rc0，无新增shellcheck告警（fast.log）；bash bin/qwb-lint.sh → rc0 PASS9 FAIL0、LINT PASS（lint.log）。PASS/FAIL按grep -a -c列首计数，独立退出回执和verification-summary.json齐全；candidate-hashes.json与最终提交字节一致。旧范围planning因追加需求中断rc143单独保留，未计通过。
done: 2026-10-05T10:09:03Z 已搜tests/smoke.sh与tests/collab-all.sh中的collab-roles.sh：默认清单与ORDER已有入口，PASS数动态，默认15项不变，需改计数/清单0处。/bin/bash -n tests/collab-roles.sh、git diff --check通过，已核无本票测试进程残留。未跑全门；所有运行验证均为隔离fakeHerdr，未操作真Herdr、未启动模型、未读写真实Claude会话目录，未建分支或push。
working: 2026-10-05T11:58:55Z 主控验收：三次提交 b2157c9、7488ed0、d0acdff 已在 main。全新安装的项目里真机探测通过（带 --add-dir 启动成功、窗口不在前台报 done 认作空闲、缺代次的拒绝写明当前代次，证据 .qwb-tmp/probe-claude-planner-start/result.md）；第六轮真机演练 Claude 副主控零介入走通（docs/reviews/2026-10-05-real-herdr-roles-drill-r6.md）；main 24a8a88 全门 rc=0、865 PASS、0 FAIL（.qwb-tmp/ctl-full-merge14.log）；真机端到端第 17 轮 rc=0（docs/reviews/2026-10-05-e2e-real-claude-pi-r9.md）。
