# 任务书：工人与审核者一律以最高权限启动 CLI（`QWB_WORKER_ARGS`）

```
任务 id:  worker-max-permission
state:    verified
scenarios-fp: a5c503bc3c450ec1b76801fa5b8e568f4069913e
来源:     Rocky 2026-09-16「所有工人和审核全部按最高权限开启 cli」
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1） → cmd（--yolo --trust）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-worker-max-permission.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-max-permission
分支:     worker-max-permission
前置:     worker-tab-workspace 合并 main 后再派（同改 qwb-run.sh 启动段 / smoke.sh / templates/config.sh）
```

## 0. 背景与范围

**现状**：`qwb-run.sh` 起工人是裸命令——`herdr agent start <NAME> --kind <工人> --pane <PANE>` 不传任何 agent 参数；`pane-run:<命令行>` 则是配置里写什么跑什么。结果工人在默认权限模式下跑，每个写文件/跑命令都可能弹审批，没人在窗口里点，工人就卡死（2026-09-16 主控手工派 cmd 时先卡信任框、后 Rocky 要求改 `cmd --yolo --trust` 重开）。

**决定（Rocky）**：工人与审核者一律最高权限启动。它们在隔离 worktree 里干活、产物由主控验收，审批提示只会卡流程不会加安全。

**已核实的各 CLI 参数（2026-09-16 `--help` 实测）**：

| 工人 | 最高权限参数 | 备注 |
|---|---|---|
| codex | `--dangerously-bypass-approvals-and-sandbox` | 等价 `-s danger-full-access -a never`（母仓审核票用过） |
| claude | `--dangerously-skip-permissions` | |
| devin | `--permission-mode dangerous` | "dangerous" auto-approves all tools |
| omp | `--auto-approve` | Auto-approve all tool calls |
| pi | `--approve` | 只有"信任项目文件"；pi 是否还有工具审批提示，执行者真机核实一次并记账 |
| cmd | `--yolo --trust` | pane-run 命令行里直接写；`--trust` 同时消掉新目录信任框 |
| zcode | 无需 | `zcodecli chat` 本身 yolo 模式 |

**做法**：

- `config.sh` 新键 `QWB_WORKER_ARGS`，格式与 `QWB_WORKER_LAUNCH` 同款（`工人名=<参数串>`，值可含空格，遇下一个 `工人名=` 才结束；复用同一解析函数，不要再写一份）。`templates/config.sh` 默认值填上表全部 herdr-kind 工人：
  ```bash
  QWB_WORKER_ARGS="codex=--dangerously-bypass-approvals-and-sandbox claude=--dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve pi=--approve"
  ```
  **默认工人表同步扩为** `QWB_WORKERS="codex pi claude devin omp"`（2026-09-16 主控处置 spec-defect：ARGS 默认串里的名字必须全部在默认工人表里，否则 `devin=`/`omp=` 会并进 claude 的值）。
  pane-run 工人的参数写在 `QWB_WORKER_LAUNCH` 的命令行里（如 `cmd=pane-run:cmd --yolo --trust`），`QWB_WORKER_ARGS` 里给 pane-run 工人配了值 → **拒绝派发**并提示写到 LAUNCH 命令行里（一个工人的启动参数只能有一处）。
- `qwb-run.sh` herdr 模式：`herdr agent start <NAME> --kind <工人> --pane <PANE> --timeout <ms> -- <参数串按空格切词>`。参数串为空 → 不加 `--`。
- `templates/QWBUDDY.md` §4 派发流程加一句「工人与审核者一律最高权限启动（`QWB_WORKER_ARGS` / pane-run 命令行）」；§10 硬规矩不加条（这是配置默认值，不是禁令）。
- `docs/DECISIONS.md` 加一条：为什么最高权限（隔离 worktree + 主控验收 = 审批无增益）；`QWB_WORKER_ARGS` 与 `QWB_WORKER_LAUNCH` 分两键的理由（一个管"起什么"，一个管"带什么参数"，herdr 模式起法固定只差参数）。
- `qwb-init.sh` **不**动：新装项目拿模板默认值；已装项目由主控手工往 `config.sh` 加键（`qwb-init` 不覆盖已有 config.sh 是既定行为）。

