# 生产说明与开局值守指引校准

state: verified
scenarios-fp: fd17172ea0d846647a7d10f637e0d0a43bdd390a

## 0. 目标与范围

执行者只改 README.md、README.zh.md、templates/QWBUDDY.md；不递归派发。
基线 1c500b38c014be9e55aa33fede2735ebaaf17d16。主账本为本文件绝对路径，不改 state。
保留产品用途、安装/使用步骤和准确的架构边界，以简洁中英文内容替换无法证明的营销断言。

- README 声称 8 个脚本约 1000 行、405 测试、full 45 秒、零依赖、毫秒级指纹、绝对不丢行等已经不准确。当前 bin 11 个文件共 2865 行；主控本次 fast 1.38s rc=0、full 88.35s rc=0、smoke 567 PASS、review-identity PASS、lint PASS。这些是该 SHA 在 macOS 当前环境的观测，不是速度保证。
- 明示 bash 与实际脚本依赖（读安装/运行脚本确认），测试环境 Node v26.8.1、ShellCheck 0.11.0、Python 3.14.6、Herdr 0.9.1；区分测试与运行依赖。不要编造最低版本或已验证 Linux 支持。
- docs/E2E-RUNBOOK.md 为旧 e917008 基线且首次派发需手动介入，不许称当前无人值守闭环已验证。删除未经测量的竞品、98% 瘦身、绝对保障等断言。
- 起步使用 pnpm 示例。值守按 harness 选择，模板 §1.5 无条件 --ensure 与 §1.6 隐形值守冲突：合并为单一按 harness 分流的步骤；Pi 要有实际扩展入口，Codex 按现有前台 checkpoint，Claude 按 hook，其他才 --ensure。不能默默改运行时契约。
- 动态 ID 不写入配置：模板开局去掉要求把当前 pane/workspace ID 写入 config 的步骤；pane 默认已可由 HERDR_PANE_ID 解析（核代码），跨项目 workspace 则介绍现有解析和命令/环境可行范围，若缺运行时支持在账本报告，不编造参数。不改模板 config/runtime，本票只文档。
- 路线图保留仍未验证事项，进生产状态必须诚实说明当前仍在收敛审核，不许宣布已生产就绪。

## 1. 验收场景

### 正常路径：文档与当前产品一致
Given 当前源码与本票列明的主控实跑证据
When 按中英文 README 阅读安装和开局指引
Then 依赖、测试范围、唤醒机制与限制一致，步骤不启动两个值守，不要求动态 ID 持久化。

### 失败路径：缺证不宣传成功
Given 只有旧 SHA 且有人工介入的真机报告
When 读当前版本的生产可用性与性能声明
Then 不声称当前无人干预真机通过、不把 mock 或单测当真实闭环，不保留虚构对比数据。

## 2. 验证与交付

只跑 bash bin/qwb-test.sh fast 和 bash bin/qwb-lint.sh，不跑全门、不联网、不改历史审核/任务。
先读文件后改，仅提交白名单三个文件到当前任务 worktree 分支；不 push，不 merge，不清理 worktree。
往主账本追加 done:，含 SHA、改动、实际验证和限制。主控独立审核后收尾。
wake: 2026-09-22T06:40:20Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
dispatch: 2026-09-22T06:40:31Z worker=pi agent=qwb-production-docs pane=wF2:pH dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/production-docs

working: 主控补充核代码：tab 值守不自动读取 HERDR_PANE_ID；现有参数支持 --ensure --pane "$HERDR_PANE_ID"，可以不持久化 ID；block 模式依赖锁及 HERDR_PANE_ID，不需要目标 pane 参数。本票按真实参数写文档。
wake: 2026-09-22T06:42:21Z state=running fp=58ba8e5b6e385a6e2cf5c5c0d7df6247b0e24e71
done: 2026-09-22T09:00:00Z executor=codex commit=59eb8ffe66d3afe146aa6d03d8d941370c63800c; only README.md, README.zh.md, templates/QWBUDDY.md changed: corrected dependency/evidence/production claims, pnpm setup, harness-specific single watch path, --ensure --pane "$HERDR_PANE_ID", and non-persistent workspace/pane guidance; verification on committed files: bash bin/qwb-test.sh fast rc=0; bash bin/qwb-lint.sh rc=0 (LINT PASS; historical placeholder warnings); git diff --check rc=0; full gate and current-source unattended device E2E not run; no push/merge/worktree cleanup.
done: correction 2026-09-22T06:47:27Z: previous done line used an incorrect wall-clock timestamp; this line records the actual append time. Commit/evidence/limits in the previous line are unchanged.
wake: 2026-09-22T06:48:22Z state=running fp=f419630d4ec66c1e79cf406235c776fe800d715d
done: 2026-09-22T06:51:53Z docs correction commit=40250b7b5235e49cfbaa44c64cc99afc75e85b3b; only README.md, README.zh.md, templates/QWBUDDY.md changed: removed false per-command QWB_WORKSPACE environment override claim, documented config.sh assignment and automatic workspace resolution; bash bin/qwb-test.sh fast rc=0, bash bin/qwb-lint.sh rc=0 LINT PASS, git diff --check rc=0; no push/merge/cleanup.
wake: 2026-09-22T06:52:24Z state=running fp=fbc6058281b78998c3e32854761016251dec72ba
done: 2026-09-22T06:53:44Z docs review AMEND follow-up commit=556d6aac7769edccd3598513eff7615d11dce5df; only README.md, README.zh.md, templates/QWBUDDY.md changed: Pi each-startup lock then /reload plus live pi-ext check, and cross-workspace --ensure reuse limitation; prior workspace config precedence fix commit=40250b7b5235e49cfbaa44c64cc99afc75e85b3b; bash bin/qwb-test.sh fast rc=0, bash bin/qwb-lint.sh rc=0 LINT PASS, git diff --check rc=0; runtime fixes deferred to separate ticket; no push/merge/cleanup.
wake: 2026-09-22T06:54:24Z state=running fp=7191084f28f49b558fce53419396b91ed22b42d1
working: 2026-09-22T06:58:39.838726+00:00 主控已收回独立 Sol high 复核 PASS，范围 59eb8ff..556d6aa，仅三项文档返修。候选 556d6aac7769edccd3598513eff7615d11dce5df；主控 git diff --check rc=0，白名单仅三个文档。state=done 等合并候选的统一全门，暂不标 verified，不把文档 PASS 算作运行时生产就绪。

working: 2026-09-22T10:41:24.995773+00:00 主控验收：最终源码整合 4dbc28a，独立复审全部 PASS；整合 full rc=0/110.168s；当前同源安装副本真实 Codex Herdr 显式复用 pane 闭环通过，正负门与前台 block 2/124/0、worktree 收尾均实测。主线已快进合入；详见 docs/reviews/2026-09-22-production-final.md 的证据及未覆盖边界。state=verified。
worktree: merged branch=production-docs tag=-
