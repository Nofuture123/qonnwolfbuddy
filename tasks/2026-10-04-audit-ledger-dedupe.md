# 任务书：账本脚本内部去重：重复的读文件与判定各收成一个函数

```
任务 id:  audit-ledger-dedupe
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F23、F14 的 perl 侧）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-ledger-dedupe.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe（隔离副本，detached HEAD，起点 main 8d897cd）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

`bin/qwb-ledger.sh` 是已迁票协议的唯一写入者。审核时在它内部查出大量手抄（行号以 `4678ba0` 为准，现在已有偏移，自己重新定位并用 grep 把每一类的全部出现处列全）：

1. 「安全打开 → 整读 → 关闭」三连语句约 24 处；其中 4 处只是为了算 `workers.sh` 的 sha256。
2. 「子 op 仍在途」的判定（`claimed|dispatch`，或 `sent` 且没有对应的 done 事件）逐字重复 5 处。
3. 「已验收历史」`phase eq 'verified' || gate.verdict eq 'accepted'` 4 处。
4. 规格疑点末事件的循环 3 处。
5. 场景块合法性（`## 验收场景` 标题、Given/When/Then、失败关键词、不含协作区标记）3 处，其中一处的标题正则略宽，差异要保留。
6. 规格正文剥离的正则 2 处。
7. identity 八键校验 3 处。
8. 「旧 owner 已死」2 处（其中一处多一条身份检查，要留在原处）。
9. 就绪指纹 `sha256_hex(encode([spec_rev, needs, …, authorization]))` 3 处。
10. `sha256_hex($owner_raw)` 18 处，而 `$owner_raw` 在取得后不再变化。
11. 一行里 8 个 `exists(...) ? 'x' : ()` 串起来的写法。

白名单：`bin/qwb-ledger.sh`。

### 工程规格

1. 上面每一类各提成一个短的 `sub`（或一个只算一次的变量），调用点替换。先 grep 列全，再逐处确认「替换前后是同一个表达式」——只要有一处多了或少了条件，就让它保持原样并写明。
2. **失败关键词对齐（F14，唯一一处有意的行为修正）**：账本这三处场景合法性判定用的失败关键词是 `失败|拒绝|fail|error` 四个，而 `bin/qwb-run.sh` 与 `bin/qwb-lint.sh` 的派发门是 `失败|拒绝|报错|异常|负例|非法|fail|error` 八个。后果：只写了「报错」的场景块过得了派发门，过不了账本的建票与修订。把账本对齐到八个（放进第 5 类抽出的那个函数里，只留一处），并在旁边注释指向派发门的对应位置。单独一个提交。
3. 抽取顺序由低风险到高风险：第 1、10、11 类 → 第 2、3、6、9 类 → 第 4、5、7、8 类 → 第 2 条的关键词对齐。
4. 不调整子命令的分发结构，不改变量名的可见范围以外的东西，不重排代码。

## 1. 验收场景

### user_正常路径_协作测试全绿且逐类可回溯

Given 每一类抽取各自的提交
When  每个提交后都跑 `bash tests/collab-all.sh`（12 项）
Then  每次都全绿；`done:` 行列出每个提交的 sha、对应的类别、替换了几处、跳过了几处及原因、该提交后的 collab-all 结果

### user_正常路径_各子命令输出逐字节不变

Given 起点提交的 `bin/qwb-ledger.sh` 与改后的版本，以及一组覆盖主要子命令的已迁票夹具（可从 `tests/collab-*.sh` 的搭建代码里取用）
When  对同样的夹具状态新旧各跑：`read`、`pending`、`start-check`、`append`、`state`、`dispatch`、`not-sent`、`gate-assign`、`gate-context`、`plan-assign`、`plan-revision`、`revise`、`land-authorize`、`migrate`（成功与拒绝路径各至少一个）
Then  除关键词对齐涉及的那一种输入外，stdout、stderr、退出码、写入后的票文件字节逐一相同

### user_失败路径_拒绝路径文案与副作用不变

Given 会被拒绝的输入：子 op 仍在途时再派、已验收历史上重复派工、身份八键缺一、旧 owner 仍活时接班、规格疑点未处置时派发、场景块缺 Given
When  新旧各跑
Then  拒绝文案、退出码逐字节相同，票文件在拒绝后一个字节都没变

