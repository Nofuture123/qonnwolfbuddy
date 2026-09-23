# 生产接入前优化 正式独立审核 r1

结论：**Standards AMEND；Spec AMEND**。审核者为 Claude Code（Opus 5.5，Herdr pane `wF2:p3`），只读审核，未改候选源码、未提交、未派发。

## 冻结对象与证据

- 需求：`docs/plans/2026-09-23-production-optimization.md`。基线 `846fccea0c34c204e388e37886f49f71c1af5222`；候选 `f4d7c8a9d671d57064c40f038b3fb1b4fc0d6430`（分支 `qwb-production-optimization`，worktree `/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-production-optimization`，Space `wGR`），审核开始与结束时工作区均干净。本仓无 `AGENTS.md`（worktree、主 checkout、git 历史均无），标准依据取计划与 `docs/DESIGN.md`、`docs/DECISIONS.md`。
- full 收据 `/tmp/qwb-full-f4d7c8a.md` 与 `/tmp/qwb-full-f4d7c8a.log` 已核对：前后提交均为 f4d7c8a、工作区 clean、门退出码 0；命令 SHA-256 `2b905f93…` 与配置 SHA-256 `06bf3005…` 经重算吻合；日志 SMOKE / REVIEW-IDENTITY / LINT 均 PASS，639 PASS / 0 FAIL。该收据不覆盖下文审点②的路径。
- 真实 Herdr 实验全部在新建 named session `qwbrev-iso` 中完成：`herdr --session qwbrev-iso server` 后台运行，每条命令经包装脚本强制 `HERDR_SOCKET_PATH=~/.config/herdr/sessions/qwbrev-iso/herdr.sock`、清空 `HERDR_PANE_ID/TAB_ID/WORKSPACE_ID`，并先用 `herdr status server` 确认 socket；结束后 `herdr session stop` 与 `delete` 均 rc=0。default 会话前后都是 20 个 workspace，无增删、无路径变化。

## 审点

### 1. MEDIUM（Standards + Spec）打开 Space 后未绑定所有权；Space 存在性以 repo_root==项目根判断，收尾可能在活 Space 下删 checkout

- 位置：`bin/qwb-run.sh:617-632`：`herdr worktree open` 成功后，解析失败（625-626）、重新 list 失败（630）、身份不符（631-632）均直接退出，不关闭 `opened_id`、不记账、不报 ID；只有记账写失败（635-640）会关闭。`bin/qwb-lib.sh:127-130` 只认 `repo_root == 项目根物理路径` 的 Space。`bin/qwb-worktree.sh:224-225` 查不到 Space 即 `return 0`，随后走 Git 删除（321、356）。
- 触发：(a) 仓库根安装，`worktree open` 成功与所有权写入之间任一步失败；(b) 项目根不是 Git 主工作树根（子目录安装，或项目根本身是 linked worktree）时必然触发——真实 Herdr 的 `repo_root` 恒为主工作树根（live list 中 `wGR` 的 repo_root 即主仓路径）。
- 已证实（真实 Herdr 0.9.1，隔离会话）：
  - 仓库根安装，包装一个 `herdr` shim，使 `worktree open` 成功后第一次 `workspace list` 失败：派发 rc=1，stderr 只有「herdr workspace list 失败…」；遗留 w8（主仓）与 w9（任务 Space）；任务书 `cmp` 不变；随后 `finish case --merged` rc=1，「worktree Space w9 没有本票所有权记录；请手工关闭后重试」。
  - QWB 装在 `mono/app`（Git 根为 `mono`）：派发两次均 rc=1，「worktree Space 登记后路径/身份无法唯一核对」，遗留 w6（主仓）与 w7（任务 Space）；随后 `finish case --merged` rc=0，checkout 与分支被删（`show-ref` rc=128），账本写 `worktree: merged`，而 QWB 开的 w7 仍在，pane `w7:p1` 的 cwd 指向已删目录。
