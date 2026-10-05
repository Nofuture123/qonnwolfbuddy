# 任务书：副主控开的票场景标题不合门控要求——开票时就该拦；两处拒绝信息写出路

```
任务 id:  scenario-names
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第二轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r2.md） 的 R1、R2
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-scenario-names.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/scenario-names（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：副主控开票派工之后，这张票要能一路走到门控验收。

### 事实（主控已核对代码与演练记录）

1. 副主控用 `qwb-ledger.sh new` 开的票，场景小节标题是「### 单行内容」「### 失败路径」。工人交付后主控 `gate-assign` 被拒：`账本拒绝：需要冻结的命名场景`。
2. `new` 校验场景用的 `scenarios_ok`（`bin/qwb-ledger.sh` 约第 352–355 行）只查场景块里有 Given、When、Then 与失败类关键词。`gate-assign`（约第 1374–1376 行）用 `/^###\s+(user_[^\s]+)\s*$/mg` 取场景名，一个都取不到就拒。两处标准不一致，缺口到门控授权时才暴露，此时工人已经交付。
3. `templates/TASK.md` 第 45 行写着「场景命名：项目有测试框架时以 `user_` 开头；没有测试框架时用同名小节标题即可」，与 `gate-assign` 的硬要求冲突。
4. 主控想自己把标题补上 `user_` 前缀，`revise-scenarios` 被拒：`账本拒绝：规划票修订须使用持久plan-revision/CAS`（约第 1612 行）。拒绝信息没写该怎么办。演练主控摸索出的正路：主控在入口票用 `qwb-send.sh send` 给规划发修订请求，规划执行 `plan-revision` 再 `revise`。

### 要做的事

1. **开票与修订时就按门控的标准校验场景名。** `new`，以及规划票的 `revise`（含 `plan-revision` 之后的修订），要求场景块里至少有一个 `### user_` 开头的场景标题，且场景块里每个三级标题都是 `### user_` 开头（取名规则与 `gate-assign` 第 1375 行用同一个定义，抽成一处，不各写一套）。不满足就拒绝，信息写明规则与一个合规示例。主控直接开的未迁旧票不受影响（那条路由 lint 与 `qwb-run.sh` 管，本票不动）。
2. **`gate-assign` 的拒绝写出路。** 「需要冻结的命名场景」之后补充：场景标题须为 `### user_名字`；带规划授权的票由主控向规划发修订请求、规划 `plan-revision` 加 `revise`；其余已迁票由主控 `revise-scenarios`。原拒绝句开头不变。
3. **`revise-scenarios` 对规划票的拒绝写出路。** 「规划票修订须使用持久plan-revision/CAS」之后补充：主控在承载该请求的入口票上用 `qwb-send.sh send` 给规划发修订请求，由规划执行 `plan-revision` 与 `revise`。原拒绝句开头不变。先读代码确认这条路确实如此（来源票、命令名、谁有权执行），与上面第 4 条事实不符就写 `needs-decision:`。
4. **说明书对齐。** `templates/TASK.md` 第 45 行改为：需要走门控验收的票，场景标题一律 `### user_` 开头。`templates/roles/规划.md` 加一句：开票与修订时场景标题必须是 `### user_名字`，否则开票被拒。

白名单：`bin/qwb-ledger.sh`（仅场景名校验、`new` 与规划票 `revise` 的调用处、上述两处拒绝信息）、`templates/TASK.md`（仅第 45 行那句）、`templates/roles/规划.md`、`tests/` 下为验收所需的已接入文件（现有夹具里不合规的场景标题按新规则改名）。

## 1. 验收场景

### user_失败路径_开票时场景标题不合规即拒绝

Given 规划在主控授权下开票，请求里的场景标题是「### 单行内容」
When  `new`
Then  拒绝，信息写明标题须为 `### user_` 开头并给示例；没有生成票文件；这条用例在起点提交上是红的（开票成功），先跑出红并留证

### user_失败路径_混有不合规标题也拒绝

Given 场景块里一个标题是 `### user_正常路径_甲`，另一个是「### 失败路径」
When  `new`
Then  拒绝，指出不合规的那个标题

### user_正常路径_合规标题开票后门控授权通过

Given 场景标题全部是 `### user_` 开头，工人交付了干净候选
When  `new`，之后主控 `gate-assign`
Then  两步都成功

### user_失败路径_修订成不合规标题被拒

Given 一张合规的规划票
When  规划走 `plan-revision` 后 `revise`，新场景块里有不合规标题
Then  拒绝，票字节不变

### user_失败路径_两处旧拒绝带出路

Given 一张没有 `user_` 场景名的已迁票（用旧数据夹具或直接构造），以及一张规划票
When  分别 `gate-assign` 与主控 `revise-scenarios`
Then  退出码与原来相同，标准错误以原拒绝句开头，后面是上述出路文字；票字节不变

### user_正常路径_其余行为逐字节不变

