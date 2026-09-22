# 生产基线生命周期核查

**结论：AMEND。** 固定源码 `1c500b38c014be9e55aa33fede2735ebaaf17d16`，只用 `git show <SHA>:<路径>` 取得白名单脚本与 Pi 扩展；`qwb-lib.sh` 仅供隔离运行所需。未将当前 main 当候选，不跑全门、不联网、不派发、不创建真实 Herdr 窗口。三个隔离复现都在系统临时目录完成并由 `TemporaryDirectory` 清理；最后 `ps` 未发现带这些临时目录标识的残留进程。Pi probe `exit=2` 与前轮锁/派发问题不在本轮重复报告。

## 1. Claude hook 死锁回收可删掉继任者的活锁，两个值守同时运行

- **问题与代码**：`bin/qwb-hook-claude-stop.sh:35-49` 读取旧 `.hook.lock/pid` 判死后直接 `rm -rf` 再 `mkdir`；判定与删除之间没有回收互斥或身份复核。退出 trap `bin/qwb-hook-claude-stop.sh:54-55` 也按固定路径无条件删除，可能清掉已换主的锁。
- **已复现**：临时项目预置死 PID，A 判死后停在删除前；B 先回收并进入假 `qwb-wake.sh --block`，随后放行 A。两次 hook 均 `rc=0`，观测 **2 个并存值守子进程**；`.hook.lock/pid` 由 B 的 PID 变成 A 的 PID。假值守只阻塞并记 PID，未调用真实 Claude 或改真实账本。
- **影响**：hook 单飞约束失效。真实两个 `--block` 可并发读取同一未结进展、写 `wake:` 或重复交付摘要；先退出者的 trap 还可删掉后继者的活锁，为第三个实例腾出入口。
- **最小修复**：把残留回收串行化，在独占回收区重新核对 owner/pid 后再替换；释放时仅清理仍属于本实例的锁。增加 A/B 交错与旧实例退出的确定性测试。

`.watch.lock` 对照：`bin/qwb-wake.sh:302-315` 使用原子 `mkdir`，自动路径遇到已有锁即拒绝，**没有**像 hook 那样自动 `rm -rf` 回收残留锁；正常调用未见同一竞态。其手动删除提示不能充当自动安全恢复证明。

## 2. Pi 值守与主控生死未绑定，晚获锁漏启动，强制退出后孤儿可消费进展

- **问题与代码**：`templates/pi-extensions/qwb-watch.ts:184-196` 仅在 `session_start` 持锁时启动；此前未起过子进程则 `idleAfterZero=false`，晚获锁后的 `turn_end` 不会启动。扩展用普通 `spawn`（`:249-255`）；`shutdown()` 只向 child 发 `kill()` 且不清 `.watch`（`:76-84,198-206`），SIGKILL 无法触发 `session_shutdown`/`process.once("exit")`。子进程 `bin/qwb-wake.sh:607-614` 只比对锁文件中的 pane ID，不检查 Pi 进程；仍匹配时会写 `wake:`（`:622-630`）。
- **已复现**：从冻结扩展 blob 加载核心：`session_start` 时无锁、后来获锁并 `turn_end`，启动数仍为 0；重新加载并持锁时会启动。另在临时项目用冻结 `qwb-wake.sh` 作真实子进程，Pi 宿主进程 SIGKILL 后子进程仍存活；保持旧锁 owner，追加一条 `working:`，任务书 `wake:` 从 1 行增至 2 行，但没有宿主可执行 `sendMessage`（消息文件不存在），`.watch` 登记仍在。父进程 `-9`，子进程已在复现结束前清理。
- **影响**：新 Pi 会话按开局顺序晚获锁时没有值守；异常退出时反而可能由孤儿值守把新进展标成“已叫醒”，摘要无处交付，指纹去重将压住后续同一进展。`.watch` 的 PID 存活也不足以证明 Pi 主控仍在。
- **最小修复**：晚获锁后在可观察事件中启动单个值守；子进程须有能判断父 Pi 会话存活的租约或随父进程终止的机制，失联时在写 `wake:` 前退出；关闭/重载时等待子进程结束并只清本实例的 `.watch`。增加晚获锁、SIGKILL 孤儿与重载交错的定向测试。

## 3. 跨 workspace `--ensure` 首次建在 B，第二次从 A 无法复用

- **问题与代码**：`bin/qwb-wake.sh:274-300` 以调用者 workspace A 验证主控 pane；`bin/qwb-wake.sh:319-323` 只扫描 A。但创建路径 `bin/qwb-wake.sh:393-419` 可以按项目 `QWB_WORKSPACE` 在 B 建 tab 并登记 `.watch`。再次调用时，`bin/qwb-wake.sh:354-362` 发现登记 pane 属于 B 而调用者仍为 A，直接拒绝。
- **已复现**：临时项目 `QWB_WORKSPACE=wB`，假 Herdr 返回主控 pane 在 wA、假值守 pane 在 wB；首次 `--ensure --pane wA:pCtl` 为 `rc=0`，`.watch` 记 `pane=wB:pWatch workspace=wB`；同样命令第二次为 `rc=1` 并报“跨 workspace 不认领不重启”。假 `tab create` 共记录 1 次，没有创建真实窗口。
- **影响**：跨项目值守首次可报告成功，但后续幂等确保、失活重启和单实例扫描不在同一 workspace 边界内；可能误报已有实例状态或拒绝恢复。
- **最小修复**：在创建前统一调用者、目标主控和候选值守 workspace 的规则；若支持跨 workspace，扫描与登记复用须使用同一目标范围并校验真实 `--pane`，否则在创建前明确拒绝。加首次调用与第二次复用的假 Herdr 闭环测试。
