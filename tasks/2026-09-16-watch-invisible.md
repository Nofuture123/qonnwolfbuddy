# 任务书：值守隐形化——按主控 harness 接值守，不再要求可见 tab（Claude Code / Codex 两种主控）

```
任务 id:  watch-invisible
state:    verified
scenarios-fp: d3766400970340564d231c86fd63c20f07c684e6
来源:     Rocky 2026-09-16「firstmate 就没有值守窗口」；主控只会是 codex / pi / claude code 三种
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1，qonnwolf-sites 主控兼任） → <待派>
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-watch-invisible.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/watch-invisible
分支:     watch-invisible
前置:     worker-launch-modes 票 verified 后再派（同改 tests/smoke.sh 与 templates/QWBUDDY.md，避免冲突）
```

## 0. 背景与范围

**现状**：值守 = `qwb-wake.sh --ensure` 在主控所在 workspace 开一个**可见 shell tab**，死循环读账本指纹，变了就 `herdr pane run <主控 pane>` 往主控输入框打字。Rocky 不想要这个窗口。

**先例（已读源码，`/Users/rocky/projects/firstmate`）**：firstmate 也有 bash watcher（`bin/fm-watch.sh`），但没有窗口。它按主控 harness 各接一套：

| 主控 | firstmate 做法 | 证据 |
|---|---|---|
| Claude Code | `.claude/settings.json` 的 **Stop hook**（`"asyncRewake": true, "timeout": 28800`）→ hook 前台跑 watcher，有可动作事件时 **exit 2** → Claude Code 重新进入一个 turn。零 token、无窗口、进程随会话死 | `.claude/settings.json` Stop 段；`bin/fm-claude-stop-autoarm.sh` 头注释 |
| Codex | **前台 checkpoint**：模型自己循环调 `fm-watch-checkpoint.sh --seconds 180`（阻塞式 tool call）；有事件 exit 0 带输出，安静到期 exit 124。原因："Codex cannot reason while a foreground tool call is running"，且不依赖后台任务唤醒 | `docs/supervision-protocols/codex.md`；`bin/fm-watch-checkpoint.sh` |
| Pi | `.pi/extensions/*.ts` 扩展持有子进程，子进程返回时由扩展注入 follow-up 消息 | `.pi/extensions/fm-primary-pi-watch.ts` |

**本票范围：Claude Code 与 Codex 两种主控。** Pi 扩展另开票 `watch-invisible-pi`（TS 扩展，改动边界不同）。可见 tab（`--ensure`）**保留**作为未知主控的 fallback，但 §1 开局不再强制。

### 要做的事

**A. `qwb-wake.sh --block [--max-ms <毫秒>]`（阻塞式值守，三种主控共用的核心）**

- 前台阻塞，不 `pane run`、不开 tab。复用现有的指纹/`wake:` 行去重/`QWB_REWAKE_MS` 时间兜底逻辑（去重状态仍记在账本 `wake:` 行，与 `--ensure` 模式共享，两种模式不会互相重复叫）。
- 退出码契约：**2** = 有可动作变化（stdout 打印摘要：哪些票、最后一条状态行；同时往对应票追加 `wake:` 行）；**0** = 账本无未结项（不写任何行）；**124** = `--max-ms` 到期无变化（不写任何行）；其他非 0 = 错误。
- 轮询间隔沿用 `QWB_WAKE_INTERVAL_MS`；必须支持 `QWB_NOW_MS_CMD` / `QWB_SLEEP_CMD` 假时钟注入（现有约定），否则超时场景 smoke 跑不快。
- 不给 `--max-ms` 时无限阻塞直到 exit 2 或 0。

**B. Claude Code 主控：Stop hook**

- 新脚本 `bin/qwb-hook-claude-stop.sh`（随 `qwb-init.sh` 装进 `qwbuddy/bin/`，§9 表加一行）：
  1. 守卫：读 `qwbuddy/.controller.lock/owner`，锁主 id ≠ 本进程 `HERDR_PANE_ID` → **exit 0**（不是主控的 Claude 会话不值守；锁不存在同样 exit 0）。
  2. 单飞：`qwbuddy/.hook.lock/`（mkdir 原子）+ pid 存活判定；已有活的 → exit 0 立即返回；残留死锁 → 接管。Claude Code 每次 Stop 都触发、不去重（firstmate 头注释原话），必须自己单飞。
  3. 跑 `qwb-wake.sh --block --max-ms ${QWB_HOOK_MAX_MS:-7200000}`；exit 2 → 把摘要同时写 stdout 与 stderr（执行者用真机 E2E 确定哪条通道能到模型，把结论写进账本与脚本注释）后 **exit 2**；0/124 → exit 0；错误 → exit 0 并把错误写 `qwbuddy/.hook.err`（hook 出错不能卡死主控）。
  4. `config.sh` 新键 `QWB_HOOK_MAX_MS=7200000`（毫秒），`templates/config.sh` 同步。
