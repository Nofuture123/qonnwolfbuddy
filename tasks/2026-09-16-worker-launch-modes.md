# 任务书：qwb-run.sh 支持非 herdr-kind 工人（cmd / zcode 启动方式）

```
任务 id:  worker-launch-modes
state:    verified
scenarios-fp: ddd54816cf66203796d1435bc3ea4e37bd1cd863
来源:     Rocky 2026-09-16（qonnwolf-sites 主控接入 Command Code 与 zcodecli 时发现派不出去）
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1，qonnwolf-sites 主控兼任） → codex
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-worker-launch-modes.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-launch-modes
分支:     worker-launch-modes
```

## 0. 背景与范围

**问题（已实测，2026-09-16）**：`bin/qwb-run.sh` 起工人只有一条路 `herdr agent start --kind <工人名>`。herdr 的 kind 是硬编码白名单（pi/claude/codex/gemini/cursor/devin/agy/cline/omp/…），不含 `cmd`（Command Code）与 `zcode`：

```
$ herdr agent start x --kind cmd --pane w0:p0
unsupported interactive agent kind: cmd
```

但 herdr **能检测**这两种已在跑的进程（`~/.config/herdr/plugins/config/commandcode.integration/agent-detection/cmd.toml` 与 zcode 插件），检测到后 `herdr agent get/prompt/wait <pane_id>` 都能寻址（实测 zcode pane `wAB:p2` 的 `agent get` 返回 `agent=zcode`）。所以缺的只是「怎么起」，起来之后账本/值守机制不变。

**目标**：`qwb-run.sh` 支持按工人名选择启动方式，默认仍是 `herdr agent start`，新增两种：

| 启动方式 | 怎么起 | 怎么发提示词 |
|---|---|---|
| `herdr`（默认，现状） | `herdr agent start <NAME> --kind <工人> --pane <PANE>` | `herdr agent prompt <NAME> "<提示词>"` |
| `pane-run:<命令行>` | 在 qwb-run 新开（或 `--pane` 复用）的 shell pane 里 `herdr pane run <PANE> "<命令行>"`，然后轮询 `herdr agent get <PANE>` 直到成功（超时 `QWB_AGENT_START_MS`），再 `herdr agent rename <PANE> <NAME>` | `herdr pane run <PANE> "<提示词>"`——**不是** `agent prompt`：实测 2026-09-16 检测到的非官方 kind agent（含 rename 后）调 `herdr agent prompt` 返回 `agent_not_ready: not an active named agent`；`pane run` 直打一行可用（zcode 已回话）。`agent get / wait --until done` 可用 |

**zcode 不需要单独方式**：`zcodecli chat-open` 内部就是 `herdr tab create` + `herdr pane run <pane> "zcodecli chat"`（见 `~/.local/share/herdr-zcode/scripts/zcodecli_cli.py` `cmd_chat_open`），`zcodecli chat` 是当前 pane 的前台交互会话，与 `codex`/`cmd` 同形。所以 zcode 就是 `pane-run:zcodecli chat`。原 `zcodecli-chat` 方式**取消**——F2 时序疑点随之消失（pane 在 tab create 后即已知）。

**配置**：`config.sh` 新增一个键（保持 bash 可 source、lint 「config 死键」检查能识别）：

```bash
QWB_WORKER_LAUNCH="cmd=pane-run:cmd zcode=pane-run:zcodecli chat"   # 工人名=启动方式；未列出的工人走 herdr agent start。值里可含空格：解析按「工人名=」前缀切分，不按空格切
```

工人仍须在 `QWB_WORKERS` 里；`QWB_WORKER_LAUNCH` 只决定起法。`templates/config.sh` 同步加该键（默认空串）+ 一行注释；`qwb.config.sh`（母本仓自用）不需要。

**记账不变**：`dispatch:` 行仍写 `worker= agent= pane= dir=`；三种方式下 `pane=` 都必须是最终托管工人的那个 pane id（值守 `qwb-wake.sh` 按它 `herdr agent wait`）。

**F2 规则在三种方式下的精确含义**（2026-09-16 主控处置 spec-defect 后明确）：F2 保护的是「工人收到提示词、可能开始往账本追加」之前账本已写完。`state:`/`scenarios-fp:` 一律在起任何进程之前写；`dispatch:` 行的时点按方式定：
- `herdr` / `pane-run`：pane 在 tab create 后即已知 → `dispatch:` 在起工人之前写（现状）。
- `zcodecli-chat`：pane 只能由 `chat-open` 返回 → 顺序为 `chat-open`（拿 pane）→ 写 `dispatch:` → `zcodecli --pane <pane> send <提示词>`。`chat-open` 之后、`send` 之前任何一步失败，必须 `zcodecli --pane <pane> close` 收掉该 pane 再以非 0 退出，不留孤儿 pane；此时任务书里不得留下 `dispatch:` 行（写失败）或留下的 `dispatch:` 行必须已完整（写成功但 send 失败——与 `herdr agent start` 失败现状一致）。

