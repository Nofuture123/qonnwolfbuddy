# 工人启动专项

**触发**：覆盖默认 Herdr kind、配置权限、处理 pane-run 或迁移旧工人参数时，从 [总说明](QWBUDDY.md) §4 进入。普通派发直接按总说明使用 `qwb-run.sh`。

工人表在 `qwbuddy/config.sh` 的 `QWB_WORKERS`；在 `qwbuddy/workers.sh` 对每名工人保留一条 `qwb_worker` 声明，参数逐个 Bash argv 写入。工人与审核者均交互式最高权限启动；原因见母本仓 `docs/DECISIONS.md`「为什么最高权限」。禁止 headless 参数。

- Herdr kind：如 `qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox`；其后的权限参数逐项传给 `herdr agent start --`。
- 自定义命令：如 `qwb_worker cmd pane-run cmd --yolo --trust`；首项是可执行文件，后续逐项为参数。pane-run 检测并改名后用 `herdr pane run` 直打提示词，不走只支持官方 kind 的 `agent prompt`；若 300ms 内未进入 working/done/blocked（Command Code 长文本可能只粘贴未提交），再补一次 Enter。
- 旧 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS`：用母本仓 `bash <母本仓>/bin/qwb-init.sh --migrate-worker-config <项目根>` 显式迁移。迁移前派发拒绝；迁移失败保留原配置，按报错处理歧义项，不从老版本复制配置。
