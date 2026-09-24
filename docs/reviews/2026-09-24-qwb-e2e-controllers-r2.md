# 真实 E2E 三主控 r2

**结论**：r1 交付已独立复验通过，包括三主控脚本和三轮真实 E2E。但复验三轮转录时，发现 3 个产品问题（不是测试脚本的问题）：

1. MEDIUM：pi 扩展在主控忙的时候，会把唤醒消息越堆越多。
2. LOW：`--block` 的输出里夹带每一轮的「跳过」日志。
3. LOW：文档没写明 Claude 和 pi 派发后应当结束回合、等待叫醒。

**Standards AMEND；Spec AMEND**。审核者是 Claude Code（Opus 5.5，pane `wF2:p3`）。

## 冻结对象

- 候选 `94dafc29eb86fc4a46c472188e0db93c0e8d9f78`，代码定稿 `22e0b3fa223bbd1a4551f4d71800e1f413a2966c`，基线 `e2a3a80`。

## r1 复验（通过）

**门**

- full：在 94dafc2 导出副本上运行，FULL_RC=0，耗时 217s，664 PASS / 0 FAIL。
  - §84 是 SMOKE PASS 之前的最后一节。
  - REVIEW-IDENTITY 和 LINT 均 PASS。
  - 节标题与执行者日志一致。
- fast：rc=0。

**反转验证**

- `tests/e2e-controllers-cli.py` 在 e2a3a80 上 rc=1（`AssertionError: --controller codex|claude|pi`），在 94dafc2 上 rc=0。

**脚本审查**

- Claude 信任框处理是确定性的：先比对含项目路径在内的完整原文；按 Down 后重新读屏，确认选中了 Yes 才按 Enter；否则失败退出。
- pi 用 `--approve` 加临时 `--session-dir`；codex 用 `-c` 覆盖信任。
- 各宿主的唤醒取证方式合理，并有 `no_foreground_wake` 检查。

**Claude 轮逐条核对**（`ba6efefc….jsonl`）

1. 08:22:04 派发后结束回合。
2. 08:22:12 被 hook 叫醒，工人尚未交付，它继续等待。
3. 08:22:39 被 hook 带着 done 叫醒，接着验收、合并、收尾。
4. 08:23:07 输出 DONE。

Claude 的 hook 路径完全按设计工作。

**全局状态**

- `~/.codex/config.toml` 的哈希 `eba3ca35…` 前后不变。
- pi 的 `trust.json` 在三轮期间不变。三轮结束后，审核者按使用者要求删掉了一条过期临时条目，所以现在的哈希不同，这是审核者改的。
- `~/.claude.json` 新增了两个临时键：
  - 预检目录 `/private/tmp/qwb-controllers-preflight.17JEsLHY`；
  - 正式轮项目 `/private/tmp/qwb-e2e-claude-devin.hpl4YIaZ/project`。
  - 按规则不删除。

## 审点

### 1. MEDIUM（Standards）pi 扩展在主控忙时持续产生唤醒，过期消息排队，收尾后才逐条送达

**位置**

- `templates/pi-extensions/qwb-watch.ts` 的 `onExit`：code 2 时调用 `sendMessage`（followUp），紧接着执行 `startBlock(); // 立即重启下一轮`。

**证据**（pi 轮，`/tmp/qwb-e2e-pi-cmdc.mWh8DpXd`，E2E 配置 `QWB_REWAKE_MS=30000`）

- 票上有 6 条 wake 行：

  | 时间 | 时机 |
  |---|---|
  | 08:23:39 | 派发前 |
  | 08:24:09 | 派发前，30 秒重叫 |
  | 08:24:39 | 派发后 |
  | 08:24:43 | 工人 done 之后 |
  | 08:25:13 | 主控验收期间，30 秒重叫 |
  | 08:25:43 | 主控验收期间，30 秒重叫 |

- 08:24:30 到 08:26:37 之间，主控一直停在同一个回合里，先轮询，再验收、合并、收尾。这 6 次唤醒全部作为 followUp 排着队。
- 08:25:55 票已经改成 verified，08:26:10 已经 finish。
- 之后 08:26:37 到 08:27:58，6 条消息才逐条送达。消息里仍是 `state=running`，第一条的「最近」还是空的，因为那是工人交付之前的快照。
- 主控因此多跑了 6 个回合，每次都重新核对账本，并重复输出了 DONE。

**后果**

- 主控拿到的是与账本不符的过期信息。这一轮 glm 每次都回读账本，所以没有出错；换一个不回读账本的模型，可能据此重复派发或重复收尾。
- 白白多出空转回合，浪费 token。
- 生产默认的重叫间隔是 30 分钟，排队会少一些。但只要主控一个回合的时长超过重叫间隔，或者回合期间有别的票进展，就会发生。

**根因**

- followUp 要等主控当前回合结束才会投递。
- 扩展投递之后立刻重启 `--block`，既不等主控消费这条消息，投递时也不复核票的状态。

**修复要求**

- 主控忙的时候，不再持续产生新唤醒：同一时刻最多只有一条待投递的唤醒。
- 主控空闲时，行为保持不变。
- 推荐做法：exit 2 注入消息之后先不重启，等下一次 `turn_end` 再开下一轮。执行者也可以选等价方案，但要在报告里说明理由。

