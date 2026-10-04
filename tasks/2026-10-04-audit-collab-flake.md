# 任务书：协作测试并发跑时清理失败（collab-handoff 收尾 rm 撞上残留子进程）

```
任务 id:  audit-collab-flake
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1 第 1 波合并全门（main 011389b）暴露
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，magpie codex/gpt-6.1-sol high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-collab-flake.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake（隔离副本，detached HEAD，起点 main 011389b）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

### 现象（主控实测，main 011389b）

`bash bin/qwb-test.sh full`：smoke、review-identity、lint 全过；`tests/collab-all.sh` 并发跑 11 个测试时 `tests/collab-handoff.sh` 退出码 1。它的 10 条断言全部 PASS，失败发生在退出清理：

    rm: <仓库>/.qwb-tmp/tmp.Dvo429dF/project/tasks: Directory not empty
    rm: <仓库>/.qwb-tmp/tmp.Dvo429dF/project: Directory not empty
    rm: <仓库>/.qwb-tmp/tmp.Dvo429dF: Directory not empty

残留目录里只剩一个 0 字节文件 `project/tasks/other.md.qwb-lock`（账本侧车锁；`qwb-ledger.sh read` 会创建它）。随后在同一 HEAD 上单独连跑 4 次 `bash tests/collab-handoff.sh`，4 次都是退出码 0、无 rm 报错。所以这是并发负载下的偶发：测试的 `trap 'rm -rf "$TMP"' EXIT` 执行时，还有一个子进程（很可能是某次 `qwb-wake.sh --block` 起的 `qwb-herdr.sh subscribe` 及其 python 子进程，它每秒对已迁票做一次 ledger read）活着并重新建出了侧车锁文件。

### 工程规格

1. **先定位**：找出到底是哪个进程在测试结束后还在写（给出证据：进程命令行、父子关系、它由测试的哪一步启动、为什么测试结束时没被回收）。可以在临时拷贝里给测试加诊断输出，或在并发负载下重复跑直到复现；报出复现率（跑了多少次、失败多少次）。
2. **判断归属并分别处理**：
   - 若是**测试**没有回收自己启动的进程（例如只 `killpg` 了外层、没等孙进程退出）：修测试——退出前先确保它启动的全部进程已结束，再删目录。不要用「rm 失败就重试几次」这种掩盖竞态的写法。
   - 若是**产品**在正常退出路径上漏回收子进程（例如 `bin/qwb-wake.sh` 的 `event_cleanup` 只杀了外层 bash、python 子进程成了孤儿）：这是产品缺陷，**不要改 `bin/`**，写一条 `needs-decision:` 把证据和你建议的修法报给主控，同时照上一条把测试自己的回收补稳。
3. **排查同类**：其余 `tests/collab-*.sh` 与 smoke 调用的子测试脚本里，有没有同样「起了后台产品进程、退出时直接 rm」的写法；有就一并按同样原则处理，逐个列出。
4. 不改各测试的断言内容。

白名单：`tests/` 下的文件。**不改 `bin/` 与 `templates/`。**

## 1. 验收场景

### user_正常路径_并发跑批连续多次全绿

Given 只含本票改动的隔离副本
When  连续跑 5 次 `bash tests/collab-all.sh`
Then  5 次退出码都是 0、末行都是 COLLAB-ALL PASS，输出里没有任何以 rm: 开头的行；每次跑完 `.qwb-tmp/` 下不留本次建的目录

### user_失败路径_改动前的问题能被复现

Given 起点提交（main 011389b）的拷贝
When  在并发负载下重复跑 `tests/collab-handoff.sh`（例如同时跑 collab-all，或人为并发多份）
Then  至少复现一次清理失败并留下证据（哪个进程、哪个文件）；若跑了足够多次仍不复现，如实报次数与条件，并说明你的修复依据的是代码分析而非复现

### user_失败路径_断言失败时退出码仍然非零

Given 在临时拷贝里把 collab-handoff 的某一条断言改成必然失败
When  跑它
Then  退出码非 0 且输出里有该断言的失败信息——清理逻辑的改动没有把真实失败吞掉

### user_失败路径_测试被中断时不留孤儿进程

Given 跑 `tests/collab-handoff.sh` 到一半时对它发 TERM
When  等 5 秒后检查
Then  没有任何命令行里带该次临时目录路径的进程存活；该次临时目录已删除或只剩可解释的残留并写明

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根 `/Users/rocky/projects/qonnwolfbuddy` 下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。测试现在都带失效关闭的隔离，不要移除或绕过它。
- **临时文件**：只许删除你自己建出来并记在变量里的确切路径，一次一个。禁止任何带 `*` 的 `rm`。杀进程只许杀你自己启动并记下 PID 的进程，禁止按名字模式批量杀（本机还有别的项目的 pi、wake、herdr 在跑）。
- git：只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2。状态行时间戳取自机器。状态行里不要出现尖括号占位写法。阶段性进展用 `working:`，只有全部完成才写 `done:`。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 四个场景逐个验证，命令与原始结果写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到你自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `bin/`、`templates/`、文档；不改测试断言；不给测试提速或重构。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T00:02:43Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（默认 magpie codex/gpt-6.1-sol high） agent=qwb-audit-collab-flake pane=w14Z:p8 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake base=011389b
working: 2026-10-04T00:06:12Z 阶段1：完整读取规格及 qwb-test/collab-all/collab-handoff、wake 订阅清理与 herdr targets 路径；基线8份handoff并发启动，采样超出60秒工具期限，任务仍运行，正在按已记录PID接续采证；证据目录=.worktrees/audit-collab-flake/.qwb-tmp/audit-evidence-nnqhkpq1。
working: 2026-10-04T00:14:16Z 阶段1自然复现：起点011389b，8份 tests/collab-handoff.sh 同时执行，1/8退出1，其余7/8退出0；失败日志repeat-3.log中10条PASS后3条rm错误，残留tmp.DNenKXMY/project/tasks/answered-question.md.qwb-lock大小0；原始receipt=隔离副本/.qwb-tmp/audit-evidence-nnqhkpq1/repeat.json，订阅PID/PPID采样=repeat-processes.txt；另8份首次采样超时，均到10条PASS但无完整退出回执，不计入复现率。
needs-decision: 2026-10-04T00:22:12Z 产品缺陷证实（未改bin）：qwb-wake正常--block退出2后，event_cleanup只kill/wait EVENT_PID订阅器，订阅器exec Python的targets()正在subprocess.run(qwb-ledger.sh read)时，其读账子进程漏回收；受控PATH bash/FIFO边界记录wake=8365、subscribe=8441、ledger-read=8455，退出后8455的PPID=1，释放FIFO后重新生成case.md.qwb-lock大小0。证据=隔离副本/.qwb-tmp/audit-evidence-nnqhkpq1/product-leak.json；该受控探针只延后读账启动，产品代码原样。建议另票修subscribe中活动子进程的TERM/INT finally终止并wait，或wake独占进程组并排空后删EVENT_DIR；本票继续仅修tests自己的进程回收。
working: 2026-10-04T00:22:12Z 阶段2/3：测试侧引入每测试独占进程组监督与临时目录删除前排空，登记单独setsid组，保持原断言；同类处理collab-handoff/gate/herdr/ledger/planning/posture/land，smoke及子测试lifecycle-readiness/runtime-readiness/wake-block-output/r4-cli，collab-all中断清理等待已启动子测试退出。roles/ci-diagnostics/test-policy与其余smoke子测的同步once/dry-run未发现订阅后台泄漏，不改。自然复现1/8与受控产品孤儿重建锁均已留原始证据，固定handoff单次退出0、原10PASS、无rm错误。
working: 2026-10-04T00:22:48Z 主控裁决（回应 00:22:12Z 的 needs-decision）：认定为产品缺陷，另开后续票修 bin/qwb-herdr.sh 的订阅器（收到 TERM/INT 时终止并回收正在进行的读账子进程），本票不改 bin/。本票继续只修 tests 自己的进程回收；测试侧不得依赖产品尚未修好的回收行为，也不得用重试 rm 掩盖。完成后照常报 done，后续产品票届时派给你（沿用本会话与证据）。
working: 2026-10-04T00:30:04Z 阶段4验收中：快门/bin/bash bin/qwb-test.sh fast退出0；新增python3 tests/process-fixture-check.py退出0，证明真实失败7及stdout原样保留、TERM-resistant后代退出后才返回、TERM143与记录子PID确死；全部tests/*.sh用系统/bin/bash3.2 -n退出0。并发第1轮collab-all退出0，末行COLLAB-ALL PASS（11 项），无rm错误/本轮目录残留；正在第2轮。已补独立进程组及时排空并注销，避免把旧PID保留到退出清理；后续以最后5轮最终代码结果验收。
working: 2026-10-04T00:52:14Z 阶段4：并发第2/3/4轮均退出0，11 PASS、0 FAIL，末行COLLAB-ALL PASS（11 项），逐轮无rm错误/新目录残留；smoke root-tab-missing、lifecycle-readiness、runtime-readiness、wake-block-output、r4-cli五个定向入口全部退出0，原始结果targeted.json。额外collab-land退出1于recover-endpoint关闭/焦点读回断言，日志无rm错误；该脚本原先未接入默认全门，正在用011389b原脚本对照确认失败归属，不修改原断言。第5轮、失败断言/TERM及最终代码补轮仍执行中。
working: 2026-10-04T00:54:53Z 阶段4：失败断言临时拷贝退出1，原始日志明确AssertionError: FORCED_HANDOFF_ASSERTION_FAILURE，无rm错误/新目录残留；对handoff记录PID45584发TERM，退出143，5秒后目录.qwb-tmp/9965已删除且路径匹配存活进程0。collab-land当前版和011389b原样拷贝均在recover-endpoint同一关闭/焦点读回断言退出1，确认既有失败（land-check.json/land-baseline.json），未更改断言或默认全门清单。测试代码已提交32cb242，正在最终代码第6轮；连续最终5轮以2..6计，随后跑提交后full。
working: 2026-10-04T01:05:08Z 阶段4完成：最终代码连续5轮collab-all（2..6）退出码=0,0,0,0,0；末行均COLLAB-ALL PASS（11 项）；逐轮11 PASS/0 FAIL，rm错误0，新目录0；耗时277.31/350.38/343.24/235.63/223.89秒，原始结果validation.json和collab-6.json。基线自然复现1/8、失败断言1、TERM143并5秒后无目录/活进程已逐项验收；原始baseline残留已复制到证据baseline-residual后删除其确切原路径。提交32cb242aed4d3c6b73802010d303af4c82632dcb，parent=011389b0e578307a63ff3335b72e438071fdacd4，16文件全部在tests/；阶段5提交后bash bin/qwb-test.sh full已启动，PID17160，日志=隔离副本/.qwb-tmp/audit-evidence-nnqhkpq1/full.log，等待完整退出回执。
working: 2026-10-04T01:25:14Z 阶段5返修：首次full在smoke成功提示处失败（raw full.log含FC_RC非法UTF8变量名）；此前误判看门狗，诊断修正：fake-now=3000、45条sleep记录、原3轮完成、watchdog-fired不存在，正常TERM已发生。根因是监督器硬编码/bin/bash把PATH Bash5调用降到3.2；现改为保留调用方BASH，不动任何原断言/预算，并补默认Bash5与系统3.2解释器保真回归（3条PASS、退出0）。将重跑最终代码五轮与四场景后提交后full，先前记录不作最终版全绿声明。原始失败/诊断证据仍在full.log、clock-diagnostic-fixture。
working: 2026-10-04T01:42:00Z 返修后阶段4：最终提交f55544efdd730628c0a63786c0460a6393824be8；第二轮快门退出0，新解释器/真实失败/TERM回归退出0；原smoke三个250/600/0假钟预算诊断全部通过、退出0。final-validation下连续跑批第1/2轮均退出0、11 PASS/0 FAIL、COLLAB-ALL PASS，无rm错误或新目录；正在第3轮，随后失败断言/TERM重验及提交后full。两次提交均在本隔离副本，bin/templates仍未改。
working: 2026-10-04T01:52:06Z 返修后阶段4完成：f55544e最终版连续5次collab-all退出码0,0,0,0,0，逐次11 PASS/0 FAIL、末行COLLAB-ALL PASS（11 项）、rm错误0、新目录0；耗时338.45/335.16/228.88/221.87/226.73秒。断言失败拷贝退出1且有FORCED_HANDOFF_ASSERTION_FAILURE，TERM实际PID76275退出143、等待5秒后.qwb-tmp/4137已删除、路径匹配存活进程0；原始结果final-validation/validation.json。返修后提交后full已启动，PID76852，最终日志final-validation/full.log；这次先写独立full-exit.json退出回执再按raw bytes解析日志，避免非法UTF8损坏汇总。等待全门完成，未写done。
done: 2026-10-04T02:04:17Z commit=f55544efdd730628c0a63786c0460a6393824be8 base=011389b0e578307a63ff3335b72e438071fdacd4，提交链32cb242aed4d3c6b73802010d303af4c82632dcb→f55544efdd730628c0a63786c0460a6393824be8（2次普通提交，集成须包含两次）；16文件全在tests/，bin/templates不改，原断言不改，git clean；测试独占进程组/另起setsid登记、排空注销后才删自有目录，包装保留调用BASH/argv/标准流，无rm重试。 正常场景命令=/bin/bash tests/collab-all.sh连续5次，rc=0,0,0,0,0，逐次11 PASS/0 FAIL、末行COLLAB-ALL PASS（11 项），rm错误0、每轮新目录0，秒数=338.45,335.16,228.88,221.87,226.73。 旧版失败场景=011389b原tests/collab-handoff.sh同时8份，rc=0,0,0,1,0,0,0,0，1/8在10 PASS后3条rm错误，留下answered-question.md.qwb-lock大小0；自然残留已存baseline-residual并删除原确切路径。 writer证据=原产品qwb-wake --block经subscribe targets→ledger read；受控PATH bash/FIFO探针wake8365正常rc2、subscribe8441退出、read8455变PPID1，释放后重建case.md.qwb-lock大小0；已由主控裁决另票修产品。 断言失败场景命令=/bin/bash tests/.handoff-failure-56819.sh（自有临时拷贝，已删除），rc=1，AssertionError: FORCED_HANDOFF_ASSERTION_FAILURE，rm错误0、新目录0。 中断场景命令=/bin/bash tests/collab-handoff.sh后对记录PID76275发TERM，rc=143，等待5秒后/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/4137不存在、路径匹配存活进程0。 快门=/bin/bash bin/qwb-test.sh fast rc0；Bash3.2所有tests/*.sh语法检查0；python3 tests/process-fixture-check.py rc0，系统3.2与PATH Bash5保真、真实7不吞与TERM143/子PID结束均PASS。 提交后全门=bash bin/qwb-test.sh full rc=0，594.38秒，PASS行数=830、FAIL行数=0（列首^PASS/^FAIL），rm错误0、新目录0；末尾5行各前100字符=["PASS  tests/collab-roles.sh（62s）", "PASS  tests/collab-test-policy.sh（87s）", "PASS  tests/lint-scenario-stream.sh（1s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"]。 同类修复逐项=collab-handoff/gate/herdr/ledger/planning/posture/land、smoke、lifecycle-readiness/runtime-readiness/wake-block-output/r4-cli；collab-all中断收尾wait；roles/ci-diagnostics/test-policy仅同步入口未改。额外collab-land在011389b原脚本与32cb版均同一recover-endpoint关闭/焦点读回断言rc1，既有不在默认全门，未降级其断言或清单。 完整原始结果=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-evidence-nnqhkpq1/final-validation/acceptance.json；全门raw日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-evidence-nnqhkpq1/final-validation/full.log、独立退出回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-evidence-nnqhkpq1/final-validation/full-exit.json；基线/进程原始证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-evidence-nnqhkpq1/repeat.json、repeat-3.log、repeat-processes.txt、product-leak.json；首次全门的解释器问题已返修并重跑最终五轮及full，旧结果不作最终全绿。
working: 2026-10-04T02:16:57Z 主控验收（返修 1）：在副本 f55544e 上独立跑 bash bin/qwb-test.sh full：rc=0、830 PASS / 0 FAIL、COLLAB-ALL PASS（11 项）、无 rm 报错、575.01s；跑前跑后真 Herdr 拓扑不变。两处须返修后再落地：一、全门跑完后 git status 出现未跟踪的 tests/__pycache__/（新夹具模块被不带 -B 的 Python 导入所生成），全门不得弄脏工作区；二、发现一个孤儿进程 PID 42923（PPID=1，PGID 41373，本机时间 2026-10-04 02:32:29 启动，命令为本副本的 tests/fixtures/herdr/wire-server.py），它早于主控这次全门，出自执行者某次中间运行；主控已按确切 PID 结束它。请查明是哪条命令留下的，并确认最终代码的各入口（含 smoke 的 root-tab-missing 窄入口与被 TERM 中断的路径）都不会留下它。
working: 2026-10-04T02:22:28Z 返修1定位：旧targeted.py明确执行bash tests/smoke.sh root-tab-missing；targeted-run.log出生于本机02:32:27.752、该窄入口日志02:32:27.865，与主控记录server42923启动02:32:29及PGID41373（该次工具shell组）相符。该分支在qwb_test_scope前运行，拼接stdin脚本$0=bash、qwb_test_drain按marker跳过，EXIT只rm并漏掉wire-server。缓存问题是普通heredoc首次导入process_fixture生成.pyc，前次手删缓存只能清理当次，不能保证再次全门干净。将先受控复现窄入口孤儿，再把监督前移覆盖分支/片段，并在导入前禁写字节码；不改原断言/预算、bin/templates。纠正记入本票主账本及持久经验，不超白名单改lessons文档。
working: 2026-10-04T03:01:03Z 返修1关键验证：f555旧窄入口受控重现rc0，wire59264存活且PPID1/PGID59038（证据baseline-wire.json；仅该次自有PID已清理）。修复把smoke监督启动前移到所有分支，stdin拼接只删除重新启动监督的调用并继承/执行外层drain，消除$0=bash跳过清理；shell来源/监督器子环境禁写.pyc，r4与自检入口在导入前sys.dont_write_bytecode=True。新增公开入口回归记录实际wire exec PID/PGID：默认Bash及系统3.2窄入口均rc0；窄入口TERM、常规smoke TERM、handoff TERM均rc143，5秒后自有进程组非僵尸成员0、目录0、字节码0；原断言/预算不改。其余9个受监督入口TERM矩阵执行中，原始日志entry-check-final.log。
working: 2026-10-04T03:25:11Z 返修1定向验收完成：公开入口回归5项、普通Python r4入口、9个其余受监督脚本TERM矩阵均通过；实际wire PID/PGID已记录，正常窄入口rc0，中途TERM rc143，5秒后成员0/目录0/字节码0；原始证据targeted-final.json、entry-final.log、all-term-final.log。监督marker同时绑定直属supervisor PPID，避免同一脚本嵌套继承marker而误跳过监督；不动原断言/预算。准备提交后全门，后续不手删缓存，以原样git status证明干净。
working: 2026-10-04T03:29:20Z 返修1已追加提交0b9faefac693273c3bf10e949259b78a76a17eb6（parent=f55544e，6文件全在tests/），定向入口/字节码/TERM矩阵通过，git status --short当前输出为空。提交后bash bin/qwb-test.sh full启动；日志audit-rework-1/full.log、独立full-exit.json，并在退出后立即原样保存git-status-after.txt与命令行含本副本路径的非僵尸存活进程清单worktree-live-processes.txt。之后不手删.pyc或杀进程，以真实状态验收。
done: 2026-10-04T03:54:21Z 返修1commit=0b9faefac693273c3bf10e949259b78a76a17eb6 parent=f55544efdd730628c0a63786c0460a6393824be8（已追加普通提交，6文件全在tests/）；bin/templates与原断言/预算不改。 历史孤儿42923来源=此前targeted.py执行的bash tests/smoke.sh root-tab-missing：targeted-run.log及该窄入口日志出生于本机02:32:27.752/02:32:27.865，对应主控记录02:32:29及工具shell PGID41373。旧代码在qwb_test_scope前进入该分支，stdin片段$0=bash导致drain按marker跳过；f555受控同命令rc0仍留wire59264、PPID1/PGID59038，baseline-wire.json记录真实命令与父子关系，该次自有PID已清理，未操作历史42923。 修复=监督先于所有分支；stdin片段继承外层scope并真实drain；marker绑定直属supervisor PPID，避免嵌套同脚本继承跳过监督；PYTHONDONTWRITEBYTECODE在shell来源与监督器子环境设置，普通Python独立r4/self-check入口在导入前sys.dont_write_bytecode=True，无gitignore隐藏或全门后手删缓存。 新公开入口回归python3 tests/process-entry-cleanup.py rc0：默认Bash与系统/bin/bash3.2窄入口都实际记录wire exec PID/PGID并rc0；窄入口TERM、常规smoke TERM、handoff TERM均143，等待5秒后进程组非僵尸成员0、新目录0、字节码0。其余collab-gate/herdr/land/ledger/planning/posture与lifecycle-readiness/runtime-readiness/wake-block-output的实际产品子进程启动后TERM矩阵9项均143，5秒后成员0/目录0/字节码0；普通python3 tests/r4-cli.py和解释器/失败退出/TERM自检rc0。 提交后一次bash bin/qwb-test.sh full自然rc=0，596.55秒，列首^PASS=830、^FAIL=0，rm错误0、新目录0；末尾5行各前100字符=["PASS  tests/collab-roles.sh（59s）", "PASS  tests/collab-test-policy.sh（82s）", "PASS  tests/lint-scenario-stream.sh（1s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"]。 全门后原样git status --short输出=""（0字节，无任何输出），命令行含本副本绝对路径的非僵尸存活进程清单=[]（0条）；采集前后没有删.pyc/清目录/杀进程洗绿，tests/__pycache__不存在，当前git仍clean。 原始全门日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/full.log；自然退出回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/full-exit.json；全门后git原样输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/git-status-after.txt；完整存活进程原样清单=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/worktree-live-processes.txt；汇总=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/full.json；定向原始证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-flake/.qwb-tmp/audit-rework-1/targeted-final.json、entry-final.log、all-term-final.log；历史命令记录仍保留audit-evidence-nnqhkpq1/targeted.py与targeted-run.log。
working: 2026-10-04T04:06:43Z 主控验收（返修 1 通过）：审过进程登记夹具（只按本测试自建的进程组排空，不按名字匹配）；在副本 0b9faef 上独立复验：先单跑 bash tests/smoke.sh root-tab-missing rc=0 且其后命令行含副本路径的存活进程为 0；再跑 bash bin/qwb-test.sh full：rc=0、830 PASS / 0 FAIL、COLLAB-ALL PASS（11 项）、rm 报错 0、576.72s；全门后 git status --short 无输出、存活进程 0；跑前跑后真 Herdr 拓扑不变。已 ff-only 合入 main（HEAD=0b9faef，含 32cb242、f55544e、0b9faef），未 push。产品缺陷（值守退出时订阅器的读账子进程漏回收）另开 audit-subscribe-reap。
