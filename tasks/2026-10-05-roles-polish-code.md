# 任务书：常驻职责链路的四处收尾：授权载荷的拒绝信息、主控自派的待办、状态显示口径、落地前先查工人是否退出

```
任务 id:  roles-polish-code
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第三轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r3.md 的 S1–S5）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-roles-polish-code.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-polish-code（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控照着脚本的提示就能走通，不用读源码、不做白工。

### 事实（标明处主控已核对代码；其余为演练主控的记录，动手前先核对）

1. **`plan-assign` 载荷写错时拒绝信息不说该怎么写（已核对代码）。** 预算写成按票的映射 → `启动授权/预算未明确`（`bin/qwb-ledger.sh` 约第 393 行，实际要求 1 到 64 的整数）；包对应的票写成 `tasks/x.md` → `工作包id/任务路径歧义`（约第 378 行，实际只接受不带目录的 `.md` 文件名）。
2. **`gate-assign` 载荷的形状只能读源码才知道（演练记录）。** `workers` 只允许 `review`、`rework` 两个键；`required` 的键只能是 `fast` 或 `full` 且 `full` 要覆盖全部 `user_` 场景；`environment` 必须是存在的文件；`base` 为完整提交号。对应的拒绝句在 `gate-assign` 一段（约第 1435–1480 行）。
3. **主控自己写的授权行成了主控的待办（已核对代码写入处）。** `plan-assign` 成功时写 `working: planner-authorized actor=… request=…`（约第 1132 行），演练里这一行以到期状态出现在主控的待办中，主控走四步办结。`collab-notify-gaps` 的设计（`docs/designs/2026-10-05-collab-notify-gaps.md` E 节）把 plan-assign 类列为「按职责保留」，理由是有规划就绪接力。
4. **票已结，`qwb-status` 仍列「交接待办」（已核对显示处）。** `bin/qwb-status.sh` 约第 144 行按原始未办结交接逐条打印。演练里票 verified 之后仍列出 7 条（工人进度、门控通过通知、交还通知），而落地与收尾的未结判定已经不把它们算作未结（`bin/qwb-lib.sh` 的 `qwb_task_obligations_json` 与账本里的有效义务分类）。主控因此逐条手工办结。
5. **落地在合入之后才因工人未退出被拒（已核对拒绝处）。** `qwb-worktree.sh land` 被拒 `拒绝：本票写入者尚未退出（idle/done不等于已停）`（`bin/qwb-worktree.sh` 约第 248 行），此时 main 已经快进；关掉工人窗口后同一操作号重跑成功。拒绝信息没写是哪个窗口、该怎么办。
6. `bin/qwb-run.sh` 约第 730 行发给审核者的提示词里还有「unknown/同family不伪填」；2026-10-05 起规则是「审核者与实现者模型不同、会话不同」，family 只是可选附记。

### 要做的事

1. **两处授权载荷的拒绝写明期望形状。** `plan-assign`：预算、包这两类拒绝在原句之后补充期望的类型与一个合规示例。`gate-assign`：各形状类拒绝在原句之后补充该字段的期望形状。原拒绝句开头一律不变。每条补充文字都要与代码的实际校验一致（先读校验代码再写，不照抄上面的事实描述）。
2. **主控自己的授权行不成为主控的待办。** 先查清 `planner-authorized`（以及 `plan-authorize` 的同类行）派生的交接按现有路由该给谁、在第三轮演练的情形下为什么落到主控。目标：写入者是主控、内容只是「主控已授权」的行，不需要主控自己再走四步；规划需要知道的话路由给规划。给出最小改法；若与 `collab-notify-gaps` 设计 E 节「按职责保留」的理由冲突，写 `needs-decision:` 说明两难在哪。
3. **状态显示与有效未结用同一口径。** `qwb-status` 的「交接待办」只列有效未结的交接（复用 `qwb_task_obligations_json` 或账本的同一分类，不另写一套判断）；已被静默或已被满足的不逐条列，改为一行计数（例如「另有 N 条已满足或纯进度的历史交接」）。票没有任何有效未结时不出现「交接待办」字样。
4. **落地先查工人是否已退出，并把出路写出来。** `qwb-worktree.sh land` 在动 main 之前先做「本票写入者是否已退出」的检查（复用现有判定，不新写）；未退出就在合入前拒绝，信息写明是哪些窗口，以及出路：确认工人已停后 `herdr pane close 窗口号`，再用同一操作号重跑。`finish` 路径上同一句拒绝也补上窗口号与出路。原拒绝句开头不变。已经部分落地（main 已快进）后重跑的续接行为保持现状。
5. `bin/qwb-run.sh` 审核提示词里的「同family」改为与现行规则一致的说法（模型相同或未知时不伪填）；同文件其他位置若还有「换家族」类措辞一并对齐。只改文字，不改任何判定。

白名单：`bin/qwb-ledger.sh`（仅上述拒绝信息与第 2 项所需的最小路由或分类改动）、`bin/qwb-lib.sh`（仅 `qwb_task_obligations_json`，且仅当第 2、3 项需要）、`bin/qwb-wake.sh`（仅当第 2 项需要）、`bin/qwb-status.sh`（仅交接待办的显示）、`bin/qwb-worktree.sh`（仅 `land` 的前置检查与两处拒绝信息）、`bin/qwb-run.sh`（仅审核提示词文字）、`tests/` 下为验收所需的已接入文件。`templates/` 与 `bin/qwb-init.sh` 由另一张票 `roles-walkthrough-docs` 在改，本票不碰。

## 1. 验收场景

### user_失败路径_授权载荷写错时拒绝信息给出正确写法

Given 主控的 `plan-assign` 载荷把预算写成对象，或把包对应的票写成带目录的路径；`gate-assign` 载荷的 `workers` 多了一个键，或 `required` 缺 `full`
When  执行
Then  各自被拒，退出码不变，标准错误以原拒绝句开头，后面是该字段的期望形状与示例；票字节不变；照示例改正后同一命令成功

### user_正常路径_主控授权后没有自己的待办

Given 主控 `plan-assign` 成功
When  读主控的到期待办并跑一轮值守
Then  主控不因自己那条授权行被叫醒，也不需要办结它；规划照常被叫到去接需求原话；这条用例在起点提交上的结果如实记录（若起点主控就没有这条待办，说明事实 3 不成立，写进 `done:` 行并跳过第 2 项）

### user_正常路径_已结的票状态显示没有待办

Given 一张走完落地与收尾、verified 的票，票上留有未逐条办结的纯进度交接、门控通过通知与交还通知
When  `qwb-status`
Then  该票显示已结，没有「交接待办」逐条列表，只有一行历史交接计数；这条用例在起点提交上是红的，先跑出红并留证

### user_失败路径_真正未办的交接仍然列出

Given 票上有一条没人办理的工人 blocked 交接
When  `qwb-status`
Then  它出现在「交接待办」里，内容与起点提交相同

### user_失败路径_工人未退出时落地在合入前被拒

Given 门控已通过、主控已 `land-authorize`，实现工人的窗口还在
When  `qwb-worktree.sh land`
Then  被拒，main 没有动，标准错误以原拒绝句开头并写明窗口号与出路；关掉窗口后同一操作号重跑成功；这条用例在起点提交上是红的（main 已被快进），先跑出红并留证

### user_正常路径_其余行为逐字节不变

Given 起点提交与改后的脚本（基线按第 2 节约束写成只撤掉本票改动）
When  跑合规载荷下的 `plan-assign`、`gate-assign`，工人已退出时的 `land`，以及未迁旧票的 `qwb-status`
Then  标准输出、标准错误、退出码、票内容新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 同时有另一张票 `roles-walkthrough-docs` 在改 `templates/` 与 `bin/qwb-init.sh`；本票只动 `bin/` 下上述脚本的最小区域，不顺手整理。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交（钉死的基线会被后续正当的行为变更打坏）。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加；文件改名用 `git mv`）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 六个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh`、`tests/collab-gate.sh`、`tests/collab-land.sh`、`tests/collab-handoff.sh`、`tests/wake-block-output.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（多个工人同时跑全门会互相挤出超时类假失败，全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名与你改过名的每个文件名，凡是写死了通过条数、用例组数或文件清单的地方同步改成新值；这些行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」「演练主控的记录」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件与权限；不改审核身份判定；拒绝仍然拒绝，只是把出路写出来。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T07:35:27Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-roles-polish-code pane=w14Z:p1C dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-polish-code base=a76b8fa
working: 2026-10-05T07:37:35Z 主控更正：任务书事实 2 里「full 要覆盖全部 user_ 场景」不准确。实际规则是 required 必须有 full 键，且 fast 与 full 所列场景的并集覆盖全部 user_ 场景（bin/qwb-ledger.sh 第 1447–1451 行）。拒绝信息的补充文字按代码实际校验写。
working: 2026-10-05T07:38:42Z 执行者已完整读规格/notify-gaps设计/r3报告；起点a76b8fa：route-base rc=0，planner-authorized与原话由wake路由planner-pane，ctl零该行门铃且未伪造handled，事实3不成立按验收约定跳过第2项。plan/status/land起点新增断言红：预算缺写法；verified逐条列历史待办；活工人拒绝时main已快进。原始日志=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/{route-base,plan-red,status-red,land-red}.log。required遵最新裁决：full必有、fast/full并集覆盖，不改校验。
working: 2026-10-05T07:44:55Z 执行者阶段2完成：仅改5个bin脚本及tests；拒绝前缀/校验不变，required写full必有且并集覆盖；status复用义务读模；land前置复用退出探针，finish两处写窗口/同op出路，审核文字对齐模型+会话。plan/gate/land/旧票status逐字节比较通过，部分land恢复无重复merge。fast rc=0，lint rc=0且LINT PASS；handoff与wake-block定向rc=0；planning/gate/land完整定向执行中。证据均在.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence。
working: 2026-10-05T07:49:10Z 执行者阶段3：入口自检44文件/选定helper一项rc=0，快门及独立lint通过。land旧endpoint夹具先显式建立部分落地，再保留原换代/未知端点/同op恢复断言；新增活工人场景单独守main不前进。完整land定向已重新开跑。一次E窄测业务断言通过后因运行期间源文件编辑导致shell旧偏移EOF，保留status-final.log/rc并以稳定源码重跑。此前阶段2写5个bin是计数误写，实际改4个bin。
working: 2026-10-05T07:54:18Z 执行者阶段4：稳定源码land完整定向rc=0 PASS=58 FAIL=0；gate rc=0 29/0，handoff rc=0 12/0，wake-block rc=0 20/0；E状态窄测rc=0 4/0，agent-shapes rc=0 34/0；Bash3.2授权窄测plan 4/0、gate 2/0均rc=0。planning原运行所有业务断言通过，但改过运行中文件的旧偏移使最终shell rc=2，原日志planning.log保留；当前源码已冻结（frozen-files.sha256），planning-final完整重跑中，未提交/未写done。
done: 2026-10-05T08:04:07Z sha=109c7e49be82aad58e669a49c25128012aa167be 执行者全部完成，detached追加提交且工作区clean；仅4个bin+4个tests文件，无分支/push/真Herdr/模型会话。场景1：QWB_ROLES_POLISH_ONLY=plan bash tests/collab-planning.sh、同变量gate bash tests/collab-gate.sh通过；预算对象/目录票名/多workers键/缺full均保留拒绝前缀、退出码与票字节，合规示例成功；required必须full且fast/full并集覆盖。起点plan-red/gate-red均rc=1，候选plan-green/gate-green3均rc=0；日志前缀=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/
done: 2026-10-05T08:04:07Z sha=109c7e49be82aad58e669a49c25128012aa167be 场景2：QWB_ROLES_POLISH_ONLY=route bash tests/collab-planning.sh起点rc=0，PASS=3 FAIL=0；plan-assign授权行及需求原话均给planner-pane，ctl没有该行门铃，不伪造handled，事实3不成立按规格跳过第2项路由改动；planning-final完整入口亦保持。场景3/4：QWB_NOTIFY_ONLY=E bash tests/collab-land.sh，status-stable rc=0 PASS=4 FAIL=0；verified无待办列表、有精确历史计数，真实blocked行与仅撤本票改动的基线逐字节相同；起点status-red rc=1。日志前缀=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/
done: 2026-10-05T08:04:07Z sha=109c7e49be82aad58e669a49c25128012aa167be 场景5：bash tests/collab-land.sh roles-polish，land-green3 rc=0 PASS=4 FAIL=0；起点land-red rc=1且main已快进，候选活工人拒绝时main不动，窗口/关闭出路/同op重跑成功；finish两处窗口提示及已部分land续接均保留，无重复merge。场景6：合规plan-assign/gate-assign、已停工人land与旧票status的stdout/stderr/rc/票字节逐字节一致，基线为当前脚本只撤本票改动；见plan-green/gate-green3/land-green3.log。日志前缀=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/
done: 2026-10-05T08:04:07Z sha=109c7e49be82aad58e669a49c25128012aa167be 定向逐个：bash tests/collab-planning.sh rc=0 PASS=37 FAIL=0（planning-final.log）；bash tests/collab-gate.sh 0/29/0（gate.log）；bash tests/collab-land.sh 0/58/0（land-final.log）；bash tests/collab-handoff.sh 0/12/0（handoff.log）；bash tests/wake-block-output.sh 0/20/0（wake-block.log）；python3 -B tests/roles_polish_fixture.py 0/1/0（fixture.log）。bash bin/qwb-test.sh fast 0/0/0（fast-ship.log），bash bin/qwb-lint.sh 0/9/0且LINT PASS（lint-ship.log）；未跑仓库全门。日志前缀=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/
done: 2026-10-05T08:04:07Z sha=109c7e49be82aad58e669a49c25128012aa167be 已逐名搜collab-planning.sh、collab-gate.sh、collab-land.sh、roles_polish_fixture.py及4个改动bin文件在tests/smoke.sh/tests/collab-all.sh的清单/组数/PASS断言，无改名，既有15项清单与动态计数无需改；helper由planning引用，collab-all.sh仅选helper自检44文件rc=0（entry.log）；检索原文entry-search.log。Bash3.2：四bin语法通过，agent-shapes-stable 0/34/0、plan-bash32 0/4/0、gate-bash32 0/2/0。8文件冻结哈希一致，本票测试进程零残留；汇总final-receipts.json；日志前缀=.worktrees/roles-polish-code/.qwb-tmp/roles-polish-evidence/
working: 2026-10-05T08:42:39Z 主控验收：工人提交 109c7e4 合入主干为 534f966。主控读过全部脚本改动；合并后自跑 collab-land 58/0、collab-planning 37/0、collab-gate 29/0、账本检查通过。任务书事实 3（主控自己的授权行成了主控待办）被工人对照代码证伪：该行路由给规划窗口，第 2 项按规格跳过。合并后主干 a4ddc78 全门 rc=0、861 PASS、0 FAIL（724 秒，.qwb-tmp/ctl-full-merge11.log）；真机端到端第 15 轮 15 项断言全 PASS（docs/reviews/2026-10-05-e2e-real-claude-pi-r7.md）。
