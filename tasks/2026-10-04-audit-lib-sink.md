# 任务书：跨脚本逐字重复的小函数下沉到共享库

```
任务 id:  audit-lib-sink
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F14 的 bash 侧、F15、F17、F26、F28、F39）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-lib-sink.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-lib-sink（隔离副本，detached HEAD，起点 main 8d897cd）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

同一段逻辑在多个脚本里各写一份，已经查出抄走样的例子。本票把 bash 侧能安全下沉的收进 `bin/qwb-lib.sh`。行号以 `4678ba0` 为准，现在已有偏移，自己重新定位。

白名单：`bin/qwb-lib.sh`、`bin/qwb-run.sh`、`bin/qwb-wake.sh`、`bin/qwb-lint.sh`、`bin/qwb-lock.sh`、`bin/qwb-send.sh`、`bin/qwb-init.sh`。

### 工程规格

**A. 主控锁 owner 解析（F17）。** `<时间戳> <owner>` 这个文件现在 bash 侧有多种读法：`bin/qwb-lock.sh`（两处，sed 取首行去首字段）、`bin/qwb-wake.sh`（两处 sed、一处 awk 取首行末字段）、`bin/qwb-send.sh`（awk 取首行末字段）。lib 新增 `qwb_lock_owner <项目根>`（输出 owner，无锁或空文件输出空串，不报错），语义取「首行、去掉第一个字段及其后的空白」。逐处替换前先证明：对「正常单行」「多行」「owner 含空格」「空文件」「文件不存在」这五种输入，该调用点新旧结果相同；有任何一种不同，就保留原写法并在 `working:` 行写明差异（不要为了统一去改行为）。`bin/qwb-hook-claude-stop.sh` 取的是末非空行，语义不同，不在白名单，不动。`qwb-lock.sh`、`qwb-send.sh` 目前不 source lib：先看它们为什么不 source（启动开销、被谁调用），加 source 会不会改变它们的行为或输出，再决定；拿不准就不动它们。

**B. 计时与睡眠（F28）。** `now_ms` / `sleep_ms` 在 `bin/qwb-run.sh` 与 `bin/qwb-wake.sh` 各一份，函数体原本逐字相同，第 1 波只给 wake 那份做了「优先用 bash 内建、不起子进程」的优化。把优化后的版本搬进 lib（保留 `QWB_NOW_MS_CMD` / `QWB_SLEEP_CMD` 两个测试注入点，调用次数不变），两个脚本删掉自己的定义。注意定义位置要早于首次调用。`bin/qwb-dispatch.sh` 另有一份自己的 `now_ms`，它不 source lib，不动。

**C. 单引号转义（F28）。** `bin/qwb-run.sh` 的 `quote_shell_arg` 与 `bin/qwb-init.sh` 的 `quote_worker_arg` 函数体相同。lib 新增 `qwb_shell_quote`，run 改用它。init 是安装器、目前不 source lib：同 A，先评估再决定，拿不准就只改 run。

**D. 值守内部重复（F26）。** 只在 `bin/qwb-wake.sh` 内：可见值守「投递启动命令 → 探测若干次 → 取 pid → 登记」在原 pane 重启与新开 tab 两条路各抄一份；gate 身份 proof 的规范化两行抄两份；同一句「跳过…已叫过，进展未变」在 if/else 两侧各写一次；`lostrc` 可由 `worker_lost` 的输出推导；取锁主的同一条 sed 管道写两次。各提成一个本地函数或合并条件，失败文案留在各自调用点。

**E. 验收场景门（F14 的 bash 侧）。** 「Given/When/Then 或至少两个 `user_` 标题」加「失败路径关键词」这套判定，`bin/qwb-run.sh` 与 `bin/qwb-lint.sh` 各写一份（lint 注释写明与派发门同标准）。lib 新增一个判定函数（stdin 读场景块，输出 `ok` / `no-scenario` / `no-failure-path`），两边调用，各自的报错文案与「缺指纹时 run 拒绝、lint 警告」的策略留在调用方。必须以 lint 现在的写法为准（读完全部输入、不提前退出），并保证 `tests/lint-scenario-stream.sh` 仍然通过。`bin/qwb-ledger.sh` 里 perl 的那三份不在本票。

**F. 已迁票未结义务的 `ci-` 漂移（F15）。** `bin/qwb-ledger.sh` 排除 `handoff-|ci-|gate-(?!verdict)`，`bin/qwb-lib.sh` 的 `qwb_task_obligations_json` 只排除了 `handoff-|gate-(?!verdict)`——账本那边后来加了 `ci-`，lib 没跟上。后果：带 CI 事件的已迁票被值守和点名永远算作未结。把 lib 对齐到账本（这是本票唯一一处**有意的行为修正**），并在函数上方加一行注释指向账本里的对应位置。用一张带 `ci-assign` 事件的已迁票夹具证明：修正前 lib 报 `source=…`、修正后不报，而账本的 `pending` 结果前后一致。

**G. 值守临时文件泄漏（F39）。** `bin/qwb-wake.sh` 用 `mktemp "${TMPDIR:-/tmp}/qwb-due.XXXXXX"` 建临时文件（两处）。主控清理系统临时目录时发现 41 个残留的 `qwb-due.*`——值守在创建与删除之间被终止时没人清。让它在所有退出路径（含 INT/TERM）上都删掉自己建的那个文件：检查现有的 `trap`（`event_cleanup` 等）如何组织，把它并进去，不要覆盖已有的清理。用「创建后立刻对值守发 TERM」重复 20 次证明不再残留。

## 1. 验收场景

### user_正常路径_各脚本输出逐字节不变

Given 起点提交的 `bin/`（git archive 导出到副本 `.qwb-tmp/` 下）与改后的 `bin/`，以及一个用假 herdr 的临时项目
When  对每个被改脚本的主要入口各跑一遍新旧对比：`qwb-run.sh`（herdr 类首次派发、pane-run 派发、场景门拒绝、缺失败路径拒绝）、`qwb-wake.sh`（`--dry-run --once`、`--once`、`--block --max-ms`、`--check`、`--ensure` 的两条路）、`qwb-lint.sh`（健康项目、场景缺失、缺失败路径）、`qwb-lock.sh`（acquire / status / release）、`qwb-send.sh`
Then  除 F 项涉及的已迁票义务输出外，stdout、stderr、退出码、假 herdr 调用日志逐字节相同

### user_失败路径_锁文件异常时行为不变

Given 锁 owner 文件分别是多行、owner 含空格、空文件、不存在
When  新旧各跑用到锁主的入口（`qwb-lock.sh status` 与 release、`qwb-wake.sh --block` 的锁复核、`qwb-send.sh`）
Then  新旧 stdout、stderr、退出码逐字节相同

### user_失败路径_场景门照样拒绝

Given 无场景块、只有一个 `user_` 标题、有 Given/When/Then 但没有失败路径关键词、场景块很大（超过 200KB）的四张任务书
When  新旧各跑派发与 lint
Then  拒绝与否、报错文案、退出码逐字节相同；`bash tests/lint-scenario-stream.sh` 通过

### user_正常路径_CI事件不再让已迁票永远未结

Given 一张 `state: done`、带 `ci-assign` 事件且无其他未结义务的已迁票
When  跑改后的 `qwb-status.sh` 与 `qwb-wake.sh --dry-run --once`
Then  它不再被列为未结；同一夹具在起点提交上会被列为未结；其余类型的未结义务（claim、handoff、未答问题）照旧被列出

### user_失败路径_值守被终止不留临时文件

Given 值守运行到已建出 `qwb-due.*` 文件的时刻
When  对它发 TERM，重复 20 次；另对 INT 重复 20 次
Then  每次之后该次值守建的 `qwb-due.*` 都已不存在；值守退出码与修复前相同（143 / 130）

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行；逐项写明 A–G 各做了什么、跳过了什么及原因、各脚本行数前后变化。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`（含 12 个协作测试，值守与锁的改动必须经它们检验），重定向到自己建的日志文件。起点主仓是 840 PASS / 0 FAIL（副本里少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 6. 本票不允许做的事

