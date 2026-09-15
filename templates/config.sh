# QW buddy 配置——bash 可直接 source；这就是唯一来源，直接改这里
QWB_WORKERS="codex pi claude"          # 工人表（空格分隔，与 herdr --kind 同名）
QWB_AGENT_START_MS=30000               # 起工人的超时（毫秒）
QWB_WAKE_INTERVAL_MS=120000            # 值守每轮等待预算（毫秒）
QWB_REWAKE_MS=1800000                  # 时间兜底重叫：距上次叫醒超过它仍未结项就再叫一次（0 = 关闭）
QWB_CONTROLLER_PANE=""                 # 主控 pane id；开局点名时填入
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
