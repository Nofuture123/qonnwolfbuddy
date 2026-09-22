# 票②正式独立审核 r1

结论：**PASS**（Standards 0 个阻断问题；Spec 0 个阻断问题）。审核者为现有 Herdr pane `wF2:pG`；本轮未递归派发、未改候选源码或提交。

## 冻结范围

- 唯一需求：`tasks/2026-09-22-qwb-simplify-ledger-parsing.md`；执行证据：`docs/reviews/2026-09-22-qwb-simplify-ledger-parsing-execution.md`。
- 候选 worktree：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-ledger-parsing`；HEAD `7ddb341b5873d7e70b6671c1420e4a75077e15d0`；`git diff --binary | shasum -a 256` 为 `b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2`，与交接值一致。
- `git status --porcelain=v1` 仅有六个已修改文件：`bin/qwb-lib.sh`、`bin/qwb-run.sh`、`bin/qwb-wake.sh`、`bin/qwb-status.sh`、`bin/qwb-lint.sh`、`bin/qwb-worktree.sh`；无候选新文件。六文件 SHA-256 均与执行证据第 27–32 行相同。`git diff --check` rc=0。

## Standards

1. **纯读取抽取与原语义：PASS。** `bin/qwb-lib.sh:8-24` 的首个 state、末条规格事件、场景 awk 与基线原表达式逐字对应。status/lint/wake/worktree 各自仍判断 state 存在性和合法值；run/status 仍分别处理规格疑点的拒发与展示，status 继续屏蔽读取 stderr；run/lint 仍分别决定缺 fp 拒绝与警告。`bin/qwb-run.sh:483-519,640-655` 的指纹修订及派发前写事务未改变。未见本轮引入的重复实现、额外抽象或作用域越界。

## Spec

2. **三场景差分与负例：PASS。** 独立重跑 `QWB_TEST_ROOT="$PWD" bash /tmp/qwb-ledger-parsing-diff.sh`，rc=0，`DIFF PASS 39 comparisons`。脚本从冻结 HEAD 取基线脚本，对九类夹具比较公开 CLI stdout、stderr、rc，逐次检查账本哈希，并比较场景块原始字节及 SHA-1。脚本第 47–58 行另检查非法/空 state 与篡改时 lint rc=1、未决疑点/篡改/缺 fp 时 run 拒发、旧票缺 fp 时 lint 警告；不是仅比较两个实现同错。独立最小反例对 `working/done/blocked/needs-decision/dispatch/not-sent/wake/worktree/scenarios-fp` 九种尾部记录逐一验证基线与候选场景块字节相同、尾行不进入块，rc=0。`spec-defect` 后普通 `done/working` 仍触发 run rc=1。
3. **安装和缺库：PASS。** `bin/qwb-init.sh:54-59` 的现有 `qwb-*.sh` 安装循环覆盖新库及调用者。独立隔离临时项目的初装、升级各运行安装副本 status rc=0、lint rc=0 且保留旧票缺 fp 警告、run 预检 rc=1 且给出缺 fp 拒发诊断；升级前后用户 config 字节相同。单独将 lint 放在无库目录运行，rc=1，stdout 为空，stderr 明示“找不到共享库”“安装副本不完整”。执行者的 source 检查在独立重跑的差分脚本中通过：无 stdout/stderr、无 shell 选项变化。所有复核使用临时项目与假 Herdr，没有真实派发或 pane 副作用。

## 证据口径与边界

- 执行证据第 4 行把首个 `state:` 的重复读取写成“五个入口”；候选和基线实为 **status、lint、wake、worktree 四个入口**。run 的本轮共享调用是规格事件与场景块。此处校正描述，不把旧任务书背景表述重开为代码缺陷。主账本第 69 行的“35 组”也应以脚本实际输出的 **39 组公开 CLI 比较**为准。
- 首次独立安装反例把用户标记误写为未使用配置变量，lint 按既有死配置规则 rc=1；改为注释后同一初装/升级检查通过。该夹具错误不归因于候选。
- `bash bin/qwb-test.sh fast` rc=0 是执行者记录，本审核未重跑；主控的 `full` 不属于本审核。未实测真实 Herdr 派发、真实宿主组合或成功派发路径，因此本 PASS 仅覆盖冻结的纯读取候选及本票三场景的指定证据边界。

**REVIEW_QWB_SIMPLIFY_LEDGER_PARSING_R1 PASS**
