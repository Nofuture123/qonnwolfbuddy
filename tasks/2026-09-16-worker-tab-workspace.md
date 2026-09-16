# 任务书：工人 tab 开在项目的 workspace，不是主控所在的 workspace

```
任务 id:  worker-tab-workspace
state:    running
scenarios-fp: 9eb0465201721561334c0f2744ab24b823544730
来源:     Rocky 2026-09-16「母仓我也没看到有 herdr 窗口」——主控在 wA2（qonnwolf-sites）给母仓 wA3 派活，工人 tab 开在了 wA2
派发:     主控 claude-opus-5（Claude Code，pane wA2:p1） → cmd（改派，原 pi）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-worker-tab-workspace.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-tab-workspace
分支:     worker-tab-workspace
前置:     worker-launch-modes 已合并 main（本票改 qwb-run.sh 同一段）；与 watch-invisible 串行（同改 qwb-wake.sh / smoke.sh / config.sh）
```

## 0. 背景与范围

**缺陷**：`qwb-run.sh` 与 `qwb-wake.sh --ensure` 调 `herdr tab create` 时不传 `--workspace`，herdr 把 tab 落在**调用者所在** workspace（`HERDR_WORKSPACE_ID`）。主控与项目同 workspace 时无感；主控跨项目派活（今天：主控在 wA2 给 wA3 的项目派）时，工人窗口出现在主控身边，项目的 workspace 里什么都看不到。2026-09-16 实测：`worker-launch-modes` 工人开在 `wA2:t3`；两次 E2E 临时项目的工人开去了 `w8Z`。

**已核实的 herdr 事实**：
- `herdr tab create --workspace <WORKSPACE_ID>` 存在。
- `herdr workspace list` 每项有 `workspace_id`、`label`，**部分**有 `worktree.repo_root`（w8Z 有，wA2/wA3 没有——取决于 workspace 怎么建的），所以按 cwd 匹配不可靠，只能当次选。

**做法**（解析顺序，取第一个命中）：
1. `config.sh` 新键 `QWB_WORKSPACE=""`——项目声明自己的 herdr workspace id（如 `wA3`）。非空即用；herdr 查不到该 id → **拒绝派发**并提示改 config（不静默回退到别处）。
2. 空 → `herdr workspace list` 里 `worktree.repo_root` 物理路径 == 项目根物理路径的那一个（多于一个 → 取 `focused` 的，再不行取第一个并 stderr 警告）。
3. 都没有 → 现状（调用者 workspace），但 **stderr 打一行警告**「工人 tab 开在调用者 workspace <id>，项目未声明 QWB_WORKSPACE」。

抽成一个函数 `resolve_workspace()` 放在 `qwb-run.sh`（`qwb-wake.sh --ensure` 用同款逻辑；两处不能各写一份——若要共享，允许新建 `bin/qwb-lib.sh` 被两者 `source`，并在 §9 表注明「库文件，不直接运行」，lint「文档承诺脚本」检查按需调整）。

`qwb-run.sh` 的 `--pane` 复用路径不受影响（pane 已定）。`QWBUDDY.md` §1 第 6 步旁加一句：主控开局把 `HERDR_WORKSPACE_ID` 写进 `QWB_WORKSPACE`（与写 `QWB_CONTROLLER_PANE` 同一步），跨项目派活的主控则手工填项目的 workspace id。

**白名单**：`bin/qwb-run.sh`、`bin/qwb-wake.sh`（仅 `--ensure` 建 tab 那一处）、`bin/qwb-lib.sh`（可选新建）、`bin/qwb-lint.sh`（仅当新增库文件需要）、`templates/config.sh`、`templates/QWBUDDY.md`、`tests/smoke.sh`、`tests/fixtures/herdr/`（新增 `workspace-list*.json` 真录）、`docs/DECISIONS.md`。**不许动**：`bin/qwb-status.sh`、`bin/qwb-lock.sh`、`bin/qwb-worktree.sh`、`bin/qwb-init.sh`、`bin/qwb-test.sh`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### 显式声明优先

Given `QWB_WORKSPACE="wX"`，stub `workspace list` 含 `wX`；调用者 `HERDR_WORKSPACE_ID=wY`
When  `qwb-run.sh --task disp --worker codex --here`
Then  stub 日志的 `tab create` 带 `--workspace wX`；stderr 无警告；退出码 0

### 显式声明但 herdr 查不到则拒绝（失败路径）

