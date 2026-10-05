# 任务书：值守退出时可能永远卡住——订阅子进程没被终止，值守无限期等它

```
任务 id:  wake-exit-hang
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 主控在一轮卡死的全门里现场取证
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-wake-exit-hang.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控靠值守被叫醒；值守自己不能卡死。

### 现场事实（主控亲眼所见，2026-10-05，机器负载约 85）

1. 一轮全门里 `tests/collab-gate.sh` 调用的 `qwb-wake.sh --block --project … --max-ms 1` 运行了 16 分钟以上没有退出（本应 1 毫秒到期后以 124 退出）。
2. 对该 bash 进程取调用栈（`sample`）：`main → exit_shell → run_exit_trap → … execute_function → … wait_builtin → wait_for_single_pid`。即它已经进入退出流程，停在 EXIT 清理函数 `event_cleanup`（`bin/qwb-wake.sh` 约第 803–812 行）的 `wait "$EVENT_PID"` 上；它前一句是 `kill "$EVENT_PID"`。
3. 它唯一的子进程是订阅器（`qwb-herdr.sh subscribe` 里的 python，父进程号就是该值守）。订阅器这 16 分钟一直活着并在正常循环：通知文件里的 `seq` 持续增长（两次读取间从 576 到 587），`phase` 为 `fallback`；调用栈在 `time.sleep` 与 `poll` 之间来回。`ps` 显示它没有被屏蔽的信号，也没有待处理的信号。
4. 所以：终止信号发出了，订阅器却没退出；值守的 `wait` 没有时限，于是永远等下去。
5. 订阅器的信号处理（`bin/qwb-herdr.sh` 约第 118–122 行）是「收到 TERM 或 INT 就在处理函数里 `raise SystemExit`」，循环本身不检查任何停止标志。

### 主控的推断（**不是已证实的事实；你读代码后认为不成立就写 `needs-decision:`**）

Python 里，信号处理函数抛出的异常如果恰好落在某个对象的析构函数（`__del__`）执行期间，会被解释器当作「析构期间的异常」打印后丢弃，进程照常继续。主控做了最小实验证实这个机制存在（在 `__del__` 里给自己发 TERM，处理函数抛 `SystemExit`，进程打印 `Exception ignored while calling deallocator …` 后继续运行）。`subprocess.Popen` 有 Python 写的 `__del__`，订阅器每一轮都会通过 `command()` 创建并丢弃 `Popen` 对象。高负载下信号落进这个窗口的概率变大。主控没有证明这次现场就是这个窗口，只证明了「信号发出后订阅器没退」这个结果。

### 要做的事

两头都要修，值守这头是必须的保险。

1. **值守退出清理必须有时限。** `event_cleanup` 里对订阅器：发 TERM 后有界等待；没退就再发一次 TERM 并再有界等待；仍没退就 KILL 并在标准错误留一行说明。整个清理的总时限由你定，写成具名常量，不超过 5 秒。正常情况下（订阅器立刻退出）不得增加可感知的耗时，也不得改变值守现有的退出码与输出。订阅器被 KILL 时它正在跑的查询子进程怎么办，你读 `reap_command` 与 `command()` 后给出处理（能一并清掉最好；清不掉就在 `done:` 行写明残留的最坏情况）。
2. **订阅器不能只靠处理函数里的异常退出。** 处理函数除了抛异常，还要留下一个停止标志；外层与内层循环每一轮开头都检查它，标志已立就按 `128+信号号` 退出。这样即使异常被吞，最多再跑一轮就退。`command()` 里围绕创建与回收子进程的信号屏蔽不要动。
3. **测试。** 值守这头：测试用的临时安装里把 `qwb-herdr.sh` 换成一个替身订阅器（一种是忽略第一次 TERM，一种是忽略所有 TERM），断言值守在时限内退出、退出码与正常时相同、替身进程最终不存在、标准错误有相应说明。订阅器这头：若能在不给产品加测试钩子的前提下确定性地造出「异常被吞」，就测「下一轮即退出」；造不出来就写 `needs-decision:` 说明你考虑过的办法，不要硬造、不要给产品加只为测试存在的开关。

白名单：`bin/qwb-wake.sh`（仅 `event_cleanup` 及其所需常量）、`bin/qwb-herdr.sh`（仅 `subscribe()` 及其信号处理）、`tests/` 下为验收所需的已接入文件。**`tests/subscribe-reap.py`、`tests/full-gate.sh`、`tests/process-entry-cleanup.py` 正被另一张票修改，不要动这三个文件**；新用例放进别的已接入文件（例如 `tests/wake-block-output.sh` 或你认为更合适的已接入文件）。

## 1. 验收场景

### user_失败路径_订阅器吞掉第一次终止信号时值守仍按时退出

Given 临时安装里的订阅器替身忽略第一次 TERM、第二次 TERM 正常退出
When  `qwb-wake.sh --block --max-ms 1`
Then  值守在总时限加 2 秒内退出，退出码与输出同正常情况（124 及原有文字）；替身进程不存在；这条用例在起点提交上是红的（值守不退，测试自己用超时判红并清掉自己起的进程），先跑出红并留证

### user_失败路径_订阅器忽略所有终止信号时值守强杀后退出

Given 替身忽略所有 TERM
When  同上
Then  值守在总时限加 2 秒内退出，退出码不变；标准错误多一行强杀说明；替身进程不存在

### user_正常路径_订阅器正常时行为与耗时不变

Given 现有夹具
When  跑现有的值守阻塞用例（到期 124、有变化退出 2、无未结项 0、TERM 143、INT 130）
Then  标准输出、退出码与起点提交逐字节相同；标准错误除本票新增的说明行（正常路径不应出现）外相同；单次耗时与起点提交同时段对比无可见增加

### user_正常路径_订阅器收到信号后一轮内退出

Given 真订阅器在假 Herdr 下运行
When  发 TERM
Then  按 143 退出，耗时不超过一轮循环；INT 同理按 130

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改值守的叫醒判定、退出码、输出文字；不改订阅的 2 秒查询超时。
- 不许起烧 CPU 的压力进程来「复现高负载」；用替身订阅器确定性地造失败。
- 测试自己起的每个进程都要登记并在用例结束时清掉；用例失败时也不得留下进程。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径；shell 变量后面紧跟中文或中文标点时用花括号括起变量名。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 四个场景逐个验证，命令与结论写进 `done:` 行。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/wake-block-output.sh`、`tests/collab-gate.sh`、`python3 -B tests/subscribe-reap.py`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门。** 机器上多个工人同时跑全门会互相挤出超时类假失败；全门由主控在合并后串行跑。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
`done:` 行里另列：你读代码后对主控推断的判断（成立、不成立或无法判定，依据是什么）；订阅器被强杀时查询子进程的最坏残留情况。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不给产品加只为测试存在的开关；不改叫醒判定；不放宽任何现有断言。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T03:51:15Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-wake-exit-hang pane=w14Z:p15 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang base=abf5d05
working: 2026-10-05T03:52:30Z 执行者完成规格与调用链核对；基点 abf5d05，白名单与三处禁改文件已确认。拟用真实时钟3秒有界TERM/TERM/KILL清理；测试侧Popen析构注入验证吞异常，不加产品钩子。原始证据目录=.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence。
working: 2026-10-05T03:55:26Z 完成先红阶段：起点abf5d05替身retry在5秒超时判红且排空；真实Popen析构吞TERM后订阅外循环继续，旧版同样判红。日志=.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence/red-wake.log、red-subscriber.log。已仅在白名单实现3秒分阶段清理及双循环停止标志，进入绿证与字节对照。
working: 2026-10-05T03:56:33Z 四场景首轮绿证已完成：retry=1.084s、KILL=1.732s、正常124/2/0/143/130与起点stdout/stderr/rc逐字节相同、增量均小于0.15s。真实订阅外/内循环分别1.02s/0.01s内按143/130退出，确定性析构吞异常同样退出且seq=1；日志green-scenarios.log。已接入wake-block-output.sh，进入指定快门与定向门，不跑全门。
working: 2026-10-05T03:59:27Z 快门rc0；wake-block-output首轮rc0 PASS20 FAIL0；subscribe-reap裸跑rc1为既有夹具缺QWB_TEST_GROUPS，未改禁改文件，改由process_fixture.py --command运行后rc0 PASS8 FAIL0。收敛真实时钟取整：总清理上限由3秒调整为4秒，首段至少1秒裕量，防正常TERM在SECONDS秒边界误触发重试；仍低于规格5秒，正在对最终实现重跑相关门。
working: 2026-10-05T04:01:25Z 最终4秒版场景门rc0 PASS11 FAIL0，起点retry卡死再次按6秒超时红证且排空；测试就绪文件改原子发布消除夹具空文件窗口。产品改动仍仅event_cleanup所需常量与subscribe信号/循环检查；正常字节和耗时通过，内外循环真实析构吞TERM/INT均143/130退出。collab-gate继续推进，最终wake-block-output重跑中。
done: 2026-10-05T04:06:31Z 执行完成 commit=814d547c85fa7e923919532163ad6602aa9b3a5b；仅4个白名单文件，detached HEAD干净。event_cleanup真实总上限4秒，TERM/TERM/KILL后仅wait已退出PID；subscribe外/内循环保留停止信号。四场景命令：python3 -B tests/process_fixture.py --command python3 -B tests/wake-exit-hang.py --baseline-wake .qwb-tmp/wake-exit-hang-evidence/baseline-qwb-wake.sh，rc0 PASS11 FAIL0；retry=2.177s、KILL=2.579s，124/2/0/143/130 stdout/stderr/rc与基点逐字节相同，吞异常后143/130且通知seq=1。旧版两项rc1按超时红证并排空。日志绝对目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence（green-scenarios.log、red-wake.log、red-subscriber.log、commands.txt）。
done: 2026-10-05T04:06:31Z 门禁：bash bin/qwb-test.sh fast rc0 PASS0 FAIL0；/bin/bash tests/wake-block-output.sh rc0 PASS20 FAIL0；bash tests/collab-gate.sh rc0 PASS23 FAIL0；最终4秒代码另用QWB_GATE_ROUTES_ONLY=1 bash tests/collab-gate.sh rc0 PASS3 FAIL0。python3 -B tests/subscribe-reap.py 裸跑rc1 PASS0 FAIL0为既有夹具缺QWB_TEST_GROUPS；通过python3 -B tests/process_fixture.py --command python3 -B tests/subscribe-reap.py单独运行rc0 PASS8 FAIL0，未改3处禁改文件。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence，文件名fast.log/wake-block-output.log/collab-gate.log/collab-final-routes.log/subscribe-reap.log/subscribe-reap-scoped.log/summary.log；计数由grep -c取得。未跑全门。
done: 2026-10-05T04:06:31Z 推断判断：析构吞SystemExit机制成立；对原现场是否命中该窗口仍无法判定。依据为测试解释器保持原Popen析构后自发TERM/INT，CPython打印Exception ignored/SystemExit，固定旧版继续循环、新版两层循环均退出，未加产品钩子且command信号屏蔽/2秒超时未动。强杀最坏残留：查询独立session内的子孙可能无限期存活，父订阅器已死就无法执行reap_command和2秒超时；本票未杀未核实归属的查询进程组。所有本票测试进程与临时夹具已清理，仅保留证据目录；资源原始记录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence/resources.log。
done: 2026-10-05T04:06:57Z 报告补正：上一组前两条done分别618/674字符，超过600限制；按仅追加约束保留历史，本行与下一行提供合规短版。commit=814d547c85fa7e923919532163ad6602aa9b3a5b；工作区干净，资源无残留。event_cleanup上限4秒；subscribe保留信号并检查双循环。四场景：python3 -B tests/process_fixture.py --command python3 -B tests/wake-exit-hang.py --baseline-wake .qwb-tmp/wake-exit-hang-evidence/baseline-qwb-wake.sh，rc0 PASS11 FAIL0。retry=2.177s，KILL=2.579s；正常124/2/0/143/130输出逐字节不变；吞异常后143/130。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/wake-exit-hang/.qwb-tmp/wake-exit-hang-evidence，日志green-scenarios.log/red-wake.log/red-subscriber.log/commands.txt。
done: 2026-10-05T04:06:57Z 门禁短版：bash bin/qwb-test.sh fast rc0 PASS0 FAIL0；/bin/bash tests/wake-block-output.sh rc0 PASS20 FAIL0；bash tests/collab-gate.sh rc0 PASS23 FAIL0；QWB_GATE_ROUTES_ONLY=1 bash tests/collab-gate.sh rc0 PASS3 FAIL0。python3 -B tests/subscribe-reap.py裸跑rc1（既有夹具缺QWB_TEST_GROUPS）；python3 -B tests/process_fixture.py --command python3 -B tests/subscribe-reap.py rc0 PASS8 FAIL0。三处禁改文件未变，未跑全门。原始日志目录同上一行：fast.log/wake-block-output.log/collab-gate.log/collab-final-routes.log/subscribe-reap.log/subscribe-reap-scoped.log/summary.log/resources.log。
working: 2026-10-05T04:24:59Z 主控验收：读完产品改动（event_cleanup 改为 TERM、再 TERM、KILL，总上限 4 秒；订阅器两层循环检查停止标志）。提交 814d547 已 cherry-pick 进 main（1624688）。合并后 main @ 44ab8ac 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、669 秒（.qwb-tmp/ctl-full-merge6.log），tests/wake-exit-hang.py 经 tests/wake-block-output.sh 在冒烟内执行；真机验收第 12 轮 14 项断言全 PASS。已知残留：订阅器被强杀时，它正在跑的查询子进程可能留下（查询本身是短命令）。原现场是否就是「析构期间异常被吞」无法判定。
