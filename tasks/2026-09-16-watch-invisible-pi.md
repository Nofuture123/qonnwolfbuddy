# 任务书：值守隐形化（Pi 主控）——`.pi/extensions/qwb-watch.ts` 持有阻塞值守子进程并注入 follow-up

```
任务 id:  watch-invisible-pi
state:    verified
scenarios-fp: e05cb5c4f5649f89d9939dcbc87c1ac394d02522
来源:     Rocky 2026-09-16；主控三种之一是 pi（本机 pi 0.85.1）
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1） → <待派>
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-watch-invisible-pi.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/watch-invisible-pi
分支:     watch-invisible-pi
前置:     watch-invisible 票 verified（依赖它交付的 `qwb-wake.sh --block` 退出码契约 2/0/124）
```

## 0. 背景与范围

`watch-invisible` 票交付了 `qwb-wake.sh --block`（阻塞到有变化 exit 2 / 无未结项 exit 0 / `--max-ms` 到期 exit 124）与 Claude Code Stop hook、Codex 前台 checkpoint。本票补 Pi：Pi 主控没有 Stop hook，但有扩展机制，可以持有子进程并把结果作为 follow-up 消息注入会话——不需要窗口、不需要模型循环调 tool。

**先例（只读）**：`/Users/rocky/projects/firstmate/.pi/extensions/fm-primary-pi-watch.ts`（1167 行；关键 API：`pi.on("session_start", …)`、`spawn("bash", …)` 持有子进程、`pi.sendUserMessage(content, { deliverAs: "followUp" })` 注入）。firstmate 验证过 Pi 0.81–0.84；本机 0.85.1，API 差异由执行者按 Pi 文档核实。**本票只取"持子进程 + follow-up 注入"这一个机制，不搬 firstmate 的分支监督、lease、generation ledger 等。**

### 要做的事

- 新文件 `templates/pi-extensions/qwb-watch.ts`；`qwb-init.sh` 装到目标项目 `.pi/extensions/qwb-watch.ts`（幂等：同内容不重写；目标已有不同内容 → 备份为 `.bak` 后覆盖并在 stdout 说明）。
- 扩展行为：
  1. `session_start`：读 `qwbuddy/.controller.lock/owner`，锁主 ≠ 本进程 `HERDR_PANE_ID` → 不动（非主控的 pi 会话不值守）。是锁主 → `spawn` 子进程 `bash qwbuddy/bin/qwb-wake.sh --block`（无 `--max-ms`，无限阻塞）。
  2. 子进程 exit 2 → 把 stdout 摘要以 `sendUserMessage(…, { deliverAs: "followUp" })` 注入（前缀固定 `[qwb-wake]`），然后**立即重新 spawn** 下一轮。
  3. exit 0（无未结项）→ 不注入、不重启；下次 `turn_end` 时若账本又有未结项则重新 spawn（用 `qwb-wake.sh --block --max-ms 1` 的 0/124 判定是否有未结项，不另写判定逻辑）。
  4. 其他退出码 → 记 `qwbuddy/.pi-watch.err`，指数退避重启（上限 `QWB_WAKE_INTERVAL_MS` × 8），退避到顶注入一条 `[qwb-wake] 值守故障：…`（这是叫醒主控去修，不是通知使用者）。
  5. 单飞：扩展内只持一个子进程；`session_start` 重复触发（/new、/resume、reload）先杀旧子进程再起新。
  6. pi 进程退出 → 子进程随之退出（`spawn` 不 detach；必要时监听 `exit` 事件 kill）。
