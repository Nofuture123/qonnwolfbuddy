# Claude Code 在 Herdr 里的会话行为实测

- 日期：2026-10-05，07:42Z–07:52Z
- 环境：Herdr 0.9.3、Claude Code 2.1.289，`claude-opus-5-5` / `medium`；两个隔离的具名 Herdr 会话，项目建在本仓 `.qwb-tmp/probe-claude-role/project`，默认会话未被触碰，两个会话均已停止并删除
- 目的：给「Claude Code 当副主控（规划常驻职责）」准备事实；查清第二、三轮演练里 Claude Code 把长提示词当粘贴内容（R9）的条件
- 原始样本：`.qwb-tmp/probe-claude-role/out/`（轮询记录）与 `.qwb-tmp/real-herdr-samples/`（Herdr 响应）。这两个目录不入库

以下每一条都是对着确切命令试出来的；只试过一次的标「单次」。

## 启动与会话身份

1. `herdr agent start 名字 --kind claude --pane 窗口 --timeout 60000 -- --dangerously-skip-permissions --model claude-opus-5-5 --effort medium --session-id 会话号 --append-system-prompt 文字`：`--session-id` 与 `--append-system-prompt` 可以同时用。`--session-id` 必须是带连字符的标准 UUID（帮助原文 `must be a valid UUID`）。
2. 目录没被信任过时，Claude Code 停在信任确认框：`agent start` 3.6 秒后返回退出码 1、`{"error":{"code":"agent_not_ready","message":"agent probe is blocked during startup and is not ready for prompts"}}`；窗口的 `agent_status` 为 `blocked`，没有 `agent_session`。选「信任」后 0.27 秒变 `idle`，0.54 秒报出 `agent_session`。
3. 目录已信任时，`agent start` 约 3.4 秒返回成功，**响应里已经带 `agent_session`**（与 Pi 不同，Pi 要约 1.5 秒后才报）。形状：`{"agent":"claude","kind":"id","source":"herdr:claude","value":"会话号"}`，值等于传入的 `--session-id`。
4. 会话文件在 `~/.claude/projects/目录名/会话号.jsonl`，目录名是工作目录绝对路径把 `/` 与 `.` 都换成 `-`（例：`…/qonnwolfbuddy/.qwb-tmp/probe-claude-role/project` → `-Users-rocky-projects-qonnwolfbuddy--qwb-tmp-probe-claude-role-project`）。**第一条消息发出之前这个目录和文件都不存在。** Claude Code 没有指定会话目录的参数，会话文件在项目之外。
5. 前台进程：`herdr pane process-info` 里 `argv0` 为 `claude`；跑过一轮对话后前台进程列表里会多一个 `caffeinate`（所以「前台只有一个进程」不成立，按 `argv0` 名字过滤后唯一）。已信任目录里，进程号在三轮对话间不变。首次信任那一次，信任确认后读到的进程号与几轮对话后读到的不同（单次，原因未查）。

## 运行态与模型证明

6. 空闲为 `idle`；收到提示后约 0.6 秒变 `working`，答完回到 `idle`，`completion_seq` 与 `state_change_seq` 同步加一。本次没有观察到 `done`。
7. 会话文件里每条 `type":"assistant"` 记录带 `message.model`（实测 `claude-opus-5-5`）和顶层 `effort`、`perTurnEffort`（实测 `medium`）。这是可核对的实际模型与档位证据，但只有答过至少一轮才有。
8. 窗口底部的状态行是使用者自己配置的（本机显示 `Opus 5.5 │ …`，不显示档位），不能当作产品级证据。

## 退出与续接

9. `herdr pane run 窗口 /exit`：0.3 秒内进程结束，约 1 秒后窗口的 `agent` 变为空、`agent_status` 变 `unknown`、`agent_session` 为空；`herdr agent get 名字` 返回 `agent_not_found`。Claude Code 退出时打印 `claude --resume 会话号`。
10. 对已存在的会话号再用 `--session-id` 启动：Claude Code 打印 `Error: Session ID … is already in use.` 后退出，`agent start` 等到超时返回退出码 1、`code":"timeout"`。
11. `-- … --resume 会话号 --append-system-prompt 文字` 续接成功：`agent_session` 的值不变，会话文件是同一个、在原文件上续写（76 行 → 83 行），目录里没有新文件；续接后答复的 `message.model` 与 `effort` 不变。

