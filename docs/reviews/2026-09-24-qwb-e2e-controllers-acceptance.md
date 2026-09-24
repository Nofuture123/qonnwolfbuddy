# 三主控真实 E2E 交付与验收

记录时间：2026-09-24T10:06:24+00:00。

分支 `qwb-e2e-controllers`（基线 e2a3a80）经过 r1–r3 三轮独立审核与返修，最终版本 `b3941d3bef1fd150fc13823e274409eeda06a6bb` 已快进合并进本地 main。

本文件记录时的状态：

- 尚未 push。
- 未安装到生产项目。qonnwolf-sites 由使用者自己安装。
- 主仓中预存的 `docs/plans/` 草案不纳入本次提交。

分工：

- 执行：Codex（gpt-6-sol / high，`service_tier="default"`，Herdr pane `wHH:p1`）。
- 独立审核：Claude Code（Opus 5.5，pane `wF2:p3`）。
- 真实 E2E：
  - 主控：Codex `gpt-6-luna/max`、Claude Code `opus/high`、pi `zai-coding-cn/glm-5.3-flash/high`。
  - 工人：devin `swe-2-max`、cmdc `deepseek/deepseek-v4-flash`。

## 交付了什么

- **三种主控都能跑真实 E2E**：Codex、Claude Code、pi。以前只测过 Codex。现在 Claude 的 Stop hook 和 pi 的扩展也在真实闭环里跑过了。
- **真机跑出 3 个产品问题，都已修好**：

  | 问题 | 修复前 | 修复后 |
  |---|---|---|
  | pi 主控忙的时候，扩展不停产生唤醒，排队到收尾后才逐条送达 | 10 条唤醒里 9 条在收尾后送达 | 等 pi 真正空下来（`agent_settled`）才重新值守，最后一轮收尾后 0 条 |
  | 三种宿主收到的唤醒里夹带逐轮「跳过」日志 | 一条最多 27 行 | 每条 0 行 |
  | 文档没写 Claude/pi 派发后要结束回合，pi 主控在回合里 sleep 轮询 | pi 主控 `for … sleep 10` 轮询 | 写明规则后，最后一轮 0 次轮询 |

- **E2E 里的 Codex 主控不许用 fast**：启动参数固定 `service_tier="default"`，TUI 一出现 fast 就判失败。

## 提交

- 代码和模板定稿为 `e6bb460`。
- 其后的提交只改文档：`git diff --stat e6bb460 b3941d3` 只列出 `README.md`、`README.zh.md`、`docs/DECISIONS.md` 和 `docs/reviews/` 下的文件。

| 提交 | 内容 |
|---|---|
| `22e0b3f` | r1：`tests/e2e-real.sh` 增加 `--controller codex\|claude\|pi` |
| `94dafc2` | r1 执行报告 |
| `081e6ce` | r2：`--block` 只输出摘要；pi 扩展投递后暂停（首版等 `turn_end`）；写明宿主结束回合的规则；E2E 增加唤醒取证和禁用 fast |
| `d682ac6` | r2：pi 扩展改为 `agent_settled` 后重启（真机首轮失败后修） |
| `e6bb460` | r2：宿主指南同步（代码和模板定稿） |
| `c289b83` | r2 执行报告 |
| `4a4cb6b` | r3：README 中英文，以及 DECISIONS §四十一 |
| `b3941d3` | r3 执行报告 |

## 改动文件（19 个，+1236/−129）

