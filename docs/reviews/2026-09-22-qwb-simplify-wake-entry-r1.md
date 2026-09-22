# 票①独立审核 r1：统一开局唤醒入口

结论：AMEND。

对象：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-wake-entry` 的未提交候选；HEAD `33ab7e4d15926c21fe9199efdbaffeff7f8393cd`；`git diff --binary HEAD` SHA256 `018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438`（21566 字节）。本轮仅审 README.md、README.zh.md、templates/QWBUDDY.md、templates/claude-hook.md、templates/agents-hook.md、docs/DECISIONS.md。对照主账本 `tasks/2026-09-22-qwb-simplify-wake-entry.md` 六场景与 `/tmp/qwb-simplify-wake-entry-walkthrough.md` 最终更正段；没有修改候选源码、提交或运行 full。

Standards：没有发现白名单越界或新增格式问题。六个文件均为允许路径，`docs/DECISIONS.md:513-517` 只追加并明确取代历史 §二十九默认 fallback，旧段未改。`git diff --check HEAD` 退出 0。Gardening、规格疑点/场景冻结/派发、锁恢复对应模板及运行时未被本 diff 改写；本轮不重审其历史正确性。

Spec：两项须返修。

1. 未知主控在被拒绝前仍会取得并保留主控锁。新交接入口 `templates/agents-hook.md:5` 与 `templates/claude-hook.md:5` 指示先取锁、点名，再识别宿主；`templates/QWBUDDY.md:11-15` 也把宿主拒绝放在取得锁之后。`bin/qwb-lock.sh:99-103` 的 acquire 会建立 `.controller.lock`，并以当前 pane 记 owner；`bin/qwb-lock.sh:85-94,118-123` 会拒绝另一个仍存活的 pane。影响：一个不支持或无法识别但仍存活的 Herdr 宿主会占锁而不值守，随后真正受支持的主控无法接入，违背未知主控拒绝场景的安全接续目的。修复建议：在任何 acquire 之前先确认宿主属于三者之一；无法确认就报告并停止。保持已识别宿主原有锁抢占、死锁回收和点名顺序。

2. 新增说明把 Codex 的退出码 0 等同于「无未结项」，与当前运行时不符。`templates/QWBUDDY.md:18`、`README.md:45`、`README.zh.md:45` 均这样要求收工；实际 `bin/qwb-wake.sh:688-697` 在主控锁不属于本 pane 时也打印「孤儿值守退出不消费唤醒」并返回 0，`bin/qwb-wake.sh:665-673,695-697` 在本轮写入前失锁也可能返回 0。审核在隔离安装目标、无主控锁下调用 `HERDR_PANE_ID=wF2:pG bash .../qwb-wake.sh --project ... --block --max-ms 1`，输出为孤儿值守提示且 `rc=0`。影响：锁丢失或被接管时，Codex 会按新说明误报任务已清空并收工，未结项可能无人接续。修复建议：将 0 写成「本轮值守结束」，只有核对输出、锁主及账本确无未结项后才按空账本收工；遇孤儿提示或归属不明时按锁恢复流程处理。三份新说明须一致，勿为文档修改运行时退出码。

其余限定走读：§1 三宿主单选及健康未知不启第二路的文字一致；安装器 `bin/qwb-init.sh:114-137,139-207` 对应 Claude/agents 注入与 Pi 安装路径；Pi 扩展 `templates/pi-extensions/qwb-watch.ts:303-336` 对应 `/reload` 后加载、`session_start`/晚获锁 `turn_end` 和 `followUp`；Codex 的 2、124 及前台循环与 `bin/qwb-wake.sh:683-703` 相符。`templates/brief-include.md` 未动，仍是工人附页。当前 wake/Pi 扩展 SHA256 分别为 `f770cb0f2a43d7bf6170e7909829be3e30cf256c22c5cab0c3cb2e81b2a0653f`、`c2aa32e5abd8e297767070edcce7c09737b6d37e47b84bbcadedb0997a2746f2`，与旧 `/private/tmp/qwb-production-e2e-bayoulto/receipt.json` 的对应安装文件哈希相同；旧收据的 Codex 2/2/124/0、`/tmp/qwb-lifecycle-r2-pi.log` 的 15 项是历史证据，不证明本轮真实 Pi `/reload`、Claude Stop 或 Codex 180000ms 等待。执行者本候选 `fast` 退出 0 的记录见 `/tmp/qwb-simplify-wake-entry-final-fast.log`；本审核仅独立重算候选哈希、走读源码、运行上述隔离调用及 `git diff --check`，没有跑 fast/full。

本轮审点数：2（未知宿主占锁；Codex 0 的文档语义）。Standards 0，Spec 2。AMEND。
