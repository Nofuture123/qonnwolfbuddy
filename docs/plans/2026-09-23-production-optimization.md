# QW buddy 生产接入前优化

基线：`846fccea0c34c204e388e37886f49f71c1af5222`（`main`）。执行分支：`qwb-production-optimization`。分支创建时干净；本计划文件现为本票未跟踪内容。主仓原有未跟踪 `docs/plans/` 是他人 WIP，不纳入本票。目标是修复本仓当前源码的已证实接入风险，并取得最终候选 SHA 绑定的验证证据；不安装、升级或接管任何生产项目，不推送或合并。

## 已确认的问题与边界

1. `bin/qwb-init.sh:155` 等写入点对核心模板、运行脚本和钩子目标缺统一的链接/硬链接保护。隔离安装实跑：目标 `qwbuddy/QWBUDDY.md` 为指向项目外的符号链接时，安装返回 0，外部文件被改写。
2. `bin/qwb-run.sh:578-584,693-710` 用 Git 建 worktree，却只在项目 workspace 建 tab；新 worktree 没有以 worktree 形式登记到 Herdr Spaces。这违反全局 `~/.codex/AGENTS.md:10`。本机 Herdr 0.9.1 提供 `herdr worktree open --path ... --no-focus`，但具体返回/失败语义须以实际 CLI 验证。
3. `bin/qwb-worktree.sh:205-225,262-264` 接受远端跟踪分支证明提交已落地，然后 `branch -d` 可能失败。隔离 Git 实跑：`finish --merged` 返回 1、worktree 已删除、本地分支保留、任务书无 `worktree:` 行。
4. `bin/qwb-run.sh:484-491` 在锁命令任何非零退出后，仅凭 owner 文本等于当前 pane 就继续派发。锁命令的 I/O/flock 错误必须失败关闭；同一锁主重入必须在锁保护下确认。
5. `bin/qwb-test.sh:97-119` 的可选报告仅记录配置路径和变量名，未绑定本次实际执行的配置命令。报告用途仍是执行记录，不自动代表产品验收。
6. 历史真实 Herdr 闭环在简化改动之前；本分支最终需要自己的默认新 worktree/新窗口真实闭环。既有 full 门收据绑定较早候选；本分支最终须重新运行 full。

## 执行顺序与验收

### 1. 安装目标保护

范围：`bin/qwb-init.sh`；必要时 `tests/on-demand-guide.py`、`tests/worker-config.py`、`tests/smoke.sh` 和安装说明。第一次写入前清点并预检所有目标与父目录：`qwbuddy/`、`roles/`、`bin/`、`tasks/lessons/`、`.pi/extensions/`、`.claude/`，其下所有会写的模板/脚本/配置，以及 `.gitignore`、`AGENTS.md`、`CLAUDE.md`。清单还包括 Pi 扩展 `.bak`、Claude 设置临时文件、迁移模式的配置备份与临时文件。任何拒绝都应发生在第一次写入之前。

安装器覆盖的文件拒绝现有或断开的符号链接；“存在即保留”的配置/工人文件允许指向现存普通文件，但断链拒绝，迁移模式要修改它们时拒绝链接。追加式 `.gitignore`、`AGENTS.md`、`CLAUDE.md` 明确拒绝符号链接，包括项目内链接，以免悄悄替换链接或写穿到别处。替换既有普通文件（包括硬链接目标）时用同目录随机、独占创建的临时文件加原子替换，不改写外部 inode；固定名备份也须预检或改为安全的独占名字。保留已有配置/工人表、合法自定义内容和增量安装语义。隔离负例覆盖现存/断开的文件链接、目录链接、硬链接、旁路文件、迁移模式、普通升级与重复安装，确认外部哨兵字节不变。

### 2. 主控锁失败关闭

范围：`bin/qwb-lock.sh`、`bin/qwb-run.sh`、`tests/runtime-readiness.sh` 及必要 smoke 用例。让 `acquire` 在同一 owner 重入时于 `flock` 临界区明确成功；owner 文件缺失或格式坏不算重入。`qwb-run` 对任何非零结果直接停止。验证同主控重复派发仍可用、异主控拒绝、注入锁命令失败且 owner 文本等于当前 pane 时零 worktree/tab/dispatch 副作用。

### 3. Herdr Spaces 的 worktree 生命周期

范围：`bin/qwb-run.sh`、`bin/qwb-worktree.sh`、`bin/qwb-lib.sh`、`bin/qwb-wake.sh`、`templates/QWBUDDY.md`、`templates/host-watch-guide.md` 与相关测试。`qwb_ws_rows` 输出 `is_linked_worktree` 和 `checkout_path`；解析项目主 workspace 时排除任务 linked Space，不能因用户聚焦某任务 Space 就把后续主控/值守窗口送到那里。工人复用的期望 workspace 按实际目标目录的 `checkout_path` 认定；升级前仍在主 workspace 的历史工人明确拒绝并提示改名重派，不静默认领。