- **bin/**：`qwb-wake.sh`。
- **templates/**：`QWBUDDY.md`、`host-watch-guide.md`、`pi-extensions/qwb-watch.ts`。
- **tests/**：
  - 修改：`e2e-real.sh`、`e2e-real.py`、`pi-ext.test.mjs`、`smoke.sh`（新增 §84、§85）。
  - 新增：`e2e-controllers-cli.py`、`wake-block-output.sh`。
- **docs/**：`DECISIONS.md`（更新 §三十九，新增 §四十一），以及 r1–r3 的任务书和执行报告。
- **根目录**：`README.md`、`README.zh.md`。

## 各轮审点

- **[r1](2026-09-24-qwb-e2e-controllers-r1.md)**：任务书，[执行报告](2026-09-24-qwb-e2e-controllers-execution.md)。
  - 先实测了三件事：Claude 信任框的原文、pi `--approve` 能加载项目扩展、Herdr 能在 named session 里识别这两种宿主。
  - 然后扩展了 harness，在 22e0b3f 上跑三轮，rc 全是 0。
- **[r2](2026-09-24-qwb-e2e-controllers-r2.md)**（1 MEDIUM + 2 LOW），[执行报告](2026-09-24-qwb-e2e-controllers-r2-execution.md)。
  - 复验 r1 时从三份转录里发现 3 个问题：pi 扩展堆积唤醒、`--block` 输出夹带「跳过」日志、Claude/pi 派发后的做法没写明。
- **[r3](2026-09-24-qwb-e2e-controllers-r3.md)**（2 LOW，都是文档），[执行报告](2026-09-24-qwb-e2e-controllers-r3-execution.md)。
  - README 中英文还写着 `turn_end`；DECISIONS 没记本次的设计变化。

## 门与收据

**执行者**（最终 SHA b3941d3）

- `/tmp/qwb-e2e-controllers-r3-{fast,full}.md`：门退出码都是 0，运行前后工作区都干净。

**审核者独立复跑**

- b3941d3 导出副本：
  - full：FULL_RC=0，耗时 218s，665 PASS / 0 FAIL。§85 是 SMOKE PASS 之前的最后一节；REVIEW-IDENTITY PASS，LINT PASS。
  - fast：rc=0。
- c289b83 导出副本：full 耗时 313s，665 PASS / 0 FAIL；fast rc=0。
- 94dafc2（r1）：full 664 PASS / 0 FAIL。

**反转验证**

| 测试 | 旧版本 | 新版本 | 做的人 |
|---|---|---|---|
| `tests/e2e-controllers-cli.py` | e2a3a80 上 rc=1 | 94dafc2 上 rc=0 | 审核者 |
| `tests/pi-ext.test.mjs` | 081e6ce 旧核心（用适配器把 `onAgentSettled` 接到旧的 `onTurnEnd`）rc=1，第一个失败是「忙碌运行内多次 turn_end 不得重启值守」 | 18 passed | 审核者 |
| `tests/wake-block-output.sh` | 94dafc2 的 `qwb-wake.sh` 上 rc=1，`--block` 的 stdout 带两行「跳过」 | rc=0 | 审核者（执行者也做过，日志在 `/tmp/qwb-r2-reversal.9cItxd8D/`） |

**对照 pi 0.87.1 源码**

- **agent_settled 一定会发出。**
  - 所有运行都走 `_runAgentPrompt`（`dist/core/agent-session.js:1078-1104`），它在 `finally` 里发出 `agent_settled`，中止和报错也不例外。
  - 因此值守不会卡在「忙」上。
- **sendUserMessage 返回 void。**
  - 扩展拿到的 `sendUserMessage` 没有返回值（`dist/core/extensions/loader.js:284-287`），投递确认是同步完成的。
  - 所以不会出现「确认晚于 settled 到达，导致值守停摆」的时序。

## 真实 E2E

**r1**（22e0b3f）

- 三轮 rc 都是 0，断言全部 PASS：
  - `/tmp/qwb-e2e-controllers-codex-22e0b3f.md`
  - `/tmp/qwb-e2e-controllers-claude-22e0b3f.md`
  - `/tmp/qwb-e2e-controllers-pi-22e0b3f.md`
- 那时还没有唤醒计数。r2 的 3 个问题，是审核者逐条读这三份转录才发现的。

**r2**

| 候选 | 主控 + 工人 | 唤醒数 | 每条跳过行 | 收尾后送达 | 回合内轮询 | rc |
|---|---|---:|---|---:|---:|---:|
| 081e6ce | codex + devin | 1 | `[0]` | 0 | 0 | 0 |
| 081e6ce | claude + devin | 4 | `[0,0,0,0]` | 0 | 0 | 0 |
| 081e6ce | pi + cmdc | 10 | 均 0 | 9 | 0 | 1 |
| d682ac6 | pi + cmdc | 1 | `[0]` | 0 | 0 | 0 |
| e6bb460 | pi + cmdc | 2 | `[0,0]` | 0 | 0 | 0 |

- 五份报告的 SHA-256 都与 r2 执行报告一致。
- 审核者逐条核对了最后一轮 pi 的会话 JSONL（`/tmp/qwb-e2e-pi-cmdc.OepvjUIo`）：
  - 09:39:00 第一次叫醒，内容是「尚无状态行」；
  - 09:39:20 带着 done 叫醒；
  - finish 在 09:40:59，此后没有唤醒，也没有轮询命令。

**全局状态**

- `~/.codex/config.toml`：SHA-256 `eba3ca35…` 在各轮前后和验收时都没变。
- `~/.pi/agent/trust.json`：
  - r1 三轮前后都是 `01f0632b…`。
  - 之后审核者按使用者要求删掉一条过期临时条目，哈希变为 `c79b4e4d…`。
  - r2 各 pi 轮前后和验收时都是 `c79b4e4d…`。
- `~/.claude.json`：
  - 本分支让 Claude Code 自己写入了 3 个临时项目键：
    - `/private/tmp/qwb-controllers-preflight.17JEsLHY`
    - `/private/tmp/qwb-e2e-claude-devin.hpl4YIaZ/project`
    - `/private/tmp/qwb-e2e-claude-devin.SQ57YBPd/project`
  - 另有 `/private/tmp/qwb-e2e-cc` 和两个 commandcode scratchpad 键，比本分支早，不属于它。
  - harness 按规则不删改这个文件。

## 流程记录

- **r2 推荐的做法是错的。**
  - 审核者在 r2 任务书里推荐「等下一次 `turn_end` 再重启」，没有先读 pi 文档。
  - 执行者照做，单元测试全过，真机却失败了。
  - 真实 E2E 抓住了这个错，执行者改用 `agent_settled`。
  - 教训已追加到 `tasks/lessons/定级与放行前跑通真实链路.md`。
- **r3 执行记录先写了结果，后跑的门。**
  - 执行者在 11:57:21 把「原始退出码 **0**」写进记录并提交，11:57:34 才开始跑门。
  - 起因是审核者的 r3 任务书要求把门退出码写进执行记录，而这份记录本身就在最终 SHA 里。
  - 门后来的结果确实是 0，审核者独立复跑也通过了。
  - 教训：`tasks/lessons/门结果不能预写进被测提交.md`。

## 未覆盖

- **没有安装到 qonnwolf-sites。** 按 DECISIONS §三十九，装进生产项目之前，要用该项目实际用的主控宿主跑一遍。
- **真实 E2E 只覆盖三种组合**：codex+devin、claude+devin、pi+cmdc。
  - 其他组合、其他模型取值，以及 pi-kimi 工人都没有跑。
- **派发后会马上叫醒一次**：新票从没被叫醒过，所以派发后立即叫醒一次。这是观察项，代价是主控多跑一个短回合。另开票评估是否在派发时就记录指纹。
- **以下情况没在真机测过**：
  - Claude hook 等满 2 小时上限（`timeout: 7200`）之后的续等；
  - Herdr 服务重启后的恢复。
- **历史票和 DECISIONS §三十二至§三十四**里仍有 `turn_end` 的描述。它们作为历史记录保留，§四十一已声明取代。

## 待使用者确认

- push main：本分支 8 个提交，加上本验收提交。
- 关闭 Space `wHH`（只有 `wHH:p1`，是 Codex 执行者会话，已空闲），删除 worktree `/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-e2e-controllers` 和分支 `qwb-e2e-controllers`。
- 可选：等所有 Claude 会话都关掉以后，清理 `~/.claude.json` 里上面列出的 `/private/tmp` 项目键。

## 收尾结果（2026-09-24T10:08:43+00:00，使用者确认后执行）

- **推送**
  - main 已推送：`e2a3a80..ad5a421`，共 9 个提交。
  - `git ls-remote origin refs/heads/main` 返回 ad5a421。
  - 本节是另一个文档提交，随后单独推送。
- **Space 与分支**
  - 已执行 `herdr worktree remove --workspace wHH`，结果为 `worktree_removed`、`forced:false`。Space 已关闭，worktree 目录已删除。
  - 分支已用 `git branch -d` 删除，删除前指向 b3941d3。没有残留的 `branch.qwb-e2e-controllers.*` 配置，`git worktree list` 只剩主仓。
- **临时文件**
  - 审核者自己的导出副本和反转副本都在会话 scratchpad 里，已删除。
  - 执行者留在 `/tmp` 的 E2E 报告、转录和临时项目是本文引用的证据，没有删。
- **没有执行的**
  - 使用者没有选择删除 `~/.claude/settings.json` 里的两条明文密码放行规则，所以没动。
  - `~/.claude.json` 的临时项目键仍然保留，要等所有 Claude 会话都关掉以后再清。
