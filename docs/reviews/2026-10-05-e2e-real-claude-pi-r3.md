# QWB real E2E

- 候选 SHA：`57d6e7af4a3f901af73d0472efb3bf076a162f48`
- 主控：`claude`
- 工人：`pi`
- 中文票 id：`真实闭环-e2e`
- 默认工人名预期：`qwb--e2e-8c270138`
- 主控模型/推理档：`claude-opus-5-5` / `medium`
- 工人模型/推理档：`magpie/codex/gpt-6.1-sol/high`
- 会话：`qwb-e2e-claude-pi-1791169650-17981`
- 临时项目：`/tmp/qwb-e2e-claude-pi.LgVpo2iB/project`
- nonce：`ee1770cfa823ce7f`
- 工具版本：`{"herdr": ["herdr 0.9.3"], "claude": ["2.1.289 (Claude Code)"], "pi": ["1.0.2"]}`

## 时间线

- 2026-10-05T03:07:31.141671+00:00 主 workspace 已创建；controller pane=w1:p1
- 2026-10-05T03:07:32.224869+00:00 Claude 已识别信任框并选择 Yes，仅按一次 Enter
- 2026-10-05T03:07:35.058912+00:00 claude TUI 已核对模型=claude-opus-5-5 推理档=medium
- 2026-10-05T03:07:35.075653+00:00 主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行
- 2026-10-05T03:09:22.008499+00:00 主控输出 DONE
- 2026-10-05T03:09:22.104482+00:00 成功收尾命令时刻：2026-10-05T03:09:06.410000+00:00
- 2026-10-05T03:09:22.119418+00:00 断言：worker_space_observed=PASS, ledger=PASS, worker_agent_name=PASS, main_content=PASS, git_cleanup=PASS, git_runtime_clean=PASS, space_observed=PASS, space_cleanup=PASS, controller_done=PASS, host_wake=PASS, no_foreground_wake=PASS, finish_time_observed=PASS, wake_skip_lines_zero=PASS, default_untouched=PASS
- 2026-10-05T03:09:22.121042+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.LgVpo2iB/project']
- 2026-10-05T03:09:22.122230+00:00 Claude ~/.claude.json projects 新增键：['/private/tmp/qwb-e2e-claude-pi.LgVpo2iB/project']

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
- 主控转录：`/tmp/qwb-e2e-claude-pi.LgVpo2iB/controller-transcript.txt`
- 工人转录：`/tmp/qwb-e2e-claude-pi.LgVpo2iB/worker-transcript.txt`
- Herdr/命令日志：`/tmp/qwb-e2e-claude-pi.LgVpo2iB/commands.jsonl`、`/tmp/qwb-e2e-claude-pi.LgVpo2iB/monitor.jsonl`
- 主控会话 JSONL：`/Users/rocky/.claude/projects/-private-tmp-qwb-e2e-claude-pi-LgVpo2iB-project/8c554124-9e23-4474-8809-d94789642db9.jsonl`
- 宿主唤醒证据：`<task-notification>
<summary>Stop hook feedback</summary>
</task-notification>
<system-reminder>
Stop hook blocking error from command "Stop": Herdr subscription established: w2:p1
看账本：1 张未结项有进展 →① 2099-01-01-真实闭环-e2e(running) 最近: done: pane=w2:p1 dispatch op_id=8b37c5fa2f0afe2b2ab527462eaa72c0；提交 SHA=5d7254157dca5af7f55bbb2daf692c9fd5ecb026；仅新增 e2e/hello.txt。实际检查：python3 工作树字节/提交字节/提交范围/。只需读这些票。

</system-reminder>`

## 宿主值守统计

- 主控收到的唤醒消息数：`1`
- 每条消息的逐轮跳过行数：`[0]`
- 收尾之后才送达的唤醒数：`0`
- 回合内 sleep 轮询命令数：`0`
- Pi 完成后静默排空窗口：`不适用 秒`
- Pi 完成后排空上限：`不适用 秒`
- Pi 账本 wake 行/已送达摘要：`不适用`
- 逐条时间与命令取证：`/tmp/qwb-e2e-claude-pi.LgVpo2iB/wake-observations.json`
- 消息 1：送达 `2026-10-05T03:08:47.231Z`；跳过行 `0`；收尾后 `False`

- 最终 rc：`0`
- ~/.claude.json projects 新增键：`['/private/tmp/qwb-e2e-claude-pi.LgVpo2iB/project']`
- 全局文件：`/Users/rocky/.pi/agent/trust.json`
- 跑前 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`
- 跑后 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`

- 会话清理：已请求停止和删除；stop rc=0；delete rc=0
