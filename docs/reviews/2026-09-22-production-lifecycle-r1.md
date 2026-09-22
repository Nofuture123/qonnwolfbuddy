# 生产生命周期候选独立审核 r1

**结论：AMEND。** 冻结基线 `7444a57c813ff9862241918938d887f2d8529447`，候选 `aa1c710e7148c952a522740691038be0c809903b`（`5670546` 业务及 `aa1c710` 测试入口）。只审指定白名单的 `git diff baseline..candidate`；从候选 `git archive` 在 `/tmp` 隔离运行，不读取共享工作树的未提交 `tasks` 改动作为候选源码。规格取当前 `tasks/2026-09-22-production-lifecycle-fixes.md`，旧问题取 `docs/reviews/2026-09-22-production-lifecycle.md`。未运行全门、真实 Pi/Claude host 或真实 Herdr workspace，未创建窗口、联网或派发。

## 可行动发现（限本轮新增内容）

1. **Pi 失锁后立刻重获锁可短暂双开值守。** `templates/pi-extensions/qwb-watch.ts:77-87` 的 `killChild()` 在仅调用异步 `child.kill()` 后就清空 `child`；`:214-225` 下一次 `turn_end` 只看 `child` 为空，立即启动第二个子进程，不等旧进程 `exit`/管道关闭。隔离 fake ChildProcess 按 Node `kill()` 的异步语义延迟退出，顺序执行“获锁 → 失锁 → 重获锁”，观测 `spawns=2, oldKillRequested=true, oldExitObserved=false, newStarted=true`（`/tmp/qwb-lifecycle-r1-pi-race.log`，rc=0）。旧子进程仍有本宿主 PPID；同一 pane 重获锁后它也可通过 `block_owner_ok`，因此单飞和不重复消费没有保证。修复应保留旧进程的退出中状态，等 `close`/管道排空及确认终止后再允许新实例启动；把重获锁交错加到 Pi 定向测试。

2. **跨 workspace 缺登记复用时，关键查询失败却成功并写错 workspace。** `bin/qwb-wake.sh:354-357` 在扫描 B 发现活值守、但 `.watch` 缺失时，吞掉 `pane_info` 的失败，并以调用者 `ws`（A）替代实际值守 workspace。基于现有假 Herdr 夹具的隔离复现：首次在 B 创建成功；删掉登记后让 `pane get wB:pWatch` 查询失败，第二次 `--ensure` 仍 `rc=0`，写出 `pane=wB:pWatch workspace=wA`（`/tmp/qwb-lifecycle-r1-ws-probe.log`，rc=0）。这违反查询未知时 fail-closed，且下一次 ensure 会按错误登记拒绝自己的值守；README 中跨 workspace 复用承诺因此尚不成立。应在该查询失败时拒绝登记/复用，或使用已验证的目标 `tabws` 并核验 pane 身份；增加缺登记加 `pane get` 失败测试。

3. **宿主 SIGKILL 后仍留下死 PID 的 Pi 登记。** `templates/pi-extensions/qwb-watch.ts:99-103,279-296` 只由 Pi 宿主写/清 `.watch`；`bin/qwb-wake.sh:615-621,662-667` 检出 PPID 改变后仅退出，没有按实例身份清理登记。隔离 Node 宿主加载候选扩展、持锁启动真实 `qwb-wake.sh` 后被 SIGKILL：宿主 `rc=-9`、子进程退出、但 `.watch` 仍是 `kind=pi-ext pid=<已退出 PID>`（`/tmp/qwb-lifecycle-r1-orphan-watch.log`，rc=0）。现有 `tests/lifecycle-readiness.sh:36-60` 只检查子进程和 `wake:`，没有创建或断言该登记。状态检查会把死 PID 显示为“未运行”，但任务验收明确要求宿主强退后不残留错误登记。应由孤儿退出路径在同一 flock 临界区仅条件删除自身 PID/实例登记，并增加真实子进程宿主死亡后的 `.watch` 断言。

## 通过范围与证据边界

- hook 回收竞争定向测试通过；另在隔离项目让 hook 值守持续运行时执行 `qwb-lock.sh release --project`，`rc=0`、耗时约 0.034 秒，hook 当时仍运行（`/tmp/qwb-lifecycle-r1-hook-lock.log`）。该证据支持正常主控锁操作不会被整个值守周期占住；未实测真实 Claude host。
- 候选归档运行 `node tests/pi-ext.test.mjs`：14/14，`rc=0`（`/tmp/qwb-lifecycle-r1-pi.log`）；`bash tests/lifecycle-readiness.sh`：4 个 PASS、`rc=0`（`/tmp/qwb-lifecycle-r1-readiness.log`），其中执行器假件确认能力预检后三种分支实际测试各一次，失败不换执行器重跑。`bash -n` 与 ShellCheck 定向 `rc=0`；冻结 diff 的 `git diff --check` 为 `rc=0`。
- 共享 `tests/smoke.sh:3504-3528` 的第 74 节 runtime、第 75 节 boundary 与第 76 节 lifecycle 均位于最终 `exit`（`:3533`）之前；未跑全 smoke/full。
- README 英中两版及 `templates/QWBUDDY.md` 均已同步移除 Pi 晚获锁需手动 reload 的旧限制，并声明跨 workspace 复用；第 2 项使后者尚不能按文档验收。`docs/DECISIONS.md` 保留了真实 Pi reload/跨平台宿主未验的边界。

AMEND