### user_正常路径_只写报错的场景能通过账本的场景校验

Given 一个场景块，失败路径只用了「报错」这个词（没有「失败」「拒绝」「fail」「error」）
When  用改后的账本跑会校验场景合法性的子命令（建票、修订）
Then  通过；同一输入在起点提交上被拒——这是有意的对齐；而完全没有任何失败关键词的场景块，新旧都被拒

### user_失败路径_场景块仍须满足其余条件

Given 缺标题、缺 Given/When/Then 之一、含协作区标记的场景块
When  用改后的账本跑同样的子命令
Then  照旧被拒，文案与起点相同

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行；报 `wc -l bin/qwb-ledger.sh` 前后行数。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点主仓是 840 PASS / 0 FAIL（副本里少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 6. 本票不允许做的事

- 不拆文件、不换语言、不改协议、不改子命令集合、不动锁与原子发布的实现。
- 不改 `bin/qwb-lib.sh` 里 bash 侧的场景门与义务判定（另一张票在动）。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离（死路径 `HERDR_SOCKET_PATH`）、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程，禁止按名字模式批量杀。
- git：只读命令（`git log`、`git show`、`git archive`）随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 这是账本的唯一写入者，1612 行单体 perl：**只做等价的抽取**。每一类抽取单独提交；每次提交后跑全部 `tests/collab-*.sh`（可用 `bash tests/collab-all.sh`），全绿才做下一类。
- 拒绝文案、退出码、写入账本的字节一个都不能变；各调用点原有的拒绝文案留在调用点，不要合并成一句。
- 不改 `bin/` 下其他文件、`templates/`、`tests/`。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T09:17:03Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-ledger-dedupe pane=w14Z:pF dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe base=8d897cd
working: 2026-10-04T09:18:47Z 执行者已完整读取规格及点名审核文档；基线8d897cd55c7a58cff28395af3c0e84482fac64c0，1612行，工作区干净；开始逐类清点和等价验收。
working: 2026-10-04T09:28:08Z 阶段1提交c8d53ea8609245a7396c7fe9bf4d7de5dbaf2746，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-1.log；继续阶段2。
working: 2026-10-04T09:35:29Z 阶段2提交893039f首轮协作门rc=1 PASS=11 FAIL=1；collab-land业务断言已通过，退出清理tests/process_fixture.py rows读取/bin/ps时UnicodeDecodeError字节0xfc position79878；首败保留.qwb-tmp/ledger-dedupe/collab-2.log，74例字节对照rc=0；原提交重跑全12项，不改夹具。
working: 2026-10-04T09:42:52Z 阶段2提交893039fd5aa49d8f6aa91587fdf4c32f34db6468，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-2-r2.log；继续阶段3。
working: 2026-10-04T09:50:57Z 阶段验收汇总：类别1=c8d53ea8609245a7396c7fe9bf4d7de5dbaf2746 替换24处，保留2处（publish锁内重读禁止改、land_md_snapshot须同FD stat）；类别10=893039fd5aa49d8f6aa91587fdf4c32f34db6468 替换18处跳过0；类别11=b05cb9f0e951b99d9c7976e919ec98b6abd3754f 替换1组8键判定，局部变量补齐尚未实施。每提交均跑完整collab-all，类别1rc0、类别10首轮rc1后原对象重跑rc0、类别11rc1。原始日志grep -c核对：collab-1 PASS12 FAIL0；collab-2 PASS13 FAIL1；collab-2-r2 PASS12 FAIL0；collab-3 PASS12 FAIL1（失败日志内含子测试PASS，先前PASS11表示外层11项通过，不是原始grep计数，以本行计数为准）。
blocked: 2026-10-04T09:50:57Z STOP 协作门因白名单外tests/process_fixture.py:rows解码全机/bin/ps出现重复UnicodeDecodeError（0xfc；先land清理position79878，后planning release/drain position120496）；未改测试、未绕过隔离，按全绿才下一类的硬约束停止。固定HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f，仅bin/qwb-ledger.sh有已提交差异，git status --short为空，登记的自有执行组残留=[]；行数1612→1617；/bin/bash bin/qwb-test.sh fast rc0；python3 -B .qwb-tmp/ledger-dedupe/byte-check.py rc0，74例公开Bash/Perl stdout、stderr、退出码及票字节对照（固定时钟/hash seed/事件ID、假身份/Git/Herdr）通过。仅完成前段类别1/10/11；类别2/3/6/9/4/5/7/8及F14未应用，全门未运行，不记done。证据绝对目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe，汇总stop-report.json，首败collab-2.log、当前红门collab-3.log、当前字节对照bytes-3.log。
working: 2026-10-04T09:51:57Z 主控处置（回应 09:50:57Z 的 blocked）：你定位得对——tests/process_fixture.py 的 rows() 用 text=True 解码全机 ps 的命令列，机器上只要有任何进程的命令行含非 UTF-8 字节就会抛 UnicodeDecodeError。主控复查时全机已无这样的进程：它是别的工人同时在跑的测试（损坏账本、UTF-8 回归那几节会带坏字节的参数起进程）留下的瞬时干扰，与你的改动无关，也不在你的白名单内。夹具的修复已交给 audit-reap-window 一并做。本票恢复执行：重跑 bash tests/collab-all.sh；若再次遇到同一个 UnicodeDecodeError，隔 2 分钟重跑，最多 3 次，把每次结果记进 working 行；除这一种干扰外的任何失败仍按「全绿才做下一类」处理。
working: 2026-10-04T09:53:07Z 恢复/执行collab-3-r2 HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T10:01:32Z collab-3-r2 attempt=1 HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f rc=1 grep-PASS=11 grep-FAIL=1 log=.qwb-tmp/ledger-dedupe/collab-3-r2-a1.log；授权的ps UTF-8干扰
working: 2026-10-04T10:01:32Z collab-3-r2 再遇同一ps解码干扰；从当前机器时间等待120秒后重跑第2次。
working: 2026-10-04T10:16:44Z collab-3-r2 attempt=2 HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f rc=1 grep-PASS=18 grep-FAIL=2 log=.qwb-tmp/ledger-dedupe/collab-3-r2-a2.log；其他失败，不继续下一类
working: 2026-10-04T10:25:08Z 恢复第2次协作门除ps解码干扰外，collab-handoff出现watch.communicate(timeout=3)超时；未改源，单独bash tests/collab-handoff.sh rc0 PASS10 FAIL0，超时未复现，日志=.qwb-tmp/ledger-dedupe/handoff-resume-diagnostic.log；尚不视作协作全绿。现在原HEAD执行恢复第3次完整12项（不再自动追加重跑），旧日志全部保留。
working: 2026-10-04T10:25:08Z 恢复/执行collab-3-r3 HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f command=bash tests/collab-all.sh；最多1次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T10:28:52Z collab-3-r3 attempt=1 HEAD=b05cb9f0e951b99d9c7976e919ec98b6abd3754f rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-3-r3-a1.log；全绿
working: 2026-10-04T10:32:17Z 类别11原提交b05cb9f0e951b99d9c7976e919ec98b6abd3754f恢复第3次collab全绿rc0 PASS12 FAIL0，前两次失败及handoff单跑rc0均保留；补齐类别11局部optional_keys变量，追加提交da5f7e7cffd3a924474edd99d6638f02812a4389，不改写历史；现跑补齐后的完整12项。
working: 2026-10-04T10:32:18Z 恢复/执行collab-3b HEAD=da5f7e7cffd3a924474edd99d6638f02812a4389 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T10:36:25Z collab-3b attempt=1 HEAD=da5f7e7cffd3a924474edd99d6638f02812a4389 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-3b-a1.log；全绿
working: 2026-10-04T10:39:03Z 阶段3提交da5f7e7cffd3a924474edd99d6638f02812a4389，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-3b.log；继续阶段4。
working: 2026-10-04T10:39:03Z 恢复/执行collab-4 HEAD=1784b2e3005fdc65578976d2405f18cb180fee48 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T10:43:16Z collab-4 attempt=1 HEAD=1784b2e3005fdc65578976d2405f18cb180fee48 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-4-a1.log；全绿
working: 2026-10-04T10:47:08Z 阶段4提交1784b2e3005fdc65578976d2405f18cb180fee48，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-4.log；继续阶段5。
working: 2026-10-04T10:47:08Z 恢复/执行collab-5 HEAD=6c600a3cfdcc1aa27335760e9722b1a896cc9ce5 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T10:51:27Z collab-5 attempt=1 HEAD=6c600a3cfdcc1aa27335760e9722b1a896cc9ce5 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-5-a1.log；全绿
working: 2026-10-04T11:17:05Z 补充字节反例：同一损坏JSON read旧rc255 stderr含at - line 77，新rc255含line82，违反字节不变；证据.qwb-tmp/ledger-dedupe/frame-probe.json。已在临时计划中用Perl原生#line保留基线位置，并为未提供/为null的场景保留原调用点警告；109例（新增损坏JSON、null/false/数组/数字schema、null phase、null revision场景、缺替换场景）计划版对照rc0。此补齐将在纯抽取收尾后、F14前单独追加提交；当前执行提交尚未应用。
working: 2026-10-04T11:17:17Z 阶段5提交6c600a3cfdcc1aa27335760e9722b1a896cc9ce5，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-5.log；继续阶段6。
working: 2026-10-04T11:17:17Z 恢复/执行collab-6 HEAD=63952832110ba7b19db98c07b278c3d0f65920e4 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:21:23Z collab-6 attempt=1 HEAD=63952832110ba7b19db98c07b278c3d0f65920e4 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-6-a1.log；全绿
working: 2026-10-04T11:21:48Z 阶段6提交63952832110ba7b19db98c07b278c3d0f65920e4，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-6.log；继续阶段7。
working: 2026-10-04T11:21:49Z 恢复/执行collab-7 HEAD=862b14d84aafbe9582057c43ab42e5c3ef78e277 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:25:55Z collab-7 attempt=1 HEAD=862b14d84aafbe9582057c43ab42e5c3ef78e277 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-7-a1.log；全绿
working: 2026-10-04T11:27:15Z 阶段7提交862b14d84aafbe9582057c43ab42e5c3ef78e277，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-7.log；继续阶段8。
working: 2026-10-04T11:27:15Z 恢复/执行collab-8 HEAD=f26ddbeb64bfad876889ca0352027abe14c5e5bc command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:31:20Z collab-8 attempt=1 HEAD=f26ddbeb64bfad876889ca0352027abe14c5e5bc rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-8-a1.log；全绿
working: 2026-10-04T11:32:39Z 阶段8提交f26ddbeb64bfad876889ca0352027abe14c5e5bc，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-8.log；继续阶段9。
working: 2026-10-04T11:32:39Z 恢复/执行collab-9 HEAD=5243cb3eb0cf743bd684c63486742e193ec5d94a command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:36:23Z collab-9 attempt=1 HEAD=5243cb3eb0cf743bd684c63486742e193ec5d94a rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-9-a1.log；全绿
working: 2026-10-04T11:37:03Z 阶段9提交5243cb3eb0cf743bd684c63486742e193ec5d94a，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-9.log；继续阶段10。
working: 2026-10-04T11:37:03Z 恢复/执行collab-10 HEAD=06711e19ea7929c9685a35cacd5badb903492fef command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:40:50Z collab-10 attempt=1 HEAD=06711e19ea7929c9685a35cacd5badb903492fef rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-10-a1.log；全绿
working: 2026-10-04T11:42:18Z 阶段10提交06711e19ea7929c9685a35cacd5badb903492fef，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-10.log；继续阶段11。
working: 2026-10-04T11:42:18Z 恢复/执行collab-11 HEAD=fa74072436b24644f71d9bdb701c4f80022c79d1 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:46:13Z collab-11 attempt=1 HEAD=fa74072436b24644f71d9bdb701c4f80022c79d1 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-11-a1.log；全绿
working: 2026-10-04T11:48:02Z 纯抽取收尾：类别8 fa74072 collab12项rc0；诊断补齐commit=73bfad56c30feb94afdbf971cef505461e2c4575，19处原生#line与2处未定义场景警告保留；BYTE_DIAGNOSTICS=1 python3 -B .qwb-tmp/ledger-dedupe/byte-check.py rc0，109例纯抽取全部逐字节相同，关键词尚未对齐；日志=.qwb-tmp/ledger-dedupe/bytes-11b.log。现在跑该补齐提交后的全部collab12项。
working: 2026-10-04T11:48:02Z 恢复/执行collab-11b HEAD=73bfad56c30feb94afdbf971cef505461e2c4575 command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:52:02Z collab-11b attempt=1 HEAD=73bfad56c30feb94afdbf971cef505461e2c4575 rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-11b-a1.log；全绿
working: 2026-10-04T11:53:20Z 阶段11提交73bfad56c30feb94afdbf971cef505461e2c4575，bash tests/collab-all.sh rc=0 PASS=12 FAIL=0；证据=.qwb-tmp/ledger-dedupe/collab-11b.log；继续阶段12。
working: 2026-10-04T11:53:20Z 恢复/执行collab-12 HEAD=ced2e02168b4426dff0d3af5f50989c1a3615b1a command=bash tests/collab-all.sh；最多3次，仅全机ps UnicodeDecodeError允许间隔120秒重跑，保留每轮日志。
working: 2026-10-04T11:57:11Z collab-12 attempt=1 HEAD=ced2e02168b4426dff0d3af5f50989c1a3615b1a rc=0 grep-PASS=12 grep-FAIL=0 log=.qwb-tmp/ledger-dedupe/collab-12-a1.log；全绿
working: 2026-10-04T11:59:35Z 最终提交ced2e02168b4426dff0d3af5f50989c1a3615b1a的collab12项全绿；/bin/bash bin/qwb-test.sh fast rc0；BYTE_DIAGNOSTICS=1 python3 -B .qwb-tmp/ledger-dedupe/byte-check.py rc0，109例最终对照（仅F14获准差异，其余逐字节相同），日志=.qwb-tmp/ledger-dedupe/bytes-final.log，全部原始stdout/stderr/退出码/票SHA存byte-results.json。现执行一次bash bin/qwb-test.sh full并记录自然退出回执。
done: 2026-10-04T12:11:35Z 类别1 commit=c8d53ea8609245a7396c7fe9bf4d7de5dbaf2746 替换=24 跳过=2 原因=publish锁内重读禁止修改；land_md_snapshot在同一读FD上stat；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-1.log
done: 2026-10-04T12:11:35Z 类别10 commit=893039fd5aa49d8f6aa91587fdf4c32f34db6468 替换=18 跳过=0 原因=无额外条件差异；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-2-r2.log
done: 2026-10-04T12:11:35Z 类别11 commit=b05cb9f0e951b99d9c7976e919ec98b6abd3754f 替换=1 跳过=0 原因=一组8个可选键；b05首轮和恢复前两轮的失败日志保留；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-3-r3.log
done: 2026-10-04T12:11:35Z 类别11补齐 commit=da5f7e7cffd3a924474edd99d6638f02812a4389 替换=1 跳过=0 原因=只算一次的validate局部列表；追加提交，不改写历史；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-3b.log
done: 2026-10-04T12:11:35Z 类别2 commit=1784b2e3005fdc65578976d2405f18cb180fee48 替换=5 跳过=0 原因=保留另1处op状态值域校验，其条件不同且不是在途判定；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-4.log
done: 2026-10-04T12:11:35Z 类别3 commit=6c600a3cfdcc1aa27335760e9722b1a896cc9ce5 替换=4 跳过=2 原因=另两处是仅verified或gate/claim更强条件，保持原样；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-5.log
done: 2026-10-04T12:11:35Z 类别6 commit=63952832110ba7b19db98c07b278c3d0f65920e4 替换=2 跳过=0 原因=无额外条件差异；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-6.log
done: 2026-10-04T12:11:35Z 类别9 commit=862b14d84aafbe9582057c43ab42e5c3ef78e277 替换=3 跳过=1 原因=blocked编码顺序为spec_rev,needs,authorization,reason；ready为spec_rev,needs,evidence,authorization；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-7.log
done: 2026-10-04T12:11:35Z 类别4 commit=f26ddbeb64bfad876889ca0352027abe14c5e5bc 替换=3 跳过=0 原因=无额外条件差异；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-8.log
done: 2026-10-04T12:11:35Z 类别5 commit=5243cb3eb0cf743bd684c63486742e193ec5d94a 替换=3 跳过=0 原因=保留严格标题2处、宽标题1处及new的defined条件；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-9.log
done: 2026-10-04T12:11:35Z 类别7 commit=06711e19ea7929c9685a35cacd5badb903492fef 替换=3 跳过=0 原因=无额外条件差异；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-10.log
done: 2026-10-04T12:11:35Z 类别8 commit=fa74072436b24644f71d9bdb701c4f80022c79d1 替换=2 跳过=0 原因=两处语义位置、3次helper调用；额外身份拒绝条件仍留原处；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-11.log
done: 2026-10-04T12:11:35Z 类别字节诊断补齐 commit=73bfad56c30feb94afdbf971cef505461e2c4575 替换=19 跳过=0 原因=19处原生#line保持旧诊断位置；2个未定义场景值保留旧调用点警告；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-11b.log
done: 2026-10-04T12:11:35Z 类别F14 commit=ced2e02168b4426dff0d3af5f50989c1a3615b1a 替换=1 跳过=0 原因=共用场景函数的4关键词改8关键词，影响3个调用点，唯一有意行为修正；bash tests/collab-all.sh rc=0 PASS=12 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/collab-12.log
done: 2026-10-04T12:11:35Z 场景1逐类可回溯：14个追加提交、全部对应collab12项全绿，原始失败与恢复日志保留；场景2主要14子命令含pending(handoff-pending)成功/拒绝，场景3在途/验收历史/八键缺失/活owner/未处置规格/缺Given拒绝及票不变：BYTE_DIAGNOSTICS=1 python3 -B .qwb-tmp/ledger-dedupe/byte-check.py rc0，共109例，stdout/stderr/退出码/票字节相同；只冻结时钟与事件ID/hash种子、以假身份/Git/Herdr构建同路径夹具，真实身份发现由collab补验；log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/bytes-final.log，逐例原始结果=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/byte-results.json。
done: 2026-10-04T12:11:35Z 场景4只写报错的new/plan-revision/revise-scenarios原始结果=[{"label": "new scenario only 报错", "command": "new", "old_rc": 255, "new_rc": 0, "old_stderr": "账本拒绝：新票必须自带可验证场景\n", "stderr": ""}, {"label": "revision scenario only 报错", "command": "plan-revision", "old_rc": 255, "new_rc": 0, "old_stderr": "账本拒绝：新场景缺少正常/拒绝行为\n", "stderr": ""}, {"label": "replace scenario only 报错", "command": "revise-scenarios", "old_rc": 25, "new_rc": 0, "old_stderr": "账本拒绝：新场景块格式非法\n", "stderr": ""}]，异常/负例/非法同样对齐；场景5无关键词、缺标题/Given/When/Then、协作区标记旧新均拒绝且原字节不变，宽标题行为保留；损坏JSON与null警告也逐字节不变；以上同109例对照原始结果。
done: 2026-10-04T12:11:35Z 最终HEAD=ced2e02168b4426dff0d3af5f50989c1a3615b1a；bash bin/qwb-test.sh fast rc0；bash bin/qwb-test.sh full rc0 PASS=839 FAIL=0 log=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/full-final.log；末尾5行各前100字符=["PASS  tests/collab-roles.sh（75s）", "PASS  tests/collab-test-policy.sh（102s）", "PASS  tests/lint-scenario-stream.sh（2s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（12 项）"]；wc -l bin/qwb-ledger.sh 1612→1660；全门后git status --short输出为空；自有残留进程=[]；只改bin/qwb-ledger.sh，不建分支、不push、不改变state字段；汇总=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-ledger-dedupe/.qwb-tmp/ledger-dedupe/final-report.json。
working: 2026-10-04T12:23:48Z 主控验收：审过新抽出的函数（read_file、identity_keys、scenarios_ok、owner_dead、child_in_flight、spec_body、last_spec_event、accepted_history、ready_fingerprint 与只算一次的 owner 指纹）；14 个提交 cherry-pick 到 main，合并后 bin/qwb-ledger.sh 与工人最终版本逐字节相同；以合并后 main（HEAD=33eef46，含 audit-lib-sink 与 audit-reap-window）全门作验收：rc=0、840 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、596.39s；全门后工作区无改动、.qwb-tmp 为空、无残留进程。行数 1612 → 1660，本票的收益是规则单点定义而非代码变短。
