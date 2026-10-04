# 任务书：smoke 断言不再被大输出的 SIGPIPE 误伤；lint 占位行警告截断

```
任务 id:  audit-lint-pipe
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1 第 1 波合并全门（main 90fd3f4）暴露；与 F1 同类（测试断言随账本内容变脆）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，magpie codex/gpt-6.1-sol high；沿用 audit-gate-repair 的会话与副本）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-lint-pipe.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-repair（隔离副本，detached HEAD，在 0b1580a 之上追加提交）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

### 现象（主控实测，main 90fd3f4，2026-10-03T22:50Z 前后）

主仓合并全门在 smoke 第 51 节出现 `FAIL  lint 未过或无死键检查 PASS（rc=0）`，而紧跟着打印的 lint 输出里 `LINT PASS` 与「键全部被…引用」都在。

### 根因

1. `bin/qwb-lint.sh` 第 10 项把每一条「列首占位状态行」的**整行原文**拼进一条警告。主仓账本里这种行很多、很长，`bash bin/qwb-lint.sh --project <主仓>` 的输出现在有 262510 字节。
2. `tests/smoke.sh` 有 18 处 `printf '%s' "$lintout" | grep -q '…'`。smoke 开了 `pipefail`；输出超过管道缓冲（约 64KB）时，`grep -q` 一匹配就退出，`printf` 收到 SIGPIPE，整条管道按失败算——断言假阴性，而且带竞态（同一次运行里第 25 节过了、第 51 节没过）。
3. 干净副本里 `tasks/` 没有今天这些未提交的票，输出小，所以一直是绿的。提交 `d3dd690` 在 lint 里修过同一类问题（「drain scenario grep input to avoid pipefail SIGPIPE false negatives」），smoke 这边没跟上。

### 工程规格

**A. smoke 断言去管道（必须做）。** `tests/smoke.sh` 里所有「把一个已捕获的变量经 `printf`/`echo` 管道喂给 `grep -q`（或其他会提前退出的命令，如 `head`）」的断言，改成不会产生 SIGPIPE 的写法。先 `grep -n` 把全文件这类写法列全（不止 `$lintout` 那 18 处，其他变量名的同型写法一并处理），再统一改。推荐 here-string：`grep -q '…' <<<"$var"`；注意 here-string 会在末尾补一个换行，逐处确认这不影响该断言（对 `grep -c`、`grep -x`、行数统计要特别小心）。拿不准的个别处可改成 `grep '…' >/dev/null`（读完全部输入、不提前退出），并写明原因。不改任何断言的匹配内容、`ok`/`bad` 文案与先后顺序。

**B. lint 第 10 项警告截断（必须做）。** `bin/qwb-lint.sh` 拼占位行警告时，每条原文只保留前 80 个**字符**（不是字节，不能把多字节字符切成非法 UTF-8；可复用 `bin/qwb-lib.sh` 里的 `qwb_utf8_excerpt`，或在一次 perl 里完成），超出部分以 `…` 结尾。其余文案、`pass` 行、退出码不变。顺带把「每条警告行起一个 `basename` 子进程」换成参数展开。先查 smoke 与其他测试有没有断言这条警告的具体内容（第 58 节一带），有就保证它们仍然成立。

**C. 回归保护（必须做）。** 在 smoke 末尾「新节必须加在本行之前」的标记之前加一节：造一个临时项目，其账本里有足够多、足够长的列首占位状态行，使未截断时 lint 输出超过 200KB；断言 (1) lint 仍 `LINT PASS` 且退出码 0，(2) 输出总字节数小于 64KB，(3) 警告里每条引用不超过 80 字符加省略号，(4) 用与第 51 节相同的断言写法在该输出上连续判断 20 次都成立。

**D. `tests/collab-all.sh` 套用测试隔离（主控 2026-10-03T23:16Z 追加，原因：测试隔离票 audit-test-isolation 已落地 main，但它不知道你新加的这个文件）。** 照 main 上 `tests/collab-gate.sh` 开头现在的写法（可用 `git -C /Users/rocky/projects/qonnwolfbuddy show HEAD:tests/collab-gate.sh` 只读查看）：导出指向死路径的 `HERDR_SOCKET_PATH`；日志目录改建在 `<仓库根>/.qwb-tmp/` 下（先 `mkdir -p`），不再用系统临时目录；退出时只删自己建的那一个目录。不要在 collab-all.sh 里改 `TMPDIR` 给子测试（各测试自己会设）。验证：跑一次 `bash tests/collab-all.sh`，确认全绿、跑的过程中日志目录在 `.qwb-tmp/` 下、跑完后该目录已删、系统临时目录没有新增本脚本建的目录。

白名单：`tests/smoke.sh`、`bin/qwb-lint.sh`、`tests/collab-all.sh`。

## 1. 验收场景

### user_正常路径_主仓布局下全门不再因大输出误红

Given 副本里临时放一份 `tasks/` 夹具（或直接用上文 C 的临时项目），其 lint 输出在改动前超过 200KB
When  改动前后各跑 smoke 中调用 lint 并用 `grep -q` 判断的那几节（第 25、51 节等）各 20 次
Then  改动前至少出现一次假阴性（证明复现了问题；若 20 次都没出现，加大输出或次数直到复现，并报实际数字）；改动后 20 次全部通过

### user_正常路径_干净副本全门不回归

Given 只含本票改动（叠在 0b1580a 之上）的隔离副本
When  跑 `bash bin/qwb-test.sh full`
Then  退出码 0、0 FAIL，PASS 数等于改动前该副本的 826 加上新节的断言数，`SMOKE PASS`、`LINT PASS`、`COLLAB-ALL PASS` 都在；smoke 输出的最后一个节标题是你新加的那一节

### user_失败路径_断言在真该失败时仍然失败

Given 把 lint 输出替换成不含 `LINT PASS` 的文本、以及不含「键全部被…引用」的文本（在临时拷贝里做，不提交）
When  跑第 51 节那条断言
Then  两种情况都报 `FAIL  lint 未过或无死键检查 PASS`——去管道没有把断言改成恒真

### user_失败路径_截断不产生非法UTF-8也不丢警告

Given 一张票，列首占位状态行在第 79–82 个字符处正好是多字节中文字符，另有一条不足 80 字符的占位行
When  跑 lint
Then  输出整体是合法 UTF-8；长行被截到 80 字符加 `…`，短行原样；两条都出现在警告里；退出码与 `pass` 行不变

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根 `/Users/rocky/projects/qonnwolfbuddy` 下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。
- **临时文件**：只许删除你自己建出来并记在变量里的确切路径，一次一个。禁止任何带 `*` 的 `rm`。
- git：只许在自己的副本里 `git add <白名单文件>` 与 `git commit`（在 0b1580a 之上追加，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 行为不变：除 B 的警告截断外，lint 的检查逻辑、`pass`/`fail` 行、退出码不变；smoke 各断言的判定语义不变。
- 兼容 macOS 自带 `/bin/bash` 3.2（here-string 可用）。状态行时间戳取自机器。**状态行里不要出现尖括号占位写法**（否则本票自己会被 lint 第 10 项当成占位行）。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；新 smoke 节必须加在末尾标记之前，不能落在 `exit 0` 之后。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 四个场景逐个验证，命令与原始结果写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到你自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、最后一个节标题、输出最后 5 行里每行的前 100 个字符。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。阶段性进展用 `working:`，只有全部完成才写 `done:`。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改历史任务书（不去缩进或删除旧票里的占位状态行）。
- 不动 lint 其他检查项，不给 smoke 提速或重构。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-03T22:51:58Z 主控手工派发（同 Space 独立 Tab「修门·pi」，沿用 audit-gate-repair 的 Pi 会话与副本）：worker=pi（magpie codex/gpt-6.1-sol high）agent=qwb-audit-gate-repair pane=w14Z:p3 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-repair base=0b1580a
working: 2026-10-03T22:54:15Z Sol 已完整读取新票；工作副本HEAD=0b1580a0c155b759f5485c885d2b11cca33c1f8e且干净。开始列全捕获变量的早退管道、核查第10项及已有警告测试，只改新票白名单，状态仅写本票。
working: 2026-10-03T23:14:52Z 主控修订规格：工程规格新增 D 项（tests/collab-all.sh 套用测试隔离与仓内临时目录），白名单相应增加该文件；验收场景未改。
working: 2026-10-03T23:19:21Z Sol 已纳入新增D：只读参照main 1125c448的collab-gate开头，collab-all导出/dev/null/qwb-test.sock；日志明确建在本副本.qwb-tmp内，子测试TMPDIR不变。A-C本人实测：旧51断言20/20假阴性、PIPESTATUS=141/0；新25与51在370937字节原输出及截断后输出上各20次全部通过，缺LINT PASS和缺引用关键字仍FAIL；UTF-8长行80字符加省略号、短行制表符原样。新87节4个PASS已用/bin/bash实跑。D默认11项验收执行中。
working: 2026-10-03T23:28:38Z Sol 候选已在0b1580a上追加提交c757665525f99124828798cd41aef303a9eb4956；三份白名单，工作区干净。快门、脚本语法、collab-all shellcheck均0；D默认11项退出0、232.91s、仓内确切日志目录已删除、子TMPDIR不变。四场景定向证据已收齐；提交后唯一一次真实full已启动，预期826加新节4条=830 PASS，等自然退出后才写done。
done: 2026-10-03T23:46:31Z Sol 全部完成；HEAD=c757665525f99124828798cd41aef303a9eb4956；提交后一次真实full退出0，PASS=830=826+4，FAIL=0，耗时644.47s；smoke末节为87.lint大输出与占位警告UTF-8截断回归。命令与原始结果（JSON转义尖括号，解码后原文不变）：{"final_HEAD": "c757665525f99124828798cd41aef303a9eb4956", "base": "0b1580a0c155b759f5485c885d2b11cca33c1f8e", "changes": {"smoke": "先grep-n全量清单；199处直接输入改here-string（含lintout18处），1处两级过滤末端排空stdin；计数管道不变，原匹配内容、ok/bad文案和先后顺序已字节回溯；新增末尾87节正常路径4条断言", "lint": "仅第10项；保留原grep判定与pass/fail退出逻辑；每文件一次Perl decode/字符substr前80、超长加省略号；短行制表符不变；basename换成参数展开", "isolation": "仅collab-all；指向/dev/null/qwb-test.sock；显式仓内.qwb-tmp模板，退出仅删本次目录；不设置子TMPDIR"}, "commands": ["grep -nE 枚举全文件所有printf/echo管道、quiet grep与head；清单保存于/tmp/qwb-lint-pipe-sol.Ed8yqONN/all-grep-inventory.txt", "python3 /tmp/qwb-lint-pipe-sol.Ed8yqONN/targeted.py", "python3 /tmp/qwb-lint-pipe-sol.Ed8yqONN/live-and-section.py", "python3 /tmp/qwb-lint-pipe-sol.Ed8yqONN/isolation.py", "bash bin/qwb-test.sh fast", "bash -n tests/collab-all.sh && /bin/bash -n tests/collab-all.sh && shellcheck tests/collab-all.sh", "bash -n tests/smoke.sh && /bin/bash -n tests/smoke.sh && bash -n bin/qwb-lint.sh && shellcheck bin/qwb-lint.sh", "git diff --check", "git add tests/smoke.sh bin/qwb-lint.sh tests/collab-all.sh；git commit -m \"test: avoid lint SIGPIPE and isolate concurrent test logs\""], "targeted_raw": {"old_bytes": 370937, "new_bytes": 27425, "raw_pass_lines_unchanged": true, "refs": 102, "utf8_rc": 0, "long_chars": 81, "short_unchanged": true, "PIPESTATUS": "141 0", "trials": [{"name": "old-large", "section": 25, "shell": "bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "old-large", "section": 25, "shell": "/bin/bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "old-large", "section": 51, "shell": "bash", "rc": 0, "failures": 20, "trials": 20, "summary": "SUMMARY failures=20/20"}, {"name": "old-large", "section": 51, "shell": "/bin/bash", "rc": 0, "failures": 20, "trials": 20, "summary": "SUMMARY failures=20/20"}, {"name": "new-large", "section": 25, "shell": "bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-large", "section": 25, "shell": "/bin/bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-large", "section": 51, "shell": "bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-large", "section": 51, "shell": "/bin/bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-truncated", "section": 25, "shell": "bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-truncated", "section": 25, "shell": "/bin/bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-truncated", "section": 51, "shell": "bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"name": "new-truncated", "section": 51, "shell": "/bin/bash", "rc": 0, "failures": 0, "trials": 20, "summary": "SUMMARY failures=0/20"}, {"missing": "LINT PASS", "observed": "FAIL  lint 未过或无死键检查 PASS（rc=0）", "check_rc": 0}, {"missing": "config引用", "observed": "FAIL  lint 未过或无死键检查 PASS（rc=0）", "check_rc": 0}]}, "live_raw": {"live_comparison": [{"name": "old-public", "shell": "/bin/bash", "rc": 0, "seconds": 15.41, "public_invocations": 20, "section25_failures": 0, "section51_failures": 20, "raw_summary": "SUMMARY public=20 section25=0/20 section51=20/20"}, {"name": "new-public", "shell": "/bin/bash", "rc": 0, "seconds": 4.33, "public_invocations": 20, "section25_failures": 0, "section51_failures": 0, "raw_summary": "SUMMARY public=20 section25=0/20 section51=0/20"}], "new_section_rc": 0, "new_section_PASS": 4, "new_section_raw": "== 87. lint 大输出与占位警告 UTF-8 截断回归 ==\nPASS  大账本 lint 仍退出 0 且 LINT PASS\nPASS  截断后的 lint 总输出小于 64KB\nPASS  102 条警告保留且按 80 个字符截断，UTF-8 与短行原文不变\nPASS  第 51 节同型断言连续 20 次全部通过\n", "output_bytes": 27477}, "UTF8_short_boundary_stderr": "警告：发现列首占位状态行（不算 FAIL，但值守指纹与疑点门会把它们当真，建议删除或缩进）： 2099-01-01-big.md（占位状态行: blocked: aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa中文…） 2099-01-01-big.md（占位状态行: done: \u003c短\u003e 保留\t制表符）\n", "isolation_D_raw": {"command": "bash tests/collab-all.sh", "rc": 0, "seconds": 232.91, "logs_during_run": ["/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-gate-repair/.qwb-tmp/collab-all.x9nIFZRg"], "all_own_logs_removed": true, "system_tmp_own_logs_created": false, "caller_TMPDIR": "/var/folders/s6/1ctcm6010k911b19ckg_gkrm0000gn/T/", "child_TMPDIR": "/var/folders/s6/1ctcm6010k911b19ckg_gkrm0000gn/T/", "HERDR_SOCKET_PATH": "/dev/null/qwb-test.sock", "short_rc": 0, "lines": ["PASS  tests/collab-ci-diagnostics.sh（63s）", "PASS  tests/collab-gate.sh（233s）", "PASS  tests/collab-handoff.sh（59s）", "PASS  tests/collab-herdr.sh（58s）", "PASS  tests/collab-ledger.sh（42s）", "PASS  tests/collab-planning.sh（131s）", "PASS  tests/collab-posture.sh（65s）", "PASS  tests/collab-roles.sh（60s）", "PASS  tests/collab-test-policy.sh（84s）", "PASS  tests/lint-scenario-stream.sh（2s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"]}, "full_once_raw": {"sha": "c757665525f99124828798cd41aef303a9eb4956", "command": "bash bin/qwb-test.sh full \u003e /tmp/qwb-lint-pipe-sol.Ed8yqONN/full.log 2\u003e&1", "rc": 0, "seconds": 644.47, "PASS": 830, "FAIL": 0, "last_smoke_section": "== 87. lint 大输出与占位警告 UTF-8 截断回归 ==", "last_overall_section": "== 10. 任务书正文无占位状态行（只警告，不 FAIL）==", "tail5_first100": ["PASS  tests/collab-roles.sh（62s）", "PASS  tests/collab-test-policy.sh（86s）", "PASS  tests/lint-scenario-stream.sh（2s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（11 项）"], "SMOKE_PASS": true, "LINT_PASS": true, "COLLAB_ALL_PASS": true}, "final_quality": "全部通过；真实full仅提交后一次；830=原826+新节4条，0 FAIL，SMOKE/LINT/COLLAB三总结俱在；Git工作区干净，父提交0b1580a，只三份获批文件", "main_read_only_reference": "D参照main 1125c448ea558b60c401f7400bd09209a41d03ef的collab-gate开头；未写主仓其他文件或真Herdr状态", "evidence_dir": "/tmp/qwb-lint-pipe-sol.Ed8yqONN"}
working: 2026-10-04T00:03:02Z 主控验收：审过 diff（smoke 199 处变量经管道喂 grep -q 改 here-string、1 处两级过滤改末端排空；lint 第 10 项每条警告按字符截 80 加省略号；collab-all.sh 导出死路径 HERDR_SOCKET_PATH、日志目录改到仓内 .qwb-tmp；smoke 新增第 87 节）。提交 c757665 cherry-pick 到 main 与测试隔离的 smoke 改动自动合并无冲突（main=011389b），bash 与 /bin/bash 语法检查通过。以合并后 main 全门作验收：SMOKE PASS、REVIEW-IDENTITY PASS、LINT PASS，主仓 lint 输出 262510 → 8661 字节，第 51 节原假阴性消失，smoke 末节为第 87 节；全门合计 840 PASS / 1 FAIL、rc=1，唯一 FAIL 是 COLLAB-ALL 里 tests/collab-handoff.sh 退出清理 rm 报 Directory not empty（其 10 条断言全 PASS；同 HEAD 单独连跑 4 次均 rc=0），属并发下清理竞态，与本票改动无关，另开 audit-collab-flake。未 push。