Given `QWB_WORKSPACE="wZ"`，stub `workspace list` 不含 `wZ`
When  `qwb-run.sh --task disp --worker codex --here`
Then  在任何副作用（锁、worktree、tab、账本写）之前退出非 0；stderr 指出 `wZ` 不存在并提示改 `QWB_WORKSPACE`；任务书无新增 `dispatch:` 行；stub 日志无 `tab create`

### 未声明：按 repo_root 匹配

Given `QWB_WORKSPACE=""`，stub `workspace list` 里恰有一项 `worktree.repo_root` 等于项目根（stub 用 `$TMP` 真路径，含 /tmp→/private/tmp 符号链接差异）；调用者在 `wY`
When  `qwb-run.sh --task disp --worker codex --here`
Then  `tab create` 带 `--workspace <那一项的 id>`；不是 `wY`

### 未声明且无匹配：回退调用者 workspace 并警告

Given `QWB_WORKSPACE=""`，stub `workspace list` 无 `repo_root` 匹配；`HERDR_WORKSPACE_ID=wY`
When  `qwb-run.sh --task disp --worker codex --here`
Then  `tab create` 带 `--workspace wY`（或不带——两者等价，断言最终 pane 落在 wY）；stderr 恰有一行含「未声明 QWB_WORKSPACE」；退出码 0

### 多个 repo_root 匹配取 focused（边界）

Given 两项 `repo_root` 都匹配，其中一项 `focused: true`
When  `qwb-run.sh --task disp --worker codex --here`
Then  取 `focused` 的那项；stderr 无警告。若都不 focused → 取第一项且 stderr 警告「多个 workspace 匹配」

### --ensure 同款

Given `QWB_WORKSPACE="wX"`
When  `qwb-wake.sh --ensure`
Then  值守 tab 的 `tab create` 带 `--workspace wX`；`.watch` 记录 `workspace=wX`

### workspace list 查询失败（失败路径）

Given stub `workspace list` 返回 io_error
When  `qwb-run.sh --task disp --worker codex --here`（`QWB_WORKSPACE` 为空）
Then  退出非 0，stderr 含原始错误；任何副作用之前；无 `dispatch:` 行

### lint 认新键与库文件

Given 实现完成
When  `bash bin/qwb-lint.sh`
Then  全部 PASS（`QWB_WORKSPACE` 被 bin/ 引用；若新增 `qwb-lib.sh`，§9 表有其行）

### 真机 E2E（执行者跑，主控复验）

Given 临时 git 项目，`QWB_WORKSPACE` 填一个**不是**执行者所在的 workspace id（用 `herdr workspace list` 挑现有的，或 `herdr workspace create` 新建一个临时的）
When  从执行者自己的 pane 派发一张只写 `done: hello` 的票（工人任选）
Then  `herdr agent get` 显示工人 `workspace_id` == 所填 id；临时项目、tab、临时 workspace 用完即清（TEMP_CLEANUP=PASS）

## 2. 硬约束

- 超时一律毫秒；只用 Herdr；零通知使用者。
- `workspace list` 响应用 `perl -MJSON::PP` 解析（与 `tab create` 同款，R2-M2 类型防御：id 必须是非空 JSON 字符串）。
- stub 响应来自 `tests/fixtures/herdr/` 真录，不硬编码 JSON。
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

- 不改 herdr；不给 herdr 提需求。
- 不动 `--pane` 复用路径与 pane-run 启动逻辑。
- 不做「自动建 workspace」——找不到就按上面三级规则处理。
dispatch: 2026-09-16T19:31:57Z worker=pi agent=qwb-worker-tab-workspace pane=wA3:pC dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-tab-workspace
working: 2026-09-16T19:40:53Z worker=pi 阶段=规格已读/真录已取 实现开始：真录 workspace list 已存 tests/fixtures/herdr/workspace-list.json；计划=qwb-lib.sh 共享 resolve_workspace + run/wake ensure 接线 + config/QWBUDDY/DECISIONS 文档 + smoke 场景
working: 2026-09-16T19:45:24Z 主控改派：Rocky 指定 cmd 为快档首选，pi（wA3:pC）在读票阶段停下并关窗，worktree 保留原样（如有 pi 的改动见上一行 git status）
dispatch: 2026-09-16T19:45:36Z worker=cmd agent=qwb-worker-tab-workspace pane=wA3:pD dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-tab-workspace
working: 2026-09-16T19:46:54Z 主控重派：Rocky 要求 cmd 以最高权限启动；wA3:pD 关窗，改动回滚（保留真录 fixture），改用 `cmd --yolo --trust` 重开（--trust 同时消掉新目录信任框）
dispatch: 2026-09-16T19:46:54Z worker=cmd agent=qwb-worker-tab-workspace pane=wA3:pE dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-tab-workspace
