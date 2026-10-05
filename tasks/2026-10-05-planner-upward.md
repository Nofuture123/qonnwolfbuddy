# 任务书：副主控派出去的活做完后，主控必须被叫到

```
任务 id:  planner-upward
state: verified
implementation-authorized: Rocky 2026-10-05 确认副主控即 secondmate、隶属主控；2026-10-04 起的整仓审核与修复授权
dispatch-budget: 4
来源:     2026-10-05 副主控与门控真机演练（docs/reviews/2026-10-05-real-herdr-roles-drill.md 的 D4、D6）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high；跨模块改动按派工规则用强档）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-planner-upward.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：副主控是主控的直接下属，像 First Mate 的 secondmate：主控把一块活交给它，它自己开票、派工、盯工人；主控不替它盯工人，但活的结果必须回到主控手里。

### 真机上看到的事实（主控已核实，全文见演练记录）

1. 主控 `plan-assign` 授权后，规划（副主控）被门铃叫醒、`new` 开票、`qwb-run` 派工，全部成功。
2. 工人写下 `done:` 之后，这条事件被门铃给了规划 pane；规划逐条 received、accept、prepared、handled，并在自己窗口里写「待主控安排门禁」。**没有任何东西通知主控**：主控结束回合后 24 分钟没被叫醒，门禁从未被授权。
3. 根因在 `bin/qwb-wake.sh` 的 `route_gate_due`（约第 646–712 行）：票上只要有规划授权（`planning_authority` 或 `planning.authority`），整票所有到期交接都门铃给规划 pane；规划 handled 之后主控的待办集合为空，Stop hook 无事可叫。
4. 同一段里，门禁分支只认 `verdict` 为 `pending` 或 `rework`；`accepted` 之后的到期交接同样会落到规划分支，而落地是主控的事。这一条主控只读了代码，没有在真机上走到。
5. 工人每条 `working:` 进度都门铃规划一次（演练里 01:30:58Z、01:31:21Z、01:31:28Z 三次）。未迁旧票已在 `wake-tighten` 票里改成进度行不叫醒，已迁票没有覆盖。

### 必须成立的性质（怎么实现由你设计）

- **P1 交付必达主控。** 带规划授权的票上，工人写下 `done:` 之后，主控 pane 在一轮值守内被门铃，摘要点明是哪张票、工人已交付、下一步是主控安排门禁。这件事不能依赖规划模型主动做任何动作。
- **P2 规划仍然管自己的工人。** 工人的 `blocked:`、`needs-decision:`、工人丢失，先到规划；规划在授权范围内能解决的（答复、在预算内续派）自己解决。规划办理完这类事件时，主控要能确定地得到结果：要么脚本在规划写下 handled 时自动给主控生成一条带规划办理结果引用的交接，要么你设计出同样不依赖模型自觉的机制。规划不办（超时未 handled）时，现有的重试与预算耗尽逻辑要最终落到主控。
- **P3 验收结论回到主控。** 门禁给出 `accepted` 之后，该票后续到期交接门铃主控，不门铃规划。
- **P4 进度不叫人。** 带规划授权的票上，工人的 `working:` 进度事件不门铃任何人；工人挂起与丢失的现有兜底不能因此失效，兜底触发时门铃规划。
- **P5 不破坏现有约定。** 只有一个值守监督者，不新建第二个；交接的 received、accept、prepared、handled 语义不变；派生出来的交接幂等（同一来源事件重放不产生第二条）；门铃前的身份复核（`gate_proof` 两次）不减少；规划身份失效时照旧回落主控。
- **P6 其余票逐字节不变。** 没有规划授权的已迁票、未迁旧票、门禁已 claim 且 `pending` 或 `rework` 的票、测试体系请求的路由，行为与起点提交逐字节相同。

### 分两步做

**第一步：只写设计，不改代码。** 读 `bin/qwb-wake.sh`（`collect_due`、`route_gate_due`、`record_transport`、`compose_msg`）、`bin/qwb-ledger.sh`（交接事件的生成与 handled、`plan-ready`、`dispatch` 之后工人状态行如何变成交接事件、`gate-verdict`）、`bin/qwb-send.sh`、`templates/roles/规划.md`、`主控.md`、`门禁.md`、`收件箱约定.md`，以及 `tests/collab-planning.sh`、`tests/collab-handoff.sh` 里现有的路由用例。然后在副本里写 `docs/designs/2026-10-05-planner-upward.md`（不超过 80 行），内容：

- 现状：一张带规划授权的票从派工到落地，每类事件现在门铃谁（列表）。
- 方案：P1–P4 各自改哪里、新增什么事件或字段、主控收到的摘要长什么样（给出原文示例）。
- 对 P2 你选哪种机制、为什么；另一种为什么不选。
- 幂等与恢复：重放、规划换代、主控换代、值守重启各自怎么保证不丢不重。
- 会改到的现有测试断言清单与理由；哪些地方你读不出确定答案。

写完提交这份设计文档（单独一个提交），往主账本写一行 `needs-decision:`，内容是设计文档路径与三句话摘要，然后**停下等主控确认**，不要开始实现。

**第二步：主控确认后实现。** 主控会在主账本追加一条 `working:` 行说明确认或修改意见，并续派你。按确认后的设计实现、补测试、跑门。

白名单：`bin/qwb-wake.sh`、`bin/qwb-ledger.sh`、`bin/qwb-send.sh`、`bin/qwb-lib.sh`（仅当确有共用需要）、`docs/designs/2026-10-05-planner-upward.md`、`templates/roles/规划.md`、`templates/roles/主控.md`、`templates/roles/门禁.md`、`templates/roles/收件箱约定.md`（四份角色说明只改与本票机制直接相关的句子）、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景（第二步的验收；第一步只交设计）

### user_正常路径_工人交付后主控被门铃

Given 一张带规划授权的已迁票，规划已派工，工人写下 `done:`，规划没有任何动作
When  值守跑一轮
Then  门铃发到主控 pane，摘要含票名、工人已交付与「安排门禁」的指向；规划 pane 没有因这条事件被门铃；这条用例在起点提交上是红的

### user_失败路径_工人阻塞先到规划且结果确定到达主控

Given 同上，工人写下 `blocked:`
When  值守跑一轮；随后规划 handled 这条事件；值守再跑一轮
Then  第一轮门铃规划；规划 handled 之后主控收到一条带规划办理结果引用的交接并被门铃；把同一条 handled 重放一次，主控不会收到第二条

### user_失败路径_规划不办理时最终落到主控

Given 工人写下 `needs-decision:`，规划始终不 received
When  按现有重试预算耗尽
Then  该事件转交主控并门铃，票上保留待办；行为与现有预算耗尽约定一致

### user_正常路径_验收通过后交接回到主控

Given 带规划授权的票，门禁已给出 `accepted`
When  该票出现新的到期交接
Then  门铃主控，不门铃规划

### user_正常路径_进度事件不门铃任何人

Given 带规划授权的票，工人连续写三条 `working:` 进度
When  值守各跑一轮
Then  零门铃、不写 `wake:` 行；随后工人丢失时照现有规则门铃规划

### user_失败路径_规划身份失效时回落主控

Given 规划 pane 已不存在或代次不符
When  出现本应门铃规划的事件
Then  门铃主控，行为与起点提交相同

### user_正常路径_其余票逐字节不变

Given 起点提交与改后的脚本
When  对没有规划授权的已迁票、未迁旧票、门禁 `pending` 与 `rework` 的票、测试体系请求各跑现有用例
Then  stdout、stderr、退出码、票内容、Herdr 调用序列新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不放松任何身份、授权、预算、claim 核对；不让规划获得验收、落地、改 state 的权限；不让主控的锁语义发生变化。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。假 Herdr 的应答形状照现有夹具，不凭空造字段。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 同时有别的票在改 `bin/qwb-run.sh` 与 `bin/qwb-herdr.sh`（提示词提交确认、续派身份绑定）以及 `qwb-ledger.sh` 里 `new` 生成票正文的那一行；这些地方本票不要碰。

## 3. 验收门（第二步）

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
第一步结束打印 DESIGN 加设计提交的 sha；第二步结束打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 第一步不改任何脚本与测试。
- 不新增常驻角色、不新增值守进程、不改主控锁；不处理 Claude Code 当常驻角色的问题。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T02:44:01Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-planner-upward pane=w14Z:p0 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward base=d66d77c【主控更正：这次派发因主控脚本补丁未生效误用了 sol high，工人未产出任何改动即被主控关闭 pane；以下一条派发行为准】
working: 2026-10-05T02:44:44Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-planner-upward pane=w14Z:p11 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward base=d66d77c
working: 2026-10-05T02:47:10Z 执行者已完成指定源码、角色约定和两份现有测试的只读梳理（base=d66d77c）；确认整票规划路由吞交付，handoff三次预算耗尽只留pending且已迁分支跳过worker_lost/时间兜底；正编写第一步设计，不改实现。
needs-decision: 2026-10-05T02:50:39Z 设计已单独提交 eae86b0dcc4d2267ccbfcdc7487a5ab7417ade22，文档=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward/docs/designs/2026-10-05-planner-upward.md（71行；git diff --cached --check通过，提交后git status --short为空；未改脚本/测试，未运行真Herdr或模型）。方案以真实事件逐项分流，工人done与accepted交主控，规划handled在同次原子发布派生带结果引用的上行交接。补齐基点实际缺失的三次预算耗尽升级与已迁票丢失/停滞兜底，保留单监督、双身份复核和原receipt权限，现按第一步要求停止等待主控确认。
working: 2026-10-05T02:53:19Z 主控确认设计（eae86b0），范围收窄后进入第二步。先更正：任务书 P2 写的「现有的重试与预算耗尽逻辑要最终落到主控」与 P4 写的「工人挂起与丢失的现有兜底」是主控写错了——如你查明，已迁票在 collect_due 里提前 continue，根本没有丢失/停滞兜底，三次投递后也没有任何升级。这两条的前提不成立。裁决如下。【本票做】① P1：工人 done 直接留给主控，摘要带「下一步：主控安排门禁」；门禁已 claim 且 pending/rework 时返修 done 仍先给门禁。② P3：accepted 与既定需主控重诊的后续到期交接留主控。③ P2 中的「handled 原子派生上行」：规划办理工人 blocked/needs-decision/question 交接时，同一次发布里生成 source:planner-result: 上行交接，带原交接 ID、规划 actor/op、result_ref、result_sha256；幂等按你的设计。④ writer 入口拒绝规划对主控专属来源（工人 done、迁入核查、accepted 后续、上行结果）做 received/accept/prepared/handled——演练里规划正是读了整票 pending 把 done 抢先办掉的，不拒绝 P1 就不确定；pending 读取仍给完整集合。⑤ 迁入核查交接归主控。⑥ 四份角色说明里与以上机制直接相关的句子。【本票不做，另开票】P4 整条（进度静默）、已迁票的工人丢失/停滞兜底、plan-watch 新写入命令、三次投递后的 planner-escalation 升级、qwb_task_obligations_json 的改动。理由：进度静默必须和兜底一起上，否则挂起的工人会变得无人知晓；这是一块新机制，要单独设计并真机演练。因此本票里工人 working 进度照旧门铃规划，行为不变。【验收场景调整】保留场景 1、2、4、6、7；场景 3（规划不办理最终落主控）与场景 5（进度不门铃）从本票删除；新增一条：规划对主控专属来源做 handled 被拒且票字节不变。【其余要求】按 P1+P3 路由、P2 派生与 writer 拒绝、角色说明 分成至少三个提交，便于主控逐个审；设计文档按本裁决更新一版并在首个实现提交里一起提交；tests/collab-planning.sh 另一张票（提示词提交确认）也改了夹具，你只做本票需要的最小改动。实现完按任务书第 3 节跑门并报告。
working: 2026-10-05T03:04:35Z 路由阶段已提交；P1混合done/blocked分流、P3 accepted、身份失效回落、working保持的定向门rc=0；起点d66d77c同用例因done仍到规划失败（baseline-red.log）；P6五类stdout/stderr/rc/票/Herdr逐字节一致，原始证据在本副本.qwb-tmp/planner-upward/compat-1，日志routes-2.log，fast-1.rc=0。继续原子结果上行与writer拒绝阶段。
working: 2026-10-05T03:18:25Z 原子上行与writer守卫实现完成；upward.log（含五类P6原始字节复验）rc=0、handoff.log rc=0、fast-2.rc=0；新增旧handled缺上行的恢复检查已通过，最后一轮定向收尾中。四份角色说明已按裁决同步；未改P4/兜底/升级/lib/run/herdr/new正文。独立审核由主控安排，本票遵守禁止启动模型会话限制。
working: 2026-10-05T03:20:02Z 已分别提交原子上行/writer守卫与四角色说明；路由提交be70cc3，后续提交见本副本git log。实现范围按02:53:19Z裁决完成；当前进入提交后全门验收，完整退出回执与残留检查后才写done。
working: 2026-10-05T03:25:44Z 提交前复查补正测试注入：每次gate_proof内有两次pane读取，现改为第三次读取失效，准确覆盖第二轮复核。旧定向回归及恢复用例rc=0；为使全门验证最终测试，主动中止首轮full（rc=143，非质量失败，原始日志full.log保留），即将以最终提交重跑；fast-final.rc=0。
working: 2026-10-05T03:39:20Z 最终提交a113258的full仍运行，已见两处非本票旧用例超时：smoke §12真看门狗15秒（假钟2900/3000）及process-entry-cleanup root-tab-missing入口90秒。原§12固定快照d66d77c/a113258串行对照均rc=0，日志clock-baseline.log/clock-candidate.log；未改任何原断言或时限。当前uptime观察load=61.84/75.62/68.74，只作环境证据，不据此宣布根因；继续收齐full原始退出回执。
working: 2026-10-05T03:41:50Z 更正前条观察：process-entry-cleanup.py 的入口 deadline 实为60秒，不是90秒；90秒是collab-planning另一层CLI预算，前条混淆。以原源码60秒为准，未改时限。§12起点/候选原断言已各自rc=0；full仍在收齐。
working: 2026-10-05T03:52:04Z 主控指令：候选 a113258 已收到，主控现在开始审读并在合并后的主干上串行跑全门。你那轮全门可以停掉（多轮全门并发互相挤出超时类假失败，结果不作数）；停掉后清理自己起的进程，确认 git status --short 为空，把已完成的定向验证与快门结果写成 done 行即可，全门一项写明「由主控合并后执行」。
done: 2026-10-05T03:54:27Z 候选=a11325822f0a138a35ee6e4fd6efac159d2d80d5；实现提交be70cc3（路由/设计）、e6ce693（原子上行/守卫）、d316729（四角色说明）、a113258（第二轮proof夹具）。按03:52:04Z主控裁决交付；bash bin/qwb-test.sh fast rc=0，原始日志/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward/.qwb-tmp/planner-upward/fast-final.log。范围内P1/P3、P2 handled原子上行及规划四入口拒绝均完成；P4/兜底/升级/lib/run/herdr/new正文未改。
done: 2026-10-05T03:54:27Z 定向：QWB_PLANNING_UPWARD_ONLY=1 bash tests/collab-planning.sh rc=0，场景1/2/4/6及新增writer拒绝通过；混合分流、结果引用/幂等、未知结果与发布失败无半状态、question不自动关闭、旧handled恢复均覆盖，日志/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward/.qwb-tmp/planner-upward/upward.log、upward-bash32.log。bash tests/collab-handoff.sh rc=0（handoff.log）。P1相同用例在d66d77c上rc=1，准确失败于done仍门铃规划（baseline-red.log）；末次提交仅修正第二轮proof的注入计数。
done: 2026-10-05T03:54:27Z 场景7：QWB_PLANNING_UPWARD_ONLY=1 QWB_PLANNING_UPWARD_COMPARE=1 bash tests/collab-planning.sh rc=0；无规划已迁票/旧票/门禁pending/rework/测试请求五类stdout、stderr、rc、票字节、Herdr序列均与d66d77c一致，原始证据/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-upward/.qwb-tmp/planner-upward/compat-2。全门：由主控合并后执行；我的并发轮已自然结束（full-final.log及rc保留，不作验收）。git status --short为空，测试进程及cwd占用均=[]，临时快照pb/pc已移除；见final-check.json。最终SHA=a11325822f0a138a35ee6e4fd6efac159d2d80d5。
working: 2026-10-05T04:12:24Z 主控验收：读完值守路由改动，与批准的设计（docs/designs/2026-10-05-planner-upward.md）一致；五个提交 eae86b0…a113258 已 cherry-pick 进 main（e7113c0…b6366c8），无冲突。合并后 main @ 015fb4f 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、731 秒（.qwb-tmp/ctl-full-merge5.log）。尚未做：真机演练重跑；已迁票进度行静默、工人丢失与停滞兜底、三次投递后升级另票。