## 提示词何时被当成粘贴内容（R9 的条件）

12. 经 `herdr agent prompt` 或 `herdr pane run` 发给 Claude Code 的文字，**含换行，或单行超过 800 个字符（按字符数，不按字节）**，在会话文件里被记成 `<pasted_content id="…">…</pasted_content>`，外面没有任何使用者自己的文字；不超过 800 字符的单行记成普通输入。实测：786 字符（ASCII）与 762 字符（中文，2286 字节）是普通输入；806 字符（ASCII）与 813 字符（中文）是粘贴；五行共约 130 字符的消息是粘贴。两条发送通道表现相同（`pane run` 297 字符普通、897 字符粘贴）。
13. 被记成粘贴内容之后模型怎么做不固定：两轮演练里搭建阶段的多行长指令，Claude Code 都先回「粘贴内容里的指令要你本人明确要求后我才执行」（2 次里 2 次）；本次把产品真实的派工提示词（`bin/qwb-run.sh` 的执行者提示词，按探测项目路径展开后 849 字符、单行）发给全新的 Claude Code，它被记成粘贴，但直接开工并完成了任务（1 次里 1 次）。
14. 产品现状（主控按 `bin/qwb-run.sh` 的模板估算，只有第 13 条那一次是实测长度）：执行者派工提示词的固定文字约 323 字符，另含三次任务书路径、一次工作目录、两次项目根路径与操作号，常见项目路径下约 690–850 字符，跨在 800 的两侧；返工与续派提示词在此之上再加前缀。值守叫醒主控的 `看账本：…` 一条会把多张票拼在一起，票多时也会超过。

## 工具调用、打断与后台命令在会话文件里的样子（08:04Z 追加实测）

15. 工具执行中：Herdr 运行态为 `working`，会话文件末尾是一条 `assistant` 记录，`stop_reason` 为 `tool_use`、内容里有 `tool_use`（带 `id`），还没有对应的 `tool_result`。
16. 工具执行中按一次 `esc`（单次）：约 5 秒内运行态回到 `idle`；Claude Code 自己补写一条 `user` 记录，内容是对应 `tool_use_id` 的 `tool_result`（`is_error` 为真，文字 `The user doesn't want to proceed with this tool use…`），随后一条 `user` 文本记录 `[Request interrupted by user for tool use]`。也就是说这次打断之后工具调用是配对的，没有留下悬空的 `tool_use`。模型还在输出、尚未发出工具调用时打断的情形没有试。
17. 正常答完的一轮以 `assistant` 记录（`stop_reason` 为 `end_turn`）结束，后面跟 `system` 记录 `stop_hook_summary` 与 `turn_duration`。打断后再发新提示，新一轮照常记录。
18. Claude Code 会拒绝在前台单独执行 `sleep 45`，自行改成后台命令后结束这一轮：此时运行态是 `idle`，但后台命令仍在跑（窗口底部显示 `1 shell`），命令结束时它可能自己再开一轮。会话文件里只有那条工具结果的文字 `Command running in background with ID: …` 能看出来（单次）。

脱敏后的会话文件样本（只留结构）：`.qwb-tmp/real-herdr-samples/claude-session-tool-running.jsonl`、`claude-session-interrupted.jsonl`、`claude-session-after-new-turn.jsonl`。

## 对设计的含义

- Claude Code 当常驻职责在机制上可行：会话号可由调用方指定并在启动响应里立即核对，续接不换号，实际模型与档位能从会话文件核对。与 Pi 的差异集中在：会话文件在项目之外且首条消息前不存在；没有 Pi 那样可核对的固定页脚；未信任目录会让启动返回失败；退出命令是 `/exit`；空白输入框里有占位提示文字。
- 发给 Claude Code 的提示词应保持单行且不超过 800 字符；更长的内容放进文件，提示词只指路。
