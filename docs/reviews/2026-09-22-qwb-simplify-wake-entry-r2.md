# 票①独立审核 r2：r1 两项 AMEND 返修

结论：PASS。本轮仅复审 r1 两项及直接相关的文档一致性，不重开历史范围。

对象：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-wake-entry`；HEAD `33ab7e4d15926c21fe9199efdbaffeff7f8393cd`；未提交 `git diff --binary HEAD` 为 28653 字节，SHA256 `a20d2e75f485f4d387d7922e6a46faec186f5cf00659443652c18d93cf879eb8`。审前及写报告前两次核对均相同。改动仍限 README.md、README.zh.md、docs/DECISIONS.md、templates/QWBUDDY.md、templates/agents-hook.md、templates/claude-hook.md。

1. r1 未知宿主占锁：已修复。`templates/QWBUDDY.md:11-13` 现先识别 Claude Code/Codex/Pi，未知即报告并停止且不取锁；确认后才 acquire、点名。`templates/agents-hook.md:5-6` 与 `templates/claude-hook.md:5-6` 均要求读完整总说明书，并按相同顺序接入。`README.md:35`、`README.zh.md:35`、`docs/DECISIONS.md:515` 同步说明取锁前识别。历史 tab 仅供手工排障，在 `templates/QWBUDDY.md:144,152` 与 `docs/DECISIONS.md:517` 明确，不再是未知宿主的默认退路。本项为入口和安装目标走读，未模拟第四种真实宿主。

2. r1 Codex 退出码 0 误判空账本：已修复。`templates/QWBUDDY.md:19` 与脚本表 `templates/QWBUDDY.md:144` 把 0 定为本轮值守结束，要求核对输出、锁主和账本后才可认定无未结项；孤儿提示或归属不明按锁恢复处理。`README.md:45`、`README.zh.md:45`、`docs/DECISIONS.md:515` 同义。实际 `bin/qwb-wake.sh:688-697` 在失锁时仍可返回 0；执行者隔离安装目标的 `/tmp/qwb-simplify-wake-entry-r2-orphan.log` 记录孤儿提示和 rc=0，与新说明相符。本审核没有把它当作空账本证明。

验证边界：本审核独立复核 diff 身份、`git diff --check HEAD` 退出 0，并 `cmp` 隔离目标 `/tmp/qwb-wake-entry-r2-install.1dOYY3/qwbuddy/QWBUDDY.md` 与源模板、隔离 Pi 扩展与源模板，均退出 0。执行者 `/tmp/qwb-simplify-wake-entry-r2-receipt.json` 记录本候选 `bash bin/qwb-test.sh fast` rc=0；本审核未重跑 fast。主控先前 full rc=0 绑定的是旧 diff `018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438`，不能用于本候选；本审核未跑 full，也未实测真实 Pi `/reload`、Claude Stop 或 Codex 180000ms 前台等待。运行时源码、state、场景与历史决策旧段未修改，本轮未提交。

审点数 2；两项均闭环。PASS。
