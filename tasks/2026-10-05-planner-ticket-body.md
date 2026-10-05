# 任务书：副主控开的票要告诉工人提交；三处拒绝信息写出路

```
任务 id:  planner-ticket-body
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练（docs/reviews/2026-10-05-real-herdr-roles-drill.md 的 D1、D5、D5b、D8）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-planner-ticket-body.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：副主控开票派工之后，这张票要能一路走到门控验收。

### 真机上看到的事实（主控已核实，全文见演练记录）

1. 规划（副主控）用 `qwb-ledger.sh new` 开出的票，正文只有「原始意图、工程规格、必要约束、验收场景」（`bin/qwb-ledger.sh` 约第 994 行拼出来的）。它没有 `templates/TASK.md` 里给工人的报告要求。工人写好了文件、写了 `done:`，但没有提交，`done:` 行里也没有提交号。
2. 主控随后 `gate-assign` 被拒：`账本拒绝：授权候选必须clean`（`bin/qwb-ledger.sh` 约第 1346 行）。拒绝信息只有这一句。主控想让工人返修，但门禁派返修要先有 `gate-assign`，而 `gate-assign` 要求候选干净——说明书没给出路。演练里主控最后是走「规格缺陷处置 + `plan-authorize` 追加预算，让规划续派原工人」。
3. 配置里 `QWB_WORKSPACE` 为空时，`qwb-role.sh start` 被拒：`拒绝: 须有唯一已登记workspace，不回退focused默认窗口`（`bin/qwb-role.sh` 约第 351 行）。真 Herdr 对普通方式建出的工作区不返回 `worktree.repo_root`，自动匹配落空。拒绝信息没说要去 `qwbuddy/config.sh` 填 `QWB_WORKSPACE`。
4. 规划把给账本命令用的 JSON 载荷文件写在了项目根（`.qwb-drill-hello-created.json` 等四个），成了未跟踪文件。说明书没规定这些文件放哪。

### 要做的事

1. **`new` 生成的票带上工人的报告要求。** 在生成的正文里加一节固定文字（不由请求 JSON 提供、不可被请求覆盖），内容与 `templates/TASK.md` 给工人的报告要求一致，至少包括：只在本票的工作副本里改动并提交；全部完成后工作区须干净；`done:` 行写明提交号、跑了什么检查及原始结果；不改 `state:`。措辞从 `templates/TASK.md` 现有句子取，不另写一套；两处以后要保持一致，在 `tests/` 里加一条断言核对 `new` 生成的这一节与模板对应句子相同。`plan-revision` 与 `revise` 修订规格时这一节原样保留（先读约第 880 行的修订正则，确认新增一节不会让「工程规格格式不支持安全修订」误报，也不会被修订吞掉）。
2. **`gate-assign` 拒绝候选不干净时写出路。** 在原拒绝句之后补充：列出未提交或未跟踪的路径（上限若干条）；说明正路是让实现者在原副本提交后重试——带规划授权的票由规划在预算内续派原工人（预算不足由主控 `plan-authorize` 追加），未带规划授权的票由主控续派。原拒绝句开头保持不变，方便现有断言与人工检索。
3. **`qwb-role.sh start` 拒绝无工作区时写出路。** 原拒绝句之后补充：在 `qwbuddy/config.sh` 把 `QWB_WORKSPACE` 填成本项目主工作区的 id，并打印当前 `herdr workspace list` 里可选的 id；原拒绝句开头保持不变。
4. **规定规划的载荷文件位置。** `templates/roles/规划.md` 与 `templates/roles/门禁.md` 各加一句：给账本命令用的 JSON 载荷与结果引用文件一律放在 `qwbuddy/.roles/` 下本角色自己的工作目录里，不放项目根与 `tasks/`。先确认 `bin/qwb-role.sh` 登记时有没有现成的角色私有目录可用（例如会话目录旁边）；有就指向它，没有就写 `qwbuddy/.roles/<actor>.work/` 并确认安装器的忽略规则已覆盖 `qwbuddy/.roles/`。账本命令对载荷路径如有「必须在项目内」「不得在某目录」之类的校验，先读清楚，放不进去就写 `needs-decision:`。

白名单：`bin/qwb-ledger.sh`（仅 `new` 生成正文处、与之相关的修订正则、`gate-assign` 的候选干净拒绝信息）、`bin/qwb-role.sh`（仅上述拒绝信息）、`templates/roles/规划.md`、`templates/roles/门禁.md`、`templates/TASK.md`（仅当需要给被引用的句子加稳定锚点时）、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_规划开的票带报告要求

Given 规划在主控授权下用 `new` 开出一张票
When  读这张票
Then  正文含报告要求一节，文字与 `templates/TASK.md` 对应句子相同；请求 JSON 里即使带了同名内容也不能改写这一节；同一请求重放，票字节不变

### user_正常路径_修订规格后报告要求仍在

Given 上面那张票
When  走一次 `plan-revision` 加 `revise` 修订工程规格
Then  修订成功，报告要求一节字节不变

### user_失败路径_候选不干净时拒绝并给出路

Given 候选副本里有未跟踪文件与未提交改动
When  主控 `gate-assign`
Then  退出码与原来相同，stderr 以原拒绝句开头，后面列出相应路径并写明由谁续派；票字节不变

### user_失败路径_无工作区时角色启动拒绝并给出路

Given `QWB_WORKSPACE` 为空且假 Herdr 的 `workspace list` 不带 `worktree` 字段（照真机形态：`{"workspaces":[{"active_tab_id":"w1:t1","agent_status":"idle","focused":true,"label":"drill-main","number":1,"pane_count":1,"tab_count":1,"workspace_id":"w1"}]}`）
When  `qwb-role.sh start`
Then  拒绝，stderr 以原拒绝句开头，后面写明填 `QWB_WORKSPACE` 并列出可选 id `w1`；没有创建角色记录，也没有新建 tab

### user_正常路径_其余行为逐字节不变

Given 起点提交与改后的脚本
When  跑现有的协作票用例（`new` 之外的账本命令、`gate-assign` 成功路径、`qwb-role.sh start` 成功路径）
Then  stdout、stderr、退出码、票内容新旧相同（`new` 生成的票多出报告要求一节除外）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改任何放行条件：候选不干净仍然拒绝，无工作区仍然拒绝，只是把出路写出来。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 同时有别的票在改：`bin/qwb-wake.sh` 与 `bin/qwb-ledger.sh` 的交接路由和 handled（副主控上报）、`bin/qwb-run.sh` 与 `bin/qwb-herdr.sh`（提示词提交确认、续派身份绑定）。这些地方本票不要碰；`tests/collab-planning.sh` 多张票都会改，只做本票需要的最小改动。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改交接路由、不改授权与预算逻辑、不改门禁验收条件。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T02:54:21Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-planner-ticket-body pane=w14Z:p12 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body base=d66d77c
working: 2026-10-05T02:56:09Z 执行者阶段1完成：完整读任务书与演练/模板/角色文档；基点d66d77c且副本clean。报告节置于场景后可由现有正则原样保留；载荷使用qwbuddy/.roles/<actor>.work/，安装忽略已覆盖且读取允许。日志目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z。
working: 2026-10-05T02:59:51Z 执行者阶段2完成：新增已接入planning/roles断言，在基点d66d77c实现上红证rc1，原因分别为缺报告节及拒绝缺配置改法；原输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/red-planning.log、red-roles.log。已完成最小实现，正在跑场景与快门；role原退出码核实为1。
working: 2026-10-05T03:04:41Z 执行者验收中：冻结后roles rc0/PASS24/FAIL0，快门rc0且无shellcheck告警；规划新增基点字节对照夹具的--project位置错误已修正，重跑中。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/final-roles.log、final-fast.log、verified-planning.log；全门待提交后执行。
working: 2026-10-05T03:11:48Z 执行者阶段3完成：产品场景及修订保留已验证；roles完整rc0/PASS24/FAIL0，fast rc0；补充字节/dirty/10条上限/报告边界定向复验rc0（/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/byte-dirty-check.log）。先前planning失败为观察夹具参数与time/gmtime冻结问题，原日志保留；当前7文件准备提交，再以提交后full完整验收。
working: 2026-10-05T03:12:13Z 执行者阶段4：已提交ca066a8f66641648eeba2861c263f06ef005bcfb，git status --short为空；提交后启动bash bin/qwb-test.sh full，pid=62451，原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/full.log，退出回执=full.rc；等待完整结果，尚未done。
working: 2026-10-05T03:14:45Z 执行者更正阶段1状态行的路径示意：验收实际使用qwbuddy/.roles/planner.work/request.json；后续状态行均使用具体路径。提交后full仍执行中，review-identity与lint阶段已有完整PASS，等待smoke及collab-all退出回执。
working: 2026-10-05T03:24:18Z 执行者阶段5完成：提交后full内planning完整rc0/663s/PASS9/FAIL0，roles完整rc0/233s/PASS24/FAIL0；五个场景与旧新字节对照全部通过，已保存/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/full-planning.log和full-roles.log及各st回执。总门仍待其余协作测试，不提前done。
blocked: 2026-10-05T03:28:13Z 提交ca066a8f66641648eeba2861c263f06ef005bcfb的全门smoke第88节未能验证：subscribe-reap normal连续5次错过真实2秒观察窗口，读龄3.624/3.263/2.867/3.545/2.708秒；原输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/full.log（总门其余段仍执行中）。本票planning rc0/PASS9、roles rc0/PASS24；无产品残留证据，不改窗口/断言。待总门结束单独核验环境失败。
working: 2026-10-05T03:40:20Z 执行者阶段6收齐全门：bash bin/qwb-test.sh full rc1/PASS849/FAIL2（grep -c列首统计），原输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/full.log；失败为subscribe-reap normal观察窗口未建立，以及process-entry-cleanup的root-tab-missing入口60秒超时。本票planning/roles均rc0，candidate clean。已在保留process_fixture/socket隔离条件下单跑subscribe；之后单跑entry-cleanup，不改断言/超时或扩大实现。
working: 2026-10-05T03:45:29Z 执行者最终场景证据：1生成报告/模板相同/防覆盖重放、2修订报告保留、3dirty路径及续派出路、5read与gate成功字节对照由bash tests/collab-planning.sh验证（full内rc0/PASS9）；4无workspace出路及5role start字节对照由bash tests/collab-roles.sh验证（rc0/PASS24）。快门rc0；逐项命令、原始输出和边界见/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/report.md。
blocked: 2026-10-05T03:45:29Z STOP 全门质量未过；候选ca066a8f66641648eeba2861c263f06ef005bcfb。full rc1/PASS849/FAIL2；subscribe单跑rc1仍未建立2秒窗口，entry-cleanup单跑rc1在full-gate TERM观察到临时目录残留，超出本票实现范围；不改阈值/断言或自放行。证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/planner-ticket-body/.qwb-tmp/planner-body.nUwLEx1Z/report.md、full.log、subscribe-standalone.log、entry-standalone.log。最终git status --short为空，残留测试进程清单=[]；只余自有日志与指针，未改state，不写done。
working: 2026-10-05T04:12:24Z 主控验收：读完产品与模板改动，独立跑 tests/collab-planning.sh rc=0 PASS=9、tests/collab-roles.sh rc=0 PASS=24；提交 ca066a8 已 cherry-pick 进 main（abf5d05）。工人自己的全门因多轮全门并发在 subscribe-reap 与 process-entry-cleanup 上超时失败，不作数；合并后 main @ 015fb4f 上主控串行跑 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、731 秒（.qwb-tmp/ctl-full-merge5.log）。