- 代码确认、未实跑：仓库根安装下重试派发会以 `qwb_worktree_space` 查到的该 Space 为目标，但不写所有权，之后每次收尾拒绝，只能人工关闭。
- 后果：无主 Space（无 ID、无恢复指引）；(b) 形态下收尾失败开放，在 QWB 自己开的 Space 下删 checkout，违背计划「查询未知时……在任何删除前拒绝」的意图。生产目标为仓库根安装时只遇到 (a)；若子目录安装算受支持形态，本项应升 HIGH。
- 最小修复方向：`already_open=false` 之后任何失败先 `herdr workspace close "$opened_id"`，关不掉就打印 ID 与手工命令；派发与收尾以「linked 且 checkout_path == 目标目录」判断 Space 存在，repo_root 不符或无所有权时拒绝，不得当作「无 Space」；非主工作树根的项目在创建 worktree/打开 Space 之前明确拒绝（或改用 `git rev-parse --git-common-dir` 推出的主工作树根比对）。

### 2. MEDIUM（Standards）带 Space 且已派发工人的收尾成功路径没有回归保护

- 位置：`bin/qwb-worktree.sh:237-251`（按最后一条 `dispatch:` 的 pane 认工人 tab）、`259-262`（放行根 tab 与工人 tab）；`tests/worktree-space.py:167-192` 的收尾用例任务书无 `dispatch:` 行（174-175）且只测失败模式；smoke 的 `qwb_finish` 与 `tests/boundary-readiness.sh` 的收尾都不带 Space。
- 已证实（变异测试，隔离副本）：把第 250 行改为 `worker_tab="${pane_meta%%$'\t'*}"`（取 workspace ID 而非 tab ID；bash -n 与 shellcheck 均 0）后，`bash bin/qwb-test.sh full` rc=0（SMOKE/REVIEW-IDENTITY/LINT PASS，639/0），`fast` rc=0。该变异下，真实闭环记录中工人 tab 为 `wH5:t2` 的收尾会被判「Space 中有非本票 tab」而拒绝。
- 对照：删除 `TAB_WS="$TASK_SPACE"` 的变异被 `tests/worker-config.py:289` 拦下（派发入 Space 有保护）；「只放行根 tab」的变异只被 shellcheck SC2034（未用变量）拦下，非行为断言。
- 最小修复方向：新增收尾成功用例——账本含 `worktree-space:` 与 `dispatch: … pane=<工人pane> dir=<wt>`；假件 `tab list` 返回根 tab 与工人 tab，`pane get` 返回本 Space 与工人 tab，`pane list` 中根 pane 为 unknown+空闲 shell、工人为 idle；断言 rc=0、`workspace close <Space>` 恰一次且早于 `git worktree remove`、worktree 与分支已删、账本有 `worktree: merged`。补负例：派发 pane 属于别的 workspace 时拒绝、不关闭、不删除。

### 3. LOW（Spec 计划第 4 条）`--archive` 部分失败后工具无法续做，partial 行无可执行恢复指引

- 位置：`bin/qwb-worktree.sh:337-344`（本次新增的「归档标签已存在即拒绝」）、`354-356`（先打标签再删 worktree）、`211-218`（partial 提示为通用文字）。
- 已证实（隔离 Git，git shim 让第一次 `worktree remove` 失败）：首次 `--archive` rc=1，写 `worktree: partial action=archive branch=arch tag=archive/arch stage=worktree-remove space=-`，标签已在；重跑 `--archive` rc=1「归档标签 archive/arch 已存在」；改用 `--merged` rc=1（未落地）。代码推断：`stage=branch-delete` 时 worktree 已删，重跑报「worktree 不存在」，同样续不了。
- 后果：Space 可能已关，副本仍在且不在 Spaces 中显示，收尾只能手工改 Git，计划要求的「恢复指引」不可执行。
- 最小修复方向：标签已存在且指向当前实际 HEAD OID 时跳过打标签、继续后续步骤（指向别处仍拒绝）；partial 记录带 `oid=`，输出含带 OID 条件的具体恢复命令；`branch-delete` 阶段至少给出可直接执行的命令。

## 已排除的怀疑

