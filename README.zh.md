# Q-Wolf Buddy (`qwbuddy`)

[English](README.md) · [MIT 许可证](LICENSE)

Q-Wolf Buddy 是仓库内的 AI 编程协作流程：Markdown 主账本记录需求与进度，Git worktree 隔离工人改动，Herdr 提供可见的 Agent 会话。主控负责派工、独立验收、安排审核和决定落地。

## 能力与边界

- `qwb-run.sh` 检查 Given/When/Then 验收场景并记录指纹，默认把工人派到任务 worktree。
- 工人向**项目主账本**追加进度和证据；主控独立运行项目声明的检查后才决定是否验收。
- `qwb-wake.sh` 观察未结项。支持的主控为使用 Stop hook 的 Claude Code和使用自带扩展的 Pi。
- `qwb-status.sh` 报告账本和值守状态，`qwb-lock.sh` 维护主控锁。

主控进程退出后不会自动恢复。具体任务可能需要人工介入。测试通过不等于已具备生产条件。

## 依赖与起步

运行脚本使用 Bash、Git、Herdr、带标准模块的 Perl，以及包含 `shasum` 的常见命令行工具。安装器用 Python 3 合并 Claude Code 的 `.claude/settings.json` Stop hook；缺少 Python 3 时会报告 hook 未安装。可选的 `--worker auto` 路由使用 `jq` 和已配置的 Typesafe API key。所选 Agent CLI 和项目质量门命令也须可用。下述检查使用 ShellCheck；Pi 扩展在 Pi 的 Node 环境运行。这些是工具用途，不是最低版本声明。这里未验证 Linux 支持。

在本仓目录安装到已有 Git 项目：

```bash
bash bin/qwb-init.sh /path/to/project
```

安装器将模板和运行脚本复制到 `<project>/qwbuddy/`，添加角色与任务文件，并在条件满足时安装 Pi 扩展和 Claude Code hook。已有 `qwbuddy/config.sh` 和 `qwbuddy/workers.sh` 会保留；留意输出中是否有部分安装失败。每个工人在 `workers.sh` 中只有一条 `qwb_worker 名称 herdr 宿主 -- 参数…` 或 `qwb_worker 名称 pane-run 可执行文件 参数…` 声明；旧式 `qwb_worker 名称 herdr 参数…` 仍以工人名作为宿主。Pi 固定档位须显式声明 `--provider`、`--model`、`--thinking`；模板中的 Pi 工人统一使用 Magpie；`pi-sol-high` 参数为 `--provider magpie --model codex/gpt-6.1-sol --thinking high`。审核者的模型须与实现者不同，且为独立会话；同一会话换角色不算独立审核。型号比较忽略渠道前缀、大小写与推理档位，`family` 为可选附记。 Bash 参数逐项保留空格、空串和字面特殊字符。仍使用 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS` 的旧项目，须从本仓显式运行 `bash bin/qwb-init.sh --migrate-worker-config <项目根>`；迁移先备份 `config.sh`，无法保留旧 shell 语义的命令会被拒绝。已有 `config.sh` 无旧启动键但缺 `workers.sh` 时，普通 init 不执行用户配置，也不猜默认工人表；须按提示手动声明工人后才可派发。

在目标项目的 `qwbuddy/config.sh` 声明项目检查。例如项目本来使用 pnpm：

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

在项目根目录启动主控，让它读完整份 `qwbuddy/QWBUDDY.md`。先确认宿主属于 Claude Code、Pi；未知宿主报告并停止，不取得主控锁。已确认的主控再取锁、点名未结项，按宿主选一种值守入口。按 `qwbuddy/TASK.md` 建立 `tasks/YYYY-MM-DD-topic.md`，写正常与失败路径验收场景。模板本身不包含启动授权；未迁旧票首次派发前，须主控在头部显式填写 `implementation-authorized:` 授权依据和正整数 `dispatch-budget:`，再由主控派工：

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker pi-sol-high
```

主控须自己执行相关质量门并记账，不能以工人自述代替验收。锁、审核和 worktree 收尾规则见[主控说明](templates/QWBUDDY.md)。

**测试须知：** 本仓离线测试在桩失效时对真 Herdr 失效关闭；临时文件只建在仓库内 `.qwb-tmp/`；仓库根路径不得超过 89 字节，否则使用 socket 的测试在启动时拒绝；新增测试文件须显式接入测试入口。

## 每个主控只选一种值守入口