- `qwb-init.sh`：往目标项目 `.claude/settings.json` **合并**一条 Stop hook（不覆盖已有 hooks，其他键原样；幂等——按 command 字符串判重）：
  ```json
  {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/qwbuddy/bin/qwb-hook-claude-stop.sh","asyncRewake":true,"timeout":7200}
  ```
  `timeout` 单位按 Claude Code hooks 文档核实（firstmate 写 28800 配 8 小时 → 秒），执行者查文档确认并在账本留证；settings.json 不存在则新建；已存在但非法 JSON → **拒绝并提示**，不写。
- Claude Code hooks 的 `asyncRewake` 语义（exit 2 是否重新起 turn、输出走哪条通道）**以本机 Claude Code 版本实测为准**：执行者用 `claude --version` + 官方文档（context7 / claude-code-guide）+ 真机 E2E 三方核实，不凭 firstmate 转述。

**C. Codex 主控：前台 checkpoint 协议（文档 + 复用 A）**

- `templates/QWBUDDY.md` §1 第 8 步改写为「按主控 harness 接值守」：
  - Claude Code：`qwb-init.sh` 已装 Stop hook，开局只需确认 `qwb-status.sh` 报「值守：hook」；什么都不用起。
  - Codex：开局点名后，把 `bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000` 当**前台 tool call** 循环跑：exit 2 → 处理账本 → 再跑；124 → 再跑；0 → 停。**禁止** `&` 后台、禁止 Codex 后台任务（firstmate codex.md 第 6 条同理）。
  - 其他/未知主控：沿用 `--ensure` 可见 tab。
- `qwb-status.sh` 的「值守：」行要能报三种形态：`hook`（`.hook.lock` 活）/ `tab`（现状 `.watch`）/ `未运行`。

**D. 记录**

- `docs/DECISIONS.md` 加一条：§10.2「无守护进程」的边界——**由主控进程（hook / 前台 tool call / 扩展）拥有、随主控死**的子进程不算守护进程；仍然禁 cron / launchd / systemd / 独立 nohup 进程。可见 tab 降级为 fallback。
- `templates/QWBUDDY.md` §9 表、§11 MVP 边界同步。

**白名单**：`bin/qwb-wake.sh`、`bin/qwb-hook-claude-stop.sh`（新）、`bin/qwb-init.sh`、`bin/qwb-status.sh`（仅「值守：」行）、`bin/qwb-lint.sh`（若 §9 新脚本/新 config 键需要）、`templates/config.sh`、`templates/QWBUDDY.md`、`tests/smoke.sh`、`tests/fixtures/`、`docs/DECISIONS.md`。**不许动**：`bin/qwb-run.sh`、`bin/qwb-lock.sh`、`bin/qwb-worktree.sh`、`bin/qwb-test.sh`、`templates/roles/*`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### block 有变化：exit 2 + 摘要 + wake 行

Given 账本有一张 `state: running` 票，其最后状态行是工人新写的 `done: …`，票上无 `wake:` 行或最后 `wake:` 行的指纹与之不同
When  `qwb-wake.sh --block`（stub herdr；假时钟）
Then  退出码 2；stdout 含该票文件名与那条 `done:` 行；票末尾多一行 `wake:`；stub 日志**无** `pane run`、**无** `tab create`

### block 无未结项：exit 0 不留痕

Given 账本全部票 `state` ∈ {done, verified} 或账本为空
When  `qwb-wake.sh --block`
Then  退出码 0；任何票文件字节不变；stub 日志无 herdr 调用

### block 到期无变化：exit 124（失败路径）

Given 有未结项但指纹与最后 `wake:` 行一致，且距该 `wake:` 未超 `QWB_REWAKE_MS`；`--max-ms 500`；假时钟
When  `qwb-wake.sh --block --max-ms 500`
Then  退出码 124；票文件字节不变；假时钟推进 ≥ 500ms 且未忙循环（sleep 调用次数有上界，与现有 §"不得忙循环" 断言同款）

