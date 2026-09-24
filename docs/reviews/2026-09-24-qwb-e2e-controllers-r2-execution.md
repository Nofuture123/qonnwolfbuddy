# QWB 三主控真实 E2E r2 执行记录

- 起点：`94dafc29eb86fc4a46c472188e0db93c0e8d9f78`，分支 `qwb-e2e-controllers`，Space `wHH`。r2 任务书随首笔提交 `081e6cef66568c6497fd00967ac24ef76b3811c1` 入库。
- 环境：2026-09-24，macOS，Herdr 0.9.1；前台执行 tab `wHH:tA`。三宿主使用隔离临时 Git 项目和 named session，串行运行；没有 push、合并本分支或安装到生产项目。
- 代码和模板最终候选：`e6bb460b8fd849bcd3b367d5cbb4bbbb0ba2d2ec`。其后只提交本 `docs/reviews/` 报告。

## 改动及原因

1. Pi 扩展 `templates/pi-extensions/qwb-watch.ts`：exit 2 注入 followUp 后暂停值守，最多保留一条待投递摘要。首次实现以 `turn_end` 重启，单元测试通过，但真实 Pi 证明该事件在一次忙碌运行内反复触发。修复提交 `d682ac6cdf804bec0bab12cd8637a6b6262b2ffe` 改为在 `agent_settled` 后重启，`agent_start` 将运行标为忙碌；晚获锁、exit 0 后探测及探测返回 124 时也只在空闲启动。Pi 0.87.1 的 `dist/core/extensions/types.d.ts` 第 625、1001 行声明了 `agent_settled` 事件及订阅重载；`docs/extensions.md` 说明它是 Pi 不再自动继续的边界。`templates/host-watch-guide.md` 的旧 `turn_end` 描述同步改为 `agent_settled`（提交 `e6bb460`）。历史 `docs/DECISIONS.md` 中的旧事件描述以本轮实测和当前模板为准。
2. `bin/qwb-wake.sh`：`--block` 只输出最终摘要，不夹带各轮「跳过」日志；`--once` 与 `--dry-run` 保留原日志。空状态显示「尚无状态行」。公开 CLI 回归在 `tests/wake-block-output.sh`，smoke §85 调用。
3. `templates/QWBUDDY.md`、`templates/host-watch-guide.md`：Claude/Pi 派发或处理唤醒后结束回合，由 hook/扩展再叫醒，不运行 sleep 轮询或自行调用 `qwb-wake.sh`。Codex 前台值守规则未变。
4. `tests/e2e-real.py`：从各宿主会话记录逐条统计唤醒、跳过行、成功 finish 之后才送达的消息及回合内 sleep 命令。三宿主逐条跳过行必须为 0，Pi 收尾后旧消息不得超过 1。Pi 还核对票据 `wake:` 行与实际送达数，并在首次 DONE 后观察 35 秒无新消息、最多 180 秒。结果保留于每轮 `wake-observations.json`。
5. 使用者明确禁止 Codex fast 模式：Codex 主控启动参数包含 `-c service_tier="default"`；启动核对 TUI 的模型与状态行，发现 `fast` 即失败。E2E 报告记录该 service_tier。本轮 Codex TUI 核对通过，`~/.codex/config.toml` 前后 SHA-256 相同。

## 红绿、反转和审核

- 修复前 `node tests/pi-ext.test.mjs` rc=1，首次失败在“turn_end 前不重启 --block”；`bash tests/wake-block-output.sh` rc=1，exit 2 stdout 含两行「跳过」。修复后 Pi 扩展 17 项与公开 CLI 回归均 rc=0。两份旧源码分别反转运行新测试，均 rc=1；原始日志在 `/tmp/qwb-r2-reversal.9cItxd8D/{pi,wake}-{red,green}.log`。
- 真机 Pi 首轮在 `081e6ce` 上 rc=1：10 条唤醒中 9 条在成功 `finish --merged` 后送达，明确触发 `pi_stale_wake_limit=FAIL`。报告 `/tmp/qwb-e2e-controllers-r2-pi-081e6ce.md`，转录 `/tmp/qwb-e2e-pi-cmdc.Z32R3ywR/controller-transcript.txt`。本机 Pi 文档确认 `turn_end` 只是一次模型响应及工具调用结束，而 followUp 要等运行结束。
- 新测试模拟忙碌运行内四次 `turn_end`，要求不新起 `--block`、只投递一条 followUp，直到 `agent_settled` 才恢复；晚获锁和 exit 0 探测也覆盖此边界。旧版扩展配兼容测试适配器时 rc=1，精确失败在“忙碌运行内多次 turn_end 不得重启值守”；隔离样本在 `/tmp/qwb-r2-pi-settled-evidence/`。修复版 `node tests/pi-ext.test.mjs` 为 18 passed、rc=0；`python3 -B tests/e2e-controllers-cli.py`、`bash tests/wake-block-output.sh`、`git diff --check` 均 rc=0。
- 提交 `081e6ce` 前在可见 Herdr tab `wHH:t8/t9` 进行了 Standards/Spec 双轴审核，每轮不超过三审点；投递失败重试、finish 时间边界、Pi 排空上限等问题已修，最终两轴均 0 finding。针对真机失败的后续修复由上述反转测试和 Pi 实机复跑验证。

