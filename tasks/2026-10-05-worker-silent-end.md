# 任务书：工人收工却没把结果写进票时，一分钟内叫到派工者

```
任务 id:  worker-silent-end
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 Rocky 对 30 分钟兜底的原话「太长了，哪可能30分钟停滞兜底呢」
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第四轮（.qwb-tmp/drill-roles-r4/，记录待写入 docs/reviews/）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-worker-silent-end.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-silent-end（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky，2026-10-05）：链路上不许出现「所有人都停着、没人知道该谁动」的空等。原话：「太长了，哪可能30分钟停滞兜底呢」。

### 事实

1. **真机现场（演练第四轮，主控亲见）。** 门控派出的独立审核工人 08:59:11Z 结束回合，结论只说在自己窗口里，没有往票上写任何状态行。票上没有新事件，值守没东西可路由；门控在等「审核结果交回」，主控在等门控，全员空等 20 分钟，直到主控人工提醒审核工人补写 `done:` 行。补写后 15 秒内门控被叫醒继续。上一轮演练里审核工人自己写了 `done:`，所以没暴露。
2. **审核工人的提示词里没有回票指令（主控已核对代码）。** `bin/qwb-run.sh` 里执行者提示词（约第 725 行）写明「每完成一个阶段往主账本追加状态行…写完状态行再收工」以及已迁票用 `qwb-ledger.sh append` 的完整写法；而门控派审核时（`GATE_KIND` 为 `review`，约第 730 行）整条提示词被换成「你是独立审核者…」，其中没有任何「把结论写进票」的要求。返修（`rework`）是在原提示词前加前缀，所以带着回票指令。
3. **值守对在途工人只有两种兜底（主控已核对代码）。** `bin/qwb-wake.sh` 的 `collect_worker_due` 与 `worker_due_row`：工人窗口消失（`worker_lost`）立刻叫派工者；否则只有「距最后一条业务事件超过 `QWB_REWAKE_MS`（默认 30 分钟）」才叫，文案是「工人无进展」。工人回合已经结束、票上却没有交代这种情况，现在也要等满 30 分钟。
4. 工人回合是否结束是可以直接观察的：`bin/qwb-herdr.sh activity` 对 Pi 与 Claude Code 都能在核对本代进程与会话文件后给出 `idle`（无未配对工具调用）；给不出结论时返回 `unknown`。

### 要做的事

1. **审核提示词补上回票指令。** 与执行者提示词同一口径：审核结论必须写成原票上的一条 `done:` 行（已迁票给出 `qwb-ledger.sh append` 的完整写法与本次派发的操作号），写明两轴结论、覆盖的场景、findings、原生会话路径；只在窗口里说不算交付；写完再收工。提示词仍是单行。
2. **新增「已收工未报告」的快路径。** 条件全部满足才触发：票在途且最近一次有效派发的工人窗口仍在；该次派发之后票上没有这个操作号的 `done:`、`blocked:`、`needs-decision:`；`activity` 证实该工人为 `idle`（`unknown` 与 `busy` 都不算）；并且「已收工」这个状态持续达到新配置项 `QWB_SILENT_END_MS`（默认 60000，0 为关闭，离开/静音姿态下关闭，与现有兜底同一规矩）。触发后按现有路由叫派工者一次（门控派的叫门控，规划派的叫规划，其余叫主控；身份失效时的回落沿用现有规则），文案写清：工人已收工但没有报告、窗口号与操作号、请读它的窗口或让它补写状态行。同一次收工只叫一次（去重口径参照丢失那一路）；工人之后补写了状态行就按正常事件走。
   「持续多久」需要一个不靠常驻进程的时间依据：优先用现有证据里能拿到的时间（例如会话文件最后一条记录的时间，或值守自己已有的状态文件），你读代码后选一种并说明理由；拿不到可靠时间就不触发（宁可退回 30 分钟那一路，不许猜）。
3. 原有两路不变：窗口消失立刻叫；仍在干活（`busy`）或活动未知但长时间没有新事件，仍按 `QWB_REWAKE_MS`。
4. `templates/config.sh` 加上 `QWB_SILENT_END_MS` 及一行说明；`templates/roles/审核者.md` 与 `templates/roles/门禁.md` 各补一句：审核结论必须写进原票的 `done:` 行，门控不必等满长时限。

白名单：`bin/qwb-run.sh`（仅审核提示词）、`bin/qwb-wake.sh`（仅 `collect_worker_due`、`worker_due_row` 及其文案）、`bin/qwb-lib.sh`（仅当需要一个小的共用函数）、`templates/config.sh`、`templates/roles/审核者.md`、`templates/roles/门禁.md`、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_审核工人被要求把结论写进票

Given 门控派独立审核
When  读发给审核工人的提示词（超过长度上限时读它指向的文件原文）
Then  其中有把结论写成原票 `done:` 行的明确指令与已迁票的完整写法；这条用例在起点提交上是红的，先跑出红并留证

### user_失败路径_审核工人收工未报告时门控一分钟内被叫到

Given 门控派出的审核工人已证实空闲，票上没有它的 `done:`，假钟推进到超过 `QWB_SILENT_END_MS`
When  值守跑一轮
Then  门控收到一条「已收工未报告」的门铃，写明窗口号与操作号；再跑若干轮不重复叫；这条用例在起点提交上是红的（要等满 30 分钟），先跑出红并留证

### user_失败路径_规划或主控派的工人同样处理

Given 规划派出的实现工人、以及未带规划授权的票上主控派出的工人，各自收工未报告
When  值守跑一轮
Then  分别叫到规划、主控；规划身份失效时按现有规则回落主控

### user_正常路径_仍在干活的工人不被误叫

Given 工人 `busy`，或活动为 `unknown`，票上超过一分钟但不到 `QWB_REWAKE_MS` 没有新事件
When  值守跑若干轮
Then  不叫任何人；满 `QWB_REWAKE_MS` 后的行为与起点提交相同

### user_正常路径_正常交付不触发

Given 工人写了 `done:` 后收工
When  值守跑一轮
Then  只有原有的交付路由，没有「未报告」门铃

### user_正常路径_补写后恢复正常

Given 已经叫过一次「未报告」，随后工人补写了 `done:`
When  值守跑一轮
Then  按正常交付事件路由，不再出现「未报告」

### user_正常路径_关闭与其余行为逐字节不变

Given `QWB_SILENT_END_MS` 为 0，或离开/静音姿态
When  跑上述各情形与现有丢失、无进展用例
Then  与起点提交的标准输出、标准错误、退出码、票内容相同（基线按第 2 节约束写成只撤掉本票改动）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 当前没有别的票在改这些文件。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-gate.sh`、`tests/collab-planning.sh`、`tests/collab-handoff.sh`、`tests/wake-block-output.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了通过条数、用例组数或文件清单的地方同步改成新值；这些行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改 30 分钟「仍在干活但长时间无进度」这条兜底的判定与时限；不把活动未知猜成已收工；不新增常驻进程或第二个值守。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T09:21:10Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-worker-silent-end pane=w14Z:p1F dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-silent-end base=198d7da
working: 2026-10-05T09:22:23Z 执行者已完整读票及点名模板/脚本/验收入口；确认审核提示词缺回票指令。拟复用activity --task核对本代PID/session，取原生会话末条记录时间作为收工时间，缺时间/早于派发/unknown不触发；先补提示词与快路径红证。代码仅本隔离副本。
working: 2026-10-05T09:30:41Z 实现阶段完成：审核单行提示词已补原票done/完整append/op；快路径复用collect_worker_due/worker_due_row，核本代idle+原生末记录时间，末记录早于派发/未来/缺失均不猜，按原收件代次去重并投递前重验；默认60000ms，0与away/quiet关闭。bash bin/qwb-test.sh fast rc0；bash bin/qwb-lint.sh rc0 LINT PASS。提示词旧红rc1、新绿rc0；快路径仅撤本票改动基线红证与七场景/定向验收进行中，日志在本副本.qwb-tmp/worker-silent-end-evidence/。
working: 2026-10-05T09:32:09Z 红证阶段完成：QWB_GATE_PROMPT_ONLY=1 bash tests/collab-gate.sh 在实现前rc1，断言审核提示词缺完整append/op（red-prompt.log）；QWB_PLANNING_UPWARD_ONLY=1 QWB_SILENT_END_ONLY=1 QWB_SILENT_END_BASELINE=1 bash tests/collab-planning.sh 当前仅撤本票改动基线rc1，原生idle已绑定、假钟60000ms仍零规划门铃（red-fast-baseline.log）。日志均在本副本.qwb-tmp/worker-silent-end-evidence/；早先受瞬时语法编辑影响的red-fast.log/red-fast-focused.log不计红证。