- 任务 Space 根 pane `cd` 到主仓或 `/` 后，Space 的 `is_linked_worktree`、`checkout_path`、`repo_root` 不变，只有未显式设定的 label 跟随 cwd。
- Herdr 文档说明 tab/pane ID 关闭后不复用，根 tab 可作所有权锚点。
- 安装器首次写入前的预检覆盖全部写入目标（链接、断链、目录链接、硬链接均在首写前拒绝或同目录原子替换），未发现越界写路径；检查与写入之间的 TOCTOU 未测。
- 主控锁任何非零结果都拒绝派发；同 owner 重入在 flock 内确认。

## 仍未验证的生产边界

- 生产目标已由使用者改为 `qonnwolf-sites`（2026-09-24），安装由使用者自行处理，不在本返修范围。
- 真实闭环只跑过 pi（herdr 模式）；Claude、Codex、pane-run 工人在 Space 中的状态判定与收尾未验证。
- Herdr 重启/会话恢复后根 tab 与工人 pane 是否仍可查询未验证；收尾要求两者存在，否则拒绝（代码推断）。
- 主仓 workspace 未打开时，`worktree open --cwd` 会额外新建主仓 workspace（隔离会话 4 次复现：w1、w4、w6、w8），QWB 不记录不清理；`--workspace` 与 `--cwd` 互斥，且只接受位于 Git 工作树内的 workspace。
- 长期值守与 Space 并存、两个主控对同票并发 `worktree open` 的所有权竞争未测。

## 返修任务（执行者：Codex，gpt-6-sol / high）

- 工作目录：`/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-production-optimization`，分支 `qwb-production-optimization`，起点 `f4d7c8a9d671d57064c40f038b3fb1b4fc0d6430`。不开新分支，不 push，不合并。本报告文件随第一笔返修提交一并提交。
- 范围：只修上文审点 1、2、3。不做：`update-ref -d` 残留 `branch.<名>.*` 配置、安装器新建文件为 0600、worktree 派发时误导性的「工人 tab 开在调用者 workspace」警告、任何安装相关改动；不碰 `qonnwolfai-student`、`qonnwolf-sites` 及其他项目。
- 做法：先读计划、本报告和相关源码/测试，再动手；最小实现，不顺手重构或改格式，注释与报错沿用现有中文风格。每项修复配公开 CLI 层回归测试，并做反转验证：新测试在 f4d7c8a 源码上变红、修复后变绿；审点 2 的新测试还须拦下上文变异（`worker_tab` 取 workspace ID）。反转与变异只在临时副本里做，不提交。
- smoke 新节必须加在 `tests/smoke.sh` 末尾「新节必须加在本行之前」之前；汇报时核对 smoke 输出的最后一个节标题确实是你的新节之后的内容。
- 真实 Herdr 只能在自建 named session 中试（`herdr --session <名> server`，每条命令前用 `herdr status server` 确认 socket 指向该会话），结束后 `herdr session stop` 与 `herdr session delete`；不得在 default 会话中创建、关闭或改动任何 workspace/tab/pane。
- 验收：提交后工作区干净，在最终 SHA 上运行 `bash bin/qwb-test.sh fast --project "$PWD"` 与 `bash bin/qwb-test.sh full --project "$PWD" --report /tmp/qwb-full-<SHA前7位>.md`（原始输出存 `/tmp/qwb-full-<SHA前7位>.log`，报告文件须事先不存在），记录命令、原始退出码、耗时、前后工作区状态。
- 报告：写 `docs/reviews/2026-09-24-qwb-production-optimization-r1-execution.md`（逐项：改了哪里、测试名、红/绿证据、隔离 Herdr 实验命令与 rc、未验证项），与返修一起提交；full 在含该报告的最终提交上跑。最后在对话中单独输出一行 `QWB_PROD_OPT_R1_FIX DONE <完整SHA>`，或 `QWB_PROD_OPT_R1_FIX BLOCKED <原因>`。

**REVIEW_QWB_PRODUCTION_OPTIMIZATION_R1 AMEND**
