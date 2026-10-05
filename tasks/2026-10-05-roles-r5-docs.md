# 任务书：第五轮演练暴露的说明书矛盾与缺口

```
任务 id:  roles-r5-docs
state: running
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第五轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r5.md 的 V4、V5）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-roles-r5-docs.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-r5-docs（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：主控照着说明书和脚本提示就能走通，不靠猜、不做白工。

第五轮演练（Claude Code 当副主控）里，主控有几处是被彼此矛盾或没写清的说明书绊住的。演练记录先读 `docs/reviews/2026-10-05-real-herdr-roles-drill-r5.md`；演练主控的原始笔记在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r5/notes.md`（只读）。**本票只改说明书与配置注释，不改任何脚本行为。** 下面标「主控已核对」的是主控对着文件看过的；标「演练记录」的是演练主控的说法，写进说明书之前逐条对照代码或公开入口的实际输出核实，不符就写 `needs-decision:`。

### 要做的事

1. **值守说明里关于 Claude 活动判定的过时说法（主控已核对文字，适用范围待你核实）。** `templates/host-watch-guide.md` 第 28 行写「Claude及其他CLI的idle未核验，报告unknown并拒绝据此复用/收尾」。现在 `bin/qwb-herdr.sh` 的 `activity` 已有 Claude 分支（约第 207 行起：按会话号找会话文件、未配对的工具调用算忙、回合结束接受 `idle` 与 `done`），Claude Code 也可以当规划常驻职责。先读代码确认这个分支对哪些窗口生效（常驻职责、`qwb-run.sh` 派出的 Claude 工人各自是什么结果）、哪些情形仍然报 `unknown`，再把这句话改成与代码一致的说法；Claude 以外的其他 CLI 仍未核验这一点保留。
2. **主控窗口号该不该写进配置，两处说法相反（主控已核对）。** `templates/config.sh` 第 17 行注释写「主控 pane id；开局点名时填入」；`templates/host-watch-guide.md` 第 7 行写「当前主控 pane 从 `HERDR_PANE_ID` 取得，不把动态 pane ID 写入 `qwbuddy/config.sh`」。代码里 `bin/qwb-wake.sh` 只把它当 `--pane` 的缺省值（第 58、104 行）。核实各入口实际从哪里取主控窗口后，把 `config.sh` 这一行的注释改成与值守说明一致的说法（只改注释，不改键名与默认值）；`templates/QWBUDDY.md` 的开局步骤如有同样的矛盾一并改。
3. **说明书没写清的几处（演练记录，逐条核实后写进 `templates/roles/常驻流程.md` 或对应角色说明的相关步骤，每条一两句）：**
   - `qwb-send.sh send` 输出的事件号带 `send:` 前缀，后续命令原样使用，不要去掉前缀。
   - 副主控新开的票在派工前状态是 `blocked`，派工后才变 `running`，这是预期现象。
   - 落地前怎样确认工人进程已经退出（`qwb-worktree.sh land` 现在会在写入者未退出时拒绝并给出关闭窗口的命令；说明书写明落地前要做的确认动作与这条拒绝信息的关系）。
   - 怎样在不读脚本源码的前提下查看某个工人名对应的启动参数（先找有没有公开入口；没有就写明 `qwbuddy/workers.sh` 是配置文件、可以直接读对应那一行）。
   - Claude Code 当副主控时特有的三点：项目目录没被信任时 `qwb-role.sh start` 会拒绝并给出恢复命令；握手最长等 120 秒；副主控窗口不在前台时 Herdr 报 `done`，与 `idle` 同样算回合结束。事实依据见 `docs/reviews/2026-10-05-claude-code-herdr-probe.md`，逐条对照 `bin/qwb-role.sh` 与 `bin/qwb-herdr.sh` 的现行代码后再写。
4. 改动涉及从说明书原样取块执行的部分时，`tests/roles-walkthrough.sh` 必须照旧通过；本票预期不需要改测试，如需改动先写 `needs-decision:`。

白名单：`templates/host-watch-guide.md`、`templates/config.sh`（仅 `QWB_CONTROLLER_PANE` 一行的注释）、`templates/QWBUDDY.md`、`templates/roles/常驻流程.md`、`templates/roles/主控.md`、`templates/roles/规划.md`（各仅相关句子）。安装器会把模板复制进项目，测试里若有对这些文件逐字比对或行数、字数上限的断言，同步所需的最小改动自动算在白名单内，并在 `done:` 行写明。

## 1. 验收场景

1. 值守说明里关于 Claude 活动判定的说法与 `bin/qwb-herdr.sh` 现行代码一致：`done:` 行写明你核对到的各情形结果与代码位置。
2. `QWB_CONTROLLER_PANE` 在 `config.sh` 注释、值守说明、总说明三处说法一致，且与各入口的实际取值顺序相符。
3. 第 3 项的每一条都能在说明书里找到对应句子；每条在 `done:` 行写明核实方式（代码位置或公开入口的实际输出）。核实后发现演练记录不成立的条目不写进说明书，在 `done:` 行说明。
4. `bash tests/roles-walkthrough.sh` 通过，PASS 行数不少于改动前。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时有另一张票 `worker-silent-end` 在改 `bin/qwb-wake.sh`、`bin/qwb-run.sh`、`bin/qwb-lib.sh`、`templates/config.sh`（新增一行 `QWB_SILENT_END_MS`）、`templates/roles/审核者.md` 与 `templates/roles/门禁.md`；本票不碰这些脚本与那两份角色说明，`templates/config.sh` 只改 `QWB_CONTROLLER_PANE` 那一行的注释。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 定向：`bash tests/roles-walkthrough.sh`；另在 `tests/` 下搜被你改动的模板文件名，凡是读取这些模板做断言的测试文件各单独跑一次，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（全门由主控合并后串行跑）。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
