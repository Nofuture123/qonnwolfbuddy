# QWB 三主控真实 E2E 执行记录

- 起点：`e2a3a80925ce47ba4dafd2d7f4c61628501b9adb`；冻结代码候选：`22e0b3fa223bbd1a4551f4d71800e1f413a2966c`。
- 环境：2026-09-24，macOS，Herdr 0.9.1，Space `wHH`；三轮在新 tab `wHH:t6` 前台串行启动，各自使用隔离 `/tmp` Git 项目与 named session。未 push、未合并本分支、未安装到生产项目。
- 起点 WIP：仅任务书 `docs/reviews/2026-09-24-qwb-e2e-controllers-r1.md` 未跟踪；它已随首笔提交入库。

## 先实测的三项

预检 TUI 与 Herdr `pane read/get` 的原始工具输出留在本执行者会话 `/Users/rocky/.codex/sessions/2026/09/24/rollout-2026-09-24T09-52-47-01a0d267-1c50-7e63-9d95-7d3a694093c3.jsonl`；预检项目目录本身不包含终端截录。以下信任框和资源列表是当时的现场输出，hook 与扩展后续结果另可在临时项目/宿主 JSONL 复核。

1. Claude Code 2.1.281：在 `/tmp/qwb-controllers-preflight.17JEsLHY` 交互启动后，信任框原文含 `Accessing workspace:`、`Quick safety check: Is this a project you created or one you trust?`、`No, exit`、`Yes, I trust this folder`、`Enter to confirm · Esc to cancel`。默认选中 No；选择 Yes 后仅按一次 Enter，TUI 显示 `Opus 5.5 with high effort`，Herdr pane `wHH:p2` 识别 `agent=claude`。隔离项目安装的 Stop hook 在主控获得锁后，主控转录出现 `Stop hook feedback` 和账本摘要；当次项目 hook 即生效。这个接受动作由 Claude Code 自己写入 `~/.claude.json`，harness 没有改写该文件。
2. pi 0.87.1：在 `/tmp/qwb-controllers-pi.rq330owp` 使用 `--approve --provider zai-coding-cn --model glm-5.3-flash --thinking high --session-dir <临时目录>` 交互启动；启动资源列表明确含 `qwb-watch.ts`，Herdr pane `wHH:p3` 识别 `agent=pi`。获锁后 `.watch` 为 `kind=pi-ext`，会话 JSONL 出现带 `[qwb-wake]` 的 user followUp。`~/.pi/agent/trust.json` 前后 SHA-256 同为 `01f0632b19e3ab94d60256ba5a792c8a413148b8b35ea7127660720029404811`。
3. 两个预检 tab 均已关闭；这三项都是实机交互观察，不能由 `--help` 单独替代。

## 代码与文档

- `tests/e2e-real.sh` 新增 `--controller codex|claude|pi`，按宿主选择默认模型、推理档、CLI 版本与启动参数；先打印实际主控、模型、工人和候选 SHA。只启动交互 TUI。
- `tests/e2e-real.py` 为 Codex 保留本次 `-c` 信任覆盖并校验全局配置字节；pi 用 `--approve` 和临时 `--session-dir` 并校验 trust.json 字节；Claude 只识别确定的信任框后选择 Yes，由 Claude 自己写 `~/.claude.json`，从同一份跑前字节快照报告 projects 新键。主控提示改为宿主无关，idle 无标记不判完成。
- 宿主唤醒断言分别读 Codex 会话的已执行 shell 命令及含 `done:` 的 stdout、Claude JSONL 的 Stop hook 投递、pi JSONL 的 `[qwb-wake]` followUp；Claude/pi 同时检查主控未前台运行 `qwb-wake.sh --block`。原有账本、目标文件、worktree Space、清理与 devin 默认名字断言保留。
- `--help` 与 `docs/DECISIONS.md` §三十九补充三宿主默认值、全局状态规则和生产安装前须用实际主控宿主跑一遍。`tests/smoke.sh` 的第 84 节调用公开 CLI 回归。

## 红绿与审核

