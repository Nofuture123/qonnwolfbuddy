# 任务书：把三个没人跑的回归脚本接进全门，并加一道「测试文件必须有入口」的自检

```
任务 id:  audit-orphan-tests
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」
dispatch-budget: 3
来源:     主控 2026-10-04 验收 audit-pi-profile 时扫出；与审核发现 F2 同类
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-orphan-tests.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests（隔离副本，detached HEAD，起点 main 68d0e63）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

这一轮开头查出「12 个测试文件没有任何入口调用」并补进了全门。随后的几张票又新加了三个回归脚本，却同样没接进任何门，主控验收时也没发现：

- `tests/process-fixture-check.py`（进程登记夹具自检）
- `tests/process-entry-cleanup.py`（各测试入口被 TERM 后不留进程、目录、字节码）
- `tests/socket-path-regression.py`（socket 路径守卫与长路径回归）

没人跑的回归测试等于没有。而且同一个错误已经犯了两次，需要一道机制防第三次。

白名单：`tests/collab-all.sh`；确有必要时可动上面三个脚本本身（仅为让它们能在并发跑批里稳定运行），并写明理由；第 6 条涉及的 `tests/collab-*.sh`（只许改等待上限的数值）。

### 工程规格

1. 先在本副本里把三个脚本各单独跑 3 次，记下退出码与耗时。有不稳定或失败的，先定位原因再决定：属于脚本自身的并发或环境问题就修脚本；属于它在测的东西真的有问题，就写 `needs-decision:` 报主控，不接进门。
2. 把稳定通过的接进 `tests/collab-all.sh` 的默认清单（它们与清单里其他测试并发跑；`collab-all.sh` 现在用 `bash` 启动每一项，`.py` 脚本要按各自的方式启动——让清单里的每一项能表达「用什么解释器跑」，不要靠给 `.py` 加执行权限或改 shebang 来凑）。更新清单上方的注释与末行的项数。
3. 确认它们并发跑时不互相干扰、也不干扰清单里别的测试：`process-entry-cleanup.py` 会对别的测试入口发 TERM——它发的对象必须只是它自己启动的那些进程；逐行读代码确认，并连续跑 3 次 `bash tests/collab-all.sh` 全绿来证明。
4. **加一道自检**（放在 `tests/collab-all.sh` 里，在启动任何测试之前执行）：列出 `tests/` 下所有 `.sh`、`.py`、`.mjs` 文件，每一个都必须满足下面之一，否则立刻以清晰的中文信息失败退出并点名文件：
   - 在 `tests/collab-all.sh` 的默认清单里；
   - 被 `tests/smoke.sh`、`qwb.config.sh` 的门命令，或另一个已有入口的测试文件按文件名引用；
   - 在脚本里显式写死的豁免名单里，每一项后面带一句理由（例如 `e2e-real.sh` / `e2e-real.py` 是连真 Herdr、要花钱的手工验收；夹具模块 `process_fixture.py`、`process-fixture.sh`、`fixtures/` 下的文件不是测试）。
   豁免名单要尽量短，逐项写明理由；不要用「名字匹配某种模式就豁免」的写法。
5. 自检只读文件名与文件内容，不执行被检查的文件。
6. **放宽测试自己的等待上限（主控 2026-10-04T14:00Z 追加）**：并发项数从 12 增到 15 之后，`tests/collab-handoff.sh` 里 `watch.communicate(timeout=3)` 这种「等被测进程结束最多等几秒」的上限在机器忙时不够用，第 2 轮因此失败。这类上限只是测试夹具防止挂死的保险，不是对产品时序的断言（那条用例断言的是值守以 124 退出）。把 `tests/collab-*.sh` 与本票新接入的三个脚本里这类**等待上限**统一放宽到不少于 20 秒；先 grep 出所有 `timeout=` 与轮询截止时间，逐个判断：是「等它结束的保险」就放宽，是「产品必须在多少时间内做到某事」的时序断言就不动，并在 `done:` 行里列表说明每一处的判断。放宽后测试在正常情况下的耗时不应变长（等待是到点即返回的）。

## 1. 验收场景

### user_正常路径_三个回归脚本进门且并发稳定

Given 只含本票改动的隔离副本
When  连续跑 3 次 `bash tests/collab-all.sh`
Then  3 次都退出码 0，每次的 PASS 行里包含这三个脚本，末行的项数与清单一致；没有以 rm: 开头的行，跑完没有残留进程与残留目录

### user_失败路径_新增一个没接入口的测试文件会被拦下

Given 在副本的 `tests/` 下临时新建一个不被任何入口引用的 `zz-orphan-example.sh`（验完按确切路径删除，不提交）
When  跑 `bash tests/collab-all.sh`
Then  在启动任何测试之前就以非 0 退出，信息点名这个文件并说明三种合规方式；删掉它之后恢复通过

### user_失败路径_被别的测试引用或已豁免的文件不被误拦

Given 现有的全部测试文件
When  跑自检
Then  通过；`done:` 行里列出每个文件是凭哪一条合规的（在清单里 / 被谁引用 / 豁免及理由）

### user_失败路径_回归脚本失败时全门照样红

Given 在临时拷贝里让三个脚本之一必然失败（不提交）
When  跑 `bash tests/collab-all.sh`
Then  退出码 1，对应那一行是 FAIL 并打印其日志，其余各项照常报结果

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内（场景二那个示例文件除外，它必须在 `tests/` 下，验完立刻按确切路径删除）；禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 的进程。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`；另跑 `bash -n tests/collab-all.sh && shellcheck tests/collab-all.sh`，不得有告警。
- 四个场景逐个验证，命令与原始结果写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 6 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `bin/`、`templates/`、`tests/smoke.sh`、`qwb.config.sh`；不改任何断言。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T13:25:41Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-orphan-tests pane=w14Z:pM dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests base=68d0e63
working: 2026-10-04T13:26:53Z 阶段0完成：完整读取任务书、三个回归脚本、collab-all、qwb.config、qwb-test及进程登记夹具；副本起点68d0e631e429dd60c548ea20f9fddbd4dd36f0b8，git status为空；process-entry-cleanup全局BASE快照存在并发误判风险，先执行规定单跑。
working: 2026-10-04T13:41:43Z 阶段1完成：命令 python3 -B tests/{process-fixture-check.py,process-entry-cleanup.py,socket-path-regression.py} 各单独连续3次，原始回执=[{"script": "process-fixture-check.py", "attempt": 1, "rc": 0, "seconds": 1.778}, {"script": "process-fixture-check.py", "attempt": 2, "rc": 0, "seconds": 1.822}, {"script": "process-fixture-check.py", "attempt": 3, "rc": 0, "seconds": 1.79}, {"script": "process-entry-cleanup.py", "attempt": 1, "rc": 0, "seconds": 43.758}, {"script": "process-entry-cleanup.py", "attempt": 2, "rc": 0, "seconds": 47.278}, {"script": "process-entry-cleanup.py", "attempt": 3, "rc": 0, "seconds": 42.963}, {"script": "socket-path-regression.py", "attempt": 1, "rc": 0, "seconds": 215.358}, {"script": "socket-path-regression.py", "attempt": 2, "rc": 0, "seconds": 223.362}, {"script": "socket-path-regression.py", "attempt": 3, "rc": 0, "seconds": 243.736}]；日志目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/orphan-audit-evidence，standalone.exit=0；三个脚本稳定通过，可以接入默认并发清单。
working: 2026-10-04T13:44:19Z 阶段2完成：默认清单12→15项，每项显式bash/python3解释器；启动前只读引用图自检覆盖39文件，仅豁免e2e-real.sh/e2e-real.py；孤儿示例原始rc=1、stdout为空、stderr点名且说明三种合规方式，启动前无新增目录；快门rc=0，bash -n + shellcheck rc=0且无告警。为消除已复现的跨测试目录误判，入口清理回归改为仓内短路径git archive HEAD独立导出，原断言AST逐项相同；理由和反例见directory-race-before.json。
working: 2026-10-04T13:51:39Z 阶段3进行中：第一轮 bash tests/collab-all.sh rc=0，15 PASS/0 FAIL，276.728s，末行COLLAB-ALL PASS（15 项），三个新增脚本均有PASS；new_directories=[]、removed_directories=[]、residual_processes=[]、rm_lines=[]，原始日志与回执 .qwb-tmp/orphan-audit-evidence/collab-1.{log,json,exit}；第二轮已自动启动。
working: 2026-10-04T13:57:33Z 阶段3本轮验收结束：bash tests/collab-all.sh 第1轮rc=0/15项PASS/276.728s，第2轮rc=1/14项PASS+1项FAIL/339.379s；第2轮原始PASS行数19（包含失败项打印出的5条内部PASS日志），FAIL行数1，末行COLLAB-ALL FAIL（1/15 项）；三个新增脚本两轮均PASS；原始日志collab-2.log和回执collab-2.{json,exit}位于/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/orphan-audit-evidence；两轮残留进程、新增/删除目录、rm:行均为空。
needs-decision: 2026-10-04T13:57:33Z 范围外既有 tests/collab-handoff.sh 失败：stdin第98行 watch.communicate(timeout=3)，等待 bash bin/qwb-wake.sh --block --max-ms 500 触发 subprocess.TimeoutExpired（3秒）；相同候选SHA256第一轮通过第二轮失败，未改源码/断言/超时。该文件不在本票白名单，无法在票内修复或放宽；请主控裁定既有时序失败后再恢复三连全绿验收。未进行第3轮、强制失败场景、提交与提交后full门，不宣称完成。
blocked: 2026-10-04T13:57:33Z STOP：三连全绿被范围外 collab-handoff.sh 的3秒监督等待超时阻塞。保留隔离副本内两个白名单文件WIP；HEAD仍为68d0e631e429dd60c548ea20f9fddbd4dd36f0b8；git status --short=" M tests/collab-all.sh\n M tests/process-entry-cleanup.py\n"；本人记录的存活测试进程=[]，临时目录仅保留orphan-audit-evidence证据，孤儿示例已删除，无tests/__pycache__；完整收据blocked-final.json。主账本只追加，state字段未改。
working: 2026-10-04T13:59:40Z 主控处置（回应 13:57:33Z 的 blocked）并修订规格：tests/collab-handoff.sh 第 148 行一带的 3 秒是测试夹具「等值守结束」的保险上限，不是产品时序断言；并发项数增加加上当时主控正在 main 上跑全门（全机负载约 9），它不够用了。工程规格新增第 6 条、白名单增加 tests/collab-*.sh（只许改等待上限的数值）：把这类等待上限放宽到不少于 20 秒，时序断言不动，逐处列表说明。本票恢复执行；三连全绿仍是验收条件，主控的全门大约 10 分钟内结束，之后负载会回落。
working: 2026-10-04T14:06:36Z 已完整重读新增工程规格6与13:59:40Z主控裁定，恢复执行；修正先前“既有时序失败”的表述：handoff 3秒是夹具等待保险，产品断言仍为值守退出124。逐处判定并修改32处保险数值：wait/communicate/run/join/握手/就绪屏障统一至少20秒；6个collab脚本除数值外逐字节相同，新接入脚本断言除获准timeout参数外AST相同。保留latency<10、断流送达deadline15、短锁<60、产品max-ms、5秒清理观察窗口、5秒communicate切片及20/90/120/60秒既有保险；明细timeout-changes.json，最终done逐项报告。快门rc=0，bash -n+shellcheck rc=0无告警；开始新候选独立连续三轮，保留原失败日志不覆盖。
working: 2026-10-04T14:09:15Z 工程规格6判定阶段完成：timeout-inventory.log记录rg完整原始扫描，timeout-decisions.json逐处列出33处已放宽保险和16条保留规则；上条working写“32处”为计数笔误，以本条33处及逐项JSON为准。共修改9个白名单文件；仅新增6个collab脚本数值改动及process-fixture-check保险数值，三轮在冻结候选上执行，日志前缀collab-resumed-。
working: 2026-10-04T14:15:56Z 新候选三连验收第1轮完成：bash tests/collab-all.sh rc=0，15 PASS/0 FAIL，416.732s；三个新增脚本均PASS，原handoff失败路径本轮自然成功；末行COLLAB-ALL PASS（15 项），rm_lines/new_directories/removed_directories/residual_processes全部=[]；独立回执collab-resumed-1.{log,json,exit}，第2轮已经自动启动。
working: 2026-10-04T14:19:58Z 新候选三连验收第2轮完成：bash tests/collab-all.sh rc=0，15 PASS/0 FAIL，309.664s，末行COLLAB-ALL PASS（15 项）；三个新增脚本均PASS，rm_lines/new_directories/removed_directories/residual_processes全部=[]；回执collab-resumed-2.{log,json,exit}，第3轮已自动启动；旧13:57红门证据仍保留。
working: 2026-10-04T14:26:09Z 阶段3三连全绿完成：同一冻结候选连续命令bash tests/collab-all.sh，三次rc=[0,0,0]、每次15 PASS/0 FAIL、耗时[416.732,309.664,372.318]秒；每轮三个新增脚本都PASS、末行15项、无rm:行；各轮new_directories/removed_directories/residual_processes均=[]。原始回执collab-resumed-1/2/3.{log,json,exit}和collab-resumed-series.exit=0；恢复后原handoff夹具退出保险没有再误报。
working: 2026-10-04T14:32:10Z 阶段4失败场景首次夹具准备不足已定位：纯git archive临时副本不含.git，ROOT里的read-only git archive会按原仓子目录前缀导出空内容/无法读bea487d历史，导致额外roles失败和entry-cleanup rc127；首轮原始rc1/3 FAIL已归档*.attempt-1，残留=[]。只在本票.qwb-tmp临时副本复制原gitfile为0400以保留历史读取上下文；只读预检--show-toplevel为临时副本且HEAD archive包含bin/qwb-wake.sh；原候选哈希不变、原索引为空。重新执行强制socket回归rc7，验收要求仍为14 PASS+1 FAIL，不改源码或断言。
working: 2026-10-04T14:37:43Z 阶段4四场景全部完成：三连正常rc0各15 PASS；孤儿示例在启动前rc1/stdout空/点名并说明三种合规方式，删除后恢复；39文件只读引用/豁免自检通过；临时副本强制socket脚本退出7，最终COLLAB-ALL rc1、14 PASS/1 FAIL、日志打印故意失败标记，其余项全部自然通过，场景断言rc0/285.081s。临时拷贝、纯图fixture和git-context实验目录已按确切路径回收；原索引为空、候选9文件哈希未变。准备提交后执行规定full门。
working: 2026-10-04T14:38:28Z 阶段5提交完成：sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72；英文单行提交Connect orphan regressions and validate test entry coverage，仅9个白名单文件，提交前候选SHA256与三连/四场景冻结对象相同，git status --short为空；未建分支或push。开始提交后命令bash bin/qwb-test.sh full，日志/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/orphan-audit-evidence/full-postcommit.log，结束后核退出码/PASS/FAIL/末尾6行/状态/残留。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 全部工程规格和四个场景完成；提交仅含9个获准文件。默认清单15项，解释器显式指定；只读入口图自检覆盖39文件，豁免仅2个具名付费手工入口。主账本仅追加，state字段未改，无真实Herdr写操作、建分支或push。证据根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/orphan-audit-evidence
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 规格1原始单跑命令=python3 -B tests/process-fixture-check.py；连续3次原始回执=[{"script":"process-fixture-check.py","attempt":1,"rc":0,"seconds":1.778},{"script":"process-fixture-check.py","attempt":2,"rc":0,"seconds":1.822},{"script":"process-fixture-check.py","attempt":3,"rc":0,"seconds":1.79}]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 规格1原始单跑命令=python3 -B tests/process-entry-cleanup.py；连续3次原始回执=[{"script":"process-entry-cleanup.py","attempt":1,"rc":0,"seconds":43.758},{"script":"process-entry-cleanup.py","attempt":2,"rc":0,"seconds":47.278},{"script":"process-entry-cleanup.py","attempt":3,"rc":0,"seconds":42.963}]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 规格1原始单跑命令=python3 -B tests/socket-path-regression.py；连续3次原始回执=[{"script":"socket-path-regression.py","attempt":1,"rc":0,"seconds":215.358},{"script":"socket-path-regression.py","attempt":2,"rc":0,"seconds":223.362},{"script":"socket-path-regression.py","attempt":3,"rc":0,"seconds":243.736}]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 目录并发误判根因：共享BASE快照受其他测试创建/删除目录影响；仅在入口清理回归增加本次拥有的短路径git archive HEAD导出，不移除进程/socket夹具。原反例directory-race-before rc=1、temporary directory survived；同反例修复后rc=0/42.659s。TERM正常只发给自建Popen；失败清理仅限已记录自身后代/自身wire PID。原断言除新增授权等待保险参数外AST保持相同。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 正常路径第1轮命令=bash tests/collab-all.sh；原始结果={"command":["bash","tests/collab-all.sh"],"rc":0,"seconds":416.732,"pass_lines":15,"fail_lines":0,"rm_lines":[],"tail":["PASS  tests/lint-scenario-stream.sh（5s）","PASS  tests/path-canonicalization.sh（0s）","PASS  tests/process-fixture-check.py（3s）","PASS  tests/process-entry-cleanup.py（68s）","PASS  tests/socket-path-regression.py（379s）","COLLAB-ALL PASS（15 项）"],"new_directories":[],"removed_directories":[],"residual_processes":[],"observed_processes":6748,"git_status":" M tests/collab-all.sh\n M tests/collab-handoff.sh\n M tests/collab-herdr.sh\n M tests/collab-land.sh\n M tests/collab-ledger.sh\n M tests/collab-planning.sh\n M tests/collab-posture.sh\n M tests/process-entry-cleanup.py\n M tests/process-fixture-check.py\n"}；三个新增脚本均有独立PASS行，末行COLLAB-ALL PASS（15 项）
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 正常路径第2轮命令=bash tests/collab-all.sh；原始结果={"command":["bash","tests/collab-all.sh"],"rc":0,"seconds":309.664,"pass_lines":15,"fail_lines":0,"rm_lines":[],"tail":["PASS  tests/lint-scenario-stream.sh（5s）","PASS  tests/path-canonicalization.sh（0s）","PASS  tests/process-fixture-check.py（2s）","PASS  tests/process-entry-cleanup.py（76s）","PASS  tests/socket-path-regression.py（273s）","COLLAB-ALL PASS（15 项）"],"new_directories":[],"removed_directories":[],"residual_processes":[],"observed_processes":6325,"git_status":" M tests/collab-all.sh\n M tests/collab-handoff.sh\n M tests/collab-herdr.sh\n M tests/collab-land.sh\n M tests/collab-ledger.sh\n M tests/collab-planning.sh\n M tests/collab-posture.sh\n M tests/process-entry-cleanup.py\n M tests/process-fixture-check.py\n"}；三个新增脚本均有独立PASS行，末行COLLAB-ALL PASS（15 项）
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 正常路径第3轮命令=bash tests/collab-all.sh；原始结果={"command":["bash","tests/collab-all.sh"],"rc":0,"seconds":372.318,"pass_lines":15,"fail_lines":0,"rm_lines":[],"tail":["PASS  tests/lint-scenario-stream.sh（7s）","PASS  tests/path-canonicalization.sh（0s）","PASS  tests/process-fixture-check.py（3s）","PASS  tests/process-entry-cleanup.py（91s）","PASS  tests/socket-path-regression.py（314s）","COLLAB-ALL PASS（15 项）"],"new_directories":[],"removed_directories":[],"residual_processes":[],"observed_processes":6641,"git_status":" M tests/collab-all.sh\n M tests/collab-handoff.sh\n M tests/collab-herdr.sh\n M tests/collab-land.sh\n M tests/collab-ledger.sh\n M tests/collab-planning.sh\n M tests/collab-posture.sh\n M tests/process-entry-cleanup.py\n M tests/process-fixture-check.py\n"}；三个新增脚本均有独立PASS行，末行COLLAB-ALL PASS（15 项）
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 孤儿失败路径命令=bash tests/collab-all.sh；临时tests/zz-orphan-example.sh包含执行哨兵，原始结果={"command":["bash","tests/collab-all.sh"],"rc":1,"stdout":"","stderr":"错误：以下测试文件没有入口：\n  tests/zz-orphan-example.sh\n请加入 collab-all.sh 默认清单、由 smoke.sh/qwb.config.sh 门命令或已有入口测试按文件名引用，或加入显式豁免名单并逐项说明理由。\n","new_directories":[]}；没有执行哨兵或启动测试，没有建立跑批目录；示例按确切路径删除，删除后只读自检及三轮正常路径通过。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 引用/豁免路径：collab-all启动前嵌入的python3 -B只读自检输出“测试入口自检 PASS（39 个文件）”；下一组按每个文件列出合规依据，原始映射entry-coverage.json。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/boundary-readiness.sh":"被 tests/smoke.sh 引用","tests/collab-all.sh":"qwb.config.sh 门命令引用","tests/collab-ci-diagnostics.sh":"默认清单","tests/collab-gate.sh":"默认清单","tests/collab-handoff.sh":"默认清单","tests/collab-herdr.sh":"默认清单","tests/collab-land.sh":"默认清单"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/collab-ledger.sh":"默认清单","tests/collab-planning.sh":"默认清单","tests/collab-posture.sh":"默认清单","tests/collab-roles.sh":"默认清单","tests/collab-test-policy.sh":"默认清单","tests/e2e-controllers-cli.py":"被 tests/smoke.sh 引用","tests/e2e-real.py":"豁免：付费手工验收实现，仅由手工入口调用"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/e2e-real.sh":"豁免：连接真实 Herdr、启动付费模型的手工验收入口","tests/fixtures/herdr/snapshot.py":"被 tests/smoke.sh 引用","tests/fixtures/herdr/wire-server.py":"被 tests/process-entry-cleanup.py 引用","tests/invalid-ledger.py":"被 tests/smoke.sh 引用","tests/lifecycle-readiness.sh":"被 tests/smoke.sh 引用","tests/lint-scenario-stream.sh":"默认清单","tests/on-demand-guide.py":"被 tests/smoke.sh 引用"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/optional-routing.sh":"被 tests/smoke.sh 引用","tests/path-canonicalization.sh":"默认清单","tests/pi-ext.test.mjs":"被 tests/smoke.sh 引用","tests/pi-profile.sh":"被 tests/collab-roles.sh 引用","tests/process-entry-cleanup.py":"默认清单","tests/process-fixture-check.py":"默认清单","tests/process-fixture.sh":"被 tests/collab-gate.sh 引用"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/process_fixture.py":"被 tests/process-fixture-check.py 引用","tests/r2-cli.py":"被 tests/smoke.sh 引用","tests/r4-cli.py":"被 tests/smoke.sh 引用","tests/review-identity.sh":"qwb.config.sh 门命令引用","tests/runtime-readiness.sh":"被 tests/smoke.sh 引用","tests/smoke.sh":"smoke 入口","tests/socket-path-regression.py":"默认清单"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 每个文件入口依据={"tests/subscribe-reap.py":"被 tests/smoke.sh 引用","tests/wake-block-output.sh":"被 tests/smoke.sh 引用","tests/worker-config.py":"被 tests/smoke.sh 引用","tests/worktree-space.py":"被 tests/collab-herdr.sh 引用"}
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 强制回归失败路径：在本副本.qwb-tmp下的短路径源码临时拷贝叠加全部9个WIP文件，仅令socket-path-regression.py打印INTENTIONAL SOCKET REGRESSION FAILURE并退出7。命令与原始结果={"command":["bash","/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/68/tests/collab-all.sh"],"rc":1,"seconds":285.081,"pass_lines":14,"fail_lines":1,"rm_lines":[],"tail":["PASS  tests/path-canonicalization.sh（0s）","PASS  tests/process-fixture-check.py（2s）","PASS  tests/process-entry-cleanup.py（62s）","FAIL  tests/socket-path-regression.py（rc=7，0s）","INTENTIONAL SOCKET REGRESSION FAILURE","COLLAB-ALL FAIL（1/15 项）"],"new_directories":[],"removed_directories":[],"residual_processes":[],"observed_processes":4831,"git_status":" M tests/collab-all.sh\n M tests/collab-handoff.sh\n M tests/collab-herdr.sh\n M tests/collab-land.sh\n M tests/collab-ledger.sh\n M tests/collab-planning.sh\n M tests/collab-posture.sh\n M tests/process-entry-cleanup.py\n M tests/process-fixture-check.py\n"}；对应FAIL行rc=7且打印标记，其余14项PASS，末行COLLAB-ALL FAIL（1/15 项），场景断言rc=0；临时拷贝已精确删除，不提交。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 强制失败场景夹具上下文补证：首次纯archive拷贝缺.git，历史源码读取和二次导出失败，原始COLLAB-ALL FAIL（3/15 项）保留在forced-failure.{log,json,exit}.attempt-1；随后给临时拷贝复制0400 gitfile，--show-toplevel读取确认临时根、历史archive恢复，重跑达到14 PASS+1 FAIL；原候选SHA256与索引均未变，未修改正式测试源码来迁就夹具。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 工程规格6：逐处扫描命令=["rg","-n","-F","-e","timeout=","-e","deadline","-e","settimeout","-e",".wait(","-e","for _ in {","tests/collab-all.sh","tests/collab-ci-diagnostics.sh","tests/collab-gate.sh","tests/collab-handoff.sh","tests/collab-herdr.sh","tests/collab-land.sh","tests/collab-ledger.sh","tests/collab-planning.sh","tests/collab-posture.sh","tests/collab-roles.sh","tests/collab-test-policy.sh","tests/process-fixture-check.py","tests/process-entry-cleanup.py","tests/socket-path-regression.py"]；原始扫描timeout-inventory.log。33处不足20秒的等待保险统一放宽；6个新增collab文件全部只改数值，产品时序和固定窗口不动，未增加固定sleep；正常等待仍结束即返回，逐项实际耗时已保存在三轮原始PASS行及回执中。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-handoff.sh:148；out,err=watch.communicate(timeout=3) → out,err=watch.communicate(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-handoff.sh:153；if watch.poll() is None: os.killpg(watch.pid,signal.SIGTERM); watch.wait(timeout=3) → if watch.poll() is None: os.killpg(watch.pid,signal.SIGTERM); watch.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:121；api.close(); thread.join(timeout=1) → api.close(); thread.join(timeout=20)；判断=停止假服务线程后的回收保险；线程完成即返回
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:163；child.communicate('exit\n',timeout=10); assert child.returncode==0 → child.communicate('exit\n',timeout=20); assert child.returncode==0；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:166；if child.poll() is None: child.terminate(); child.wait(timeout=10) → if child.poll() is None: child.terminate(); child.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:198；assert writer.wait(timeout=10)==0 → assert writer.wait(timeout=20)==0；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:201；if writer.poll() is None: writer.terminate(); writer.wait(timeout=10) → if writer.poll() is None: writer.terminate(); writer.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:214；old.stdin.write('continue\n'); old.stdin.flush(); assert old.wait(timeout=10)==0 → old.stdin.write('continue\n'); old.stdin.flush(); assert old.wait(timeout=20)==0；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:223；if old.poll() is None: old.terminate(); old.wait(timeout=10) → if old.poll() is None: old.terminate(); old.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:236；child.communicate('exit\n',timeout=10); assert child.returncode==0 → child.communicate('exit\n',timeout=20); assert child.returncode==0；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-land.sh:249；if child.poll() is None: child.terminate(); child.wait(timeout=10) → if child.poll() is None: child.terminate(); child.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:43；server=socket.socket(socket.AF_UNIX); server.bind(sockpath); server.listen(); server.settimeout(8) → server=socket.socket(socket.AF_UNIX); server.bind(sockpath); server.listen(); server.settimeout(20)；判断=假Unix服务accept或读请求的I/O防挂死保险
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:58；got=subprocess.run(wake+['--block','--max-ms','12000'],env=env,capture_output=True,text=True,timeout=15) → got=subprocess.run(wake+['--block','--max-ms','12000'],env=env,capture_output=True,text=True,timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:60；server.close(); thread.join(timeout=1) → server.close(); thread.join(timeout=20)；判断=停止假服务线程后的回收保险；线程完成即返回
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:76；return subprocess.run(list(args),env=env,capture_output=True,text=True,timeout=10) → return subprocess.run(list(args),env=env,capture_output=True,text=True,timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:231；stop.set(); thread.join(timeout=1); api.close() → stop.set(); thread.join(timeout=20); api.close()；判断=停止假服务线程后的回收保险；线程完成即返回
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:261；r=subprocess.run(['bash',str(ROOT/'bin'/script),cmd,'--project',str(p),'--task',str(t),*args],env=env,capture_output=True,text=True,timeout=15) → r=subprocess.run(['bash',str(ROOT/'bin'/script),cmd,'--project',str(p),'--task',str(t),*args],env=env,capture_output=True,text=True,timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:266；prime=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=15); assert prime.returncode==0,prime.stderr → prime=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=20); assert prime.returncode==0,prime.stderr；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:276；c.settimeout(2); req=json.loads(c.makefile('rb').readline()); requests.append(req); count+=1 → c.settimeout(20); req=json.loads(c.makefile('rb').readline()); requests.append(req); count+=1；判断=假Unix服务accept或读请求的I/O防挂死保险
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:288；assert disconnected.wait(8),'subscription was not established' → assert disconnected.wait(20),'subscription was not established'；判断=阶段开始前的订阅/重连握手就绪保险；布尔就绪断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:289；duplicate=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=10) → duplicate=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:300；latency=time.monotonic()-start; reconnect.set(); assert connected.wait(8),'not reconnected' → latency=time.monotonic()-start; reconnect.set(); assert connected.wait(20),'not reconnected'；判断=阶段开始前的订阅/重连握手就绪保险；布尔就绪断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:310；owner.terminate(); out,err=owner.communicate(timeout=15) → owner.terminate(); out,err=owner.communicate(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:312；stop.set(); thread.join(timeout=3); api.close() → stop.set(); thread.join(timeout=20); api.close()；判断=停止假服务线程后的回收保险；线程完成即返回
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-herdr.sh:314；timed=subprocess.run(wake+['--block','--max-ms','150'],env=env,capture_output=True,text=True,timeout=10) → timed=subprocess.run(wake+['--block','--max-ms','150'],env=env,capture_output=True,text=True,timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-posture.sh:221；reader=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','status','--project',str(p)],env=env,capture_output=True,text=True,timeout=5) → reader=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','status','--project',str(p)],env=env,capture_output=True,text=True,timeout=20)；判断=控制器锁保持时并发reader完成的防挂死保险；锁序与成功结果断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-posture.sh:225；out,err=change.communicate(timeout=5) → out,err=change.communicate(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-planning.sh:121；try: out,err=process.communicate(timeout=3) → try: out,err=process.communicate(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/collab-ledger.sh:126；for _ in {1..400}; do [[ -s "$1" ]] && return 0; sleep 0.01; done → for _ in {1..2000}; do [[ -s "$1" ]] && return 0; sleep 0.01; done；判断=等待夹具就绪文件的保险；400×0.01秒改为2000×0.01秒，正常就绪即返回
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/process-fixture-check.py:44；deadline = time.monotonic() + 5 → deadline = time.monotonic() + 20；判断=等待被测子进程pidfile就绪的保险；截止5秒改20秒
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/process-fixture-check.py:50；assert process.wait(timeout=8) == 143 → assert process.wait(timeout=20) == 143；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/process-fixture-check.py:57；process.wait(timeout=8) → process.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 等待保险调整 tests/process-entry-cleanup.py:108；process.wait(timeout=10) → process.wait(timeout=20)；判断=等待调用/子进程自然退出或TERM后排空的防挂死保险；退出码与状态断言保留
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-planning.sh:90；bound=20 if target else 90；判断=CLI整体等待保险已至少20秒；匹配行=[90]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-planning.sh:105；timeout=min(5,remaining)；判断=5秒为捕获超时后继续的诊断轮询切片；最终保险仍20/90秒；匹配行=[105]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-gate.sh:342；deadline=time.monotonic()+30；判断=长门启动就绪保险已至少20秒；匹配行=[342]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-gate.sh:366；communicate(timeout=30)；判断=长门退出回收保险已至少20秒；匹配行=[366]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-gate.sh:268；while time.time()<=receipt ended_at（另见282行）；判断=严格跨秒收据排序条件，不是防挂死等待上限；匹配行=[268]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-test-policy.sh:60；timeout=120；判断=公共CLI防挂死保险已至少20秒；匹配行=[60]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/process-entry-cleanup.py:54；deadline=monotonic()+60；判断=每个入口的整体防挂死保险已至少20秒；匹配行=[54]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-herdr.sh:62；latency<10；判断=产品通知延迟的时序断言，保留；匹配行=[62]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-herdr.sh:294；deadline=monotonic()+15；判断=断流期间真实事实须15秒内送达的时序验证，保留；匹配行=[294]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-land.sh:298；monotonic()-start<60；判断=真实短锁竞争必须及时拒绝的时序断言，保留；匹配行=[298]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-herdr.sh:113；api.settimeout(.2)（另见267行）；判断=假服务循环的stop轮询切片，非整体失败上限；匹配行=[113,267]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-herdr.sh:277；reconnect.wait(1)；判断=刻意保持断流直到主线程释放重连，每秒重试而非到点失败；匹配行=[277]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-herdr.sh:283；stop.wait(5)；判断=保持重连后的连接供固定观察窗口使用，非退出保险；匹配行=[283]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/process-entry-cleanup.py:92；time.sleep(5)；判断=TERM后观察残留的固定窗口，不放宽也不缩短；匹配行=[92]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/collab-handoff.sh:142；--max-ms 500；退出124；判断=产品等待预算与终态断言，保留；其他产品max-ms 1/12000/150同样保留；匹配行=[142]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 保留判定 tests/socket-path-regression.py:1；无timeout=或轮询截止时间；判断=没有本票需修改的等待上限；匹配行=[1]
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 快门命令=bash bin/qwb-test.sh fast，rc=0；静态门命令=bash -n tests/collab-all.sh && shellcheck tests/collab-all.sh，rc=0且无告警；git diff --check通过，额外核对所有numeric-only脚本在/bin/bash 3.2下语法通过。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 提交后全门命令=bash bin/qwb-test.sh full；stdout/stderr重定向=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests/.qwb-tmp/orphan-audit-evidence/full-postcommit.log；原始退出码=0，PASS行数=843，FAIL行数=0；末尾6行各前100字符=["PASS  tests/lint-scenario-stream.sh（5s）","PASS  tests/path-canonicalization.sh（0s）","PASS  tests/process-fixture-check.py（3s）","PASS  tests/process-entry-cleanup.py（66s）","PASS  tests/socket-path-regression.py（242s）","COLLAB-ALL PASS（15 项）"]；全门后git status --short原始输出=""；残留进程清单=[]；新增/删除目录=[[],[]]；rm:行=[]；仅保留明确证据目录，无孤儿示例或字节码。
done: 2026-10-04T14:52:49Z sha=b50d37d498a6209698625d43a4e1c5ca5ea16e72 此前collab-2红门保留：rc=1/14项PASS+1项FAIL，handoff communicate(timeout=3)触发夹具保险；按主控13:59:40Z明确裁定扩展授权解决后重新三连全绿，未把旧红门写成绿。最终提交=b50d37d498a6209698625d43a4e1c5ca5ea16e72，detached HEAD候选留给主控审核，工作目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-orphan-tests，未擅自合并/回收主控创建的副本。
working: 2026-10-04T15:04:14Z 主控验收（只动测试，按分级走）：提交 b50d37d cherry-pick 到 main，与 audit-death-proof 对 tests/collab-herdr.sh 的改动自动合并无冲突；collab-all.sh 审过（默认清单 15 项、每项显式写解释器；启动前自检；豁免名单仅两个付费的真机验收入口），bash 与 /bin/bash 语法检查及 shellcheck 通过；主控亲手验证：在 tests/ 下新建一个无入口的 zz-orphan-example.sh，bash tests/collab-all.sh 在启动任何测试前 rc=1 并点名该文件，删除后恢复。合并后 main（HEAD=d94329b，含 audit-death-proof 与 audit-readme-refresh）全门：rc=0、844 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（15 项）全过、456.58s、无 rm 报错、无残留进程、工作区无改动。执行者逐处判定的等待上限清单（33 处放宽、16 处保留）在其证据文件里，随副本清理一并移除。
