# 任务书：诊断 collab-land.sh 为什么一直是红的（只诊断，修测试侧，不改产品）

```
任务 id:  audit-collab-land-red
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F34）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，magpie codex/gpt-6.1-sol high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-collab-land-red.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-land-red（隔离副本，detached HEAD，起点 main 0b9faef）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

`tests/collab-land.sh` 是本地落地与收尾恢复（`qwb-worktree.sh land` / finish 续做）唯一的测试，但它从没被任何门调用过，而且是确定性的红。主控与三个执行者在 `4678ba0`、`cf4a9c0`、`8067347`、`011389b` 上各自跑过，结果完全相同：前 7 条 PASS 之后，在 recover-endpoint 一段

    RC=1 qwb-worktree.sh land recover-endpoint --op land-recover-endpoint --auth-ref auth-endpoint-resumed
    AssertionError: (1, '', '拒绝：Herdr Space task-space 关闭/焦点读回未确认，Git 未动：Herdr refusal/unknown: query/action failed: ')

因为它是红的，第 1 波把协作测试接进全门时没有接它（`tests/collab-all.sh` 的默认清单里没有它）。落地路径因此在全门里零覆盖，`bin/qwb-worktree.sh` 的后续简化也被它挡着。

### 工程规格

1. **二分**：用 `git archive <提交> | tar -x -C <自己的临时目录>` 导出历史版本（不许 checkout、不许 worktree），找出 `tests/collab-land.sh` 最后一次通过的提交与第一次失败的提交。先确认它在被加入仓库的那个提交上是否通过；注意本机 Herdr 现在是 0.9.3，历史上记录过 0.9.1——如果它在所有历史提交上都失败，如实报，并转向环境因素（见第 3 条）。
2. **定位根因**：在第一次失败的提交上，说清是哪一次 herdr 调用（经假 herdr）返回了什么、`bin/qwb-herdr.sh close` 或 `bin/qwb-worktree.sh` 的哪一行据此拒绝、测试的假件缺了哪种应答或哪个字段。给出最小复现命令。
3. **判断归属**，三选一并给证据：
   - 测试的假 herdr 落后于产品（产品后来多查了一步，假件没跟上）→ 属测试侧，按第 4 条修。
   - 产品缺陷（真实 Herdr 下同样会拒绝一个本应成功的落地恢复）→ **不改 `bin/`**，写 `needs-decision:` 报给主控，附证据与建议修法。
   - 环境相关（Herdr 版本、`bin/qwb-herdr.sh` 里 2 秒硬超时在本机偶发超时、Python 版本等）→ 报出在什么条件下通过、什么条件下失败。
4. **若属测试侧**：只补假件缺的应答，使这条断言在不改断言内容的前提下通过；然后把 `tests/collab-land.sh` 加进 `tests/collab-all.sh` 的默认清单，并更新清单上方那段说明它未接入的注释。之后的断言如果又暴露别的问题，同样先判断归属再处理。
5. 不许为了让它变绿而放宽、删除或改写任何断言。

白名单：`tests/collab-land.sh`、`tests/collab-all.sh`；确有必要时可动 `tests/` 下它直接依赖的夹具，并写明理由。**不改 `bin/` 与 `templates/`。**

## 1. 验收场景

### user_正常路径_根因有可复现的证据

Given 二分得到的最后通过与首次失败两个提交
When  按你给的最小复现命令分别在两个导出副本上执行
Then  前者通过、后者在同一断言失败；`done:` 或 `needs-decision:` 行里写明两个提交的 sha、失败的那次 herdr 调用及其应答、产品里据此拒绝的文件与行号

### user_正常路径_若属测试侧则修后稳定通过并进门

Given 判定为测试侧并已修
When  连续跑 5 次 `bash tests/collab-land.sh`，再连续跑 3 次 `bash tests/collab-all.sh`
Then  全部退出码 0；collab-all 输出 12 个 PASS、末行 COLLAB-ALL PASS（12 项）；没有以 rm: 开头的行、没有残留目录与残留进程

### user_失败路径_若属产品缺陷则不动产品

Given 判定为产品缺陷或环境相关
When  收工
Then  `bin/` 与 `templates/` 相对起点零改动；`tests/collab-all.sh` 默认清单不变；主账本有一条 `needs-decision:` 写明证据、影响（真实落地恢复在什么情况下会被错误拒绝）与建议修法

### user_失败路径_断言不被放宽

Given 你对 `tests/collab-land.sh` 的全部改动
When  用 diff 对照起点
Then  没有任何断言被删除、放宽或改写期望值；改动只出现在假件与夹具搭建部分

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离（死路径 `HERDR_SOCKET_PATH`）与进程登记夹具。
- 临时文件只许删除自己建出并记在变量里的确切路径；禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 的进程。
- git：只读命令（`git log`、`git show`、`git archive`）随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`checkout` 历史提交、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、`bisect`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 四个场景中适用的逐个验证，命令与原始结果写进状态行。
- 若改了代码：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点全门是 831 PASS / 0 FAIL。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha（没有代码改动就写 DONE no-change），或 STOP 加原因。

## 6. 本票不允许做的事

- 不改 `bin/`、`templates/`、文档；不改任何断言。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T04:24:07Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（默认 magpie codex/gpt-6.1-sol high） agent=qwb-audit-collab-land-red pane=w14Z:pA dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-land-red base=0b9faef
working: 2026-10-04T04:25:02Z 执行者完成规格与F34来源完整读取；base=0b9faefac693273c3bf10e949259b78a76a17eb6，git status --short为空；开始原始红测与首次加入提交283cfb3af66394da20df23d7d324288f830db9cf的archive历史验证，证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-land-red/.qwb-tmp/land-red-evidence.TG5T7VJc。
working: 2026-10-04T04:27:32Z 原始红测已在base复现：7 PASS后recover-endpoint新授权仍RC=1，AssertionError含query/action failed空消息；首次监督shell未留下退出回执，已以set +e重跑取自然退出码。历史按Git祖先拓扑定位集成边界，导出fb27ad93255a5a869965b4a655902a4cc3c643a4与c4403be6f3da842ce50842074555a2a230e6aedb对照，不使用checkout/worktree/bisect。
working: 2026-10-04T04:29:48Z 阶段1/2完成：首次加入283cfb3af66394da20df23d7d324288f830db9cf RC=0/9 PASS；最后通过fb27ad93255a5a869965b4a655902a4cc3c643a4 RC=0/9 PASS；首次失败c4403be6f3da842ce50842074555a2a230e6aedb（前者是其第二父提交）RC=1/7 PASS，同recover-endpoint断言；base复跑自然RC=1/7 PASS。最小历史复现：d=$(mktemp -d); git archive SHA | tar -x -C "$d"; HERDR_SOCKET_PATH=/dev/null/qwb-test.sock TMPDIR="$d" GIT_CEILING_DIRECTORIES="$d" bash "$d/tests/collab-land.sh"。首次失败herdr api snapshot经原假件返回9且stdout/stderr均空（missing-responses.json）；c4403be:bin/qwb-herdr.sh:21拒绝，:157调用快照；bin/qwb-worktree.sh:538-539据此拒绝收尾。新增close helper在集成时进入，假件未同步，归属测试侧；还缺status --json、AF_UNIX workspace.move应答及task-pane process_info的pane_id/前台shell行。复用tests/collab-herdr.sh现有协议夹具形状补齐，不改产品与断言。证据=.qwb-tmp/land-red-evidence.TG5T7VJc。
working: 2026-10-04T04:34:27Z 阶段3修复完成：只修改tests/collab-land.sh假件搭建（api snapshot、status、私有AF_UNIX RPC、task-pane前台shell字段）及tests/collab-all.sh默认清单/说明；fixed-first RC=0/9 PASS，bash bin/qwb-test.sh fast RC=0；git diff --check与shell语法通过；49条原assert AST完全一致，bin/templates相对0b9faef零改动。连续稳定性验收仍在执行，非done。
working: 2026-10-04T04:41:07Z 阶段3定向稳定性完成：连续bash tests/collab-land.sh五次均RC=0（land-1..5.log/rc），49条assert的AST逐条与base相同；快门bash bin/qwb-test.sh fast RC=0；继续默认12项collab-all三连跑。
working: 2026-10-04T04:46:15Z 阶段4首次跑批失败已完整收据：all-1 RC=1，11 PASS/1 FAIL，唯一失败collab-herdr.sh的events.sock绑定AF_UNIX path too long，land子项通过；39个已观察测试进程组均无存活成员，测试临时目录清零。隔离工作目录68字节，共用process_fixture.py的4位hex scope令events.sock=105字节；同机器私有socket单变量探针105字节绑定失败、103字节成功（socket-length-probe.json）。本票明确允许必要时修改直接依赖夹具；因此将只把land直接依赖的process_fixture.py scope名称缩短2字节，保留仓内目录、原子mkdir碰撞重试、全部进程登记/清理及死Herdr路径。原始land失败仍属缺假件应答，新增问题属测试夹具路径长度；不改其他测试或断言。最终夹具变更后重新完整5+3连跑，不采信此前版本结果作为最终验收。
working: 2026-10-04T04:57:46Z 最终夹具阶段定向稳定性完成：连续bash tests/collab-land.sh五次RC=0（最终land-1..5.log/rc）；process_fixture.py仅缩短scope名、保持隔离/登记/清理；继续默认12项collab-all三连跑。
working: 2026-10-04T05:10:46Z 阶段4最终验收完成：bash tests/collab-land.sh连续5次均RC=0/9 PASS；bash tests/collab-all.sh连续3次均RC=0/12 PASS，三次末行均COLLAB-ALL PASS（12 项），全部日志无rm:开头行；126个观察进程组无活成员，记录的PID/start实例无活进程，仓内测试scope/跑批临时目录清零；49条原assert AST完全不变，bin/templates零改动；快门fast-final RC=0。必要新增白名单直接依赖夹具仅tests/process_fixture.py（scope名2字符缩短，原子创建/进程登记/死路径不变，理由见上行），其余仅两张测试文件。原始失败attempt-1保留，最终证据final-repeat-verification.json。现在提交后执行full。
working: 2026-10-04T05:11:24Z 阶段5已提交：a76c58d22f65bcafe4bc81e9a1fe5b3f22189f6f（detached HEAD，3个授权测试侧文件）；提交后bash bin/qwb-test.sh full已启动，PID=61018，原始日志=.qwb-tmp/land-red-evidence.TG5T7VJc/full.log，退出回执full.rc尚待取得；此前5+3与快门均通过，非done。
done: 2026-10-04T05:23:49Z 最终提交=a76c58d22f65bcafe4bc81e9a1fe5b3f22189f6f（detached HEAD，不建分支/不push）；首次加入283cfb3af66394da20df23d7d324288f830db9cf通过，最后通过fb27ad93255a5a869965b4a655902a4cc3c643a4 RC=0/9 PASS，首次失败c4403be6f3da842ce50842074555a2a230e6aedb RC=1/7 PASS；首次失败herdr api snapshot经原假件返回RC=9、stdout=""、stderr=""，c4403be的bin/qwb-herdr.sh:157调用、:21拒绝，bin/qwb-worktree.sh:538-539据此拒绝。归属测试侧：集成新close协议未同步假件；补snapshot/status/私有RPC与shell字段，不改断言。必要直接依赖夹具process_fixture.py只缩短scope名2字节（105字节socket失败、103字节成功），保留仓内归属/原子碰撞重试/进程登记/死路径隔离。最终bash tests/collab-land.sh连续5次RC=0/各9 PASS，bash tests/collab-all.sh连续3次RC=0/各12 PASS且末行均COLLAB-ALL PASS（12 项），无rm:行；fast-final RC=0；提交后bash bin/qwb-test.sh full RC=0，PASS行数=831，FAIL行数=0，末尾5行各前100字符=["PASS  tests/collab-roles.sh（69s）", "PASS  tests/collab-test-policy.sh（100s）", "PASS  tests/lint-scenario-stream.sh（2s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（12 项）"]；全门后git status --short输出=""；49条原assert AST一致，bin/templates相对base零改动；测试临时目录及PID/start实例清零；原始失败日志保留attempt-1，历史导出副本已回收，完整证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-land-red/.qwb-tmp/land-red-evidence.TG5T7VJc/final-quality-receipt.json，全门日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-collab-land-red/.qwb-tmp/land-red-evidence.TG5T7VJc/full.log。
working: 2026-10-04T05:44:04Z 主控验收：根因成立（合并提交 c4403be 引入新的关闭 Space 协议后，测试假件未跟上 herdr api snapshot 等应答，产品据此正确拒绝；属测试侧）；diff 已审，改动只在假件与夹具搭建，断言未动；把 a76c58d 导出到仓库内短路径 .qwb-tmp/v2 独立验证：bash tests/collab-land.sh 连跑 2 次均 rc=0、各 9 PASS；bash bin/qwb-test.sh full：rc=0、831 PASS / 0 FAIL、COLLAB-ALL PASS（12 项，含 collab-land 188s）、无残留进程，717.09s。已 cherry-pick 到 main（HEAD=a7722dc），未 push。
