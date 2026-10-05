# QWB real E2E

- 候选 SHA：`21837659b7c592130044706b26e7fc0cfa446290`
- 主控：`pi`
- 工人：`claude`
- 中文票 id：`真实闭环-e2e`
- 默认工人名预期：`qwb--e2e-8c270138`
- 主控模型/推理档：`magpie/codex/gpt-6.1-sol` / `high`
- 工人模型/推理档：`claude-opus-5-5/medium`
- 会话：`qwb-e2e-pi-claude-1791160375-79097`
- 临时项目：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/project`
- nonce：`1cd7127500283e54`
- 工具版本：`{"herdr": ["herdr 0.9.3"], "pi": ["1.0.2"], "claude": ["2.1.289 (Claude Code)"]}`

## 时间线

- 2026-10-05T00:32:58.792008+00:00 主 workspace 已创建；controller pane=w1:p1
- 2026-10-05T00:33:14.671884+00:00 pi TUI 已核对模型=magpie/codex/gpt-6.1-sol 推理档=high
- 2026-10-05T00:33:14.698921+00:00 主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行
- 2026-10-05T00:34:11.588274+00:00 Claude 已识别信任框并选择 Yes，仅按一次 Enter
- 2026-10-05T00:36:00.011905+00:00 Pi 已输出 DONE，等待 35s 无新 followUp 后统计排队消息
- 2026-10-05T00:36:37.564422+00:00 主控输出 DONE，Pi followUp 排空窗口已结束
- 2026-10-05T00:36:37.866258+00:00 成功收尾命令时刻：2026-10-05T00:35:42.353000+00:00
- 2026-10-05T00:36:37.909057+00:00 断言：worker_space_observed=PASS, ledger=PASS, worker_agent_name=PASS, main_content=PASS, git_cleanup=PASS, space_observed=PASS, space_cleanup=PASS, controller_done=PASS, host_wake=FAIL, no_foreground_wake=PASS, finish_time_observed=PASS, wake_skip_lines_zero=PASS, pi_wake_queue_drained=PASS, pi_stale_wake_limit=PASS, default_untouched=PASS
- 2026-10-05T00:36:37.911392+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.oBcDZyx3/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project/.worktrees/ç\x9c\x9få®\x9eé\x97\xadç\x8e¯-e2e']
- 2026-10-05T00:36:37.913075+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.oBcDZyx3/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project/.worktrees/ç\x9c\x9få®\x9eé\x97\xadç\x8e¯-e2e']

## 断言

- PASS worker_space_observed
- PASS ledger
- PASS worker_agent_name
- PASS main_content
- PASS git_cleanup
- PASS space_observed
- PASS space_cleanup
- PASS controller_done
- FAIL host_wake
- PASS no_foreground_wake
- PASS finish_time_observed
- PASS wake_skip_lines_zero
- PASS pi_wake_queue_drained
- PASS pi_stale_wake_limit
- PASS default_untouched
- PASS global_state_unchanged

- 账本含非法 UTF-8：`False`
- 主控转录：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/controller-transcript.txt`
- 工人转录：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/worker-transcript.txt`
- Herdr/命令日志：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/commands.jsonl`、`/tmp/qwb-e2e-pi-claude.VRwTwf3c/monitor.jsonl`
- 主控会话 JSONL：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/pi-sessions/2026-10-05T00-33-00-501Z_01a1097a-6c55-741c-8ead-32a481643d30.jsonl`
- 宿主唤醒证据：``

## 宿主值守统计

- 主控收到的唤醒消息数：`2`
- 每条消息的逐轮跳过行数：`[0, 0]`
- 收尾之后才送达的唤醒数：`0`
- 回合内 sleep 轮询命令数：`0`
- Pi 完成后静默排空窗口：`35 秒`
- Pi 完成后排空上限：`180 秒`
- Pi 账本 wake 行/已送达摘要：`2 / 2`
- 逐条时间与命令取证：`/tmp/qwb-e2e-pi-claude.VRwTwf3c/wake-observations.json`
- 消息 1：送达 `2026-10-05T00:34:17.375Z`；跳过行 `0`；收尾后 `False`
- 消息 2：送达 `2026-10-05T00:34:37.622Z`；跳过行 `0`；收尾后 `False`

- 最终 rc：`1`
- 全局文件：`/Users/rocky/.pi/agent/trust.json`
- 跑前 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`
- 跑后 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`
- ~/.claude.json projects 新增键：`['/private/tmp/qwb-e2e-claude-pi.oBcDZyx3/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project', '/private/tmp/qwb-e2e-pi-claude.VRwTwf3c/project/.worktrees/ç\x9c\x9få®\x9eé\x97\xadç\x8e¯-e2e']`

- 会话清理：已请求停止和删除；stop rc=0；delete rc=0
