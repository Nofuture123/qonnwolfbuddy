# 任务书：已迁票的三个值守缺口——进度行白叫人、工人丢了没人知道、交接投三次后石沉大海

```
任务 id:  collab-silence-fallback
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05「收紧叫醒」
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练 D6（docs/reviews/2026-10-05-real-herdr-roles-drill.md）；planner-upward 票设计阶段查明并推迟的两个缺口（docs/designs/2026-10-05-planner-upward.md「范围与现状」）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-collab-silence-fallback.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：「收紧叫醒」——进度不叫人，只有要人处理的事才叫；同时主控、副主控不能因为没被叫就对出事的工人一无所知。

背景：角色是主控、副主控（即「规划」常驻职责，能开票派工）、工人、门控（即「门禁」常驻职责）。带规划授权的已迁票上，`planner-upward` 票已经做到：工人 `done` 与门禁结论回主控，工人的阻塞类交接先给副主控、副主控办完自动上报主控。本票补剩下的三个缺口。

### 事实（主控已核实）

1. **进度行白叫人。** 真机演练里，已迁票上工人每追加一条 `working:` 进度，副主控就被门铃一次（01:30:58Z、01:31:21Z、01:31:28Z 三次）。未迁旧票已在 `wake-tighten` 票里做到「running 且末行是 `working:` 不叫醒」（`bin/qwb-wake.sh` 的 `collect_due`），但那只覆盖未迁旧票。
2. **工人丢了、停了没人知道。** `collect_due` 对已迁票的分支（约第 520–566 行）取完到期交接后直接 `continue`，不走未迁旧票的「工人丢失」与「超过 `QWB_REWAKE_MS` 无变化则兜底重叫」逻辑。已迁票上工人 pane 没了或长时间无动静，不会产生任何叫醒。
3. **交接投三次后石沉大海。** `bin/qwb-ledger.sh` 的 `handoff_due`（约第 624–626 行）在 `transport_count>=3` 后返回不到期；没有任何升级。目标角色三次都没接（例如副主控卡死），这条交接就再也没人看到。

### 要做的事（分两步，先设计后实现）

**第一步：设计。** 读 `bin/qwb-wake.sh`（`collect_due`、`route_gate_due`、`compose_msg`）、`bin/qwb-ledger.sh`（交接的产生、`handoff_due`、`record_transport`、`handoff-pending`）、`bin/qwb-send.sh`、四份角色说明（`templates/roles/`）、`docs/designs/2026-10-05-planner-upward.md`，写一页设计到 `docs/designs/2026-10-05-collab-silence-fallback.md`（80 行以内），提交后在主账本写 `needs-decision:` 等主控确认，再进入第二步。设计要回答：

- A（进度静默）：已迁票上哪些事件算「纯进度」（至少包括工人的 `working:`）；它们照常记账，但不门铃任何角色。副主控、门禁、主控自己写的 `working:` 现在各自会叫谁、要不要一并静默，逐类列出现状与你的建议。`blocked`、`needs-decision`、`question`、`done`、请求类交接不受影响。
- B（丢失与停滞兜底）：已迁、未完成、已派过工的票，工人 pane 丢失或超过 `QWB_REWAKE_MS` 没有任何新事件时，叫醒谁（建议：派工者——副主控派的叫副主控，副主控身份失效或票上没有规划授权则叫主控）、用什么去重避免每轮都叫、摘要里写什么。尽量复用未迁旧票已有的丢失判定与兜底时钟，不另写一套。
- C（升级）：交接投递满三次仍未被接收时怎么办。目标是副主控、门禁、测试体系的，升级给主控一次，摘要写明原目标与已投次数；目标本来就是主控的，不能就此沉默——给出有界的低频重提方案。升级本身的幂等、值守重启后的恢复、与现有预算与 `wait` 语义的关系都要写清。
- 每一项对现有 events、handoffs 结构的改动（能不动就不动）、对无规划授权的已迁票与未迁旧票的影响（应为零）、测试打算放在哪些已接入文件里。
- 你认为本任务书的前提有误之处，逐条列出。

**第二步：实现。** 按主控确认后的设计实现，至少三次提交（A、B、C 各一次），每次提交都保持快门通过。

白名单：`bin/qwb-wake.sh`、`bin/qwb-ledger.sh`、`bin/qwb-send.sh`（仅当设计确认需要）、`templates/roles/` 下四份角色说明里与这三项直接相关的句子、`docs/designs/2026-10-05-collab-silence-fallback.md`、`tests/` 下为验收所需的已接入文件。`bin/qwb-run.sh`、`bin/qwb-herdr.sh`、`bin/qwb-role.sh` 另有票在改，本票不碰。

## 1. 验收场景

### user_正常路径_已迁票工人进度不叫任何人

Given 带规划授权的已迁票，工人已派出
When  工人连续追加三条 `working:` 进度，值守跑若干轮
Then  三条都记在票里；副主控、主控、门禁都没有收到门铃；这条用例在起点提交上是红的（副主控被叫），先跑出红并留证

### user_正常路径_阻塞与完成照常送达

Given 同上
When  工人写 `blocked:`，之后写 `done:`
Then  `blocked` 先到副主控，副主控办完自动上报主控；`done` 直接到主控；行为与起点提交相同

### user_失败路径_工人丢失时叫醒派工者

Given 已迁票由副主控派出工人，工人 pane 随后消失
When  值守跑一轮
Then  副主控被叫醒一次，摘要写明工人丢失；同一丢失状态下后续各轮不重复叫；副主控身份失效时改叫主控

### user_失败路径_工人长时间无动静时兜底

Given 已迁票工人已派出，此后超过 `QWB_REWAKE_MS` 没有任何新事件
When  值守到期
Then  派工者被叫醒一次，摘要写明无进展时长；有新事件后时钟重新起算

### user_失败路径_交接投满三次未接则升级主控

Given 一条发给副主控的阻塞交接已投递三次，副主控始终没有接收
When  值守再跑
Then  主控收到一次升级，摘要写明原目标、原交接标识与已投次数；值守重启后不重复升级；副主控之后若接收并办理，按既有规则上报，不产生重复

### user_失败路径_发给主控的交接投满三次不沉默

Given 一条发给主控的交接已投递三次未接
When  时间继续推进
Then  按设计确认的低频间隔继续提醒，直到被接收；不会无界增长，也不会永久停止

### user_正常路径_其余路径逐字节不变

Given 起点提交与改后的脚本
When  跑未迁旧票的全部值守用例、无规划授权的已迁票用例、门禁 pending 与 rework、测试请求优先级
Then  标准输出、标准错误、退出码、票内容、Herdr 调用序列新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改权限模型：不扩大任何角色的写权限，不改主控锁、claim、验收门、五值 state、落地授权。
- 宁可多叫一次主控，不可让要人处理的事沉默；拿不准归谁的一律归主控。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh`、`tests/collab-handoff.sh`、`tests/collab-gate.sh`、`tests/collab-test-policy.sh`、`tests/wake-block-output.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门。** 全门由主控在合并后串行跑。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改权限与授权逻辑；不动另有票在改的三个脚本；不放宽任何现有断言。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T04:15:27Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-collab-silence-fallback pane=w14Z:p17 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback base=44ab8ac
working: 2026-10-05T04:17:42Z 执行者完成设计前源码核查（base=44ab8ac60f7f65591b87f5291b68cd95250feff8）：确认working还承载answer/resume/就绪等动作；handoff.recipient恒为controller，实际目标由wake分流；无规划授权零影响与B无授权回主控存在范围冲突。下一步提交80行内设计，列明静默分类、复用指纹/时钟、预算升级及兼容口径后等主控裁决；尚未改实现、未运行真Herdr/模型。
working: 2026-10-05T04:19:13Z 执行者完成第一阶段设计并提交54cb437498809bc4a46124ce9ed22c2eec523553（仅docs/designs/2026-10-05-collab-silence-fallback.md，55行，副本clean）；bash bin/qwb-test.sh fast rc=0，git diff --check rc=0；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/design-check.ll6wkN/fast.stdout、fast.stderr、fast.rc。未进入实现，未跑全门。
needs-decision: 2026-10-05T04:19:13Z 执行者请求主控审设计54cb437：建议A/B/C仅有规划授权的已迁票生效，身份失效回主控，无授权票保持逐字节；普通kind=working静默但保留完整pending义务与spec-resolved/answer/resume/request；B复用worker_lost与专用wake指纹；C复用原handoff和transport事件（需改send薄参数），一次升级后最短30分钟重提。请裁决：①B无授权回主控与无授权零影响冲突，是否采纳零影响；②历史实际目标未存，摘要改为当前原路由目标+历史unknown；③计数/交接数量/频率有界，允许审计events随真实提醒增长。门禁/测试字节等价仅约束非纯进度且未耗尽输入。按任务第一步要求停在设计确认点，等最新working后做A/B/C与七场景红绿；当前不报done。
working: 2026-10-05T04:19:57Z 主控确认设计（54cb437），进入第二步。裁决：① 范围冲突是任务书写错了，改为：A、B、C 对所有已迁票生效，不限于有规划授权的票。理由：没有规划授权时工人进度会门铃主控，这正是「收紧叫醒」要消除的；工人丢失与交接耗尽在主控直接派工的已迁票上同样会沉默。路由规则统一为：有效规划授权且派工者是规划则给规划，其余一律给主控。「逐字节不变」相应收窄为：未迁旧票全部不变；已迁票在没有命中 A、B、C 的输入上（非纯进度、未耗尽、工人未丢未停滞）不变。collab-handoff 等文件里与新规则冲突的旧断言（例如无授权票三次后停投）按新规则改写，在 done 行逐条列出改了哪些断言及原因。② 同意：摘要写「原路由目标（按当前规则判定）」，不写历史目标。③ 同意：有界指重提频率有上限、计数封顶、不派生新交接；审计事件可随真实提醒增长。重提周期按你的公式。④ 同意 qwb-send.sh transport 增加耗尽模式的薄参数，不扩大权限。⑤ 新增一项必须先查清并写进 A 的提交说明：被静默的纯进度交接一直未办理，会不会挡住后续任何门（门禁接手与结论、land 各步、收尾、state 推进）。会挡的话，纯进度交接不得成为这些门的阻塞项——给出最小做法（例如这些门的未结检查不计纯进度）；若必须改 events 或 handoffs 结构才能做到，先写 needs-decision。其余按设计执行，三次提交，不跑全门。
needs-decision: 2026-10-05T04:20:34Z 执行者落实裁决⑤发现：纯working未handled会由bin/qwb-lib.sh:qwb_task_obligations_json的handoff与source两处计为义务，进而阻止worktree finish并让done/verified仍未结；gate接手/verdict、land各步、state本身无该handoff拦截。最小修复是不改schema/不伪造handled，在lib两处排除真实自动纯进度（spec-resolved/test-request仍保留），ledger due使用相同口径。请求将bin/qwb-lib.sh仅此义务函数加入白名单；不碰另票run/herdr/role/worktree。先继续白名单内A回归红证与静默实现，未获批不改lib、不提交不完整A。
working: 2026-10-05T04:20:49Z 主控裁决：同意。白名单追加 bin/qwb-lib.sh，只许改 qwb_task_obligations_json 这一个函数：handoff 与 source 两处不把真实来源的自动纯进度计为未结义务（spec-resolved、test-request 等照旧保留），口径与 ledger 的 due 判定用同一处定义，不各写一套。补一条验收：票上留有未办理的纯进度交接时，worktree finish 与 done/verified 不被它挡住；留有未办理的 blocked 时仍被挡住（与起点相同）。
working: 2026-10-05T04:23:18Z 执行者细查调用链更正前述表述：qwb_task_obligations_json使worktree list、status与wake把done/verified继续列为未结，open_task_for只用于list；finish动作本身不调用该义务函数，单纯未received的blocked在起点也不直接禁止finish --keep，不能声称修复了不存在的finish硬门。将验证纯进度不阻finish且done/verified无未结，blocked仍在上述未结读模中阻止结清；不新增finish权限/硬门。分类将放lib获批函数中唯一固定定义，ledger复用，不改schema。
working: 2026-10-05T04:28:05Z A已提交a61eac3eba455eb68294d48eccbd803be18bd71a：所有已迁票自动纯working静默，lib义务与ledger due复用唯一分类；纯进度不阻done/verified结清，blocked仍未结，finish --keep保留未handled进度通过（finish起点本无该义务硬门）。A-red rc1明确红在规划被门铃；A-fast rc0；collab-ledger rc0，PASS=8 FAIL=0；planning已过静默/义务与blocked上行等检查但完整重跑留最终验收，未冒充全绿。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs。继续B实现。
needs-decision: 2026-10-05T04:28:15Z B兼容口径有一处物理冲突：要在每轮发现已派工pane消失，必须新增worker_lost的pane get只读探针；因此“工人仍活且未停滞”的完整Herdr调用序列无法与起点逐字节相同（起点根本不探工人）。建议完整序列字节对照覆盖无在途工人/已done的普通交接，其余未命中场景保持stdout/stderr/票/写投递不变，仅允许新增该只读探针；不会删隔离或减身份复核。实现与七场景继续，待主控确认这个必要兼容例外。
working: 2026-10-05T04:28:33Z 主控裁决：同意这个例外。已派工且未完成的已迁票，每轮值守允许新增一次对工人 pane 的只读存在性探针（与未迁旧票的丢失判定同一种调用）；这类票的 Herdr 调用序列对照改为「除新增只读探针外相同」，标准输出、标准错误、票内容、写操作与投递仍须逐字节相同。无在途工人或已 done 的票保持完整序列逐字节对照。探针失败或结果不明时不得当成丢失。
working: 2026-10-05T04:32:50Z B已提交（提交号见下一行）；QWB_PLANNING_UPWARD_ONLY=1 QWB_SILENCE_WATCH_ONLY=1 bash tests/collab-planning.sh rc=0 PASS=7 FAIL=0，覆盖A静默及义务、B丢失去重/重启/身份两次复核/unknown/假钟停滞/新事件重置/wait/无规划授权/已done；B-fast rc0。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs/B-watch.stdout、B-watch.stderr、B-watch.rc。C正在复用原handoff与transport事件实现耗尽升级，未创建新schema。
working: 2026-10-05T04:32:50Z B提交=5ae488e5d2e5beca7dbe64670d8780c2528f1a88；A提交=a61eac3eba455eb68294d48eccbd803be18bd71a。
working: 2026-10-05T04:39:00Z C已提交73b6905eb255207ef6a0327ed7b458382395fecf，C-fast-final rc0、collab-handoff完整rc0 PASS=10 FAIL=0。新C规划/主控用例已打印PASS，但该次运行中测试脚本被编辑，shell续读尾部rc2，不采信为完整通过；当前bash -n与内嵌Python compile均通过。已冻结文件，完整planning（含A/B/C、门禁/测试升级与44ab8ac字节对照）、旧票基线对照、gate及test-policy正在串/并行定向验收；不跑全门。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs。
working: 2026-10-05T04:43:24Z 最终验收继续：collab-gate rc0 PASS=24 FAIL=0；wake-block-output含44ab8ac旧票基线对照重跑rc0 PASS=21 FAIL=0（把已过期“纯working仍交接”对照样本改为spec-resolved真实动作，未动旧票断言）；/bin/bash 3.2.57下collab-handoff rc0 PASS=10 FAIL=0。修复set -u下新空数组展开不兼容，final-fast rc0；planning全文件含所有新用例/字节对照、test-policy、ledger和Bash3.2 B用例仍在执行。全部日志在本副本.qwb-tmp/silence-logs。
working: 2026-10-05T04:49:07Z 完整planning首轮A/B/C及原回流、门禁/测试耗尽用例均通过，进入字节对照时夹具给silent-test/up-test复用同一fake pane，第二次角色启动被正确的incarnation守卫拒绝(rc1)。已改为全程复用一个up-test身份，未改身份守卫；新一轮完整planning含字节对照已启动，等自然退出。其余定向门均rc0，Bash3.2交接与丢失/停滞均rc0。最终候选代码为8e639f4，当前仅测试夹具修正在途。
done: 2026-10-05T04:57:49Z 全部完成，最终提交=38baba8e65b72a1a12e4eb72bf5876e75cc1e8b6；A=a61eac3，B=5ae488e，C=73b6905，兼容修正=8e639f4，测试身份夹具修正=38baba8。所有已迁票纯进度静默且不阻结清，丢失/停滞按派工者回流，三投耗尽升级主控并低频重提。fast rc0、git diff --check rc0、工作区clean；未改state，未跑仓库全门，未碰真Herdr/模型。完整命令/退出码/原始日志哈希见/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs/verification.json。
done: 2026-10-05T04:57:49Z 场景1—6通过：QWB_PLANNING_UPWARD_COMPARE=1 QWB_PLANNING_UPWARD_EVIDENCE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs/compatibility-r2 bash tests/collab-planning.sh，rc0 PASS=32 FAIL=0。覆盖三条working零门铃；blocked先规划、handled唯一上行、done直达主控；工人丢失一次且身份失效回主控；假钟停滞/新事件重置；规划/门禁/测试三投升级一次；主控最短30分钟重提至received，计数封顶3且不派生新交接。原始输出=final-planning-r2.stdout/.stderr（同日志目录）。
done: 2026-10-05T04:57:49Z 场景7通过：planning同次运行的plain/pending/rework/test-request/live/legacy六组与44ab8ac对照stdout/stderr/rc/票/Herdr原始字节相同（live仅扣除主控获批的一次工人pane只读探针）。QWB_TEST_WAKE_BASELINE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs/baseline-wake.sh bash tests/wake-block-output.sh rc0 PASS=21 FAIL=0；旧票六类字节对照、进度静默与时间兑底保持原规则。证据=compatibility-r2与final-legacy-r2.stdout/.stderr。
done: 2026-10-05T04:57:49Z 逐文件定向均单独完成：bash tests/collab-handoff.sh rc0 PASS=10 FAIL=0；bash tests/collab-gate.sh rc0 PASS=24 FAIL=0；bash tests/collab-test-policy.sh rc0 PASS=6 FAIL=0；bash tests/collab-ledger.sh rc0 PASS=8 FAIL=0。原始日志对应C-handoff-final、final-gate、final-test-policy、final-ledger三类stdout/stderr/rc；planning与wake结果见上两行。bash bin/qwb-test.sh fast各提交均rc0，无新增ShellCheck告警。
done: 2026-10-05T04:57:49Z 红绿证：QWB_PLANNING_UPWARD_ONLY=1 QWB_SILENCE_BASELINE=1 bash tests/collab-planning.sh 在44ab8ac rc1，明确失败在工人working门铃规划（A-red.stdout/.stderr）；候选同断言通过。新增义务验收：未办理纯进度的source/handoff不使done/verified与worktree list未结，真实blocked仍未结；公开finish --keep通过且进度仍未handled。finish原本不按普通交接阻断，未新增硬门或伪造办理。
done: 2026-10-05T04:57:49Z 旧断言变更逐条：①planning的working照旧门铃改为不含进度但仍交接显式send；②accepted后续对照输入改为spec-resolved真实动作，保留主控专属拒绝；③wake-block-output把要求纯working交接的对照样本改成spec-resolved，纯进度由A独立验收；④handoff保留三投后短间隔不due，新增30分钟后重提/计数封顶断言；⑤P6基点改为本票44ab8ac并单列一次只读探针例外。未降低权限/claim/wait/门禁/隔离断言。
done: 2026-10-05T04:57:49Z Bash3.2.57验收：私有PATH bash shim全部转/bin/bash，collab-handoff rc0 PASS=10 FAIL=0；QWB_PLANNING_UPWARD_ONLY=1 QWB_SILENCE_WATCH_ONLY=1的collab-planning rc0 PASS=7 FAIL=0（完整命令在verification.json，日志bash32-handoff/bash32-watch）。测试scope与本票测试进程残留=0；超时旧scope已核死与无FD后精准回收，日志及证据保留在/Users/rocky/projects/qonnwolfbuddy/.worktrees/collab-silence-fallback/.qwb-tmp/silence-logs。最终SHA=38baba8e65b72a1a12e4eb72bf5876e75cc1e8b6。
working: 2026-10-05T05:30:17Z 主控验收：确认设计后实现；六个提交 54cb437…38baba8 已 cherry-pick 进 main（fd2c8c2…538803f），tests/collab-planning.sh 两处与 prompt-start-window 的冲突由主控手工合并（两边对假 Herdr 的扩展都保留），合并后单跑该文件 rc=0 PASS=27。main @ 4b1f2e2 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、611 秒（.qwb-tmp/ctl-full-merge8.log）。未做：真机演练验证（第二轮演练的候选不含本票）。
