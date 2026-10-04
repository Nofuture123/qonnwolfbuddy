# QWB real E2E

- 候选 SHA：`ded7d889ff3fef9c7b9fe142612177c4bedff011`
- 主控：`claude`
- 工人：`devin`
- 中文票 id：`真实闭环-e2e`
- 默认工人名预期：`qwb--e2e-8c270138`
- 主控模型/推理档：`opus` / `high`
- Codex service_tier：`不适用`
- 工人模型：`swe-2-max`
- 会话：`qwb-e2e-claude-devin-1791123473-2368`
- 临时项目：`/tmp/qwb-e2e-claude-devin.1bGKDEwH/project`
- nonce：`6d1cfdbe63eae6cb`
- 工具版本：`{"herdr": ["herdr 0.9.3"], "claude": ["2.1.289 (Claude Code)"], "devin": ["devin 3000.11.3 (9c803229faa4)"], "cmdc": ["1.65.4"]}`

## 时间线

- 2026-10-04T14:17:55.656193+00:00 主 workspace 已创建；controller pane=w1:p1
- 2026-10-04T14:17:56.770449+00:00 Claude 已识别信任框并选择 Yes，仅按一次 Enter
- 2026-10-04T14:17:59.506584+00:00 claude TUI 已核对模型=opus 推理档=high
- 2026-10-04T14:17:59.520861+00:00 主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行
- 2026-10-04T14:24:33.560425+00:00 主控输出 BLOCKED
- 2026-10-04T14:24:33.730921+00:00 成功收尾命令时刻：2026-10-04T14:21:13.771000+00:00
- 2026-10-04T14:24:33.778693+00:00 断言：worker_space_observed=PASS, ledger=FAIL, devin_agent_name=PASS, main_content=PASS, git_cleanup=FAIL, space_observed=PASS, space_cleanup=FAIL, controller_done=FAIL, host_wake=FAIL, no_foreground_wake=PASS, finish_time_observed=PASS, wake_skip_lines_zero=PASS, default_untouched=PASS
- 2026-10-04T14:24:33.781821+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-devin.1bGKDEwH/project']
- 2026-10-04T14:24:33.783461+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-devin.1bGKDEwH/project']

## 断言

- PASS worker_space_observed
- FAIL ledger
- PASS devin_agent_name
- PASS main_content
- FAIL git_cleanup
- PASS space_observed
- FAIL space_cleanup
- FAIL controller_done
- FAIL host_wake
- PASS no_foreground_wake
- PASS finish_time_observed
- PASS wake_skip_lines_zero
- PASS default_untouched

- 账本含非法 UTF-8：`False`
- 主控转录：`/tmp/qwb-e2e-claude-devin.1bGKDEwH/controller-transcript.txt`
- 工人转录：`/tmp/qwb-e2e-claude-devin.1bGKDEwH/worker-transcript.txt`
- Herdr/命令日志：`/tmp/qwb-e2e-claude-devin.1bGKDEwH/commands.jsonl`、`/tmp/qwb-e2e-claude-devin.1bGKDEwH/monitor.jsonl`
- 主控会话 JSONL：`/Users/rocky/.claude/projects/-private-tmp-qwb-e2e-claude-devin-1bGKDEwH-project/673d2465-7daf-47d3-999d-da08dbe3a6c1.jsonl`
- 宿主唤醒证据：``

## 宿主值守统计

- 主控收到的唤醒消息数：`5`
- 每条消息的逐轮跳过行数：`[0, 0, 0, 0, 0]`
- 收尾之后才送达的唤醒数：`0`
- 回合内 sleep 轮询命令数：`3`
- Pi 完成后静默排空窗口：`不适用 秒`
- Pi 完成后排空上限：`不适用 秒`
- Pi 账本 wake 行/已送达摘要：`不适用`
- 逐条时间与命令取证：`/tmp/qwb-e2e-claude-devin.1bGKDEwH/wake-observations.json`
- 消息 1：送达 `2026-10-04T14:18:38.966Z`；跳过行 `0`；收尾后 `False`
- 消息 2：送达 `2026-10-04T14:19:08.538Z`；跳过行 `0`；收尾后 `False`
- 消息 3：送达 `2026-10-04T14:19:39.149Z`；跳过行 `0`；收尾后 `False`
- 消息 4：送达 `2026-10-04T14:20:08.360Z`；跳过行 `0`；收尾后 `False`
- 消息 5：送达 `2026-10-04T14:20:39.110Z`；跳过行 `0`；收尾后 `False`

- 最终 rc：`1`
- ~/.claude.json projects 新增键：`['/private/tmp/qwb-e2e-claude-devin.1bGKDEwH/project']`

- 会话清理：已请求停止和删除；stop rc=0；delete rc=0