## 前台真实 E2E 与逐条观察

下表为原始命令及退出码；Codex/Claude 在 `081e6ce` 上已通过。之后只改 Pi 扩展与 Pi 指南，按失败分类重跑受影响的 Pi 轮。各轮完整报告均保留在 `/tmp`，表中 SHA-256 用于锁定报告字节。

| 候选与原始命令 | 主控/工人 | 唤醒数 | 每条跳过行 | 收尾后送达 | sleep 轮询 | 报告 SHA-256 | rc |
| --- | --- | ---: | --- | ---: | ---: | --- | ---: |
| `081e6ce` `bash tests/e2e-real.sh --controller codex --worker devin --report /tmp/qwb-e2e-controllers-r2-codex-081e6ce.md` | codex `gpt-6-luna/max` + devin `swe-2-max` | 1 | `[0]` | 0 | 0 | `f3e7901f661d57bcb8d3211e7150eff460d347dd12eeda31ee233e519b36e049` | 0 |
| `081e6ce` `bash tests/e2e-real.sh --controller claude --worker devin --report /tmp/qwb-e2e-controllers-r2-claude-081e6ce.md` | Claude `opus/high` + devin `swe-2-max` | 4 | `[0,0,0,0]` | 0 | 0 | `d7f77e287b2c7f356ce789cb551a9cdb8f1d6906802b90ef54d44decb782a2ec` | 0 |
| `081e6ce` `bash tests/e2e-real.sh --controller pi --worker cmdc --report /tmp/qwb-e2e-controllers-r2-pi-081e6ce.md` | Pi `zai-coding-cn/glm-5.3-flash/high` + cmdc `deepseek/deepseek-v4-flash` | 10 | 十条均 0 | 9 | 0 | `9ebdb26dfd8d4bbd2b2a11922fd915b6ec12fc2e91bebe106bed296c17677114` | 1 |
| `d682ac6` `bash tests/e2e-real.sh --controller pi --worker cmdc --report /tmp/qwb-e2e-controllers-r2-pi-d682ac6.md` | 同上 | 1 | `[0]` | 0 | 0 | `9a93a7d6ca84b1acaeb9a9ea4bca7addddb190ed585e4f86cb4d82c02097c50c` | 0 |
| `e6bb460` `bash tests/e2e-real.sh --controller pi --worker cmdc --report /tmp/qwb-e2e-controllers-r2-pi-e6bb460.md` | 同上 | 2 | `[0,0]` | 0 | 0 | `a7cbc23ea16be19ea595bc3226e383d6752bc4d31fb970a3da7ad5f97af0166c` | 0 |

最终 Pi 轮票据 `wake:`/送达摘要为 `2/2`，`pi_wake_queue_drained`、`pi_stale_wake_limit`、`wake_skip_lines_zero` 均 PASS；35 秒静默排空后结束。转录与逐条取证分别在 `/tmp/qwb-e2e-pi-cmdc.OepvjUIo/controller-transcript.txt`、`/tmp/qwb-e2e-pi-cmdc.OepvjUIo/wake-observations.json`。Codex 轮启动参数含 `service_tier="default"`，TUI 模型/状态行均无 `fast`；其报告对应转录 `/tmp/qwb-e2e-codex-devin.m2hzyKfD/controller-transcript.txt`。Claude 转录在 `/tmp/qwb-e2e-claude-devin.SQ57YBPd/controller-transcript.txt`。

三种成功轮次的内容、账本、工人 Space、Git/Space 清理、宿主唤醒与默认全局状态断言均 PASS；named session 的 stop/delete 原始 rc 均为 0。Pi 最终轮 `~/.pi/agent/trust.json` 前后 SHA-256 均为 `c79b4e4d0be9fd9cab57334bd622d7e122a0c5e8d0d32284addb85703f43e0ac`；Codex 配置前后均为 `eba3ca35ed66eca2d506560582ebcc611b2106ca35c97c2cc795ffa7b676efb8`。Claude 自身在 `~/.claude.json` 增加临时项目键，harness 未删改该键。

## 边界与后验门

真实 E2E 仅覆盖这些指定模型和隔离项目；未安装生产项目，也未验证其他模型覆盖值。`docs/DECISIONS.md` 的旧 Pi `turn_end` 记述是历史设计，当前行为以本报告、扩展和宿主指南为准。fast/full 在本报告提交后的最终 SHA 上后验运行，结果以原始命令和退出码单独交付。
