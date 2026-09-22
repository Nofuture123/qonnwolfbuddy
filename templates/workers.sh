# 每个工人一条启动定义。herdr 后每个 Bash 实参即最终 argv 的一个参数；空串也保留。
# pane-run 后第一项是可执行文件，其余每个 Bash 实参是独立参数。
# 工人默认最高权限：隔离 worktree 中执行，产物由主控验收；见 docs/DECISIONS.md。
qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox
qwb_worker pi herdr --approve
qwb_worker claude herdr --dangerously-skip-permissions
qwb_worker devin herdr --permission-mode dangerous --respect-workspace-trust false
qwb_worker omp herdr --auto-approve
