# Q-Wolf Buddy (`qwbuddy`)

[English](README.md) · [MIT 许可证](LICENSE)

Q-Wolf Buddy 是仓库内的 AI 编程协作流程：Markdown 主账本记录需求与进度，Git worktree 隔离工人改动，Herdr 提供可见的 Agent 会话。主控负责派工、独立验收、安排审核和决定落地。

## 能力与边界

- `qwb-run.sh` 检查 Given/When/Then 验收场景并记录指纹，默认把工人派到任务 worktree。
- 工人向**项目主账本**追加进度和证据；主控独立运行项目声明的检查后才决定是否验收。
- `qwb-wake.sh` 观察未结项。支持的主控为使用 Stop hook 的 Claude Code、使用自带扩展的 Pi 和使用前台 checkpoint 的 Codex。
- `qwb-status.sh` 报告账本和值守状态，`qwb-lock.sh` 维护主控锁。

主控进程退出后不会自动恢复。具体任务可能需要人工介入。测试通过不等于已具备生产条件。

## 依赖与起步

运行脚本使用 Bash、Git、Herdr、带标准模块的 Perl，以及包含 `shasum` 的常见命令行工具。安装器用 Python 3 合并 Claude Code 的 `.claude/settings.json` Stop hook；缺少 Python 3 时会报告 hook 未安装。可选的 `--worker auto` 路由使用 `jq` 和已配置的 Typesafe API key。所选 Agent CLI 和项目质量门命令也须可用。下述检查使用 ShellCheck；Pi 扩展在 Pi 的 Node 环境运行。这些是工具用途，不是最低版本声明。这里未验证 Linux 支持。

在本仓目录安装到已有 Git 项目：

```bash
bash bin/qwb-init.sh /path/to/project
```

安装器将模板和运行脚本复制到 `<project>/qwbuddy/`，添加角色与任务文件，并在条件满足时安装 Pi 扩展和 Claude Code hook。已有 `qwbuddy/config.sh` 和 `qwbuddy/workers.sh` 会保留；留意输出中是否有部分安装失败。每个工人在 `workers.sh` 中只有一条 `qwb_worker 名称 herdr 参数…` 或 `qwb_worker 名称 pane-run 可执行文件 参数…` 声明，Bash 参数逐项保留空格、空串和字面特殊字符。仍使用 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS` 的旧项目，须从本仓显式运行 `bash bin/qwb-init.sh --migrate-worker-config <项目根>`；迁移先备份 `config.sh`，无法保留旧 shell 语义的命令会被拒绝。已有 `config.sh` 无旧启动键但缺 `workers.sh` 时，普通 init 不执行用户配置，也不猜默认工人表；须按提示手动声明工人后才可派发。

在目标项目的 `qwbuddy/config.sh` 声明项目检查。例如项目本来使用 pnpm：

```bash
QWB_GATE_FAST='pnpm lint'
QWB_GATE_FULL='pnpm lint && pnpm test'
```

在项目根目录启动主控，让它读完整份 `qwbuddy/QWBUDDY.md`。先确认宿主属于 Claude Code、Codex、Pi；未知宿主报告并停止，不取得主控锁。已确认的主控再取锁、点名未结项，按宿主选一种值守入口。按 `qwbuddy/TASK.md` 建立 `tasks/YYYY-MM-DD-topic.md`，写正常与失败路径验收场景，再由主控派工：

```bash
bash qwbuddy/bin/qwb-run.sh --task YYYY-MM-DD-topic --worker codex
```

主控须自己执行相关质量门并记账，不能以工人自述代替验收。锁、审核和 worktree 收尾规则见[主控说明](templates/QWBUDDY.md)。

## 每个主控只选一种值守入口

Claude Code 核对已安装的 `.claude/settings.json` Stop hook，在下次 Stop 事件接续。Pi 的自带源模板是 `templates/pi-extensions/qwb-watch.ts`，安装目标为项目 `.pi/extensions/qwb-watch.ts`；安装后重启 Pi 或运行 `/reload`。启动时持锁会在 `session_start` 值守，晚获主控锁会在后续 `turn_end` 启动；进展以 `[qwb-wake]` follow-up 接续。Codex 把 `bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000` 作为真正前台 tool call 循环：退出 2 处理进展、124 再等待、0 只表示本轮值守结束；须核对输出、主控锁归属和账本，确认无未结项后才收工，孤儿提示或归属不明则按主控说明的锁恢复步骤处理。循环中断后须重新开局。未知宿主不支持，取锁或接入值守前须先确认宿主。

用 `bash qwbuddy/bin/qwb-status.sh` 排查账本和值守。健康结果为「未知」时检查失败的查询、安装和主控锁，不启动另一种值守。单凭 status 不能证明 Codex 前台调用仍在等待，也不能用 Claude hook 回合间的结果断言 hook 未安装。主控退出后须重新启动。运行时保留可见 tab 命令供手工排障，不作为主控开局入口。

新工人 tab 的 workspace 选择顺序是：目标项目 `qwbuddy/config.sh` 中的 `QWB_WORKSPACE`；`herdr workspace list` 中 `worktree.repo_root` 与项目根匹配的 workspace；最后带警告回退到调用者 workspace。配置的 workspace 在本机不存在会拒绝派发。跨项目且无法按项目根匹配时，应在目标项目的该配置文件中有意指定 workspace ID；不要盲目写入主控当前 ID。脚本会 source `config.sh`，因此仅在命令环境设置 `QWB_WORKSPACE` 不能覆盖文件中的赋值。

## 证据与路线图

在源码提交 `1c500b38c014be9e55aa33fede2735ebaaf17d16` 上，主控记录的 macOS 观测是：`fast` 1.38 秒、`full` 88.35 秒、smoke 567 PASS、review-identity PASS、lint PASS。该环境的 Node 为 v26.8.1、ShellCheck 0.11.0、Python 为 3.14.6、Herdr 为 0.9.1。这些是该源码与机器的记录，不是速度保证、最低版本或本次文档提交的测试证明。本票执行者只跑 fast 与 lint。

[E2E 运行记录](docs/E2E-RUNBOOK.md)对应旧 `e917008` 基线，且首次派发有人工介入；它不能证明当前源码已有无人值守的真机闭环。生产使用仍在收敛审核。当前源码的无人介入真机验证、首次信任提示处理、长时间值守与重启恢复验证、生产场景试用仍待完成。

仓库结构：`bin/` 是安装器和运行脚本（上述基线共 11 个 shell 文件）；`templates/` 是主控说明、任务与角色模板、配置和 Pi 扩展；`tests/` 是 smoke 与契约检查；`docs/` 是设计、审核和历史 E2E 记录；`tasks/` 是主账本。
