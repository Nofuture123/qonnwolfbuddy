# Q-Wolf Buddy (`qwbuddy`)

> 面向单项目的轻量级代码库内置 AI 主控规范与运行时。使用者只提需求；QW buddy 负责任务派发、执行者隔离、自动唤醒、验收门禁与账本审计。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/shell-bash%203.2+-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)]()
[![Tests](https://img.shields.io/badge/tests-405%20passed-brightgreen.svg)]()
[![Gates](https://img.shields.io/badge/quality%20gates-fast%200.7s%20%7C%20full%2045s-orange.svg)]()

<p align="center">
  🌐 <a href="README.md">English</a> | <b>简体中文</b>
</p>

---

## 它解决什么与为什么

在真实项目中使用代码智能体（Claude Code、Codex、Pi、Devin）时，普遍存在三个阻碍闭环的痛点：

| 问题 | 典型症状 | QW Buddy 解决方案 |
|---|---|---|
| **主控容易「叫不醒」** | 派活给后台工人后，10 分钟工人干完，主控的交互回合早结束了，永远不会主动回来验收或合入代码。 | 部署轻量值守脚本（`qwb-wake.sh`），监控账本状态，通过终端多路复用（`herdr`）自动将空闲主控重新唤醒。 |
| **没有身份切换约束** | 单个会话在架构设计、代码审查、编码执行和咨询之间随意漂移，上下文污染严重且范围不断发散。 | 固化明确的角色操作手册（`qwbuddy/roles/`）。强制独立审核必须换用不同模型家族及原生独立会话。 |
| **缺乏规范的派工标准** | 任务随意扔进某个 agent 会话，没有明确的验收场景、隔离工作区或失败路径防御。 | 强制推行结构化任务书（`tasks/YYYY-MM-DD-*.md`），包含 Given/When/Then 验收场景、基线指纹冻结与自动 git worktree 隔离。 |

**使用者角色**：只提需求。将规划、执行、验收与收尾落地全权委托给主控模型。

---

## 运行机制

### 整体架构

```
+-------------------------------------------------------------------------+
|                            使用者 / 开发者                              |
|                              只负责提需求                               |
+-------------------------------------------------------------------------+
                                     |
                                     v
+-------------------------------------------------------------------------+
|                       主控（Herdr 内的 AI 会话）                       |
|  - 创建结构化任务书（tasks/YYYY-MM-DD-<topic>.md）                      |
|  - 执行 qwb-run.sh 将工人派发至隔离的 git worktree                      |
|  - 唤醒后独立执行验收门禁与测试，不采信自述                             |
+-------------------------------------------------------------------------+
            ^                                                |
            | 唤醒提示词                                     | 派发任务
            | ("看账本：未结项待处理...")                    v
+-----------------------+                        +------------------------+
|      值守守护脚本     |                        |      工人（Agent）     |
|     (qwb-wake.sh)     |                        |      (Herdr Pane)      |
|  - 巡检未结项账本     |                        |  - 在 worktree 中运行  |
|  - SHA1 进展指纹去重  |                        |  - 仅追加状态行        |
|  - 超时兜底重叫       |                        |    (working:/done:)    |
+-----------------------+                        +------------------------+
            |                                                |
            | 读取未结项任务书                               | 追加状态与证据
            v                                                v
+-------------------------------------------------------------------------+
|                          项目账本（tasks/*.md）                         |
|             唯一事实来源：任务规格、验收场景、证据与审计留痕            |
+-------------------------------------------------------------------------+
```

### 核心机制

| 核心机制 | 承载组件 | 强制执行的行为与保障 |
|---|---|---|
| **进展指纹唤醒与超时兜底** | `qwb-wake.sh` | 计算进展指纹 `sha1(state + "\n" + 最后状态行)`。指纹未变跳过唤醒；超过 `QWB_REWAKE_MS`（默认 30 分钟）无新进展时无条件兜底重叫，防工人崩溃挂起。 |
| **规格疑点门与显式修订** | `qwb-run.sh` | 拦截规格疑点（`blocked: spec-defect:`）。在主控记录 `working: spec-resolved:` 处置前禁止重派。改动场景必须通过 `--revise-scenarios=<原因>` 显式修订。 |
| **验收场景冻结** | `qwb-run.sh`, `qwb-lint.sh` | 派发前必须包含 BDD 验收场景（Given/When/Then 且至少一条失败路径）。派发写入 `scenarios-fp:` 基线；后续无痕改动直接导致 lint 报错。 |
| **Worktree 全生命周期** | `qwb-worktree.sh` | 默认自动在 `.worktrees/<任务id>/` 隔离副本派发。提供 3 种规范收尾通道：`--merged`（校验合入后清理）、`--archive`（打 tag 归档后清理）、`--keep`（冲突保留）。删除前核实 HEAD OID 未变。 |
| **审核身份独立性校验** | `qwb-lint.sh` | 强制核验要求独立审核的票（`review-required: yes`）。检查 `review-impl` 与 `review-rev` 使用不同模型家族和不同原生会话 ID，拒绝同家族自审。 |
| **双层质量门禁** | `qwb-test.sh` | 执行项目自定义的快门（`QWB_GATE_FAST`，约 0.7s）和全门（`QWB_GATE_FULL`，约 45s）。未声明门直接报错拒绝，防止假绿。 |

---

## 快速上手

### 1. 装进目标项目

从 `qonnwolfbuddy` 母本仓根目录执行安装脚本：

```bash
# 幂等执行：复制规范模板、初始化 tasks/ 账本并追加 AGENTS/CLAUDE 钩子
bash bin/qwb-init.sh /path/to/target-project
```

### 2. 声明项目质量门

打开 `/path/to/target-project/qwbuddy/config.sh` 并声明你的项目质量门命令：

```bash
# Node / TypeScript 项目示例：
QWB_GATE_FAST='npm run lint'
QWB_GATE_FULL='npm run lint && npm test'
```

验证质量门能够正常执行：

```bash
cd /path/to/target-project
bash qwbuddy/bin/qwb-test.sh fast    # 运行快门（必须退出码 0）
bash qwbuddy/bin/qwb-test.sh full    # 运行全门（必须退出码 0）
```

### 3. 初始化主控并完成点名

在目标项目目录下打开你的主控 AI 会话（Claude Code、Pi 或 Codex），发送开局指令：

```text
你现在是 QW buddy。请阅读 qwbuddy/QWBUDDY.md 并进入「主控」角色。
```

检查活跃任务、工人窗口与值守运行状态：

```bash
bash qwbuddy/bin/qwb-status.sh
```

### 4. 派发任务书

在 `tasks/YYYY-MM-DD-<topic>.md` 编写任务规格书，必须包含「验收场景」块：

```markdown
## 验收场景

Scenario: user_successful_export
  Given 数据库中存在有效业务数据
  When 触发数据导出接口
  Then 导出文件成功写入目标路径

Scenario: user_export_invalid_format_fails (失败路径)
  Given 请求参数传入不支持的导出格式
  When 触发数据导出接口
  Then 返回退出码 1 并输出格式错误提示
```

将任务派发给后台工人在隔离 worktree 中执行：

```bash
# 工人必须已在 qwbuddy/config.sh 的 QWB_WORKERS 中声明（默认：codex pi claude）。
# 如需使用 devin，先将其追加进配置：QWB_WORKERS="codex pi claude devin"
bash qwbuddy/bin/qwb-run.sh \
  --project . \
  --task YYYY-MM-DD-<topic> \
  --worker codex \
  --name feat-export
```

启动值守守护，持续监控账本并在工人完工后自动唤醒主控：

```bash
bash qwbuddy/bin/qwb-wake.sh --ensure --pane <主控-pane-id>
```

---

## 设计原则

### 三把尺子

1. **谁的状态归谁**  
   厂商特定状态（上下文窗口、会话缓存、token 缓冲区）留在厂商内部；项目业务状态（任务书、执行进度、验证日志、教训总结）全部存放在 AI 外部的 Markdown 文件中（`tasks/*.md`）。
2. **薄即抗淘汰**  
   单个厂商的 Harness 发展迅速，会不断吸收等待与唤醒等基础设施。QW buddy 只实现跨模型、跨会话不可替代的核心能力：跨模型路由、持久化项目记忆与对抗性验收纪律。
3. **规范不写在纸上**  
   用可执行的测试断言取代写在纸上的行为指南。每一条规范均由 `qwb-lint.sh` 检查、由 `tests/smoke.sh` 负例测试反转验证，并通过自动化门禁严格拦截。

### 明确不做的事

| 非目标 | 决策理由 |
|---|---|
| **不做中心化注册表或多仓同步** | 专为自包含的单个项目设计，以代码仓库为绝对边界。 |
| **不发人类通知** | 绝不接入飞书、钉钉、Slack 或系统弹窗。主控醒来干活，人类正常休息。 |
| **不引入后台数据库或消息队列** | `tasks/` 纯 Markdown 文件即可充当持久化队列、状态账本与审计日志。 |
| **不做纯 Headless 静默工人** | 工人必须在可见的交互式终端窗口（`herdr`）中运行，确保随时可观察、可调试。 |
| **不自动拉起已死亡的主控进程** | 唤醒存活且空闲的主控。若整机重启或会话退出，使用者根据账本直接续接。 |
| **不依赖厂商专有插件或私有 Hook** | 纯 POSIX / Bash 实现，零外部复杂依赖。 |

---

## 母本仓布局

```
qonnwolfbuddy/
├── README.md               # 英文主页文档与项目说明
├── README.zh.md            # 中文主页文档与项目说明
├── qwb.config.sh           # 本母本仓自用的质量门声明
├── docs/                   # 系统设计、运行手册与审核报告
│   ├── DESIGN.md           # 权威系统架构设计文档
│   ├── DECISIONS.md        # 架构决策记录（ADRs）
│   ├── E2E-RUNBOOK.md      # 真实多模型闭环运行手册
│   └── reviews/            # 10 份独立审核与咨询报告
├── templates/              # 安装到目标项目的资产模板
│   ├── QWBUDDY.md          # 主控核心操作说明书
│   ├── TASK.md             # 任务书模板（含场景块与身份字段规范）
│   ├── config.sh           # 工人表、超时与质量门配置（Bash 可直接 source）
│   ├── roles/              # 角色手册：主控、审核者、执行者、咨询师
│   ├── agents-hook.md      # 目标项目 AGENTS.md 引导钩子
│   └── claude-hook.md      # 目标项目 CLAUDE.md 引导钩子
├── bin/                    # 运行时执行脚本（安装至 <项目>/qwbuddy/bin/）
│   ├── qwb-init.sh         # 安装器（幂等；仅在母本仓运行）
│   ├── qwb-run.sh          # 派发器（场景门校验、创建隔离 worktree、记账）
│   ├── qwb-wake.sh         # 值守守护（指纹去重、超时兜底重叫）
│   ├── qwb-status.sh       # 点名与状态汇总（聚合账本与 Herdr 状态）
│   ├── qwb-lock.sh         # 主控并发目录锁（原子 mkdir 锁）
│   ├── qwb-worktree.sh     # Worktree 生命周期管理（清点与 3 种收尾）
│   ├── qwb-test.sh         # 快门 / 全门执行器
│   └── qwb-lint.sh         # 仓库契约检查器（文档承诺、状态值域、死键等）
├── tests/                  # 验证测试套件与契约基线
│   ├── smoke.sh            # 冒烟测试套件（含历轮负例反转断言）
│   ├── review-identity.sh  # 独立审核身份核验专项测试
│   └── fixtures/herdr/     # 真实录制的 Herdr CLI 契约基线
└── tasks/                  # 项目自身账本与复盘教训
    └── lessons/            # 故障事后复盘与防御措施记录
```

---

## 测试与真实 Agent 验证

### 测试套件表现

每一次提交都必须通过可执行门禁验证。未声明门将以退出码 1 失败。

| 质量门 | 执行耗时 | 覆盖范围 | 执行命令 |
|---|---|---|---|
| **快门 (Fast Gate)** | `~0.7s` | 全部脚本的 Shell 语法检查（`bash -n`）+ 零告警的严格 `shellcheck` | `bash bin/qwb-test.sh fast` |
| **全门 (Full Gate)** | `~45s` | 405 项断言：冒烟测试、契约校验、负例拦截、身份核查与 lint 静态检查 | `bash bin/qwb-test.sh full` |

### 真实 Agent 严苛验证

- **真实闭环端到端验证**：使用真实 Devin（SWE-2 Max）工人、真实 Herdr 终端标签页、shell 值守与 Claude 主控完成了完整闭环验证（`docs/E2E-RUNBOOK.md`）。实证了完工自动唤醒、主控独立验收、蓄意破坏识别与 worktree 安全清理。
- **9 份对抗性审核报告 + 1 份架构咨询**：经不同模型家族（GPT-6 Astra High/Medium、Claude Fable 5.1）多轮对抗性独立审查（详见 `docs/reviews/`），外加一次重塑了规格疑点门机制的模型家族架构咨询。
- **致命缺陷 6 → 0**：彻底根除对抗性审核中暴露的全部 6 项致命安全与业务缺陷：
  1. *F3 唤醒死锁*：将仅看 `state:` 的静态去重重构为包含状态行的 SHA1 进展指纹。
  2. *F4 值守崩溃*：对终端投递失败进行容错，避免异常退出整个值守主循环。
  3. *G1 Detached HEAD 代码丢失*：废除分支名假设，全面以真实 HEAD 提交 OID 进行归档与比对。
  4. *H1 删除前 TOCTOU 竞态*：在执行删除命令前紧邻复核 HEAD OID，防止抹掉工人并发提交的新代码。
  5. *F1 工人挂起主控漏叫*：引入基于 `QWB_REWAKE_MS` 的超时兜底重叫，防工人无状态退出时主控永久沉睡。
  6. *F2 记账并发覆盖*：将原先快照整体覆盖任务书改为就地原子改写，保护工人并发追加的状态与证据。

---

## 路线图

- [x] 完成核心架构设计规范与 ADR 决策记录（`docs/DESIGN.md`, `docs/DECISIONS.md`）
- [x] 实现项目内置模板、角色手册与纯 POSIX bash 运行时脚本
- [x] 构建包含 405 项断言的测试套件，全面覆盖契约校验与反转负例断言
- [x] 在真实终端窗口中与真实模型完成闭环端到端验证（`docs/E2E-RUNBOOK.md`）
- [x] 通过多轮跨模型家族独立终审验收（`docs/reviews/2026-09-15-fable-终审.md`）
- [ ] 在生产级开源项目中实战试用并收集工作流反馈
- [ ] 实现针对首次 Agent CLI 初始化的工作区信任自动握手

---

## 许可证

本项目在 [MIT License](LICENSE) 许可下发布。
