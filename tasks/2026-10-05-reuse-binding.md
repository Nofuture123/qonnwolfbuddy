# 任务书：续派原工人在真机上必被拒——派发时的身份记录缺会话

```
任务 id:  reuse-binding
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练（docs/reviews/2026-10-05-real-herdr-roles-drill.md 的 D7）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-reuse-binding.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：门控不通过时要能让原来的工人返修。

### 真机上看到的事实（主控已核实）

环境：Herdr 0.9.3、Pi 1.0.2。

1. 首次派发 Pi 工人后，票上写下的身份记录是：
   `working: worker-activity op=… pane=w2:p1 evidence={"activity": "unknown", "proof": "native-pid; CLI idle not verified", "pid": 60618, "pid_start": "Mon Oct  5 03:30:41 2026"}`
   没有 `session`。
2. 工人做完一轮后，对同一张票续派（`qwb-run.sh` 的复用路径，约第 427–429 行）被拒：
   `错误：本代真实活动为 unknown，不凭Herdr idle复用或中断`
3. 同一时刻直接跑探针：
   - 不带 `--task`：`{"activity": "idle", "proof": "native-pid-start+session-branch", "pid": 60618, "pid_start": "Mon Oct  5 03:30:41 2026", "session": "/Users/rocky/.pi/agent/sessions/…/2026-10-05T01-30-41-954Z_01a109af-….jsonl", "pending_tools": []}`
   - 带 `--task`：`{"activity": "unknown", "proof": "unverified", "conflict": "startup incarnation/session not bound; refuse stale idle"}`
4. 判定在 `bin/qwb-herdr.sh` 约第 347–351 行：带 `--task` 时要求现场观测的 `pid`、`pid_start`、`session` 三项都等于票上该 pane 最近一条 `worker-activity` 记录。记录里没有 `session`，现场有，永远不等。
5. 该工人 pane 的真实 `herdr pane get` 与 `process-info` 应答已保存：`/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles/real-pane-get-worker.json`、`real-process-info-worker.json`。Herdr 在 `agent start` 返回时就已经给出 `agent_session`（`{"agent":"pi","kind":"path","source":"herdr:pi","value":"<会话文件路径>"}`），当天所有 Pi 启动的应答都如此。
6. 常驻角色的启动记录走的是另一段代码，写下的是 `"proof": "native-pid+unpersisted-session"` 且带 `session` 路径（例：`"session": "…/qwbuddy/.roles/gate.sessions/2026-10-05T01-25-26-111Z_….jsonl"`）。

主控的推断（**你要先读代码确认，不成立就写 `needs-decision:`**）：首次派发写记录时，Herdr 已经报出会话文件路径，但 Pi 还没把会话文件写到磁盘，`bin/qwb-herdr.sh` 的活动判定对工人走了通用分支，于是丢掉了 `session`；角色那段代码对同样的情形保留了路径。

这段复用判定在通用路径上，未迁旧票的返工续派同样受影响。假 Herdr 夹具在启动时就让会话可读，所以现有测试测不出来。

### 要做的事

1. 让首次派发写下的 `worker-activity` 记录在「Herdr 已报出 Pi 会话路径、会话文件尚未落盘」时带上这个 `session` 路径，证明方式如实写成未落盘（参照角色记录的写法），`activity` 仍是 `unknown`，不得写成 `idle`。
2. 续派时的三项比对保持原样、一项不松：`pid`、`pid_start`、`session` 都要与最近一条记录相等才认本代；会话文件已落盘后的空闲判定仍按现有的会话分支逻辑。
3. 旧记录兼容：票上最近一条记录没有 `session` 的（修复前派出的工人），续派照旧拒绝，但拒绝信息要写出路——说明是派发时记录未绑定会话，换一个工人名重新派发，或在确认原工人已停下后关闭其 pane 再派。不许为旧记录放宽比对。
4. 非 Pi 工人（Claude Code）现有行为不变：活动仍是 `unknown`，续派仍被拒。本票不解决它，只在 `done:` 行里写明你读到的现状与拒绝信息原文。
5. 假 Herdr 夹具补一个「会话路径已报出、文件不存在」的启动形态，形状照上面第 5 条的真实应答，不凭空造字段。

白名单：`bin/qwb-herdr.sh`（活动判定与带 `--task` 的绑定段）、`bin/qwb-run.sh`（仅复用路径的拒绝信息）、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_首次派发后续派原工人成功

Given 假 Herdr 按真机形态：`agent start` 之后 `pane get` 报出 Pi 会话路径但文件不存在；提示词投递后会话文件出现且会话分支显示已空闲
When  首次派发一张票，工人完成一轮后对同一张票续派
Then  首次派发的 `worker-activity` 记录带 `session` 且 `activity` 为 `unknown`；续派成功，投递的是续派提示词；这条用例在起点提交上是红的（续派被拒），先跑出红并留证

### user_失败路径_换了进程或换了会话仍拒绝

Given 同上，但续派前分别制造：工人进程已换（pid 或启动时间不同）；同一进程但 Herdr 报出的会话路径与记录不同
When  续派
Then  两组都被拒，信息与起点提交相同；票与 Herdr 调用记录里没有新的投递

### user_失败路径_工人仍在忙时拒绝

Given 记录与现场三项一致，但会话分支显示工人还有未结束的工具调用或仍在回合中
When  续派
Then  被拒，行为与起点提交相同

### user_失败路径_旧记录没有会话时拒绝并给出路

Given 票上最近一条 `worker-activity` 记录没有 `session`（修复前写下的），现场一切正常
When  续派
Then  被拒；stderr 说明原因是派发时记录未绑定会话，并给出换名重派或关闭原 pane 再派两条出路；零投递

### user_正常路径_会话文件已落盘时的行为不变

Given 假 Herdr 按现有夹具形态（启动时会话文件就可读）
When  跑现有的派发、复用、活动探针用例
Then  stdout、stderr、退出码、票内容与起点提交逐字节相同

### user_正常路径_非Pi工人现状不变

Given Claude Code 工人
When  首次派发后续派
Then  与起点提交行为相同（把现状写进 `done:` 行）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 真机形态只能来自上面给出的样本文件与票内引用的原文。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 这是防止把陈旧的空闲状态当成当前状态的防护：只补上派发时缺的那一项记录，任何比对条件不许放松。拿不准的一律拒绝。
- 不改常驻角色的记录与判定（`bin/qwb-role.sh`）；不改值守、收尾。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 六个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
`done:` 行里另列：你读代码确认的根因（哪一行、哪个条件让首次派发的记录丢了会话），以及它与主控推断是否一致。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不放松三项比对；不为没有会话的旧记录开例外；不让非 Pi 工人的续派通过。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T03:07:40Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-reuse-binding pane=w14Z:p13 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding base=57d6e7a
working: 2026-10-05T03:08:34Z 已完整读取任务票、D7演练文档及两份真机应答；基点57d6e7a的bin/qwb-herdr.sh:173–174已具备unknown+native-pid+unpersisted-session并保留session，与票内推断不符；正在隔离离线复现，不调用真Herdr或模型。
needs-decision: 2026-10-05T03:09:15Z 推断不成立，按第0节停止实现。基点57d6e7af4a3f901af73d0472efb3bf076a162f48的bin/qwb-herdr.sh:173–174已有缺文件时保留session的unknown/native-pid+unpersisted-session分支；qwb-run.sh:777–780原样存证。用指定真机JSON形状离线执行基点源码（Herdr/ps均拦截，无真实调用），首次保留session、落盘后三项匹配的--task探针返回idle，故票内起点红证前提不成立。命令python3 -B .qwb-tmp/reuse-binding-baseline-probe.py，rc=0 PASS=3 FAIL=0，原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-baseline-probe.log；git status --short为空，无源码改动、无提交、未跑快/全门、无启动模型/Herdr进程，探针私有临时目录已清。建议主控核对启动瞬间pane get是否尚无agent_session及演练安装版本，再裁决修订根因/验收；旧记录提示改进待根因裁决后续做。
working: 2026-10-05T03:11:13Z 主控裁决（返工指令，取代第0节的主控推断与事实第5条，那两处是主控写错的）：你的反驳成立。主控刚在隔离会话实测（Herdr 0.9.3，Pi 1.0.2）：agent start 返回时应答里没有 agent_session（interactive_ready 为 true）；返回后 0.02、0.14、0.28 秒查 pane get 都没有 agent_session，1.52 秒时才出现（source=herdr:pi，kind=path，文件尚未落盘）。三份真实应答在 /Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/ 下：agent-start-pi.json、pane-get-pi-just-started-no-session.json、pane-get-pi-session-unpersisted.json。所以根因是时序：qwb-run.sh 首次派发在 agent start 返回后立刻 record_worker_activity，Herdr 还没报出会话，探针落到 qwb-herdr.sh 第202行的通用分支，记录就没有 session；演练那次撞上了，今天的真机验收那次恰好没撞上（记录是 native-pid+unpersisted-session）。修订后的要做的事：（一）首次派发、工人是 Pi 时，写身份记录前有界等待会话路径出现：轮询活动探针直到结果带 session，上限10秒、间隔约0.5秒；等到就按现有写法记录（unknown 加 native-pid+unpersisted-session，或文件已落盘时的会话分支结果）；超时就照现状记录不带 session 的结果，并另追加一条 working: 说明会话未绑定、本工人日后不可续派，派发本身不失败。等待放在 qwb-run.sh 还是 qwb-herdr.sh 你定，取改动最小的。非 Pi 工人不等待、行为不变；复用路径不等待。（二）原第2、3、4条不变：三项比对不松；旧记录没有 session 的续派照旧拒绝并写出两条出路；Claude 工人现状不变并在 done 行写明。（三）假 Herdr 夹具补的启动形态改为照上面三份样本：agent start 应答无 agent_session，其后前若干次 pane get 无 agent_session，之后才报出路径且文件不存在。场景一的起点红证相应改为：在这个形态下起点提交首次派发的记录没有 session、续派被拒。新增一个场景：会话路径在上限内始终不出现时，派发成功、记录不带 session、多一条未绑定说明、耗时不超过上限加2秒。其余场景与硬约束、验收门、报告要求不变。
working: 2026-10-05T03:14:11Z 修订根因确认：首次agent start后尚无agent_session，qwb-run.sh:843立即记证，探针落入qwb-herdr.sh:202通用分支。已接入collab-herdr第9套回归，命令QWB_REUSE_BINDING_BASELINE=1 /bin/bash tests/collab-herdr.sh reuse-binding在基点57d6e7a有效红：首次rc=0记录无session，续派rc=1且stderr为原unknown拒绝；原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-red.log。继续实施Pi新启动有界等待与旧记录出路提示。
working: 2026-10-05T03:22:01Z 实现完成，快门bash bin/qwb-test.sh fast rc=0（.qwb-tmp/reuse-binding-fast.log）。已验证延迟session续派成功、pid/start/session变化及pending/in-round零投递且基点字节一致、旧记录两条出路、已落盘Pi和Claude行为字节一致。定向验收首轮夹具JSON文字/显式harness/计数问题已修正并留原日志；最新轮整体派发15.29秒触发总耗时断言，已明确10秒预算属于agent start后的绑定等待窗口，调整从agent start到提示词投递校验≤12秒并继续输出整命令耗时（前置检查/锁耗时不洗掉）。正在重跑最终定向门，完整通过后提交并跑一次全门。
working: 2026-10-05T03:24:11Z 最终定向门完成：QWB_REUSE_BINDING_BASELINE=1 /bin/bash tests/collab-herdr.sh reuse-binding rc=1为有效基点红；/bin/bash tests/collab-herdr.sh reuse-binding rc=0 PASS=10 FAIL=0，七类场景均验证（拆分pid/start/session与pending/in-round共10条PASS）。超时分支整命令12.230秒、agent start至提示词10.512秒，派发成功、记录无session且另有未绑定说明；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-final-green.log。快门rc=0，源码仅3处行为改动，三项比对未改；现在提交并执行提交后的全门。
working: 2026-10-05T03:30:47Z 候选已提交8a8c3a24fa3f565b50e2d1008f7b2eb0a7a2c641，提交后全门仍在运行，新增绑定回归在全门通过（绑定窗口11.480秒，整命令14.214秒）。发现process-entry-cleanup.py导出副本的/bin/bash tests/full-gate.sh等待wire就绪60秒超时，尚无本轮最终退出回执；该wire出现在smoke第7节，早于本票qwb-run启动/绑定等待的第9节，暂不归为实现回归。已独立保存首败=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-entry-cleanup-first-failure.log，先收齐全门再核查，不改超时或断言。
needs-decision: 2026-10-05T03:39:03Z 全门发现必须修复的接缝：collab-gate.sh rc=1，qwb-run新Pi超时普通working说明被bin/qwb-ledger.sh:1501–1505拒绝「门禁仅可写本人已派child活动绑定」（qwb-run rc=25），因此门控新启动超时会派发失败，违反派发不失败要求。候选8a8c3a24fa3f565b50e2d1008f7b2eb0a7a2c641已提交，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-gate-timeout-note-failure.log。建议扩白名单到bin/qwb-ledger.sh：为固定worker-session-unbound通知沿用现有child/actor/pane/claim/status归属校验，只开放这条同child通知，不开放一般working权限；qwb-run改为该固定格式，并在已接入门控测试补超时回归。当前白名单不能改账本，也不能用活动evidence伪装说明或吞掉拒绝。仍收齐已启动全门并清理本票资源，未改候选。
working: 2026-10-05T03:42:16Z 协作跑批已收齐，4/15失败：门控超时说明权限（实现接缝，需扩白名单）；lint-scenario-stream.sh固定Herdr调用次数被新增等待打破（其成功夹具只有shell、无Pi原生session，后续可在现有tests白名单中补真实PID/session，保留原调用断言）；process-entry-cleanup.py的60秒就绪超时；socket-path-regression.py导出Herdr收尾字节对照中qwb-lib查询2秒超时。定向新增场景在本仓及导出副本均通过。剩余smoke仍运行，待最终全门rc与资源清点。未改源码或超时阈值。
working: 2026-10-05T03:44:40Z 主控裁决：不扩白名单、不改账本。那条「另追加一条 working: 说明」是主控上一条指令里加的，非必需，撤回。改为：会话路径在上限内没出现时，qwb-run 只把未绑定说明打印到自己的标准输出（一行，写明本工人日后不可续派及原因），不往票里多写任何行；票里仍只有那条不带 session 的 worker-activity 记录，日后续派时由拒绝信息给出路。相应场景改为断言标准输出有这行、票里没有多出的行、门控派发新工人在超时形态下照常成功（collab-gate.sh 转绿）。另：你的副本里 git status 显示 tests/lint-scenario-stream.sh 有未提交改动，不在白名单内，查清是谁改的（若是全门运行中的临时状态，等全门结束后再看），在 done 行里说明并保证最终工作区干净。机器上多轮全门并发导致超时类假失败很多（主仓全门刚才在 process-entry-cleanup 与 socket-path-regression 上超时），你的全门若只剩这类与本票无关的超时失败，原样报告即可，主控会在负载降下后独立复跑，不要反复重跑全门。
needs-decision: 2026-10-05T03:46:54Z 已读最新裁决，按stdout通知方案继续，不改账本。lint-scenario-stream.sh未提交改动是我在首轮全门结束后修复成功夹具所写；原票白名单原文为「tests/ 下为验收所需的已接入文件」，该文件已接入且其固定调用断言因无Pi会话的shell夹具失败，修复后/bin/bash tests/lint-scenario-stream.sh rc=0，原调用次数断言未改。最新裁决称该文件不在白名单，我先恢复HEAD，并保留拟补丁=.qwb-tmp/reuse-binding-lint-fixture-proposed.diff、绿证=.qwb-tmp/reuse-binding-lint-fixture-green.log。请明确允许这一个已接入夹具的真实PID/session修复，或裁决将该非超时夹具失败交主控处理；否则后续全门不能声称只剩无关超时。核心stdout返修与定向验收继续推进。
working: 2026-10-05T03:47:20Z 主控裁决：你对，原白名单「tests/ 下为验收所需的已接入文件」包含 tests/lint-scenario-stream.sh，上一条说它不在白名单是主控看错了。允许按你保留的拟补丁修这个夹具（给它真实的 PID 与会话，原调用次数断言不改），随本票提交。其余按标准输出通知方案继续。
working: 2026-10-05T03:55:27Z 已按03:44 stdout裁决返修：超时仅打印一行原因/日后不可续派，票无超时说明；按03:47裁决保留我写的lint-scenario-stream.sh真实PID/session夹具修复，原调用次数断言未改（此前恢复尝试未匹配，文件并未回退）。首轮全门已完整结束，8a8c3a2 rc=1 PASS=868 FAIL=8（含失败测试内3条预期负例日志），git status当时空；残留进程/目录均为空（.qwb-tmp/reuse-binding-residual.log）。R2 recovery原样单跑rc=0。最新Herdr定向rc=0、stream rc=0、fast rc=0；门控派发已成功，测试断言误计原有gate-dispatch行已修正，正单独重跑门控；账本/角色/收尾实现均未改。
working: 2026-10-05T04:03:22Z stdout返修与已获准夹具验收全绿：/bin/bash tests/collab-herdr.sh reuse-binding rc=0 PASS=10；/bin/bash tests/collab-gate.sh rc=0 PASS=24（包含门控新Pi超时仅stdout、原child活动绑定与三类越权零写拒绝）；/bin/bash tests/lint-scenario-stream.sh rc=0，原调用次数断言保留；bash bin/qwb-test.sh fast rc=0。原始日志前缀=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-，门控成功日志=gate-attempt2.log。现在追加提交并在最终候选上跑一次全门；按主控裁决，不为无关超时反复全门。
working: 2026-10-05T04:12:56Z 主控指令：候选 fea4ab2 已收到并合入本地主干做串行全门；你那轮全门可以停掉（并发全门结果不作数）。停掉后清理自己起的进程，确认 git status --short 为空，写 done 行（六个场景的定向验证结果、根因确认、Claude 工人现状与拒绝信息原文），全门一项写「由主控合并后执行」。
done: 2026-10-05T04:17:26Z commit=fea4ab269c6e7964368231c099ed19a11a78cd65。根因确认：基点57d6e7a的qwb-run.sh:843在agent start返回后立即record_worker_activity；Herdr尚未报agent_session，qwb-herdr.sh:202通用分支因此只有PID/start，无session。与03:11主控修订推断一致，与原“文件未落盘”推断不同。新Pi启动有界等待10秒/约500ms；三项绑定比较保持原样；代码仅6个白名单文件，未改账本、角色与收尾。
done: 2026-10-05T04:17:26Z user_正常路径_首次派发后续派原工人成功：QWB_REUSE_BINDING_BASELINE=1 /bin/bash tests/collab-herdr.sh reuse-binding在57d6e7a rc=1，记录缺session并拒绝续派（有效红证）；移除该环境变量后rc=0，先报路径后落盘、unknown未落盘证明、读回本代空闲后续派提示词投递均通过。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-final-red.log；/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-herdr.log。
done: 2026-10-05T04:17:26Z user_失败路径_换了进程或换了会话仍拒绝；user_失败路径_工人仍在忙时拒绝：/bin/bash tests/collab-herdr.sh reuse-binding rc=0。PID、pid_start、session分别变化，pending-tool和in-round两种忙碌状态均拒绝、零新投递，stdout/stderr/rc/票字节/Herdr调用与基点逐字节一致。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-herdr.log。
done: 2026-10-05T04:17:26Z user_失败路径_旧记录没有会话时拒绝并给出路；user_正常路径_会话文件已落盘时的行为不变：/bin/bash tests/collab-herdr.sh reuse-binding rc=0。旧记录拒绝且给换工人名、确认停下后关pane再派两条出路，零写入/零投递；启动时已落盘Pi的首次派发与续派stdout/stderr/rc/票字节/调用日志与57d6e7a完全一致。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-herdr.log。
done: 2026-10-05T04:17:26Z user_正常路径_非Pi工人现状不变：/bin/bash tests/collab-herdr.sh reuse-binding rc=0。读到qwb-herdr.sh:202仅以working/blocked判busy，否则unknown，proof为native-pid; CLI idle not verified，不等待session、不接受续派；基点字节对照一致。拒绝原文：错误：本代真实活动为 unknown，不凭Herdr idle复用或中断。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-herdr.log。
done: 2026-10-05T04:17:26Z user_正常路径_会话绑定超时仍派发：/bin/bash tests/collab-herdr.sh reuse-binding rc=0，新增等待窗口10.862秒，整命令13.252秒；超时仅stdout一行说明，记录无session，票无额外通知行，派发成功。/bin/bash tests/collab-gate.sh rc=0 PASS=24 FAIL=0，门控身份下同样成功，只保留既有gate-dispatch及child活动绑定，越权拒绝不变。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-herdr.log；/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-gate-attempt2.log。
done: 2026-10-05T04:17:26Z 快门bash bin/qwb-test.sh fast rc=0，未新增ShellCheck告警；Herdr定向PASS=10 FAIL=0。tests/lint-scenario-stream.sh是我在首轮全门后修复的成功夹具，非临时状态或他人改动；03:47主控允许后随fea4ab2提交，真实阻塞进程PID/cwd与已落盘session已补，原调用次数断言未改，/bin/bash tests/lint-scenario-stream.sh rc=0。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-fast.log；/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-stdout-stream.log。
done: 2026-10-05T04:17:26Z 全门：由主控合并后执行。04:12主控指令已说明fea4ab2合入本地主干并串行验收，并发结果不作数；本执行者按原生PID/PPID/命令快照，仅TERM自己的smoke监督器25004，正常门收尾退出回执1作为中断记录，不作为全门验收。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-final-full.log，退出回执=同前缀.exit。首轮8a8c3a2全门rc=1 PASS=868 FAIL=8已留证（门控/夹具问题随后修复），不冒充最新候选全绿；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-full.log。
done: 2026-10-05T04:17:26Z 最终commit=fea4ab269c6e7964368231c099ed19a11a78cd65，git status --short输出为空；残留进程清单=[]，剩余测试临时目录=[]，只保留验收日志/探针文件。独立清点python3 -B .qwb-tmp/reuse-binding-residual-probe.py rc=0；证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reuse-binding/.qwb-tmp/reuse-binding-final-residual.log。未调用真Herdr、未启动模型会话、未建分支或push，主仓仅追加本票状态行，state字段未动。
working: 2026-10-05T04:24:59Z 主控验收：读完产品改动（首次派发 Pi 工人时最多等 10 秒会话路径再记身份；三项比对未放松；旧记录无会话时续派拒绝并给两条出路；超时只在标准输出留一行）。两个提交 8a8c3a2、fea4ab2 已 cherry-pick 进 main（1ac7a81、44ab8ac）。合并后 main @ 44ab8ac 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、669 秒（.qwb-tmp/ctl-full-merge6.log），续派绑定用例经 tests/herdr-batch.py 第 9 组在全门内执行；真机验收第 12 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS，身份记录带会话路径。未做：真机上实际续派一次（留给副主控与门控演练重跑）。
