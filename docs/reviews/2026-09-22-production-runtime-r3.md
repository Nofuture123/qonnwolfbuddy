# 生产运行时锁返修第三轮复核

**结论：PASS（仅本轮唯一锁审点）。** 基线 `d9ed8052ccbcfbc1e286ade07853026a3ae5d470`，候选由 `git rev-parse 856f870` 固定为 `856f87049bab37eb9e42dcf3fe491373003ca864`。只审 `git diff baseline..candidate` 的 `bin/qwb-lock.sh`、`tests/runtime-readiness.sh`、`tests/smoke.sh`、`docs/DECISIONS.md`，并用 `git show candidate:文件` 核对行号；差异仅这四个白名单文件。未重审 Pi、派发、边界或其他生命周期问题。

## 审点：真正执行临界区的子进程持有同一锁 FD

- **实现证据**：候选 `bin/qwb-lock.sh:52-65` 在 Perl 对稳定的 `qwbuddy/` 目录取得 `flock` 后，读取 FD 标志并清除 `FD_CLOEXEC`，再 `system` 启动实际执行回收/释放的 Bash；内层 Bash 的判死与删除重建位于 `bin/qwb-lock.sh:98-113`。因此 Perl 父进程单独死亡时，已加锁 FD 仍由内层进程持有。`docs/DECISIONS.md:487` 的新说明与该实现相符。
- **候选定向测试**：将固定候选 `git archive` 导入临时目录，运行 `bash tests/runtime-readiness.sh`：`rc=0`、**18 PASS**、`RUNTIME READINESS PASS`。其中 `tests/runtime-readiness.sh:71-105` 从正常 `qwb-lock.sh acquire` 入口暂停内层 `rm`，SIGKILL 真正的 Perl 父进程，确认 B 在 A 结束前未返回，随后确认 B 拒绝活锁、owner 未被覆盖。
- **独立隔离复现**：另从候选 blob 导出 `qwb-lock.sh` 到临时项目，用假 `rm` 在 A 判死后暂停；找到该内层 Bash 的 Perl 父进程并 SIGKILL，**未注入 `QWB_LOCK_GUARDED`**。B 的正常 `acquire` 在 A 暂停的 0.6 秒观察窗内仍未返回；放行 A 后，A 外层 `rc=137`，B `rc=1`，最终 owner 为 A 指定的存活 PID，B 未删除或覆盖它。此前 r2 的“父死后 B 抢先进入、孤儿 A 覆盖活锁”交错在该候选上未复现。
- **资源与范围**：临时导出、假命令和锁目录已由临时目录清理；`ps` 未见带本轮临时目录标识的残留进程。白名单 `git diff --check baseline..candidate` 为 `rc=0`。未跑全门、Pi/边界测试、真实 Herdr 窗口或派发。

本轮没有可行动 AMEND。PASS 只覆盖上述固定候选的锁 FD 继承与父进程异常终止交错，不等于整个生产候选或其他已排队问题通过。
