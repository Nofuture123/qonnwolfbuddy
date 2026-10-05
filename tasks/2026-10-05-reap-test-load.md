# 任务书：订阅回收测试在机器忙时让全门白白失败

```
任务 id:  reap-test-load
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     整仓审核报告 F53（docs/reviews/2026-10-03-qwb-full-audit-r1.md）；2026-10-05 当天第三次撞上
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-reap-test-load.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：机器负载高是常态，不能因为忙就让验收门失败、让工人多跑一轮。

### 看到的事实（主控已核实）

1. `tests/subscribe-reap.py` 的 `probe()`（约第 40–63 行）对每种模式最多试 5 次；每次由 `probe_once()` 起一个真的 `qwb-wake.sh --block`，要求在产品「订阅读账 2 秒超时」之内观察到值守退出（约第 199–200 行：`read_age >= 2` 或 stderr 含 `timed out after 2 seconds` 记为错过窗口）。5 次全错过就抛 `未能验证（测量环境问题，非产品缺陷）…`，冒烟第 88 节（`tests/smoke.sh` 约第 5018–5019 行）据此报 `订阅子进程回收公开入口回归`，全门 rc=1。5 次之间没有任何等待，连着试。
2. 全门（`tests/full-gate.sh`）把 `tests/smoke.sh`、`tests/review-identity.sh`、`bin/qwb-lint.sh`、`tests/collab-all.sh` 四段并发跑；第 88 节在冒烟段里，正好与另外三段抢 CPU。
3. 今天的原始失败（`planner-ticket-body` 工人的全门，当时机器上同时有四轮全门，负载约 40）：`subscribe-reap normal连续5次错过真实2秒观察窗口，读龄3.624/3.263/2.867/3.545/2.708秒`。此前当天另有两个工人各因此多跑一轮全门，单独复跑均通过。
4. 这条测试量的是产品的真实行为（退出码、无残留读账进程、事件目录被删、FIFO 释放），「错过窗口」只说明没量到，不说明有没有泄漏。

### 要做的事

目标：机器忙时这条测试仍能量到，量不到时也不许算通过。

1. **全门里把它挪到并发段之后单独跑。** `tests/full-gate.sh` 在四段并发全部结束后串行跑一次 `tests/subscribe-reap.py`；全门调用冒烟时用一个环境变量让第 88 节跳过实测（打印一行说明由全门尾段执行），避免跑两遍。单独跑 `bash tests/smoke.sh` 时第 88 节照旧实测。全门的 PASS 行总数与逐行文字同起点提交一致（行的先后位置可以变）；尾段失败时全门 rc=1 并打印该段输出。
2. **错过窗口后退避再试。** `probe()` 的 5 次尝试之间加等待：依次约 1、2、4、8 秒（合计不超过 15 秒），等的是机器缓过来，不是放宽判定。每次 `INCONCLUSIVE` 行照旧打印，并带上本次等待秒数。尝试次数、2 秒窗口、`missed` 判定一个字不改。
3. **量不到仍然是失败。** 5 次都错过时仍抛原来的错误并让调用方 rc 非零；不许把「未能验证」变成通过或跳过。
4. `--races`、`--timings`、`query_cleanup` 的行为不变。

白名单：`tests/subscribe-reap.py`、`tests/full-gate.sh`、`tests/smoke.sh`（仅第 88 节）、`bin/qwb-test.sh`（仅当全门入口必须跟着改时）。产品脚本（`bin/` 其余、`templates/`）一律不动。

## 1. 验收场景

### user_正常路径_全门尾段串行执行且计数不变

Given 起点提交与改后的副本
When  各跑一次 `bash bin/qwb-test.sh full`
Then  两边 `grep -c '^PASS'` 相等，排序后的 PASS 行逐行相同；改后的日志里订阅回收的 PASS 行出现在四段并发全部结束之后；冒烟段日志里第 88 节是一行跳过说明

### user_正常路径_单独跑冒烟仍实测

Given 改后的副本，不带全门的环境变量
When  只执行冒烟第 88 节所调用的命令（`python3 -B tests/subscribe-reap.py`），以及用同样的环境读第 88 节的分支
Then  实测执行，PASS 行与起点提交相同

### user_失败路径_连续错过窗口时退避后仍失败

Given 用测试自己的手段让每次尝试都错过窗口（例如给 `probe_once` 打桩抛 `MissedWindow`，不起真进程、不烧 CPU）
When  调 `probe()`
Then  共 5 次尝试，四次等待依次约 1、2、4、8 秒（把睡眠函数打桩记录参数，不真等）；最后抛出原错误文字；调用方 rc 非零

### user_正常路径_前几次错过后量到即通过

Given 打桩让前两次错过、第三次返回正常结果
When  调 `probe()`
Then  返回第三次的结果，`attempts` 为 3，只等了前两段；没有第四次尝试

### user_失败路径_尾段失败让全门失败

Given 让尾段的订阅回收测试失败（例如用环境变量指向一个必然失败的替身脚本，或你认为更干净的做法）
When  跑全门的编排脚本
Then  rc=1，输出里能看到尾段的失败信息；其余四段的结果照常汇总

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改产品的 2 秒超时，不改 `missed` 的判定，不把量不到当通过。
- 不许起烧 CPU 的压力进程来「复现高负载」；失败路径用打桩验证。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 机器上同时有别的工人在跑全门，负载高是常态。你自己的全门如果在别的测试上因超时失败，原样报告，不要改那些测试。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门耗时（与起点提交那一轮对比）、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
第 0 节的事实里凡与你读到的代码不符的，先写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改产品脚本；不放宽任何判定；不删测试。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T03:30:32Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-reap-test-load pane=w14Z:p14 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load base=57d6e7a
working: 2026-10-05T05:30:52+0200 执行者已完整读取规格与点名审核报告，基点=57d6e7af4a3f901af73d0472efb3bf076a162f48，工作区干净；开始起点全门，证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V。
needs-decision: 2026-10-05T05:30:52+0200 白名单接缝：tests/process-entry-cleanup.py 的 check_full_gate() 在私有导出中只替换四段，且第166行严格断言只有四段输出；新增真实尾段必使该既有门失败。建议追加允许只改该函数：替换订阅尾段为桩并扩展顺序/失败/TERM断言；其余断言与隔离不变。先继续基线和当前白名单工作。
working: 2026-10-05T03:31:21Z 主控裁决：同意。白名单追加 tests/process-entry-cleanup.py，只许改 check_full_gate() 这一个函数：把订阅尾段替换成桩，并把顺序、失败、TERM 的断言扩到五段；其余断言与隔离不变。另：机器现在负载约 80（五个工人同时跑全门），你的全门若在别的测试上因超时失败，原样报告即可，主控会在负载降下来后独立复跑，不要为此反复重跑全门。
needs-decision: 2026-10-05T05:31:26+0200 PASS逐字对照存在固有变量：smoke的assert_file输出随机临时路径，collab-all第175行输出各项实测秒数。建议保留两轮原始PASS清单与总数，另仅归一化本票副本下的随机临时路径及collab-all末尾耗时再排序逐行比对；静态PASS文案必须完全相同。
working: 2026-10-05T05:35:36+0200 候选在本票证据目录构建，尚未改源文件以保护正在运行的起点全门。定向场景：旧退避红rc1；新连续错过5次、等待1/2/4/8后原错误且调用方rc1；前2次错过第3次成功；尾段失败rc1并保留四段输出；bash和/bin/bash下12个五段编排/TERM场景通过、无残留；新full-gate shellcheck rc0。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V。
working: 2026-10-05T05:45:08+0200 起点全门仍等协作段收齐；smoke/identity/lint均通过。基点collab的process-entry-cleanup在首个root-tab-missing用例60秒上限失败（尚未应用改动），原始日志暂在full-gate/协作段，收齐后存baseline.log；按主控裁决不改其他测试、不重复全门。
needs-decision: 2026-10-05T05:47:48+0200 起点全门停滞：只剩collab-gate.sh，其公开qwb-wake.sh --block --max-ms 1已持续约15分钟；测试监督器PID=74455（本副本tests/process_fixture.py tests/collab-gate.sh），wake PID=38843，测试范围为本副本.qwb-tmp/68/qwb-gate-4enzfid4。其余三段已结束，另有既有入口60s超时红。建议TERM本票这个精确监督器，保留全门失败及干预说明后续做；不改产品/夹具。新全门若同处停滞，同样有界停止并原样报告。
working: 2026-10-05T05:49:33+0200 起点全门已收齐rc=1、PASS=856、FAIL=2、1104.402s；只有本票监督器74455被TERM终止（max-ms 1运行超过15分钟），另有既有入口60s超时失败。干预单独留baseline-intervention.json，原始全门baseline.log；应用已定向验收候选，继续提交后全门，不重跑起点。
working: 2026-10-05T05:50:11+0200 四个获准文件已应用：订阅回收移入受监督串行尾段，smoke第88节仅全门延后；错过窗口退避1/2/4/8，5次与2s及missed不变。bash bin/qwb-test.sh fast rc0；shellcheck tests/full-gate.sh rc0；verify.py retry/orchestration/smoke_section均rc0；候选四文件逐字一致，开始提交后唯一一轮全门。证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V。
working: 2026-10-05T03:51:15Z 主控裁决：那轮卡住不是你的改动造成的，主控已现场取证并另开票 wake-exit-hang 处理（值守退出清理里无时限地等订阅子进程，子进程没被终止信号杀掉）。你已有界停止即可，如实记录。后续不要再跑全门：只跑快门、定向测试（tests/subscribe-reap.py、tests/process-entry-cleanup.py、改动涉及的文件）以及场景一所需的新旧 PASS 行对照（这一项需要全门输出时，改为分别单独跑 tests/smoke.sh 与 tests/full-gate.sh 的编排用例做对照，或说明做不到的部分留给主控）；全门由主控合并后串行跑。若再遇到值守不退的卡死，同样有界停止并原样报告。
working: 2026-10-05T05:53:29+0200 已读主控03:51:15Z裁决，停止裁决前03:50启动的全门：rc143、144.481s，四段部分日志留final-partial，干预留final-intervention.json，不再跑全门。裸订阅命令缺监督环境报QWB_TEST_GROUPS；同smoke监督环境下5次读龄均超2s，记录了1/2/4/8退避且仍失败。现全门已停，定向复测订阅与入口夹具；新旧完整PASS对照留主控。提交=73b571261882dc07f8844dba6352c804d7fd7ab8。
working: 2026-10-05T05:54:22+0200 定向订阅已完成：在原smoke监督环境运行python3 -B tests/subscribe-reap.py，rc0、8 PASS/0 FAIL、27.304s，normal/term/int均首轮量到，query return/timeout通过；与基点全门8条订阅PASS排序后cmp rc0（未归一化）。当前正在定向运行tests/process-entry-cleanup.py，不再跑全门。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V/standalone-after-cancel.log。
done: 2026-10-05T05:56:35+0200 sha=73b571261882dc07f8844dba6352c804d7fd7ab8；仅四个获准文件，产品零改动；fast rc0、full-gate shellcheck rc0；订阅定向rc0/8PASS/0FAIL/27.304s，入口完整定向rc0/76.721s（含两个Bash的12个五段编排/失败/TERM场景）。git status --short为空，测试残留进程=[]，仅保留证据目录。汇总与原始命令日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V/REPORT.md、summary.json。
done: 2026-10-05T05:56:35+0200 五场景：1 verify.py orchestration证明四段完成后尾段才起、且订阅8条新旧PASS排序cmp rc0；完整全门总PASS对照按最新主控裁决留主控。2 verify.py smoke_section默认调用实测，原监督环境订阅8条原文通过。3 verify.py retry打桩5次、等待1/2/4/8、原错误且子进程rc1。4 前2次错过第3次成功，attempts=3、只等1/2秒。5 尾段桩失败rc1、四段输出保留。上述verify均rc0；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V。
done: 2026-10-05T05:56:35+0200 基点full rc1/856PASS/2FAIL/1104.402s：既有入口60s超时，collab-gate max-ms1卡住约15分钟后只TERM本票监督器；根因另票wake-exit-hang。提交后已起full按主控03:51:15Z新裁决取消，rc143/0PASS/0FAIL/144.481s（部分输出、非完整门，不能比速度），四段部分日志final-partial；不再跑全门，合并后串行全门及总PASS对照留主控。原始记录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reap-test-load/.qwb-tmp/reap-load.sA5sTm4V/baseline.log、final-intervention.json；sha=73b571261882dc07f8844dba6352c804d7fd7ab8。
working: 2026-10-05T04:12:24Z 主控验收：读完全门编排与冒烟第 88 节改动；提交 73b5712 已 cherry-pick 进 main（015fb4f）。合并后 main @ 015fb4f 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、731 秒（同时有一个工人在跑另一轮全门，负载 25–41）；订阅回收实测出现在四段并发之后，三种模式均一次量到（读龄 1.21、0.21、0.19 秒），冒烟段第 88 节为跳过说明（.qwb-tmp/ctl-full-merge5.log）。
