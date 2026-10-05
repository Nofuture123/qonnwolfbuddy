# 任务书：副主控与门控链路上还有四处「该叫的人没被叫」和一处「被自己写的行挡住」

```
任务 id:  collab-notify-gaps
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第二轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r2.md） 的 R3、R4、R6、R7
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-collab-notify-gaps.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控、副主控、工人、门控四个角色接力，任何一棒交出去，下一棒都要被叫到；主控不该干等，也不该在回合里轮询。

背景：副主控即「规划」常驻职责，门控即「门禁」常驻职责。此前两张票已做到：工人 `done` 与门禁结论回主控、副主控办完工人的阻塞类交接自动上报主控（`docs/designs/2026-10-05-planner-upward.md`）；纯进度静默、工人丢失与停滞兜底、交接三投耗尽升级（`docs/designs/2026-10-05-collab-silence-fallback.md`）。本票补真机演练第二轮暴露的剩余缺口。演练全文见来源文档，主控笔记原件在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r2/stage2-notes.md`（只读参考）。

### 事实（主控已核对演练记录；标明处已核对代码）

1. **门控第一次接手没有门铃（R4）。** 主控 `gate-assign` 成功后，门控在 claim 之前收不到任何通知。演练主控手写了一个文件到 `qwbuddy/.roles/gate.inbox/` 再用 `herdr pane run` 往门控窗口打字。值守现在只给「已 claim 且结论为 pending 或 rework」的票门铃门禁（`bin/qwb-wake.sh` 的 `route_gate_due`）。
2. **副主控办完主控交办的事，主控不知道（R3）。** 主控在入口票用 `qwb-send` 给副主控发了场景修订请求；副主控做完 `plan-revision` 与 `revise` 并办结了相关交接；没有任何东西通知主控，主控空等了 28 分钟。现有的「handled 时派生上行结果」只覆盖副主控办理工人的 blocked、needs-decision、question。
3. **登记的等待到期不触发重叫（R3，已核对代码）。** 主控对一条交接登记了 20 分钟等待；`handoff_due`（`bin/qwb-ledger.sh` 约第 624–632 行）在 `wait_until` 过后仍要求距 `activity_at` 与 `transport_at` 都超过重叫间隔（演练配置 30 分钟），所以实际 30 分钟才被叫。
4. **门控交还 claim 不叫醒主控（R7）。** 门控给出通过后，主控要等门控交还 claim 才能落地；交还不产生任何叫醒，演练主控在回合内轮询账本约 20 秒（说明书禁止）。
5. **收尾被主控自己写的行挡住（R6）。** `land-close` 被拒「收尾义务/用户问题仍未结」：`gate-verdict`、`land-authorize`、`land-prepare`、`land-apply` 各派生了一条给主控的交接，主控逐条走接收、接手、准备、办结四步后才收尾成功；收尾后写的那一行又再派生一条。

### 要做的事（分两步，先设计后实现）

**第一步：设计。** 读 `bin/qwb-wake.sh`、`bin/qwb-ledger.sh`（交接的派生、`handoff_due`、门禁各命令、落地各命令、`land-close` 的未结检查）、`bin/qwb-send.sh`、`bin/qwb-lib.sh` 的 `qwb_task_obligations_json`、`bin/qwb-role.sh` 的收件箱部分、四份角色说明、上面两份设计，写一页设计到 `docs/designs/2026-10-05-collab-notify-gaps.md`（80 行以内），提交后在主账本写 `needs-decision:` 等主控确认。设计要回答：

