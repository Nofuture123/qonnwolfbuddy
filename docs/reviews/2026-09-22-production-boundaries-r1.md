# 生产边界返修独立复审

**结论：AMEND。** 基线 `1c500b38c014be9e55aa33fede2735ebaaf17d16`，候选 `3b8edbf67f09f003c23300133f0c645a79a89d6b`（先由 `git rev-parse 3b8edbf` 固定）。只看白名单内 `git diff baseline..candidate` 与 `git show candidate:文件`，未把主工作区当候选；差异仅 `bin/qwb-init.sh`、`bin/qwb-dispatch.sh`、`bin/qwb-worktree.sh`、`tests/boundary-readiness.sh`、`tests/smoke.sh`。未跑 full/smoke、未联网、未创建窗口或派发。

## 发现 1：已有旧 marker 的不完整忽略段只补 Pi 日志，仍漏其他运行态

- **问题与行号**：`bin/qwb-init.sh:71-78` 一旦发现旧 marker，只检查并追加 `qwbuddy/.pi-watch.err`；`bin/qwb-init.sh:81-90` 的完整七条规则仅在无 marker 时写入。候选自己的 `tests/boundary-readiness.sh:15,25-28` 用“marker + `.worktrees/`”模拟旧段，却只断言 Pi 行存在、第二次字节不变，没有核对其余运行态忽略项。
- **隔离实证**：从固定候选导出安装器和模板，在临时 Git 项目放 `user-line`、旧 marker、`.worktrees/` 三行，执行安装器 `rc=0` 并提交安装产物。之后创建 `qwbuddy/.controller.lock/owner`、`qwbuddy/.watch`、`qwbuddy/.pi-watch.err`；`git status --short --untracked-files=all` 报 `?? qwbuddy/.controller.lock/owner` 与 `?? qwbuddy/.watch`，Pi 日志被忽略。生成的 `.gitignore` 只有原三行加 Pi 行，重复安装不会补其余规则。该夹具是**不完整旧段**；基线安装器正常生成的完整六条旧段不受此反例影响，但本票的旧段升级测试和“补缺项”承诺涵盖该情况。
- **影响**：安装命令报告成功且重复运行稳定，实际主控锁和值守登记仍污染 Git 状态，容易被提交进项目；部分安装或人工保留 marker 后无法自愈。
- **最小修复**：对已有 marker 逐项核对全部必需的运行态 ignore 规则，只追加缺项且保持用户原有行字节不变；把当前 marker-only 夹具扩成 `git status` 反证，并验证第二次安装不重复。

## 其余两审点

- **路由**：候选 `bin/qwb-dispatch.sh:149` 的 HTTP 非 200 分支只输出状态、耗时与固定类别，不读取响应体作错误文字；临时假 `curl` 反射 Authorization canary 的 `tests/boundary-readiness.sh` 定向运行 `rc=0`，13 项总计 PASS，其中路由断言未发现 stdout/stderr canary。`tests/smoke.sh` 新增上层默认回退断言已核对在最终退出之前，但本轮未运行 smoke，不能把该集成断言称为实跑通过。
- **收尾**：`bin/qwb-worktree.sh:102-131` 在账本/Git 操作前校验单组件 ID、任务与 worktree 物理路径及本仓登记。候选定向测试的越界 ID、符号链接、借名、外仓 worktree、未合入拒绝、合法收尾与中文 keep 均通过；我另在隔离 Git 项目实跑中文 ID 的 `--merged` 和 `--archive`，两者 `rc=0`，目录按预期移除、账本记账，归档标签保留。未发现该 diff 的其他可行动问题。

**验证与清理**：固定候选 `git archive` 临时导出后，`bash tests/boundary-readiness.sh` 为 `rc=0，13 PASS`；相关 Shell `bash -n` 与 `shellcheck tests/boundary-readiness.sh` 均 `rc=0`；白名单 `git diff --check baseline..candidate` 为 `rc=0`。额外的旧 marker 与中文收尾复现仅使用临时仓库，临时目录已清理。上述结果不替代 full gate 或真机闭环。
