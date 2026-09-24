# 生产接入前优化 交付与验收

记录时间：2026-09-24T02:38:51+00:00。

分支 `qwb-production-optimization`（基线 846fcce）经过 r1–r4 四轮独立审核与返修，最终版本 `d807f27f933460a69638d628fb2abefc8e4f5adc` 已快进合并进本地 main。

本文件记录时的状态：

- 尚未 push。
- 未安装到生产项目。qonnwolf-sites 由使用者自己安装。
- 主仓中预存的 `docs/plans/` 草案不纳入本次提交。本分支自己的计划 `docs/plans/2026-09-23-production-optimization.md` 已随合并入库。

分工：

- 执行：Codex（gpt-6-sol / high，Herdr pane `wGR:p2`）。
- 独立审核：Claude Code（Opus 5.5，pane `wF2:p3`）。
- 真实 E2E 主控：Codex gpt-6-luna / max。

## 提交

代码定稿为 `556b828`。其后的 `d807f27` 只新增 r4 执行报告；`git diff --stat 556b828 d807f27` 只列出这一个文件。

| 提交 | 内容 |
|---|---|
| `f4d7c8a` | 原始实现：生产流程加固与 worktree Space |
| `87222a2` | r1 返修 |
| `9e9e7c9` | r2 返修 |
| `7ae8cad` | r2 执行报告 |
| `8ee1f84` | r3 返修 |
| `93a601a` `159f549` `787d98d` `ea2ab5d` `06f6f22` `a08c7fd` | r3 返修：E2E 脚本修正 |
| `0abb697` | r3 执行报告 |
| `556b828` | r4 返修（代码定稿） |
| `d807f27` | r4 执行报告 |

## 改动文件（40 个，+2832/−165）

