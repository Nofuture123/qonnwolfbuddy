# 任务书：派发后确认开工的窗口太短；补回车的记账在门控派工时可能被拒

```
任务 id:  prompt-start-window
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     整仓审核报告 F56（docs/reviews/2026-10-03-qwb-full-audit-r1.md「副主控链路与派发可靠性」）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-prompt-start-window.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：机器负载高是常态；派工不能因为机器忙就把已经开工的工人判成派发失败。

### 事实（主控已核实）

1. `bin/qwb-run.sh` 的 `confirm_prompt_submitted`（约第 836–847 行）：投递提示词后调 `wait_prompt_started` 等 `PROMPT_SUBMIT_WAIT_MS`（第 209 行，5000 毫秒）；没等到就往票里追加一行 `working: …prompt-submit-enter op=… pane=…`，补一次回车，再等同样的 5000 毫秒；仍没等到就 `delivery_failed`（「提示词已投递但工人未开工…」）。
2. 2026-10-05 机器负载约 40 时，主控的手工派发脚本用同样的办法（查 `agent_status` 是否为 working，10 秒后补回车，再等 10 秒）报了「未开工」；约一分钟后看该窗口，Pi 正在正常干活。也就是从投递到 Herdr 显示 working 超过了 20 秒。主控没有量到确切秒数，也没有分清慢在 Pi 开始处理还是慢在 Herdr 查询本身。
3. 对空输入框多按一次回车，Pi 不做任何事（当天多次手工补回车，没有观察到副作用）。
4. 另一张票（`reuse-binding`）里发现：门禁角色经 `qwb-run.sh` 派工时，往已迁票追加普通 `working:` 行会被账本拒绝（`bin/qwb-ledger.sh` 约第 1501–1505 行，「门禁仅可写本人已派child活动绑定」，`qwb-run` 以 rc=25 失败）。那张票最后改成把说明打印到标准输出。

### 主控的推断（**读代码并用测试确认；不成立就写 `needs-decision:`**）

第 1 条里那行 `prompt-submit-enter` 也是经 `qwb_ledger … append` 写的普通 `working:` 行。门禁派工、提示词又恰好停在输入框时，这次追加会被账本拒绝，派发在补回车之前就失败了。规划派工时是否同样被拒，主控没有核实。

### 要做的事

1. **补回车仍在 5 秒时做，补回车之后的等待放宽。** 第一段等待保持 `PROMPT_SUBMIT_WAIT_MS`（5000）；补回车之后的第二段改用新的具名常量，默认 60000 毫秒。第二段内一旦确认开工立即返回，不白等。失败信息里的毫秒数相应改为第二段的值。
2. **补回车的记账不能让派发失败。** 先用测试确认上面的推断（门禁派工与规划派工各一条：提示词第一段没开工时会发生什么）。若被拒：把这行说明改为打印到 `qwb-run` 的标准输出（一行，含 op 与 pane），不再写进票；主控直接派工的路径同样改为标准输出，三条路保持一致。若你认为保留票内记录更好且能在不扩大门禁、规划写权限的前提下做到，写 `needs-decision:` 说明方案。
3. 首次派发、续派、`pane-run` 三条路共用这段逻辑，改动要同时覆盖。

白名单：`bin/qwb-run.sh`（仅上述常量与 `confirm_prompt_submitted`、`wait_prompt_started`）、`tests/` 下为验收所需的已接入文件。不改账本的权限规则。

## 1. 验收场景

### user_正常路径_补回车后二十秒才开工仍算派发成功

Given 假 Herdr：提示词投递后状态不变；补回车后要再过 20 秒（用测试已有的假时钟或睡眠替身推进，不真等）才变为 working
When  派发
Then  派发成功，只按了一次回车；这条用例在起点提交上是红的（5 秒后判失败），先跑出红并留证

### user_失败路径_补回车后六十秒仍未开工则派发失败

Given 假 Herdr：状态始终不变
When  派发
Then  第二段等满 60 秒（假时钟）后派发失败，退出码与起点提交相同，失败信息含原有排查命令；只按了一次回车

### user_正常路径_投递后立即开工时零等待

Given 现有夹具（投递后立刻 working 或序号变化）
When  跑现有的派发、续派、`pane-run` 用例
Then  标准输出、标准错误、退出码、票内容、Herdr 调用序列与起点提交逐字节相同

### user_失败路径_门禁与规划派工时提示词停在输入框

Given 门禁角色、规划角色各自经授权派工，假 Herdr 让提示词第一段不开工、补回车后开工
When  派发
Then  两者都派发成功，回车按了一次，说明出现在标准输出；票里没有被拒的痕迹，也没有多出的 `working:` 行。这条用例在起点提交上的结果如实记录（若起点就是绿的，说明主控推断不成立，写进 `done:` 行）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 真实应答样本在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/`（`agent-get-pi-done.json`、`agent-get-claude-working.json`、`agent-get-missing.json` 等），假 Herdr 的应答形状照样本，不凭空造字段。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改「开工」的判定条件（状态为 working 或序号变化）；不改第一段 5 秒；不多按回车。
- 测试不许真等 20 秒、60 秒；用现有的假时钟或睡眠替身。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 四个场景逐个验证，命令与结论写进 `done:` 行。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/runtime-readiness.sh`、`tests/collab-gate.sh`、`tests/collab-planning.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门。** 全门由主控在合并后串行跑。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
`done:` 行里另列：主控推断是否成立（门禁、规划各自的结果与拒绝信息原文）。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改账本权限；不改开工判定；不放宽任何现有断言。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T04:14:14Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-prompt-start-window pane=w14Z:p16 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window base=44ab8ac
working: 2026-10-05T04:15:12Z 执行者已完整读票与点名审核报告；基点44ab8ac，干净detached副本。确认三路径共用confirm_prompt_submitted；先在已接入runtime/gate/planning夹具用假时钟复现旧超时及角色append，再做白名单最小修复。日志目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence
working: 2026-10-05T04:18:27Z 角色红证完成：QWB_PROMPT_START_BASELINE=1 QWB_GATE_PROMPT_ONLY=1 bash tests/collab-gate.sh 验证旧门禁自然rc25、stderr原文「账本拒绝：门禁仅可写本人已派child活动绑定」、Enter=0；同基点规划窄验自然rc0、stderr空、Enter=1且说明写入票，规划未被拒。原输出见本副本.qwb-tmp/prompt-start-evidence/{gate,planning}-baseline.log。继续时间窗口红证与修复。
working: 2026-10-05T04:20:35Z 时间红证完成：QWB_PROMPT_START_BASELINE=1 bash tests/runtime-readiness.sh rc=1 PASS=38 FAIL=7；三个20秒开工用例均旧版rc1/clock10000/Enter5000，旧超时信息5000ms。已改共用常量/等待预算及stdout说明，门禁与规划修复窄验均rc0；开始runtime、collab-gate、collab-planning逐文件完整定向验收，不跑全门。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence
working: 2026-10-05T04:22:55Z runtime完整定向rc=0 PASS=48 FAIL=0；3路径20秒晚开工在clock25000成功，始终不变clock65000失败/60000ms诊断/原rc1，3路径立即开工六项原始字节与44ab8ac相同。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence/runtime.log。门禁/规划完整定向在跑，续做/bin/bash 3.2运行时验收。
working: 2026-10-05T04:25:08Z 系统/bin/bash 3.2运行时验收rc=0 PASS=48 FAIL=0，三路径原字节对照及延迟/超时均过；fast rc0，测试文件ShellCheck与基点诊断集合相同、新增0。完整门禁/规划仍执行中；早期规划窄验工具超时未收到外层退出回执，现补跑同基点窄验取得独立回执，原自然派发rc0证据保留。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence
working: 2026-10-05T04:29:09Z 全部验收收敛：fast rc0；runtime与Bash3.2各48/0、门禁25/0、规划19/0，各自然rc0；ShellCheck测试诊断23项与基点相同、新增0；仅4个白名单文件变化。早期超时的空登记目录6f核supervisor92929已不存在、登记全空后精确清理，当前无本票测试scope/后代。准备提交，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence
done: 2026-10-05T04:29:37Z 执行者完成，commit=7d09c2401005c5a5b372660f25aa5c7da68a44f6（detached HEAD），只改bin/qwb-run.sh与tests/{runtime-readiness,collab-gate,collab-planning}.sh。首段5000ms不变，第二段PROMPT_START_WAIT_MS=60000；补一次Enter说明改stdout含op/pane，三路径共用；权限、开工条件未改。代码副本干净；未跑仓库全门、未操作真Herdr/启动模型会话。
done: 2026-10-05T04:29:37Z 四场景之时间/即时路径：bash tests/runtime-readiness.sh rc0 PASS48 FAIL0。首次/续派/pane-run均5秒补Enter、再20秒在clock25000立即成功；永不变在clock65000失败，自然rc1与起点相同、诊断60000ms及三条排查命令保留、仅一次Enter；三路径立即开工clock0/零睡眠，stdout/stderr/rc/票/Herdr原始字节与44ab8ac相同（观察副本固定日期/op，不过滤结果）。旧版QWB_PROMPT_START_BASELINE=1同命令rc1 PASS38 FAIL7，三个晚开工用例均clock10000误失败。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence/{runtime,runtime-baseline}.log。
done: 2026-10-05T04:29:37Z 四场景之角色路径：QWB_GATE_PROMPT_ONLY=1 bash tests/collab-gate.sh rc0 PASS1 FAIL0；QWB_PLANNING_PROMPT_ONLY=1 bash tests/collab-planning.sh rc0 PASS4 FAIL0。两角色补一次Enter成功，stdout含op/pane，票无多出working/拒绝痕迹。加QWB_PROMPT_START_BASELINE=1测44ab8ac：门禁派发自然rc25、Enter0，拒绝原文「账本拒绝：门禁仅可写本人已派child活动绑定」；规划起点即绿、派发自然rc0、stderr空、Enter1且说明写票。主控门禁推断成立，规划未被拒；旧验证脚本外层均rc0。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence/{gate-baseline,planning-baseline-receipt,gate-prompt,planning-prompt}.log。
done: 2026-10-05T04:29:37Z 质量门：bash bin/qwb-test.sh fast rc0 PASS0 FAIL0；bash tests/runtime-readiness.sh rc0 PASS48 FAIL0；bash tests/collab-gate.sh rc0 PASS25 FAIL0；bash tests/collab-planning.sh rc0 PASS19 FAIL0；/bin/bash tests/runtime-readiness.sh rc0 PASS48 FAIL0（Bash3.2）。ShellCheck测试文件23项既有诊断与44ab8ac相同、新增0，对照rc0；git diff --check通过。cleanup rc0，supervisor92929死亡且空登记目录6f已精确回收；无本票测试进程/scope残留，保留证据日志。原始输出和自然退出回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-start-window/.qwb-tmp/prompt-start-evidence/{fast,runtime,gate,planning,runtime-bash32,test-shellcheck-compare,cleanup}.{log,rc}。
working: 2026-10-05T05:30:17Z 主控验收：读完产品改动（第一段 5 秒不变，补回车后的第二段 60 秒；补回车说明改为标准输出）。提交 7d09c24 已 cherry-pick 进 main（5e4a160）；独立跑 tests/runtime-readiness.sh rc=0 PASS=48。合并后首轮全门 rc=1：冒烟第 74 节写死该文件 42 项通过，本票加到 48 项而未同步（主控没让工人跑全门所致），主控补提交 4b1f2e2 改为 48。main @ 4b1f2e2 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、611 秒（.qwb-tmp/ctl-full-merge8.log）。主控对门禁派工的推断经工人测试证实（起点 rc=25），规划不受影响。