- A（门控首次门铃）：`gate-assign` 成功后怎样让门控被叫到。要求走值守现有的门铃通道与身份复核，不让主控手写收件箱文件；门控身份失效时回落主控并说明。幂等、值守重启恢复、与三投耗尽升级的关系。
- B（副主控办完主控请求要回报）：主控经 `qwb-send` 发给副主控的请求，副主控 handled 时同样原子派生一条上行结果给主控，复用现有派生机制；哪些来源算「主控发给副主控的请求」要按真实来源判定，不看正文。需求原话那条事件（`plan-assign` 绑定的来源）由谁办结、办结后要不要回报，一并给出规则。
- C（等待到期即到期）：本代接手人登记的 `wait_until` 过了之后，该交接应立即视为到期重提，不再叠加重叫间隔；说明这与「回复迟到不是失活」那段保护的关系，以及会不会造成频繁重叫（给出上限）。
- D（交还 claim 的通知）：门控给出结论并交还 claim 后主控怎样被叫到。可选方向：结论类交接在 claim 仍被持有时不向主控投递，交还后再投；或交还本身产生一条给主控的交接。选一个并说明主控被叫醒时能否直接落地。
- E（自己写的动作行不成为自己的待办）：主控执行 `land-authorize`、`land-prepare`、`land-apply`、`land-close` 各自写下的行，以及其他「写入者就是唯一应处理者」的动作行，不应派生需要同一角色再走四步办结的交接，也不应挡住 `land-close` 与票的结清。门禁结论给主控的那条交接是真通知，保留；但主控一旦对同一票完成 `land-authorize`，它应视为已被处理（给出判定办法）。列出现在会自我派生的行的种类与你的处理。
- 每一项对 events、handoffs 结构的改动（能不动就不动）、对未迁旧票的影响（应为零）、测试放在哪些已接入文件里；你认为本任务书前提有误之处逐条列出。

**第二步：实现。** 按主控确认后的设计实现，A 到 E 每项一个提交，每次提交保持快门通过。

白名单：`bin/qwb-wake.sh`、`bin/qwb-ledger.sh`、`bin/qwb-send.sh`、`bin/qwb-lib.sh`（仅 `qwb_task_obligations_json`）、`templates/roles/` 下四份角色说明里与这五项直接相关的句子、`docs/designs/2026-10-05-collab-notify-gaps.md`、`tests/` 下为验收所需的已接入文件。`gate_context` 与落地各步的「验收条件未变」比对另有票在改（`land-env-digest`），本票不碰那部分；`new`、`revise` 的场景校验与两处拒绝信息也另有票在改（`scenario-names`）。

## 1. 验收场景

### user_正常路径_门控授权后门控被叫到

Given 工人已交付，主控 `gate-assign` 成功
When  值守跑一轮
Then  门控窗口收到一次门铃，摘要写明哪张票待接手；主控没有写任何收件箱文件；门控 claim 之后不再重复这条门铃；这条用例在起点提交上是红的，先跑出红并留证

### user_正常路径_副主控办完主控的请求后主控被叫到

Given 主控经 `qwb-send` 给副主控发了一条请求，副主控接收、办理并 handled
When  值守跑一轮
Then  主控收到一次上行结果，带原请求标识与结果引用；重放 handled 不产生第二条

### user_正常路径_等待到期后立即重提

Given 主控接手一条交接并登记 20 分钟等待，重叫间隔为 30 分钟
When  假时钟推进到第 21 分钟
Then  该交接到期并叫醒主控一次；第 19 分钟时不叫

### user_正常路径_门控交还后主控被叫到且可直接落地

Given 门控给出通过并交还 claim
When  值守跑一轮
Then  主控被叫醒一次；此时执行 `land-authorize` 不会因 claim 仍被持有而被拒；主控全程不需要轮询

### user_正常路径_主控落地后可直接收尾

Given 门控通过，主控依次执行落地各步
When  执行 `land-close`
Then  成功，不需要先逐条办结自己那几步写下的行；票 verified 后 `qwb-status` 显示已结

### user_失败路径_真正未办的事仍然挡住收尾

Given 票上有一条工人的 blocked 交接没人办理，或有未答复的使用者问题
When  主控 `land-close`
Then  被拒，信息与起点提交相同

### user_失败路径_门控身份失效时回落主控

Given `gate-assign` 之后门控窗口消失或身份复核不过
When  值守跑一轮
Then  不向失效窗口投递；主控被叫醒一次并得知门控不可用

### user_正常路径_其余路径不变