### block 时间兜底：超过 REWAKE 即使指纹未变也 exit 2

Given 有未结项，指纹与最后 `wake:` 一致，但该 `wake:` 时间戳距假时钟"现在"≥ `QWB_REWAKE_MS`
When  `qwb-wake.sh --block`
Then  退出码 2；追加新的 `wake:` 行

### hook 非锁主：exit 0 不值守（失败路径）

Given `qwbuddy/.controller.lock/owner` 记的是 `wX:p1`，本进程 `HERDR_PANE_ID=wX:p2`；账本有可动作变化
When  `qwb-hook-claude-stop.sh`
Then  退出码 0；立即返回（假时钟不推进）；票无新增 `wake:` 行；不创建 `.hook.lock`

### hook 单飞：并发第二次触发立即返回（失败路径）

Given 本进程是锁主；`qwbuddy/.hook.lock/` 已存在且其 pid 存活
When  `qwb-hook-claude-stop.sh`
Then  退出码 0；立即返回；不动已有 `.hook.lock`；不跑 `--block`

### hook 残留锁接管

Given 本进程是锁主；`.hook.lock/` 存在但 pid 已死
When  `qwb-hook-claude-stop.sh`（账本有可动作变化）
Then  接管锁、跑 `--block`、退出码 2、摘要在输出里；结束后 `.hook.lock` 已清

### init 合并 settings.json：幂等且不覆盖

Given 目标项目 `.claude/settings.json` 已有 `PreToolUse` 与一条别人的 `Stop` hook
When  `qwb-init.sh <项目>` 跑两次
Then  `Stop` 数组里恰好一条 qwb hook（command 含 `qwb-hook-claude-stop.sh`）；别人的 hook 与 `PreToolUse` 字节级原样；文件是合法 JSON

### init 遇非法 JSON 拒绝（失败路径）

Given `.claude/settings.json` 内容为 `{not json`
When  `qwb-init.sh <项目>`
Then  退出非 0；stderr 指出该文件与"未写入"；文件字节不变；`qwbuddy/` 其余安装照常完成或整体回退——二选一但必须在 stderr 说明是哪种

### status 三态

Given 分别构造：`.hook.lock` 活 / 只有 `.watch` 且 pane 在 / 两者皆无
When  `qwb-status.sh`
Then  「值守：」行分别为 `hook` / `tab（pane …）` / `未运行`

### 真机 E2E：Claude Code 主控无打字被叫醒（执行者跑，主控复验）

Given 临时 git 项目装了 QW buddy（含 Stop hook）；一个 Claude Code 会话在 herdr pane 里持主控锁并处于空闲提示符；一张 running 票
When  另一个 pane（任意工人或人工）往票追加 `done: hello`
Then  在 `QWB_WAKE_INTERVAL_MS` 量级内，Claude Code 会话**在无人打字的情况下**开始新 turn，且其上下文含 hook 摘要（该票名 + `done: hello`）；执行者把 `herdr pane read` 原文、`claude --version`、settings.json 内容贴账本；临时项目与 pane 用完即清（TEMP_CLEANUP=PASS）

### 真机 E2E：Codex checkpoint

Given 同上，但主控是 Codex 会话，按 §1 协议前台跑 `--block --max-ms 180000`
When  工人追加 `done: hello`
Then  该 tool call 以 exit 2 返回并带摘要，Codex 在同一 turn 内处理；再跑一次到期返回 124

## 2. 硬约束

- 超时一律毫秒（config、参数、文档）；hook 的 `timeout` 字段按 Claude Code 文档单位写，注释注明。
- 零通知使用者（§10.1）不变：hook 只叫醒主控，不弹窗不推送。
- 只用 Herdr；不引入 tmux/launchd/cron。
- 不改 `dispatch:`/`wake:` 行格式，不加 `state` 值。
- shellcheck 干净；`settings.json` 合并用 `python3`/`perl -MJSON::PP`（本仓已有 JSON::PP 先例），不用 jq（不保证装了）。
- 不凭 firstmate 转述下结论：Claude Code hook 语义三方核实（版本 + 文档 + 真机）。

## 3. 验收门

- 快门（改一行跑它）：`bash bin/qwb-test.sh fast`
- 全门（合并前跑）：`bash bin/qwb-test.sh full`
- 主控另跑：`bash tests/smoke.sh` 两次 + 真机复验两条 E2E + 在 qonnwolf-sites 重跑 `qwb-init.sh` 确认合并进它的 `.claude/settings.json` 不破坏现有内容

