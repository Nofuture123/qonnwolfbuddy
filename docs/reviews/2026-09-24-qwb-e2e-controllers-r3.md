# 真实 E2E 三主控 r3

**结论**：r2 的代码、测试和真机证据都已独立复验通过，pi 扩展不会再在主控忙的时候堆积唤醒。只剩两处文档还写着旧行为，都是 LOW。修完即可合并，不用重跑真实 E2E。

**Standards PASS；Spec AMEND（仅文档）**。审核者是 Claude Code（Opus 5.5，pane `wF2:p3`）。

## 冻结对象

- 候选 `c289b831f270369a348271a9ba24cd3e2b2d2993`，代码和模板定稿 `e6bb460`，基线 `e2a3a80`。

## r2 复验（通过）

**门**

- full 在 c289b83 的导出副本上跑：FULL_RC=0，耗时 313s，665 PASS / 0 FAIL。
  - §85 是 SMOKE PASS 之前的最后一节。
  - REVIEW-IDENTITY 和 LINT 均 PASS。
- fast：rc=0。
- 执行者的 `/tmp/qwb-e2e-controllers-r2-{fast,full}-c289b83.md`：门退出码都是 0，运行前后工作区都干净。

**反转验证（审核者独立做）**

- 取 081e6ce 的旧扩展核心，用适配器把 `onAgentSettled` 接到旧的 `onTurnEnd`，`onAgentStart` 设为空操作，然后跑新的 `tests/pi-ext.test.mjs`：rc=1。第一个失败正是「忙碌运行内多次 turn_end 不得重启值守」。
- 换成 c289b83 的核心：18 passed，rc=0。

**对照 pi 0.87.1 源码**

- **agent_settled 一定会发出。**
  - 所有运行都走 `_runAgentPrompt`（`dist/core/agent-session.js:1078`），它的 `finally` 里调用 `_emitAgentSettled`，中止和报错也不例外。
  - 因此 `agentIdle` 不会卡在「忙」上。
- **没有「值守停摆」的时序。**
  - 扩展拿到的 `sendUserMessage` 返回 void（`dist/core/extensions/loader.js:284-287`），所以 `accepted()` 是同步执行的。
  - 这就不会出现「投递回调晚于 agent_settled 到达，导致值守停摆」的情况。
- **类型声明**：`types.d.ts` 第 625 行声明了 `agent_settled` 事件，第 1001 行声明了订阅重载。

**最后一轮 pi**（`/tmp/qwb-e2e-pi-cmdc.OepvjUIo`）

- 会话 JSONL 里有 2 条 `[qwb-wake]`：
  - 09:39:00，派发后第一次叫醒，显示「尚无状态行」；
  - 09:39:20，带着工人的 done。
- finish 在 09:40:59，此后没有任何唤醒，也没有轮询命令。

**报告哈希与改动范围**

- 五份 E2E 报告的 SHA-256 都与执行记录一致。
- Codex 轮的启动参数含 `service_tier="default"`，harness 检查了 TUI 的模型行和状态行，里面没有 fast。
- 改动范围：
  - `e6bb460..c289b83` 只改了 `docs/reviews/`。
  - `081e6ce..e6bb460` 只改了 pi 扩展、pi 单元测试、smoke 计数，以及指南的 Pi 段。所以 Codex 和 Claude 两轮在 081e6ce 上的证据仍然有效。

## 审点

### 1. LOW（Spec）README 中英文仍写「晚获锁在 turn_end 启动」

**位置**

- `README.md:45`：`… or a later turn_end after acquiring the controller lock starts the watch`
- `README.zh.md:45`：`晚获主控锁会在后续 turn_end 启动`

**问题**

- 扩展现在只订阅 `agent_settled`，不再订阅 `turn_end`。
- `templates/host-watch-guide.md` 已经同步改了，README 没跟上。

**修复**

- 两处都改成「晚获锁后，在 `agent_settled`（Pi 不再自动继续）时启动」。
- 顺带写明：exit 2 投递之后，也要等到 `agent_settled` 才重启值守。
- 中英文意思一致，其余句子不动。