- **bin/**：`qwb-init.sh`、`qwb-lib.sh`、`qwb-lint.sh`、`qwb-lock.sh`、`qwb-run.sh`、`qwb-status.sh`、`qwb-test.sh`、`qwb-wake.sh`、`qwb-worktree.sh`。
- **templates/**：`QWBUDDY.md`、`TASK.md`、`host-watch-guide.md`、`worker-launch-guide.md`。
- **docs/**：`DECISIONS.md`、`DESIGN.md`、`plans/2026-09-23-production-optimization.md`，以及 r1–r4 审核报告和各轮执行报告。
- **tests/**：
  - 修改：`smoke.sh`（新增 §80–83 等）、`boundary-readiness.sh`、`runtime-readiness.sh`、`worker-config.py`。
  - 新增：`worktree-space.py`、`r2-cli.py`、`invalid-ledger.py`、`r4-cli.py`、`on-demand-guide.py`、`e2e-real.sh`、`e2e-real.py`、`fixtures/herdr/worktree-open*.json`。
- **根目录**：`README.zh.md`。

## 各轮审点

- **[r1](2026-09-24-qwb-production-optimization-r1.md)**（2 MEDIUM + 1 LOW），[执行报告](2026-09-24-qwb-production-optimization-r1-execution.md)：
  - Space 所有权与收尾安全；
  - 带 Space 收尾的回归保护；
  - `--archive` 部分失败的续做。
- **[r2](2026-09-24-qwb-production-optimization-r2.md)**（2 MEDIUM + 4 LOW），[执行报告](2026-09-24-qwb-production-optimization-r2-execution.md)：
  - 安装器文件权限；
  - 真实闭环；
  - separate-git-dir / submodule 布局；
  - 删分支阶段的续做；
  - 遗留的分支配置；
  - 误导性警告。
- **[r3](2026-09-24-qwb-production-optimization-r3.md)**（1 HIGH + 1 LOW），[执行报告](2026-09-24-qwb-production-optimization-r3-execution.md)：
  - 账本出现非法 UTF-8 时，票从点名和值守中消失；
  - zcode / cmd 启动文档过时；
  - 另新增真实 E2E 脚本。
- **[r4](2026-09-24-qwb-production-optimization-r4.md)**（1 MEDIUM + 2 LOW），[执行报告](2026-09-24-qwb-production-optimization-r4-execution.md)：
  - 全局 `LC_ALL=C` 导致唤醒摘要成为非法 UTF-8，被 Herdr 拒收；
  - 默认工人名依赖 locale，且会重名；
  - 非法 state 文档过时。
  - r4 报告末尾已追加更正：重名机制与数字、全局配置条目的说法。

## 门与收据

**执行者**（最终 SHA d807f27）

- fast：rc=0。
- full：报告 `/tmp/qwb-full-d807f27.md`，日志 `/tmp/qwb-full-d807f27.log`，663 PASS / 0 FAIL。

**审核者独立复跑**（d807f27 导出副本）

- full：FULL_RC=0，耗时 218s，663 PASS / 0 FAIL。
  - §83「R4 UTF-8 唤醒摘要与中文票工人名公开 CLI 回归」是 SMOKE PASS 之前的最后一节。
  - REVIEW-IDENTITY PASS，LINT PASS。
  - 节标题与执行者日志逐行一致。
- fast：rc=0。

**反转验证**

- `tests/r4-cli.py` 在 0abb697 上，wake 和 name 两组都是 rc=1：严格 Herdr 替身拒收摘要；两张中文票都叫 `qwb--e2e`。
- 在 d807f27 上 rc=0。

## 真实 E2E（计划第 6 条）

运行在代码定稿 556b828 上，使用中文票 `2099-01-01-真实闭环-e2e`。

| 工人 | 报告 | 断言 | rc |
|---|---|---|---:|
| devin `swe-2-max` | `/tmp/qwb-e2e-devin-556b828.md` | 10 条全 PASS（含默认工人名 `qwb--e2e-8c270138`） | 0 |
| cmdc `deepseek/deepseek-v4-flash` | `/tmp/qwb-e2e-cmdc-556b828.md` | 9 条全 PASS | 0 |

审核者直接核对了两个临时项目：

- state 为 verified。账本里有 scenarios-fp、worktree-space、dispatch、done、wake、`worktree: merged`。
- main 上的 `e2e/hello.txt` 与 nonce 一致。
- 只剩 main 分支，没有任务 worktree，没有 `branch.<票>.*` 配置。
- 工作区里唯一的改动是活账本本身，r3 时也是如此。
- cmdc 的 done 行有 647 个字符，说明真实闭环中走了 160 字符截断，并经 Codex `--block` 投递成功。

`~/.codex/config.toml` 的 SHA-256 在跑前、两轮之间、跑后和验收时都是 `26363e19…ce2d2`。

## 真实 Herdr 复放（r4 审点 1）

- **执行者**：日志 `/tmp/qwb-r4-replay-final.log`。所用 named session 已删除。
- **审核者**：在 `qwbrev-iso3` 中用 `--once` 投递，结果如下。
  - 一条 249 个字符（729 字节）的中文行，被截成前 160 个字符送达，与原文逐字一致；从 pane 读回的文本是合法 UTF-8。
  - 末行含 `\x80\x82` 的账本，坏字节被替换成 U+FFFD 后送达。
  - 同一损坏账本再跑两轮，都按指纹跳过，没有重复叫醒。
  - status 仍把这张票列为未结，lint 仍 FAIL。

## 未覆盖

- 没有安装到 qonnwolf-sites。
- 真实闭环只覆盖 Codex 主控加 devin、cmdc 两种工人：
  - Claude Code、pi 主控没有跑真实闭环，pi-kimi 工人也没有跑；
  - zcode 不可用（Herdr 不识别它，而且写文件默认要审批），使用者决定不用。
- 没有在真实闭环中核实 Claude Code 和 pi 宿主如何显示唤醒摘要。摘要现在已保证是合法 UTF-8。
- 没有测试 Herdr 服务重启后的恢复。
- 纯中文主题的默认工人名形如 `qwb---<8位哈希>`，连续短横，只影响观感。
- `~/.codex/config.toml` 里本分支之前就存在的临时信任条目（如 `/private/tmp/qwb-e2e-codex`）没有清理，等使用者决定。

## 待使用者确认

- 关闭 Space `wGR`。里面有 opus-qwb-plan 的 Claude 会话和 Codex 返修会话。
- 删除 worktree `/Users/rocky/.herdr/worktrees/qonnwolfbuddy/qwb-production-optimization` 和分支 `qwb-production-optimization`。
- push main。

## 收尾结果（2026-09-24T07:45:05+00:00，使用者确认后执行）

- **Space 与分支**
  - 已执行 `herdr worktree remove --workspace wGR`，rc=0，未用 --force。Space 已关闭，worktree 目录已删除。
  - 分支已用 `git branch -d` 删除（删除前指向 d807f27），没有残留的 `branch.qwb-production-optimization.*` 配置。
- **推送**
  - main 已推送：`846fcce..884b22c`。
  - `git ls-remote origin refs/heads/main` 返回 884b22c。
  - 本节是另一个文档提交，随后单独推送。
- **`~/.codex/config.toml`**
  - 删除了 6 个指向 /private/tmp 的信任条目，这些路径都已不存在。projects 从 101 条变为 95 条。
  - 其余配置解析后完全一致，文件权限保持 0600。
  - 备份：`~/.codex/config.toml.bak-20260924T074430Z-tmp-trust`。
- **Herdr 会话**
  - 审核用的 named session `qwbrev-iso3` 已 stop 并 delete。
  - default 会话中只关闭了 wGR；同期消失的 wHA、wHD、wHE 属于 qonnwolfai-student 的 simplify 工人，不是本次操作关闭的。
