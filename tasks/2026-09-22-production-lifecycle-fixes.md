# 生产生命周期返修

state: verified

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
working: 2026-09-22T08:00:00Z 执行者在 production-lifecycle-fixes 完成独立整合 merge 7444a57c813ff9862241918938d887f2d8529447；父提交 178caed0bb2a9f8b8d2bbf5ab2cc0aa704242366 与 a8eec488a75d9cec8a006af4deeb310a3b7554b2。仅手解 tests/smoke.sh，保留 runtime 第 74 节及 boundary 第 75 节完整测试调用；bin/qwb-dispatch.sh、bin/qwb-init.sh、bin/qwb-worktree.sh、tests/boundary-readiness.sh 为已审父提交自动整合。验证 bash bin/qwb-test.sh fast、bash tests/runtime-readiness.sh、bash tests/boundary-readiness.sh 均 rc=0；日志在 /tmp/qwb-lifecycle-merge-*.log。后续生命周期业务提交以此 SHA 为基线。
working: 2026-09-22T07:53:57Z 更正上一行误写的未来时间：整合 merge 7444a57c813ff9862241918938d887f2d8529447 的真实提交时间由 git show -s --format=%cI 核对为 2026-09-22T09:50:29+02:00，即 2026-09-22T07:50:29Z。上一行 08:00:00Z 非实取，不能作为完成时间证据；此更正行时间由 date -u 实取。
wake: 2026-09-22T07:50:42Z state=running fp=e7e5c768b392909f925b0f8351ab064829925a52
wake: 2026-09-22T07:54:43Z state=running fp=e621f907776f3616974a71af6987e77b45249e86
working: 2026-09-22T08:01:20Z 执行者完成生命周期业务提交 56705466beeb72151b7aa1773f63680dba91d5c7（基线 merge 7444a57c813ff9862241918938d887f2d8529447）。red：Pi 晚获锁定向 node tests/pi-ext.test.mjs rc=1（预期 1、实得 0）；冻结 7444a57 真实宿主死亡定向 rc=1，复现宿主 SIGKILL 后孤儿写新 wake。green：Pi 14/14；bash tests/lifecycle-readiness.sh rc=0（真实宿主 SIGKILL 后子进程退出且无新 wake；hook A/B 回收交错单飞；假 Herdr 跨 workspace 创建/复用/失活恢复/错误目标/查询失败）；bash bin/qwb-test.sh fast rc=0；shellcheck tests/lifecycle-readiness.sh rc=0；git diff --check rc=0。日志 /tmp/qwb-lifecycle-*.log；临时项目由 TemporaryDirectory 清理，真实子进程 finally 兜底清理。未跑全门、真实 Pi reload 或真实 Herdr 跨 workspace，交主控统一验收；未 push、未 merge 其他分支。
wake: 2026-09-22T08:02:45Z state=running fp=cf973b43ba367cf2830c3b3faad9c9781b493da5
working: 2026-09-22T08:05:45Z 执行者按主控补充完成现有门真实性小提交 aa1c710e7148c952a522740691038be0c809903b；仅改 tests/smoke.sh 与 tests/lifecycle-readiness.sh。red：旧 run_pi_ext 在隔离 stub 下首次 pi-ext 实测 rc=1、第二次带 --experimental-strip-types 实测 rc=0，函数误返 0 且调用两次（/tmp/qwb-pi-runner-red.log）。green：独立 TypeScript 能力预检后选 Node/Node strip-types/Bun，三种 stub 分支实际测试各一次且失败均非零；本机真实执行器 Pi 14/14（/tmp/qwb-pi-runner-real.log）；生命周期定向 rc=0（/tmp/qwb-pi-runner-green.log）；快门、shellcheck、bash -n、diff check 均 rc=0。不跑全门、不动生命周期源码、不 push。
wake: 2026-09-22T08:06:47Z state=running fp=f2c4dfc4bbd804a72fe6886a0959ef8c75cbb851
wake: 2026-09-22T08:36:56Z state=running fp=f2c4dfc4bbd804a72fe6886a0959ef8c75cbb851
wake: 2026-09-22T09:07:06Z state=running fp=f2c4dfc4bbd804a72fe6886a0959ef8c75cbb851
wake: 2026-09-22T09:37:15Z state=running fp=f2c4dfc4bbd804a72fe6886a0959ef8c75cbb851
wake: 2026-09-22T10:07:25Z state=running fp=f2c4dfc4bbd804a72fe6886a0959ef8c75cbb851