**白名单**：`bin/qwb-run.sh`、`bin/qwb-lint.sh`（若「config 死键」检查需要认新键）、`templates/config.sh`、`tests/smoke.sh`、`tests/fixtures/herdr/`、`templates/QWBUDDY.md` §4/§9 各加一句、`docs/DECISIONS.md` 加一条。**不许动**：`bin/qwb-wake.sh`、`bin/qwb-status.sh`、`bin/qwb-lock.sh`、`bin/qwb-worktree.sh`、`bin/qwb-init.sh`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### 默认工人不受影响（回归）

Given `QWB_WORKER_LAUNCH` 为空或未声明，`--worker codex`
When  `qwb-run.sh --task disp --worker codex --here`（stub herdr）
Then  stub 日志有 `agent start` 与 `agent prompt`，`dispatch:` 行 `pane=` 为 tab create 返回的 pane；与现有 smoke §9 断言全部一致

### pane-run 方式派发成功

Given `QWB_WORKERS` 含 `cmd`，`QWB_WORKER_LAUNCH="cmd=pane-run:cmd"`，stub herdr 的 `agent get <pane>` 在第 N 次（N≥2）调用后才返回成功（模拟检测延迟）
When  `qwb-run.sh --task disp --worker cmd --here`
Then  stub 日志顺序为 `tab create` → `pane run <pane> cmd` → ≥2 次 `agent get <pane>` → `agent rename <pane> qwb-disp` → `pane run <pane> <提示词>`（提示词含任务书绝对路径与「写完状态行再收工」）；**没有** `agent start`、**没有** `agent prompt`；`dispatch:` 行 `worker=cmd agent=qwb-disp pane=<该 pane>`；退出码 0

### pane-run 检测超时则失败

Given 同上，但 stub 的 `agent get` 一直返回 `agent_not_found`，`QWB_AGENT_START_MS=300`
When  `qwb-run.sh --task disp --worker cmd --here`
Then  在约 300ms 内退出非 0，stderr 含「检测超时」及 pane id 与手工排查步骤；stub 日志在 `pane run <pane> cmd` 之后**无**第二次 `pane run`（未发提示词）；任务书里已有的 `dispatch:` 行保留（与现状 `herdr agent start` 失败时行为一致，不回滚账本）

### 命令行含空格的 pane-run（zcode）

Given `QWB_WORKERS` 含 `zcode`，`QWB_WORKER_LAUNCH="cmd=pane-run:cmd zcode=pane-run:zcodecli chat"`
When  `qwb-run.sh --task disp --worker zcode --here`
Then  stub 日志有 `pane run <pane> zcodecli chat`（整条命令行，不被空格截成 `zcodecli`）；其余与「pane-run 方式派发成功」同；`dispatch:` 行 `worker=zcode`；退出码 0

### pane-run 命令行为 headless 形式则拒绝（失败路径）

Given `QWB_WORKER_LAUNCH="cmd=pane-run:cmd -p"`
When  `qwb-run.sh --task disp --worker cmd --here`
Then  在任何副作用之前退出非 0，stderr 说明禁 headless；任务书无新增 `dispatch:` 行

### 启动方式非法则拒绝（失败路径）

Given `QWB_WORKER_LAUNCH="cmd=teleport"`
When  `qwb-run.sh --task disp --worker cmd --here`
Then  在任何副作用之前退出非 0，stderr 列出合法启动方式（`herdr` / `pane-run:<命令行>`）；任务书无新增 `dispatch:` 行

### lint 认新键

Given `templates/config.sh` 与 `qwb.config.sh` 已含/未含 `QWB_WORKER_LAUNCH`
When  `bash bin/qwb-lint.sh`
Then  「config 无死键」PASS（新键被 `bin/qwb-run.sh` 引用）；全部检查 PASS

### 真机 E2E（执行者跑，主控复验）