- `qwb-status.sh` 「值守：」行加第四态 `pi-ext`（判定文件：扩展在 spawn 后写 `qwbuddy/.watch` 同款记录，`kind=pi-ext pid=<子进程 pid>`；`.watch` 格式如需扩字段，`--ensure` 读取端同步兼容）。
- `templates/QWBUDDY.md` §1 第 8 步 Pi 一行：「Pi：`qwb-init.sh` 已装扩展，开局只需确认 `qwb-status.sh` 报 `值守：pi-ext`；首次装后需重启 pi 或 `/reload` 让扩展加载」。§9 表不加脚本行（扩展不是 `bin/` 脚本，在 §1 点名即可）。
- `docs/DECISIONS.md` 加一条：Pi 值守走扩展而非窗口/checkpoint 的理由（有后台注入能力就不让模型轮询）。

**白名单**：`templates/pi-extensions/qwb-watch.ts`（新）、`bin/qwb-init.sh`、`bin/qwb-status.sh`（仅「值守：」行）、`bin/qwb-wake.sh`（仅当 `.watch` 记录格式需要扩字段）、`templates/QWBUDDY.md`、`tests/smoke.sh`、`tests/fixtures/`、`docs/DECISIONS.md`。**不许动**：`bin/qwb-run.sh`、`bin/qwb-hook-claude-stop.sh`、`bin/qwb-lock.sh`、`bin/qwb-worktree.sh`、`bin/qwb-test.sh`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

（扩展是 TS，smoke.sh 是 bash；扩展逻辑用一个**不依赖 pi 进程**的方式测：把子进程管理与消息拼装抽成纯函数/可注入的模块，用 `node`/`bun` 跑一个 `tests/pi-ext.test.mjs`（或 `.ts`，按本机可直接执行的为准），由 `tests/smoke.sh` 调用；真机行为由 E2E 场景覆盖。）

### 锁主会话起子进程

Given 假的 `pi` 对象（记录 `on`/`sendUserMessage` 调用）、`.controller.lock/owner` = 本进程 `HERDR_PANE_ID`、假 `spawn`
When  触发 `session_start`
Then  `spawn` 被调 1 次，参数含 `qwb-wake.sh --block` 且**不含** `--max-ms`；`.watch` 写入 `kind=pi-ext pid=…`

### 非锁主不起子进程（失败路径）

Given `.controller.lock/owner` = 别的 pane id
When  触发 `session_start`
Then  `spawn` 0 次；无 `.watch` 写入；无 `sendUserMessage`

### exit 2 注入并重启

Given 子进程已起
When  假子进程以 exit 2 退出，stdout 为两行摘要
Then  `sendUserMessage` 被调 1 次，内容以 `[qwb-wake]` 开头且含那两行；`spawn` 随即第 2 次被调

### exit 0 不注入不重启

Given 子进程已起
When  假子进程 exit 0
Then  `sendUserMessage` 0 次；`spawn` 仍 1 次；`.watch` 已清

### 故障退避与到顶告警（失败路径）

Given 子进程已起；假时钟
When  假子进程连续以 exit 1 退出 9 次
Then  重启间隔依次翻倍并封顶在 `QWB_WAKE_INTERVAL_MS × 8`；第 9 次后 `sendUserMessage` 恰好 1 次且内容含 `值守故障`；`.pi-watch.err` 有 9 条记录

### session_start 重复触发单飞

Given 子进程 A 已起
When  再次触发 `session_start`（仍是锁主）
Then  A 被 kill；`spawn` 第 2 次被调；同一时刻活的子进程恰好 1 个

### init 幂等与备份

Given 目标项目 `.pi/extensions/qwb-watch.ts` 不存在 / 内容相同 / 内容不同 三种
When  `qwb-init.sh <项目>`
Then  分别：新建 / 不重写（mtime 不变）/ 备份为 `qwb-watch.ts.bak` 后覆盖并 stdout 说明

### status 四态

Given `.watch` 记 `kind=pi-ext pid=<活 pid>`
When  `qwb-status.sh`
Then  「值守：pi-ext」；pid 死时报「未运行」

### 真机 E2E：Pi 主控无打字被叫醒（执行者跑，主控复验）

