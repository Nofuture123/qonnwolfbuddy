# QWB 生产优化 r1 返修执行记录

执行目录：`/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-production-optimization`；起点 `f4d7c8a9d671d57064c40f038b3fb1b4fc0d6430`。只改审点 1、2、3，未 push、合并或切分支。`docs/reviews/2026-09-24-qwb-production-optimization-r1.md` 原文随返修提交。

## 审点 1：Space 所有权与项目根身份

- `bin/qwb-run.sh` 在默认建树前和显式 linked worktree 打开 Space 前核对项目根就是 Git 主工作树根；`worktree open` 成功后，root tab 解析、重新查询或身份核对失败时关闭本次新建 Space，关闭失败打印 Space ID 与 `herdr workspace close <id>`。已存在 Space 不自动关闭。
- `bin/qwb-lib.sh` 先按 linked `checkout_path` 找 Space，再检查 `repo_root`；路径已命中但项目根身份不符时拒绝，收尾不能误当作“无 Space”。
- 公开 CLI 用例：`tests/worktree-space.py` 的 `R1 OPEN CLEANUP`（打开后 list 失败、root tab 缺失、关闭失败时的手工命令）及 `R1 NESTED ROOT`（子目录安装的默认派发在建树前拒绝、显式 linked worktree 派发在打开 Space 前拒绝；已有 linked Space 时收尾不关闭、不删 checkout）。
- 反转：把新增测试放进 `f4d7c8a` 的临时源码副本执行，rc=1，首个红例为打开后 list 失败仍遗留 `wTask`；日志 `/tmp/qwb-r1-reversal-618_uekc/baseline-point1.log`。修复版 `python3 tests/worktree-space.py` rc=0。

## 审点 2：已派发工人的成功收尾测试

- `tests/worktree-space.py` 的 `R1 WORKER FINISH` 从 `qwb-worktree.sh finish` 公开 CLI 验证：根 tab 与工人 tab 均属于本票，根 pane 是空闲 shell、工人 idle 时，Space 关闭一次且早于 `git worktree remove`，checkout 与分支已删、账本记 `worktree: merged`；工人 pane 属于别的 workspace 时零关闭、零删除。
- 基线本来能正确处理此路径，故不能诚实声称新用例在未变异的 `f4d7c8a` 上变红：基线该用例 rc=0，日志 `/tmp/qwb-r1-reversal-618_uekc/baseline-point2.log`。按评审指定变异把 `worker_tab` 改为 workspace ID 后，新用例 rc=1，报 `Space 中有非本票 tab wTask:t2`；日志 `/tmp/qwb-r1-reversal-618_uekc/mutant-point2.log`。修复版原实现 rc=0。变异仅在临时副本，未提交。

## 审点 3：归档部分失败恢复

- `bin/qwb-worktree.sh` 的 partial 行增加 `oid=`。`worktree-remove` 失败时输出以 HEAD OID（归档时也以 tag OID）为条件的重跑命令；`branch-delete` 失败时输出带旧 OID 条件的 `git update-ref -d` 命令。同名归档标签若指向当前实际 HEAD，跳过再次打标签并继续；指向其他提交仍拒绝。
- 公开 CLI 用例：`tests/worktree-space.py` 的 `R1 ARCHIVE RECOVERY` 注入一次性 `git worktree remove` 失败，核对 partial OID 后重跑 `--archive` 成功；另注入一次性分支删除失败，执行输出的 OID 条件恢复命令并核对分支删除。原有异 OID 标签拒绝用例保留。
- 反转：新增测试在 `f4d7c8a` 临时源码副本 rc=1，首个红例为 partial 行无 `oid=`；日志 `/tmp/qwb-r1-reversal-618_uekc/baseline-point3.log`。修复版同一 CLI 测试 rc=0。

## 验证与边界

- `bash bin/qwb-test.sh fast --project "$PWD"`：提交前 rc=0。`python3 tests/worktree-space.py`：rc=0，六个分组均 PASS。`shellcheck -S warning bin/qwb-run.sh bin/qwb-worktree.sh bin/qwb-lib.sh` 与四个改动 shell 文件的 `bash -n`：rc=0。`bash tests/smoke.sh`：提交前 rc=0，末节标题是 `== 80. R1 Space 收尾与归档恢复公开 CLI 回归 ==`，之后为该节 PASS 与 `SMOKE PASS`；原始输出 `/tmp/qwb-r1-smoke-precommit.log`。
- 真实 Herdr 0.9.1 只使用自建 named session `qwb-r1fix-9501`：启动 `herdr --session qwb-r1fix-9501 server`；每条 API 命令前 `herdr --session qwb-r1fix-9501 status server` 确认 socket 指向 `~/.config/herdr/sessions/qwb-r1fix-9501/herdr.sock`；依次 `worktree open --cwd <临时主仓> --path <临时副本> --label case --no-focus`、`workspace list`、`workspace close w2`、`workspace list`，各 rc=0，linked checkout 可见一次且关闭后消失。`herdr session stop qwb-r1fix-9501` 与 `delete` 均 rc=0；临时 Git worktree 与仓库已清理。原始命令/rc/JSON：`/tmp/qwb-r1fix-9501.log`。首次路径断言因 `/tmp` 与 `/private/tmp` 别名 rc=1，named session `qwb-r1fix-8645` 已 stop/delete（均 rc=0），日志 `/tmp/qwb-r1fix-8645.log`；第二次按物理路径比较通过。没有对 default 会话执行创建或关闭命令。
- 未验证：真实 Herdr 中的完整 QWB 工人派发与收尾、重启恢复、生产项目。上面的真实实验只证明独立 Space 打开、可见和关闭；其余路径由公开 CLI + Herdr 契约假件覆盖。
- 最终提交上的 fast/full 由提交后运行；full 的 `--report` 收据和原始日志按 `/tmp/qwb-full-<最终 SHA 前 7 位>.md/.log` 保存。报告文件须在命令前不存在；最终提交、前后 clean、原始退出码与耗时以该收据和交付回复为准。
