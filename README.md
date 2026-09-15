# qonnwolfbuddy

**Q-Wolf Buddy（简称 QW buddy / 机器写法 `qwbuddy`）** —— 装进单个项目的轻量 AI 主控。

这是一份**母本仓**：存放模板、脚本与安装器。真正的使用方式是把它**装进某个项目**，用 `qwbuddy init` 一条命令配好。

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

## 母本仓规划布局

```
qonnwolfbuddy/
├── README.md          本文件
├── docs/              设计文档（已完成）
├── templates/         装进项目的模板（待建）
│   ├── QWBUDDY.md         主控总说明书
│   ├── roles/             主控 / 审核者 / 执行者 / 咨询师
│   ├── config.json        工人表 + 派工规则 + 超时
│   ├── agents-hook.md     写入项目 AGENTS.md 的钩子片段
│   └── claude-hook.md     写入项目 CLAUDE.md 的钩子片段
├── bin/               脚本（待建）
│   ├── qwb-init.sh        装进新项目
│   ├── qwb-run.sh         派发 + 记账
│   ├── qwb-wake.sh        值守：叫醒主控
│   └── qwb-status.sh      点名 + 汇报
└── tests/             （待定）
```

装进项目后的布局见 [`docs/DESIGN.md`](docs/DESIGN.md) 第 8 节。

## 下一步

1. 写 `templates/` 下的说明书与角色文件
2. 写 `bin/` 下四个脚本（约 300 行 shell）
3. 挑一个真实项目跑通一轮：派活 → 工人在 Herdr 窗口干活 → 值守叫醒主控 → 主控验收 → 记账

设计已定稿并经过独立审核（见 docs/），可以按 `docs/DESIGN.md` 第 13 节的清单开工。
