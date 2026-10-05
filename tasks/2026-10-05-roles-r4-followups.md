# 任务书：第四轮演练的说明书缺口与两处小缺陷

```
任务 id:  roles-r4-followups
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第四轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r4.md 的 U2–U9）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-roles-r4-followups.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r4-followups（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控照着说明书和脚本提示就能走通，不靠猜、不做白工。

第四轮演练里主控已经做到不读源码、零次被拒，但还有 4 处靠猜、10 条说明书缺口。演练记录先读 `docs/reviews/2026-10-05-real-herdr-roles-drill-r4.md`；演练主控的原始笔记在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r4/notes.md`，两张票的终态在 `.qwb-tmp/drill-roles-r4/evidence/`（只读）。演练笔记里的说法是演练主控的记录，写进说明书或据此改代码之前逐条对照代码核实；与代码不符就写 `needs-decision:`。

### 要做的事

1. **说明书补「工人已派出、尚未交付时来了修订」这一支（U2、U4）。** `templates/roles/常驻流程.md` 的修订一节现在只写了「开票后派工前」与「门控验收阶段」。补上第三种时机的完整做法，并说明前两种与它的区别。演练里走通的做法是：主控照常在来源票发修订请求；副主控 `plan-revision` 加 `revise`；旧规格下工人交来的 `done:` 不送门控，主控按 not-applied 办结并写明被哪次修订取代；主控 `plan-authorize` 后副主控重派，重派沿用原副本，并且（演练观察）复用原工人的同一个窗口与会话。逐条对照代码确认这些是脚本的实际行为再写（尤其「旧 `done:` 会不会被误送门控」「重派何时复用原工人、何时新开」），代码行为与演练观察不一致就写 `needs-decision:`。把这一支纳入从说明书原样取出执行的测试（与现有修订分支同样的做法）。
2. **重新授权之后不再给主控留一条要手工办结的阻塞（U3）。** 演练记录：`revise` 之后票上自动出现 `blocked: planner-not-ready … 首次启动无明确实施授权/预算`（写入处在 `bin/qwb-ledger.sh` 的 `plan-ready` 一段，约第 1149 行）并成为主控的待办；主控 `plan-authorize` 后它仍挂着。目标：同一 `spec_rev` 上主控已经 `plan-authorize`、随后出现就绪记录之后，这条阻塞不再算主控的未结义务，也不再被叫醒；复用 `bin/qwb-lib.sh` 的 `qwb_task_obligations_json` 里已有的「已被后续事件满足」分类，不另写一套。授权之前它照常是主控的待办（这是它存在的意义）。说明书在修订一节写明这条阻塞是预期现象、授权后自动了结。
3. **说明书讲清 `pending` 里哪些不用办（U5、U6）。** 写明：`qwb-send.sh pending` 列的是原始未办结交接；其中纯进度行、已被 `land-authorize` 满足的通过与交还通知、已有后续事件满足的记录不是未结义务，不办也不影响落地与结案，是否还有真正未结的以 `qwb-status.sh` 为准；`pending` 里收件人字段的含义与实际门铃对象的关系。先核对代码里 `pending` 的输出字段与 `--due` 的含义再写。常驻流程步骤 07 的批量办结循环如果因此显得多余或有误导，改成只办真正需要办的（测试同步）。
4. **自检不再把必填配置判成死配置（U7，主控已核对代码）。** `bin/qwb-lint.sh` 第 4 节只把脚本里以 `$` 读取的变量算作被引用；`bin/qwb-role.sh` 把 `QWB_ROLE_PI_CONTROL` 导出后在内嵌 Python 里读，于是项目按说明书配置了这一项之后自检整体 FAIL。改法：把「导出后供内嵌解释器读取」也算作引用（规则要窄，纯赋值与注释仍不算），并在 `templates/config.sh` 里加上 `QWB_ROLE_PI_CONTROL=""` 及一行说明（与已有的 `QWB_ROLE_CLAUDE_CONTROL` 并列）。加用例：安装后把这两项设为 verified，自检通过；真正没人读的键仍报死配置。
5. **去掉自相矛盾与含糊（U8、U9）。** 常驻流程前提里「全门要真正检查场景」与「不要为运行示例改门」的关系写清（示例说的是不要为了跑示例去动真实项目已有的门；项目的门是空命令时门控结论不能单独作证，这一点写给主控和门控）。`.roles/.prompts/` 下指令文件的回收规则写成可判断的条件（先读 `bin/qwb-lib.sh` 的 `qwb_shape_prompt` 与模板里现有那句，给出不依赖「相关读者」这种说法的规则）。

