# 任务书：只剩等人裁决的票时，Claude 值守钩子到期后安静退出，不再定时叫醒主控

```
任务 id:  audit-hook-quiet
state: verified
implementation-authorized: Rocky 2026-10-04「我是不希望有自动叫醒的，因为没有任何事情，不需要叫醒」「还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     2026-10-04 Rocky 提问「主控没有任何新任务，会不会有一个自动叫醒服务」；主控在临时项目里实测（见下）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-hook-quiet.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet（隔离副本，detached HEAD，基点 d01ddca）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：没有任何事情的时候，不要叫醒主控。每叫醒一次，主控就白跑一轮。

### 主控实测（main @ d01ddca，临时项目，周期调到 3 秒，连不到真 Herdr）

| 情形 | 现在的结果 |
|---|---|
| 没有任何未结票 | 钩子 0.3 秒内退出码 0，不叫醒——符合意图 |
| 只有一张 `needs-decision` 的票，已经叫过一次，之后无任何变化 | 等满两个周期后退出码 2，叫醒主控，文案是「值守接班未就绪」；主控回合结束后钩子再次启动，于是**每两个周期叫醒一次，无限循环**。真实周期是 2 小时，也就是每 4 小时空叫一次 |
| 一张 `running` 的票无变化，`QWB_REWAKE_MS` 大于 0 | 到重叫间隔时叫醒一次（时间兜底，本票不动） |
| 一张 `running` 的票无变化，`QWB_REWAKE_MS=0` | 等满两个周期后同样以「值守接班未就绪」叫醒 |

第二行就是违背意图的那一种：票在等人裁决，工人和系统都不会自己往前走，叫醒主控没有任何可做的事。这条「第二次到期就叫醒」是 10-01 的提交 `90aa764` 加进 `bin/qwb-hook-claude-stop.sh` 的，目的是值守到期时不要悄悄丢掉接班；9 月的版本是到期安静退出。

### 主控裁决

第二次到期时按「还有没有会自己往前走的事」分两种：

- **全部未结项都是未迁旧票，且状态都是 `blocked` 或 `needs-decision`**（含按现有规则归为 `needs-decision` 的非法状态票）：安静退出，退出码 0，stdout 与 stderr 都不输出，不写 `.hook.err`，不写任何 `wake:` 行。
- **其余情形**（存在 `running` 的未迁旧票，或存在任何未结的已迁协作票）：行为与现在逐字节相同——写 `.hook.err`、输出「值守接班未就绪」、退出码 2。

理由：等人裁决的票要往前走，一定先有人对主控说话，主控回合结束时钩子会重新启动值守，不存在丢接班；而 `running` 的票和已迁协作票可能在无人说话时自己产生新事实，值守悄悄结束才是真的丢接班，所以保留原有的门铃。

白名单：`bin/qwb-hook-claude-stop.sh`、`bin/qwb-wake.sh` 或 `bin/qwb-lib.sh`（仅在钩子需要一个「列出当前未结项及其状态与是否已迁」的只读入口、而现有入口不够用时，做最小的暴露；不改值守的任何判定）、`templates/host-watch-guide.md`（第 37 行那句相应改写）、`tests/` 下已接入的文件（现有断言在 `tests/lifecycle-readiness.sh` 第 198 行附近）。

### 工程规格

1. 判定「未结项是哪些、各是什么状态、是否已迁」必须复用现有的账本扫描（`bin/qwb-lib.sh` 的 `qwb_ledger_scan` 或 `bin/qwb-wake.sh` 的 `open_items` 口径），不在钩子里另写一套解析。口径与值守一致：未结项为 `running`、`blocked`、`needs-decision`，非法状态或账本损坏按 `needs-decision`。
2. 判定只在「第二次 124」这一个点上做，其他路径不增加任何调用：没有未结项时仍是立即退出；有新进展时仍是第一时间退出码 2；第一次 124 后仍接续一个周期。
3. 判定本身失败或结果不明（扫描出错、输出无法解析）时，按「其余情形」处理，即保留现有门铃——宁可多叫一次，不悄悄丢接班。
4. Pi 扩展（`templates/pi-extensions/qwb-watch.ts`）与 Codex 的前台 `--block` 不在本票范围，不改。
5. `templates/host-watch-guide.md` 第 37 行按新行为改写成一两句，写法与密度照该文件现有句子。

## 1. 验收场景

### user_正常路径_只剩等裁决的票时到期安静退出

Given 项目里唯一的未结票是未迁旧票，状态 `needs-decision`，已被叫醒过一次（票里有与当前进展指纹相同的 `wake:` 行），之后无任何变化；钩子周期调短
When  触发 `bin/qwb-hook-claude-stop.sh` 并等它连续两个周期到期
Then  退出码 0；stdout 与 stderr 为空；`.hook.err` 没有新增内容；票里没有新增 `wake:` 行；`.hook.lock` 已释放

### user_正常路径_blocked的票同样安静

Given 同上，但票的状态是 `blocked`；另一组是一张 `blocked` 加一张 `needs-decision`
When  同样触发并等两个周期到期
Then  两组都与上一条结果相同

### user_失败路径_有running的票时照旧叫醒

Given 未结票里有一张 `running` 的未迁旧票（`QWB_REWAKE_MS=0`，已叫过、无变化）；另一组是一张 `running` 加一张 `needs-decision`
When  触发钩子并等两个周期到期
Then  两组都是退出码 2、stderr 含「值守接班未就绪」、`.hook.err` 记下「连续两周期到期」——stdout、stderr、退出码、`.hook.err` 新增内容与起点提交 d01ddca 逐字节相同

### user_失败路径_有已迁协作票时照旧叫醒

Given 未结项里有一张已迁协作票（没有到期可投递的事件，值守返回 124）
When  触发钩子并等两个周期到期
Then  与起点提交逐字节相同（退出码 2、门铃文案、`.hook.err`）

### user_失败路径_判定出错时照旧叫醒

Given 只剩等裁决的票，但让未结项扫描在第二次到期时失败（例如账本目录在那一刻不可读；用测试自己能控制的方式制造，测完恢复）
When  触发钩子
Then  按原行为退出码 2 并给出门铃，不安静退出

### user_正常路径_安静退出之后有新进展仍会叫醒

Given 第一条场景安静退出之后，票里新增一条状态行
When  再次触发钩子
Then  第一时间退出码 2，摘要点名这张票——安静退出没有吞掉后续的新事实

### user_正常路径_其余既有行为逐字节不变

Given 起点提交 d01ddca 与改后的脚本
When  对「没有未结项」「有新进展」「非锁主会话」「单飞锁被占」「值守异常退出」「第一次 124 后第二周期内出现新进展」各跑一遍
Then  stdout、stderr、退出码、`.hook.err`、票内容新旧逐一相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何操作**；不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 钩子出错不能卡住主控这条既有原则不变；新增的判定不得让「没有未结项」的路径变慢。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。测试里的周期用毫秒级的短值（钩子从项目 `qwbuddy/config.sh` 读 `QWB_HOOK_MAX_MS`，环境变量会被它覆盖，改测试项目里的配置文件），不许真等两小时，也不许用 `sleep` 之外的忙等。
- 测试启动的进程记下 PID，测完逐个回收，结束时不留任何值守或订阅进程。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在 d01ddca 之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条控制在 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 已知情况：`tests/process-entry-cleanup.py` 在机器同时跑多个全门的高负载下会失败（起点就有的夹具竞态，另一张票在收口）。全门里只红这一条时，如实写进 `done:` 行并在低负载下单独重跑它三次附上结果，不要去修它。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `QWB_REWAKE_MS` 的时间兜底重叫、不改指纹去重、不改值守的任何叫醒判定、不改 Pi 扩展、不改 Codex 的值守说明。
- 不碰真 Herdr；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T20:28:51Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-hook-quiet pane=w14Z:pS dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet base=d01ddca
working: 2026-10-04T20:29:33Z 执行者已完整读取规格及点名文件；基点=d01ddcaea86c5ad31c356f3db9e734fc7ac6d97b，副本初始clean；仅第二次124复用qwb_ledger_scan做只读判定，失败保留门铃；开始实现和已接入生命周期回归。
working: 2026-10-04T20:36:14Z 实现与定向回归完成：仅第二次124增加只读判定；快门rc=0；/bin/bash tests/lifecycle-readiness.sh rc=0，覆盖7类验收及d01ddca逐字节对照，日志=.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/lifecycle.log。正在复核白名单改动并准备提交后全门。
working: 2026-10-04T20:37:30Z 提交前验收完成：/bin/bash 3.2.57下fast rc=0；lifecycle rc=0、PASS=29、FAIL=0，七类场景及额外非法状态/UTF-8/已迁done义务均通过；基点原实现同回归rc=1，精确失败于decision本应安静退出却rc2。白名单仅4文件，git diff --check通过。日志=.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/{fast.log,lifecycle.log,baseline-red.log}；开始提交后全门。
working: 2026-10-04T20:41:33Z 补查发现UTF-8 locale下损坏state字节被TSV正则拒绝；已局部LC_ALL=C与值守口径对齐，并补正文/state两组损坏回归。fast rc=0；lifecycle rc=0、PASS=30、FAIL=0；d146616原实现新state回归rc=1（locale-red.log）。此前全门经本票进程清理监督器停止，rc=143，保存superseded-full.log，不冒充通过；正在追加提交并重跑最终候选全门。
working: 2026-10-04T20:42:36Z 最终候选提交=c48da097bc33de9f78025ea177dbd94742423566，detached HEAD、副本clean；提交后bash bin/qwb-test.sh full运行中，监督PID=33053，原始日志=.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/full.log，结束码回执同目录full.rc。未操作真Herdr、分支、push或主仓代码。
working: 2026-10-04T20:54:27Z 最终候选c48da097bc33de9f78025ea177dbd94742423566提交后全门结束rc=1，仅FAIL tests/process-entry-cleanup.py（既有临时目录groups/socket-directories夹具竞态）；其余14项协作测试、smoke、review-identity、lint均通过，full后git status --short为空。全门日志=.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/full.log；已保存process-entry-full.log，开始低负载单项顺序复跑三次。
done: 2026-10-04T20:58:13Z 最终提交=c48da097bc33de9f78025ea177dbd94742423566（d01ddca之上两次追加提交，detached HEAD）。只改4个白名单文件；第二次124复用qwb_ledger_scan/qwb_task_obligations只读判定，旧票全等裁决则安静退出，未知保留门铃；已更新宿主说明。/bin/bash bin/qwb-test.sh fast rc=0、无新增ShellCheck告警；Bash=3.2.57。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/fast.log。
done: 2026-10-04T20:58:13Z 七场景逐个验证命令=/bin/bash tests/lifecycle-readiness.sh，rc=0、PASS=30、FAIL=0：needs-decision安静；blocked及混合安静；running及混合保留门铃；已迁票含done未结义务保留门铃；目录失效/扫描非0/rc0诊断/坏输出保留门铃；安静后新进展立即rc2点名；其余六路径与d01ddca逐字节相同。额外非法/空state和正文/state坏UTF-8在UTF-8 locale通过。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/lifecycle.log；旧基点及locale旧实现分别在预期断言失败，证据同目录baseline-red.log、locale-red.log。
done: 2026-10-04T20:58:13Z 最终提交后bash bin/qwb-test.sh full：rc=1、grep -c ^PASS=842、grep -c ^FAIL=1；唯一FAIL=tests/process-entry-cleanup.py既有groups/socket-directories临时目录竞态，其余14项协作测试及smoke/review-identity/lint通过。full后及最终git status --short均输出为空，git diff --check通过。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/full.log，退出回执full.rc、状态full-status.log/final-status.log、原失败process-entry-full.log在同目录；未修该夹具。
done: 2026-10-04T20:58:13Z 按已知例外要求，低负载（启动时1.54/18核）顺序三次python3 tests/process-entry-cleanup.py，rc=0/0/0，每次五个入口均通过、survivors=[]、new_directories=[]、bytecode=false。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-hook-quiet/.qwb-tmp/audit-hook-quiet/entry-recheck-1.log、entry-recheck-2.log、entry-recheck-3.log及对应.rc；最终残留进程清单=none（residual-processes.log）。本票临时源码导出已删除，只保留证据目录；未动state字段、主仓代码、真Herdr、分支或push。已完成。
working: 2026-10-04T21:19:38Z 主控验收：bin/qwb-hook-claude-stop.sh 与 bin/qwb-lib.sh 的改动逐行审过（只在第二次 124 处多一次只读判定，复用 qwb_ledger_scan 与 qwb_task_obligations；判定失败、有 running 旧票或任何未结的已迁票时保留原门铃）；两个提交 cherry-pick 到 main（a53942e、41fc0bd），与工人最终版 c48da09 的 bin/、templates/、tests/ 逐字节相同；fast rc=0；/bin/bash tests/lifecycle-readiness.sh rc=0、30 PASS / 0 FAIL。主控在临时项目实测（周期 3 秒、连不到真 Herdr）：无未结票 rc=0；等裁决票首次有进展 rc=2；之后无变化等满两周期 rc=0、零输出、.hook.err 零行、wake 行不增；再触发仍 rc=0；新增状态行后 rc=2；running 票（重叫关闭）无变化等满两周期仍 rc=2 并给出门铃。合并后 main 全门（另一工人同时跑整门，1002 秒）：rc=1、843 PASS、1 FAIL=tests/process-entry-cleanup.py（F47 夹具竞态），随后低负载单跑该测试三次均 rc=0；其余全过，予以合入。只测了假 Herdr 与临时项目，没有在真 Claude Code 会话里等过真实的 4 小时周期。
