# 任务书：全门里互不相干的两大段并发跑，把总时长压到起点以下

```
任务 id:  audit-gate-parallel
state: verified
implementation-authorized: Rocky 2026-10-04 问「全门这个合理吗」（指全门比起点更长）；此前已委托「还是你定」
dispatch-budget: 3
来源:     全仓审核 r1 收口后的遗留（docs/reviews/2026-10-03-qwb-full-audit-r1.md「最终实测」）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-gate-parallel.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-parallel（隔离副本，detached HEAD，起点 main 47de4b6）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。他看到收口报告里「全门从约 390 秒变成 457–574 秒」，问这是否合理。

不完全合理。把 15 个测试接进门是对的，但现在的全门是**串行**的四段：

    bash tests/smoke.sh && bash tests/review-identity.sh && bash bin/qwb-lint.sh && bash tests/collab-all.sh

主控在 `main` 上实测（负载约 2–4）：smoke 单独约 190 秒；`tests/collab-all.sh` 约 262 秒，由最慢的两项决定——`tests/collab-gate.sh` 262 秒、`tests/socket-path-regression.py` 247 秒；review-identity 与 lint 合计几秒。总计约 457 秒。smoke 与 collab-all 互不依赖、各用各的临时目录与进程组，却排着队跑，白白多等了一个 smoke 的时间。

白名单：`qwb.config.sh`、`tests/` 下的文件（可新增一个全门入口脚本）、`README.md` 与 `README.zh.md`（只改描述全门怎么跑的那一两句与相应数字）。

### 工程规格

1. **全门改成 smoke 与 collab-all 并发跑**，review-identity 与 lint 照旧（它们只要几秒，放在哪都行）。任何一段失败，全门退出码非 0；一段失败不得中止另一段的运行与汇报。
2. **输出仍然可读、可核对**：各段的输出不许交错。先收齐、再按固定顺序整段打印（smoke → review-identity → lint → collab-all），每段的内容与单独跑时逐行相同；末尾仍有各段原有的收尾行（`SMOKE PASS`、`REVIEW-IDENTITY PASS`、`LINT PASS`、`COLLAB-ALL PASS（N 项）`）与 `qwb-test.sh` 的「门失败」提示。全门输出里 `^PASS` 与 `^FAIL` 的行数与现在一致（主仓 844 / 0）。
3. 实现形式自己定并在 `working:` 行说明理由：可以新增一个 `tests/` 下的全门入口脚本、把 `QWB_GATE_FULL` 指向它；也可以直接改门命令。注意：
   - `bin/qwb-lint.sh` 第 3 项要求 `qwb.config.sh` 与不入库的 `qwbuddy/config.sh` 的门命令一致，后者由主控落地时同步——把新门命令的整行原文写进 `done:` 行。
   - `tests/collab-all.sh` 的入口自检要求 `tests/` 下每个文件都有入口；新增的脚本要被门命令引用到。
   - 被 INT/TERM 打断时，两段的进程都要被回收，不留孤儿、不留临时目录。
4. **并发安全由你证明**：两段同时跑时 CPU 与进程数都更高，对时间敏感的用例可能变脆。连续跑 5 次全门必须全绿。有偶发失败就定位到具体用例：属于「测试夹具的等待上限不够」的，按既有口径放宽（不少于 20 秒；真正断言产品时序的不动）；属于两段共享了某个资源的，修掉共享。不许用「失败就重试整段」来掩盖。
5. **顺带压最慢的两项（能做就做，不能确认安全就跳过并写明）**：`tests/socket-path-regression.py` 247 秒、`tests/collab-gate.sh` 262 秒决定了并发跑批的下限。先量清它们各自的时间花在哪（真等待、重复搭建、重复跑整份 smoke？），在不改断言、不删用例的前提下去掉浪费。例如 socket-path-regression 如果是把整份 smoke 在别的路径下重跑，看能否只跑到它要验证的那一步。
6. README 两份里描述全门的句子（「全门依次运行 …」及英文对应句）与耗时数字相应更新，数字用你在本副本实测的并注明提交与负载。

## 1. 验收场景

### user_正常路径_全门更快且结果不变

Given 起点提交与改后提交，同一台机器、相近负载（记下每次跑前的 `uptime`）
When  各跑 3 次 `bash bin/qwb-test.sh full`，新旧背靠背交替
Then  改后全门最小耗时不超过 300 秒，且不超过起点的 70%；两边 PASS 行数相同、FAIL 为 0；把两边输出按段拆开，各段的节标题与 PASS/FAIL 行按序逐行相同（路径、哈希、耗时数字归一化后）

### user_失败路径_任一段失败全门都红且另一段照常汇报

Given 在临时拷贝里分别让 smoke 的一条断言、collab-all 的一项必然失败（不提交）
When  跑全门
Then  两种情况退出码都非 0，失败的那一段照原样报出 FAIL 与其收尾行，另一段完整跑完并照常汇报，末尾有「门失败」提示

### user_失败路径_被中断时不留孤儿

Given 全门跑到两段都在进行中
When  对它发 TERM
Then  5 秒后没有任何命令行含本副本路径的测试进程存活，`.qwb-tmp/` 下不留本次的目录，`git status --short` 无输出

### user_失败路径_连续多次不偶发

Given 改后提交
When  连续跑 5 次全门
Then  5 次都退出码 0、PASS 行数相同；报出 5 次各自的耗时与跑前负载。有任何一次失败，按规格第 4 条定位并修复后重新连跑 5 次

### user_正常路径_快门与各段单独跑不受影响

Given 改后提交
When  跑 `bash bin/qwb-test.sh fast`、单独跑 `bash tests/smoke.sh`、单独跑 `bash tests/collab-all.sh`
Then  三者的行为、输出与退出码与起点相同（collab-all 若因规格第 5 条变快，只有耗时不同）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；不要移除或绕过测试的失效关闭隔离、进程登记夹具、socket 路径夹具与入口自检。
- 不删、不跳过、不合并任何断言；不改 `bin/` 与 `templates/`。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。并发改造、压最慢两项、README 分成各自的提交。
- 兼容 macOS 自带 `/bin/bash` 3.2（不用 `wait -n`、关联数组、`mapfile`）。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；把变量喂给会提前退出的命令用 here-string，不用管道。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`；新增或改动的 shell 脚本另跑 `bash -n`、`/bin/bash -n` 与 `shellcheck`，不得有告警。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行；全门各次的耗时与跑前负载列成表。
- `done:` 行写新门命令的整行原文、最终一次全门的退出码、PASS 行数、FAIL 行数、末尾 6 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `bin/qwb-test.sh`（它只负责执行门命令并报告退出码）、不改 `bin/` 其他脚本、不改 `templates/config.sh`（那是别的项目各自的门）。
- 不把协作测试再拆出全门，不降低任何一段的覆盖。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T17:33:35Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-gate-parallel pane=w14Z:pQ dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-parallel base=47de4b6
working: 2026-10-04T17:35:18Z 执行者完成规格与点名审核报告阅读；实现选新增 tests/full-gate.sh 并令 QWB_GATE_FULL 引用：复用 process-fixture.sh 的监督/进程组回收，四段独立日志收齐后按 smoke→review-identity→lint→collab-all 打印，任段失败仍等待其余段；慢项先实测，socket 正例已是 root-tab-missing 窄入口，不重复整份 smoke。
working: 2026-10-04T17:42:28Z 并发入口阶段提交完成；新增入口与 review-identity 的 bash/-bin-bash 语法及 ShellCheck 均 rc=0，fast rc=0；持久回归接在既有 process-entry-cleanup.py，bash 与 /bin/bash 的成功、smoke失败、collab失败、TERM 八例均满足顺序输出、失败透传与零目录残留，不新增外层 PASS 行。基线首轮导出夹具缺陷导致空 archive，已修正，保留无效轮日志并重测。
working: 2026-10-04T17:56:02Z 真实 TERM 发现旧跑批递归终止令监督器来不及清理，以及旧夹具目录在监督范围外；已修为通知登记 PID 并等待监督器结束，各旧夹具进入现有 scope，Python 入口 exec 监督器，socket 导出受 scope 保护。第三次真实 /bin/bash 全门 TERM 验收 rc=143，5秒后进程=[]、新增目录=[]；定向八例与所有改动 shell 的 bash/-bin-bash -n、ShellCheck、fast 均 rc=0。清理与 socket 并发各自独立提交，性能/稳定性验收仍进行中。
working: 2026-10-04T18:00:16Z 慢项核查完成：collab-gate 逐 subprocess.run 记录239次调用，总调用227.62秒/墙钟232.18秒（所有原断言执行通过；计时夹具退出漏设 QWB_TEST_GROUP 的 KeyError 已单独记录，不作正常门通过证据）；gate-review 33次42.32秒、full真实门11次39.90秒、gate-verdict23次28.87秒；未发现重复整份smoke或可删的无效等待，状态依赖的公开调用不并发、不减断言，跳过该项进一步提速。socket 四个正例改为独立监督下并发收齐再原序汇报，正在用真实全门验证收益。新旧背靠背与五连跑已排队启动，全部结果保留于本副本 .qwb-tmp/audit-evidence.itdqqdzu。
working: 2026-10-04T18:30:47Z 并发预跑 new-preview=378.24秒/rc1/PASS842/FAIL1，唯一失败为 process-entry-cleanup 的 full-smoke TERM 后残留空 scope，不作成功或性能验收证据；定位后补了父子scope目录回执及scope-owner代际校验，真实杀嵌套监督器与保留新owner反例均过。collab改四槽并优先最慢四项，Bash3.2/PATH Bash六任务失败注入均证明max=4、六项全执行、原序五PASS一FAIL；全部原断言保留，完整门将重新测量。基线改为本副本同路径临时还原47de4b6白名单源码字节，结束逐字节还原候选；只读archive由薄exec shim冻结到起点，避免嵌套导出与解释器转交污染。
working: 2026-10-04T19:00:43Z 四槽完整预跑=373.62秒/rc1/PASS842/FAIL1，smoke与gate均通过（gate279秒/socket256秒），排队令总时长超目标；唯一红仍是full-smoke TERM空scope。直接父级目录回执在中间监督器已退出时丢失，已向全部有效祖先登记并保留owner绑定，新增目录差异诊断而不改原断言。改六槽、提前planning与process-entry-cleanup及test-policy/roles；两种Bash八任务机械回归均max6/完成8/原序7PASS1FAIL，fixture检查与ShellCheck/fast退出0；提交f9161cc与3a7e33c，最终全门验收重新开始。
needs-decision: 2026-10-04T19:32:29Z 基线验收条件冲突：本副本同路径逐字节还原47de4b6白名单源码、archive冻结同起点，base1=721.58秒/rc1/PASS842/FAIL1；唯一FAIL仍是旧process-entry-cleanup对full-smoke TERM的空scope残留断言，新版本已修并全门843/0。薄Git转交10次对照direct0.109秒/shim0.125秒，不能解释此红。不能修改起点且要求旧版本三轮FAIL0，两条件无法保证同时满足；建议如实保留旧失败，验收新版本五连绿、失败注入与TERM，性能比较标注旧红。仅阻塞旧版全绿与最终DONE声明，其余授权工作继续。
working: 2026-10-04T19:33:08Z 主控裁决（回应 19:32:29Z 的 needs-decision）：同意。旧版本在高负载下的那一条红如实保留、不要求旧版三轮全绿；性能对比照常给出并标注旧版为红。主控独立核实了同一现象：main 合入 audit-finish-real 后的全门在你并行跑门的负载下 rc=1、843 PASS、唯一 FAIL 同为 process-entry-cleanup 对整份 smoke 发 TERM 后残留空 scope（两个目录各只剩 groups 与 socket-directories），低负载单跑该测试两次均 rc=0。因此这条夹具竞态归本票收口，验收以新版本连续五次全绿、失败注入与 TERM 为准。另：main 已前进到 089b0bd（合入 audit-finish-real 的五个提交 9e86d98..089b0bd），其中改了 tests/process_fixture.py、tests/process-fixture-check.py、tests/process-entry-cleanup.py、tests/worktree-space.py、tests/boundary-readiness.sh、tests/optional-routing.sh、tests/collab-herdr.sh、tests/collab-land.sh。最终候选必须建在 089b0bd 之上：特此授权在本副本执行一次 git rebase 089b0bd（硬约束里的 rebase 禁令仅此一次放开，其余不变）。解决冲突的规则：bin/ 与 templates/ 以 089b0bd 为准不得改动；collab-herdr.sh、collab-land.sh 里对方新增的用例一条不少；夹具的中断清理只保留一套自洽的机制（可以用你的机制取代对方在 process_fixture.py 里的初始化信号延迟，但对方在 process-fixture-check.py 里新增的初始化期 TERM 用例必须保留并通过）。rebase 后重跑五连绿与性能测量，done 行写新的提交 sha。
working: 2026-10-04T19:42:20Z 已按19:33:08Z裁决执行唯一获批的git rebase 089b0bd，最终候选已为其后代；冲突保留main的初始化信号延迟在同一监督器try/finally内，并接入本票祖先scope回执，无双套清理机制。bin/、templates/、collab-herdr.sh、collab-land.sh、boundary-readiness.sh、optional-routing.sh逐文件与089b0bd相同；初始化期真实TERM新增断言完整保留且python3 -B tests/process-fixture-check.py退出0，其余嵌套死亡/新owner保留/六槽八任务原序失败回归均过；fast与全部改动shell的ShellCheck退出0。旧红获准保留，新候选五连绿与性能重新计。
working: 2026-10-04T21:02:57Z rebase后df35774首轮全门rc0/843PASS/0FAIL/485.07秒；五连跑第一轮461.59秒全绿，第二轮505.40秒唯一红为全门TERM后boundary-readiness独立进程组残活，跑批立即停止。已保护有owner回执的监督器不被祖先一秒强杀，新增1.3秒监督清理回归通过，提交2ec6053；collab-herdr八个原Python段与089b0bd逐字节同一，仅独立scope并发/原序打印，全部main新增断言保留，提交2b71aa1，bash与/bin/bash -n、ShellCheck退出0。先单跑Herdr批次再重启五连跑，未以重试掩盖旧红。
working: 2026-10-04T21:20:17Z 主控收口指令：（1）改动范围到此为止，不再新增并发化或提速项；只允许为「五连绿」修当前候选里已暴露的中断清理问题。（2）「全门不超过 300 秒」这条线作废，不再追；以实测为准，由主控按数字决定是否合入。（3）交付物：当前候选连续五次全门的 rc、PASS、FAIL、用时；同一时段新旧各一次的用时对比（旧版红照实标注）；失败注入与 TERM 回归结果；最终提交 sha。（4）主控从现在起不再并行跑全门，机器留给你测，之前的用时受主控并行全门干扰，以此后的测量为准。（5）你的上下文已到 80%：到 90% 之前必须先写一条交接用的 working 行（当前候选 sha、已完成项、未完成项、证据目录），再继续。（6）main 之后又前进了几个提交（值守钩子与文档），不要求你再 rebase，合入时由主控处理。
working: 2026-10-04T21:32:03Z 交接（按21:20:17Z收口指令，在上下文90%前落盘）：当前HEAD=2b71aa16a18b8a05d18bc5ab8719f675405e917a，已在089b0bd之上完成唯一获批rebase；bin/templates未改，main新增断言保留；full命令=QWB_GATE_FULL='bash tests/full-gate.sh'。已完成：固定四段日志原序输出、六槽跑批、socket四正例并发、Herdr八段原代码独立scope并发、初始化TERM/祖先scope代际/监督器清理保护回归；单独Herdr=185.59秒/rc0/86PASS/0FAIL。此前稳定跑批stable1绿461.59秒、stable2红505.40秒（全门TERM后boundary组存活）；修保护后stable-v2-1又红472.01秒（仅socket目录2b/s残留）。当前未提交改动仅tests/process_fixture.py：socket目录加scope-owner，向全部有效祖先登记，屏蔽INT/TERM至登记完成；须先验证再提交。未完成：当前修复后重新五连绿；同一时段新旧各一次实测；真实smoke/collab失败注入；真实TERM五秒零残留/clean；fast+单独smoke/collab；README两句与数字更新独立提交；最终done证据和DONE sha。全部原始日志/退出回执在本副本.qwb-tmp/audit-evidence.itdqqdzu/results.jsonl与各name.log；测量工具measure.py，旧源码测量前必须按新裁决只测一次并如实保留红；stable-v2.py已因失败停止，无活跃跑批。源码原起点47de4b6，性能基线后续用089b0bd同路径白名单字节恢复、Git archive固定源且结束还原；300秒线已作废、禁止再扩大提速范围，主控不再并行跑全门。
working: 2026-10-04T21:57:55Z 重启前停工交接（主控要求立即停止）：当前候选sha=f21b1d032eb88c1533185e490d9beb81836338d9，detached HEAD、基于089b0bd；全部可保留源码已提交，git status --short输出为空，无源码半成品。最新提交socket祖先归属修复已通过process-fixture-check（初始化TERM、强杀嵌套监督、新owner保留、延迟监督清理、六槽失败原序）与fast；未跑其完整全门。当前候选五连跑完成0/5轮。历史轮次必须按候选区分：df35774 stable1=rc0/PASS843/FAIL0/461.59秒，stable2=rc1/PASS842/FAIL1/505.40秒（boundary组中断残活），该跑批已停止并修；2b71aa1 stable-v2-1=rc1/PASS842/FAIL1/472.01秒（全门TERM仅socket目录残留），该跑批已停止，f21b1d0是其修复，不能拼凑为五連绿。rebase后预跑df35774=rc0/PASS843/FAIL0/485.07秒；单独Herdr批次2b71aa1=rc0/PASS86/FAIL0/185.59秒。新旧最终同一时段对比尚未测：旧47de4b6同路径base1=rc1/PASS842/FAIL1/721.58秒，仅属主控并行干扰前历史数据；旧红获裁决保留、300秒线已作废。未完成：f21b1d0五连跑、089b0bd旧版与新候选同一时段各一次、真实smoke/collab失败注入、最终真实TERM五秒零目录进程且clean、单独smoke/collab、README实测数字与并发描述独立提交、最终done证据/DONE。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-parallel/.qwb-tmp/audit-evidence.itdqqdzu（results.jsonl、各name.log、reboot-handoff.json）；测量脚本measure.py的BASE已改089b0bd，same-path-benchmark.py已改旧一次+新五次，git-baseline.c已改089b0bd但native-shim/git尚未重编译，均为不入库的验收脚本草稿，续接前核对；failures.py尚未实际执行。停止核查：全部已登记harness/test PID均已自然退出，无需再发kill；路径进程扫描无测试残留，自己建立的旧源码目录.qwb-tmp/b已按确切路径回收，保留证据目录。已停下，不再启动任何测试。
blocked: 2026-10-04T21:58:13Z 主控交接（Rocky 重启机器，工人已停）：候选 f21b1d0 留在隔离副本 .worktrees/audit-gate-parallel（detached HEAD、基于 089b0bd、工作区干净），未合入 main。main 此后又前进到 5fe2e55 之后（值守钩子 a53942e、41fc0bd 及文档提交），续做时先把候选改到最新 main 之上。尚未完成：候选连续五次全门；同一时段新旧各一次用时；失败注入与 TERM 回归；README 两句。合入标准（主控已定）：300 秒线作废；拿到不受并行干扰的五连绿和新旧对比后再定——提速有限而夹具明显变复杂时，只合「高负载下夹具清理竞态」（F47）的修复，其余不合。在此之前 main 的全门在高负载下会红 tests/process-entry-cleanup.py 一条，低负载单跑通过。续做方式：新开 Pi 会话（magpie codex/gpt-6.1-sol high）进该副本，先读本票最后三条 working 行。
working: 2026-10-04T22:03:54Z 主控重启后续做：仓库、副本（候选 f21b1d0，干净）、远端均完好。先由主控在刚重启的空闲机器上亲测决策用数据：候选全门一次、main（b1a95f6）全门一次、候选再一次，顺序执行、互不并行；据此决定是续做整票还是只取 F47 的夹具修复。
working: 2026-10-04T22:48:36Z 主控实测与裁决（重启后，四次全门顺序执行、互不并行，机器另有日常负载 13–23）：候选 f21b1d0 两次 rc=0、843 PASS / 0 FAIL、383 秒与 440 秒；main b1a95f6 两次 rc=0、844 PASS / 0 FAIL、769 秒与 1044 秒。候选用时为 main 的 42%–50%，且两次全绿、无残留目录。裁决：续做到合入。新执行者按以下顺序收尾，范围冻结，不再做任何新的提速或并发化：（1）特此授权在本副本执行一次 git rebase 到主仓 main 当前提交 b1a95f6（rebase 禁令仅此一次放开）；冲突规则：bin/ 与 templates/ 以 main 为准不得改动，main 在 tests/lifecycle-readiness.sh、tests/collab-herdr.sh、tests/collab-land.sh 里新增的断言一条不少，夹具的中断清理只保留一套自洽机制。（2）rebase 后跑 fast，再顺序连跑五次 bash bin/qwb-test.sh full（一次跑完再跑下一次，期间不并行跑任何别的测试），逐次记录 rc、PASS、FAIL、用时；PASS 预期 844；任一次不绿就停下定位，修好后五次重新计数。（3）失败注入与中断回归：smoke 段失败、collab 段失败时全门退出码非 0 且四段输出仍按原顺序；对运行中的全门发 TERM 后 5 秒内无残留进程与目录；用已接入的回归测试给出结果。（4）README.md 与 README.zh.md 里说全门「依次运行」四段的那句，改为四段同时运行、输出按原顺序打印；其余实测数字不要动，由主控合入时更新。（5）写 done 行：最终提交 sha、五次结果、回归结果、git status --short 输出、残留进程清单。每条 done 行 600 字以内。本票硬约束其余各条照旧（不碰真 Herdr、不带星号的 rm、临时文件只在本副本 .qwb-tmp 内、不建分支不 push）。
working: 2026-10-04T22:49:01Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-gate-parallel pane=w14Z:pT dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-parallel base=b1a95f6
working: 2026-10-04T22:49:57Z 续接已完整读规格与审核报告；按22:48:36Z最新裁决完成唯一获批rebase到b1a95f6，无冲突，候选=a63304f91d772324738986f237077c059d6b4c1e。bin/templates/lifecycle-readiness/collab-land与main逐字节同一，collab-herdr仅入口五行增量、main全部新增断言保留；fast rc=0。范围冻结，开始顺序五连门，证据沿用.qwb-tmp/audit-evidence.itdqqdzu，新轮次用resume前缀，不混用旧轮次。
working: 2026-10-04T22:56:42Z rebase后顺序五连门第1轮：候选=a63304f91d772324738986f237077c059d6b4c1e rc=0 PASS=843 FAIL=0 用时=385.27秒 跑前=0:50  up 49 mins, 1 user, load averages: 4.79 15.60 23.75；原始日志=.qwb-tmp/audit-evidence.itdqqdzu/resume-stable-1.log。
working: 2026-10-04T22:57:41Z 第一轮实际全绿但验收器因PASS预期844暂停，未启动第二轮；已核实843与主仓844差的一条仅bin/qwb-lint.sh第112行双配置检查：主仓有未入库qwbuddy/config.sh，本副本仅qwb.config.sh，该检查按原规则不适用。bin/templates及smoke与b1a95f6无差异，collab新增断言保留；不造配置凑数、不改产品检查，保留第一轮rc0/843/0回执，继续原候选第2至5轮按843核对。
working: 2026-10-04T23:04:42Z rebase后顺序五连门第2轮：候选=a63304f91d772324738986f237077c059d6b4c1e rc=0 PASS=843 FAIL=0 用时=420.9秒 跑前=0:57  up 57 mins, 1 user, load averages: 4.78 16.71 22.64；原始日志=.qwb-tmp/audit-evidence.itdqqdzu/resume-stable-2.log。
working: 2026-10-04T23:12:54Z rebase后顺序五连门第3轮：候选=a63304f91d772324738986f237077c059d6b4c1e rc=0 PASS=843 FAIL=0 用时=492.02秒 跑前=1:04  up  1:04, 1 user, load averages: 30.47 28.30 26.24；原始日志=.qwb-tmp/audit-evidence.itdqqdzu/resume-stable-3.log。
working: 2026-10-04T23:21:16Z rebase后顺序五连门第4轮：候选=a63304f91d772324738986f237077c059d6b4c1e rc=0 PASS=843 FAIL=0 用时=502.28秒 跑前=1:12  up  1:12, 1 user, load averages: 46.89 44.48 36.33；原始日志=.qwb-tmp/audit-evidence.itdqqdzu/resume-stable-4.log。
working: 2026-10-04T23:29:24Z rebase后顺序五连门第5轮：候选=a63304f91d772324738986f237077c059d6b4c1e rc=0 PASS=843 FAIL=0 用时=487.22秒 跑前=1:21  up  1:20, 1 user, load averages: 21.03 35.06 36.79；原始日志=.qwb-tmp/audit-evidence.itdqqdzu/resume-stable-5.log。
working: 2026-10-04T23:30:38Z rebase后同一候选a63304f五连门完成，全部rc0/PASS843/FAIL0，用时385.27、420.90、492.02、502.28、487.22秒；未改源码，未并行跑其他测试。开始单独留证已接入的process-entry-cleanup与process-fixture-check，随后仅改README运行说明。
working: 2026-10-04T23:31:26Z 静态验收：10个改动执行脚本的bash/-bin-bash语法与ShellCheck均rc0、无告警；qwb.config.sh两版语法rc0，独立lint三条SC2034/SC2016与b1a95f6逐条完全相同，属被source的门声明/延后展开既有诊断，没有修改代码消除它们。原始结果resume-static.json与resume-static-context.json；单独入口/夹具回归执行中。
working: 2026-10-04T23:33:16Z 独立回归完成：python3 -B tests/process-entry-cleanup.py rc0/92.28秒，PATH Bash和/bin/bash共八例成功/两段失败/TERM输出原序且失败透传；真实full TERM rc143，等待5秒后survivors=[]、new_directories=[]。python3 -B tests/process-fixture-check.py rc0/8PASS/0FAIL/5.34秒，保留初始化期TERM与所有main新增断言。证据resume-entry.log与resume-fixture.log；下一步仅README两句独立提交。
done: 2026-10-04T23:35:25Z 最终提交=4981735b354dbcd2cb21bcdc3e189acf2633ef33，基于获批b1a95f6；五连门源码候选=a63304f91d772324738986f237077c059d6b4c1e，最终仅独立追加README两句提交、实测数字未改。bin/templates/lifecycle-readiness/collab-land与main完全相同，collab-herdr八个原Python段逐字节同一；未建分支、未push、未写真Herdr。新门整行：QWB_GATE_FULL='bash tests/full-gate.sh'。
done: 2026-10-04T23:35:25Z 同一候选顺序五连 bash bin/qwb-test.sh full（轮|rc|PASS|FAIL|秒|跑前load1/5/15）：1|0|843|0|385.27|4.79/15.60/23.75；2|0|843|0|420.90|4.78/16.71/22.64；3|0|843|0|492.02|30.47/28.30/26.24；4|0|843|0|502.28|46.89/44.48/36.33；5|0|843|0|487.22|21.03/35.06/36.79。843比主仓844少的一条已定位为未入库qwbuddy/config.sh不存在时原lint不运行的双配置检查；第一轮仅验收器预期错误暂停，门本身rc0，没有失败重试、源码改动或删断言。
done: 2026-10-04T23:35:25Z 独立回归：python3 -B tests/process-entry-cleanup.py rc0/92.28秒；私有导出段替身在bash、/bin/bash各跑成功、smoke失败、collab失败、TERM八例，两种失败rc1、另一段完整运行、四段原序、门失败提示精确；真实/bin/bash全门TERM rc143，5秒后survivors=[]、new_directories=[]、无bytecode。python3 -B tests/process-fixture-check.py rc0/8PASS/0FAIL/5.34秒，初始化期真实TERM、嵌套死亡/owner代际/延迟监督清理/六槽原序全部通过。原始日志resume-entry.log、resume-fixture.log。
done: 2026-10-04T23:35:25Z fast rc0；10个改动执行脚本bash -n、/bin/bash -n、ShellCheck rc0无告警；配置声明两版语法rc0，独立lint SC2034/SC2016与main相同、无新增诊断，见resume-static-context.json。最终全门rc0/PASS843/FAIL0；末尾6行前100字符：1=PASS  tests/lint-scenario-stream.sh（5s）；2=PASS  tests/path-canonicalization.sh（1s）；3=PASS  tests/process-fixture-check.py（7s）；4=PASS  tests/process-entry-cleanup.py（169s）；5=PASS  tests/socket-path-regression.py（471s）；6=COLLAB-ALL PASS（15 项）。
done: 2026-10-04T23:35:25Z 最终git status --short输出为空；残留测试进程=[]，登记harness进程=[]，测试目录=[]。保留原始证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-parallel/.qwb-tmp/audit-evidence.itdqqdzu（results.jsonl、resume-stable-1至5.log、resume-final-receipt.json），既有audit-evidence-path仅证据指针亦保留。新旧决策数据沿用主控22:48:36Z独立顺序测量：f21b1d0 383/440秒、843/0，main b1a95f6 769/1044秒、844/0，四次rc0；本轮没有重测旧版。DONE 4981735b354dbcd2cb21bcdc3e189acf2633ef33。
working: 2026-10-04T23:45:38Z 主控验收：候选 16 个提交 cherry-pick 到 main，bin/、templates/、tests/、qwb.config.sh、README 与工人最终版 4981735 逐字节相同；运行时零改动；fast rc=0；本地 qwbuddy/config.sh 的 QWB_GATE_FULL 已同步为 bash tests/full-gate.sh。合入后 main 全门（负载约 55）：rc=0、844 PASS / 0 FAIL、502 秒、四段与 COLLAB-ALL（15 项）全过、无残留目录。连同主控重启后亲测的候选两次全绿（383/440 秒）与工人的顺序五连全绿（385–502 秒），以及同一时段依次运行版本的 769/1044 秒，判定通过。300 秒线已作废，并发后约为依次运行的一半。
