# 工人启动专项

**触发**：覆盖默认 Herdr kind、配置权限、处理 pane-run 或迁移旧工人参数时，从 [总说明](QWBUDDY.md) §4 进入。普通派发直接按总说明使用 `qwb-run.sh`。

工人表在 `qwbuddy/config.sh` 的 `QWB_WORKERS`；在 `qwbuddy/workers.sh` 对每名工人保留一条 `qwb_worker` 声明，参数逐个 Bash argv 写入。工人与审核者均交互式最高权限启动；原因见母本仓 `docs/DECISIONS.md`「为什么最高权限」。禁止 headless 参数。

- Pi 固定档位（角色与门禁共用）：`--provider`、`--model`、`--thinking` 各显式出现一次且非空；如 `qwb_worker pi-sol-high herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high`。旧 `--model 渠道/模型` 不再用于角色或门禁；改成 `--provider 渠道 --model 模型ID`，模型ID自身的斜杠保留。模板 `pi-glm-high` 同样分开写。OMP 帮助列有 legacy `--provider`，但本轮未证明分开写的型号解析等价，保留原合写声明。
- 独立审核家族：在同一 `qwbuddy/workers.sh` 写 `qwb_family magpie/codex/gpt-6.1-sol gpt`；第一项整体为渠道/模型ID，允许 `gpt` / `claude` / `gemini` / `glm` / `qwen` / `swe`（Devin SWE）。每个型号只声明一次；缺失、重复或非法家族按 `unknown` 拒绝审核，普通派发不受影响。声明随整个 `workers.sh` 的 `workers_sha256` 冻结，修改后须重授权。重装保留已有配置；旧项目须手动补相应声明。
- Herdr kind：如 `qwb_worker codex herdr --dangerously-bypass-approvals-and-sandbox`；其后的权限参数逐项传给 `herdr agent start --`。
- Devin：`qwb_worker devin herdr --model swe-2-max --permission-mode dangerous --respect-workspace-trust false`。
- Command Code 1.65.0：`cmd` 与 `cmdc` 是同一入口；交互工人用 `qwb_worker cmdc pane-run cmdc --yolo --trust --skip-onboarding -m deepseek/deepseek-v4-flash`。本机安装的 `commandcode.integration` 向 Herdr 上报 `cmd` 状态。首项是可执行文件，后续逐项为参数；pane-run 检测并改名后用 `herdr pane run` 直打提示词，不走只支持官方 kind 的 `agent prompt`；若 300ms 内未进入 working/done/blocked（长文本可能只粘贴未提交），再补一次 Enter。
- zcode 0.16.9 的 TUI 入口是 `zcode` 或 `zcode tui`；旧 `zcodecli chat` / `chat-open` 已失效。本机 Herdr 0.9.1 不识别该 TUI，写文件默认要求审批；在有可靠状态上报的集成之前不能作为 pane-run 工人。本轮不使用 zcode，也不开发集成。
- 旧 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS`：用母本仓 `bash <母本仓>/bin/qwb-init.sh --migrate-worker-config <项目根>` 显式迁移。迁移前派发拒绝；迁移失败保留原配置，按报错处理歧义项，不从老版本复制配置。