- 红：新增 `tests/e2e-controllers-cli.py` 后首次运行 `python3 -B tests/e2e-controllers-cli.py`，rc=1，`AssertionError: --controller codex|claude|pi`，证明原入口不支持要求的公开参数。
- 绿：实现后同命令 rc=0，输出 `E2E CONTROLLERS CLI PASS: help declarations, invalid controller`；`bash -n tests/e2e-real.sh tests/smoke.sh`、Python AST 解析、`git diff --check` 均 rc=0。
- 提交前 Herdr 双轴审核：Standards 起初指出 Codex 唤醒伪阳性与 CLI 测试宣称过宽；Spec 起初指出同一伪阳性与 Claude 基线并发读取间隙。修复后两轴复核通过；Spec 的 `echo` 反例再次促使限定外层 shell argv，复核已关闭。审核 tab `wHH:t4`、`wHH:t5` 已关闭，均未修改文件。

## 冻结候选上的真实 E2E

| 轮次与原始命令 | 主控/工人 CLI 与模型 | 报告 SHA-256 | 原始 rc |
| --- | --- | --- | --- |
| `bash tests/e2e-real.sh --controller codex --worker devin --report /tmp/qwb-e2e-controllers-codex-22e0b3f.md` | codex-cli 0.156.1 `gpt-6-luna/max`；devin 3000.11.3 `swe-2-max` | `f4309c3a9d7d5140d7edce68223e8555395719f14d8a4a7973ce806479dcff9b` | 0 |
| `bash tests/e2e-real.sh --controller claude --worker devin --report /tmp/qwb-e2e-controllers-claude-22e0b3f.md` | Claude Code 2.1.281 `opus/high`（TUI 显示 Opus 5.5）；devin 3000.11.3 `swe-2-max` | `bc9a4e92414c6cc2c328ac70861a6e225c35ceb6585889d38bb57a228a59f87a` | 0 |
| `bash tests/e2e-real.sh --controller pi --worker cmdc --report /tmp/qwb-e2e-controllers-pi-22e0b3f.md` | pi 0.87.1 `zai-coding-cn/glm-5.3-flash/high`；cmdc 1.65.0 `deepseek/deepseek-v4-flash` | `8299cf97af2ade2adc57f1d40f830bd37570cfef1208c3f5e51d97ef9109f802` | 0 |

三份报告均保留在 `/tmp/qwb-e2e-controllers-{codex,claude,pi}-22e0b3f.md`；报告逐项断言全部 PASS，包含各自 `host_wake`、`default_untouched`、内容与 Git/Space 清理。Codex/pi 的全局文件字节比较 PASS；Claude 的 `no_foreground_wake` 与 pi 的 `no_foreground_wake` 均 PASS。三个 named session 的 stop/delete 原始 rc 均为 0，临时项目与转录目录保留供复核。

宿主证据索引：

- Codex：`/tmp/qwb-e2e-codex-devin.d6b1uZiK/controller-transcript.txt` 与报告所列 Codex JSONL；JSONL 中主控实际执行 `bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000`，结果 rc=2，stdout 含工人 `done:`。`~/.codex/config.toml` 前后 SHA-256 均为 `eba3ca35ed66eca2d506560582ebcc611b2106ca35c97c2cc795ffa7b676efb8`。
- Claude：`/tmp/qwb-e2e-claude-devin.hpl4YIaZ/controller-transcript.txt` 与报告所列 Claude JSONL；Stop hook 投递的 user notification 含工人 `done:`。`~/.claude.json` 的 `projects` 新增键仅 `/private/tmp/qwb-e2e-claude-devin.hpl4YIaZ/project`；harness 没有删除或预置信任项。
- pi：`/tmp/qwb-e2e-pi-cmdc.mWh8DpXd/controller-transcript.txt` 与 `pi-sessions/*.jsonl`；JSONL 中带 `[qwb-wake]` 的 user followUp 含工人 `done:`。`~/.pi/agent/trust.json` 前后 SHA-256 均为 `01f0632b19e3ab94d60256ba5a792c8a413148b8b35ea7127660720029404811`。

pi 模型在扩展运行期间也主动轮询了账本；followUp 证据证明正式扩展入口把 `done:` 投进会话，但这轮验收行动本身并非只能由该 followUp 触发。cmdc 曾在隔离 worktree 留下未跟踪 `.commandcode/`，pi 主控确认内容后清理，最终 `git_cleanup` 与 `space_cleanup` 为 PASS。

## 边界与后验门

- 三轮仅覆盖临时 Git 项目及指定主控/工人组合；未在 qonnwolf-sites 等生产项目安装或运行，也未测试其他模型覆盖值。
- 最终提交的 fast/full 在本执行报告提交后对最终 SHA 后验运行；此处不提前记作 PASS。E2E 之后的源码和测试没有改动。
