# 任务书：收紧叫醒——工人的进度行不再叫醒主控

```
任务 id:  wake-tighten
state: verified
implementation-authorized: Rocky 2026-10-05「收紧叫醒」
dispatch-budget: 3
来源:     2026-10-05 主控统计已装项目历史账本后向 Rocky 提出，Rocky 批准
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-wake-tighten.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控没有事情要做的时候不要被叫醒。主控是 opus，每被叫醒一次就带着全部上下文跑一轮。

### 现状与数据（主控已核实）

`bin/qwb-wake.sh` 的 `collect_due` 对未迁旧票的判定是：指纹 = `state` 加最后一条状态行原文，指纹一变就叫醒主控。所以工人每追加一条 `working:` 进度行，主控就被叫一次。

主控统计了两个已装项目（qonnwolf-sites、qonnwolfmcp）的历史账本，95 张票共 904 次叫醒，按叫醒前最后一条状态行分类：

| 触发 | 次数 | 占比 |
|---|---|---|
| 最后一行是 `working:` | 515 | 57.0% |
| 上次叫醒后没有新状态行（时间兜底重叫） | 155 | 17.1% |
| 最后一行是 `done:` | 141 | 15.6% |
| 还没有任何状态行 | 70 | 7.7% |
| 最后一行是 `blocked:` 或 `needs-decision:` | 23 | 2.6% |

`working:` 行只说明工人在推进，主控没有要做的动作。

### 主控裁决的新规则

只改未迁旧票、`state: running`、工人没有丢失这一种情况；其余全部不变。

1. **进度行不叫醒。** 最后一条状态行以 `working:` 开头时，指纹变化不算新事实，不叫醒主控，也不写 `wake:` 行。
2. **进度行当作心跳，只推迟兜底。** 这种票只剩时间兜底：距「兜底时钟」已满 `QWB_REWAKE_MS` 仍无新进展才叫一次（叫醒时照常写 `wake:` 行，记当前指纹）。兜底时钟取两者中较晚的一个：票文件的修改时间、最近一条 `wake:` 行的时间戳。取修改时间用 perl 的 `stat`，不用 `stat` 命令（macOS 与 Linux 参数不同）。`wake:` 时间戳解析失败照旧按超期处理。
3. `QWB_REWAKE_MS` 为 0 或未设时兜底关闭，这种票不会因为进度行被叫醒；静默模式（posture quiet）下同样不做时间兜底。两者都与现有「指纹未变」分支的处理一致。
4. 现有「指纹未变、running、满 `QWB_REWAKE_MS` 重叫」分支改用同一个兜底时钟，两个分支不要各写一份时间判断。
5. **照旧立刻叫醒的情况，一条都不许变**：最后一条状态行是 `done:`、`blocked:`、`needs-decision:` 且指纹是新的；票里还没有任何状态行（新票等主控派发）；工人丢失（`lost=` 段）；`state` 为 `blocked`、`needs-decision` 或非法值；账本 UTF-8 损坏；已迁协作票（`qwb-collab-v1`）的全部路径。
6. 非 `--block` 模式下，被本规则跳过的票打一行说明，写法照现有「跳过：」行，内容点明是工人在推进、进度行不叫醒。
7. `--once`、`--dry-run`、循环模式与 `--block` 继续共用同一份判定。Claude Code 的 Stop hook 与 Pi 扩展都只调用 `qwb-wake.sh --block`，不在它们里面另写判定；动手前先确认这一点，如果发现哪一处自己解析账本，写 `needs-decision:`。
8. **说明文字**：`bin/qwb-wake.sh` 文件头的「去重」「兜底重叫」两段、`templates/config.sh` 里 `QWB_REWAKE_MS` 的注释、模板说明里描述叫醒时机的句子，改到与新规则一致。给工人看的说明（`templates/TASK.md`、`templates/roles/执行者.md`、`templates/QWBUDDY.md` 里讲状态行的地方）补一句：`working:` 只记进度，不会叫醒主控；需要主控处理时写 `blocked:` 或 `needs-decision:`，全部完成写 `done:`。写法与密度照各文件现有句子，不另起小节。

白名单：`bin/qwb-wake.sh`、`templates/config.sh`（仅 `QWB_REWAKE_MS` 那一行的注释）、`templates/TASK.md`、`templates/roles/执行者.md`、`templates/roles/主控.md`、`templates/QWBUDDY.md`、`templates/host-watch-guide.md`、`README.md` 与 `README.zh.md`（后五个文件都只改描述叫醒时机的句子，没有就不动）、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_进度行不叫醒

Given 一张未迁旧票 `state: running`，工人 pane 在、之前已被叫醒过一次（有带 `fp=` 的 `wake:` 行），`QWB_REWAKE_MS` 为 30 分钟
When  工人连续追加三条 `working:` 行，每追加一条分别跑一次 `--once` 和一次带短 `--max-ms` 的 `--block`
Then  都不投递、不新增 `wake:` 行；`--block` 以 124 到期；`--once` 打出跳过说明

### user_正常路径_做完或卡住立刻叫醒

Given 同一张票，最后一条是 `working:` 行，期间没有被叫醒
When  工人追加一条 `done:` 行；另两组分别追加 `blocked:` 行、`needs-decision:` 行
Then  三组都立刻叫醒：`--block` 退出码 2，摘要带该行，新增一条 `wake:` 行；紧接着再跑一次不重复叫

### user_失败路径_工人挂起由兜底叫醒一次

Given 一张 `running` 票最后一条是 `working:` 行，票文件修改时间与最近一条 `wake:` 行的时间戳都早于 `QWB_REWAKE_MS` 之前（用 `touch -t` 把修改时间拨回去）
When  跑一轮判定
Then  叫醒一次并写 `wake:` 行；立刻再跑一轮不叫；把修改时间与该 `wake:` 行再次拨到超期之前后，再叫一次

### user_失败路径_心跳在则不兜底

Given 同上，但票文件修改时间在 `QWB_REWAKE_MS` 之内（工人刚写过进度行），最近一条 `wake:` 行早已超期
When  跑一轮判定
Then  不叫醒

### user_失败路径_工人丢失照旧立刻叫醒

Given 一张 `running` 票最后一条是 `working:` 行，登记的工人 pane 已不存在
When  跑一轮判定
Then  立刻叫醒，摘要带「工人丢失」，行为与起点提交相同

### user_失败路径_兜底关闭与静默模式

Given `QWB_REWAKE_MS=0`（另一组为静默模式），一张 `running` 票只有 `working:` 行在增长，修改时间已拨到很久以前
When  跑一轮判定
Then  两组都不叫醒；随后追加 `done:` 行则照常叫醒

### user_正常路径_其余情况逐字节不变

Given 起点提交与改后的脚本
When  对以下情况各跑一遍：没有任何状态行的新票、`state` 为 `blocked` 或 `needs-decision` 的票、非法 `state`、UTF-8 损坏的票、已迁协作票的现有用例
Then  stdout、stderr、退出码、写入的 `wake:` 行（时间戳除外）新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 现有测试里凡是断言「追加 `working:` 行就叫醒」的，改成新规则下的正确断言；**不许为了让测试变绿而删用例或放宽无关断言**。`done:` 行里逐条列出改过的断言（文件、节号、原来断言什么、现在断言什么）。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 另两张票同时在别的副本里进行：`harness-roster` 改 `templates/workers.sh`、`templates/config.sh` 的工人相关行、`templates/dispatch-rules.json`、`templates/host-watch-guide.md` 与 `templates/QWBUDDY.md` 里和 Codex 有关的句子、真机验收脚本、`tests/smoke.sh` 的模板断言；`review-model-rule` 改 `bin/qwb-lint.sh`、`bin/qwb-ledger.sh`、审核身份的说明与测试。说明文字只做句子级的最小改动，方便主控合并。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`（四段并发，约 6–8 分钟），重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改已迁协作票的交接、门禁路由与事件判定；不改主控锁、派发、收尾；不改 Stop hook 与 Pi 扩展的退出码约定。
- 不加新的配置开关；不改 `QWB_REWAKE_MS` 的默认值。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T00:10:19Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-wake-tighten pane=w14Z:pX dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten base=70581f9
working: 2026-10-05T00:11:23Z 执行者阶段1：完整读取任务书及点名模板/README；核对 Claude hook 与 Pi 扩展均调用 qwb-wake.sh --block，未自写指纹唤醒判定（hook 第二次124仅调用共享 waiting-only 检查）。基点70581f9、detached、工作区clean；后续仅改白名单，测试保留失效关闭及进程/socket夹具，不碰真Herdr/模型。
working: 2026-10-05T00:19:32Z 执行者阶段2：旧票running的working进度与未变指纹共用较晚时钟（Perl stat），quiet/零值/未设关闭兜底；已迁及需主控处理的新事实保持原路径，说明句同步。fast rc0；七场景Bash3.2定向首轮修正协作区随机event_id的比较范围后rc0、7PASS/0FAIL，日志=.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-r2.log；旧实现在进度跳过断言处rc1（baseline-red.log）。补工人丢失字节对照后准备提交并跑全门。
working: 2026-10-05T00:20:09Z 执行者阶段3：已提交643e44c13f7d1418ef9bb2ef300572220f0b37fc，git status --short为空；fast-final.rc=0，posture-r2.rc=0。提交后已启动 bash bin/qwb-test.sh full（四段并发），日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/full.log，退出回执同目录full.rc；执行中，等完整退出再报告done。
working: 2026-10-05T00:24:25Z 执行者验收进展：提交后全门仍运行；协作跑批中 tests/process-entry-cleanup.py 已报告中断 full-gate 后临时目录残留（survivors=[]），其余段未收齐。保留full首败日志，不降低断言；待全门结束后定向复验清理入口，区分环境时序与本票回归。七场景最终回执scenarios-complete.rc=0（7PASS/0FAIL），日志同目录。
working: 2026-10-05T00:30:55Z 执行者验收返查：首轮full rc1、842PASS/1FAIL、544s，唯一失败为process-entry-cleanup.py中断full-gate后的临时目录残留（full.log）；未改代码或断言。单独 python3 -B tests/process-entry-cleanup.py 复验rc0，正常/TERM与两种Bash全门边界全部通过（cleanup-recheck.log/.rc）。同一提交643e44c上再跑完整并发全门，保留首败。
working: 2026-10-05T00:44:09Z 执行者全门二查：full-r2 rc1、835PASS/1FAIL、550s，唯一失败为subscribe-reap.py五次均错过2秒观察窗口（读龄3.9307/2.1727/2.4591/2.5958/2.3579秒）；报告明确测量环境问题。登记前移试改因组号断言失败且register函数无额外进程，已完整撤回，git status为空。原探针带进程夹具单独复验rc0，normal读龄0.822394秒、TERM/INT约0.18秒、查询返回/2秒超时均通过（subscribe-original.log/json）。同一643e44c提交启动第三轮完整并发全门。
done: 2026-10-05T00:52:40Z 场景1 user_正常路径_进度行不叫醒：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（tests/wake-block-output.sh §1），连续三条working分别once/dry-run/block；均零投递、票字节不变，once含跳过说明，block=124。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景2 user_正常路径_做完或卡住立刻叫醒：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§2）；done/blocked/needs-decision分别block=2、摘要含该行、追加wake，再跑block=124且票不变。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景3 user_失败路径_工人挂起由兜底叫醒一次：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§3）；touch -t 200001010000把mtime拨旧且wake超期，once叫一次，立即block=124；两时钟再次拨旧后block=2。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景4 user_失败路径_心跳在则不兜底：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§4）；mtime新/wake旧时，新/未变fp均block=124；新wake/旧mtime亦124；坏wake时间戳仍按超期block=2。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景5 user_失败路径_工人丢失照旧立刻叫醒：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§5及§7 lost对照）；working+pane丢失立即block=2，摘要含工人丢失；随后124不重复；与70581f9的once输出/错误/退出码/wake/调用字节相同。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景6 user_失败路径_兜底关闭与静默模式：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§6）；REWAKE=0、未设、quiet三组旧时钟加新working均不叫（block=124），随后done均block=2。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log。
done: 2026-10-05T00:52:40Z 场景7 user_正常路径_其余情况逐字节不变：命令=QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh（§7）；基线70581f9与候选的新票/blocked/needs-decision/非法state/坏UTF8的stdout、stderr、rc、票写入及Herdr调用相同（仅归一wake时间）；已迁working/done handoff的摘要、rc、wake行及调用相同，已迁末行working的dry-run整票不变。协作区随机事件ID不作字节比较。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/scenarios-complete.log；定向总计rc0、7PASS/0FAIL。
done: 2026-10-05T00:52:40Z 断言改动逐条：tests/smoke.sh §27 首轮原断言“已有working就写第一条wake”，现先以无状态行新票写第一条wake，再追加working；原“指纹未变且未超期不再叫”现断言“新的working且未超期不再叫”；原“仅拨旧wake就超期再叫”现同时拨旧wake与mtime才再叫。dry-run不写wake、真叫写第二条、坏时间戳超期、REWAKE=0关闭等无关断言保留。原始输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/full-r3.log。
done: 2026-10-05T00:52:40Z 夹具改动：tests/collab-posture.sh user_静音与空闲成本，原以working作为首次可动作事实，现以done初始化；三轮quiet空输出、无重复投递、版本/模式不变及真实失败持久交接断言原样保留。working+quiet的新行为由tests/wake-block-output.sh §6明确检验。新七场景接入原wake-block-output文件，未删用例。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/posture-r2.log及full-r3.log。
done: 2026-10-05T00:52:40Z 快门/兼容：bash bin/qwb-test.sh fast rc0，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/fast-final.log，未新增ShellCheck告警；七场景用/bin/bash 3.2完整跑通。旧脚本以QWB_TEST_WAKE_SOURCE=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh运行同定向文件，在“working进度跳过”断言处rc1，证明回归识别旧行为（baseline-red.log）。
done: 2026-10-05T00:52:40Z 全门：最终提交643e44c13f7d1418ef9bb2ef300572220f0b37fc之后 bash bin/qwb-test.sh full 四段并发第三轮rc0、843PASS/0FAIL、407秒；计数用grep -c '^PASS'与grep -c '^FAIL'。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/full-r3.log，回执full-r3.rc/full-r3.seconds。无qwbuddy/config.sh，比主仓少1PASS属票定边界，未造配置。
done: 2026-10-05T00:52:40Z 全门历史保留：第一轮rc1、842PASS/1FAIL、544秒（中断清理目录残留），清理入口原断言单独复验rc0；第二轮rc1、835PASS/1FAIL、550秒（订阅读龄超2秒、报告环境问题），原探针带进程夹具单独复验rc0。未提交的subscribe-reap登记前移试改已完全撤回，该文件与基点相同。三轮均同一提交；日志根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ（full.log、full-r2.log、cleanup-recheck.log、subscribe-original.log/json）。
done: 2026-10-05T00:52:40Z 收尾：最终提交643e44c13f7d1418ef9bb2ef300572220f0b37fc；全门后git status --short输出为空；本副本测试残留进程清单=[]（已排除执行者本身及本次检查祖先），证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-tighten.QLPhPOfJ/closure.json。实现只在隔离副本白名单内；执行者会话/本副本留待主控审核回收，本票不操作真Herdr或worktree。DONE 643e44c13f7d1418ef9bb2ef300572220f0b37fc。
working: 2026-10-05T00:54:17Z 主控验收返修（第1轮，候选 643e44c 之上追加一个提交）：逻辑与七场景认可。一处与规格不符要补：进度票（未迁、running、工人未丢失、末行 working:）在票里**还没有任何 wake: 行**时，现在 ts_epoch 对空串失败、被当作「时间戳解析失败按超期」而立刻叫醒一次。这正是最常见的路径——主控刚派发完，派发脚本或工人写下第一条 working: 行，值守第一轮就白叫主控一次（2026-10-05 真机验收里两轮都出现了这次白叫）。规格第2条的兜底时钟是「票文件修改时间与最近一条 wake: 时间戳中较晚者」：没有 wake: 行时时钟就是票文件修改时间，不算解析失败；只有存在 wake: 行但时间戳非法才按超期处理。只改进度票这一种情况，其余分支（含指纹未变分支）行为不变。补测试：无 wake 行 + 末行 working + 修改时间新鲜 → 不叫醒不写行；无 wake 行 + 末行 working + 修改时间拨到超期之前 → 兜底叫一次；有 wake 行但时间戳非法 → 照旧按超期叫。文件头说明同步一句。提交后跑快门、tests/wake-block-output.sh、tests/smoke.sh 与一次全门，done 行报新 sha 与结果。
working: 2026-10-05T00:56:11Z 执行者返修阶段1：已读00:54:17主控指令；只改bin/qwb-wake.sh的进度票无wake分支及文件头，并在原wake-block-output文件补三条用例（非法时间戳含空值）。新测试在643e44c原脚本的“无wake新鲜进度”断言处rc1，确认有效红；预快门rc0，定向验收执行中。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/red.log及pre-fast.log。
working: 2026-10-05T00:57:52Z 执行者返修阶段2：在643e44c之上只追加提交4e97b233ec841b82001a854dd2cabb295056f4df（2文件22增4删）；预定向10PASS/0FAIL、Bash3.2与预快门通过，提交后fast rc0。提交后定向进行中，随后独立smoke与一次full按序验收，避免同时跑两份smoke。日志根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD。
working: 2026-10-05T01:04:18Z 执行者返修阶段3：提交4e97b233ec841b82001a854dd2cabb295056f4df后的fast rc0；定向含原七场景与三条新增回归rc0、10PASS/0FAIL；独立bash tests/smoke.sh rc0（计数与原始输出在日志），即将启动规定的一次full四段并发。日志根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD（fast.log、scenarios.log、smoke.log及对应rc回执）。
done: 2026-10-05T01:11:44Z 返修第1轮完成：在643e44c13f7d1418ef9bb2ef300572220f0b37fc之上只追加一个提交4e97b233ec841b82001a854dd2cabb295056f4df。bin/qwb-wake.sh仅为未迁running、工人未丢失、末行working且无wake行的票补mtime兜底；存在非法wake时间戳仍按超期，原指纹未变分支及其他路径不改。文件头同步一句；只改该脚本与tests/wake-block-output.sh两文件。
done: 2026-10-05T01:11:44Z 新增三条回归（tests/wake-block-output.sh“返修1/2/3”，原断言未删除/放宽）：①无wake+新鲜mtime，once/dry-run跳过、block=124，零投递/写行；②无wake+touch -t 200001010000超期mtime，once只叫一次写首条wake，立即block=124；③已有wake但GARBAGE/空时间戳，mtime新鲜仍叫一次，随后去重。原643e44c脚本在①断言处rc1（有效红），日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/red.log。
done: 2026-10-05T01:11:44Z 提交后快门与定向：bash bin/qwb-test.sh fast rc0，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/fast.log；QWB_TEST_WAKE_BASELINE=.qwb-tmp/wake-tighten.QLPhPOfJ/base-wake.sh /bin/bash tests/wake-block-output.sh rc0、10PASS/0FAIL，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/scenarios.log。含三条新增、原七场景及其余分支新旧字节对照；Bash3.2通过，无新增ShellCheck告警。
done: 2026-10-05T01:11:44Z 提交后独立smoke：bash tests/smoke.sh rc0、804PASS/0FAIL、348秒，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/smoke.log，回执smoke.rc/smoke.seconds。与后续full按序执行，未并跑两份smoke；保持原进程登记、失效关闭与socket夹具。
done: 2026-10-05T01:11:44Z 提交后规定的一次全门：bash bin/qwb-test.sh full 四段并发，rc0、843PASS/0FAIL、344秒；计数用grep -c '^PASS'与grep -c '^FAIL'。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/full.log，回执full.rc/full.seconds；未造qwbuddy/config.sh。四项指定验证全部通过。
done: 2026-10-05T01:11:44Z 返修收尾：最终sha=4e97b233ec841b82001a854dd2cabb295056f4df，父提交643e44c13f7d1418ef9bb2ef300572220f0b37fc；全门后git status --short为空，测试残留进程清单=[]（排除执行者自身及检查祖先），证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-tighten/.qwb-tmp/wake-repair.PO6O8OYD/closure.json。仅向主账本追加本人的状态，不改state或别人行；执行者会话/副本留主控复审回收。DONE 4e97b233ec841b82001a854dd2cabb295056f4df。
working: 2026-10-05T01:20:25Z 主控验收：独立核对改动与探针，返修项已补；提交已 cherry-pick 进 main，合并后 main @ 4bdd2fd 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、429 秒（.qwb-tmp/ctl-full-merge.log）；真机验收第 10 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS。详见 docs/reviews/2026-10-03-qwb-full-audit-r1.md「工具与角色调整」。
