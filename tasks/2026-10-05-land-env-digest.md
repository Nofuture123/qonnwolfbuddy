# 任务书：主控落地必被拒——验收环境摘要拿落地者自己的环境去比

```
任务 id:  land-env-digest
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第二轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r2.md） 的 R5
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-land-env-digest.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/land-env-digest（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：门控通过后，主控按规定落地到 main 并收尾。

### 事实（主控已核对代码与演练记录）

1. 门控通过后，主控执行 `qwb-ledger.sh land-authorize` 被拒：`账本拒绝：未验收或验收条件已变`。演练主控用 `gate-context … observe` 与审核时的上下文逐键比对，唯一差异是 `environment_sha256`。
2. `gate_context`（`bin/qwb-ledger.sh` 约第 801 行）取调用者进程的 `PATH LANG LC_ALL LC_CTYPE CI NODE_ENV BASH_ENV SHELLOPTS` 连同工具二进制摘要算环境摘要。门控在自己的 Pi 窗口里验收，主控在 Claude Code 的 shell 里落地，两边 `PATH` 不同。
3. `bin/qwb-worktree.sh` 第 6 行 `export LC_ALL=C`。门控验收时 `LC_ALL` 为空，所以经 `qwb-worktree.sh land` 调 `land-prepare`、`land-apply` 必然对不上——演练里即使把其余环境变量都对齐，经这个脚本仍被拒。`bin/qwb-run.sh`、`bin/qwb-wake.sh`、`bin/qwb-status.sh`、`bin/qwb-lint.sh` 开头同样 `export LC_ALL=C`。
4. 演练主控最后是让门控导出环境变量，在相同环境下直接调 `qwb-ledger.sh land-prepare` 与 `land-apply` 才落地成功。官方路径走不通。
5. 现有测试里验收与落地都由同一个测试进程发起，环境天然相同，所以测不出来。

### 主控的设计方向（**你读代码后有更好的办法或认为不成立，写 `needs-decision:`**）

环境摘要的用途是把「门的运行回执」和「门控结论」绑在同一个工具环境上——这些都发生在门控自己的环境里。落地由主控执行，落地不运行任何门；落地要核的是「被通过的那个候选没有变」：候选的 head、tree、base、规格与场景、策略、命令、工人配置。拿落地者的环境变量去比门控的环境没有意义，还必然失败。

所以：落地各步（`land-authorize`、`land-prepare`、`land-apply`、`land-close`）核对「验收条件未变」时，候选相关各项照旧现场重算并比对；环境这一项不取调用者的环境重算，改为沿用门控结论里记录的环境摘要（或从比对中剔除——两种做法你选一个并说明理由）。门控自己的各步（收据、审核、结论）仍按现状用现场环境严格比对，一项不松。

另外查清并处理：门控经 `qwb-run.sh` 派审核或返修工人、经其他带 `export LC_ALL=C` 的脚本间接调到 `gate_context` 时，是否也会和它直接调账本时算出不同的摘要（主控没有核实这一点）。有的话一并消除——做法是让摘要不受包装脚本自己设的语言环境影响，而不是去掉包装脚本的 `LC_ALL=C`。

白名单：`bin/qwb-ledger.sh`（`gate_context` 及落地各步的验收条件比对）、`tests/` 下为验收所需的已接入文件。`bin/qwb-worktree.sh` 的 `export LC_ALL=C` 不许删。

## 1. 验收场景

### user_正常路径_主控在不同环境下经官方脚本落地成功

Given 门控在环境甲（某个 PATH、LC_ALL 为空）下完成收据、审核并给出通过
When  主控在环境乙（不同的 PATH、LANG）下依次执行 `land-authorize` 与 `qwb-worktree.sh land`
Then  落地成功，main 快进到被通过的提交，票 verified；这条用例在起点提交上是红的（被拒「未验收或验收条件已变」），先跑出红并留证

### user_失败路径_候选在通过后被改动则落地拒绝

Given 门控通过后，候选副本又多了一个提交，或工作区变脏，或规格与场景被修订
When  主控落地
Then  三种情况都被拒，信息与起点提交相同；main 不动

### user_失败路径_门控自己的环境变了仍拒绝

Given 门控在环境甲下留了门的运行回执，随后在环境丙（不同 PATH）下提交审核或结论
When  执行该步
Then  被拒，行为与起点提交相同

### user_正常路径_同一环境下的现有行为不变

Given 现有夹具（验收与落地同一环境）
When  跑现有的门禁与落地用例
Then  标准输出、标准错误、退出码、票内容与起点提交逐字节相同

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
- 四个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-gate.sh`、`tests/collab-land.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（多个工人同时跑全门会互相挤出超时类假失败，全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名，凡是写死了该文件 PASS 条数或用例组数的地方（例如冒烟某节的 `-eq 48`、`tests/herdr-batch.py` 的组数断言），同步改成新值；这些计数行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不放松门控各步的环境比对；不放松候选身份的任何一项比对；不删包装脚本的语言环境设置。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T05:23:08Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-land-env-digest pane=w14Z:p18 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/land-env-digest base=4b1f2e2
needs-decision: 2026-10-05T05:24:12Z 执行者核对：land-close 并不调用 gate_context/land_ready，而是在候选已删除后核对固定main、分支/副本/Space消失和义务闭环；任务对四步均比环境的前提仅前三步成立。拟仅修前三步共用 land_ready，保留 land-close 全部既有守卫；不影响官方land闭环验收。
working: 2026-10-05T05:24:12Z 执行者已完整读票与R2演练记录；确认基点4b1f2e2、工作区干净。定位land_ready共用比对与qwb-run gate-context/gate-dispatch/gate-diff的LC_ALL差异，开始在既有隔离测试里补先红后绿反例。证据目录=.worktrees/land-env-digest/.qwb-tmp/land-env-evidence。
working: 2026-10-05T05:24:23Z 主控裁决：同意。前提里把 land-close 也算进去是主控写错了；只改前三步共用的 land_ready，land-close 的既有守卫全部保留。继续。
working: 2026-10-05T05:27:34Z 基点先红已完成：bash tests/collab-land.sh env-digest rc=1，真实land-authorize rc=255并拒绝「未验收或验收条件已变」；bash tests/collab-gate.sh rc=1，直接/LC_ALL=C采样仅environment_sha256不同。日志为本副本.qwb-tmp/land-env-evidence/red-land.log、red-gate.log。已按最新裁决保留land-close；修复仅gate_context与land_ready，进入绿灯及字节等价验证。
working: 2026-10-05T05:29:06Z 最小修复绿灯：env-digest rc=0，门控原PATH/空LC_ALL收据审核通过，主控异PATH/LANG经官方land到verified；env-compat rc=0，固定时钟/事件后基点与当前gate收据/审核/结论及官方land的stdout、stderr、rc、票字节一致，dirty/spec/scenarios/new-commit在authorize/prepare/apply均拒绝且main未动。fast rc=0。正在跑collab-gate.sh与collab-land.sh定向文件；不跑全门。
working: 2026-10-05T05:31:07Z 补记定向首败：collab-land原有9组完成后rc=2，原因是执行者运行期间编辑本测试脚本，使Bash heredoc后的读取偏移失效（语法检查本身通过）；首败保留land-first.log/.rc。已冻结三个改动文件SHA256到frozen.sha256并重跑collab-land，不再在测试运行期编辑。另/bin/bash 3.2 env-digest rc=0，明确LANG=en_US.UTF-8到C的跨环境闭环通过。
