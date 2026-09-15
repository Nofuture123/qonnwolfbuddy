# qonnwolfbuddy

**Q-Wolf Buddy（简称 QW buddy / 机器写法 `qwbuddy`）** —— 装进单个项目的轻量 AI 主控。

这是一份**母本仓**：存放模板、脚本与安装器。真正的使用方式是把它**装进某个项目**，一条命令配好：

```bash
bash <母本仓>/bin/qwb-init.sh <项目根>      # 幂等：复制模板 + 建账本 + 写钩子
```

装好后**先做两件事**：① 在项目的 `qwbuddy/config.sh` 里声明本项目自己的质量门（`QWB_GATE_FAST` / `QWB_GATE_FULL`，文件里有注释示例）；② 跑 `bash qwbuddy/bin/qwb-test.sh fast|full` 确认门能跑起来（未声明门会**明确报错**，不会静默当绿）。

## 它解决什么

使用者在项目里用 Claude Code / Codex / Pi 干活时，会遇到三个问题：

1. **主控会「叫不醒」**——任务派出去、工人干完了，主控回合结束就不再回来验收，流程断掉。
2. **没有身份切换**——同一个会话无法在「主控 / 审核者 / 执行者 / 咨询师」之间规范切换。
3. **没有派工标准**——什么活发给哪个模型（不同 CLI、不同能力、不同额度）没有明确判据。

QW buddy 把这三件事固化成一本书（说明书 + 角色文件）和几个脚本。

## 使用者的角色

**只做一件事：提需求。** 验收、落地、超时判断全部下放给主控（主控是强模型，判断力优于使用者本人）。

## 文档

| 文件 | 内容 |
|------|------|
| [`docs/DESIGN.md`](docs/DESIGN.md) | **架构设计（定稿）**——机制、职责、布局、MVP 边界 |
| [`docs/DECISIONS.md`](docs/DECISIONS.md) | **决策记录**——每条设计结论及其理由、被否掉的替代方案 |
| [`docs/reviews/2026-09-15-astra-review.md`](docs/reviews/2026-09-15-astra-review.md) | **Astra（gpt-6-astra high）独立审核**——送审快照、审核结论、逐条处置 |

## 母本仓布局

```
qonnwolfbuddy/
├── README.md          本文件
├── docs/              设计文档（已完成）
├── templates/         装进项目的模板（已完成）
│   ├── QWBUDDY.md         主控总说明书
│   ├── roles/             主控 / 审核者 / 执行者 / 咨询师
│   ├── config.sh          工人表 + 派工规则 + 超时（bash source 单一来源）
│   ├── agents-hook.md     写入项目 AGENTS.md 的钩子片段
│   └── claude-hook.md     写入项目 CLAUDE.md 的钩子片段
├── qwb.config.sh      本仓自用的质量门声明（快门 / 全门）
├── bin/               脚本（8 个；其中 qwb-init.sh 为母本仓专用，不随安装进入目标项目）
│   ├── qwb-init.sh        装进新项目（幂等；仅从母本仓运行）
│   ├── qwb-run.sh         派发 + 记账
│   ├── qwb-wake.sh        值守：以账本未结项为准叫醒主控（进展指纹去重）
│   ├── qwb-status.sh      点名 + 汇报
│   ├── qwb-lock.sh        主控锁（mkdir 原子目录锁）
│   ├── qwb-worktree.sh    worktree 清点与收尾（list / finish --merged|--archive|--keep）
│   ├── qwb-test.sh        快门/全门执行器（`qwb-test.sh fast|full`）
│   └── qwb-lint.sh        自身 lint（承诺未实现 / state 值域 / 死配置 / 非 ASCII 陷阱）
├── tests/             测试（已完成）
│   ├── smoke.sh           328 项断言（含历轮全部回归与 M1–M6 负例），须打印 SMOKE PASS
│   └── fixtures/herdr/    真录的 herdr 响应基线（假替身的契约依据）
└── tasks/             本仓自己的账本 + 错题本
```

装进项目后的布局见 [`docs/DESIGN.md`](docs/DESIGN.md) 第 8 节。

## 下一步

1. ~~写 `templates/` 下的说明书与角色文件~~ ✅
2. ~~写 `bin/` 下脚本~~ ✅
3. **挑一个真实项目跑通一轮**：派活 → 工人在 Herdr 窗口干活 → 值守叫醒主控 → 主控验收 → 记账

1、2 已完成并验收（见 [`tasks/2026-09-15-qwbuddy-mvp.md`](tasks/2026-09-15-qwbuddy-mvp.md) 的验收记录）。第 3 步待做。

## 质量门

```bash
bash bin/qwb-test.sh fast        # 快门：语法 + shellcheck（改一行跑它）
bash bin/qwb-test.sh full        # 全门：smoke + lint（合并前跑它）
```
