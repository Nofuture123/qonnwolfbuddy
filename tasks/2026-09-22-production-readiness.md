# 生产级收敛：正确性、速度与 token 成本

state: verified

主控：Codex；用户授权审核、优化本项目至生产级。
基线：1c500b38c014be9e55aa33fede2735ebaaf17d16，main，开局工作区干净。

## 完成条件

1. 安装与升级保护项目既有配置，运行态不污染受版本控制配置；依赖与支持范围准确。
2. 锁、派发、值守、账本、worktree 收尾的失败与并发路径不丢工作、不重复消费、不假报成功。
3. 当前候选通过快门、全门与独立可见审核；真实 Herdr 闭环验证绑定候选和工具版本，历史、mock、未验证分别标明。
4. 以当前运行测量门耗时和唤醒次数；默认空闲值守不消耗模型 token；不以重试、放宽断言换速度。
5. README、安装指引、运行手册与实际能力一致；遗留风险和明确不保证的边界可查。

## 第一轮审核（最多三个审点）

只读冻结基线，不递归派发，不跑全门；主控负责一次全门。
源码白名单：bin/qwb-lock.sh、bin/qwb-run.sh、bin/qwb-wake.sh、bin/qwb-lib.sh、bin/qwb-hook-claude-stop.sh、templates/pi-extensions/qwb-watch.ts。
参考：templates/QWBUDDY.md、templates/config.sh、docs/DESIGN.md、docs/DECISIONS.md、tests/smoke.sh、tests/pi-ext.test.mjs。

1. 锁获取、死锁回收和并发互斥是否真正保证唯一主控。
2. 值守去重、消费时机、子进程退出和失败恢复是否遗漏或重复唤醒并浪费 token。
3. 派发在启动/投递失败及重派时，是否误记成功、复用错误工人或污染工作目录。

审核结果只写 docs/reviews/2026-09-22-production-runtime.md，每条给问题、准确 file:line、复现或静态证据、影响、最小修复。最多三个最重要发现，区分已复现与推断，给 PASS/AMEND；不要自行修改源码。

## 验收场景

### 正常路径：候选交付可追溯
Given 固定候选版本和当前工具环境
When 执行必要检查与真实闭环
Then 结果、耗时、产物、清理和审核结论绑定相同候选，不以旧结果替代。

### 失败路径：检查通过不足以证明生产可用
Given 存在并发、恢复缺陷或真实闭环缺证
When 单元及静态门通过
Then 保持任务未完成，补齐修复与证据，不宣布生产就绪。

## 当前证据

### 待闭环的问题

- 首轮 runtime 三项已隔离复现，见 `docs/reviews/2026-09-22-production-runtime.md`；返修票 `2026-09-22-production-runtime-fixes.md` 执行中。
- 文档候选 59eb8ff 的复审 AMEND 见 `docs/reviews/2026-09-22-production-docs.md`：workspace 环境覆盖说明错误、Pi 晚获锁不启动、跨 workspace ensure 不幂等。文档先如实说明现状；后两个运行时缺陷必须后续修复，不能以限制文档替代生产目标。
- `qwbuddy/.pi-watch.err` 安装后未被忽略，待修。
- 后续核查需覆盖 Claude hook 单飞锁的死锁回收交错（当前仍是判死后 rm/mkdir），避免只修主控锁而留下同类竞争。
- 第二轮审核仅 `qwb-init.sh` / `qwb-dispatch.sh` / `qwb-worktree.sh`，三个审点为安装更新安全、路由凭据与失败处理、worktree 收尾；冻结源码 1c500b3，复用已有 Sol high 会话，报告 `docs/reviews/2026-09-22-production-install-routing.md`。
- 最终仍需对真实合入候选跑一次全门，并完成当前源码绑定的真实 Herdr 生命周期验收和资源清理；历史 PASS 不抵扣。

working: 2026-09-22 开局核实 HERDR_ENV=1、当前 pane 和 codex PATH；Herdr 0.9.1；Node v26.8.1；ShellCheck 0.11.0。仓库没有根 AGENTS.md/CLAUDE.md，遵循用户提供全局规范与母本模板主控职责。
working: 基线 fast rc=0，real 1.38s；full 正在执行，结果待回收。历史 E2E-RUNBOOK 绑定 e917008 且首次派发有人为介入，不构成当前候选无人干预证明。
wake: 2026-09-22T06:38:20Z state=running fp=37a3e48bf00c9ea800808c1c0fd03053b64491c2

