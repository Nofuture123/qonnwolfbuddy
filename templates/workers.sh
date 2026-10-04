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
qwb_worker pi-glm-high herdr pi -- --approve --provider zai-coding-cn --model glm-5.3 --thinking high
qwb_worker pi-sol-high herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high
qwb_worker omp-gemini herdr omp -- --auto-approve --model google-antigravity/gemini-3.1-pro --thinking high

# 独立审核的家族声明：第一项为完整渠道/模型ID（模型ID可含斜杠），不得按名字猜。
# 允许gpt/claude/gemini/glm/qwen/swe；缺失、重复或非法声明仅在判家族时按unknown拒绝。
qwb_family devin/swe-2-high swe
qwb_family openai-codex/gpt-6-sol gpt
qwb_family anthropic/claude-fable-5 claude
qwb_family zai-coding-cn/glm-5.3 glm
qwb_family magpie/codex/gpt-6.1-sol gpt
qwb_family google-antigravity/gemini-3.1-pro gemini
# 原账本固定表的三项，保留已知型号的声明。
qwb_family openai-codex/gpt-6.1-sol gpt
qwb_family openai-codex/gpt-6-astra gpt
qwb_family anthropic/claude-opus-4-6 claude