Given 起点提交与改后的脚本
When  跑合规场景下现有的开票、修订、门控授权用例
Then  标准输出、标准错误、退出码、票内容新旧相同

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
- 六个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh`、`tests/collab-gate.sh`、`tests/collab-ledger.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（多个工人同时跑全门会互相挤出超时类假失败，全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了该文件 PASS 条数或用例组数的地方（例如冒烟某节的 `-eq 48`、`tests/herdr-batch.py` 的组数断言），同步改成新值；这些计数行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改授权与预算逻辑；不改门禁验收条件；不放宽任何现有断言。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T05:23:17Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-scenario-names pane=w14Z:p1A dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/scenario-names base=4b1f2e2
working: 2026-10-05T05:24:29Z 执行者已完整读规格、TASK/规划说明和主仓演练记录；核对 new/plan-revision/revise/gate-assign 与03来源、02权限中，改动仅隔离副本；无真Herdr/模型调用。
working: 2026-10-05T05:26:46Z 基点4b1f2e2先红已留证：QWB_SCENARIO_NAMES_ONLY=all bash tests/collab-planning.sh，rc1/PASS4/FAIL4；旧new对全错与混合标题返回0，旧revise对非法标题返回0；合规交付门控和成功字节对照通过。日志=.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/baseline-red-valid.log。修订路径源码已确认，开始最小修复。
working: 2026-10-05T05:29:25Z 最小修复完成；最终六场景QWB_SCENARIO_NAMES_ONLY=all rc0/PASS8/FAIL0；同断言固定基点回放rc1/PASS4/FAIL4（两处出路均缺）；旧拒绝自然rc与原前缀保留，new/revise/gate-assign合规stdout/stderr/rc/票全字节一致。日志=.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/{baseline-final,scenarios-final}.log；开始快门及三份定向。
working: 2026-10-05T05:31:37Z 补获场景块边界反例：场景外user_标题曾误放行，boundary-red.log rc1/PASS2/FAIL1；已让新命名校验复用scenario提取，gate标准不改。因源码补改，当前串行门日志作为attempt1留存，结束后重跑最终定向门。
working: 2026-10-05T05:38:24Z 首轮规划33 PASS/0 FAIL但自然rc2：运行期间补入边界用例后，Bash在脚本末段读源偏移报syntax error；当前与基点bash -n均rc0。首败planning.log保留，不当通过；冻结源码的final-planning完整复跑已串行排队。快门原rc0；gate/ledger正按最终源码运行。
working: 2026-10-05T05:43:03Z 最终源码下 /bin/bash tests/collab-gate.sh 完成rc0/PASS25/FAIL0，日志=.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/gate.log；账本单跑中；冻结源码后的fast/planning复跑仍按本票串行排队。
working: 2026-10-05T05:44:53Z /bin/bash tests/collab-ledger.sh rc0/PASS8/FAIL0；冻结源码后的 bash bin/qwb-test.sh fast rc0/PASS0/FAIL0、无ShellCheck告警。final-planning完整复跑中，六新增场景已通过；日志=.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/{ledger,final-fast,final-planning}.log。
done: 2026-10-05T05:52:04Z sha=bfb63d5b009f8702863bea196363e7b30799c786 六场景：QWB_SCENARIO_NAMES_ONLY=all bash tests/collab-planning.sh rc0/PASS8/FAIL0；invalid-new（含无标题/空后缀/场景外标题）、mixed-new、valid-gate、invalid-revision、refusal-routes、byte-equivalence均通过；旧拒绝自然rc/前缀与票字节保留，合规new/revise/gate-assign完整字节一致。固定基点回放rc1/PASS4/FAIL4；边界先红rc1/PASS2/FAIL1。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/scenarios-complete.log、baseline-final.log、boundary-red.log。
done: 2026-10-05T05:52:04Z sha=bfb63d5b009f8702863bea196363e7b30799c786 验收门：bash bin/qwb-test.sh fast rc0/PASS0/FAIL0、无ShellCheck告警；/bin/bash tests/collab-planning.sh rc0/PASS33/FAIL0；/bin/bash tests/collab-gate.sh rc0/PASS25/FAIL0；/bin/bash tests/collab-ledger.sh rc0/PASS8/FAIL0；Bash3.2，源码冻结前后SHA256一致。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/final-fast.log、final-planning.log、gate.log、ledger.log；首轮规划rc2/PASS33/FAIL0日志planning.log保留，冻结重跑已通过；未跑全门。
done: 2026-10-05T05:52:04Z sha=bfb63d5b009f8702863bea196363e7b30799c786 入口计数：在tests/smoke.sh、tests/collab-all.sh搜索改动文件collab-planning.sh，并扩搜整个tests/；仅collab-all默认清单和排序引用，无PASS/组数硬编码，计数改动0处，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/scenario-names/.qwb-tmp/scenario-names-evidence/entry-count-audit.log、all-test-references.log。仅四个白名单文件提交，detached基点上追加，工作区clean；本票测试进程与临时项目已回收，仅保留证据目录（cleanup-check.log）。无真Herdr/模型会话，无分支/push；state字段未改。
working: 2026-10-05T07:15:35Z 主控验收：读完产品与模板改动；提交 bfb63d5 已 cherry-pick 进 main（0b72de8）。两处合并后修正由主控补提交：本票的字节对照用例基线钉在 4b1f2e2，合入 collab-notify-gaps 后失败，改为「当前脚本只去掉场景名校验」（3f26a6d）；拒绝信息里 $title 后紧跟中文标点，被账本检查与冒烟第 8 节拦下并连带 43 项失败（工人只跑了快门，快门不含这条检查），改为 ${title}（adfb7b4）。修正后 QWB_SCENARIO_NAMES_ONLY=all 的 collab-planning rc=0 PASS=9。main @ adfb7b4 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、825 秒（.qwb-tmp/ctl-full-merge10.log）。