Given 临时 git 项目装了 QW buddy（含扩展）；一个 `pi` 会话在 herdr pane 里持主控锁、处于空闲提示符；一张 running 票
When  另一个 pane 往票追加 `done: hello`
Then  `QWB_WAKE_INTERVAL_MS` 量级内 pi 会话**无人打字**出现 `[qwb-wake]` follow-up 并开始新 turn；执行者贴 `herdr pane read` 原文、`pi --version`、扩展加载日志；临时项目与 pane 用完即清（TEMP_CLEANUP=PASS）

## 2. 硬约束

- 超时一律毫秒；零通知使用者；只用 Herdr；无 cron/launchd/nohup 独立进程——子进程必须随 pi 死。
- 扩展不引入 npm 依赖（只用 Node 内置 + Pi 提供的 API）。
- 不凭 firstmate 转述下结论：Pi 0.85.1 的扩展 API 以官方文档/类型定义 + 真机为准。
- TS 文件通过 `tsc --noEmit`（若本机有）或 `node --check`（转译后）之一，写进快门或全门。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`
- 全门：`bash bin/qwb-test.sh full`
- 主控另跑：`bash tests/smoke.sh` 两次 + 真机复验 E2E

## 4. 报告要求

往主账本绝对路径追加 `working:` / `done:`（含跑了什么命令与原始结果）/ `blocked:` / `needs-decision:`。
最后打印 `DONE <commit sha>` 或 `STOP <原因>`。**不要改本文件的 `state:` 字段。**

疑点两行约定：

```
blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
working:  spec-resolved: <impl|spec>；<逐项回应与证据；改票位置，或保留原票的理由>
```

## 6. 本票不允许做的事

- 不搬 firstmate 的分支监督 / lease / generation ledger / 远程 secondmate。
- 不改 Claude hook 与 Codex 协议。
- 不给 pi 加 turn-end guard 之类的"阻止模型停下"机制——本票只做叫醒。
wake: 2026-09-21T19:24:16Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T19:54:26Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T20:24:37Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T20:54:46Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T21:24:58Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T21:55:27Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
wake: 2026-09-21T22:25:37Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
working: 2026-09-21T22:45:00Z 主控（claude-opus-5，pane wF2:p3）派发说明：前置 watch-invisible 已合并 main（b05036b；`qwb-wake.sh --block` 契约 2/0/124 与 `.watch` 三态已在）。改派 pi（zai-coding-cn/glm-5.3-flash）。与 audit-install-fixes 并行（它改 qwb-init.sh 的 .gitignore 段、dispatch-rules 路径、lint、hook 模板），本票只动票内白名单。**完成前先 `git merge main` 到本分支解冲突，smoke 新节号接在现有最大号之后、且必须加在 smoke.sh 收尾判定（SMOKE PASS; exit 0）之前，done: 行贴输出最后一个节标题与 PASS/FAIL 计数。** 本机 pi 版本以 `pi --version` 实测为准；真机 E2E 用临时项目 + 临时 pi 会话，用完即清。
dispatch: 2026-09-21T22:38:56Z worker=pi agent=qwb-watch-invisible-pi pane=wF2:pD dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/watch-invisible-pi
wake: 2026-09-21T22:40:36Z state=running fp=cd6a8fc36940511dda3240ee01464027776aebef
wake: 2026-09-21T23:10:44Z state=running fp=cd6a8fc36940511dda3240ee01464027776aebef
working: 2026-09-21T23:35:00Z 执行者（pi，pane wF2:pD）已交付并提交（分支 watch-invisible-pi，HEAD bfd260a）：pi-extensions/qwb-watch.ts（createWatchCore 依赖注入+default factory）、tests/pi-ext.test.mjs（9 项行为测试，node 26 直跑 .ts）、qwb-init.sh 装 .pi/extensions/qwb-watch.ts 幂等三态、qwb-wake.sh watch_check 加 pi-ext 第四态（kill -0 判活不需 herdr）、QWBUDDY.md §1 第 8 步 Pi 行、DECISIONS 三十二；已 git merge main（audit-install-fixes），本票 smoke 节顺延 71-73、DECISIONS 编号让位；质量门全绿待主控复验
done: 2026-09-21T23:55:00Z worker=pi agent=qwb-watch-invisible-pi pane=wF2:pD dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/watch-invisible-pi sha=bfd260a。检查与原始结果：①bash bin/qwb-test.sh fast → rc=0；②bash bin/qwb-test.sh full（smoke+review-identity+lint）→ rc=0、尾行 LINT PASS；③bash tests/smoke.sh 两次 → 均 rc=0、SMOKE PASS、567 PASS/0 FAIL，最后一节标题「== 73. status 值守第四态 pi-ext：pid 活 → pi-ext，pid 死 → 未运行 ==」（merge main 后节号 71-73，main 的 audit-install-fixes 占 67-70）；④node tests/pi-ext.test.mjs → 9 passed（锁主/非锁主/exit2 注入重启/exit0 清.watch/退避封顶+告警恰1次+err 9条/单飞/turn_end 探测124 重新值守/shutdown 旧代际作废）；⑤TS 门=node type-stripping 转译 rc=0（本机无 tsc，npx 撞假 tsc 包）；⑥真机 E2E（临时 git 项目 /tmp/qwb-e2e-pi.ikHNWO + qwb-init 装扩展，QWB_WAKE_INTERVAL_MS=2000，herdr pane wF2:pE 抢锁 wF2:pE+exec pi，pi 0.86.1，zai-coding-cn/glm-5.3-flash）：pi 信任扩展后无人打字，pane read 原文出现「[qwb-wake] 看账本：1 张未结项有进展 →(1) 2099-01-01-e2e-demo(running)…」并开始新 turn（基线叫醒）；另一侧往票追加 done: hello → 账本 wake: 23:13:43 行、pi TUI 显示「Follow-up: [qwb-wake] …」排队并在回合结束投递（模型随后自主按 QWBUDDY.md 剧本 dispatch 工人 pane wF2:pF 实现并验收，值守连续叫醒，.watch 登记 kind=pi-ext pid=21185 cmd=bash …/qwb-wake.sh --block 无 --max-ms——链路与单飞登记全部实测命中）；⑦TEMP_CLEANUP=PASS（pane wF2:pE/wF2:pF 已 close，/tmp/qwb-e2e-pi.ikHNWO 已删）；⑧qwb-status.sh 对 pi-ext 活 pid 报「值守：pi-ext（pid …）」、kill 后报「值守：未运行」。注意：本机 pi 实测 0.86.1（票面写 0.85.1），扩展 API（session_start/session_shutdown/turn_end、sendUserMessage deliverAs:"followUp"）按 0.86.1 官方文档核实通过，E2E 真机验证同一版本。
wake: 2026-09-21T23:20:47Z state=running fp=a76f449dd741c12b88d6f15365b808bc14063096
working: 2026-09-21T23:22:00Z 主控验货（独立复跑于 worktree bfd260a）：`qwb-test.sh fast` rc=0；`tests/smoke.sh` rc=0、567 PASS / 0 FAIL，末节「== 73.」后 SMOKE PASS；`qwb-lint.sh` LINT PASS；`node tests/pi-ext.test.mjs` 9 passed；diff main 7 文件 +647/−1 全在白名单（含 merge main 提交）；main 可 fast-forward；临时项目 /tmp/qwb-e2e-pi.* 与 pane wF2:pE 确认已清。反转：把锁主判定 === 改成 !== → pi-ext 测试首条断言即失败（rc=1，「spawn 被调 1 次 0 !== 1」），恢复后工作树干净。备注：本机 pi 0.86.1（票面 0.85.1），执行者按 0.86.1 文档核实并真机 E2E 通过。结论：通过，state → verified，fast-forward 合并。
worktree: merged branch=watch-invisible-pi tag=-