白名单：`templates/roles/常驻流程.md`、`templates/QWBUDDY.md`、`templates/roles/主控.md`、`templates/roles/规划.md`（各仅相关句子）、`templates/config.sh`（仅新增 `QWB_ROLE_PI_CONTROL` 一行）、`bin/qwb-lint.sh`（仅第 4 节的引用判定）、`bin/qwb-lib.sh`（仅 `qwb_task_obligations_json`）、`bin/qwb-ledger.sh`（仅当第 2 项的分类必须在这里同步，最小改动）、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_已派出后修订按说明书走通

Given 假 Herdr 的临时项目，副主控已派出工人、工人尚未交付或刚交了旧规格的结果
When  测试从装进项目的说明书里取出这一支的命令与样例，按顺序执行
Then  旧结果没有被送去门控，修订、重新授权、重做、验收、落地依次完成，两张票 verified；这条用例在起点提交上是红的（说明书里没有这一支），先跑出红并留证

### user_正常路径_重新授权后主控没有残留待办

Given 修订使派工授权失效、票上出现规划未就绪的阻塞
When  主控 `plan-authorize`，随后出现就绪记录
Then  这条阻塞不再出现在主控的未结义务里，值守不为它叫醒主控；这条用例在起点提交上是红的，先跑出红并留证

### user_失败路径_未重新授权时阻塞仍是主控的待办

Given 同上但主控还没有 `plan-authorize`
When  读主控的未结义务并跑一轮值守
Then  这条阻塞照常是主控的待办，与起点提交相同

### user_正常路径_启用常驻职责后自检通过

Given 全新安装后把 `QWB_ROLE_PI_CONTROL` 与 `QWB_ROLE_CLAUDE_CONTROL` 设为 verified
When  在该项目里跑 `qwb-lint.sh`
Then  第 4 节通过；这条用例在起点提交上是红的，先跑出红并留证

### user_失败路径_真正的死配置仍被报出

Given 配置里有一个任何脚本都不读的 `QWB_` 键
When  跑 `qwb-lint.sh`
Then  仍报死配置并点名这个键

### user_正常路径_说明书示例与其余行为不变

Given 改后的说明书与脚本
When  跑按说明书原样执行的全部既有用例，以及合规载荷下未涉及修订的票的值守、状态显示
Then  既有用例全部通过；未涉及本票改动的输出与起点提交逐字节相同（基线按第 2 节约束写成只撤掉本票改动）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时有另一张票 `worker-silent-end` 在改 `bin/qwb-wake.sh`、`bin/qwb-run.sh` 的审核提示词、`templates/config.sh`（新增一行 `QWB_SILENT_END_MS`）、`templates/roles/审核者.md` 与 `templates/roles/门禁.md`；本票不碰前两个脚本与那两份角色说明，`templates/config.sh` 只新增自己那一行。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 六个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/roles-walkthrough.sh`、`tests/collab-planning.sh`、`tests/collab-land.sh`、`tests/collab-handoff.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了通过条数、用例组数或文件清单的地方同步改成新值；这些行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T09:27:35Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-roles-r4-followups pane=w14Z:p1G dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r4-followups base=c62fea9
working: 2026-10-05T09:28:46Z 执行者已完整读取规格及演练记录；核对 qwb-run 的同名工人复用须身份、目录、Space、原dispatch与真实idle全部吻合，查询失败或忙碌均拒绝；旧done仍通知主控，是否送门控由主控gate-assign决定。接下来先补红测，再最小修复义务分类和lint，补说明书分支。
needs-decision: 2026-10-05T09:30:54Z U3前提与公开入口实测不符：本副本起点c62fea9中，plan-ready生成的blocked经qwb-wake --once送planner-pane，不是主控；controller_hint未将plan-ready列为主控专属。证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r4-followups/.qwb-tmp/roles-r4-evidence/red-ready.log（末尾fakeHerdr原文），该红不是目标缺陷红。请裁决：A保留现有路由，仅同spec授权+ready自动满足（建议，符合不改权限范围）；B另授权修正主控路由并同步脚本白名单。其余U2/U4–U9继续实施。
working: 2026-10-05T09:32:41Z 主控裁决：选 A。保留现有路由（plan-ready 生成的阻塞送规划），不改权限与路由；只做「同一 spec_rev 上主控已 plan-authorize 且随后出现就绪记录之后，这条阻塞自动算已满足」，对规划与主控都不再是未结义务、不再叫醒任何人。任务书里「成为主控的待办」是演练主控的记录（它在 pending 里看到并办了），以你对代码与公开入口的实测为准；说明书相应写成：这条阻塞是预期现象，授权并就绪后自动了结，主控不用办。场景 2、3 里的「主控」按实际收件角色改写。