working: 基线 full 实跑 rc=0，real 88.35s；smoke 567 PASS / 0 FAIL，review-identity PASS，lint PASS。原始日志 /tmp/qwb-production-fast.log 与 /tmp/qwb-production-full.log。安装临时复现 rc=0，但 qwbuddy/.pi-watch.err 未被 gitignore 忽略（.watch 对照已忽略）；临时目录已清理。此项待修。
working: 用户新增约束：本窗口禁止创建 pane；后续只复用已有窗口。已启动的 runtime 审核与 production-docs 执行继续回收，不再扩容。
wake: 2026-09-22T06:42:21Z state=running fp=ce104aa280a4b060be80481aea6c4ce84ce3cd46
working: 用户今日指定执行 GPT Sol medium、审核 GPT Sol high，覆盖模板跨家族默认。旧 Pi/Claude 已停止，未交付不计验收；原执行/审核 pane 已移至独立后台 tab，当前主控 tab 仅一个 pane。新两个 Codex TUI 已核实模型/effort 且任务均进入 working。
wake: 2026-09-22T06:44:21Z state=running fp=36e930d27e892c15433538d9f61b89737d9fd194
wake: 2026-09-22T07:14:30Z state=running fp=36e930d27e892c15433538d9f61b89737d9fd194
working: 2026-09-22T07:26:48.751254+00:00 文档 556d6aa 复审 PASS（待统一全门）；运行时 d9ed805 复审 AMEND 余1个父死锁交错；安装/路由/收尾 boundaries 已在独立 worktree 由新 Sol medium 会话执行。生命周期三项已实证待修，见 production-lifecycle 报告。没有当前候选全门或真机 PASS，生产目标未完成。
wake: 2026-09-22T07:28:35Z state=running fp=4c1ca39f80b093436f849073ee113da459f561d0
wake: 2026-09-22T07:58:44Z state=running fp=4c1ca39f80b093436f849073ee113da459f561d0
working: 2026-09-22T07:59:53.754220+00:00 进展更新：runtime 856f870 与 boundaries a8eec48 的最后 AMEND 均已独立 PASS，docs 556d6aa 已 PASS，均汇入候选 7444a57。旧摘要中 d9ed805 尚有父死锁问题的状态已被 856f870 取代。当前仅生命周期实现进行中（hook单飞、Pi晚获锁/宿主死亡/关闭、跨workspace恢复）；执行者已用真实子进程复现旧基线宿主死亡后继续写 wake。最终生命周期复审、整合全门、当前候选真机闭环、清理与主线源码合入均未完成。
wake: 2026-09-22T08:00:45Z state=running fp=230acc4bc2dac2ce0d70a643eaaa89afe8193d26
wake: 2026-09-22T08:30:54Z state=running fp=230acc4bc2dac2ce0d70a643eaaa89afe8193d26
wake: 2026-09-22T09:01:04Z state=running fp=230acc4bc2dac2ce0d70a643eaaa89afe8193d26
wake: 2026-09-22T09:31:13Z state=running fp=230acc4bc2dac2ce0d70a643eaaa89afe8193d26
wake: 2026-09-22T10:01:23Z state=running fp=230acc4bc2dac2ce0d70a643eaaa89afe8193d26

working: 2026-09-22T10:19:25.768248+00:00 用户明确授权先按原生产票收尾，再依次执行三张改进票。生命周期 aa1c710 的独立 r1 为 AMEND：Pi 快速失锁重获可能双开、跨 workspace 缺登记查询失败误认领、宿主 SIGKILL 后残留死 PID 登记。已复用现有 Sol medium 执行会话返修；Sol high 原审核会话保留。新改进票尚未激活，待生产基线验收完成。
wake: 2026-09-22T10:19:29Z state=running fp=0a82c04f70c9d2569f0082e3092dbb69a03235a7

working: 2026-09-22T10:28:58.817319+00:00 生命周期 fc0c29c 独立 r2 PASS。开始整合候选全门与当前源码安装副本真实 Herdr 派发验收；生产总票尚未完成，三张改进票未激活。
wake: 2026-09-22T10:29:32Z state=running fp=bad29cc6bc7f954ab8a5d388d4a1399332527a80

working: 2026-09-22T10:32:17.888481+00:00 整合候选 6e9b0f2 首次 full rc=1，103.011s，smoke 12项失败集中旧值守与 pane-run 场景；保留日志 /tmp/qwb-production-final-full.log。已交原执行 pane 新 Sol medium 会话定向诊断，初始只准修 tests/smoke.sh；不得放宽契约或删断言。真实 Codex 复用 pane 派发闭环单独通过，不抵扣 full。
wake: 2026-09-22T10:33:33Z state=running fp=b3ec4a90eb9136b9113f3893a679315389002317

working: 2026-09-22T10:41:24.995773+00:00 主控验收：最终源码整合 4dbc28a，独立复审全部 PASS；整合 full rc=0/110.168s；当前同源安装副本真实 Codex Herdr 显式复用 pane 闭环通过，正负门与前台 block 2/124/0、worktree 收尾均实测。主线已快进合入；详见 docs/reviews/2026-09-22-production-final.md 的证据及未覆盖边界。state=verified。
