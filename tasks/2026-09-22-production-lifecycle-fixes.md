# 生产生命周期返修

state: running

## 0. 范围

修复 docs/reviews/2026-09-22-production-lifecycle.md 的三项实证缺陷。执行 GPT Sol medium、审核 GPT Sol high；不创建窗口、不递归派发。已准备独立整合目录 .worktrees/production-lifecycle-fixes。先完成下述已启动的合并，再记录合并基线并实施本票。

白名单：bin/qwb-hook-claude-stop.sh、bin/qwb-wake.sh、bin/qwb-lib.sh、templates/pi-extensions/qwb-watch.ts、tests/pi-ext.test.mjs、tests/smoke.sh、tests/lifecycle-readiness.sh（可选定向入口）、docs/DECISIONS.md、README.md、README.zh.md、templates/QWBUDDY.md。若新增运行态文件，bin/qwb-init.sh 仅可补必要忽略项及升级测试。

1. hook 单飞：回收与释放不能删除后继活实例的锁，同一项目最多一个活 hook 值守；异常中断不遗留只能手删的恢复障碍。复用前票可靠互斥经验，避免独立复制不可靠 mkdir/rm 回收。
2. Pi：启动时无锁、稍后本会话获锁后能在现有事件中自动启动一个值守；失锁、会话重载、shutdown 不会重复运行或被旧回调重启。SIGKILL 等宿主退出后，孤儿子进程不得继续消费进展；写 wake 前必须能判断宿主仍活，采用最小进程生命周期机制，不引入守护进程/队列/ACK 服务。关闭时回收自己的子进程与登记，不能清掉新会话的登记；摘要管道排空后才能判断退出结果，不能漏交子进程输出。
3. 跨 workspace ensure：保留已有跨项目派发用途，统一创建、扫描、登记、复用、失活恢复的目标范围；重复调用不会拒绝自己首次创建的值守，也不误认他项目或错误主控目标。不得通过直接禁止已有跨 workspace 用法来使测试更容易通过。

运行时通过后，中英文 README 与主控说明同步移除已修复的临时限制；仍明确尚未实测的 host 边界，不扩大生产声明。

## 合并准备（主控已启动，先单独收尾）

当前 HEAD 178caed0bb2a9f8b8d2bbf5ab2cc0aa704242366 已含审核通过的 runtime 856f870 与 docs 556d6aa；MERGE_HEAD a8eec488a75d9cec8a006af4deeb310a3b7554b2 为已复审通过的 boundaries。仅 tests/smoke.sh 的末尾新增测试块冲突：保留 runtime 18 项调用与 boundary 调用，各自完整 if/fi，编号可顺延，不删任何用例，不放在最终 exit 之后。

应用 resolving-merge-conflicts 技能，先核对上述两个父提交和主票/审核报告意图。合并阶段只手改这个冲突文件；自动暂存的边界源码保持来自已审提交的内容。跑快门与相关定向测试后完成这笔合并提交并记录 SHA。这里明确授权完成这笔候选整合 merge，不授权 merge 其他分支或主线。合并提交与本票后续生命周期实现提交分开；全门仍由主控在最终候选上统一运行。

## 1. 验收场景

### 失败路径：并发回收与旧实例退出
Given 两个 hook 竞争旧死锁，A 停在判死与回收之间，B 尝试接管
When 按确定性交错放行且旧实例退出
Then 最多一个值守子进程运行，旧退出不删新实例锁；异常后可恢复。

### 正常路径：晚获锁后自动值守
Given Pi session_start 时无锁，之后当前 pane 获主控锁
When turn_end 等既有事件发生
Then 恰好启动一个值守，无需人为 reload；未获锁的执行者始终不启动。

### 失败路径：宿主强制退出
Given 真实 qwb-wake 子进程绑定持锁宿主且已消费旧进展
When 宿主被 SIGKILL，随后账本出现新进展
Then 子进程退出且不写新 wake，不残留活进程/错误登记；重启后的宿主仍能看到未消费进展。

### 失败路径：重载与失锁交错
Given 老子进程、迟来 exit/error、重启计时器与新会话可能交错
When 失锁、重载或 shutdown
Then 不启动额外值守、不清新会话登记、不丢已完整输出的摘要，正常 0/2/124 分支仍成立。

### 正常路径：跨 workspace 幂等与恢复
Given 主控在 A，项目解析的值守 workspace 为 B
When 第一次 ensure、同参数第二次 ensure、值守失活后再次 ensure
Then 初次创建、第二次复用、失活可恢复；始终只服务指定主控与项目，没有重复实例。

### 失败路径：错误目标与未知身份
Given 已登记值守实际指向别的项目/主控，或关键 Herdr 查询失败
When ensure/check
Then 明确拒绝或报未知，不错误认领、关闭或重启别人的服务。

## 2. 验证与交付

定向测试必须含真实 shell 子进程的宿主死亡/管道/清理证据；Herdr 跨 workspace 可用明确假件，但不冒充真实窗口。先 red 后修，接入已有 full 入口。只跑快门和本票定向检查，统一全门由主控跑；不 push/merge/清理 worktree。只提交白名单，主账本只追加证据与 SHA，不改 state。
wake: 2026-09-22T07:04:27Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-22T07:34:37Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa

scenarios-fp: bd79cb90412527aad1cdd8ad2041a55b5c2c3373
working: 2026-09-22T07:48:22.931498+00:00 主控核实 runtime-r3 与 boundaries-r2 的单点 PASS；已在独立候选目录启动整合，仅 smoke 新增段冲突，交执行者按两边原意收尾，再做生命周期实现。主线源码未变。
wake: 2026-09-22T07:48:42Z state=running fp=5cc82a78af665cf6f8508c12556ab3aa64a1c09d
