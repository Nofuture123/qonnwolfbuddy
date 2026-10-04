# QWB real E2E

- 候选 SHA：`20ea2cc56d8fcbb2d72b555f1dbd29ad0813f99b`
- 主控：`pi`
- 工人：`devin`
- 中文票 id：`真实闭环-e2e`
- 默认工人名预期：`qwb--e2e-8c270138`
- 主控模型/推理档：`magpie/codex/gpt-6.1-sol` / `high`
- Codex service_tier：`不适用`
- 工人模型：`swe-2-max`
- 会话：`qwb-e2e-pi-devin-1791129906-29368`
- 临时项目：`/tmp/qwb-e2e-pi-devin.WcX92DPY/project`
- nonce：`a137b067defb97d0`
- 工具版本：`{"herdr": ["herdr 0.9.3"], "pi": ["1.0.2"], "devin": ["devin 3000.11.3 (9c803229faa4)"], "cmdc": ["Updated 1.65.4 → 1.74.1", "1.74.1"]}`

## 时间线

- 2026-10-04T16:05:08.815407+00:00 主 workspace 已创建；controller pane=w1:p1
- 2026-10-04T16:05:12.561577+00:00 pi TUI 已核对模型=magpie/codex/gpt-6.1-sol 推理档=high
- 2026-10-04T16:05:12.576140+00:00 主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行
- 2026-10-04T16:12:02.163376+00:00 Pi 已输出 DONE，等待 35s 无新 followUp 后统计排队消息
- 2026-10-04T16:12:42.659207+00:00 主控输出 DONE，Pi followUp 排空窗口已结束
- 2026-10-04T16:12:42.726544+00:00 成功收尾命令时刻：2026-10-04T16:11:09.470000+00:00
- 2026-10-04T16:12:42.741600+00:00 断言：worker_space_observed=PASS, ledger=PASS, devin_agent_name=PASS, main_content=PASS, git_cleanup=PASS, space_observed=PASS, space_cleanup=PASS, controller_done=PASS, host_wake=PASS, no_foreground_wake=PASS, finish_time_observed=PASS, wake_skip_lines_zero=PASS, pi_wake_queue_drained=PASS, pi_stale_wake_limit=PASS, default_untouched=PASS

## 断言

- PASS worker_space_observed
- PASS ledger
- PASS devin_agent_name
- PASS main_content
- PASS git_cleanup
- PASS space_observed
- PASS space_cleanup
- PASS controller_done
- PASS host_wake
- PASS no_foreground_wake
- PASS finish_time_observed
- PASS wake_skip_lines_zero
- PASS pi_wake_queue_drained
- PASS pi_stale_wake_limit
- PASS default_untouched
- PASS global_state_unchanged

- 账本含非法 UTF-8：`False`
- 主控转录：`/tmp/qwb-e2e-pi-devin.WcX92DPY/controller-transcript.txt`
- 工人转录：`/tmp/qwb-e2e-pi-devin.WcX92DPY/worker-transcript.txt`
- Herdr/命令日志：`/tmp/qwb-e2e-pi-devin.WcX92DPY/commands.jsonl`、`/tmp/qwb-e2e-pi-devin.WcX92DPY/monitor.jsonl`
- 主控会话 JSONL：`/tmp/qwb-e2e-pi-devin.WcX92DPY/pi-sessions/2026-10-04T16-05-09-054Z_01a107a9-773e-7137-8b11-87856d57ca8a.jsonl`
- 宿主唤醒证据：`[qwb-wake] 看账本：1 张未结项有进展 →① 2099-01-01-真实闭环-e2e(running) 最近: done: op=88941309882d26283f8a242740c430f7 pane=w2:p1 commit=49731356945e063b3f0187559e27d45574e9ea0a branch=真实闭环-e2e checks=[git show HEAD:e2e/hello.txt|cmp - <。只需读这些票。`

## 宿主值守统计

- 主控收到的唤醒消息数：`4`
- 每条消息的逐轮跳过行数：`[0, 0, 0, 0]`
- 收尾之后才送达的唤醒数：`0`
- 回合内 sleep 轮询命令数：`0`
- Pi 完成后静默排空窗口：`35 秒`
- Pi 完成后排空上限：`180 秒`
- Pi 账本 wake 行/已送达摘要：`4 / 4`
- 逐条时间与命令取证：`/tmp/qwb-e2e-pi-devin.WcX92DPY/wake-observations.json`
- 消息 1：送达 `2026-10-04T16:07:13.974Z`；跳过行 `0`；收尾后 `False`
- 消息 2：送达 `2026-10-04T16:07:43.586Z`；跳过行 `0`；收尾后 `False`
- 消息 3：送达 `2026-10-04T16:08:13.361Z`；跳过行 `0`；收尾后 `False`
- 消息 4：送达 `2026-10-04T16:08:39.301Z`；跳过行 `0`；收尾后 `False`

- 最终 rc：`0`
- 全局文件：`/Users/rocky/.pi/agent/trust.json`
- 跑前 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`
- 跑后 SHA-256：`c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`

- 会话清理：已请求停止和删除；stop rc=0；delete rc=0