新建任务 worktree 完成 `QWB_WORKTREE_SETUP` 后、信任预置及任何账本写入前，按物理 `checkout_path` 查 Space；不存在才执行 `herdr worktree open --path "$DIR" --no-focus`（先不加 `--trust-repository`，真实临时仓库验证若证明必需再调整），再重新 list 并要求恰好一项，`is_linked_worktree=true`、`repo_root` 与项目根一致、`checkout_path` 与 `$DIR` 一致。打开失败或重复/歧义时拒绝投递和 `dispatch:` 记账，保留副本并给恢复指引。核实后立即把所有权写为任务账本第一条新增 `worktree-space:` 行；若刚打开的 Space 在记账时失败，先尝试关闭该 Space，再拒绝派发并给出未关闭 ID。`qwb_scenario_block` 须把 `worktree-space:` 当终止前缀，测试场景位于末节时指纹不变。新工人 tab 进入该 Space。`--here` 沿用项目主 Space；显式 `--worktree` 若不是本项目登记的 linked Git worktree，维持原有非登记路径语义并明确提示，不伪称展示为 worktree。动态 ID 只记独立账本行，不加到 `dispatch:` 行或配置；只在 QWB 新打开 Space 时记所有权。

`--pane` 的 cwd/身份/Space 检查保留在建树前：仅对已存在的 Space 核对归属；目标 worktree 尚无 Space 时提前拒绝，提示先 `herdr worktree open` 并在该 Space 准备 pane，或不用 `--pane` 正常派发。升级前仍在主 workspace 的历史工人按前述规则拒绝并提示换名，不在后续阶段才发现而留下无主 Space。

收尾仅在 Git 前置检查全部通过后核对 Space：`is_linked_worktree=true`、`repo_root` 和物理 `checkout_path` 均吻合，且任务账本的 QWB 所有权记录吻合。该 Space 的本票 tab 仅为 worktree open 产生的根 tab 和本票最后一条有效 `dispatch:` 所指 pane 所在 tab；有其他 tab、`working`/`blocked` agent 或无法确认是否仍有前台工作的 pane 时，在任何删除之前拒绝。用户先前自己打开、无 QWB 所有权行的 Space 也拒绝自动关闭及 Git 删除，并提示用户手工关闭后重试；没有 Space 的旧 worktree 可走原有 Git 收尾。`--keep` 不关闭。对可关闭的 Space 用 `herdr workspace close <id>`，绝不用会直接删 checkout 的 `herdr worktree remove`；关闭失败不动 Git。关闭成功后重新核对 HEAD，再按原有安全检查删除 checkout；此后失败须记部分收尾和恢复方式。Herdr 不在 PATH、查询未知时，`--merged`/`--archive` 在任何删除前拒绝。真实 CLI 验证创建、重复打开、失败和关闭后的 workspace 列表，确认主 Space 与其他 Space 未变；契约假件据本机 0.9.1 真输出制作。

### 4. worktree 收尾不可半成功无记录

范围：`bin/qwb-worktree.sh`、`tests/boundary-readiness.sh`/`tests/smoke.sh` 与收尾说明。对“已推送到远端跟踪分支、未并入本地 HEAD、无 upstream”的分支完成 `--merged`；删除本地 ref 前复核已落地的实际 HEAD/分支 OID，并确认没有其他 worktree 检出该分支。优先使用带旧 OID 条件的原子 ref 删除，保留现有 detached HEAD、脏树、写入者已停止等边界。Space 已关闭或 worktree 已删除而后续步骤失败时，任务书必须留下明确的部分收尾记录和恢复指引，不能无账本行。隔离 Git 用例重现旧红例并验证新结果；同时复跑 archive/keep/分支推进负例。

### 5. 质量门报告身份

范围：`bin/qwb-test.sh`、`tests/smoke.sh`、`templates/TASK.md` 或 `templates/QWBUDDY.md` 中确需同步的说明。可选报告记录本次已解析执行命令的摘要、配置文件运行前后字节摘要；不把可能含凭据的命令正文写入报告。同一 HEAD 下配置变更后，报告必须可区分。保持门 stdout/stderr、退出码和报告失败语义，明确摘要只证明命令身份，不证明产品场景。

### 6. 验证、审核与交付

- 每个修复以公开 CLI/安装行为的隔离负例验证；只保留能发现真实回归的测试。执行 `bash bin/qwb-test.sh fast --project "$PWD"` 和相关定向测试。Herdr 0.9.1 的 `worktree open` 成功、同路径重复打开、一次真实失败输出录成夹具，供假件契约测试使用。
- 实现完成后先在本分支提交计划与源码，得到干净的冻结候选 SHA；随后在该 SHA 上执行一次 `bash bin/qwb-test.sh full --project "$PWD"`，记录 SHA、命令、退出码、耗时和工作区状态。审核返修生成新 SHA 后，对最终 SHA 重跑 full 与受影响的真实步骤；交付证据只认最终 SHA。
- 用真实 Herdr 0.9.1 在隔离 Git 项目安装冻结候选，默认新建 worktree 派发一个无害任务，确认 Space、工人会话、账本、主控独立验收和收尾；收尾前后对比 workspace list，确认主 Space 与其他 Space 未变。只陈述隔离临时项目与实际所用工人类型的结论；Claude/Pi/长期值守/生产目标项目未跑则保持未验证。清理仅本次创建的临时对象，核对主仓 WIP 不变。
- 按本计划和基线对任务范围做可见 Herdr 正式代码审核，分 Standards/Spec，两轴每轮最多三个审点；修复成立项后复验。最终交付前保证审核收敛、最终 SHA 的 full 与受影响真实闭环通过。生产项目应用、推送、合并另行处理。
