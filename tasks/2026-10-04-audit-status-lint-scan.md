# 任务书：点名与 lint 复用单遍账本扫描，去掉逐票起进程

```
任务 id:  audit-status-lint-scan
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F5、F6、F30 的 status 部分）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，magpie codex/gpt-6.1-sol high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-status-lint-scan.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-status-lint-scan（隔离副本，detached HEAD，起点 main 0b9faef）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

第 1 波已给 `bin/qwb-lib.sh` 加了 `qwb_ledger_scan`（一个 perl 进程扫完全部任务书，输出 `路径 TAB utf8ok TAB collab TAB state`），`bin/qwb-wake.sh` 的一轮扫描因此从 1269ms 降到 104ms。`bin/qwb-status.sh` 与 `bin/qwb-lint.sh` 还是老办法：

- `qwb-status.sh`（审核时实测 1981ms / 约 665 次 exec，59 个任务书）：每张票起约 13 个进程；已迁票的账本读两次；`mark` 先用 case 算一遍，又用一串不等判断重判一遍 state 合法性。
- `qwb-lint.sh`（审核时实测 3032ms / 约 1030 次 exec）：对账本跑 5 遍独立循环（第 2、7、8、9、10 项），每遍逐票起 grep/sed。

白名单：`bin/qwb-status.sh`、`bin/qwb-lint.sh`、`bin/qwb-lib.sh`（只许新增函数或给 `qwb_ledger_scan` 增加**向后兼容**的输出能力；`bin/qwb-wake.sh` 正在用它现有的四列输出，不得改变）。

### 工程规格

**每一项单独做、单独自检；不能确认输出逐字节不变的就跳过并写明原因。**

1. **status**：未结/已结判定与 state 读取改用单遍扫描的结果；已迁票的 `qwb-ledger.sh read` 结果在「未结义务」与「明细」之间共用，每张已迁票每次点名只读一次；`mark` 的双重判定合并成一次（参考审核报告 F30 给的写法，但以输出逐字节不变为准）。
2. **lint 第 2 项**（state 合法性与 UTF-8）：改用单遍扫描的结果。
3. **lint 第 8、9、10 项**：先用一次 `grep -l`（或一次 perl）在整个 `tasks/` 上筛出命中的文件，再只对命中的文件做原来的细查。第 10 项的 80 字符截断（第 1 波刚加的）保持原样。
4. **lint 第 7 项**（场景块与指纹）：与派发门共用判定逻辑，本票不动。
5. 若需要「每张票最后一条状态行」「最后一条规格疑点事件」这类额外信息，可在 lib 里另加一个扫描函数，或给 `qwb_ledger_scan` 加一个显式开关来追加列；默认调用的输出必须与现在逐字节相同。
6. 不改任何输出文案、顺序、退出码；stderr 警告的内容与出现顺序也不变。

## 1. 验收场景

### user_正常路径_真账本上输出逐字节不变

Given 起点提交的 `bin/`（用 git archive 导出到自己的临时目录）与改后的 `bin/`
When  分别对主仓 `/Users/rocky/projects/qonnwolfbuddy` 以只读方式跑 `qwb-status.sh --project` 与 `qwb-lint.sh --project`（先确认这两个命令在该用法下不写任何文件；`qwb-ledger.sh read` 会在已迁票旁建侧车锁，主仓目前没有已迁票）
Then  两个命令的 stdout、stderr、退出码新旧逐字节相同

### user_正常路径_夹具账本覆盖各种票

Given 一组临时账本夹具：五种合法 state 各一张、非法 state、空 state、带多余空白与 CRLF、重复 state 行、无 state 行的普通文档、含非法 UTF-8 字节、带规格疑点未决与已处置、带占位状态行、带 review-required 与审核身份行、带 scenarios-fp 且场景被改与未改、文件名含中文与空格；另含至少两张已迁票（用仓库现有测试里造已迁票的办法造）
When  新旧各跑 status 与 lint
Then  stdout、stderr、退出码逐字节相同

### user_失败路径_坏账本仍被点名并判失败

Given 含非法 UTF-8 的票、非法 state 的票、场景被改的票
When  跑改后的 status 与 lint
Then  status 仍把前两者列为未结并带原有的提示文字；lint 仍以非 0 退出并逐项报 FAIL，文案与旧版相同——不得因为换了扫描方式而漏报或静默跳过

### user_失败路径_已迁票读账失败时不吞错

Given 一张协作区被故意写坏的已迁票
When  跑改后的 status 与 lint
Then  与旧版行为相同（status 按未结并提示、lint 第 9 项 FAIL），且该票只被读账一次这件事不影响结果

### user_正常路径_明显变快

Given 主仓真账本
When  新旧 status 与 lint 各跑 7 次取最小值
Then  报出四个数字；status 与 lint 都不慢于旧版，并说明各自省掉了多少次 exec（可用 PATH 垫片统计）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；对主仓只许跑上面写明的只读命令。
- **绝对不许对真 Herdr 做任何写操作**；`qwb-status.sh` 末尾会做 herdr 只读查询，对比新旧输出时那一段会随现场变化，比较前把它切掉或在隔离环境（死路径 `HERDR_SOCKET_PATH`）里跑，并写明你怎么处理的。
- 临时文件只许删除自己建出并记在变量里的确切路径；禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 的进程。
- git：只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。status 与 lint 分成两个提交。
- 兼容 `/bin/bash` 3.2；perl 只用系统自带模块。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点全门是 831 PASS / 0 FAIL。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `bin/qwb-wake.sh`、`bin/qwb-herdr.sh`（另一张票正在改它们）与 `tests/`。
- 不加缓存、不加增量索引、不改 lint 的检查规则。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T04:24:03Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（默认 magpie codex/gpt-6.1-sol high） agent=qwb-audit-status-lint-scan pane=w14Z:p9 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-status-lint-scan base=0b9faef
working: 2026-10-04T04:25:13Z 执行者完成规格与调用链核对；status/lint 无写账路径，已迁 read 会创建侧车锁；主仓对照将先确认无迁移标记并使用死 HERDR_SOCKET_PATH。第7项不改，默认扫描四列不改。
working: 2026-10-04T04:30:19Z status 阶段完成，commit=098c405；/bin/bash 新旧 main/fixture status stdout/stderr/rc 逐字节一致（main rc0，fixture rc0且坏协作stderr68字节）；三张已迁票 reader 次数旧6新3；bash bin/qwb-test.sh fast rc0，无新增shellcheck告警。验证脚本与原始输出=/tmp/qwb-audit-status-lint.towwI6me/。
working: 2026-10-04T04:31:50Z lint 第2项单独自检完成：--all 扫描包含无state文档，默认四列不变；python3 /tmp/qwb-audit-status-lint.towwI6me/verify.py compare rc0（main status/lint rc0，fixture status rc0/lint rc1，stdout/stderr/rc均逐字节一致）；bash bin/qwb-test.sh fast rc0。
working: 2026-10-04T04:32:30Z lint 第8项单独自检完成：一次grep -lE筛出review-required，再保留原身份细查；main/fixture新旧stdout/stderr/rc逐字节一致，verify.py compare rc0。
working: 2026-10-04T04:33:06Z lint 第9项单独自检完成：一次grep -l筛出协作标记，再保留原reader检查；main/fixture新旧stdout/stderr/rc逐字节一致，坏协作票lint仍FAIL，verify.py compare rc0。
working: 2026-10-04T04:33:42Z lint 第10项单独自检完成：一次grep -lE筛占位状态行，原逐文件grep与Unicode80字符截断逐字保持；main/fixture新旧stdout/stderr/rc逐字节一致（长中文占位行含省略号），verify.py compare rc0；bash bin/qwb-test.sh fast rc0。第7项代码未动。
working: 2026-10-04T04:38:29Z lint 阶段完成，默认scan四列与起点逐字节一致，第7项源码逐字节一致；空/缺tasks与directory.md兼容通过；fast rc0，lint独立提交完成。性能7次最小：status旧2408.619ms新883.058ms，lint旧4085.071ms新1832.106ms；PATH统计status811到383（省428），lint1249到632（省617）。计时首次工具60秒截止，仅补齐已完成6次之后第7次lint，原日志保留；将对最终提交启动一次full。
working: 2026-10-04T04:39:04Z 最终提交ce2d235f093142489ad067e5cceb9bf928d767b5已冻结；全门bash bin/qwb-test.sh full后台执行中，日志=/tmp/qwb-audit-status-lint.towwI6me/full.log，退出回执=full.exit，根PID保存于full.pid，HERDR_SOCKET_PATH为/dev/null/qwb-audit-status-lint.sock。
working: 2026-10-04T04:41:30Z 工作目录全门已见AF_UNIX path too long（离线socket路径超过Darwin103字节），仍等待完整退出回执；将使用最终commit的git archive短路径导出=/tmp/qwb-audit-status-lint.towwI6me/candidate补验，白名单源码已逐字节核对，无改tests/断言。原日志保留并与补验分开报告。
working: 2026-10-04T04:46:08Z 工作目录原full结束rc1，784条PASS/10条FAIL，SMOKE FAIL（10项）；首因socket路径105字节超过Darwin103字节，原日志full.log/full.exit完整保留。短路径89字节的最终commit导出补验已启动，根PID=30032，日志full-short.log，回执full-short.exit；仍执行同一bash bin/qwb-test.sh full，不改任何代码或断言。
done: 2026-10-04T04:59:02Z 执行者 全部实现与补验完成；final=ce2d235f093142489ad067e5cceb9bf928d767b5，status提交=098c40547abdc6143e981339a6ea61d829a63b31，lint提交=ce2d235f093142489ad067e5cceb9bf928d767b5；仅白名单3文件，detached HEAD，不建分支/不push；默认qwb_ledger_scan四列与旧版逐字节一致，lint第7项源码未动，80字符截断未动。bash bin/qwb-test.sh fast退出码0、无新增shellcheck告警；git diff --check退出码0；证据目录=/private/tmp/qwb-audit-status-lint.towwI6me。
done: 2026-10-04T04:59:02Z 执行者 场景1 command=/bin/bash /private/tmp/qwb-audit-status-lint.towwI6me/old/bin/qwb-status.sh --project /Users/rocky/projects/qonnwolfbuddy 与 /bin/bash /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-status-lint-scan/bin/qwb-status.sh --project 同根；lint同型两命令；验证 python3 /private/tmp/qwb-audit-status-lint.towwI6me/scenes.py 1；原始核验结果=真账本 status: rc=0 stdout=51223 bytes stderr=0 bytes 新旧相同 | 真账本 lint: rc=0 stdout=1180 bytes stderr=7481 bytes 新旧相同 | SCENE 1 PASS；scene日志=/private/tmp/qwb-audit-status-lint.towwI6me/scene-1.log。 已先确认主仓无协作标记/模式记录，两命令不创建侧车或写账；Herdr全段采用死HERDR_SOCKET_PATH=/dev/null/qwb-audit-status-lint.sock隔离，未碰真Herdr。完整stdout/stderr/rc原件=main-status-old/new.*、main-lint-old/new.*。
done: 2026-10-04T04:59:02Z 执行者 场景2 command=python3 /private/tmp/qwb-audit-status-lint.towwI6me/verify.py prepare；/bin/bash 新旧qwb-status.sh/qwb-lint.sh --project /private/tmp/qwb-audit-status-lint.towwI6me/fixture；python3 /private/tmp/qwb-audit-status-lint.towwI6me/scenes.py 2；原始核验结果=综合夹具 status: rc=0 stdout=2808 bytes stderr=68 bytes 新旧相同 | 综合夹具 lint: rc=1 stdout=1582 bytes stderr=576 bytes 新旧相同 | SCENE 2 PASS；scene日志=/private/tmp/qwb-audit-status-lint.towwI6me/scene-2.log。 夹具覆盖五合法值、非法/空值、空白与CRLF、重复state、普通文档及无state坏UTF8、中文空格文件名、疑点未决/处置、占位长行、审核身份、冻结/改动场景、三张已迁票；完整原件=fixture-status-old/new.*、fixture-lint-old/new.*。
done: 2026-10-04T04:59:02Z 执行者 场景3 command=/bin/bash 新旧qwb-status.sh/qwb-lint.sh --project /private/tmp/qwb-audit-status-lint.towwI6me/fixture；python3 /private/tmp/qwb-audit-status-lint.towwI6me/scenes.py 3；原始核验结果=[未结] 07-bad-utf8.md                           state=verified —— 账本 UTF-8 损坏，须主控查看 | [未结] 02-invalid.md                            state=mystery —— 状态异常，须主控查看 | lint rc=1；非法UTF-8、非法state、场景被改三项均原文FAIL | SCENE 3 PASS；scene日志=/private/tmp/qwb-audit-status-lint.towwI6me/scene-3.log。
done: 2026-10-04T04:59:02Z 执行者 场景4 command=/bin/bash 新旧qwb-status.sh/qwb-lint.sh --project /private/tmp/qwb-audit-status-lint.towwI6me/fixture；python3 /private/tmp/qwb-audit-status-lint.towwI6me/count_exec.py reads；python3 /private/tmp/qwb-audit-status-lint.towwI6me/scenes.py 4；原始核验结果=[未结] 20-migrated-corrupt.md                   state=done |        [未结] 协作区损坏/未知，须主控对账 | status stderr: 账本拒绝：schema版本非法 | 账本拒绝：schema版本非法 | lint rc=1 第9项原文FAIL；status三张已迁票旧各读2次、新各读1次（含坏票） | SCENE 4 PASS；scene日志=/private/tmp/qwb-audit-status-lint.towwI6me/scene-4.log。
done: 2026-10-04T04:59:02Z 执行者 场景5 command=python3 /private/tmp/qwb-audit-status-lint.towwI6me/benchmark.py（原工具60秒截止，已完成status各7次/lint各6次）；python3 /private/tmp/qwb-audit-status-lint.towwI6me/benchmark-resume.py（只补第7次lint，各rc0）；python3 /private/tmp/qwb-audit-status-lint.towwI6me/count_exec.py main；python3 /private/tmp/qwb-audit-status-lint.towwI6me/scenes.py 5；原始核验结果=status 7次最小: old=2408.619ms new=883.058ms | lint 7次最小: old=4085.071ms new=1832.106ms | status old rc 0 execs 811 by-command {'dirname': 5, 'grep': 371, 'basename': 62, 'sed': 61, 'head': 61, 'tr': 61, 'perl': 61, 'tail': 125, 'bash': 1, 'cat': 1, 'herdr': 2} ledger-read-count 0 | status new rc 0 execs 383 by-command {'dirname': 5, 'perl': 1, 'grep': 247, 'tail': 125, 'bash': 1, 'basename': 1, 'cat': 1, 'herdr': 2} ledger-read-count 0 | lint old rc 0 execs 1249 by-command {'dirname': 1, 'grep': 649, 'sort': 1, 'tr': 123, 'wc': 1, 'perl': 125, 'sed': 125, 'head': 122, 'basename': 2, 'awk': 25, 'cut': 25, 'shasum': 25, 'tail': 25} ledger-read-count 0 | lint new rc 0 execs 632 by-command {'dirname': 1, 'grep': 318, 'sort': 1, 'wc': 1, 'tr': 62, 'perl': 22, 'sed': 64, 'head': 61, 'basename': 2, 'awk': 25, 'shasum': 25, 'cut': 25, 'tail': 25} ledger-read-count 0 | SCENE 5 PASS；scene日志=/private/tmp/qwb-audit-status-lint.towwI6me/scene-5.log。 计数为PATH垫片捕获的外部调用（不含bash内建/进程替换fork）；status少428次，lint少617次；原始7次样本=benchmark.log/benchmark-resume.log/benchmark.json。
done: 2026-10-04T04:59:02Z 执行者 全门原工作目录 command=cd /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-status-lint-scan 后 bash bin/qwb-test.sh full > /private/tmp/qwb-audit-status-lint.towwI6me/full.log 2>&1；实际退出码1、PASS行784、FAIL行10，首因夹具AF_UNIX路径105字节超过Darwin103字节，不把原失败报绿；末尾5行各前100字符=["PASS  102 条警告保留且按 80 个字符截断，UTF-8 与短行原文不变", "PASS  第 51 节同型断言连续 20 次全部通过", "", "SMOKE FAIL（10 项）", "门失败（full）：bash tests/smoke.sh && bash tests/review-identity.sh && bash bin/qwb-lint.sh && bash tests"]；回执=/private/tmp/qwb-audit-status-lint.towwI6me/full.exit。
done: 2026-10-04T04:59:02Z 执行者 全门补验 command=git archive ce2d235f093142489ad067e5cceb9bf928d767b5 导出 /private/tmp/qwb-audit-status-lint.towwI6me/candidate，cd导出目录后 bash bin/qwb-test.sh full > /private/tmp/qwb-audit-status-lint.towwI6me/full-short.log 2>&1；实际退出码0、PASS行830、FAIL行0、COLLAB-ALL PASS（11 项）；233个跟踪文件补验前后均与最终提交逐字节一致，未改tests/断言；比票中主仓基线831少1仅因导出无qwbuddy/config.sh，既有条件第3项双配置检查不适用且不输出，主仓对照已包含并通过该项；末尾5行各前100字符=["PASS  tests/collab-roles.sh（60s）", "PASS  tests/collab-test-policy.sh（84s）", "PASS  tests/lint-scenario-stream.sh（1s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"]；回执=/private/tmp/qwb-audit-status-lint.towwI6me/full-short.exit；全门后git status --short原始输出=""（空、clean）；summary=/private/tmp/qwb-audit-status-lint.towwI6me/summary.json；final=ce2d235f093142489ad067e5cceb9bf928d767b5。
working: 2026-10-04T05:03:44Z 主控验收（返修 1）：独立对比新旧 qwb-status.sh / qwb-lint.sh 于主仓真账本（死路径 HERDR_SOCKET_PATH 下）：stdout、stderr 逐字节相同、rc=0；diff 已逐行审。一处须返修：bin/qwb-lib.sh 新增的 qwb_task_obligations_json 把 qwb_task_obligations 里那段「未结义务」perl 原样又抄了一份——这条规则此前已经因为多处实现漂移过一次（审核报告 F15），不能再多一份。请让 qwb_task_obligations 改为「判协作区标记 → 读账 → 把 JSON 交给 qwb_task_obligations_json」，规则在 lib 里只留一处；qwb_task_obligations 的对外行为（含读账失败时输出 protocol-unknown、无标记时空输出）必须逐字节不变，并用已迁票夹具对比新旧证明。另：你报的「深路径副本里 AF_UNIX 路径超 103 字节致全门 10 项 FAIL」已另开 audit-socket-path 处理，不在本票范围。
working: 2026-10-04T05:04:26Z 执行者开始返修1：按主控最新授权修改qwb_task_obligations调用共享JSON判定函数，取消重复规则；将以已迁票比较stdout/stderr/rc及protocol-unknown/无标记分支，再追加提交并仅在短路径固定导出跑全门。
working: 2026-10-04T05:07:04Z 返修1规则合并与定向自检完成：仅lib 1行新增/14行删除，qwb_task_obligations保留标记检测/reader/失败protocol-unknown，改为调用qwb_task_obligations_json；JSON规则只留一处且其源码未改。python3 /tmp/qwb-sl-r1.QqOQp8VM/verify-obligations.py rc0，/bin/bash及Homebrew Bash各4票（2张合法已迁票、1张坏协议已迁票、1张无标记票）stdout/stderr/rc逐字节相同；fast rc0，diff --check rc0。原件=/tmp/qwb-sl-r1.QqOQp8VM/obligations.log与obligations-results.json；已追加提交，下一阶段短路径全门。
working: 2026-10-04T05:07:32Z 返修1全门执行中：固定提交3ead225f8a602fce2a61052470a83ba342ccfab5的短路径git archive导出=/tmp/qwb-sl-r1.QqOQp8VM/candidate，执行bash bin/qwb-test.sh full；root_pid=51833，日志=/tmp/qwb-sl-r1.QqOQp8VM/full.log，实际退出回执=full.exit；死Herdr socket隔离，未处理另票深路径问题。
done: 2026-10-04T05:18:55Z 执行者返修1完成，final=3ead225f8a602fce2a61052470a83ba342ccfab5；追加提交Reuse shared JSON obligation rules，仅bin/qwb-lib.sh改动（1行新增/14行删除）；qwb_task_obligations保留原标记检测、reader和读账失败protocol-unknown分支，JSON交给qwb_task_obligations_json；规则只留一处，共享JSON函数源码逐字节未改。bash bin/qwb-test.sh fast退出码0且无shellcheck告警，git diff --check退出码0。
done: 2026-10-04T05:18:55Z 返修1定向证明 command=python3 /private/tmp/qwb-sl-r1.QqOQp8VM/verify-obligations.py（旧lib来自git archive ce2d235f093142489ad067e5cceb9bf928d767b5，真迁移夹具含2张合法票、1张坏协议票，另含1张无标记票）；/bin/bash及/opt/homebrew/bin/bash各4组、共8组stdout/stderr/rc逐字节一致，每组rc0；未结票原claim/key/source完整保留，已释放票无claim，坏协议票stdout逐字为protocol-unknown（无尾换行）、stderr逐字为账本拒绝：schema版本非法及尾换行，无标记票stdout/stderr均空。原件=/private/tmp/qwb-sl-r1.QqOQp8VM/obligations.log及obligations-results.json，各组stdout/stderr/rc分开保存在同目录。
done: 2026-10-04T05:18:55Z 返修1全门 command=git archive 3ead225f8a602fce2a61052470a83ba342ccfab5 导出 /private/tmp/qwb-sl-r1.QqOQp8VM/candidate，cd导出目录后 bash bin/qwb-test.sh full > /private/tmp/qwb-sl-r1.QqOQp8VM/full.log 2>&1；退出码=0、PASS行数=830、FAIL行数=0、COLLAB-ALL PASS（11项）；233个跟踪文件导出前后均与固定提交逐字节一致；830与票中主仓831的差异仍是导出没有qwbuddy/config.sh，第3项双配置检查按原规则不适用，本轮未改任何测试或深路径socket逻辑。退出回执=/private/tmp/qwb-sl-r1.QqOQp8VM/full.exit，末尾5行各前100字符=["PASS  tests/collab-roles.sh（62s）", "PASS  tests/collab-test-policy.sh（86s）", "PASS  tests/lint-scenario-stream.sh（2s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"]；全门后git status --short原始输出=""（空、clean）；summary=/private/tmp/qwb-sl-r1.QqOQp8VM/summary.json；final=3ead225f8a602fce2a61052470a83ba342ccfab5。
working: 2026-10-04T05:33:45Z 主控验收（返修 1 通过）：返修 diff 已审（qwb_task_obligations 改为调用 qwb_task_obligations_json，未结义务规则在 lib 只留一处）；新旧背靠背对比 qwb-status.sh、qwb-lint.sh、qwb-wake.sh --dry-run --once 于主仓真账本：stdout、stderr、退出码一致；把 3ead225 用 git archive 导出到仓库内短路径 .qwb-tmp/v1 独立跑 bash bin/qwb-test.sh full：rc=0、830 PASS / 0 FAIL（导出无 qwbuddy/config.sh，少 lint 第 3 项的 1 行，与主仓 831 等价）、COLLAB-ALL PASS（11 项）、无残留进程，734.83s（负载约 8）。已 ff-only 合入 main（HEAD=3ead225），未 push。