Given 本机 `cmd` 与 `zcodecli` 在 PATH，herdr 在跑，一个临时 git 项目（用完即删，见错题本「临时项目谁建谁清」）
When  分别以 `--worker cmd` 与 `--worker zcode` 真实派发一张只要求「往主账本追加 `done: hello`」的票
Then  两个 pane 的工人各自往主账本追加了 `done:` 行；`qwb-status.sh` 能列出两个窗口；`qwb-wake.sh --once` 能对它们 `agent wait` 不报错（注意：zcode 一轮结束后状态是 `done` 不是 `idle`，若 wake 只等 idle 须在账本记录实测行为，不改 qwb-wake.sh）；执行者把两次派发的 `dispatch:` 行、pane id、`herdr agent get` 原始输出贴进本账本 `done:` 行

## 2. 硬约束

- 工人一律 Herdr 窗口交互式运行，禁 headless（`pane-run` 的命令行不许带 `-p`/`--print`/`exec` 之类）。
- 超时一律毫秒；轮询 `agent get` 的间隔由脚本内常量决定，须支持 `QWB_SLEEP_CMD`/`QWB_NOW_MS_CMD` 注入（与 `qwb-wake.sh` 同款假时钟约定，见 QWBUDDY.md §6），否则超时场景在 smoke 里跑不快。
- 不改 `dispatch:` 行格式、不加头部必填字段、不加新的 `state` 值。
- 只用 Herdr；`zcodecli` 是 Rocky 自研桥接，按其 `--help` 真实接口用，不猜参数——不确定的先真跑一次录进 fixtures。
- shellcheck 干净（快门）。

## 3. 验收门

- 快门（改一行跑它）：`bash bin/qwb-test.sh fast`
- 全门（合并前跑）：`bash bin/qwb-test.sh full`
- 主控另跑：`bash tests/smoke.sh` 两次（稳定性）+ 真机复验 §1 最后一条

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

