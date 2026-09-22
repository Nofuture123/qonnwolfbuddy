# 生产边界忽略规则返修复核

**结论：PASS（仅不完整旧 marker 升级审点）。** 基线 `3b8edbf67f09f003c23300133f0c645a79a89d6b`，`production-boundaries` 当前候选由 `git rev-parse` 固定为 `a8eec488a75d9cec8a006af4deeb310a3b7554b2`。`git diff baseline..candidate` 仅改 `bin/qwb-init.sh` 与 `tests/boundary-readiness.sh`；`tests/smoke.sh` 无差异。用 `git show candidate:文件` 核对候选行号，未重审路由、收尾或旧基线。

- **实现核对**：`bin/qwb-init.sh:71-94` 将七条必需运行态规则列成清单；遇到旧 marker 时逐条精确检查并只追加缺项。原内容只可能在末尾补换行，既有字节不重写；第二次安装各项已存在，落入 `bin/qwb-init.sh:95-101` 的跳过分支。
- **候选定向**：将固定候选 `git archive` 导入临时目录，运行 `bash tests/boundary-readiness.sh`，`rc=0`、**15 PASS**、`BOUNDARY PASS`。新增 `tests/boundary-readiness.sh:15-44` 在 marker 仅有 `.worktrees/` 的真实 Git 项目中，先用 `git status`/`git check-ignore` 证明漏项，再核对七条运行态路径均忽略、原前缀保留、重复安装字节不变。
- **独立隔离复现**：另建临时 Git 项目，旧 `.gitignore` 含用户行、旧 marker、`.worktrees/`，且**无尾换行**。从候选 blob 安装两次均 `rc=0`；第一次后的文件以原始字节为前缀，七条规则各恰一行，第二次文件逐字节相同。提交安装产物后创建七种运行态文件，`git check-ignore -q` 全部成功，限定这些路径的 `git status --short --untracked-files=all` 为空。
- **清理与范围**：两次临时导出/项目均由 `TemporaryDirectory` 清理；白名单 `git diff --check baseline..candidate` 为 `rc=0`。未跑 full/smoke，未创建窗口、联网或派发。本 PASS 不代表其他已排队审点通过。