## 4. 报告要求

往主账本绝对路径追加 `working:` / `done:`（含跑了什么命令与原始结果）/ `blocked:` / `needs-decision:`。
最后打印 `DONE <commit sha>` 或 `STOP <原因>`。**不要改本文件的 `state:` 字段。**

疑点两行约定（工人或主控认为**票本身有缺陷**时用，不是实现遇到困难）：

```
blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
working:  spec-resolved: <impl|spec>；<逐项回应与证据；改票位置，或保留原票的理由>
```

- `spec-defect:` 由工人或主控提出，挂在 `blocked:` 行上。
- `spec-resolved:` 只有主控能写；一个处置结论覆盖其之前全部未决疑点。
- 普通 `working:` / `done:` / `dispatch:` 行不能解除疑点；改验收场景须用 `--revise-scenarios=<原因>`。

## 6. 本票不允许做的事

- 不做 Pi 扩展（另票 `watch-invisible-pi`）。
- 不删 `--ensure` 可见 tab 路径，不删 `qwb-wake.sh` 现有循环模式。
- 不改 firstmate 仓任何文件；只读它。
- 不往目标项目 `.claude/settings.json` 写 Stop 以外的 hook。
- 不引入通知通道。
wake: 2026-09-21T19:24:16Z state=running fp=368522136cbfcc45591872ff17a122187002a25b
working: 2026-09-21T19:32:00Z 主控（claude-opus-5，pane wF2:p3）派发说明：改派 pi（zai-coding-cn/glm-5.3-flash）。与 worker-max-permission（rebase 返工中）、worker-trust-preseed 并行，三票都改 tests/smoke.sh 尾部与 templates/QWBUDDY.md——**完成前先 `git merge main` 到本分支解冲突（两边新节都保留、本票 smoke 节号接在现有最大号之后），保证主控能 fast-forward**，再报 done。真机 E2E 两条（Claude Code Stop hook / Codex checkpoint）必须真跑并贴原文；跑不通就 blocked: 写清卡点，不许假绿。Claude Code hooks 的 Stop 语义用 context7 或 `claude --help`/官方文档核实并留证。
dispatch: 2026-09-21T19:30:31Z worker=pi agent=qwb-watch-invisible pane=wF2:p6 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/watch-invisible
working: 2026-09-23T00:00:00Z executor pi 开始：已读任务书；分支 watch-invisible 与 main 同步于 dd7daf7；进入读文档+三方核实 Claude Code Stop hook 阶段
wake: 2026-09-21T19:32:18Z state=running fp=2869de54d86df5d4096e1e19e5dfb6b9e20f79c6
working: 2026-09-23T00:10:00Z executor pi Claude Code hook 语义三方核实（其一版本、其二官方文档）：claude --version = 2.1.278；官方 hooks 参考（code.claude.com/docs/en/hooks.md，已抓全文存 /tmp/qwb-hooks-doc/hooks.md）：①timeout 字段单位=秒（原文 "Seconds before canceling"，默认 600），firstmate 写 28800 即 8 小时，本票 timeout=7200 即 2 小时、与 QWB_HOOK_MAX_MS=7200000 毫秒对齐；②asyncRewake=true：后台运行+exit 2 唤醒 Claude（Stop 事件 exit 2 效果="Prevents Claude from stopping, continues the conversation"），摘要走 stderr（stderr 为空才用 stdout）以 system reminder 交付——据此 hook 摘要 stderr 与 stdout 双写；③async hook 每次 Stop 都触发、不去重（原文 "no deduplication"）→ .hook.lock 单飞必要，firstmate 头注释与文档一致；④timeout 对 asyncRewake hook 仍生效（对 async 不生效）。其三真机 E2E 待实现完成后跑。开始实现：config 键→wake --block→hook 脚本→init 合并→status 三态→文档→smoke。
wake: 2026-09-21T19:40:21Z state=running fp=3e91dd7260b5015f47c0229155549e3a75a4c301
wake: 2026-09-21T20:10:31Z state=running fp=3e91dd7260b5015f47c0229155549e3a75a4c301
wake: 2026-09-21T20:40:42Z state=running fp=3e91dd7260b5015f47c0229155549e3a75a4c301
working: 2026-09-23T00:30:00Z executor pi 实现与门禁完成：①bin/qwb-wake.sh 新增 --block/--max-ms（退出码契约 2/0/124，去重与 REWAKE 兜底与循环模式共用）；②bin/qwb-hook-claude-stop.sh 新建（守卫/.hook.lock 单飞/摘要 stdout+stderr 双写/错误写 .hook.err 后 exit 0）；③bin/qwb-init.sh 合并 .claude/settings.json（python3 保键序重写，幂等按 command 判重，非法 JSON 拒绝且说明 qwbuddy/ 其余已装）；④bin/qwb-status.sh+watch_check 三态 hook/tab/未运行；⑤templates/config.sh 新键 QWB_HOOK_MAX_MS=7200000；⑥templates/QWBUDDY.md §1.8 按主控 harness 分流+§9 表+§10.2 守护进程边界+§11；⑦docs/DECISIONS.md 第二十八节；⑧tests/smoke.sh 新增 51-54 节 21 条断言。检查：bash bin/qwb-test.sh fast rc=0；bash bin/qwb-test.sh full rc=0（smoke 469 PASS / 0 FAIL，61s + review-identity PASS + LINT PASS）。排障记录：51 节曾被共享 $TMP 的 config.sh 污染（第 27 节负例永久追加 QWB_REWAKE_MS=0 覆盖 config），已改为独立项目 $BP/$HP 并以母本干净模板覆盖 config；hook 测试需 </dev/null 模拟 Claude Code 写完 stdin 即关。下一步真机 E2E 两条。
wake: 2026-09-21T21:10:52Z state=running fp=99c2d4667ce19f89f6781c5800743903793d9be5
working: 2026-09-23T00:40:00Z executor pi 真机 E2E 两条 PASS，TEMP_CLEANUP=PASS（临时项目 /tmp/qwb-e2e-cc、/tmp/qwb-e2e-codex 与 pane wF2:p8/p9 已清）。
【E2E-1 Claude Code 主控无打字被叫醒】claude --version=2.1.278；临时 git 项目装 buddy（settings.json 的 hooks.Stop 恰一条 qwb hook：{"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/qwbuddy/bin/qwb-hook-claude-stop.sh","asyncRewake":true,"timeout":7200}，QWB_WAKE_INTERVAL_MS=5000）；herdr pane wF2:p8 起 claude，提示词抢锁（owner=2026-09-21T21:12:44Z wF2:p8）后结束回合。pane read 原文关键段：「⏺ Stop hook feedback / ⏺ 值守 hook 反馈：2099-12-31-e2e 仍为 running…」；21:13:22Z 从另一 pane 追加 done: hello（无人打字）→ 21:13:23Z 票内新增 wake 行 → claude 自动开新 turn，pane read 原文：「⏺ Stop hook feedback / ⏺ 值守 hook 第二次反馈：2099-12-31-e2e（running）done: hello。遵照你的指令，我不再执行任何动作…」——摘要（票名+done 行）经 hook 通道到达模型，唤醒时延在 QWB_WAKE_INTERVAL_MS(5s) 量级。
【E2E-2 Codex 前台 checkpoint】herdr pane wF2:p9 起 codex v0.155.1（gpt-6-astra low），下发 §1.8 checkpoint 协议。pane read 原文关键段：第一轮「• Ran bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000 / └ 2099-12-31-e2e（running）」=exit 2 带摘要，Codex 同 turn 读票并追加 working: 状态行；21:16:28Z 追加 done: hello 触发后续轮 exit 2（账本 21:16:42Z wake 行 fp 覆盖 done: hello），Codex「账本新出现 done: hello，继续按协议监听」；再跑一轮 180000ms 到期，pane 原文：「• Ran bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000 / └ 值守：--block 到期（--max-ms 180000ms）无变化 / • 上一轮返回 124（180000ms 内无变化），已直接启动下一轮前台值守。」=124 按协议续跑。
下一步：merge main、提交、报 done。
wake: 2026-09-21T21:22:58Z state=running fp=5e6a04c4add9c76139010c72c381984fdb7e9ae1
done: 值守隐形化完成，HEAD=b05036b（merge main 后）。改动：bin/qwb-wake.sh 增 --block[--max-ms]（退出码 2=可动作变化(stdout摘要+wake:行)/0=无未结项/124=到期无变化，与循环模式共用指纹去重+REWAKE兜底+假时钟注入，不依赖 herdr）；bin/qwb-hook-claude-stop.sh 新建（守卫 owner==HERDR_PANE_ID→.hook.lock 单飞+死锁接管→前台 --block，摘要 stdout+stderr 双写，异常写 .hook.err 后 exit 0）；bin/qwb-init.sh 幂等合并 Claude Code Stop hook 进 .claude/settings.json（python3 保键序，非法 JSON 拒绝且 stderr 说明 qwbuddy/ 其余已装）；status/--check 值守三态 hook/tab/未运行；config 新键 QWB_HOOK_MAX_MS=7200000；QWBUDDY.md §1.8 按 harness 分流+§9 表+§10.2 边界（主控拥有随主控死的子进程不算守护进程，仍禁 cron/launchd/nohup）+§11；DECISIONS 增二十九节（已顺延，main 占二十八）；smoke 增 53-56 节。hook 语义三方核实：claude 2.1.278 + code.claude.com/docs/en/hooks.md（timeout 单位=秒；asyncRewake exit 2 唤醒、stderr 优先交付、不去重）+ 真机 E2E。检查与原始结果：①bash bin/qwb-test.sh fast rc=0；②合并前 full rc=0（smoke 469 PASS/0 FAIL 61s+REVIEW-IDENTITY PASS+LINT PASS）；③git merge main 解三冲突（DECISIONS 顺延二十九/QWBUDDY §1.7 取 main trust-preseed+§1.8 取本票/smoke 节号顺延 53-56），合并后重跑 fast rc=0、full rc=0（521 PASS/0 FAIL 63s），git merge-base --is-ancestor main HEAD ✓ main 可 fast-forward；④真机 E2E-1 Claude Code：pane wF2:p8 claude 2.1.278 持锁（owner=wF2:p8）空闲，21:13:22Z 无人打字追加 done: hello→21:13:23Z wake 行→pane read 原文「⏺ Stop hook feedback／值守 hook 第二次反馈：2099-12-31-e2e（running）done: hello」=模型上下文含摘要，时延 5s 量级；⑤真机 E2E-2 Codex：wF2:p9 codex v0.155.1 按 §1.8 协议前台循环，原文「• Ran bash …--block --max-ms 180000／└ 2099-12-31-e2e（running）」exit 2 带摘要并同 turn 追加 working: 行；done: hello 后续轮 exit 2 捕获（21:16:42Z wake 行）；再跑一轮原文「└ 值守：--block 到期（--max-ms 180000ms）无变化／上一轮返回 124…已直接启动下一轮」=124 ✓；⑥TEMP_CLEANUP=PASS（/tmp/qwb-e2e-cc、/tmp/qwb-e2e-codex、pane wF2:p8/p9 均已清）。
wake: 2026-09-21T21:24:58Z state=running fp=c8154d07837fd326968c9cceaaa66da5d2a41ad2
working: 2026-09-21T21:35:00Z 主控验货（独立复跑于 worktree b05036b）：`qwb-test.sh fast` rc=0；`tests/smoke.sh` rc=0、499 PASS / 0 FAIL（53–56 节在列）；`qwb-lint.sh` LINT PASS；diff main 7 文件 +456/−14 全在白名单；main 可 fast-forward；临时项目 /tmp/qwb-e2e-cc、/tmp/qwb-e2e-codex 与 pane wF2:p8/p9 确认已清。读码：hook 守卫→单飞→前台 --block→2/0/124 分流与票一致；init 合并 settings.json 幂等且非法 JSON 拒绝。反转验证：删掉 block_round 的摘要 printf → 2 条断言变红（--block 有变化 / hook 接管），恢复后 shasum c7e166b… 一致、工作树干净。两条附带发现（不阻塞，转入 audit-runtime-fixes）：① smoke §53 三处 `--block` 不带 --max-ms，若实现回归成永不 exit 2 会让整套 smoke 挂死而不是变红（主控第一次反转就撞上，需 pkill）；② hook 起的 --block 只在启动时核对锁主，主控会话退出后孤儿 hook 仍可能消费一次 wake（写 wake: 行）——新主控开局读账本可补救，但 --block 应每轮复核锁主仍是本 pane。结论：通过，state → verified，fast-forward 合并。
worktree: merged branch=watch-invisible tag=- （主控手工收尾：qwb-worktree.sh finish 因任务 id 子串撞 watch-invisible-pi 拒绝，见 audit-runtime-fixes §F；删除依据 OID b05036badcbb631ee41e81f2540937789ec118ca 已含于 main）