- 不改 `bin/qwb-ledger.sh`、`bin/qwb-herdr.sh`、`bin/qwb-worktree.sh`、`bin/qwb-status.sh`、`bin/qwb-hook-claude-stop.sh`、`templates/`、`tests/`。
- 不做 herdr 响应解析的统一（另一张票）；不改值守的去重指纹、兑底重叫、投递、1 秒节奏。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离（死路径 `HERDR_SOCKET_PATH`）、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程，禁止按名字模式批量杀。
- git：只读命令（`git log`、`git show`、`git archive`）随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 行为不变是硬线：每个被改脚本的 stdout、stderr、退出码、账本写入、herdr 调用序列逐字节不变。每一项单独做、单独自检；不能确认等价的就跳过并写明原因——少做不扣分，改坏才扣分。
- `bin/qwb-lib.sh` 被所有脚本 source：新增函数可以，现有函数的签名与行为不许变。
- 不改 `bin/qwb-ledger.sh`、`bin/qwb-herdr.sh`、`bin/qwb-worktree.sh`（另有票在动或将要动它们）与 `tests/`。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T09:16:59Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-lib-sink pane=w14Z:pE dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-lib-sink base=8d897cd
working: 2026-10-04T09:18:17Z 阶段0完成：完整读取任务书及全仓审核r1；确认detached起点8d897cd、工作区干净、只改白名单，使用假Herdr与仓内临时目录验收。
working: 2026-10-04T09:20:06Z 阶段1完成：preflight.py五种owner原始结果存于.worktrees/audit-lib-sink/.qwb-tmp/lib-sink.NBY2in/preflight.log；awk在含空格owner时输出words而首行去首字段输出pane extra words，保留wake计划入口与send的awk；缺文件旧sed rc1/helper rc0，wake两处均在条件/echo上下文，将以公开入口复核；lock/init保持独立入口，避免引入缺lib新失败。E反例：起点run场景门对72字节合法块rc0，对1019976字节同结构合法块rc1无可识别场景（grep-q/pipefail），因此按行为不变硬线保留run旧门，仅下沉lint的完整读取判定，不修本票未授权的大块派发行为。
working: 2026-10-04T09:40:05Z 阶段2完成：A新增qwb_lock_owner，仅替换wake两处sed（5输入输出与公开block复核等价），awk/lock保留；B优化计时/睡眠原样下沉，run/wake删重复定义；C新增qwb_shell_quote并接run，init因独立安装器保留；D启动探测登记/gate proof各提本地函数、合并跳过文案、去lostrc；E共享lint完整读取判定，run因1MB反例会改变行为保留；F排除ci-并注释指向handoff-pending；G共享全局due路径与EXIT清理，创建窗口记中断且忽略重复转发信号。bash bin/qwb-test.sh fast rc0无shellcheck告警；bash tests/lint-scenario-stream.sh rc0（4 PASS）；python3 -B .qwb-tmp/lib-sink.NBY2in/units.py rc0，bash3.2/bash5计时注入次数、默认毫秒、7个转义值、5种owner均通过；ci-signals.py rc0：CI旧source=ci-fixture /新空、ledger pending两边[]，claim/question/handoff保留；once/block各TERM20+INT20，80次新版本无due残留、rc143/130、每次自建进程组live=0，4次旧版本均留due。全部证据在本副本.qwb-tmp/lib-sink.NBY2in/。
working: 2026-10-04T09:41:15Z 阶段3完成：python3 -B .qwb-tmp/lib-sink.NBY2in/equivalence.py由runner后台完整执行，equivalence-final.rc=0、46 PASS，逐字节比较stdout/stderr/rc/任务书及.watch/owner/Herdr日志；4种场景含1019976字节大块、run两种派发、wake dry/once/block124/check/ensure新建与原pane重启及两类失败、lint、锁五输入status/release/acquire、send五输入均通过。已提交db8885c（Share shell helpers and clean watcher due files）；正在该固定提交上执行一次bash bin/qwb-test.sh full，日志本副本.qwb-tmp/lib-sink.NBY2in/full.log，退出回执full.rc。
working: 2026-10-04T09:50:35Z 全门验收中出现1 FAIL：smoke第76节lifecycle-readiness.sh的真实Node扩展在2秒窗内未同时出现.watch与睡眠marker，完整失败日志保存在本副本.qwb-tmp/lib-sink.NBY2in/full-first-lifecycle.log；当前全门仍运行，先等完整退出回执，不采信局部PASS，不改测试断言。机器uptime负载约11.89/23.75/29.69，仅是环境线索，根因尚未定。
working: 2026-10-04T10:02:02Z 返修收敛：首轮full完整rc1/802 PASS/1 FAIL、工作区干净且残留进程[]，保留full.log/full.rc/full-first-summary.json。真实生命周期起点rc0/候选rc1，观察副本记录第一轮宿主死亡后Python订阅器持有.supervisor.guard，下一轮exit75；PIPE观察证明stdout关闭的SIGPIPE在EXIT前截断清理。增加保留141退出码且先忽略重复PIPE的trap进入原EXIT收尾；不改tests/templates/阈值。原tests/lifecycle-readiness.sh候选修后rc0/6 PASS；fast-final.rc0无告警；ci-signals-final.rc0/89 PASS、两个入口TERM20+INT20重新完整通过；equivalence-ship.rc0/46 PASS。已追加提交，马上在新固定HEAD跑收尾全门。
working: 2026-10-04T10:06:48Z 收尾全门固定对象=23893a918dc49b4b15e2bfb552b5865b7f9791b8（在db8885cf62187c61289b424c5fe7efcc2329139c上追加）；后台runner PID=29886，日志本副本.qwb-tmp/lib-sink.NBY2in/full-final.log、full-final.rc。前一轮红门证据完整保留；当前源码未再修改，工作区clean，等待12项协作门及完整退出回执。
working: 2026-10-04T10:18:38Z 最终固定HEAD的收尾full已自然结束：rc1，grep计数待收尾核对（逐行795 PASS/1 FAIL），失败为tests/subscribe-reap.py原有read_age小于2秒的窗口断言，实际2.546638秒并发生既有2秒query超时；生命周期已通过。起点bin的同一公开probe rc1/年龄2.681520秒、最终候选rc1/3.606052秒，均missed live-reader window，证据reap-old.log/reap-new.log；机器负载82.07/72.23/64.04。未改测试/超时，完整全门尚不合格；正补跑被&&阻断的review-identity、lint与默认12项collab-all，日志remaining.log/remaining.rc。
working: 2026-10-04T10:23:28Z audit-lib-sink commit=23893a918dc49b4b15e2bfb552b5865b7f9791b8；固定起点8d897cd，只提交bin/qwb-lib.sh/qwb-run.sh/qwb-wake.sh/qwb-lint.sh，未改state字段、未建分支/未push/未写真Herdr。 A：qwb_lock_owner首行去首字段，wake两处sed下沉；五种输入命令替换输出一致，缺文件helper rc0但旧sed rc1，两处公开block条件/echo上下文复核等价；wake plan-ready/send的awk对带空格owner取末词，与新函数不同，保留；lock独立可运行且自身flock父子均加载入口，init独立母本安装器，新增lib依赖会扩大缺库失败面，均跳过source及替换。 B：wake优化版now_ms/sleep_ms移到lib，run/wake删定义，QWB_NOW_MS_CMD/QWB_SLEEP_CMD调用次数及参数原样；bash3.2/bash5注入输出0/10与sleep 1/1/1234逐字节一致，默认now_ms纯整数且在机器时钟前后界内；dispatch不动。 C：qwb_shell_quote接run，7种参数含单引号/空值/中文/换行与init旧实现输出和eval读回一致；init独立安装器保留。 D：watch_launch收敛投递/6次探测/pid/登记，失败文案留两入口；gate_proof收敛两次canonical身份核验，核验次数不减；跳过文案合并、lostrc去掉，取锁主sed两处复用A。 E：qwb_scenario_check读完stdin，输出ok/no-scenario/no-failure-path，lint接共享函数；run旧门保留：72字节合法场景rc0，而1019976字节同结构rc1无可识别场景，改成完整读取会违反本票唯一F行为修正的硬线。 F：qwb_task_obligations_json排除ci-并注释指向qwb-ledger.sh handoff-pending；有效已迁state=done/ci-assign夹具经真实reader校验，旧lib source=ci-fixture、新lib空，pending旧新均[]，旧status/wake列未结、新status不列且wake输出账本无未结项；claim=op-fixture/key=budget/handoff=source:ci-fixture仍列出。 G：due_create登记全局路径，创建窗口延后INT/TERM且mktemp子命令忽略信号以读回路径，重复转发信号先忽略再exit；due_cleanup并入event_cleanup，不覆盖订阅器清理；宿主关闭stdout的PIPE退出保持141并进入EXIT，排空继承flock的订阅器。once/block两个真实入口各TERM20+INT20，80次均无due残留、自建进程组live=0，rc143/130；4次旧入口对照均残留1个due、rc相同，按记录的确切路径清理。 场景1/2/3命令：python3 -B .qwb-tmp/lib-sink.NBY2in/runner.py equivalence-ship（内部equivalence.py，git archive 8d897cd导出bin/templates，全部假Herdr，固定date/strftime/op-id使写账可逐字节比较）；rc0/46 PASS，run herdr与pane-run均rc0，无场景/单user_/缺失败/1MB分别run rc1，lint前三rc1大块rc0；wake dry/once/check rc0、block到期rc124、ensure新建与原pane重启rc0/投递失败rc1/探测失败rc1；五owner输入锁status/release、block复核、send，以及锁acquire的stdout/stderr/rc/任务书/.watch/owner/Herdr调用序列一致。 场景4/5命令：python3 -B .qwb-tmp/lib-sink.NBY2in/ci-signals.py rc0/89 PASS（4义务断言+84次新旧信号+末尾汇总）；原始输出与CI旧新JSON在同目录。 其他验收：python3 -B .qwb-tmp/lib-sink.NBY2in/units.py rc0/9 PASS；bash tests/lint-scenario-stream.sh rc0/4 PASS，包含3条预期拒绝的FAIL诊断；bash bin/qwb-test.sh fast rc0且空日志无新增shellcheck告警；git diff --check通过。 各脚本行数（按wc换行）：lib457→516，run862→843，wake973→979，lint315→309，lock152→152，send58→58，init485→485。 全部提交后收尾bash bin/qwb-test.sh full：rc=1，grep -c ^PASS=795，grep -c ^FAIL=1，已用逐行统计对照，耗时839.4240905420156秒；日志本副本.qwb-tmp/lib-sink.NBY2in/full-final.log，回执full-final.rc，该串联在SMOKE失败后停止；review-identity/lint/COLLAB-ALL另以remaining.sh完整补验，未冒充全门通过。 首轮固定提交db8885c的full rc1/802 PASS/1 FAIL（lifecycle真实扩展登记），原始full.log/full.rc/full-first-lifecycle.log/full-first-summary.json保留；起点生命周期rc0/候选rc1，私有观察副本确认孤儿SIGPIPE截断EXIT且Python订阅器持锁，追加23893a9修复后原生命周期rc0/6 PASS、快门rc0、信号80次和逐字节46项重验通过，再在最终固定HEAD跑收尾全门，未改测试或阈值。 全门末尾5行各前100字符=["AssertionError: ('missed live-reader window', 2.54663758398965, \"Herdr timely subscription gap; boun", "FAIL  订阅子进程回收公开入口回归", "", "SMOKE FAIL（1 项）", "门失败（full）：bash tests/smoke.sh && bash tests/review-identity.sh && bash bin/qwb-lint.sh && bash tests"]；全门后git status --short输出=""；残留进程清单=[]（本副本路径及已记录全门进程组扫描，排除只读检查本身）；原始收尾收据final-summary.json。
blocked: 2026-10-04T10:26:14Z full-gate 未合格，STOP；最终提交=23893a918dc49b4b15e2bfb552b5865b7f9791b8（前序db8885cf62187c61289b424c5fe7efcc2329139c）。实现/五场景/跳过原因/行数/两轮全门末尾5行前100字符的详细证据见上条working。最终HEAD全门bash bin/qwb-test.sh full自然rc1，grep -c ^PASS=795、grep -c ^FAIL=1，与逐行统计一致，耗时839.4240905420156秒，日志本副本.qwb-tmp/lib-sink.NBY2in/full-final.log/full-final.rc；唯一失败为订阅回收夹具missed live-reader window（2.546638秒超过既有2秒窗口），起点和候选公开probe分别rc1/2.681520秒与rc1/3.606052秒，未降低断言或增加超时，不能冒充全门成功。被串联挡住的门已完整补跑：python3 -B .qwb-tmp/lib-sink.NBY2in/runner.py remaining 内依次bash tests/review-identity.sh、bash bin/qwb-lint.sh、bash tests/collab-all.sh，各rc0，总rc0，grep -c ^PASS=36、grep -c ^FAIL=0，默认COLLAB-ALL PASS（12项），耗时335.36071470798925秒；remaining日志末尾5行前100字符=[PASS tests/collab-test-policy.sh（181s）, PASS tests/lint-scenario-stream.sh（3s）, PASS tests/path-canonicalization.sh（0s）, COLLAB-ALL PASS（12项）, REMAINING collab-all rc=0]。最后git status --short输出为空，git diff --check通过，残留进程清单=[]，收尾收据final-summary.json；代码/证据均留本副本，未修改主账本state字段。全门仍需在能满足原夹具2秒窗口的运行环境独立复验，当前不写done行。
working: 2026-10-04T10:26:48Z 主控处置（回应 10:26:14Z 的 blocked）：收到。全门唯一的 FAIL 是第 88 节的订阅回收夹具没赶上 2 秒窗口，原因是同机另一个工人在做人为高负载验收（全机负载一度超过 140），与你的改动无关；该夹具的负载敏感性正由 audit-reap-window 修。本票你这边到此为止，不用再跑、不用再改；主控审 diff，并在 audit-reap-window 落地后于合并的 main 上跑全门作最终验收。
working: 2026-10-04T10:27:14Z 主控审 diff（返修 1）：A–G 的取舍认可（owner 含空格时语义不同的两处 awk 保留、lock 与 init 不加 lib 依赖、F 与 G 的修正及证据）。追加一项返修：你在 E 项里发现 bin/qwb-run.sh 的派发场景门对约 1MB 的合法场景块返回「无可识别场景」而拒绝派发——这是 pipefail 下 grep -q 提前退出、上游 printf 被 SIGPIPE 打断造成的假阴性，和提交 d3dd690 在 lint 里修掉的是同一个毛病，是缺陷不是既定行为。请把 run 的场景门也改成调用 qwb_scenario_check（各自的报错文案与退出码留在 run），这是本票第三处有意的行为修正：大场景块不再被误拒，其余输入的拒绝与否、文案、退出码不变。白名单相应增加 tests/lint-scenario-stream.sh，用来加一条派发侧的回归（大场景块能派发；无场景、缺失败路径照样被拒），该测试在起点提交上必须失败。改完追加提交；全门等 audit-reap-window 落地后由主控在合并的 main 上跑，你这边只需跑快门、定向等价对比与 tests/lint-scenario-stream.sh。
working: 2026-10-04T10:28:54Z 返修1开始：已完整读取主控10:27:14Z追加授权；run大场景SIGPIPE假阴性获准修正，tests/lint-scenario-stream.sh加入白名单。当前HEAD23893a9、工作区干净；先补真实派发入口回归并在起点验证红，再接run共享判定，保持拒绝文案/退出码；本轮只跑快门、定向等价与该测试，不跑全门。
working: 2026-10-04T10:35:51Z 返修1检查完成：run场景门接qwb_scenario_check，原缺块/无可识别/缺失败文案与退出码保留；新增公开dispatch回归使用隔离项目/假Herdr/死socket，核对大块派发后的冻结指纹、唯一dispatch与7次Herdr调用顺序，缺块/缺失败拒绝时任务书字节不变且无Herdr调用。起点8d897cd+最终新测试自然rc1，原因明确为大块误报无可识别场景（base-red-final.log）；修后bash tests/lint-scenario-stream.sh rc0/7 PASS（含3条预期lint拒绝FAIL诊断），fast-final.rc0无shellcheck告警；定向equivalence-final.rc0/11 PASS（10组输入及汇总），普通herdr/pane-run派发、无块/一个user/缺Given/缺失败/仅正文提失败/两user标题/错误指纹/缺指纹的stdout、stderr、rc、任务書/.watch/owner和Herdr日志逐字节一致。全部新证据在本副本.qwb-tmp/lib-sink-rework.9eQa8h/；未跑全门。
done: 2026-10-04T10:37:39Z 返修1完成 commit=e8bf6f6f386dfc1adc2c4eb574ac2d807b1aff0f（追加于23893a918dc49b4b15e2bfb552b5865b7f9791b8）；仅改bin/qwb-run.sh与新获授权tests/lint-scenario-stream.sh。run场景门统一调用qwb_scenario_check，去掉grep-q提前退出管道，缺块/无可识别/缺失败文案与rc1保留；第三处获授权行为修正为大场景块不再误拒。新增真实公开派发入口回归：约1MB合法块rc0并写正确sha1冻结指纹/唯一dispatch，假Herdr调用顺序7次；缺场景块和缺失败路径各rc1，任务书逐字节未改且无Herdr调用，死socket失效关闭保留。起点8d897cd的git archive副本运行同一份最终测试脚本rc1，原始失败=RC valid large block dispatches: 1 expected=0，stderr为验收场景块里没有可识别场景，证据base-red-final.log；测试脚本SHA与最终提交中的测试相同，排除夹具误报。修后bash tests/lint-scenario-stream.sh rc0/7 PASS，3条FAIL诊断均是预期lint负例，日志stream-green-final.log。bash bin/qwb-test.sh fast rc0，fast-final.log为0字节，无shellcheck告警。python3 -B .qwb-tmp/lib-sink-rework.9eQa8h/equivalence.py rc0/11 PASS（10组普通输入及汇总），stdout/stderr/rc/任务书/.watch/owner/Herdr调用日志逐字节一致，覆盖herdr与pane-run成功、无块、单user、缺Given、缺失败、只在正文提失败、双user标题、错误指纹和丢失指纹，日志equivalence-final.log。git diff --check通过；run843→838行，测试46→118行；最终git status --short输出为空，残留进程清单=[]。原始日志/退出码回执/收尾JSON均在本副本.qwb-tmp/lib-sink-rework.9eQa8h/。严格按主控10:27:14Z返修授权仅跑快门/定向等价/该测试，本轮未跑全门；合并main上的最终全门由主控在audit-reap-window落地后完成。未修改state字段，未建分支/push/写真Herdr。
working: 2026-10-04T10:50:55Z 主控验收（返修 1 通过）：三个提交的 diff 均已逐行审（lib 新增 qwb_lock_owner / now_ms / sleep_ms / qwb_shell_quote / qwb_scenario_check，义务判定补排除 ci-；wake 收敛四处重复并在所有退出路径清理 qwb-due 文件；run 与 lint 共用场景判定，大场景块不再被 SIGPIPE 误拒）；在副本 e8bf6f6 上独立跑 bash bin/qwb-test.sh full：rc=0、839 PASS / 0 FAIL（副本无 qwbuddy/config.sh，少 lint 的 1 行）、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、712.86s、无残留进程、工作区干净。已 ff-only 合入 main（HEAD=e8bf6f6），未 push。
