# 任务书：收尾在真 Herdr 上的两处断点——「没有 agent」的认法与被拒后的出路

```
任务 id:  audit-finish-real
state: verified
implementation-authorized: Rocky 2026-10-04「好，继续推进」「还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     2026-10-04 主控在独立 named Herdr 会话里做的三轮真机演练（Herdr 0.9.3，devin 工人）与同日 Claude Code 主控真机验收的会话记录
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-finish-real.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real（隔离副本，detached HEAD，基点 d3e4b49）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：本仓是他之后所有项目的初始化脚本，收尾这条路在真环境里必须走得通，被拒时主控要知道下一步该做什么。

### 真机证据（主控亲测，不是推测）

**证据一：真 Herdr 对没有 agent 的 pane 不返回 `agent` 字段。** Herdr 0.9.3 的 `herdr pane get` 对一个普通 shell pane 的应答是：

```
{"id":"cli:pane:get","result":{"pane":{"agent_status":"unknown","cwd":"…","focused":false,"foreground_cwd":"…","label":"…","pane_id":"w8Z:pBG","revision":0,"scroll":{…},"tab_id":"w8Z:t95","terminal_id":"term_…","workspace_id":"w8Z"},"type":"pane_info"}}
```

没有 `agent` 键（有 agent 的 pane 才有 `agent`、`agent_session` 等键）。而产品里有四处要求这个键**存在且为 null**：

- `bin/qwb-worktree.sh` 的 `land_writers_stopped`（perl：`exists($p->{agent}) && !defined($p->{agent})`）
- `bin/qwb-worktree.sh` 的 Space 关闭前检查里 land 分支（同一句 perl）
- `bin/qwb-worktree.sh` 的 `writers_stopped` 兑底分支（python：`'agent' in info` 再 `info['agent'] is None`）
- `bin/qwb-herdr.sh` 的 `close` 兑底分支（同样的 python 写法）

所有假 Herdr 夹具返回的都是 `"agent": null`，所以测试全绿。真机演练结果：工人退出回到 shell、pane 还在、shell 已 `cd` 出副本后，`finish drill --merged --writer-proof-missing=原因` 被拒，报「缺PID兑底：pane w2:p1 身份未知」。也就是说 pane 还在的这条兑底路径在真机上永远走不通；两处 land 判定按代码读同样永远拒绝（land 未做真机演练，这一句是读代码得出的）。只有 pane 已不存在的那条路在真机上通过了。

**证据二：默认收尾被拒后，产品没有告诉主控出路。** 工人干完活停在自己的界面里时，它的进程 cwd 就在副本目录里，`finish --merged` 一律报「拒绝：候选写入者仍持cwd/FD，保留成果」。这个拒绝本身是对的（idle/done 不等于已停）。问题是拒绝信息、`QWBUDDY.md`、主控角色说明都没写怎么办。同日 Claude Code 主控真机验收里，主控被拒两次，自己翻源码、试 `/exit`、再把工人 shell `cd` 出副本才收尾成功——换个弱一点的主控就卡死在这里。

主控真机验证过的通用出路：**关闭工人所在的 pane**（`herdr pane close 工人pane`）后，不带任何兑底参数的 `finish --merged` 直接成功（证据带 PID，进程随 pane 关闭而死；该 pane 是 Space 唯一的 pane 时 Space 一并消失，收尾照常完成）。它不依赖具体工人 CLI 的退出命令。

### 主控裁决

1. 四处统一改为：`agent` 键**不存在或为 null** 都算「没有 agent」。其余身份核对一项不松。
2. 「候选写入者仍持cwd/FD」这条拒绝保留原判定、原首行，另加一行提示，指出是谁占着、怎么解。
3. 两份模板补上「收尾前先让工人退出」的做法。

白名单：`bin/qwb-worktree.sh`、`bin/qwb-herdr.sh`（只动 `close` 兑底分支里认「没有 agent」的那两行）、`templates/QWBUDDY.md` 与 `templates/roles/主控.md`（各加一两句）、`tests/` 下为验收所需的已接入文件。

### 工程规格

1. **「没有 agent」的统一认法**：pane 应答里 `agent` 键不存在，或值为 null → 没有 agent。值是非空字符串 → 仍有 agent，沿用各处现有的拒绝文案。值是其他形态（空字符串、数字、数组、对象、布尔）→ 身份未知，拒绝。四处都按这一条；两句相同的 perl 合成一个函数，python 两处各自就地改，不为此新建跨文件的公共模块。
2. **其余核对不动**：应答须是合法 JSON、无 error、stderr 为空、`result.pane` 是对象、`pane_id` 与所查的 pane 相同；「没有 agent」之后仍须通过现有的前台空闲 shell 判定（`foreground_is_shell` 或 `activity` 探针）。这些任何一项不满足，结论与现在相同。
3. **拒绝提示**：`writers_stopped` 因资源探针非空而拒绝时，stderr 首行仍是 `拒绝：候选写入者仍持cwd/FD，保留成果`（逐字节不变），其后追加一行以 `提示：` 开头的说明，内容包含：
   - 占着副本的进程，写成 `PID(命令名)`，来自这次 `lsof` 已经拿到的输出，不另起查询；最多列 5 个，超出写「等 N 个」。
   - 出路：确认工人已交付、不再需要它的会话后，关闭本票登记的工人 pane 再重试，并给出可直接复制的命令 `herdr pane close 某pane`，pane 取自本票的 `dispatch:` 行；有多个就逐个列出。
   - 本票没有任何登记的工人 pane 时，只列进程，并写「让这些进程退出或离开副本目录后重试」。
   退出码、Git、Space、任务书都与现在相同，不因提示而多做任何动作。`bin/qwb-herdr.sh close` 那一层的同名拒绝不加提示。
4. **模板**：`templates/QWBUDDY.md` §7「收·成功」附近与 `templates/roles/主控.md` 各加一两句：收尾前工人必须已经退出，且没有进程占着副本目录；agent 显示 idle 或 done 不算退出；验收通过后关闭工人 pane（`herdr pane close`）是不依赖具体工人 CLI 的通用做法；被拒时照 `提示：` 行处理。写法、密度照这两份文件现有的句子，不另起小节。
5. 除上述两点外，所有路径在假 Herdr 返回 `"agent": null` 时的 stdout、stderr、退出码、任务书记账行逐字节不变。

## 1. 验收场景

### user_正常路径_真机形态的应答被认作没有agent

Given 假 Herdr 对已回到空闲 shell 的工人 pane 返回不带 `agent` 键的应答（与上面真机应答同形），其余证据齐全
When  分别走四处判定：`writer-proof-missing` 兑底的 `finish --merged`（经 `writers_stopped` 与 `close` 两层）、land 收尾的两处
Then  四处都放行，结果与返回 `"agent": null` 时逐字节相同

### user_失败路径_仍有agent或形态不明照旧拒绝

Given 同样的 pane，应答里 `agent` 分别是非空字符串、空字符串、数字、数组、对象
When  走同样四处判定
Then  非空字符串按现有「仍有 agent／尚未退出」文案拒绝；其余形态按身份未知拒绝；Git、Space、任务书都没动

### user_失败路径_没有agent但前台不是shell照旧拒绝

Given 应答不带 `agent` 键，但前台进程组不是 shell，或进程信息查询失败
When  走同样四处判定
Then  都拒绝，文案与现在相同——少了这个键不等于工人已停

### user_失败路径_占着副本时拒绝并给出可执行的出路

Given 一张已派发、已合入的票，有一个真实启动的子进程把副本目录当作 cwd（测完按 PID 回收）；票里登记了一个工人 pane
When  不带任何兑底参数跑 `finish 票 --merged`
Then  退出码非 0；stderr 首行逐字节是 `拒绝：候选写入者仍持cwd/FD，保留成果`；第二行以 `提示：` 开头，含那个子进程的 PID 与 `herdr pane close` 加登记的 pane；副本、分支、Space、任务书原样

### user_失败路径_没有登记pane时提示不编造命令

Given 同样有进程占着副本，但票里没有任何 `dispatch:` 行可取 pane
When  跑 `finish 票 --merged`
Then  首行相同；提示行只列进程并写让它们退出或离开副本目录，不出现 `herdr pane close`

### user_正常路径_其余既有行为逐字节不变

Given 起点提交 d3e4b49 与改后的两个脚本
When  对现有收尾对比用例（正常收尾、归档、工人在忙、查询失败、根 tab 缺失兑底、缺 PID 兑底、中断续做）在假 Herdr 返回 `"agent": null` 时各跑一遍
Then  除「占着副本」那一种多出提示行之外，stdout、stderr、退出码、任务书记账行、git 与假 Herdr 调用日志新旧逐一相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何操作，读也不要读**；不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机验收由主控在独立会话里做。
- 这是删除前的安全判定：只放宽「键不存在」这一种形态，其余输入的结论不变；拿不准的一律拒绝。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件（`tests/collab-all.sh` 启动前会自检每个测试文件都有入口）。
- 测试里的活进程用自己真实启动的子进程，记下 PID，测完逐个回收；不替换系统的 `/bin/ps` 与 `lsof`。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在 d3e4b49 之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条控制在 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 六个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改派发流程（`bin/qwb-run.sh`）、不改 `activity` 探针与 `ended` 的判定、不改资源探针的判定本身（它该拒绝的照旧拒绝）、不让 `finish` 自己去关工人的 pane 或杀进程。
- 不改 `tests/e2e-real.*`；不碰真 Herdr；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T17:45:53Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-finish-real pane=w14Z:pR dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real base=d3e4b49
working: 2026-10-04T17:46:36Z 已完整读取规格与两份模板；确认基点 d3e4b49、detached HEAD 且工作区干净，开始追踪四处身份判定与已接入夹具。
working: 2026-10-04T17:53:25Z 四处判定、资源占用提示与模板已实现；快门 bash bin/qwb-test.sh fast rc=0。已扩展现有 collab-herdr/collab-land，正在校准新夹具并验证 d3e4b49 字节对照；日志位于本副本 .qwb-tmp/audit-finish-real-logs/。
working: 2026-10-04T18:04:49Z 六场景定向验收完成：bash tests/collab-herdr.sh writer-proof-missing rc=0；bash tests/collab-land.sh agent-shapes rc=0（PASS=34 FAIL=0）；d3e4b49/null/缺键字节对照与真实 cwd 进程提示均通过，快门 rc=0。原始输出：本副本 .qwb-tmp/audit-finish-real-logs/herdr-final.log、land-final.log、fast-final.log；开始提交及提交后全门。
working: 2026-10-04T18:05:12Z 已提交 4649b96；提交后 bash bin/qwb-test.sh full 执行中，原始输出为本副本 .qwb-tmp/audit-finish-real-logs/full.log，退出回执 full.rc、监督进程 full.pid；定向 herdr-final PASS=54 FAIL=0。
working: 2026-10-04T18:11:42Z 首次全门的 collab-land 子门 rc=1，已复现新矩阵复用临时项目污染原有“尚无land”状态断言；原断言保留，新矩阵改用独立受监督项目并仍由默认入口调用。只修改本票测试文件；重新验证默认 collab-land 入口。失败原文：本副本 .qwb-tmp/audit-finish-real-logs/first-full-land-failure.log。
working: 2026-10-04T18:22:49Z 首次全门 rc=1 PASS=856 FAIL=3（原文 full.log）；land 默认入口隔离后 rc=0。中断清理已独立复现并定位 boundary-readiness 临时目录越出已登记 scope，诊断原文 cleanup-current-diagnostic.log；仅把该已接入夹具的 TMPDIR 改为原监督 scope，未放松断言/进程/socket 守卫。已追加测试修复提交，开始独立中断清理复验与最终候选全门。
working: 2026-10-04T18:24:37Z 最终候选 a0f4b7fd59f0b642ed9d8414d36617648dec4ae0；fast rc=0，land 默认入口 rc=0 PASS=43 FAIL=0，中断清理独立复验 rc=0（含正常/TERM，无进程、目录、字节码残留）。提交后最终全门执行中，原始输出 full-final.log，退出回执 full-final.rc，均在本副本 .qwb-tmp/audit-finish-real-logs/；git status --short 为空。
working: 2026-10-04T18:35:31Z 第二次全门中断清理子门仍 rc=1，原文 final-full-cleanup-failure.log；同时确认 optional-routing 与 worktree-space 的临时根也绕出既有 scope，已同类最小修正，并仅增强原残留断言的目录详情。快门 rc=0，追加提交后独立复验中断门；产品实现仍为首个提交，原进程登记、失效关闭与 socket 几何均保留。
working: 2026-10-04T18:47:04Z 残留已进一步定位为监督夹具创建 groups/socket-directories 后、安装信号处理前的初始化窗口；保留原登记/排空/socket协议，初始化信号延迟至目录/PID交接完成。确定性真 TERM：d3e4b49 原始 rc=-15 且留记录目录，新版 rc=143、不启动工人、目录为空；已接入 process-fixture-check rc=0，快门 rc=0。原文 fixture-setup-red.log、fixture-setup-green.log；追加提交后复验中断门。
working: 2026-10-04T18:52:33Z 第二次全门 rc=1，仅中断清理失败，其余14个协议子门（含长路径socket）通过；初始化交接修复后 process-fixture-check 与 process-entry-cleanup 独立复验 rc=0。固定候选 ccb5419，fast rc=0，git status --short 为空；提交后完整全门执行中，原始输出 full-complete.log、回执 full-complete.rc，均在本副本 .qwb-tmp/audit-finish-real-logs/。
done: 2026-10-04T19:13:25Z 场景1通过：bash tests/collab-herdr.sh 与 bash tests/collab-land.sh（当前完整全门内均 rc=0）；缺 agent 键与 null 经 finish 两层和 land 两处全部放行，stdout/stderr/退出码/账本/Git/Herdr 调用按 d3e4b49 逐字节一致。原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log、land-complete.log。
done: 2026-10-04T19:13:25Z 场景2通过：bash tests/collab-herdr.sh、bash tests/collab-land.sh；非空字符串（含数字开头字符串）保持仍有agent/尚未退出拒绝，空串/数字/数组/对象/布尔按身份未知拒绝；Git、Space、票原样。原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log、land-complete.log。
done: 2026-10-04T19:13:25Z 场景3通过：bash tests/collab-herdr.sh、bash tests/collab-land.sh；缺键但前台非shell或process-info失败，四处照旧拒绝；补验坏JSON、error、stderr、错pane_id及非对象pane均拒绝。原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log、land-complete.log。
done: 2026-10-04T19:13:25Z 场景4通过：bash tests/collab-herdr.sh；真实子进程 cwd 占用时 rc非0，首行逐字不变，提示含真实PID(命令名)、本票登记pane关闭命令和交付/会话条件；6个进程仅列5个并写等6个，多pane逐个列出；原Git/Space/票不变，子进程均回收。原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log。
done: 2026-10-04T19:13:25Z 场景5通过：bash tests/collab-herdr.sh；无dispatch登记pane的真实cwd占用，首行不变，只列PID(命令名)并提示让进程退出或离开副本后重试，没有herdr pane close；Git/Space/票不变。原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log。
done: 2026-10-04T19:13:25Z 场景6通过：bash tests/collab-herdr.sh（原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/herdr-complete.log）；d3e4b49/new逐项核正常、归档、旧代活着、忙碌、查询/关闭失败、根tab兑底、缺PID兑底、删除中断恢复；stdout/stderr/退出码/账本/Git/Herdr日志/ref/目录一致，仅资源占用追加提示行。两份模板已补收尾前退出与关闭pane的通用做法。
done: 2026-10-04T19:13:25Z 全部完成，commit=ccb5419d353e6dec8ce60d98e4d8d4080dc0e182；bash bin/qwb-test.sh fast rc=0（无新增shellcheck告警）；提交后 bash bin/qwb-test.sh full rc=0 PASS=843 FAIL=0，15个协议子门全过。完整原文 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-finish-real/.qwb-tmp/audit-finish-real-logs/full-complete.log、full-complete.rc；git status --short 输出为空（status-short.log）；残留测试进程=[]，额外临时目录/socket/字节码=[]（residuals.log，执行者祖先已排除），仅留审计日志。
working: 2026-10-04T19:14:40Z 收尾范围核对首次误读Git转义后的中文文件名而假红；已用 git diff --name-only -z 按真实UTF-8路径重核通过，代码及候选未变。原六场景/全门/残留结果均有效；真实范围回执 scope-check.log。
done: 2026-10-04T19:14:40Z 最终范围、基点祖先与固定候选均通过；commit=ccb5419d353e6dec8ce60d98e4d8d4080dc0e182；full rc=0 PASS=843 FAIL=0，git status --short为空，残留测试进程=[]，仅保留本副本 .qwb-tmp/audit-finish-real-logs/ 审计输出；未改state、未操作真Herdr。完整证据 scope-check.log、full-complete.log、residuals.log，六场景明细见前述done行。
working: 2026-10-04T19:33:20Z 主控验收：运行时改动（bin/qwb-worktree.sh、bin/qwb-herdr.sh）逐行审过，四处统一为「agent 键不存在或为 null 算没有 agent」，其余核对未放松；五个提交 cherry-pick 到 main（9e86d98..089b0bd），bin/、templates/、tests/ 与工人最终版 ccb5419 逐字节相同，fast rc=0。真机验收（独立 named 会话，候选 0d3d8fe，其 bin/ 与最终版相同）：缺证据票在工人退回 shell、pane 保留、cd 出副本后带 --writer-proof-missing 收尾成功，留痕 pane_proof=foreground-shell（修复前此步被拒）；工人仍在或 shell 仍在副本内时带不带参数都拒绝并打出提示行（含 PID(命令名) 与 herdr pane close w2:p1）；证据正常时按提示关 pane 后不带兑底参数收尾成功。land 两处判定只有假 Herdr 证据，未做真机演练。合并后 main 全门（另一工人同时跑整门的高负载下，806 秒）：rc=1、843 PASS、1 FAIL=tests/process-entry-cleanup.py（整份 smoke 被 TERM 后残留两个空 scope 目录）；该项低负载单跑三次均 rc=0，且 audit-gate-parallel 工人在 47de4b6 源码上的基线同样红在这一条，判定为起点就有、随负载出现的夹具竞态，与本票运行时改动无关，交 audit-gate-parallel 收口。本票其余 843 条全过，予以合入。
