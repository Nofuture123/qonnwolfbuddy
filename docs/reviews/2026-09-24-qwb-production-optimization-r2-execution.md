# QWB 生产优化 r2 返修执行记录

基线 `87222a2dca8fb649b85128b47650921b3806f2da`；代码定稿与真实 pi 闭环候选 `9e9e7c931b5b148d22408ba172dcf1536454eba5`。仅处理 r2 审点 1–6；未 push、合并本分支或改动其他项目。r2 审核原文已随代码提交。新增 CLI 用例 `tests/r2-cli.py` 可逐项运行；反转只在 `/tmp/qwb-r2-reversal-0ev3838z/baseline` 的 `87222a2` 导出副本执行，未提交变异。

## 逐项结果

1. **安装权限**：`bin/qwb-init.sh` 对新建 `.gitignore`、`AGENTS.md`、`CLAUDE.md` 使用 `0666 & ~umask`，对已有文件沿用原权限；Python 合并 `.claude/settings.json` 时同样保留已有模式或按 umask 设置新文件模式。`append_hook` 在复制、追加、移动失败后删除本次临时文件。CLI 用例 `permissions` 检查已有 0644、umask 022/027 下的新建模式及钩子移动失败清理；基线 rc=1（新文件均为 0600），修复版 rc=0。红证据：`/tmp/qwb-r2-reversal-0ev3838z/permissions.log`。
2. **真实工人闭环**：代码 SHA `9e9e7c9` 下，在 `/tmp/qwb-r2-real-wsudr1n1/project` 安装候选并创建无害任务；`qwb-run.sh --project <临时项目> --task case --worker pi` rc=0，真实 Pi 0.87.1（本机默认配置）在 named session `qwb-r2-real-28297` 的 linked Space `w2` / pane `w2:p2` 工作。账本有 `worktree-space:`、`scenarios-fp:`、`dispatch:`，Herdr `agent wait` 最终 rc=0、状态 `done`。主控独立读取工人提交 `f72073cf98450f8dff985ff1f05277a4f51ed438`：只含 `proof.txt`，提交内字节为 `QWB_R2_PI_OK\n`，工作树干净。主控 `git merge --no-ff case -m 'Merge case proof'` rc=0，合并提交 `331efc9d8e4421ee243a72b55dad8b7dbb85c2fb`；`qwb-worktree.sh finish case --merged --project <临时项目>` rc=0，Space `w2`、checkout、分支均已消失，最后记录为 `worktree: merged branch=case tag=-`；主 Space `w1` 前后 JSON 相同。完整逐命令及原始 rc：`/tmp/qwb-r2-real-9e9e7c9-evidence/commands.log`；Space 前后 JSON、账本原始字节、proof 和清理记录同目录。`herdr session stop qwb-r2-real-28297` 与 `delete` 均 rc=0，临时项目已清理。此项是最终候选上的真实验收序列；它不是一个可诚实宣称在 `87222a2` 必然变红的新增自动测试。相关默认派发的公开 CLI 反转由第 3、6 项用例覆盖。
3. **Git 布局**：`bin/qwb-run.sh` 用物理 `--show-toplevel == 项目根` 且物理 `--absolute-git-dir == --git-common-dir` 判定主工作树。CLI 用例 `layout` 检查 separate-git-dir、submodule 放行，以及子目录安装、linked worktree 根拒绝；基线 rc=1（separate-git-dir 被误拒），修复版 rc=0。红证据：`/tmp/qwb-r2-reversal-0ev3838z/layout.log`。
4. **`branch-delete` 续做**：`bin/qwb-worktree.sh` 在 checkout 已删时只接受本票最后一条、动作匹配、格式完整且带 OID 的 `stage=branch-delete` 记录；复核归档标签、分支旧 OID 与没有其他 worktree 检出后，条件删 ref、清分支配置并追加最终 `worktree:` 行。失败时的恢复命令改为带 OID 前置条件的 `finish` 重跑。CLI 用例 `recovery` 覆盖 `--archive` 与 `--merged` 的一次性失败续做、最终记录及 OID 改变拒绝；基线 rc=1（重跑报 worktree 不存在），修复版 rc=0。红证据：`/tmp/qwb-r2-reversal-0ev3838z/recovery.log`。
5. **分支配置清理**：`bin/qwb-worktree.sh` 在成功按旧 OID 删除分支 ref 后删除本地 `branch.<名>` 配置节；清理失败仅警告并输出可执行命令，已完成的 Git 删除不回滚。CLI 用例 `branch_config` 覆盖正常删除与注入清理失败；基线 rc=1（配置仍在），修复版 rc=0。红证据：`/tmp/qwb-r2-reversal-0ev3838z/branch_config.log`。
6. **派发警告**：`bin/qwb-lib.sh` 的 `resolve_workspace` 增加任务 worktree 回退静默参数，`bin/qwb-run.sh` 只在默认或已登记 linked worktree 派发时使用；`--here` 保留原警告，workspace 查询失败/响应坏仍在建树前拒绝。CLI 用例 `warning` 覆盖默认与显式 worktree、`--here`、查询失败/坏响应的零建树副作用；基线 rc=1（误导警告），修复版 rc=0。红证据：`/tmp/qwb-r2-reversal-0ev3838z/warning.log`。

## 验证、偏差与未验证项

- 代码提交前 `python3 tests/r2-cli.py` rc=0（五组 PASS）；`bash bin/qwb-test.sh fast --project "$PWD"` rc=0；`bash tests/smoke.sh` rc=0，最后一节标题为 `== 81. R2 安装权限、Git 布局、收尾续做与派发提示公开 CLI 回归 ==`，之后为该节 PASS 与 `SMOKE PASS`，原始日志 `/tmp/qwb-r2-smoke-precommit.log`。r1 Space 回归同次 smoke 通过。
- 真实 Pi 首次追加的 `done:` 行因它使用的 shell 变量紧接多字节标点而含两个无效 UTF-8 字节，且 SHA 缺失；Pi 保持追加式账本，随后补了一条带完整 SHA 的 `done:` 行。原始账本保留在证据目录（SHA-256 `9ecbf6e22701e9045b9144cf645573e6fc14a6c3300b3f341f86d029a53e489e`）。主控以提交对象和 `proof.txt` 字节独立验收，未以这两条自述代替验收。Pi 的会话另显示一次 `Memory Add` 调用；它不属于项目代码或本次验收依据。
- 真实闭环仅覆盖 pi 默认配置；Claude、Codex、pane-run、Herdr 重启恢复及生产安装未验证。named session 外没有执行 Herdr 创建或关闭；真实生产项目未触碰。
- 本执行报告在闭环后以文档提交，代码保持 `9e9e7c9`；提交后用 `git diff --stat 9e9e7c9 <最终SHA>` 核对仅有本报告。最终 SHA 的 fast/full 在该文档提交后运行；带 `--report` 的 full 收据和原始日志保存到 `/tmp/qwb-full-<最终 SHA 前 7 位>.md/.log`，以收据记录前后 SHA、clean 与原始门退出码。