working: 2026-09-22T10:19:25.768248+00:00 用户明确授权先按原生产票收尾，再依次执行三张改进票。生命周期 aa1c710 的独立 r1 为 AMEND：Pi 快速失锁重获可能双开、跨 workspace 缺登记查询失败误认领、宿主 SIGKILL 后残留死 PID 登记。已复用现有 Sol medium 执行会话返修；Sol high 原审核会话保留。新改进票尚未激活，待生产基线验收完成。
wake: 2026-09-22T10:19:29Z state=running fp=0a82c04f70c9d2569f0082e3092dbb69a03235a7
working: 2026-09-22T10:24:48Z 执行者完成原生产票 r1 三项 AMEND 返修，独立提交 fc0c29ccad205eda91404ef7ffaa95a14c7ab3d8（父 aa1c710e7148c952a522740691038be0c809903b），只改原票白名单。red：node tests/pi-ext.test.mjs rc=1，快速失锁重获在旧 close 前观测 spawns=2（/tmp/qwb-lifecycle-r1-pi-red.log）；bash tests/lifecycle-readiness.sh rc=1，真实 Pi 扩展宿主 SIGKILL 后残留旧 .watch（/tmp/qwb-lifecycle-r1-readiness-red.log）；冻结 aa1c710 的 bin/qwb-wake.sh 注入跨 workspace 定向 rc=1，缺登记 pane get 失败仍误认领（/tmp/qwb-lifecycle-r1-cross-red.log）。green：node tests/pi-ext.test.mjs 15/15 rc=0（/tmp/qwb-lifecycle-r1-pi-green.log）；bash tests/lifecycle-readiness.sh rc=0（/tmp/qwb-lifecycle-r1-readiness-green.log），含真实 Node 扩展宿主强退、旧 PID/实例条件清理和新登记保护、快速失锁/重获及跨 workspace 未知身份拒绝；bash bin/qwb-test.sh fast rc=0（/tmp/qwb-lifecycle-r1-fast.log）；shellcheck bin/qwb-wake.sh tests/lifecycle-readiness.sh、bash -n bin/qwb-wake.sh tests/smoke.sh、git diff --check 均 rc=0，ShellCheck 日志 /tmp/qwb-lifecycle-r1-shellcheck.log。临时目录 TemporaryDirectory 自动清理，真实测试子进程 finally 兜底清理。未跑 full、真实 Pi /reload、真实 Herdr 跨 workspace 或跨平台宿主；未 push/merge/清理 worktree；未触碰三张改进票。
wake: 2026-09-22T10:25:31Z state=running fp=99e25ae4d46c288c0af03f649543412c5a068e78

working: 2026-09-22T10:28:58.817319+00:00 主控收到 fc0c29c 独立 r2 PASS，三项 AMEND 已闭环；state=done，待整合全门与真实 Herdr 闭环。

working: 2026-09-22T10:32:17.888481+00:00 整合候选 6e9b0f2 首次 full rc=1，103.011s，smoke 12项失败集中旧值守与 pane-run 场景；保留日志 /tmp/qwb-production-final-full.log。已交原执行 pane 新 Sol medium 会话定向诊断，初始只准修 tests/smoke.sh；不得放宽契约或删断言。真实 Codex 复用 pane 派发闭环单独通过，不抵扣 full。
wake: 2026-09-22T10:33:33Z state=running fp=b3ec4a90eb9136b9113f3893a679315389002317
working: 2026-09-22T10:35:25Z 执行者对 6e9b0f2 full 旧日志 /tmp/qwb-production-final-full.log 的 §42/45/47/51 共 12 FAIL 定向收尾，提交 4dbc28a73b01966e520f6b5b213ae3e6e8bee691（父 6e9b0f2b0b307357445ecaf24b8c947d424dd257；仅 tests/smoke.sh）。归因：§42 status 缺 Herdr workspace 上下文，与已审目标 workspace 校验冲突；§45 正例假件把候选 pane 标成异 workspace；§47/51 stub heredoc 提前展开 ${3:-}，致 pane-run agent get 永远失败；§47 超时旧断言要求保留 dispatch，与已审 not-sent + blocked + 关新 tab 契约不符。未发现需改运行时的证据。定向脚本从 smoke 原段提取并置于 /tmp/qwb-production-targeted-smoke.sh：首次生成器路径错误 rc=1（未执行有效测试），修正路径后 bash -n rc=0、定向 rc=0 TARGETED FAILS=0（/tmp/qwb-production-targeted-smoke.log，覆盖 §42a-c、§45a、§47 全段、§51e）；bash bin/qwb-test.sh fast rc=0（/tmp/qwb-production-smoke-fix-fast.log）；bash -n tests/smoke.sh rc=0；shellcheck -S error tests/smoke.sh rc=0（/tmp/qwb-production-smoke-fix-shellcheck.log）；git diff --check rc=0。常规 shellcheck tests/smoke.sh rc=1 为全文件既有 info/warning，未作为绿门。未跑 full、§42d-j/§45b-f/§51其余项的本轮定向、真实 Herdr 跨 workspace/真实 Pi reload/跨平台宿主；full 交主控独立复审与重跑。未改运行时/state，未 push/merge/新窗口。
wake: 2026-09-22T10:35:34Z state=running fp=875a285061c77043fd7163e1b48db012f0c2a487

working: 2026-09-22T10:41:24.995773+00:00 主控验收：最终源码整合 4dbc28a，独立复审全部 PASS；整合 full rc=0/110.168s；当前同源安装副本真实 Codex Herdr 显式复用 pane 闭环通过，正负门与前台 block 2/124/0、worktree 收尾均实测。主线已快进合入；详见 docs/reviews/2026-09-22-production-final.md 的证据及未覆盖边界。state=verified。
worktree: merged branch=production-lifecycle-fixes tag=-
