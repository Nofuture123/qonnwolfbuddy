# QW buddy 配置——bash 可直接 source；这就是唯一来源，直接改这里
QWB_WORKERS="codex pi claude"          # 工人表（空格分隔，与 herdr --kind 同名）
QWB_AGENT_START_MS=30000               # 起工人的超时（毫秒）
QWB_WAKE_INTERVAL_MS=120000            # 值守每轮等待预算（毫秒）
QWB_CONTROLLER_PANE=""                 # 主控 pane id；开局点名时填入
# —— 以下仅为人/AI 阅读，脚本不读 ——
# 工人能力档：codex=强实现（复杂代码、重构）｜pi=快速便宜（常规执行、机械改动、调研）｜claude=难活/审核（架构判断、对抗审查、前端）
# 派工规则：复杂架构/高风险→强档；常规实现/机械改动→快档；审核必须换模型家族；联网/实时信息按能力挑
#           派工前可查 quota-axi；模型判定 = 智力档 × 额度现状（额度只是参考）
# 硬规矩：工人一律 Herdr 窗口交互式运行（禁 headless）；零通知使用者；只用 Herdr；超时一律毫秒
