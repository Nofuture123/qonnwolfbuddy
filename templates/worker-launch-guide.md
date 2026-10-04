# 工人启动专项

**触发**：覆盖默认 Herdr kind、配置权限、处理 pane-run 或迁移旧工人参数时，从 [总说明](QWBUDDY.md) §4 进入。普通派发直接按总说明使用 `qwb-run.sh`。

工人表在 `qwbuddy/config.sh` 的 `QWB_WORKERS`；在 `qwbuddy/workers.sh` 对每名工人保留一条 `qwb_worker` 声明，参数逐个 Bash argv 写入。工人与审核者均交互式最高权限启动；原因见母本仓 `docs/DECISIONS.md`「为什么最高权限」。禁止 headless 参数。

- Pi 固定档位（角色与门禁共用）：`--provider`、`--model`、`--thinking` 各显式出现一次且非空；如 `qwb_worker pi-sol-high herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high`。旧 `--model 渠道/模型` 不再用于角色或门禁；改成 `--provider 渠道 --model 模型ID`，模型ID自身的斜杠保留。所有 Pi 工人统一使用 magpie。
- 独立审核家族：在同一 `qwbuddy/workers.sh` 写 `qwb_family magpie/codex/gpt-6.1-sol gpt`；第一项整体为渠道/模型ID，允许 `gpt` / `claude` / `gemini` / `glm` / `qwen` / `swe`。每个型号只声明一次；缺失、重复或非法家族按 `unknown` 拒绝审核，普通派发不受影响。声明随整个 `workers.sh` 的 `workers_sha256` 冻结，修改后须重授权。重装保留已有配置；旧项目须手动补相应声明。
- Herdr kind：如 `qwb_worker claude herdr claude -- --dangerously-skip-permissions --model claude-opus-5-5 --effort medium`；分隔符后的参数逐项传给 `herdr agent start --`。
- 旧 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS`：用母本仓 `bash <母本仓>/bin/qwb-init.sh --migrate-worker-config <项目根>` 显式迁移。迁移前派发拒绝；迁移失败保留原配置，按报错处理歧义项，不从老版本复制配置。
