# 任务书：第五轮演练暴露的说明书矛盾与缺口

```
任务 id:  roles-r5-docs
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第五轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r5.md 的 V4、V5）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-roles-r5-docs.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控照着说明书和脚本提示就能走通，不靠猜、不做白工。

第五轮演练（Claude Code 当副主控）里，主控有几处是被彼此矛盾或没写清的说明书绊住的。演练记录先读 `docs/reviews/2026-10-05-real-herdr-roles-drill-r5.md`；演练主控的原始笔记在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r5/notes.md`（只读）。**本票只改说明书与配置注释，不改任何脚本行为。** 下面标「主控已核对」的是主控对着文件看过的；标「演练记录」的是演练主控的说法，写进说明书之前逐条对照代码或公开入口的实际输出核实，不符就写 `needs-decision:`。

### 要做的事

1. **值守说明里关于 Claude 活动判定的过时说法（主控已核对文字，适用范围待你核实）。** `templates/host-watch-guide.md` 第 28 行写「Claude及其他CLI的idle未核验，报告unknown并拒绝据此复用/收尾」。现在 `bin/qwb-herdr.sh` 的 `activity` 已有 Claude 分支（约第 207 行起：按会话号找会话文件、未配对的工具调用算忙、回合结束接受 `idle` 与 `done`），Claude Code 也可以当规划常驻职责。先读代码确认这个分支对哪些窗口生效（常驻职责、`qwb-run.sh` 派出的 Claude 工人各自是什么结果）、哪些情形仍然报 `unknown`，再把这句话改成与代码一致的说法；Claude 以外的其他 CLI 仍未核验这一点保留。
2. **主控窗口号该不该写进配置，两处说法相反（主控已核对）。** `templates/config.sh` 第 17 行注释写「主控 pane id；开局点名时填入」；`templates/host-watch-guide.md` 第 7 行写「当前主控 pane 从 `HERDR_PANE_ID` 取得，不把动态 pane ID 写入 `qwbuddy/config.sh`」。代码里 `bin/qwb-wake.sh` 只把它当 `--pane` 的缺省值（第 58、104 行）。核实各入口实际从哪里取主控窗口后，把 `config.sh` 这一行的注释改成与值守说明一致的说法（只改注释，不改键名与默认值）；`templates/QWBUDDY.md` 的开局步骤如有同样的矛盾一并改。
3. **说明书没写清的几处（演练记录，逐条核实后写进 `templates/roles/常驻流程.md` 或对应角色说明的相关步骤，每条一两句）：**
   - `qwb-send.sh send` 输出的事件号带 `send:` 前缀，后续命令原样使用，不要去掉前缀。
   - 副主控新开的票在派工前状态是 `blocked`，派工后才变 `running`，这是预期现象。
   - 落地前怎样确认工人进程已经退出（`qwb-worktree.sh land` 现在会在写入者未退出时拒绝并给出关闭窗口的命令；说明书写明落地前要做的确认动作与这条拒绝信息的关系）。
   - 怎样在不读脚本源码的前提下查看某个工人名对应的启动参数（先找有没有公开入口；没有就写明 `qwbuddy/workers.sh` 是配置文件、可以直接读对应那一行）。
   - Claude Code 当副主控时特有的三点：项目目录没被信任时 `qwb-role.sh start` 会拒绝并给出恢复命令；握手最长等 120 秒；副主控窗口不在前台时 Herdr 报 `done`，与 `idle` 同样算回合结束。事实依据见 `docs/reviews/2026-10-05-claude-code-herdr-probe.md`，逐条对照 `bin/qwb-role.sh` 与 `bin/qwb-herdr.sh` 的现行代码后再写。
4. 改动涉及从说明书原样取块执行的部分时，`tests/roles-walkthrough.sh` 必须照旧通过；本票预期不需要改测试，如需改动先写 `needs-decision:`。

白名单：`templates/host-watch-guide.md`、`templates/config.sh`（仅 `QWB_CONTROLLER_PANE` 一行的注释）、`templates/QWBUDDY.md`、`templates/roles/常驻流程.md`、`templates/roles/主控.md`、`templates/roles/规划.md`（各仅相关句子）。安装器会把模板复制进项目，测试里若有对这些文件逐字比对或行数、字数上限的断言，同步所需的最小改动自动算在白名单内，并在 `done:` 行写明。

## 1. 验收场景

