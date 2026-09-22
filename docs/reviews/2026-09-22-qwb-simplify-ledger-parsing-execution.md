# ② 账本纯读取提取执行证据

- 执行基线：`7ddb341b5873d7e70b6671c1420e4a75077e15d0`；执行工作树 `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-ledger-parsing` 起始干净。① `239c2ce` 已包含在基线。本次未提交、未推送。
- 原问题仍存在：基线中五个入口重复读取首个 `state:`，run/status 重复取末条 spec 相关事件，run/lint 重复同一段场景 awk。
- 旧票缺 `scenarios-fp:` 策略：run 遇 `dispatch:` 默认拒发（显式 `--accept-new-scenarios` 另行处理）；lint 只警告；status/wake/worktree 不以场景 fp 限制读取。此次仍由各调用方执行原策略。规格疑点读取错误的 stderr 也保留调用方差异：run 可见，status 屏蔽。

## 候选内容

唯一实现候选文件：

```text
bin/qwb-lib.sh
bin/qwb-run.sh
bin/qwb-wake.sh
bin/qwb-status.sh
bin/qwb-lint.sh
bin/qwb-worktree.sh
```

三段共享函数只读：首个 state 值、最后一个 spec 相关事件、场景块 awk。state 字段存在性、合法值和拒绝/警告仍由入口决定；`scenarios-fp` 计算、冻结和事务写入没有改动。未新增文件或安装步骤；现有 init 会覆盖安装副本的 `qwb-lib.sh`。无实现提交号，候选以基线加下列 diff 哈希标识。

`git diff --binary | shasum -a 256`：`b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2`

候选文件 SHA-256：

```text
42a54aa86606fe7f70c605efa4d8d5a6ad269c874568c66141b64424804cab26  bin/qwb-lib.sh
ad1502450b984ce3d54e23b081ebdfc229e4c5a8388e081e6b1fddc2bcb02e1c  bin/qwb-run.sh
98eddd9aa4074f24457156aa48ffc7450db1dbc5107e7c259c3ded3e23921c00  bin/qwb-wake.sh
b0347c474346ec15062f93e9ecc5d26a812d3e0f2a724fa901d7066d1f7fbb59  bin/qwb-status.sh
9b477ca0c62c0bc50b0b8593380a2467172d4e836ac333644480021b621682dc  bin/qwb-lint.sh
809100cecf4226de06083c26fa0fd31baa31b4e665499489c37aa78f963495af  bin/qwb-worktree.sh
```

## 实测

- `QWB_TEST_ROOT="$PWD" bash /tmp/qwb-ledger-parsing-diff.sh > /tmp/qwb-ledger-parsing-diff-final.log 2>&1` → rc=0，`DIFF PASS 39 comparisons`。一次性脚本从冻结基线真实脚本提取场景 awk，并运行基线/候选公开 status、lint、wake dry-run、run 拒发预检、worktree list。9 类夹具：无 state、非法、空 state、前后空白的合法 state、连续 state、无下一节标题而直接接 `not-sent:`/`working:`/`done:`/`wake:` 尾行、疑点后普通 done、场景篡改、旧票有 dispatch 无 fp。逐项比较 stdout、stderr、rc、场景块原始字节及 SHA-1；每次 CLI 读取前后用 shasum 验证账本未改。隔离配置声明 true fast/full，因此正常 lint rc=0；非法、空值与篡改 rc=1。另断言三种 run 拒发分别命中疑点、指纹、缺 fp 诊断，旧票 lint 留警告。
- 同一脚本使用隔离 HOME、假 Herdr、临时项目执行全新 `qwb-init.sh` 安装和既有安装升级；安装的 status/lint 可加载库、用户 `config.sh` 字节保留。source 库无 stdout/stderr 或 shell 选项变化。脚本只留 `/tmp`，常规门不依赖历史 Git 对象。
- `bash bin/qwb-test.sh fast` → rc=0；`git diff --check` → rc=0。原始差分日志 `/tmp/qwb-ledger-parsing-diff-final.log`。

未跑 `full`（主控唯一全门），未运行真实 Herdr 派发、pane 或全局 CLI；运行预检验证仅覆盖拒发路径。未改主账本已有 state、场景、指纹或旧记录；本证据文件只在主仓 `docs/reviews/`。
