# 生产运行时返修独立复审

**结论：AMEND。** 基线 `1c500b38c014be9e55aa33fede2735ebaaf17d16`，候选 `d9ed8052ccbcfbc1e286ade07853026a3ae5d470`。只审 `git diff baseline..candidate` 中本票白名单，并用 `git show candidate:文件` 核对行号；当前 main 未当作候选。未重报已排队的 hook/安装/路由/worktree 生命周期问题，未跑全门、未创建真实 Herdr 窗口或派发。

## 发现 1：持 `flock` 的父进程被终止后，内层回收仍可删除新活锁

- **问题与行号**：`bin/qwb-lock.sh:47-60` 由 Perl 进程对 `qwbuddy/` 加 `flock`，然后 `system @cmd` 启动内层 Bash；真正的判死、`rm -rf`、重建在子进程 `bin/qwb-lock.sh:100-108` 执行。只要 Perl 父进程在子进程尚未完成临界区时被 SIGKILL，内层 Bash 仍会继续，但另一调用已能取得 `flock`。`docs/DECISIONS.md:487` 称“acquire/release ... 持锁区处理”，这一异常路径不成立。
- **已复现（未注入 `QWB_LOCK_GUARDED`）**：临时项目放死 owner `pid:999999`。A 用候选脚本正常 `acquire`，内层 Bash 判死后在 `rm` 前由假 `rm` 等待；只 SIGKILL A 的 Perl 持锁父进程，再启动 B 的正常 `acquire`。B 在 A 内层仍暂停时 `rc=0`，owner 已是 B 的**存活 PID**；放行 A 后，A 内层删除 B 的活锁并写成 A。观测：A 外层 `rc=137`、B `rc=0`、`owner_before_A=B`、`owner_final=A`。这是持锁进程异常终止，非调用者人为设置内部环境变量的越权场景。
- **影响**：B 已获锁并可作为主控开始工作，却在返回成功后失去锁；A 的孤儿内层操作仍会覆盖它，唯一主控保护失效。候选 `tests/runtime-readiness.sh:68-80` 仅杀一个独立持锁 Perl 进程，未覆盖“父死、内层回收继续”的真实包装器路径。
- **最小修复**：让执行回收/释放的进程在整个临界区持有同一内核锁（例如明确继承并保有已加锁 FD，或避免由可单独存活的子进程执行受保护操作），并用上述受控交错测试 SIGKILL 持锁父进程；另一获取者在内层结束前不得获锁或被随后删除。

## 其余两审点

- **Pi probe**：`templates/pi-extensions/qwb-watch.ts:153-173` 已把 probe `exit=2` 接入普通摘要路径；候选 `tests/pi-ext.test.mjs` 的定向测试 `rc=0，10 passed`，核对一条消息、零故障、无退避、立即恢复普通 `--block`。本轮未发现该 diff 的可行动回退。
- **派发**：`bin/qwb-run.sh:365-466` 对同名复用核对 worker、物理 cwd、workspace 和本票历史；`:718-777` 保留 F2 前置状态与指纹，并按原字节偏移将本次 `dispatch:` 原位改为 `not-sent:`；`:791-844` 覆盖 herdr、显式 `--pane`、pane-run 的投递错误，`bin/qwb-lint.sh:175-180` 同步场景末节边界。候选定向 `tests/runtime-readiness.sh` 为 `rc=0，17 PASS`，含并发追加保留及失败后 lint/重派。本轮未发现这部分 diff 的可行动回退。

**本审核实际命令与清理**：将固定候选 `git archive` 导入临时目录，执行 `bash tests/runtime-readiness.sh`（`rc=0，17 PASS`）、`node tests/pi-ext.test.mjs`（`rc=0，10 passed`）、相关 Shell `bash -n`（`rc=0`）、`bash bin/qwb-lint.sh`（`rc=0，LINT PASS`）；`git diff --check baseline..candidate -- <白名单>` 为 `rc=0`。未执行 `tests/smoke.sh` 或 full gate；主控此前的全门不作为本候选证明。临时导出、假命令与隔离项目已清理，`ps` 未见这些临时目录标识的残留进程。
