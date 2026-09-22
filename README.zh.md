# Q-Wolf Buddy (`qwbuddy`)

[English](README.md) · [MIT 许可证](LICENSE)

Q-Wolf Buddy 是仓库内的 AI 编程协作流程：Markdown 主账本记录需求与进度，Git worktree 隔离工人改动，Herdr 提供可见的 Agent 会话。主控负责派工、独立验收、安排审核和决定落地。

## 能力与边界

- `qwb-run.sh` 检查 Given/When/Then 验收场景并记录指纹，默认把工人派到任务 worktree。
- 工人向**项目主账本**追加进度和证据；主控独立运行项目声明的检查后才决定是否验收。
- `qwb-wake.sh` 观察未结项。Claude Code 用 Stop hook，Pi 用扩展，Codex 用前台 checkpoint，其他 harness 可用可见 Herdr tab。
- `qwb-status.sh` 报告账本和值守状态，`qwb-lock.sh` 维护主控锁。

主控进程退出后不会自动恢复。具体任务可能需要人工介入。测试通过不等于已具备生产条件。

## 依赖与起步

运行脚本使用 Bash、Git、Herdr、带标准模块的 Perl，以及包含 `shasum` 的常见命令行工具。安装器用 Python 3 合并 Claude Code 的 `.claude/settings.json` Stop hook；缺少 Python 3 时会报告 hook 未安装。可选的 `--worker auto` 路由使用 `jq` 和已配置的 Typesafe API key。所选 Agent CLI 和项目质量门命令也须可用。下述检查使用 ShellCheck；Pi 扩展在 Pi 的 Node 环境运行。这些是工具用途，不是最低版本声明。这里未验证 Linux 支持。

在本仓目录安装到已有 Git 项目：

```bash
bash bin/qwb-init.sh /path/to/project
```

安装器将模板和运行脚本复制到 `<project>/qwbuddy/`，添加角色与任务文件，并在条件满足时安装 Pi 扩展和 Claude Code hook。已有 `qwbuddy/config.sh` 会保留；留意输出中是否有部分安装失败。

在目标项目的 `qwbuddy/config.sh` 声明项目检查。例如项目本来使用 pnpm：

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

在项目根目录启动主控，让它阅读 `qwbuddy/QWBUDDY.md`。它先取得主控锁、点名未结项，再按当前 harness 选一种值守入口。按 `qwbuddy/TASK.md` 建立 `tasks/YYYY-MM-DD-topic.md`，写正常与失败路径验收场景，再由主控派工：

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker codex
```

主控须自己执行相关质量门并记账，不能以工人自述代替验收。锁、审核和 worktree 收尾规则见[主控说明](templates/QWBUDDY.md)。

## 每个主控只选一种值守入口

Claude Code 使用已安装的 Stop hook。Pi 安装 `.pi/extensions/qwb-watch.ts` 后需重启或 `/reload`。Codex 在前台 tool call 中循环运行有界的 `qwb-wake.sh --block --max-ms 180000`。其他 harness 使用可见 tab 兜底：

```bash
bash qwbuddy/bin/qwb-wake.sh --ensure --pane "$HERDR_PANE_ID"
```

兜底入口需要 Herdr pane 上下文。`--ensure` 不会从 `HERDR_PANE_ID` 自动读取唤醒目标；调用时传 `--pane`，或在目标稳定时有意配置 `QWB_CONTROLLER_PANE`。不要每次开局把临时 pane ID 持久化进配置。`--block` 通过主控锁和 `HERDR_PANE_ID` 复核归属，不需要目标 `--pane`。

新工人和值守 tab 的 workspace 选择顺序是：已声明的 `QWB_WORKSPACE`；`herdr workspace list` 中 `worktree.repo_root` 与项目根匹配的 workspace；最后带警告回退到调用者 workspace。声明的 workspace 在本机不存在会拒绝派发。跨项目且无法按项目根匹配时，可在本次调用环境指定目标项目的 `QWB_WORKSPACE`，或有意配置它；不要盲目写入主控当前 ID。

## 证据与路线图

在源码提交 `1c500b38c014be9e55aa33fede2735ebaaf17d16` 上，主控记录的 macOS 观测是：`fast` 1.38 秒、`full` 88.35 秒、smoke 567 PASS、review-identity PASS、lint PASS。该环境的 Node 为 v26.8.1、ShellCheck 0.11.0、Python 为 3.14.6、Herdr 为 0.9.1。这些是该源码与机器的记录，不是速度保证、最低版本或本次文档提交的测试证明。本票执行者只跑 fast 与 lint。

[E2E 运行记录](docs/E2E-RUNBOOK.md)对应旧 `e917008` 基线，且首次派发有人工介入；它不能证明当前源码已有无人值守的真机闭环。生产使用仍在收敛审核。当前源码的无人介入真机验证、首次信任提示处理、长时间值守与重启恢复验证、生产场景试用仍待完成。

仓库结构：`bin/` 是安装器和运行脚本（上述基线共 11 个 shell 文件）；`templates/` 是主控说明、任务与角色模板、配置和 Pi 扩展；`tests/` 是 smoke 与契约检查；`docs/` 是设计、审核和历史 E2E 记录；`tasks/` 是主账本。
