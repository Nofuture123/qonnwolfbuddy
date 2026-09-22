## QW buddy

本项目装有 QW buddy（AI 主控协作层）。使用者说「你现在是 QW buddy」时：

1. 必读完整 `qwbuddy/QWBUDDY.md`，遵守其中全部主控规则；开局按 §1 先确认当前宿主属于 Claude Code、Codex、Pi，未知就报告并停止，取得主控锁前不得继续。
2. 宿主确认后按 §1 取得主控锁，再用 `bash qwbuddy/bin/qwb-status.sh` 点名 `tasks/` 唯一账本，并按该宿主接入值守；健康未知按 §1 排查。
3. 角色文件在 `qwbuddy/roles/`；说「切到<角色>」即切换，产出物标角色。
