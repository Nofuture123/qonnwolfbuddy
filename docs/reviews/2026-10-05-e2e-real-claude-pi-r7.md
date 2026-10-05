# QWB real E2E

- 候选 SHA：`a4ddc78a652a82cd28be82125fa338ebe92637f5`
- 主控：`claude`
- 工人：`pi`
- 中文票 id：`真实闭环-e2e`
- 默认工人名预期：`qwb--e2e-8c270138`
- 主控模型/推理档：`claude-opus-5-5` / `medium`
- 工人模型/推理档：`magpie/codex/gpt-6.1-sol/high`
- 会话：`qwb-e2e-claude-pi-1791189594-97862`
- 临时项目：`/tmp/qwb-e2e-claude-pi.1MjObohw/project`
- nonce：`6509649cb15f4182`
- 工具版本：`{"herdr": ["herdr 0.9.3"], "claude": ["2.1.289 (Claude Code)"], "pi": ["1.0.2"]}`

## 时间线

- 2026-10-05T08:39:55.912222+00:00 主 workspace 已创建；controller pane=w1:p1
- 2026-10-05T08:39:57.003990+00:00 Claude 已识别信任框并选择 Yes，仅按一次 Enter
- 2026-10-05T08:39:59.861561+00:00 claude TUI 已核对模型=claude-opus-5-5 推理档=medium
- 2026-10-05T08:39:59.875103+00:00 主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行
- 2026-10-05T08:42:18.816690+00:00 主控输出 DONE
- 2026-10-05T08:42:18.913504+00:00 成功收尾命令时刻：2026-10-05T08:42:04.790000+00:00
- 2026-10-05T08:42:18.929242+00:00 断言：worker_space_observed=PASS, ledger=PASS, worker_agent_name=PASS, main_content=PASS, git_cleanup=PASS, git_runtime_clean=PASS, space_observed=PASS, space_cleanup=PASS, controller_done=PASS, host_wake=PASS, no_foreground_wake=PASS, finish_time_observed=PASS, wake_skip_lines_zero=PASS, default_untouched=PASS
- 2026-10-05T08:42:18.931048+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.1MjObohw/project']
- 2026-10-05T08:42:18.932309+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.1MjObohw/project']

## 断言

- PASS worker_space_observed
- PASS ledger
- PASS worker_agent_name
- PASS main_content
- PASS git_cleanup
- PASS git_runtime_clean
- PASS space_observed
- PASS space_cleanup
- PASS controller_done
- PASS host_wake
- PASS no_foreground_wake
- PASS finish_time_observed
- PASS wake_skip_lines_zero
- PASS default_untouched
- PASS global_state_unchanged

- 账本含非法 UTF-8：`False`
- 主控转录：`/tmp/qwb-e2e-claude-pi.1MjObohw/controller-transcript.txt`
- 工人转录：`/tmp/qwb-e2e-claude-pi.1MjObohw/worker-transcript.txt`
- Herdr/命令日志：`/tmp/qwb-e2e-claude-pi.1MjObohw/commands.jsonl`、`/tmp/qwb-e2e-claude-pi.1MjObohw/monitor.jsonl`
- 主控会话 JSONL：`/Users/rocky/.claude/projects/-private-tmp-qwb-e2e-claude-pi-1MjObohw-project/fee480cd-9212-4a8c-8404-9eb4c6dab59e.jsonl`
- 宿主唤醒证据：`<task-notification>
<summary>Stop hook feedback</summary>
</task-notification>
<system-reminder>
Stop hook blocking error from command "Stop": Herdr subscription established: w2:p1
看账本：1 张未结项有进展 →① 2099-01-01-真实闭环-e2e(running) 最近: done: pane=w2:p1 op_id=91854896e9a559c367d0c5cd0e7f6711；仅新增 e2e/hello.txt，提交 SHA=b36dfd4bc830b733518c5d50a6dc27bc227ce07c。实际检查：Python 文件字节与唯一改动断言 rc=0，原始输出「PASS。只需读这些票。

</system-reminder>`

## 宿主值守统计

- 主控收到的唤醒消息数：`3`
- 每条消息的逐轮跳过行数：`[0, 0, 0]`
- 收尾之后才送达的唤醒数：`0`
- 回合内 sleep 轮询命令数：`1`
- Pi 完成后静默排空窗口：`不适用 秒`
- Pi 完成后排空上限：`不适用 秒`
- Pi 账本 wake 行/已送达摘要：`不适用`
- 逐条时间与命令取证：`/tmp/qwb-e2e-claude-pi.1MjObohw/wake-observations.json`
- 消息 1：送达 `2026-10-05T08:40:44.863Z`；跳过行 `0`；收尾后 `False`
- 消息 2：送达 `2026-10-05T08:41:37.371Z`；跳过行 `0`；收尾后 `False`
- 消息 3：送达 `2026-10-05T08:41:43.704Z`；跳过行 `0`；收尾后 `False`

- 最终 rc：`0`
- ~/.claude.json projects 新增键：`['/private/tmp/qwb-e2e-claude-pi.1MjObohw/project']`
- 全局文件：`/Users/rocky/.pi/agent/trust.json`
- 跑前 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`
- 跑后 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`

- 会话清理：已请求停止和删除；stop rc=0；delete rc=0