**测试要求**

- 回归测试写在现有的 `tests/pi-ext.test.mjs` 里（smoke §71）：
  - exit 2 之后、`turn_end` 之前，不再 spawn 新的 `--block`；
  - `turn_end` 之后恢复值守；
  - 主控空闲时的原有用例全部保持通过。
- 做反转验证。

### 2. LOW（Standards）`--block` 的输出夹带每一轮的「跳过」日志，三种宿主收到的唤醒消息都被灌水

**位置**

- `bin/qwb-wake.sh` 的 `collect_due` 里有 `echo "跳过：…"`，每一轮、每张进展未变的票各打一行。
- `--block` 每一轮都会调用它，stdout 累积下来后整段交给宿主：
  - Claude hook 用 `2>&1` 全量转发；
  - pi 扩展整段注入；
  - Codex 读前台命令的 stdout。

**证据**

- Claude 轮：第二条 hook 消息里有 20 行「跳过」，共 1381 字符。
- pi 轮：有 4 条消息，每条 26–27 行「跳过」，1369–1529 字符。
- Codex 轮：唤醒 stdout 同样以「跳过」行开头。
- 按生产默认（轮询间隔 2 分钟，hook 上限 2 小时）估算：一张票等 1 小时，就会攒下约 30 行；票越多越成倍增加。

**顺带问题**

- 票还没有任何状态行时，摘要显示成「最近: 。」（pi 轮 08:26:37 那条）。

**修复要求**

- `--block` 只输出最终摘要，可以附一行「另有 N 张未结项进展未变」。
- 给人看的 `--once`、循环和 `--dry-run` 日志保持不变。
- 没有状态行时，摘要里写明「尚无状态行」。

**测试要求**

- 公开 CLI 回归：多轮等待后，exit 2 的 stdout 不含逐轮的「跳过」行，并且含有摘要；`--dry-run` 和 `--once` 的输出不变。
- 做反转验证。

### 3. LOW（Spec）宿主规则没写明 Claude/pi 派发后要结束回合等待，pi 主控在回合内 sleep 轮询

**位置**

- `templates/QWBUDDY.md` §1 第 4 条，以及 `templates/host-watch-guide.md` 的「唯一值守入口」一节。
- 这两处只写了「Claude Code 用已安装的 Stop hook；Pi 用已加载的 qwb-watch.ts 扩展」，没有说出具体怎么等。

**证据**

- pi 主控（glm-5.3-flash）派发后说：「Pi 值守由 qwb-watch.ts 扩展承担（已在跑），回合内轮询账本盯工人进度」。
- 随后它执行了 `for i in $(seq 1 30); do sleep 10; …; done`，一直占着回合，间接导致了审点 1 的排队。
- Claude 主控（Opus）读的是同一份文档，却正确地结束回合，等待 hook。

**修复要求**

- 给 Claude 和 pi 写明：派发之后、或处理完一次唤醒之后，直接结束本回合，由 hook 或扩展来叫醒。
- 不要 sleep 轮询账本，也不要自己去跑 `qwb-wake.sh`。
- Codex 的规则不变。

## 本轮不处理（观察项）

- **派发后马上叫醒一次**：新票从来没有被叫醒过，所以派发后第一轮 `--block` 会立刻叫醒一次（Claude 轮 08:22:12，pi 轮 08:24:39）。这时工人还没写任何状态行，主控只是多跑一个很短的回合。
- 可以考虑派发时就记录当前指纹，这需要另开票评估，本轮不改。

## 返修任务（执行者：Codex，gpt-6-sol / high）

**起点**

- 工作目录和分支同前：Space `wHH`，分支 `qwb-e2e-controllers`，起点 `94dafc2`。
- 本报告随第一笔提交入库。

**顺序**

1. 修审点 1 和审点 2，配回归测试并做反转验证。
2. 改审点 3 的文档。
3. 在代码定稿的 SHA 上串行重跑三轮真实 E2E：codex+devin、claude+devin、pi+cmdc。三种宿主都要重跑，因为审点 2 改的是它们共用的 `--block` 输出。

**E2E 报告要增加的内容**

- 每一轮都记录：
  - 主控收到的唤醒消息数；
  - 每条消息里的「跳过」行数；
  - 收尾之后才送达的唤醒数；
  - 主控在回合内执行的轮询命令数（比如 `sleep` 循环）。
- 其中两条作为断言：
  - 唤醒消息里的逐轮「跳过」行数为 0，三种主控都要满足；
  - pi 轮收尾之后才送达的过期唤醒不超过 1 条。
- 「回合内轮询命令数」只作观察项，不作为硬门。glm 如果仍然轮询，如实记为这个模型的结果。

**其余要求同 r1**

- 失败分类、做法和约束都与 r1 相同。
- fast/full 在最终 SHA 上跑。
- E2E 之后的提交只允许改 `docs/reviews/`。

**报告**

- 写 `docs/reviews/2026-09-24-qwb-e2e-controllers-r2-execution.md`，与改动一起提交。
- 最后单独输出一行 `QWB_E2E_CONTROLLERS_R2 DONE <完整SHA>` 或 `QWB_E2E_CONTROLLERS_R2 BLOCKED <原因>`。

**REVIEW_QWB_E2E_CONTROLLERS_R1 AMEND**
