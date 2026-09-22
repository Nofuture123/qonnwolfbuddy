# 生产收敛基线（主控实测，非独立审核）

日期：2026-09-22。源码：`1c500b38c014be9e55aa33fede2735ebaaf17d16`，main。开局工作区干净；运行期间主控新增任务文档，运行时源码未改。

环境：macOS；Herdr 0.9.1；Node v26.8.1；ShellCheck 0.11.0；Python 3.14.6；Git 2.54.0 (Apple Git-157)。

| 命令 | 退出码 | 实测耗时 | 结果 |
| --- | --- | --- | --- |
| `bash bin/qwb-test.sh fast` | 0 | 1.38s | Bash 语法与 ShellCheck |
| `bash bin/qwb-test.sh full` | 0 | 88.35s | smoke 567 PASS / 0 FAIL；REVIEW-IDENTITY PASS；LINT PASS |

使用 `/usr/bin/time -p` 测量 wall time。本轮各门只跑一次，无重试。全门声明来自被忽略的本机 `qwbuddy/config.sh`，与跟踪的 `qwb.config.sh` 相同：smoke、review-identity、lint 串行。smoke 内 Pi 测试使用假子进程与时钟，不构成真实 Pi/Herdr 闭环证据。

全门有历史任务场景未冻结、占位状态行警告；退出码 0 不代表这些警告已经处理。lint 第 9 项把正文中含尖括号的历史状态行全文拼成警告，输出量较大，属于待评估成本点；本轮未改历史票。

- fast 原始日志：`/tmp/qwb-production-fast.log`，SHA-256 `bf3363f70a8e0c01e39c4b605ad2918edaa7a2b29ff349d3d5b4d9bb2c282c6f`。
- full 原始日志：`/tmp/qwb-production-full.log`，SHA-256 `524d3e3a419ae5e35b8ab6832a6826160156a505930b0a27b701da70d120e386`。

## 已确认的额外事实

- 新临时项目执行 `bash bin/qwb-init.sh <项目>` rc=0。写入合成 `.pi-watch.err` 后，`git check-ignore qwbuddy/.pi-watch.err` 非 0；对照 `.watch` 被忽略。Pi 扩展错误日志会污染安装项目的 git status，待修复。临时目录由 TemporaryDirectory 回收。
- `bin/` 当前有 11 个 shell 文件，合计 2865 行；README 的 8 个/~1000 行、405 测试、45s 全门不再描述当前状态。
- `templates/QWBUDDY.md` 开局无条件 `--ensure` 与随后按 harness 使用隐形值守存在冲突；文档修复票正在隔离 worktree 执行。
- 历史 `docs/E2E-RUNBOOK.md` 的基线是 e917008，首次派发有人工介入；不能外推当前候选的无人干预闭环。

## 本轮状态

生产就绪未获证明。正式运行时审核、文档校准、运行时修复及当前候选真机闭环均尚未完成。

用户 2026-09-22 指定：执行 GPT Sol medium，审核 GPT Sol high。两者均在独立可见 Herdr 原生会话运行；该当日要求覆盖模板跨家族默认。原先 Pi/Claude 会话已停止，未完成输出不算审核或交付。主控 tab 保持单 pane，既有执行/审核 pane 已移到后台 tab，不再分割主控窗口。
