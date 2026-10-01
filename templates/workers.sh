# 每个 agent 一条定义：qwb_worker <名> herdr <harness> -- <逐项 argv>。
# 旧式 herdr <argv> 行仍以名为 harness；空串与含空格参数保真。
# pane-run 后第一项是可执行文件，其余每个 Bash 实参是独立参数。
# 工人默认最高权限：隔离 worktree 中执行，产物由主控验收；见 docs/DECISIONS.md。
# 常驻role是独立opt-in，不改变以下派发定义。仅herdr pi且明确provider/model/thinking可用于role；
# 本项目真机验收后才在config.sh声明QWB_ROLE_PI_CONTROL=verified，未声明时拒绝启动/控制。
# QWB_ROLE_PI_INTEGRATION默认已装herdr-agent-state.ts；role仅显式加载它，无自动全项目watcher。
# qwb-role保留workers逐项argv；再添加职责/精确session绑定及no-approve/offline，不发送初始模型任务。
# Claude Code/Codex role控制未验证，明确拒绝；原qwb-run所有adapter不受此限制。
qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox
qwb_worker pi herdr --approve
qwb_worker claude herdr --dangerously-skip-permissions
qwb_worker devin herdr devin -- --permission-mode dangerous --respect-workspace-trust false --model swe-2-high
qwb_worker omp herdr --auto-approve
# 具名路由候选固定 harness × 模型 × effort；上面旧名字保留供显式派发兼容。
qwb_worker codex-sol-high herdr codex -- --dangerously-bypass-approvals-and-sandbox --model gpt-6-sol -c model_reasoning_effort=high
qwb_worker claude-fable-high herdr claude -- --dangerously-skip-permissions --model claude-fable-5 --effort high
qwb_worker pi-glm-high herdr pi -- --approve --model zai-coding-cn/glm-5.3 --thinking high
qwb_worker omp-gemini herdr omp -- --auto-approve --model google-antigravity/gemini-3.1-pro --thinking high
