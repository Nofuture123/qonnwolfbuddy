# 任务书：「进程已死」的判定两处对齐到加固过的那一份

```
任务 id:  audit-death-proof
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」「还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F20）；范围由主控收窄
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-death-proof.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof（隔离副本，detached HEAD，起点 main ded7d88）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。本仓是他之后所有项目的初始化脚本；收尾时删副本、关 Space 之前「确认工人确实已经停了」这一步判错，后果是工人还在写的时候把它的东西删掉。

「某个 PID 加启动时间对应的进程已经不在了」这个判定有两份实现：

- `bin/qwb-worktree.sh` 的 `writers_stopped` 里的 `ended()`：用绝对路径 `/bin/ps -p PID -o lstart=`，并要求 stderr 为空；注释写明是为了不让 PATH 上的替身来「证明」进程已死。
- `bin/qwb-herdr.sh` 的 `ended(pid,start)`（关闭 Space 等路径在用）：用 PATH 上的 `ps`，stderr 的要求也只加在「已死」那一支。

两份语义本该相同，其中一份后来加固了，另一份没跟上。审核原本建议把两处合成一个入口；主控收窄为**只对齐、不合并**——`qwb-worktree.sh` 里那份注释写明是有意固定下来的拷贝，在删除路径上做结构性重排的风险大于收益。

白名单：`bin/qwb-herdr.sh`（只许改 `ended` 与 `activity` 里认定原生进程的那几行）、`tests/` 下为验收所需的文件。

### 工程规格

1. 把 `bin/qwb-herdr.sh` 的 `ended()` 对齐到 `bin/qwb-worktree.sh` 那份的判定：绝对路径 `/bin/ps`；任何 stderr 输出都视为未知并拒绝；「已死」= 退出码 1 且无输出，或退出码 0 且启动时间与记录的不同；其余一律是「仍活或未知」。拒绝文案沿用 `qwb-herdr.sh` 现有的英文那句，不改。
2. 先 grep `bin/` 里所有用 `ps` 判断进程死活或取启动时间的地方（`qwb-herdr.sh` 的 `activity` 取 `lstart`、`qwb-role.sh`、`qwb-lib.sh`、`qwb-ledger.sh` 等），列表说明每一处用的是 PATH 上的 `ps` 还是 `/bin/ps`、判定条件是什么、它的结论会不会被用来放行删除或接班。**本票只改 `qwb-herdr.sh` 的 `ended()`**；其余的只列出来，判断是否同样需要加固，写进 `done:` 行供主控决定，不要动。
3. 现有测试里凡是靠在 PATH 上放一个假 `ps` 来让 `qwb-herdr.sh` 的 `ended()` 认为进程已死的，改成用「真实启动、真实退出并已回收的子进程」的 PID 与启动时间来提供死进程；要表达「进程仍活」就用一个真实存活、测完按 PID 结束的子进程。断言内容不变。逐个列出改了哪些测试的哪几行。
4. 新增一条对照测试（放进已在全门里的 `tests/collab-herdr.sh`，不要新建没人跑的文件）：对同一组输入——真实已死的进程、真实存活的进程、PID 被复用（启动时间不同）、PID 非法、启动时间缺失、PATH 上有一个谎称进程已死的假 `ps`——分别走 `qwb-herdr.sh` 的 `ended` 路径与 `qwb-worktree.sh` 的 `writers_stopped` 路径，两边的「放行 / 拒绝」结论必须一致。其中「PATH 上有假 ps」这一组在起点提交上两边结论不一致（herdr 那份会被骗），修复后一致——这是本票的核心红绿证据。

5. **真机验收抓到的缺陷：工人进程身份绑不上，副本永远收不了尾（主控 2026-10-04T14:30Z 追加，优先级最高）。**
   主控在真 Herdr 上跑了一轮端到端验收（Claude Code 主控、devin 工人）：派发、干活、验收、合入都成功，最后 `qwb-worktree.sh finish --merged` 拒绝，报「旧启动代PID/start未知」，而且没有任何合法的补救办法。原因在 `bin/qwb-herdr.sh` 的 `activity()`：它用「前台进程里名字等于工具名的恰好有一个」来认定工人的原生进程；devin 运行时有**两个**同名进程，于是判为 `native tool identity unknown`，派发时记下的证据里没有 PID，收尾时要求的死亡证明就永远拿不出来。
   主控在一个独立的临时 Herdr 会话里做了只读探测（会话已删），真实应答是：`shell_pid=38061`，`foreground_process_group_id=38189`，前台进程两条——`pid=38248 argv0=devin` 与 `pid=38189 argv0=devin`；`agent=devin`。同样的探测下 Pi 工人是 `foreground_process_group_id=41101`、唯一一条 `pid=41101 argv0=pi`，Claude Code 是组长 `pid=641 argv0=claude` 外加一条 `argv0=caffeinate`。
   修法：名字匹配的进程有多个时，取其中 `pid` 等于 `foreground_process_group_id` 的那一个（前台进程组的组长）作为原生进程；组长不在名字匹配的集合里、或名字匹配为零时，照旧判未知并拒绝——不要放宽成「随便取一个」或「取任意组长」。只有一个名字匹配时行为与现在完全相同。
   验证：用假 herdr 给出上面三种真实形态的应答（devin 双进程、pi 单进程、claude 加 caffeinate），再加「两个同名进程但都不是组长」「名字匹配为零」两种，逐个断言认定结果；devin 那一种在起点提交上是 unknown、修复后拿到组长 PID 与启动时间。用例放进已在全门里的测试文件。另外把这条路走通到底：派发时记下的证据带上 PID 之后，`finish --merged` 在工人进程真实退出后能够完成（用真实启动并退出的子进程充当工人进程，假 herdr 把它报成双进程形态）。
   另请只读地核一件事并写进 `done:` 行，不要改：派发时如果身份确实绑不上（证据里 `activity` 是 `unknown` 且没有 PID），现在的流程会照常派发，之后收尾必然被拒且无法补救。列出这种状态下使用者手里有哪些合规的出路（如果一个都没有，就照实写「没有」），供主控决定要不要改成派发时就拒绝。

## 1. 验收场景

### user_正常路径_工人确实已停时收尾照常进行

Given 一张已派发的票，它记录的工人进程是一个真实启动、已经退出并被回收的子进程
When  跑会走到 `qwb-herdr.sh` `ended` 的入口（关闭 Space 的收尾路径）
Then  判定为已停并继续，stdout、stderr、退出码与起点提交在同样输入下相同

### user_失败路径_PATH上的假ps骗不过去

Given 工人进程其实还活着，而 PATH 最前面放了一个对任何 PID 都返回「不存在」的假 `ps`
When  跑同一个入口
Then  拒绝收尾，Space、副本、分支、任务书都没被动过；同样输入在起点提交上会被骗而放行——这是要修的缺陷

### user_失败路径_查询有任何异常都按未知拒绝

Given `/bin/ps` 的查询结果分别是：有 stderr 输出、退出码既非 0 也非 1、超时（这几种在测试里通过给 `ended` 传入会触发相应结果的 PID 或用可控包装来构造，不许替换系统的 `/bin/ps`）
When  跑同一个入口
Then  一律拒绝，文案是现有的那句「仍活或死亡未知」

### user_失败路径_PID被复用时不误判

Given 记录的 PID 现在属于另一个进程（启动时间与记录的不同），以及记录的 PID 仍是原进程（启动时间相同）
When  跑同一个入口
Then  前者判为原进程已死并放行，后者判为仍活并拒绝；与 `qwb-worktree.sh` 那份对同样输入的结论一致

### user_正常路径_两份实现结论一致

Given 规格第 4 条列的六组输入
When  跑新增的对照测试
Then  修复后六组结论全部一致；在起点提交上「PATH 上有假 ps」那一组不一致

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 这是删除前的安全判定：只许让它更严，不许让任何原来拒绝的输入变成放行。不动 `bin/qwb-worktree.sh`（它那份是基准）。
- 不许替换、遮蔽或修改系统的 `/bin/ps`；测试里的死进程与活进程都用自己真实启动的子进程，记下 PID，测完逐个回收。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行；规格第 2 条的清单与第 3 条改动的测试行也写进去。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点主仓是 841 PASS / 0 FAIL（副本里没有 `qwbuddy/config.sh`，少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不把两份实现合并成一个入口；不动 `bin/qwb-worktree.sh`、`bin/qwb-role.sh`、`bin/qwb-lib.sh`、`bin/qwb-ledger.sh`、`templates/`。
- 不改 `tests/collab-all.sh`（另一张票正在改它）；新测试放进已有的 `tests/collab-herdr.sh`。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T14:07:16Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-death-proof pane=w14Z:pN dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof base=ded7d88
working: 2026-10-04T14:09:31Z 阶段1完成：完整读取规格与F20来源，核查全部bin进程查询及测试夹具；确认产品仅对齐qwb-herdr ended，现有收尾死亡证据已来自真实回收子进程，其他PATH ps用于角色身份模拟，详细清单随done提交。
working: 2026-10-04T14:18:04Z 阶段2完成：只修改bin/qwb-herdr.sh ended及tests/collab-herdr.sh；新增真实PID七组公开入口对照和六种异常包装，定向绿13 PASS，起点fake-ps红（herdr=0/worktree=1）；fast rc=0，测试脚本shellcheck按tests源路径检查通过；准备提交后全门。
working: 2026-10-04T14:26:58Z 主控修订规格：工程规格新增第 5 条（真机验收抓到的缺陷：devin 运行时有两个同名前台进程，activity 认不出原生进程，派发证据缺 PID，收尾永远被拒），白名单扩到 activity 里认定原生进程的那几行；该条优先级最高，先做并单独提交，提交后立刻追加一条 working 行报出 sha，主控据此重跑真机验收。原有各条照做。
working: 2026-10-04T14:33:50Z 新增第5条单独提交完成 sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa（父提交9231f81）；devin双进程选同名组长，pi单进程与claude+caffeinate逐字节保持旧输出；五种形态和真实devin派发→PID证据先于prompt→活时拒绝→真实退出后finish merged删除副本与分支，定向rc=0/6 PASS；起点devin缺PID反例rc=1；fast与测试shellcheck通过。主控可据此重跑真机验收。
working: 2026-10-04T14:37:41Z 阶段3核查完成：原候选9231f81提交后full rc=0/840 PASS/0 FAIL；新增第5条6f3a8cc后的最终full正在运行。第5条验收为假Herdr真实进程形态+真实启动/退出回收的子进程，不是真Herdr写操作；缺PID旧证据没有合规删除补救入口，finish --keep=原因可显式保留，详细路径与源码依据随done记录。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 全部规格1-5完成；两次独立提交=9231f81f1ecb9f3a58e38a7f6655b18463868bdc（死亡证明对齐）→6f3a8cc567772c4e17a1d971c00cad7a091fb2fa（新增第5条原生组长绑定，已即时working交接）。代码只在本副本、仅bin/qwb-herdr.sh和tests/collab-herdr.sh；不建分支、不push、不碰真Herdr写状态，qwb-worktree.sh与起点字节相同。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 快门命令=bash bin/qwb-test.sh fast，rc=0，stdout/stderr为空（native-fast.log）；测试shellcheck命令=shellcheck -x -P tests tests/collab-herdr.sh，rc=0；原候选提交后全门=bash bin/qwb-test.sh full > /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/audit-death-proof.TIvr7SrT/full.log 2>&1，rc=0/840 PASS/0 FAIL；最终提交后全门=bash bin/qwb-test.sh full > /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/audit-death-proof.TIvr7SrT/full-final.log 2>&1，rc=0/840 PASS/0 FAIL；PASS与FAIL均使用grep -c ^PASS/grep -c ^FAIL计数。主仓841相差1是副本无qwbuddy/config.sh少lint项；新增对照处于collab-herdr内层，最终内层rc=0/32 PASS/0 FAIL。全门末5行各前100字符=["PASS  tests/collab-roles.sh（86s）", "PASS  tests/collab-test-policy.sh（98s）", "PASS  tests/lint-scenario-stream.sh（4s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（12 项）"]；全门后git status --short原始stdout=''；残留进程清单=[]；lsof -nP -Fpcfn +D .qwb-tmp结果={"rc": 1, "stdout": "", "stderr": ""}；临时目录仅保留本票证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/audit-death-proof.TIvr7SrT，scope/socket/真实子进程均已回收；final-receipt.json记录完整核验。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 五场景公开命令=bash tests/collab-herdr.sh death-proof（原定向rc=0/13 PASS/0 FAIL；最终full默认亦运行，同结果）；起点反例命令=QWB_DEATH_HERDR_REV=ded7d88 bash tests/collab-herdr.sh death-proof，rc=1（herdr fake-ps=0而worktree=1，11 PASS/0 FAIL前缀，失败为对照断言，原始日志red-final.log）。正常死进程close与起点stdout/stderr/rc逐字节相同；六组加非法布尔PID均对照，stderr两分支/异常rc/超时/空活结果/死码带输出均拒绝且不动Space、树、分支、任务书。最终full内层的五场景原始结果=["DEATH-PROOF dead herdr_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n' stderr= ''", "DEATH-PROOF dead worktree_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n已收尾（已合并进当前分支（HEAD））：worktree /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/s-_foks_6h/project/.worktrees/case 已删（删除依据 OID 644769f318320052328a9d33e68966933429422b），分支 case 已删\\n注意：删前复核与删除是两次 Git 调用，之间仍有窗口（Git 层面无法封死）；\\n      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），\\n      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。\\n已记账：2099-01-01-case.md ← worktree: merged branch=case tag=-\\n' stderr= ''", "PASS death-proof dead: herdr/worktree agree allow", "DEATH-PROOF live herdr_rc= 1 stdout= '' stderr= 'Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault stderr-dead: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault stderr-reused: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault status-3: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault timeout: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault empty-live: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "PASS death-proof fault output-dead: both reject; herdr stderr='Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "DEATH-PROOF live worktree_rc= 1 stdout= '' stderr= '拒绝：旧启动代仍活或死亡未知\\n'", "PASS death-proof live: herdr/worktree agree refuse", "DEATH-PROOF reused herdr_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n' stderr= ''", "DEATH-PROOF reused worktree_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n已收尾（已合并进当前分支（HEAD））：worktree /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/s-haw0kfbn/project/.worktrees/case 已删（删除依据 OID 62dd9a3891d13f49ae69931a1a7daacd0d9ca2aa），分支 case 已删\\n注意：删前复核与删除是两次 Git 调用，之间仍有窗口（Git 层面无法封死）；\\n      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），\\n      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。\\n已记账：2099-01-01-case.md ← worktree: merged branch=case tag=-\\n' stderr= ''", "PASS death-proof reused: herdr/worktree agree allow", "DEATH-PROOF invalid herdr_rc= 1 stdout= '' stderr= 'Herdr refusal/unknown: old launch PID/start unknown\\n'", "DEATH-PROOF invalid worktree_rc= 1 stdout= '' stderr= '拒绝：旧启动代PID/start未知\\n'", "PASS death-proof invalid: herdr/worktree agree refuse", "DEATH-PROOF missing herdr_rc= 1 stdout= '' stderr= 'Herdr refusal/unknown: old launch PID/start unknown\\n'", "DEATH-PROOF missing worktree_rc= 1 stdout= '' stderr= '拒绝：旧启动代PID/start未知\\n'", "PASS death-proof missing: herdr/worktree agree refuse", "DEATH-PROOF fake-ps herdr_rc= 1 stdout= '' stderr= 'Herdr refusal/unknown: old native PID still alive or death unknown\\n'", "BASELINE fake-ps herdr_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n' stderr= ''", "DEATH-PROOF fake-ps worktree_rc= 1 stdout= '' stderr= '拒绝：旧启动代仍活或死亡未知\\n'", "PASS death-proof fake-ps: herdr/worktree agree refuse", "DEATH-PROOF boolean herdr_rc= 1 stdout= '' stderr= 'Herdr refusal/unknown: old launch PID/start unknown\\n'", "DEATH-PROOF boolean worktree_rc= 1 stdout= '' stderr= '拒绝：旧启动代PID/start未知\\n'", "PASS death-proof boolean: herdr/worktree agree refuse"]
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 新增规格5命令=bash tests/collab-herdr.sh activity-native，rc=0/6 PASS/0 FAIL；起点命令=QWB_NATIVE_HERDR_BASELINE=1 bash tests/collab-herdr.sh activity-native，rc=1，devin unknown且缺pid（native-red.log，KeyError pid准确触发所需PID断言）。用假Herdr复刻五种真实形态，PID/start属于自己实际启动并退出回收的子进程；未连接真Herdr。最终full内层原始结果=["NATIVE-SHAPE devin baseline= {\"activity\": \"unknown\", \"proof\": \"unverified\", \"conflict\": \"native tool identity unknown\"} current= {\"activity\": \"unknown\", \"proof\": \"native-pid; CLI idle not verified\", \"pid\": 13285, \"pid_start\": \"Sun Oct  4 16:37:58 2026\"}", "PASS native shape devin", "NATIVE-SHAPE pi baseline= {\"activity\": \"idle\", \"proof\": \"native-pid-start+session-branch\", \"pid\": 13285, \"pid_start\": \"Sun Oct  4 16:37:58 2026\", \"session\": \"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/s-rdfphsu5/pi.jsonl\", \"pending_tools\": []} current= {\"activity\": \"idle\", \"proof\": \"native-pid-start+session-branch\", \"pid\": 13285, \"pid_start\": \"Sun Oct  4 16:37:58 2026\", \"session\": \"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/s-rdfphsu5/pi.jsonl\", \"pending_tools\": []}", "PASS native shape pi", "NATIVE-SHAPE claude baseline= {\"activity\": \"unknown\", \"proof\": \"native-pid; CLI idle not verified\", \"pid\": 13285, \"pid_start\": \"Sun Oct  4 16:37:58 2026\"} current= {\"activity\": \"unknown\", \"proof\": \"native-pid; CLI idle not verified\", \"pid\": 13285, \"pid_start\": \"Sun Oct  4 16:37:58 2026\"}", "PASS native shape claude", "NATIVE-SHAPE no-matching-leader baseline= {\"activity\": \"unknown\", \"proof\": \"unverified\", \"conflict\": \"native tool identity unknown\"} current= {\"activity\": \"unknown\", \"proof\": \"unverified\", \"conflict\": \"native tool identity unknown\"}", "PASS native shape no-matching-leader", "NATIVE-SHAPE no-tool-name baseline= {\"activity\": \"unknown\", \"proof\": \"unverified\", \"conflict\": \"native tool identity unknown\"} current= {\"activity\": \"unknown\", \"proof\": \"unverified\", \"conflict\": \"native tool identity unknown\"}", "PASS native shape no-tool-name", "NATIVE-E2E dispatch_rc= 0 leader_pid= 13285 pid_start= Sun Oct  4 16:37:58 2026 alive_rc= 1 ended_rc= 0 stdout= '{\"before_order\": [\"wRoot\", \"wTask\"], \"after_order\": [\"wRoot\"], \"before_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"after_focus\": [\"wRoot\", \"wRoot:t1\", \"wRoot:p1\"], \"space\": \"wTask\", \"command\": \"close\"}\\n已收尾（已合并进当前分支（HEAD））：worktree /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-death-proof/.qwb-tmp/s-rdfphsu5/project/.worktrees/case 已删（删除依据 OID 07d8fab215845a3eca0abfe236f7a30c97736699），分支 case 已删\\n注意：删前复核与删除是两次 Git 调用，之间仍有窗口（Git 层面无法封死）；\\n      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），\\n      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。\\n已记账：2099-01-01-case.md ← worktree: merged branch=case tag=-\\n' stderr= ''", "PASS devin public dispatch records leader before prompt; actual exit permits merged finish"]
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa bin/ 进程证据清单（行号对应最终候选）
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-herdr.sh:27 reap_command：/bin/ps -axo pgid=,stat=；必须rc=0，排除Z后没有该新会话PGID才认为订阅查询后代已退出；只用于自己启动的订阅查询组回收，不放行worktree删除/角色接班。已固定路径；stderr未单独校验，若进一步统一未知语义可单独评估。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-herdr.sh:164 activity：PATH ps -p PID -o lstart=；command要求rc=0、start非空，不校验stderr；产生pid_start供worker-activity绑定和复用，间接进入后续死亡证明。建议后续固定/bin/ps并拒绝stderr，避免伪造启动时间污染绑定；本票未动。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-herdr.sh:201 ended：起点PATH ps，rc=1且stdout/stderr strip为空或rc=0非空start不同（后者忽略stderr）；本票改/bin/ps、两分支统一拒绝stderr、type(pid) is int，并把TimeoutExpired映射为原英文死亡未知拒绝。直接放行Space close，间接放行finish/land收尾。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-role.sh:138 stamp：PATH ps；rc=0且stdout.strip非空，忽略stderr；为native_process身份/控制/恢复写PID启动时间，间接授予控制与接班。建议固定路径和stderr拒绝。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-role.sh:164 authorize：PATH ps ppid=；run要求rc=0，父PID必须数字，最多64代祖先包含原生主控PID才授权；stderr不影响判定。间接授权控制和新代启动，建议固定路径并拒绝stderr。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-role.sh:208 current：PATH ps lstart=；rc=1且stdout/stderr strip空，或rc=0启动时间非空且不同（忽略stderr）；判断stopped后允许exit确认、retire、relaunch与pending启动。与本票同类风险最高，建议另票按相同原则加固并迁移角色身份假ps夹具；本票未动。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-lib.sh:152 qwb_gate_identity：PATH ps ppid=；check_output要求rc=0、父PID数字、最多64代祖先包含已登记门禁PID；stderr不单独检查。控制门禁/规划身份与后续账本授权，不直接删除，建议固定路径和stderr拒绝。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-wake.sh:861,863 block_owner_ok：PATH ps ppid=；stderr重定向丢弃，tr去空白后必须精确等于QWB_WATCH_PARENT_PID。控制Pi孤儿值守能否继续消费进展，不放行删除或新角色接班；建议独立加固固定路径并核rc/stderr。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-worktree.sh:253 writers_stopped：/bin/ps；type(pid) is int、pid>0、start字符串非空；stderr.strip必须为空；rc=1且stdout.strip空，或rc=0且非空start不同才放行。finish merged/archive、land和partial删树路径的基准，原样保留。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa - bin/qwb-ledger.sh:725只是tool指纹清单中的PATH ps，不执行进程查询；owner_dead实际用Perl kill(0,pid)且errno=ESRCH或Herdr pane_not_found，供recover-claim与handoff-reconcile接班，无PATH ps漏洞；PID-only无启动时间，是否扩展代次证明另票判断。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 补充无ps的死活点：qwb-lock.sh:81用kill -0失败即允许回收pid锁（未区分EPERM/ESRCH）；qwb-hook-claude-stop.sh:31用kill -0判hook锁后允许清理/接管（非法或未知亦可落入清理）；qwb-wake.sh:211,221只展示hook/pi-ext进程存活，:812只等待订阅启动。前两者宜另票审核未知拒绝，后两者不是删除/接班证明；本票均未动。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 测试迁移核查：六个现有PATH ps夹具位于collab-ci-diagnostics.sh、collab-gate.sh、collab-land.sh、collab-planning.sh、collab-roles.sh、collab-test-policy.sh，逐一追踪用于角色native身份/stamp/current模拟；collab-land关闭task Space的evidence已由/bin/ps读取真实子进程并wait回收，角色gate-pane不属于该Space。因此没有需要改成真实死亡证据的现有假ps收尾夹具，六文件未动。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 现有测试改动仅tests/collab-herdr.sh：最终272/276引入ExitStack收回自己的native；339-341将原os.getpid()活Pi替身改为真实启动、按PID terminate/wait的子进程；529/539,543-547将not-sent live/extra-pane的旧根PID改为自己真实启动的live_child并在ExitStack回收，启动时间改读/bin/ps；551的dead/extra-pane子进程start同改/bin/ps。原断言保持不变。新增100-213为七组公开close/finish对照与六种故障包装，214提供death-proof定向模式，默认全门仍执行新增对照。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 新增规格5独立提交6f3a8cc567772c4e17a1d971c00cad7a091fb2fa（父9231f81f1ecb9f3a58e38a7f6655b18463868bdc）：产品bin/qwb-herdr.sh:162只有多名字匹配时才筛选pid==foreground_process_group_id；筛后必须恰好一个且PID整数，组长不在同名集合或零名字匹配仍未知，唯一名字匹配行为原样。tests/collab-herdr.sh:12-99五种真实形态与真实子进程devin fresh dispatch→prompt前绑定组长PID/start→活时finish拒绝→全部子进程实际退出并wait→finish merged删除Space、副本、分支；Pi与Claude对同输入和起点逐字节比较，devin起点unknown无PID，修复拿到组长PID/start。
done: 2026-10-04T14:45:06Z sha=6f3a8cc567772c4e17a1d971c00cad7a091fb2fa 身份确实未知且缺PID的出路（只读核查，未改派发/收尾协议）：qwb-run.sh:770-778 record_worker_activity不检查unknown/缺PID，正常写旧启动代evidence；:791-793在写证据后照常prompt。qwb-worktree.sh:244-247保留每个(pane,op)完整evidence，同op追加不同证据被判冲突；:251,259每一条旧代都要求合法PID/start。因此即使后来真实退出、重复派发新op、新版activity重新认出当前PID、关闭Space或使用--root-tab-missing，都无法补掉旧代未知证据。当前没有可以补齐这代历史死亡证明并完成merged/archive删除的合规公开入口。可用finish case --keep=启动代PID未知待主控裁决显式记下保留路径与原因（:652-658 keep只记账，不关Space、不删Git、不修改死亡证据），或者保留现场交付/合入成果后另票修协议；这不是完成删除。不能删改旧证据冒充补救。建议主控另票决定派发绑不上PID时是否停止prompt，或设计受控补证协议。
working: 2026-10-04T14:55:48Z 主控验收：产品改动两处已逐行审（ended 改用 /bin/ps、stderr 非空或超时一律按未知拒绝；activity 在同名前台进程多于一个时取前台进程组组长，组长不在其中或零匹配照旧未知）；在副本 6f3a8cc 上独立跑 bash bin/qwb-test.sh full：rc=0、840 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、464.88s、无残留进程。真机佐证：主控把这两个提交连同验收脚本修复叠到候选副本上跑 tests/e2e-real.sh --worker devin --controller pi（magpie codex/gpt-6.1-sol high），rc=0、16 项断言全 PASS，devin 双进程身份绑定成功、finish 完成（报告存 .qwb-tmp/e2e/r2-pi-sol-devin.md）。已 cherry-pick 9231f81、6f3a8cc 到 main（HEAD 含 6761cfa）。执行者只读核查的结论（身份未知且缺 PID 时无合规出路）已另开 audit-writer-proof-missing。
