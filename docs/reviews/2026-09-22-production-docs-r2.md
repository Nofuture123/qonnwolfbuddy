# 生产文档返修复核（仅三项）

**结论：PASS（仅文档返修）。** 固定范围：`59eb8ffe66d3afe146aa6d03d8d941370c63800c..556d6aac7769edccd3598513eff7615d11dce5df`，白名单 `README.md`、`README.zh.md`、`templates/QWBUDDY.md`。只用 `git diff` 查看该范围、`git show 556d6aa:文件` 核对候选行号；差异仅白名单三文件，`git diff --check` 为 0。未读主工作区作为候选，未跑门或重复旧复现，未创建窗口、未派发。没有临时文件或进程需要清理。

1. **环境覆盖指引已修正。** `README.md:53`、`README.zh.md:53`、`templates/QWBUDDY.md:13` 均改为从目标项目 `qwbuddy/config.sh` 配置 `QWB_WORKSPACE`，明确命令环境赋值会被脚本 `source` 的文件赋值覆盖。上轮错误的临时环境优先级承诺已消失；中英文一致。
2. **Pi 获锁时序已写成必要步骤。** `README.md:45`、`README.zh.md:45`、`templates/QWBUDDY.md:11,17` 要求每次开局先获主控锁，再 `/reload`，随后用 `qwb-status.sh` 确认 `pi-ext` 进程存活；也明说先加载扩展、后获锁不会自行启动。文档不再把扩展文件存在等同于正在值守。
3. **跨 workspace 的 `--ensure` 限制已明示。** `README.md:53`、`README.zh.md:53`、`templates/QWBUDDY.md:19-20` 把已知可复用路径限于主控和值守 tab 同 workspace；异 workspace 再调用可能拒绝，需运行时修复，不再承诺跨 workspace 幂等。中英文与模板一致。

本 PASS 只表示前次报告的三处文档错误得到如实修订。Pi 自动启动、跨 workspace 复用、锁与派发等运行时问题仍须分别修复和验证；不能据此宣布生产就绪或当前候选真机闭环通过。
