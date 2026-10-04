# 每个 agent 一条定义：qwb_worker <名> herdr <harness> -- <逐项 argv>。
# 旧式 herdr <argv> 行仍以名为 harness；空串与含空格参数保真。
# 工人默认最高权限：隔离 worktree 中执行，产物由主控验收。
# 常驻role是独立opt-in，仅herdr pi且明确provider/model/thinking可用于role；
# 本项目真机验收后才在config.sh声明QWB_ROLE_PI_CONTROL=verified，未声明时拒绝启动/控制。
# QWB_ROLE_PI_INTEGRATION默认已装herdr-agent-state.ts；role仅显式加载它，无自动全项目watcher。
# qwb-role保留workers逐项argv；再添加职责/精确session绑定及no-approve/offline，不发送初始模型任务。
# Claude Code role控制未验证，明确拒绝；原qwb-run adapter不受此限制。
qwb_worker pi herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high
qwb_worker claude herdr claude -- --dangerously-skip-permissions --model claude-opus-5-5 --effort medium
qwb_worker pi-sol-high herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high
qwb_worker pi-astra-high herdr pi -- --approve --provider magpie --model codex/gpt-6-astra --thinking high
qwb_worker pi-astra-low herdr pi -- --approve --provider magpie --model codex/gpt-6-astra --thinking low
qwb_worker claude-opus-medium herdr claude -- --dangerously-skip-permissions --model claude-opus-5-5 --effort medium
qwb_worker claude-fable-low herdr claude -- --dangerously-skip-permissions --model claude-fable-5-1 --effort low

# 家族键为完整渠道/模型ID，模型ID可含斜杠，不得按名字猜。
qwb_family magpie/codex/gpt-6.1-sol gpt
qwb_family magpie/codex/gpt-6-astra gpt
qwb_family anthropic/claude-opus-5-5 claude
qwb_family anthropic/claude-fable-5-1 claude