Given 起点提交与改后的脚本
When  跑未迁旧票的全部值守用例，以及没有命中上述五项的已迁票用例
Then  标准输出、标准错误、退出码、票内容、Herdr 写操作序列新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 同时有另外两张票在改 `bin/qwb-ledger.sh` 的其他部分（见各自范围）；只动本票需要的最小区域，不顺手整理。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 八个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh`、`tests/collab-handoff.sh`、`tests/collab-gate.sh`、`tests/collab-land.sh`、`tests/collab-test-policy.sh`、`tests/wake-block-output.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（多个工人同时跑全门会互相挤出超时类假失败，全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了该文件 PASS 条数或用例组数的地方（例如冒烟某节的 `-eq 48`、`tests/herdr-batch.py` 的组数断言），同步改成新值；这些计数行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不扩大任何角色的写权限；不改主控锁、claim 的归属规则、验收门、五值 state、落地授权；宁可多叫一次主控，不可让要人处理的事沉默。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T05:23:12Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-collab-notify-gaps pane=w14Z:p19 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps base=4b1f2e2
working: 2026-10-05T05:25:08Z 执行者已完整读取任务书、两份前序设计、四角色说明与演练记录，并核对 wake/ledger/send、lib义务读模及role收件箱；基点4b1f2e2，工作区干净。正在编写A–E设计，尚未改产品代码；不触碰真Herdr或模型。
needs-decision: 2026-10-05T05:25:32Z 执行者核对补充前提：qwb-send只接受--to controller，未存历史实际目标；B须按真实handoff-send事件及规划grant绑定的controller来源判定，不能按正文或recipient认规划请求。C在transport_count>=3时先走handoff_fallback，已received交接直接停叫，等待到期修复须覆盖此分支。E的land-close当前检查全部未handled，连前票已静默纯进度也会阻断。拟在设计中统一有效义务分类并列明范围，提交后请主控确认；未改产品代码。
working: 2026-10-05T05:25:45Z 主控回复：三点补充前提都接受，按你的思路写进设计（统一有效义务分类，land-close 与结清判定用同一口径），设计提交后再等主控确认。
working: 2026-10-05T05:27:27Z 设计阶段已提交 a0c4ac59e8ea7b19faa9dc2493e7d5644975a3ad，仅新增 docs/designs/2026-10-05-collab-notify-gaps.md（68行）；git工作区干净。bash bin/qwb-test.sh fast rc=0，PASS=0、FAIL=0（快门成功静默输出），git diff --check=0；原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps/.qwb-tmp/notify-gaps-design/fast.log，退出码同目录fast.rc；未运行全门或行为验收。
needs-decision: 2026-10-05T05:27:27Z 请主控审定设计提交 a0c4ac59e8ea7b19faa9dc2493e7d5644975a3ad 后续做：A授权原子交接/合法claim满足；B主控真实send与原话handled原子回流；C到期先于三投封顶，之后最短30分钟重提；D门禁release独立通知；E统一有效义务分类，静默四类land动作及recover-claim，精确land-authorize满足当前verdict/release。05:25:45Z接受的三点前提已纳入。按任务书第一步暂不实现，等主账本最新working裁决。
working: 2026-10-05T05:27:43Z 主控确认设计（a0c4ac5），A 到 E 全部按设计实现，进入第二步。补充两点：① B 里「需求原话由规划办结、主控完成授权不等于替规划办结」这条规则，写进 主控.md 与 规划.md 各一句（主控 plan-assign 之后不要自己办结原话交接）。② D 的门铃摘要里写明主控下一步的两条命令名（接回 claim、land-authorize），不写参数。其余不变；每项一个提交，不跑全门，计数同步按任务书第 3 节做。
working: 2026-10-05T05:30:57Z A已提交 3d0220f56dbb5ef8b8445f79677ebcafa840401f：gate-assign同次发布首次交接，经原双身份复核门铃；合法claim满足首次通知，失效回主控带原因，三投升级复用。QWB_NOTIFY_BASELINE=1 QWB_NOTIFY_ONLY=A bash tests/collab-gate.sh 起点rc=1（明确缺首次门铃）；候选同用例rc=0；fast rc=0。日志本副本.qwb-tmp/notify-gaps/A-{red,green,fast}.log；未触碰真实端点，继续B。
working: 2026-10-05T05:33:11Z B已提交 7373d97bdf0f2a3205d141642b32e010c63b2679：主控真实send及需求原话handled原子回报；稳定结果ID、writer专属确认和原阻塞路径保留。起点QWB_NOTIFY_BASELINE=1 QWB_NOTIFY_ONLY=B bash tests/collab-planning.sh rc=1（缺上行）；候选rc=0，fast rc=0；日志.qwb-tmp/notify-gaps/B-{red,green,fast}.log。主控.md/规划.md已各补原话由规划办结规则；继续C。
working: 2026-10-05T05:35:02Z C已提交 b076192fea8a381fe9e2db3c6525b1a35dc52969：本代wait到期先于普通间隔与三投封顶判断；持久wait-expired传输收据去重，后续最短30分钟，count仍封顶3。起点QWB_NOTIFY_BASELINE=1 QWB_NOTIFY_ONLY=C bash tests/collab-handoff.sh rc=1（21分钟仍零门铃）；候选rc=0，fast rc=0；日志.qwb-tmp/notify-gaps/C-{red,green,fast}.log。继续D/E及全部定向验收。
working: 2026-10-05T05:38:05Z D已提交 4a22567d5e809010934d66f83c36c497dea92275：门禁accepted/rediagnose释放根claim时同次发布独立主控交接；摘要含claim与land-authorize命令名；旧release可按真实claim/verdict链补齐。QWB_NOTIFY_BASELINE=1 QWB_NOTIFY_ONLY=D bash tests/collab-land.sh 起点rc=1（release无门铃）；候选rc=0并成功land-authorize，fast rc=0；日志.qwb-tmp/notify-gaps/D-{red,green,fast}.log。继续E。
working: 2026-10-05T05:45:08Z E定向已绿：QWB_NOTIFY_ONLY=E bash tests/collab-land.sh rc=0，fast rc=0；起点同断言rc=1，真实land-close拒绝自身未办交接。新增旧交接保留、无关attempt不消音、显式send不按正文静默，以及blocked/未答/已答未恢复反例。当前用/bin/bash串行跑六个规定测试，日志本副本.qwb-tmp/notify-gaps/，未跑全门；完成后同步计数并提交E。
working: 2026-10-05T05:46:56Z 定向首轮planning在旧gate-assign整票字节等价断言处失败（A明确新增原子交接），已改为精确断言仅增加指定source交接且全部字段、stdout/stderr/rc/正文/其余事实不变，未删原拒绝检查。collab-handoff完整rc=0、PASS=11、FAIL=0；其余串行进行。补充未命中A旧已claim授权不补造首次交接，供基点4b1f2e2完整字节对照。
working: 2026-10-05T05:54:35Z land完整测试发现E真实遗漏：先授权旧候选再集成新候选时，旧verdict因只看当前land而复活。已用同一分类精确匹配land_history各自context/auth_ref/actor/op/事件顺序，保留旧匹配授权的办理事实；无关历史仍阻断。首败日志.qwb-tmp/notify-gaps/collab-land.log。gate完整rc=0/PASS=26/FAIL=0；后续复验已串行排队，绝不并跑全门。
working: 2026-10-05T05:59:07Z planning复验捕获分类器读时副作用：Perl将不存在的land槽作为grep列表元素，生成land:null，随后schema对象非法。已用最小纯函数探针复现并修复，新增collab-handoff只读断言；首败planning-final.log，探针classifier-green.log。旧版wake完整套件rc=0/PASS=20/FAIL=0；继续完整planning与land复验。
working: 2026-10-05T06:05:18Z land-final完整rc=0/PASS=45/FAIL=0（含换候选历史授权、全部失败恢复与agent-shapes矩阵）；handoff-final完整rc=0/PASS=12/FAIL=0；final-fast rc=0。E-baseline-final用全起点脚本从授权到close重跑，rc=1且唯一目标拒绝为收尾义务未结，排除了混入A新交接导致的假红。日志均本副本.qwb-tmp/notify-gaps；planning-closure和最后字节对照进行中。
working: 2026-10-05T06:16:45Z E已提交 1d55987b229cffbefcf2057d526607e8a904016e：有效义务统一分类、精确历史授权满足、原收尾拒绝顺序、分类只读反例及完整字节兼容均闭合。A–E依次3d0220f/7373d97/b076192/4a22567/1d55987；工作区干净，进入完成回执。
done: 2026-10-05T06:16:45Z 全部完成 sha=1d55987b229cffbefcf2057d526607e8a904016e。日志根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps/.qwb-tmp/notify-gaps/，汇总final-results.tsv。场景1授权首铃、场景7双身份失效回主控：QWB_NOTIFY_ONLY=A /bin/bash tests/collab-gate.sh rc=0/PASS=1/FAIL=0（A-final.log）；场景2规划办完主控请求回报：QWB_NOTIFY_ONLY=B bash tests/collab-planning.sh rc=0/PASS=3/FAIL=0（B-green.log），planning-closure全文件再次覆盖。
done: 2026-10-05T06:16:45Z 场景3等待19分钟静默/21分钟立即重叫：QWB_NOTIFY_ONLY=C bash tests/collab-handoff.sh rc=0（C-green.log），handoff-final复验含封顶与只读分类。场景4门禁release独立通知且可claim/land-authorize：/bin/bash tests/collab-land.sh rc=0（land-final.log）。场景5直接close并verified已结、场景6真实blocked/未答/未恢复原拒绝：QWB_NOTIFY_ONLY=E /bin/bash tests/collab-land.sh rc=0/PASS=2/FAIL=0（E-final.log）。A/B/C/D及E-baseline-final起点均rc=1，分别缺首铃/上行/到期/交还通知/收尾被自身义务挡住；保留*-red.log及E-baseline-final.log。
done: 2026-10-05T06:16:45Z 定向命令及rc/PASS/FAIL：QWB_PLANNING_UPWARD_COMPARE=1 QWB_NOTIFY_COMPARE=1 /bin/bash tests/collab-planning.sh=0/34/0（planning-closure.log）；/bin/bash tests/collab-handoff.sh=0/12/0（handoff-final.log）；/bin/bash tests/collab-gate.sh=0/26/0（collab-gate.log）；/bin/bash tests/collab-land.sh=0/45/0（land-final.log）；/bin/bash tests/collab-test-policy.sh=0/6/0（collab-test-policy.log）。
done: 2026-10-05T06:16:45Z QWB_TEST_WAKE_BASELINE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps/.qwb-tmp/notify-gaps/baseline-wake.sh /bin/bash tests/wake-block-output.sh=0/21/0（wake-literal.log）。/bin/bash bin/qwb-test.sh fast=0/0/0，无shellcheck告警（commit-fast.log）。
done: 2026-10-05T06:16:45Z 场景8通过：planning-closure以4b1f2e2对照plain/pending/rework/test-request/live/legacy六组stdout/stderr/rc/完整票/Herdr调用原字节，证据compat-migrated-final/；QWB_TEST_WAKE_SOURCE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-notify-gaps/.qwb-tmp/notify-gaps/baseline-wake.sh /bin/bash tests/wake-block-output.sh旧版完整套件0/20/0，wake-literal冻结私有writer时间/ID后比完整票字节，不删协作区。已逐一搜索五个改动测试文件名于tests/smoke.sh、tests/collab-all.sh、tests/herdr-batch.py：无相关写死PASS条数，动态组数与9个Herdr组不变，计数修改0处（count-audit.log）。自有测试进程残留0（process-cleanup.json）；未跑全门/真Herdr/模型，未改主账本state。
working: 2026-10-05T07:15:35Z 主控验收：确认设计后实现；六个提交 a0c4ac5…1d55987 已 cherry-pick 进 main（f08f07c…39e6966）。合并冲突三处由主控手工解决：templates/roles/规划.md（保留两张票各自加的句子）、tests/collab-land.sh 两处（与 land-env-digest 改了同一个测试函数，两边的参数、环境断言与交还通知断言都保留）。合并后单跑 collab-land 54、collab-gate 27、collab-planning 34、collab-handoff 12、wake-block-output 20，均 rc=0、0 FAIL。main @ adfb7b4 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、825 秒（.qwb-tmp/ctl-full-merge10.log）。未做：真机演练验证。
