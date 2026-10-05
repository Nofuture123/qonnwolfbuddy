# 任务书：运行态文件漏了忽略规则，真机上被主控误提交

```
任务 id:  runtime-ignore
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 真机验收（Pi 工人 + Claude Code 主控，候选 2183765）主控会话记录
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-runtime-ignore.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：装进项目的运行时不能给项目添乱。

### 真机上看到的事实（主控已核实）

1. 2026-10-05 真机验收里，Claude 主控收尾后 `git status --short` 出现两个未跟踪文件：`qwbuddy/.supervisor.guard` 和 `tasks/<票名>.md.qwb-lock`。主控执行 `git add tasks` 把票锁文件提交了进去，随后自己发现并用一个额外提交撤下。
2. 来源：`bin/qwb-ledger.sh` 在每张票旁边建 `<票文件>.qwb-lock`（约第 149 行）；`bin/qwb-wake.sh` 建 `qwbuddy/.supervisor.guard`（约第 455 行）。
3. `bin/qwb-init.sh` 写进项目 `.gitignore` 的规则（约第 316–326 行）没有这两项，也没有 `qwbuddy/.roles/`。
4. 已装项目里同样存在：`qonnwolf-sites` 与 `qonnwolfmcp` 的 `git status` 都显示未跟踪的 `qwbuddy/.supervisor.guard`。
5. 同一轮真机验收里，主控第一次派发被拒（「首次启动无明确实施授权/预算」），因为验收脚本预置的票没有 `implementation-authorized:` 与 `dispatch-budget:` 两行票头；主控自己补了票头才派出去。预置票缺票头不是这轮验收想考察的东西。

### 要做的事

1. **盘点。** 把运行时会在被装项目里生成、且不属于使用者内容的路径全部列出来（`bin/*.sh`、`templates/pi-extensions/*.ts`、安装器自身的临时文件），逐项标明：谁建的、是否已有忽略规则、该不该进 git。清单写进 `done:` 行指向的日志文件。
2. **补忽略规则。** 安装器的规则表补上盘点出的缺项，至少包括票锁（`tasks/` 下的 `.qwb-lock` 文件）与 `qwbuddy/.supervisor.guard`。`qwbuddy/.roles/` 是角色登记与会话目录：先读 `bin/qwb-role.sh` 与角色说明，确认它是本机运行态后再加；如果说明里要求它入库，写 `needs-decision:`，不要自行决定。已装过的项目重新安装时走现有的「旧段补缺项」逻辑补上，项目原有条目字节不变。
3. **回归测试。** 在已接入全门的测试里加一条：用临时项目把会生成这些文件的公开入口各跑一遍（账本写入、值守判定一轮、收尾等，全部用假 Herdr），之后 `git status --short` 里不得出现任何运行态路径。这条测试在起点提交上必须是红的，先跑出红并留证。
4. **真机验收脚本。** 预置票补上 `implementation-authorized:` 与 `dispatch-budget:` 票头，让标准路径不再必然先被拒一次；断言清单加一项：收尾后项目 `git status --short` 为空，且历史里没有任何 `.qwb-lock` 文件被提交过。只做离线可验证的部分（脚本语法、离线 CLI 测试），不运行真机流程。
5. 母本仓自己的 `.gitignore` 已整目录忽略 `qwbuddy/`，票锁规则按需补上。

白名单：`bin/qwb-init.sh`（仅忽略规则表）、`.gitignore`、`tests/e2e-real.py`、`tests/e2e-real.sh`、`tests/e2e-controllers-cli.py`、`tests/` 下为验收所需的已接入文件、`README.md` 与 `README.zh.md`（仅当其中列举了忽略规则时改那一句）。

## 1. 验收场景

### user_正常路径_新装项目跑完流程后工作区干净

Given 一个刚安装的临时 git 项目（安装产物已提交）
When  用假 Herdr 走一遍：写票、账本写入、值守判定一轮、派发登记、收尾
Then  `git status --short` 不含任何运行态路径；执行 `git add tasks` 后暂存区里没有 `.qwb-lock` 文件

### user_失败路径_起点提交上同一测试是红的

Given 起点提交的安装器
When  跑上面同一条测试
Then  失败，输出里点出未被忽略的运行态路径（保存这份红测日志）

### user_正常路径_旧项目重装后补齐规则

Given 一个用起点提交安装过的项目，`.gitignore` 里已有旧的运行态段，且使用者在段外加过自己的条目
When  用改后的安装器重装
Then  缺的规则被补进运行态段；使用者自己的条目与其余内容字节不变；再装一次 `.gitignore` 字节不变

### user_失败路径_使用者内容不被误忽略

Given 项目 `tasks/` 下有正常的票文件、`qwbuddy/` 下有 `config.sh`、`workers.sh`、角色说明等应入库的文件
When  应用新规则后跑 `git status --short` 与 `git check-ignore`
Then  这些文件都没有被忽略

### user_正常路径_真机验收脚本离线检查通过

Given 改后的真机验收脚本
When  跑 `python3 -B tests/e2e-controllers-cli.py` 与 `/bin/bash -n tests/e2e-real.sh`
Then  都通过；预置票文本带两行票头；断言清单含「工作区干净且历史无票锁文件」一项

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改运行时生成这些文件的位置与方式，只补忽略规则与测试。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 另两张票同时在别的副本里进行：`review-model-rule` 改 `bin/qwb-lint.sh`、`bin/qwb-ledger.sh` 的审核身份段、`templates/TASK.md` 与审核相关测试；`wake-tighten` 改 `bin/qwb-wake.sh` 的叫醒判定与相关测试。这些地方本票不要碰。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 五个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不清理已装项目里已经存在或已经被提交的运行态文件；不改三个已装项目。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T00:36:43Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-runtime-ignore pane=w14Z:pY dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore base=2183765
working: 2026-10-05T00:39:45Z 执行者完成规格与运行态盘点：.roles 是单机PID/pane/session代次登记，无入库要求；缺项含票锁、原票备份、supervisor guard、发布/安装临时文件。进入现有测试补反例阶段，证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence
working: 2026-10-05T00:43:52Z 已在未改安装器的2183765起点跑出有效红：python3 -B tests/worktree-space.py rc=1，公开dispatch→append→wake once→finish均成功，断言仅因qwbuddy/.supervisor.guard与tasks/2099-01-01-case.md.qwb-lock未忽略失败；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/baseline-red.log
working: 2026-10-05T00:49:16Z 忽略规则和6个白名单文件实现完成；基点红测1，当前公开流程/角色登记/旧装升级/内容保护/中文历史锁反例均通过，fast=0，e2e-real.sh Bash3.2语法=0；日志目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence。准备提交并在固定候选上跑full一次。
working: 2026-10-05T00:49:54Z 候选已提交=ae1388ef651c83013858ff501fce3aec1ff6ee3b；提交后唯一一轮bash bin/qwb-test.sh full执行中，pid=91733，原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/full.log，退出回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/full.rc；不运行真机、不连接真Herdr。
working: 2026-10-05T00:56:51Z 首候选ae1388e full=1（SMOKE/LINT/审核身份通过，COLLAB-ALL 2/15失败）；根因是本票共用STUB新增QWB_TEST_NATIVE_PID与collab-herdr既有变量碰撞。已改为QWB_TEST_IGNORE_NATIVE_*；原F2公开复用/失败复用/unknown-start三场景原断言复验rc=0，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/repaired-shared-stub.log；保留首轮full.log，准备追加修正提交后再跑最终候选full。
working: 2026-10-05T01:02:49Z 最终候选=65a147c8b69c939b3223da42ecf2370a26e38514，专属fixture变量返修已提交；同一最终场景在完整2183765运行副本仍正确红（final-baseline-red.log）。最终候选提交后的full正在执行，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/full-final.log，回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/full-final.rc；首轮失败保留，未追加其他产品范围。
done: 2026-10-05T01:04:59Z 最终提交=65a147c8b69c939b3223da42ecf2370a26e38514；盘点与五场景逐项命令/结论报告=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/report.md。完整基点安装+同一最终场景红rc=1（final-baseline-red.log）；新装公开流程、旧装补缺且原字节保留/重复幂等、用户内容保护、角色登记、真机脚本离线全部通过。
done: 2026-10-05T01:04:59Z bash bin/qwb-test.sh fast=0；python3 -B tests/e2e-controllers-cli.py=0；/bin/bash -n tests/e2e-real.sh=0；最终候选提交后bash bin/qwb-test.sh full=0，grep -c ^PASS=854，grep -c ^FAIL=0，COLLAB-ALL 15项通过；全门原始输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/full-final.log。首轮full=1的共享fixture变量碰撞已修复，失败日志保留。
done: 2026-10-05T01:04:59Z 全门后git status --short输出为空；残留测试进程=[]；.qwb-tmp只保留证据目录。收据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/final-receipt.json，状态/进程原始证据同目录post-full-status.txt与post-full-processes.json。只改6个白名单文件；未碰已装项目、未连接真Herdr、未启动模型。
working: 2026-10-05T01:06:28Z 主控验收返修（第1轮，候选 65a147c 之上追加一个提交）：盘点与规则表认可。一处要改：tests/e2e-real.py 给主控的提示里新加的「确认 git status --short 为空且 Git 历史没有 .qwb-lock 文件」要删掉——这等于把考题答案告诉被考的主控，以后忽略规则回归了也会被主控手工绕过去而测不出来。提示里可以保留「收尾后提交应入库的任务书等产物」这类正常工作要求，但不得出现 .qwb-lock、运行态文件、git status 须为空这类指向断言的字样；断言 git_runtime_clean 本身保留。同步改离线 CLI 测试里对提示文本的断言，并加一条：提示文本不含 qwb-lock 字样。只需跑快门、python3 -B tests/e2e-controllers-cli.py 与 /bin/bash -n tests/e2e-real.sh，不必再跑全门（主控合并后统一跑）。done 行报新 sha。
working: 2026-10-05T01:07:18Z 执行者已读取主控第1轮返修：仅删tests/e2e-real.py提示中暴露git_runtime_clean断言的句子，保留正常提交任务书要求与断言；离线CLI已新增实际拼出提示不含qwb-lock/运行态/git status的核对。按最新裁决仅跑fast、CLI和e2e-real.sh语法，完成后追加一提交。
done: 2026-10-05T01:08:09Z 主控第1轮返修完成；新提交=234134186ee7129f05076e637a7a191cbbb9a8dc（在65a147c之上仅追加一提交、只改tests/e2e-real.py与tests/e2e-controllers-cli.py）。已删提示中透露断言的句子，保留正常提交任务书要求及git_runtime_clean；离线测试核实际提示不含qwb-lock/运行态/git status。fast=0，python3 -B tests/e2e-controllers-cli.py=0（PASS=4 FAIL=0），/bin/bash -n tests/e2e-real.sh=0。按最新裁决未再跑full；git status为空。日志与收据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/runtime-ignore/.qwb-tmp/runtime-ignore-evidence/rework-r1-receipt.json。
working: 2026-10-05T01:20:25Z 主控验收：独立核对改动与探针，返修项已补；提交已 cherry-pick 进 main，合并后 main @ 4bdd2fd 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、429 秒（.qwb-tmp/ctl-full-merge.log）；真机验收第 10 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS。详见 docs/reviews/2026-10-03-qwb-full-audit-r1.md「工具与角色调整」。