Claude Code 核对已安装的 `.claude/settings.json` Stop hook，在下次 Stop 事件接续。Pi 的自带源模板是 `templates/pi-extensions/qwb-watch.ts`，安装目标为项目 `.pi/extensions/qwb-watch.ts`；安装后重启 Pi 或运行 `/reload`。启动时持锁会在 `session_start` 值守，晚获主控锁会在 `agent_settled`（Pi 不再自动继续）时启动；需处理的变化以 `[qwb-wake]` follow-up 接续；未迁 running 票工人未丢失时，`working:` 只记进度不叫醒，时间兜底取票修改时间与最近 wake 中较晚者（quiet 下关闭）。旧票 exit 2 投递后也要等到 `agent_settled` 才重启值守；已迁票的 `[qwb-handoff]` 摘要在投递 API 接受后立即续接唯一代码监督。未知宿主不支持，取锁或接入值守前须先确认宿主。

用 `bash qwbuddy/bin/qwb-status.sh` 排查账本和值守。健康结果为「未知」时检查失败的查询、安装和主控锁，不启动另一种值守。不能用 Claude hook 回合间的 status 结果断言 hook 未安装。主控退出后须重新启动。运行时保留可见 tab 命令供手工排障，不作为主控开局入口。

项目根和历史值守 tab 的 workspace 选择顺序是：目标项目 `qwbuddy/config.sh` 中的 `QWB_WORKSPACE`；`herdr workspace list` 中与项目根匹配的非 linked workspace；最后带警告回退到调用者 workspace。任务 Git worktree 的工人 tab 进入该 worktree 自己的 Herdr Space，派发前须在 Spaces 中可见。配置的 workspace 在本机不存在或指向任务 Space 会拒绝派发。跨项目且无法按项目根匹配时，应在目标项目配置主 workspace ID；不要盲目写入主控当前 ID。脚本会 source `config.sh`，因此仅在命令环境设置 `QWB_WORKSPACE` 不能覆盖文件中的赋值。

## 证据与路线图

在本台 macOS 机器（Darwin 27.0.0）上，提交 `20ea2cc` 的主控实测：`fast` 2.85 秒；smoke 单独两次为 190.13 秒与 191.28 秒，804 PASS / 0 FAIL，共 95 个节标题（含字母子节，编号末节为 88）；当时四段依次运行的全门为 574.34 秒（同机稍早一次为 456.58 秒），844 PASS / 0 FAIL。改为四段同时运行后，在提交 `c2079f0` 上、同机负载约 55 时全门 502 秒，844 PASS / 0 FAIL；合入前的候选在隔离副本里顺序连跑五次全绿，385–502 秒（负载 5–47），同一晚依次运行的版本两次为 769 秒与 1044 秒（负载 13–23）。提交 `4bdd2fd` 上全门 429 秒，859 PASS / 0 FAIL。全门同时运行 smoke、review-identity、lint、`tests/collab-all.sh`（15 项测试），收齐输出后按上述顺序整段打印。该环境的 Herdr 为 0.9.3、Pi 为 1.0.2、Bash 为 5.3.20（另以 `/bin/bash` 3.2.57 做语法与兼容检查）。完整的逐票证据与起点对比见[审核报告](docs/reviews/2026-10-03-qwb-full-audit-r1.md)。这些是所引源码与机器的记录，不是速度保证、最低版本或后续提交的测试证明。

[E2E 运行记录](docs/E2E-RUNBOOK.md)对应有人工介入的旧基线。历史主控真机运行与收尾演练保存在 `docs/reviews/`。新工人表在提交 `4bdd2fd` 上真机通过一轮：Claude Code 主控（`claude-opus-5-5` / `medium`）加 Pi 工人（Sol / `high`），14 项断言全 PASS；Pi 主控加 Claude Code 工人在 `2183765` 上流程走通但一项值守断言失败，修复后未重跑。提交 `57d6e7a` 上同一组合再通过一轮（派发后确认工人开工）。常驻职责（规划、门禁）在 2026-10-05 真机演练过一次：启动、授权、开票、派工成功，工人交付后链路断掉，未走到门禁验收；修复已合入 `44ab8ac`（该提交上真机再通过一轮）。第二次演练（`59f6734`）走到了门禁通过、落地与收尾，但主控要读源码并绕开官方落地脚本才走通，相应修复在进行中。首次信任提示、长时间值守与重启恢复、已迁协作票 land 收尾、生产试用仍待验证。真机入口只接受 Pi 和 Claude Code 主控/工人；Claude Code 主控默认为 `claude-opus-5-5` / `medium`，Pi 主控为 `magpie/codex/gpt-6.1-sol` / `high`；工人为 Pi Sol / `high` 或 Claude Opus 5.5 / `medium`。真机流程由主控运行。

仓库结构：`bin/` 是安装器和运行脚本（当前源码共 16 个 shell 文件）；`templates/` 是主控说明、任务与角色模板、配置和 Pi 扩展；`tests/` 是 smoke 与契约检查；`docs/` 是设计、审核和历史 E2E 记录；`tasks/` 是主账本。
