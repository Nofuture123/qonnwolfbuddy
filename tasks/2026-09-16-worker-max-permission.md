# 任务书：工人与审核者一律以最高权限启动 CLI（`QWB_WORKER_ARGS`）

```
任务 id:  worker-max-permission
state:    running
scenarios-fp: a5c503bc3c450ec1b76801fa5b8e568f4069913e
来源:     Rocky 2026-09-16「所有工人和审核全部按最高权限开启 cli」
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1） → <待派>
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