1. 值守说明里关于 Claude 活动判定的说法与 `bin/qwb-herdr.sh` 现行代码一致：`done:` 行写明你核对到的各情形结果与代码位置。
2. `QWB_CONTROLLER_PANE` 在 `config.sh` 注释、值守说明、总说明三处说法一致，且与各入口的实际取值顺序相符。
3. 第 3 项的每一条都能在说明书里找到对应句子；每条在 `done:` 行写明核实方式（代码位置或公开入口的实际输出）。核实后发现演练记录不成立的条目不写进说明书，在 `done:` 行说明。
4. `bash tests/roles-walkthrough.sh` 通过，PASS 行数不少于改动前。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时有另一张票 `worker-silent-end` 在改 `bin/qwb-wake.sh`、`bin/qwb-run.sh`、`bin/qwb-lib.sh`、`templates/config.sh`（新增一行 `QWB_SILENT_END_MS`）、`templates/roles/审核者.md` 与 `templates/roles/门禁.md`；本票不碰这些脚本与那两份角色说明，`templates/config.sh` 只改 `QWB_CONTROLLER_PANE` 那一行的注释。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 定向：`bash tests/roles-walkthrough.sh`；另在 `tests/` 下搜被你改动的模板文件名，凡是读取这些模板做断言的测试文件各单独跑一次，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（全门由主控合并后串行跑）。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T10:37:35Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-roles-r5-docs pane=w14Z:p1H dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs base=a508d7c
working: 2026-10-05T10:40:27Z 已完整读取规格、第五轮演练及Claude探测记录，完成模板与公开入口代码核对；Claude活动分支适用于常驻和普通工人，完整身份/会话证据不足仍unknown，后台命令不能以idle证明退出；正在取得改前walkthrough完整基线并准备最小文案修订，原始日志位于隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/。
working: 2026-10-05T10:45:48Z 文案修订完成并冻结：仅host-watch-guide、config的QWB_CONTROLLER_PANE注释、QWBUDDY、常驻流程、规划5文件；walkthrough改前rc=0/PASS=22/FAIL=0。已启动串行快门、自检、改后walkthrough与逐文件定向检查；可执行块与测试未改，日志/退出回执在隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/，不跑全门。
working: 2026-10-05T10:50:19Z 文案复核收敛：明确process-info只取PID、启动时间用ps核；补清Claude会话未落盘时working/blocked为busy、其余unknown，避免空闲规则过度概括。当前walkthrough自然结束后已回收暂停的初验监督，最终5文件重新冻结，所有要求检查从final/独立日志重新串行执行；首次工具超时的空scope/socket已按原owner精确回收。
working: 2026-10-05T10:56:27Z 最终walkthrough完整通过：rc=0/PASS=22/FAIL=0，与改前22 PASS一致，两条修订路径均走到两票verified及候选清理；最终快门rc=0，自检rc=0/PASS=9/FAIL=0且LINT PASS。继续串行执行读取受影响模板的各定向测试，原始输出与回执在隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/final/。
working: 2026-10-05T11:05:18Z 定向阶段进展：collab-roles rc=0/PASS=39/FAIL=0；collab-land rc=0/PASS=58/FAIL=0，已实证工人未退的拒绝/关闭后同op恢复；collab-ci-diagnostics rc=0/PASS=6/FAIL=0。继续门控、规划、交接及安装配置等逐文件检查，最终日志仍在隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/final/，模板摘要未变。
working: 2026-10-05T11:18:11Z 门控定向已完整通过：collab-gate rc=0/PASS=29/FAIL=0；规划测试持续推进，已通过开票/事件引用/授权依赖/修订旧证据失效与监督静默边界，当前尚未收齐该文件退出回执。没有规格阻塞，按要求继续后续逐文件测试；最终源文件未改，日志位于隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/final/。
working: 2026-10-05T11:23:13Z 规划定向完整通过：collab-planning rc=0/PASS=40/FAIL=0，涵盖new初始blocked、真实send来源、Claude规划祖先进程身份及授权/预算拒绝；collab-gate已rc=0/PASS=29/FAIL=0。进入测试策略、交接与剩余模板读取测试；无规格阻塞，继续执行，最终5文件摘要保持冻结。
working: 2026-10-05T11:23:42Z 主控追加（第六轮演练刚出的四条，同属说明书范围，白名单相应加上 templates/workers.sh 的注释行）：一、templates/workers.sh 第 8 行注释「Claude Code role控制未验证，明确拒绝」与现状矛盾（Claude Code 可当规划职责，开关是 QWB_ROLE_CLAUDE_CONTROL），改成与 bin/qwb-role.sh 现行判定一致的说法，只改注释。二、qwb-role.sh start 与 status 的输出里顶层 activity 为 idle、activity_evidence 里的 activity 为 unknown（proof 为 native-pid+unpersisted-session）可以同时出现，说明书写一句这两个字段各自的含义与以哪个为准（先读代码核实）。三、步骤 04 副主控开票后主控被叫醒时，哪些交接要主控办、哪些不用办：演练主控看到 plan-assign 与 new 派生的进度行出现在未结义务筛选结果里并把它们办了；对照 qwb_task_obligations_json 核实这是不是预期，再在步骤 04 之后补一句怎么做。四、门控的通过结论与交还 claim 的通知可能在同一次叫醒里一起到达，说明书现在写成两次，补一句两种情况都正常。演练主控的原始记录在 /Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r6/notes.md（只读）；每条照旧先核实再写，不成立的不写并在 done 行说明。
working: 2026-10-05T11:29:10Z 已完整读取主控11:23:42Z四条追加及r6原始笔记，并核实现行代码：workers注释修为Claude仅规划+显式开关；Pi顶层activity与未落盘探针unknown分义；plan-assign/new虽working行仍属协议义务，真实qwb_task_obligations_json离线反例已证明；通过/交还同次或分次唤醒均可按claim读回续步骤11。已在当前Herdr定向自然退出后冻结最终6文件并续原串行检查；执行块及workers非注释声明逐字节不变，后续补跑最终walkthrough/roles/fast/lint，证据在隔离副本.qwb-tmp/roles-r5-docs.Pfov8ddL/。
working: 2026-10-05T11:32:10Z 主控追加第五条（真机故障注入刚验证出的缺口，白名单相应加上 templates/roles/门禁.md 与 templates/roles/收件箱约定.md 的相关句子；另一张票 worker-silent-end 在 templates/roles/门禁.md 与 templates/roles/审核者.md 各加了一行，你不要动它加的那一行，自己的句子另起一条）：收到门铃「工人已收工但没有报告」之后派工者该怎么做，说明书没有写。真机上副主控卡在这里：它读了工人窗口、判断工人没干完，然后认为「在窗口里另发提示等于绕过 qwb-run 另派一次工」，又没有预算重派，于是只在自己窗口里说需要主控处理，没有走任何正式渠道，链路停住（原始记录 /Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r6/evidence/r6bc/pane-w1-p2.txt，只读）。主控定的口径，写进 templates/roles/规划.md、templates/roles/门禁.md 与 templates/roles/常驻流程.md 的相应位置：一、先读工人窗口。二、工人已经做完只是没回票：派工者可以直接在该工人窗口发一条单行提示，内容仅限要求它按原票把结果写成状态行，不得新增或改变任务内容；这不算新派工、不占启动预算（写出具体命令形式，先核实 herdr agent prompt 对工人名的用法与提示词单行不超过 600 字符的现有规定）。三、工人没做完、被人叫停或情况不明：派工者不自行重派，必须经正式渠道上报主控后才结束回合，只在自己窗口里说不算上报。规划与门控各自能用哪个正式入口把这件事交给主控，你对照代码核实后写成可照抄的命令（例如规划能否在票上追加 needs-decision 或 blocked 行、该行是否会门铃主控；门控同理）；如果核实下来某个角色没有任何可用的上报入口，写 needs-decision 告诉主控，不要编一个。
needs-decision: 2026-10-05T11:36:26Z 第五条的正式上报入口存在运行时缺口：当前bin/qwb-ledger.sh:611-613允许规划handoff-send/append，但禁止门控handoff-send；bin/qwb-wake.sh:770-786将无controller_hint的交接送回规划，门控pending/rework且持claim则优先送回门控。规划自己的send或needs-decision没有planner_controller_hint（ledger:730-747），不能保证门铃主控；门控append同样自路由，release后有规划授权又会落规划。gate-verdict仅接受accepted/rework（1342-1400），不能伪造rediagnose绕过。请主控给出已存在且可验证的正式入口，或另票补上报协议后明确本文命令；本票不改放行/权限脚本，先继续核实读窗和完工只催回票部分。
working: 2026-10-05T11:36:55Z 主控裁决：你核实的结论成立——规划与门控现在都没有能保证叫到主控的正式上报入口，这是运行时缺口，不在本票补。主控另开票用值守自动升级来补（派工者被提醒后若干分钟、同一次收工仍未报告，就由值守直接门铃主控一次），那张票自己负责在说明书里写升级这一句。本票第五条因此收窄为三点，只写现在已经成立的行为：一、收到这条门铃先读工人窗口。二、工人已做完只是没回票：派工者可在该工人窗口发一条单行提示，仅要求按原票补写状态行，不算新派工、不占启动预算（命令形式照你核实的写）。三、工人没做完、被人叫停或情况不明：派工者不自行重派、不改票的规格，在票上用自己有权限的公开入口追加一条 working: 行写明核查结论（看到了什么、为什么不能继续），然后结束回合；不要写「会有人来处理」之类本票无法保证的话，也不要写任何尚未实现的升级行为。其余四条追加与原任务照做，做完写 done。
working: 2026-10-05T11:40:31Z 已执行主控11:36:55Z收窄裁决：第五条只写读工人窗口、单行≤600字符原票补回票（agent取匹配dispatch注册名，不加任务/预算）、未完成/被停/不明时本人公开append working核查并读回结束；不承诺上报或未实现升级。已追加规划/门禁/收件箱/常驻流程相关句子，未动另一票的新增行；最终8文件重新冻结，17/4/1原可执行块不变，全部bash块语法与链接通过。续剩余定向及最终补验，仍不跑全门、不碰真Herdr或模型。
working: 2026-10-05T11:50:39Z 第五条收窄文案已写齐并冻结8文件；新补回票块原样离线检查通过，注册名/原票保真，换行及超600字符发送前拒绝。剩余安装配置测试已通过：optional-routing rc0/P58/F0、pi-profile rc0/P5/F0、on-demand-guide rc0/P0/F0、worker-config rc0/P21/F0、subscribe-reap rc0/P8/F0；冒烟仍在既有异步子测试中执行。lint-scenario-stream rc0/P7/F3，3条FAIL为源码逐条断言的预期负例，不改断言/测试；汇总辅助脚本的计数误判会在最终按逐文件自然rc复核并保留原回执。
done: 2026-10-05T12:06:23Z 提交 3a7b06551d7d5c9e5dd885ed6d284ed618b12d2e；原任务、四条追加与11:36:55Z收窄后的第五条均完成。仅8个获批文件：host-watch-guide/QWBUDDY/config注释/workers注释/常驻流程/规划/门禁/收件箱约定；无bin/tests改动，无测试适配，无分支/push，工作区干净。证据根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL；总览final-summary.md、final-report.json，所有原始输出在final/、r6/。
done: 2026-10-05T12:06:23Z Claude核实：bin/qwb-herdr.sh:160-250为常驻规划与普通工人共用探针；PID/启动时间、session ID、唯一JSONL与初始cwd/消息身份完整时，未配对工具或working/blocked为busy；无未配对工具且末assistant/规定工具打断记录、原生idle/done才为idle；身份/目录/文件唯一性/记录/结束证据不足为unknown。未落盘时working/blocked为busy，其余unknown；其他CLI空闲仍unknown。pane不存在为dead，前台纯shell可idle但不等于原启动代死亡。
done: 2026-10-05T12:06:23Z 调用者边界：qwb-role.sh:230-247另核本代PID/session与实际model/effort，异常顶层unknown、busy映射working；qwb-run.sh:430-442及qwb-herdr.sh:393-400复用另核原派发PID/start/session，初次未绑定会话拒绝。role:267-273允许已核页脚/PID/session的空白Pi会话顶层idle/done而activity_evidence unknown；文案限定此例外，不作工人复用/退出证据。依据详见证据根/evidence.md。
done: 2026-10-05T12:06:23Z 主控pane取值已统一：lock:42默认HERDR_PANE_ID；Claude hook:52/87及Pi扩展:340/163核锁并走block，wake:1083/1092用HERDR_PANE_ID；手工投递目标wake:58/63/104按--pane→进入进程的QWB_CONTROLLER_PANE→config同名备用键取值。config只改单行注释，键/空默认值不变。send前缀由ledger:1527生成，后续按完整键使用；new在1115/1122初始blocked，run:718→prepare:1682在派发流程置running。
done: 2026-10-05T12:06:23Z 落地核查与配置查询已补：关闭前process-info --pane取PID，ps -p原PID -o lstart=核启动时间，关闭后复核原代已退并核lsof无cwd/FD；worktree:264-288/664-669保留拒绝与pane close出路，同op/auth重试，collab-land已实证。任意工人argv无通用查询入口，run --help:33-38指向可直接读的workers.sh配置。Claude信任失败恢复与120秒握手见role:348-377，done/idle共用herdr探针；原始公开帮助在证据根/public-help.log。
done: 2026-10-05T12:06:23Z 四条追加完成：workers:4-8仅修注释，Pi/Claude opt-in范围对齐role:200-208及profile；所有非注释工人/家族声明和argv逐字节不变。常驻流程01解释双activity；04主控读回规划结果、plan-assign/new协议交接后按02 ack办理，普通append working及已满足项不办、plan-ready留副主控；08-10说明通过/交还同次或分次均正常，accepted+claim空直接11。lib:473-550真实义务读模核验日志=r6-obligations.log。
done: 2026-10-05T12:06:23Z 第五条依11:36:55Z裁决：先读匹配pane/op的工人窗口；确已完工才以dispatch.agent注册名发单行≤600字符原票补回票提示，仅已有结果，不改任务、不占启动预算。未完/被停/不明只用本人append working记录观察和原因，读回结束；门控保留claim，不承诺主控上报/未实现升级。prompt用法见本地herdr帮助与run:868/877，append权限见ledger:611-623/1663；原样命令块与长度/换行拒绝检查=r6-result-reminder-check.log，路由缺口证据=r6-report-routing.log。
done: 2026-10-05T12:06:23Z 最终8文件补验原始路径=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL/r6/：fast rc0/PASS0/FAIL0；lint rc0/PASS9/FAIL0且LINT PASS；roles-walkthrough rc0/PASS22/FAIL0；collab-roles rc0/PASS39/FAIL0。改前完整walkthrough同为rc0/PASS22/FAIL0（baseline-complete.log/.rc）；17正常、4修订、1派出后修订块及actor/步骤标签逐字节保持，全部bash块语法/文档链接检查通过。
done: 2026-10-05T12:06:23Z 逐文件检查原始路径=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL/final/，各名对应同名.log/.rc，均自然rc0：collab-land PASS58/FAIL0，collab-ci-diagnostics PASS6/FAIL0，collab-gate PASS29/FAIL0，collab-planning PASS40/FAIL0，collab-test-policy PASS6/FAIL0，collab-handoff PASS12/FAIL0，collab-herdr PASS96/FAIL0，lifecycle-readiness PASS30/FAIL0。
done: 2026-10-05T12:06:23Z 其余逐文件检查原始路径=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL/final/，均自然rc0：optional-routing PASS58/FAIL0，pi-profile PASS5/FAIL0，on-demand-guide PASS0/FAIL0，worker-config PASS21/FAIL0，subscribe-reap PASS8/FAIL0，smoke PASS819/FAIL0且SMOKE PASS；fast PASS0/FAIL0，lint PASS9/FAIL0且LINT PASS，roles-walkthrough PASS22/FAIL0，collab-roles PASS39/FAIL0。
done: 2026-10-05T12:06:23Z lint-scenario-stream自然rc0/PASS7/FAIL3；三条FAIL是缺Given、缺失败路径及改指纹的预期诊断，源码逐条断言预期rc1，原始=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL/final/lint-scenario-stream.log。临时汇总器按FAIL计数误判而原始checks.rc=1已保留；独立核19项自然rc全0与三条预期诊断后verified-required-checks.rc=0，未改测试/断言/门。
done: 2026-10-05T12:06:23Z 收尾：所有本票测试scope/socket及四个临时监督PID均已退出回收，.qwb-tmp仅保留证据目录/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs/.qwb-tmp/roles-r5-docs.Pfov8ddL；首次60秒工具超时的原日志保留，旧scope/socket按原owner和真实lsof精确回收（timeout-scope-cleanup.json），不冒充首轮无回执为成功。未跑母本全门，未操作真Herdr，未启动模型会话，主账本state及他人行未改。最终提交仍为3a7b06551d7d5c9e5dd885ed6d284ed618b12d2e。
working: 2026-10-05T13:10:52Z 主控验收：提交 3a7b065 合入 main 为 7e7db04（templates/roles/门禁.md 一处相邻行冲突由主控手工解决，两边句子都保留）。主控逐行读过改动，并对着真实 Herdr 的帮助核对了新写的 pane read 与 process-info 两条命令的写法；主控独立跑 tests/roles-walkthrough.sh rc=0、22 PASS、0 FAIL，快门 rc=0，LINT PASS。第七轮真机演练里副主控按新写的「收工核查」步骤读了工人窗口并在票上写下核查结论。全门见之后的主控记录。
working: 2026-10-05T13:29:42Z 主控记录：main 7321f8a 全门 rc=0、865 PASS、0 FAIL、1084 秒（.qwb-tmp/ctl-full-merge15.log）。
