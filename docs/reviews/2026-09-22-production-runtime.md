# 生产运行时首轮独立审核

结论：**AMEND**。

冻结源：`1c500b38c014be9e55aa33fede2735ebaaf17d16`，审核时 `HEAD` 与之相同；对白名单六个源码文件执行 `git diff --exit-code 1c500b38c014be9e55aa33fede2735ebaaf17d16 -- <白名单>`，无差异。只读核查首轮三个审点；未创建 Herdr pane/tab，未跑全门。主控报告的 567 smoke PASS、review-identity PASS、lint PASS、88.35s 是主控证据，本审核未重跑，不能覆盖下列并发与失败路径反例。隔离复现均使用系统临时目录和假 Herdr 命令，退出时目录已清理；未改源码或既有任务书。

## 1. 死锁回收能删除刚被其他主控取得的活锁

- 证据：`bin/qwb-lock.sh:80-86` 先读取旧 owner、判死，再无条件 `rm -rf "$LOCK_DIR"`，之后才 `mkdir`。判死与删除之间没有独占恢复权，也没有在删除前复核目录身份。`bin/qwb-lock.sh:76-78` 的普通 `mkdir` 获取者可以在这个间隙完成获锁。
- 已复现：在临时项目内放 `pid:999999` 死锁；令 A 判死后停在删除前，B 先回收并写入 `owner=B`，再放行 A。A 删除 B 的活锁并写入 `owner=A`；A、B 都以 `rc=0` 报告“已获锁”。复现观测：`A_rc=0, B_rc=0, owner_after_B=B, owner_final=A`。
- 影响：B 已开始作为主控执行，但 A 也获锁，唯一主控约束失效；后续派发和账本写入可能并发冲突。
- 最小修复：给残留锁回收加独立的原子互斥；进入回收临界区后重新读取并判活 owner，只有仍为原死锁才删除，随后在同一临界区完成创建与 owner 写入。增加上述交错的确定性并发测试。

## 2. Pi `turn_end` 探测把已消费的 `exit=2` 当故障，漏交唤醒

- 证据：`templates/pi-extensions/qwb-watch.ts:189-196` 在 `exit 0` 闲置后运行 `--block --max-ms 1`；`templates/pi-extensions/qwb-watch.ts:153-160` 的 probe 分支只处理 `124`、`0`，把 `2` 送入 `fail()`，不会调用 `sendMessage`。但 `bin/qwb-wake.sh:622-630,649-650` 在有进展时先写 `wake:` 再以 `2` 退出。现有 `tests/pi-ext.test.mjs:198-220` 只覆盖 probe 的 `124/0`。
- 已复现：用冻结源码的 `createWatchCore` 注入子进程，依次触发主值守 `exit=0`、`onTurnEnd()`、probe `exit=2` 且 stdout 为“看账本：新进展”。观测 `messages=[]`、错误记录 `exit=2 连续失败 1 次`、只安排 100ms 故障退避，未立即重启值守。
- 影响：账本已经标记该进展被唤醒，Pi 会话却没有收到摘要；后续指纹去重可使这次进展持续漏报，直到新的进展或 running 票兜底重叫。
- 最小修复：probe 的 `2` 走与普通值守 `exit=2` 相同的摘要注入和立即重启路径；加 `turn_end` probe `exit=2` 的断言，验证消息、无故障计数及后续值守。

## 3. 派发记录可先于有效投递成立，复用接收者也未核对身份和目录

- 证据：`bin/qwb-run.sh:585-596,656-664` 在提示词投递前写 `state: running` 和 `dispatch:`；`bin/qwb-run.sh:715-728` 只在 `agent start` 失败时回滚，`agent prompt` 失败由 `set -e` 直接退出。复用判断 `bin/qwb-run.sh:365-385` 只读取同名 agent 的名称、状态和 pane，未核对真实 agent 类型、物理 cwd、workspace 或任务归属，却在 `bin/qwb-run.sh:702-705` 直接投递并报告复用。
- 已复现（两条隔离假 Herdr 路径）：① `agent start` 返回成功、`agent prompt` 返回 9：命令 `rc=9`，任务书仍为 `state: running` 且留有 `dispatch:`，新 tab 未回收。② 同名 idle agent 实为 `codex`、cwd=`/wrong/project`、workspace=`w9`，本次要求 `pi` 和临时项目根：命令仍 `rc=0` 报“已派发”，`dispatch:` 记录 `worker=pi pane=w9:p9 dir=<本项目根>`，提示词实际送往错误工人。
- 影响：主控和后续值守会把未投递或投给错误目录的任务当作已派发；错误工人可能在异地工作区处理本项目任务。
- 最小修复：复用前按 pane 实际 agent 类型、物理 cwd、workspace 与本票最近派发身份逐项核验，不符即拒绝；所有提示词投递失败路径回滚本次 `dispatch:` 与本次创建的 tab，并恢复或明确标记未成功的 `state`，只有投递成功才报告派发成功。为新建与复用各加投递失败测试，并加异目录/异工人拒绝测试。

三个审点的判定：锁互斥 **不通过**；值守消费与失败恢复 **不通过**；派发失败及复用 **不通过**。以上均为冻结源码加隔离复现所得，不采信已中止的上一轮审核结论。
