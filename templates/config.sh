# QW buddy 配置——bash 可直接 source；这就是唯一来源，直接改这里
QWB_WORKERS="codex pi claude"          # 工人表（空格分隔；启动方式可由下一项按工人覆盖）
QWB_WORKER_LAUNCH=""                   # 可选：工人名=herdr|pane-run:<交互命令>；值可含空格，遇下一个工人名= 才结束
# 启动参数：默认让所有 herdr-kind 工人以最高权限启动——工人在隔离 worktree 里干活、产物由主控验收，
# 审批提示没人点只会卡死流程（见 docs/DECISIONS.md「为什么最高权限」）。格式与 QWB_WORKER_LAUNCH 同款：
# 「工人名=参数串」，值可含空格、遇下一个工人名= 才结束；参数按空格切词追加到 herdr agent start 的 `--` 之后
# （未列出/空值不加 `--`）。参数串同样禁 headless（-p/--print/--exec/exec）。
# pane-run 工人的参数写在 QWB_WORKER_LAUNCH 的命令行里（如 cmd=pane-run:cmd --yolo --trust）——
# 在这里再给它配值会被拒绝派发，一个工人的启动参数只能有一处。
QWB_WORKER_ARGS="codex=--dangerously-bypass-approvals-and-sandbox claude=--dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve pi=--approve"
QWB_AGENT_START_MS=30000               # 起工人的超时（毫秒）
QWB_WAKE_INTERVAL_MS=120000            # 值守每轮等待预算（毫秒）
QWB_REWAKE_MS=1800000                  # 时间兜底重叫：距上次叫醒超过它仍未结项就再叫一次（0 = 关闭）
QWB_CONTROLLER_PANE=""                 # 主控 pane id；开局点名时填入
QWB_WORKSPACE=""                       # 本项目的 herdr workspace id（如 wA3）；主控开局把 HERDR_WORKSPACE_ID 填在这里，
                                       # 跨项目派活的主控改填目标项目的 id。非空即用——本机 herdr 查不到该 id 就拒绝派发
                                       # （不静默回退）；留空则按 herdr workspace list 的 worktree.repo_root 匹配项目根
                                       # （多个匹配取 focused 的），都没有才落调用者 workspace 并在 stderr 警告
# —— 质量门：qwb-test.sh fast|full 读取执行；命令在项目根下跑，按本项目布局调路径 ——
# 默认留空：未声明（空值）时 qwb-test.sh 拒绝执行并提示、qwb-lint.sh 报 FAIL——新项目必配，不许静默当绿。
# 示例（QW buddy 母本仓的写法，路径须换成你项目的）：
#   QWB_GATE_FAST='for f in bin/*.sh tests/smoke.sh; do bash -n "$f" || exit 1; done && shellcheck bin/*.sh'
#   QWB_GATE_FULL="bash tests/smoke.sh && bash bin/qwb-lint.sh"
QWB_GATE_FAST=""                       # 快门：快、无外部依赖，改一行跑它
QWB_GATE_FULL=""                       # 全门：完整检查，合并前跑
# —— 以下仅为人/AI 阅读，脚本不读 ——
# 工人能力档：codex=强实现（复杂代码、重构）｜pi=快速便宜（常规执行、机械改动、调研）｜claude=难活/审核（架构判断、对抗审查、前端）
# 派工规则：复杂架构/高风险→强档；常规实现/机械改动→快档；审核必须换模型家族；联网/实时信息按能力挑
#           派工前可查 quota-axi；模型判定 = 智力档 × 额度现状（额度只是参考）
# 硬规矩：工人一律 Herdr 窗口交互式运行（禁 headless）；零通知使用者；只用 Herdr；超时一律毫秒