**白名单**：`bin/qwb-run.sh`、`templates/config.sh`、`templates/QWBUDDY.md`、`tests/smoke.sh`、`tests/fixtures/herdr/`（如需 `agent-start` 带参数的真录）、`docs/DECISIONS.md`。**不许动**：其他 `bin/*`、`templates/roles/*`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### herdr 模式带参数

Given `QWB_WORKER_ARGS="codex=--dangerously-bypass-approvals-and-sandbox claude=--dangerously-skip-permissions"`
When  `qwb-run.sh --task disp --worker codex --here`（stub herdr）
Then  stub 日志的 `agent start` 行以 `-- --dangerously-bypass-approvals-and-sandbox` 结尾；`agent prompt` 照常；退出码 0

### 参数含空格按词切

Given `QWB_WORKER_ARGS="devin=--permission-mode dangerous omp=--auto-approve"`
When  `--worker devin`
Then  `agent start` 行以 `-- --permission-mode dangerous` 结尾（两个词），不含 `omp=`；`--worker omp` 时以 `-- --auto-approve` 结尾

### 未配置的工人不加 --

Given `QWB_WORKER_ARGS` 为空或不含 `codex=`
When  `--worker codex`
Then  `agent start` 行与现状字节一致（无 `--`）；退出码 0

### pane-run 工人在 ARGS 里配了值则拒绝（失败路径）

Given `QWB_WORKER_LAUNCH="cmd=pane-run:cmd"`，`QWB_WORKER_ARGS="cmd=--yolo"`
When  `--worker cmd`
Then  在任何副作用（锁、worktree、tab、账本写）之前退出非 0；stderr 提示把参数写进 `QWB_WORKER_LAUNCH` 的命令行；任务书无新增 `dispatch:` 行

### pane-run 命令行带权限参数照常且过 headless 检查

Given `QWB_WORKER_LAUNCH="cmd=pane-run:cmd --yolo --trust"`
When  `--worker cmd`
Then  stub 日志 `pane run <pane> cmd --yolo --trust`；不被 headless 检查误拒；退出码 0

### 参数里混入 headless 形式则拒绝（失败路径）

Given `QWB_WORKER_ARGS="claude=--dangerously-skip-permissions -p"`
When  `--worker claude`
Then  在任何副作用之前退出非 0；stderr 说明禁 headless（与 pane-run 同一条检查，`-p|--print|--exec|exec`）；无 `dispatch:` 行

### 模板默认值可被 lint 与 source 接受

Given `templates/config.sh` 含默认 `QWB_WORKER_ARGS`
When  `bash -n templates/config.sh && bash bin/qwb-lint.sh`
Then  两者 exit 0；「config 无死键」PASS

### 真机 E2E（执行者跑，主控复验）

Given 临时 git 项目装 QW buddy，`config.sh` 用模板默认 `QWB_WORKER_ARGS`
When  分别以 `--worker codex` 与 `--worker claude` 真派一张「往主账本追加 `done: hello` 并 `touch e2e-touch.txt`」的票（写文件是为了触发审批点）
Then  两个工人**无审批提示**直接完成：账本有 `done: hello`、worktree 里有 `e2e-touch.txt`；执行者贴 `herdr pane read` 原文（须能看到无审批框）与 `herdr agent get`；pi 若可用也跑一次并记录是否弹审批；临时项目与 pane 用完即清（TEMP_CLEANUP=PASS）

## 2. 硬约束