- 不给 herdr 提 PR、不改 herdr 插件目录下的任何文件。
- 不改 `zcodecli` 本身；接口不够用就 `blocked:` 说明缺什么。
- 不把 `cmd`/`zcode` 写进母本仓 `qwb.config.sh` 的工人表（母本仓不用它们干活）；只在 `templates/config.sh` 留键与注释。
- 不重构 `qwb-run.sh` 其他段落（疑点门、场景门、worktree 逻辑原样）。
dispatch: 2026-09-16T17:53:25Z worker=codex agent=qwb-worker-launch-modes pane=wA2:p4 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-launch-modes
working: 2026-09-16T17:54:19Z intake-baseline 完成；已完整读取任务书、templates/QWBUDDY.md、templates/roles/执行者.md、tasks/lessons.md 与全局规范；实现基线 HEAD=e251ff91b59e27b48476731236c4dcd23c4a575a，staged/unstaged/untracked 均为空，锁定票内白名单，下一阶段先在 tests/smoke.sh 公共 CLI 缝隙补验收场景。
blocked: spec-defect: 2026-09-16T17:56:03Z §0/F2 要求“所有账本写入仍在起工人之前完成”，同时 zcodecli-chat 要求“不先 herdr tab create”且 dispatch.pane 必须取 chat-open 返回值；本机真实 `zcodecli chat-open --cwd /tmp --label qwb-worker-launch-fixture` 只有在已创建并启动 zcode pane 后才输出 `chat pane: wA2:p5 (tab wA2:t4, workspace wA2)`，`zcodecli chat-open --help` 仅有 --workspace/--herdr-workspace/--cwd/--label，无预留 pane/id 或 dry-run。因此起工人前无法知道最终 pane id，不能同时满足“完整 dispatch 先写”与“chat-open 后取 pane”。继续实现必须由主控明确选择：放宽 zcode 路径为 chat-open 成功后立即记账，或扩展 zcodecli 提供起工人前可获 pane 的接口；当前 worktree 仍为 HEAD=e251ff91b59e27b48476731236c4dcd23c4a575a 且 staged/unstaged/untracked 均为空，真实样本 pane 已用 `zcodecli --pane wA2:p5 close` 清理，随后 `herdr pane get wA2:p5` 原始结果为 pane_not_found。
working: spec-resolved: spec；2026-09-16T18:16Z 主控核对：疑点成立——zcodecli chat-open 无预留 pane/dry-run 接口（已按执行者证据核实 --help 仅 4 个参数），"完整 dispatch 先写"与"pane 取自 chat-open"确实不可兼得。处置：不扩 zcodecli，改票 §0「记账不变」段补「F2 规则在三种方式下的精确含义」——F2 保护的是工人收到提示词前账本写完，因此 zcodecli-chat 顺序定为 chat-open → 写 dispatch → send，中途失败须 close 该 pane 不留孤儿。验收场景块未改（"dispatch: 行 pane= 是 chat-open 返回的 pane"本就与此一致），指纹不变。继续实现。
working: 2026-09-16T18:16:00Z spec-resolved 已接收；重算验收场景指纹=c5a6d8e025bc737dc5c538b4d20b72d48c21cf00 与冻结值一致，worktree 仍为 HEAD=e251ff91b59e27b48476731236c4dcd23c4a575a 且无本地改动；按新 F2 顺序继续 tests/smoke.sh 公共 CLI 缝隙的 red→green 实现。
working: 2026-09-16T18:22:00Z red 阶段完成；新增 tests/fixtures/zcodecli/chat-open.txt 真录、herdr cmd 检测成功/延迟真录及 tests/smoke.sh §47。检查原始结果：`bash -n tests/smoke.sh && bash bin/qwb-test.sh fast` exit=0；`bash tests/smoke.sh` exit=1，末行 `SMOKE FAIL（18 项）`，新场景精确失败于 pane-run 调用序列/300ms 超时、非法方式预检、zcodecli-chat 互斥/派发/send 失败清理，证明测试未被旧 herdr 默认路径假绿。
working: 2026-09-16T18:29:00Z green 实现阶段完成；qwb-run 已支持默认 herdr、pane-run 检测/改名/按 pane prompt、zcodecli chat-open→dispatch→send 及失败 close，模板配置/§4/§9/DECISIONS 同步。检查原始结果：`bash bin/qwb-test.sh fast && bash tests/smoke.sh` exit=0，末行 `SMOKE PASS`；§47 的延迟成功、300ms 超时、非法模式、headless、zcode --pane 互斥、send 失败清理全部 PASS。下一阶段做白名单差异自检与 cmd/zcode 真机 E2E，临时项目由本窗口当场清理。
working: scenarios-revised: old=c5a6d8e025bc737dc5c538b4d20b72d48c21cf00 new=ddd54816cf66203796d1435bc3ea4e37bd1cd863 reason=主控实测（2026-09-16 20:25，测试 pane wA2:p6 已 close）：①检测到的非官方 kind agent 调 herdr agent prompt 返回 agent_not_ready（rename 后同样），pane-run 的提示词改为 herdr pane run 直打；②zcodecli chat-open 内部就是 tab create + pane run "zcodecli chat"，zcode 归入 pane-run，取消 zcodecli-chat 方式及其两个场景，新增「命令行含空格」与「headless 拒绝」两场景；依据 QWBUDDY §5 显式修订条款
working: 2026-09-16T18:35:00Z 已接收显式场景修订；重算指纹=e49d17f0fe06657b4b4a4a66193e458de5d0a8a8 与新冻结值一致。上一轮真机临时 cmd tab w8Z:p27 已 close（随后 pane get=旁证 pane_not_found），/tmp/qwb-launch-e2e.uzeilf 已删除（TEMP_CLEANUP=PASS）。按新场景先删除 zcodecli-chat 测试/fixture、把 pane-run 提示词断言改成第二次 pane run，并新增 `zcodecli chat` 空格命令场景，再做 red→green。
working: 2026-09-16T18:39:00Z revised red 完成；已删 zcodecli-chat stub/fixture/旧场景测试，新增 cmd/zcode 统一 pane-run 断言。检查原始结果：`bash -n tests/smoke.sh && bash bin/qwb-test.sh fast && bash tests/smoke.sh` exit=1，末行 `SMOKE FAIL（4 项）`；失败精确为 cmd/zcode 仍走 `agent prompt`（两项调用/顺序）及非法模式文案仍列已取消的 zcodecli-chat（两项），而 `zcodecli chat` 空格命令未截断、300ms 超时、`-p` headless 拒绝均已 PASS。
working: 2026-09-16T18:43:00Z revised green 完成；已删除 zcodecli-chat 运行分支/清理逻辑/fixture，cmd 与 zcode 统一为 pane-run，检测 rename 后以第二次 `herdr pane run` 直打提示词；配置按后续 `工人名=` 边界保留空格命令。检查原始结果：`bash bin/qwb-test.sh fast && bash tests/smoke.sh` exit=0，末行 `SMOKE PASS`；§47 的 cmd 顺序、zcodecli chat 完整命令、无 agent prompt、300ms 超时、-p 拒绝、非法方式文案全部 PASS。下一阶段重建临时项目跑 cmd/zcode 真机 E2E。
working: 2026-09-16T18:50:00Z 真机首次复验发现 Command Code 长提示词由 pane run 写入输入框后仍保持 idle，手工补 Enter 后立即转 working；zcode 同一路径直接转 working/done。两者最终均写 `done: hello`，agent get 均 status=done，status 列出两窗口，wake --once exit=0，但 cmd 不能算自动通过。已清理 panes wA3:p8/p9 与临时项目（TEMP_CLEANUP=PASS），新增“直打后 300ms 内未转 working|done|blocked 才补 Enter”的 red：`bash tests/smoke.sh` exit=1，末行 `SMOKE FAIL（2 项）`，两项均精确缺 agent wait/条件补键。
working: 2026-09-16T18:54:00Z Command Code 提交时序 green 完成；pane-run 提示词后 `agent wait --until working|done|blocked --timeout 300`，仅未转态时 `pane send-keys enter`，避免自动批准 blocked 权限。检查原始结果：首次 fast 因未引用的 shell 保留字 `done` 被 shellcheck SC1010 拒绝（exit=1），改为 `--until "done"` 后 `bash bin/qwb-test.sh fast && bash tests/smoke.sh` exit=0，末行 `SMOKE PASS`；cmd 超时补键与 zcode 已转态不补键两条对照均 PASS。下一阶段跑第二次真机 E2E。
done: 2026-09-16T19:01:32Z worker-launch-modes 已实现并提交 d7b4948c18a62d74aa212c12bac266f11d8d2d0a。检查原始结果：`git diff --check && bash bin/qwb-test.sh full` exit=0，尾部 `SMOKE PASS` / `REVIEW-IDENTITY PASS` / `LINT PASS`；提交后 `git status --short --branch` 原样为 `## worker-launch-modes`（干净）。真机 E2E 临时项目 `/tmp/qwb-launch-e2e-final.YAh3nn`：dispatch 原样为 `dispatch: 2026-09-16T18:55:42Z worker=cmd agent=qwb-cmd-hello pane=wA3:pA dir=/private/tmp/qwb-launch-e2e-final.YAh3nn` 与 `dispatch: 2026-09-16T18:55:42Z worker=zcode agent=qwb-zcode-hello pane=wA3:pB dir=/private/tmp/qwb-launch-e2e-final.YAh3nn`，两票均原样追加 `done: hello`；`herdr agent get wA3:pA` 原始核心为 `{"agent":"cmd","agent_status":"done","name":"qwb-cmd-hello","pane_id":"wA3:pA"}`，`herdr agent get wA3:pB` 原始核心为 `{"agent":"zcode","agent_status":"done","name":"qwb-zcode-hello","pane_id":"wA3:pB"}`；`qwb-status.sh` 同时列出两票且最近行均 `done: hello`；`bash qwbuddy/bin/qwb-wake.sh --once --pane wA2:p4` exit=0，原样输出 `已叫醒：2099-02-02-cmd-hello.md state=running → pane wA2:p4` 与 `已叫醒：2099-02-02-zcode-hello.md state=running → pane wA2:p4`。cmd 提示词由 qwb-run 自动从 idle 提交到 blocked，之后其两次 shell 权限由执行者人工批准；zcode 无需补键。E2E tabs wA3:t8/wA3:t9 已关闭，随后 pane get 均 pane_not_found；临时项目已删除，TEMP_CLEANUP=PASS。
working: 2026-09-16T19:19:34Z 主控更正：此前手工计算 scenarios-fp 时多算了块尾换行（管道直喂 shasum，未经 $(…) 去尾），与 qwb-run/qwb-lint 的算法不一致；已按 lint 同款算法重算 scenarios-fp 与上一条修订记录的 new=，场景文本本身未改。教训记 tasks/lessons/
working: 2026-09-16T19:31:38Z 主控验货：worktree d7b4948 上独立跑 qwb-test.sh fast exit=0；tests/smoke.sh ×2 均 SMOKE PASS（402 断言，§47 新场景 16 项全 PASS）；qwb-lint.sh LINT PASS；tests/review-identity.sh exit=0。审读 diff（qwb-run.sh +138/-33，DECISIONS §26，QWBUDDY §4/§9，templates/config.sh）无异议。真机复验（临时项目 scratchpad/e2e-launch，用交付脚本真派）：zcode=pane-run:zcodecli chat 一次过，账本收到 done: hello；cmd 首次检测超时是新目录信任框（§1.7 一次性授权，非本票缺陷），接受后重派 → 检测/rename/直打/转 working 全通；Command Code 中途自崩重启未写入，pane run "继续" 后又只粘贴未提交、补 Enter 才写入 done: hello——证实 Enter 怪癖真实且实现里的条件补键必要。status.sh 列出两窗口，wake --once --dry-run 识别两未结项。临时项目与 pane w8Z:p2A/p29 已清（pane_not_found ×2）。附带发现：工人 tab 开在调用者 workspace 而非项目 workspace，另开票 worker-tab-workspace。结论：通过。
worktree: merged branch=worker-launch-modes tag=-