### 2. LOW（Spec）DECISIONS 没记这次的设计变化，旧节写的与现在行为矛盾

**位置**

- `docs/DECISIONS.md` 的三节：
  - §三十二：「exit 2 → … 立即重启下一轮」，以及「exit 0 → … `turn_end` 用 `--block --max-ms 1` 探测」。
  - §三十三「Pi 探测」：「`turn_end` 的探测 … 立即恢复常规 `--block`」。
  - §三十四：「晚获主控锁后的 `turn_end` 启动一个值守」。

**问题**

- 本文件是决策日志，按惯例不改写旧节，而是追加新节并声明取代关系（先例是 §三十七、§三十九）。
- r2 改了行为，却没有追加。

**修复：追加「四十一、主控忙时不堆积唤醒（2026-09-24）」**，写四点：

1. **Pi 扩展**
   - exit 2 投递 followUp 之后先暂停，等 `agent_settled` 再重启 `--block`。同一时刻最多一条待投递的唤醒。
   - 以下几种启动也只在空闲时进行：晚获锁、exit 0 之后的探测、探测返回 124 之后的恢复。
   - `turn_end` 是一次模型请求的边界，同一次运行里会出现多次，所以不再订阅。
   - 依据：
     - 081e6ce 的真机轮：10 条唤醒里有 9 条在 finish 之后才送达；
     - pi 0.87.1 的 `types.d.ts` 和 `docs/extensions.md`。
   - 本条取代 §三十二、§三十三、§三十四中对应的 `turn_end` 描述。
2. **`qwb-wake.sh --block`**：只输出最终摘要，不再夹带逐轮的「跳过」行；票还没有状态行时写「尚无状态行」。`--once` 和 `--dry-run` 的输出不变。
3. **Claude Code 和 Pi 的主控规则**：派发之后，或处理完一次唤醒之后，直接结束本回合，由 hook 或扩展来叫醒；不要 sleep 轮询，也不要自己运行 `qwb-wake.sh`。Codex 的前台值守规则不变。
4. **真实 E2E**：Codex 主控固定 `service_tier="default"`，TUI 的模型行或状态行一出现 fast 就判失败。这是使用者的明令。

**可选**：在上面三节对应的句尾加上「（已由 §四十一 取代）」，其他文字不改。

## 本轮不处理（观察项）

1. **派发后马上叫醒一次**：与 r2 的观察项相同，本轮真机又出现了一次（09:39:00「尚无状态行」）。代价只是主控多跑一个短回合，仍按 r2 的结论另开票评估。
2. **工人把换行写进了 done 行**
   - 工人 cmdc（deepseek）写 done 行时，把 `\n` 写成了真实换行，账本被拆成三行，唤醒如实带出了第一段。
   - 工人随后把自己刚写的三行重写成一行，符合「只改自己的行」。
   - pi 主控发现摘要和账本对不上，就回读账本做了核对。
   - 这属于工人模型的行为，不是 QWB 缺陷。

## 返修任务（执行者：Codex，gpt-6-sol / high，禁止 fast）

**起点**

- 同一分支 `qwb-e2e-controllers`，同一 Space `wHH`，从 `c289b83` 开始。
- 本报告随第一笔提交入库。

**范围**

- 只改 `README.md`、`README.zh.md`、`docs/DECISIONS.md`，外加 `docs/reviews/`。
- 不动 `bin/`、`templates/`、`tests/`，也不重跑真实 E2E，因为这几处文档不会被装进目标项目，也不影响主控的行为。

**门与证明**

- fast 和 full 都在最终 SHA 上跑，用 `--report`，格式同 r2。
- 用 `git diff --stat c289b83 <最终SHA>` 证明只改了上面这些文件。

**报告**

- 写 `docs/reviews/2026-09-24-qwb-e2e-controllers-r3-execution.md`，内容简短：改了哪几处、门的退出码、diff 范围。
- 最后单独输出一行 `QWB_E2E_CONTROLLERS_R3 DONE <完整SHA>` 或 `QWB_E2E_CONTROLLERS_R3 BLOCKED <原因>`。

**REVIEW_QWB_E2E_CONTROLLERS_R2 AMEND**