- 超时一律毫秒；只用 Herdr；零通知使用者；禁 headless（参数串同样过 `-p|--print|--exec|exec` 检查）。
- 参数按空格切词，不做 shell 引号解析（够用；需要带空格的单个参数时用 pane-run 命令行）。
- 不改 `dispatch:` 行格式（参数不写进 dispatch 行；要审计看 config.sh）。
- shellcheck 干净。

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

- 不改 `qwb-init.sh`（已装项目的 config 由主控手工补键）。
- 不给主控自己加权限参数——主控是使用者自己起的会话，不归 QW buddy 管。
- 不引入 shell 引号解析器。
dispatch: 2026-09-16T20:10:40Z worker=cmd agent=qwb-worker-max-permission pane=wA3:pG dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-max-permission
working: 2026-09-16T00:00:00Z 读完票与点名的 QWBUDDY.md/执行者.md/lessons.md；已核实 herdr agent start 支持 [-- AGENT_ARG...]；环境有 codex/claude/pi/devin/omp/cmd，主控 pane=wA3:pG ws=wA3。开始改 qwb-run.sh 解析段与 templates/config.sh。
done: 实现完成并全门绿（白名单内 5 文件：bin/qwb-run.sh、templates/config.sh、templates/QWBUDDY.md、docs/DECISIONS.md、tests/smoke.sh；未动 qwb-init.sh / templates/roles/* / 其他 bin/*）。
working: 检查原始结果：① `bash bin/qwb-test.sh fast` → rc=0；② `bash bin/qwb-test.sh full` → rc=0，**463 PASS / 0 FAIL**（SMOKE PASS + REVIEW-IDENTITY PASS + LINT PASS）；③ `tests/smoke.sh` 新增 §49 共 22 条断言全 PASS：herdr 带参数以 `-- <参数>` 结尾且 `agent prompt` 照常、含空格参数按词切（devin 得两个词且不串入 `omp=`）、未配置/未列出则该工人 `agent start` 行与现状字节一致（无 `--`）、pane-run 工人在 ARGS 里配值→拒绝且零副作用、pane-run 命令行带 `--yolo --trust` 照常且不被误判 headless、ARGS 混入 `-p|--print|--exec|exec` 四种形式逐个拒绝且同表其他工人不受影响、模板默认值可被 source 与 lint（「config 无死键」PASS）；④ 反转验证 4 轮（改坏实现→新断言必须变红，跑完从备份恢复并以 shasum 校验字节一致）：拆掉 `--` 追加→4 条 FAIL、去掉 pane-run 冲突检查→1 条 FAIL、去掉 ARGS headless 检查→4 条 FAIL、解析退化成「只取最后一项」→3 条 FAIL。
working: 真机 E2E（临时 git 项目 + 模板默认 QWB_WORKER_ARGS + 默认隔离副本派发，票 §1 场景；证据文件在会话 scratchpad：ev-*/ev2-*.txt|json|log；临时项目与 pane 用完即清，TEMP_CLEANUP=PASS）：**codex** 首派 rc=1（`herdr agent start` 回 `agent_not_ready`「blocked during startup」——codex 在 worktree 这个新目录上先弹「Do you trust the contents of this directory?」且该框**不被** `--dangerously-bypass-approvals-and-sandbox` 跳过，`agent_status=blocked`）；按 QWBUDDY §1.7 一次性人工授权 + 补发提示词后 **38s 完成**：账本 `done: hello`、worktree `e2e-touch.txt`(6B)、pane 原文 `│ permissions: YOLO mode`、无审批框、`herdr agent get` → `agent=codex agent_status=done`。**claude** 见下条 spec-defect；补齐工人表自洽后复测：按 §1.7 预授权（注意信任框默认高亮是「No, exit」，按 Enter 会**直接退出 claude**，须 `down`+`enter` 选「Yes, I trust this folder」）→ **dispatch rc=0，11s 完成**：账本 `done: hello`、worktree `e2e-touch.txt`(46B)、pane 原文 `⏵⏵ bypass permissions on (shift+tab to cycle)`、无审批框、dispatch 响应 `"argv":["claude","--dangerously-skip-permissions"]`。**pi**（票 §0 要求核实的那条）→ **dispatch rc=0，20s 完成**：账本 `done: hello (check: ls e2e-touch.txt -> exists in worktree dir)`、worktree `e2e-touch.txt`(16B)、dispatch 响应 `"argv":["pi","--approve"]`、pi 自述「全程无审批提示」、无需预授权（`--approve` 只授「信任项目文件」，真机未见工具审批弹窗）。
blocked:  spec-defect: 票 §0 的默认值组合不自洽——默认 `QWB_WORKERS="codex pi claude"` 不含 `devin`/`omp`，而票 §0 指定的默认 `QWB_WORKER_ARGS` 串里含 `devin=`/`omp=`；按票 §0 自己也规定的语义（「值可含空格，**遇下一个 `工人名=`** 才结束」，工人名取自 `QWB_WORKERS`），这两项不会被当成新项，而是并进上一个值：claude 的参数串变成 `--dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve`。反例两条（都是纯模板默认、不碰 config.sh）：① 仓库自带真录 fixture 替身（复现脚本 scratchpad/proof-defaults.sh）：`herdr agent start qwb-claude --kind claude --pane w93:p7 --timeout 30000 -- --dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve`，同表 codex=`-- --dangerously-bypass-approvals-and-sandbox`、pi=`-- --approve` 均正确；② 真机 pane 回显同一串（pane 命令行 `claude --dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve`）。继续照做会错在哪：票 §1 的真机 E2E 场景正是「临时项目用模板默认值 + `--worker claude`」，会给 claude 传两个废词（真机已复现），即**装出来的默认项目里 claude 工人不可用**，而 codex/pi（首项/末项）不受影响、单测若只覆盖 codex 看不出问题。三个候选收敛方向（不动语义、由主控裁决）：(a) 默认 ARGS 串只列默认工人表里的名字；(b) 默认工人表补上 `devin omp`（本执行者为跑通 claude 腿临时这么做过，已如实记录）；(c) 解析后加一道 fail-closed 校验：值里出现 `名字=` 而该名字不在 `QWB_WORKERS` 时拒绝派发并指名改配置。实现侧**未擅自改语义/未改默认值**，票内其余条款全部按原样落地。
working: 交付已提交到分支 worker-max-permission：**151bf2ac83cb8fe5a164c671957d23b0161d9807**（工作树干净，5 文件 +264/−20）。提交后复跑稳定性证据：`bash tests/smoke.sh` 连跑两次均 rc=0、各 441 PASS / 0 FAIL（无「首次失败后成功」用例）；`bash bin/qwb-test.sh fast` rc=0。本票账本行只追加、未改他人行、未动 state: 字段（`state: running` 原样）。等主控处置上面那条 spec-defect。
working: spec-resolved: spec；2026-09-16T20:54:50Z 主控核对：疑点成立——票 §0 默认 ARGS 串含 devin=/omp= 而默认 QWB_WORKERS 不含二者，按"遇下一个工人名=才结束"语义会并进 claude 的值，执行者两条反例（fixture 替身 + 真机 pane 回显）均复现。处置取 (b)：templates/config.sh 默认 QWB_WORKERS 扩为 "codex pi claude devin omp"（Rocky 实际在用这五家 herdr-kind 工人；已改票 §0「做法」段）。不取 (c)：值里合法参数本身可能含 name=（如 codex -c model=o3），按"名字不在工人表就拒绝"会误杀。不取 (a)：默认串少列 devin/omp 等于装出来的项目一加这两家就裸跑。验收场景块未改，指纹不变。请执行者：改 templates/config.sh 默认 QWB_WORKERS，用纯模板默认再跑一次 claude 腿 E2E 取证，然后 done。附带发现（不在本票）：codex/claude 的新目录信任框不被权限参数跳过，每个新 worktree 都要人按一次——另开票处理预授权。
done: spec-resolved 处置已落地（取 (b)）：`templates/config.sh` 默认 `QWB_WORKERS` 扩为 `"codex pi claude devin omp"`（并在工人表下写明它同时是 `QWB_WORKER_ARGS`/`QWB_WORKER_LAUNCH` 的「工人名=」边界表、两条默认值必须自洽；能力档注释补一行说明 devin/omp 亦在默认表内）；`tests/smoke.sh` §5 默认工人表断言跟到新值、§15「报错列出全部合法工人名」改断言完整五个名字、新增 §49h「默认值自洽」回归门（默认 ARGS 表里每个「工人名=」都必须在该串所属的默认工人表里）；`docs/DECISIONS.md` §28 把「格式的隐含耦合」一段从「待主控裁决」改为记录处置结论 (b) 与被否掉的 (a)/(c)（(c) 会误杀 `codex -c model=o3` 这类合法参数）。**验收场景块未动（scenarios-fp 不变）**，账本只追加、未改他人行、未动 `state:`。
working: 本轮检查与原始结果：① `bash bin/qwb-test.sh fast` → rc=0；② `bash bin/qwb-test.sh full` → rc=0，**464 PASS / 0 FAIL**（SMOKE PASS + REVIEW-IDENTITY PASS + LINT PASS）；③ `bash tests/smoke.sh` 连跑两次均 rc=0、各 **442 PASS / 0 FAIL**（无「首次失败后成功」用例）；④ **确定性复证**（纯模板默认、config.sh 一字节未改、仓库自带真录 fixture 做替身）：codex → `-- --dangerously-bypass-approvals-and-sandbox`、claude → `-- --dangerously-skip-permissions`（修复前为 `--dangerously-skip-permissions devin=--permission-mode dangerous omp=--auto-approve`）、devin → `-- --permission-mode dangerous`、omp → `-- --auto-approve`、pi → `-- --approve`；⑤ **反转验证**：默认工人表删回 `"codex pi claude"` → 3 条断言变红（`FAIL 默认 ARGS 表含不在默认工人表里的名字（会被并进上一个值）: devin omp` 等），恢复后 shasum 字节一致（`55cc6ca8…`）。
working: **真机 claude 腿 E2E（纯模板默认，票 §1 场景）**：临时 git 项目只跑 `qwb-init.sh`（`QWB_WORKERS="codex pi claude devin omp"`、默认 ARGS、`QWB_AGENT_START_MS=30000`、`QWB_WORKSPACE` 空，全部未改）→ dispatch #1 rc=1（claude 首启把信任框卡在 `agent start` 上，`agent_not_ready`）→ 按 §1.7 一次性授权（信任框默认高亮是「No, exit」，须 `down`+`enter` 选「Yes, I trust this folder」）→ 关掉该 tab → **dispatch #2 rc=0**（隔离副本幂等复用），**11s 完成**：账本 `done: hello`、worktree `.worktrees/claude/e2e-touch.txt`(31B)、dispatch 响应 `"argv":["claude","--dangerously-skip-permissions"]`、pane 原文 `⏵⏵ bypass permissions on (shift+tab to cycle)` 且该 pane 全文**无审批/信任框字样**、`herdr agent get` → `agent=claude name=qwb-claude agent_status=working`。证据文件在会话 scratchpad（`ev3-claude-*`）。临时项目与 pane 用完即清：TEMP_CLEANUP=PASS（wA2/wA3 只剩别人的 p1/p3/p6 与我自己的 pG）。
done: 交付提交：**41005216588299033aa43ac4cf02d6f6a2982a36**（前一提交 151bf2ac83cb8fe5a164c671957d23b0161d9807），分支 `worker-max-permission`，工作树干净（本轮 3 文件 +27/−4）。本票实现、门、真机取证齐备，等主控验货。
wake: 2026-09-21T19:24:16Z state=running fp=0750f45e9d53a92313231c79c06db104303f4678
working: 2026-09-21T19:30:00Z 主控（claude-opus-5，pane wF2:p3）验货：分支 4100521 两提交在工作树内 fast 门 rc=0、smoke 442 PASS/0 FAIL，但分支基线是 d93f74a，落后 main（dd7daf7，其间合入 jev-dispatch 与 brief-include），`git merge-tree` 实测 tests/smoke.sh 冲突（双方都在文件尾加了「== 49.」节）。**返工（改派 pi / glm-5.3-flash）**：在本 worktree 内 `git rebase main`（或 merge main），解决 tests/smoke.sh 冲突——两边的新节都保留、本票的节改号为「== 51.」（main 上 49=JEV、50=brief-include）；不改任何实现语义、不改场景块；重跑 `bash bin/qwb-test.sh fast` 与 `bash tests/smoke.sh` 两次，PASS 数应 = 453 + 本票新增断言数，把原始结果与新 HEAD sha 写进 done: 行。
dispatch: 2026-09-21T19:25:07Z worker=pi agent=qwb-worker-max-permission pane=wF2:p5 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-max-permission
wake: 2026-09-21T19:26:16Z state=running fp=13518618244b1b0b3a02c57733d8453a88dbd3bd
done: 2026-09-21T20:05:00Z 返工完成：在 worktree 内 `git rebase main`（dd7daf7），tests/smoke.sh 冲突按令解掉——main 的 == 49.(JEV) 与 == 50.(brief-include) 原样保留，本票节改号为 == 51.（内部用例注释 49a-49g→51a-51g、spec-resolved 回归门 49h→51h），实现语义零改动、验收场景块零改动；bin/qwb-run.sh 与 templates/QWBUDDY.md 由 git 自动合并（复核确认 auto 派工块与 QWB_WORKER_ARGS 解析共存、合并结果相对 main 的净差异仍只限白名单 5 文件）。检查与原始结果：① `bash bin/qwb-test.sh fast` → rc=0（bash -n 全部 bin/*.sh+tests/smoke.sh、shellcheck 全部 bin/*.sh，静默门）；② `bash tests/smoke.sh` 连跑两次 → 均 rc=0、各 **477 PASS / 0 FAIL**（= main 基准 453 PASS + 本票新增 24 条断言：51 节 23 条 + lint「QWB_WORKER_ARGS 是活键」1 条；两次输出差异仅为 mktemp 随机路径）；③ `bash bin/qwb-test.sh full` → rc=0，**499 PASS / 0 FAIL**（SMOKE PASS + REVIEW-IDENTITY PASS + LINT PASS）；④ 对拍核实：临时 worktree 跑 main@dd7daf7 smoke = 453 PASS / 0 FAIL，与本分支 PASS 列表做差集（剔除路径不同的同款断言），新增项恰为本票 24 条，无一条本票断言丢失或被 main 覆盖。新 HEAD sha=**d10b0d6374b5baa3409052082a43dfee450a7eb8**（d27a787 feat + d10b0d6 fix，已 rebase 到 dd7daf7 之上），工作树干净。临时对拍 worktree 已删（git worktree remove + prune）。
wake: 2026-09-21T19:38:20Z state=running fp=40cba8220710d0cf28ae8af199428ebff970007c
working: 2026-09-21T19:40:00Z 主控验货（不采信自述，独立复跑于 worktree d10b0d6）：`qwb-test.sh fast` rc=0；`tests/smoke.sh` rc=0、477 PASS / 0 FAIL；`qwb-lint.sh` LINT PASS；`git diff main --stat` 仅白名单 5 文件（+290/−23）；反转验证：把 ARGS headless 拒绝的 exit 1 改成空操作 → 4 条断言变红（-p/--print/--exec/exec），恢复后 shasum 64798ea… 与备份一致、工作树干净；main 是分支祖先可 fast-forward。结论：通过，state → verified，fast-forward 合并。
worktree: merged branch=worker-max-permission tag=-
