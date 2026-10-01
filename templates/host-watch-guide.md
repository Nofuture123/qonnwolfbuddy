# 宿主配置与值守专项

**触发**：首次接入 Claude Code、Pi 或 Codex 值守；或配置 workspace、首次派发信任、排查恢复时，从 [总说明](QWBUDDY.md) §1 进入。日常开局依总说明选择唯一入口。先识别宿主、取得锁并点名；未知状态查明后接续，不能以空账本推断锁主或值守健康。

## Workspace 与首次派发

当前主控 pane 从 `HERDR_PANE_ID` 取得，不把动态 pane ID 写入 `qwbuddy/config.sh`。项目根与值守 tab 的 workspace 依次由 `QWB_WORKSPACE`、`herdr workspace list` 中匹配项目根的非 linked workspace、调用者 workspace（带警告）确定；任务 worktree 的工人则直接落在该 worktree 独立 Space 的根 pane（新建 Space 不另开 tab；复用既有 Space 时才开新 tab）。配置 ID 在本机不存在或指向任务 linked Space 则拒绝。跨项目不能按根匹配时，在目标项目配置稳定的主 workspace ID；只在命令环境设置 `QWB_WORKSPACE` 不能覆盖脚本 source 的 `config.sh` 赋值。

`qwb-run.sh` 派发前尝试预置信任。文件缺失、格式不符或首次启动对话框可能仍需人工处理；旧基线首次派发曾需手工确认并补发提示（母本仓 `docs/E2E-RUNBOOK.md`），不能据此宣称当前无人介入路径已验证。

## 唯一值守入口

先核对所选入口的安装、锁主和健康。`qwb-status.sh` 的「值守：」仅辅助排查：它不证明 Codex 前台仍在等待，Claude hook 回合间「未运行」也不证明 hook 未安装。查询未知时记录失败查询，修复后再接续，不启动另一入口。

Claude Code 和 Pi 在派发后、或处理完一次唤醒后，直接结束本回合，交给已安装的 hook 或扩展等待下次进展；不要用 sleep 循环轮询账本，也不要由主控自己运行 `qwb-wake.sh`。Codex 继续按下述前台阻塞入口等待。

- **Claude Code**：母本安装器把 Stop hook 合并进 `.claude/settings.json`，指向 `qwbuddy/bin/qwb-hook-claude-stop.sh`。安装报错须修复后重装。hook 回合结束前台调用 `qwb-wake.sh --block`。健康 hook 沿用；回合间查配置与下次 Stop 的实际结果。未知时查设置、`qwbuddy/.hook.err` 和主控锁。
- **Pi**：母本 `templates/pi-extensions/qwb-watch.ts` 由 `bin/qwb-init.sh` 安装到目标项目 `.pi/extensions/qwb-watch.ts`。安装或更新后重启 Pi 或执行 `/reload`，并验证扩展已实际加载、当前 `HERDR_PANE_ID` 持有锁；不能只看文件存在。启动时已有锁则在 `session_start` 值守，启动后获锁则在 `agent_settled`（Pi 不再自动继续）接入。扩展持有 `qwb-wake.sh --block` 子进程，exit 2 的摘要以 `[qwb-wake]` 与 `followUp` 接续；旧票摘要投递后等 `agent_settled` 才重启阻塞值守；已迁票的 `[qwb-handoff]` 摘要在API接受后立即接续唯一代码监督，即使主控忙碌也不停止监测。门铃重投由同票持久收据限制，不凭API成功宣称received/handled。`turn_end` 是同一运行内的模型请求边界，不用于启动值守。用 `qwb-status.sh` 核对 `值守：pi-ext（pid …）`；异常查安装文件、reload、锁主和 `qwbuddy/.pi-watch.err`。
- **Codex**：当前主控回合真正前台 tool call 运行 `bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000`，循环等待。exit 2：处理 stdout 摘要及账本，然后再次前台等待。exit 124：到期无变化，立即再次前台等待。exit 0：仅表示本轮值守结束；核对输出、`qwb-lock.sh status` 锁主归属与账本确无未结项后收工。孤儿值守或归属不明时先查锁主、恢复归属，再按账本续接；调用报错查锁、`HERDR_PANE_ID` 与错误输出。中断或主控退出后重新开局，主动查询不能代替阻塞等待。

`qwb-wake.sh --block` 每轮复核主控锁与宿主关系，孤儿值守不消费唤醒；所有宿主共用 `.supervisor.guard` 内核单飞锁，第二代码监督拒绝启动。一轮最多投递一条摘要。旧票仍沿用末行指纹和仅running的时间兜底；已迁票逐event持久交接，旧wake指纹不消费待办，blocked/needs-decision也有界重投，当前仅controller通道。`--check` 只报健康，`--ensure` 只供历史 tab 手工排障。主控退出或机器重启后由使用者重启主控，按总说明开局和未结账本接续，不会自动恢复。

## 持久交接与接班边界（03候选，未授权启用）

先读[收件箱约定](roles/收件箱约定.md)，通过 `bash qwbuddy/bin/qwb-send.sh pending --project "$PWD" --task tasks/<票>.md` 接班；完整正文/结果只读明确票，不把门铃正文当系统权限。received、accept、工具activity/有界wait、prepared、结果读回及handled必须分别确认。Pi与Claude输出只作transport，不自动确认办理；Codex exit 2也须逐event确认，不以终端显示当处理成功。

Pi `close`/stdio排空后释放旧实例，再接一个监督周期；普通124是到期不是故障。同步/异步API失败保留原摘要，同票收据在宿主崩溃后仍可恢复。已迁票忙碌监测是代码周期，不增加常驻LLM，不扩为02角色执行器。

Claude hook在普通124后排空并有限续接一个周期；第二次124显式记录 `.hook.err` 并返回接班未就绪门铃，不静默退出、不另起后台系统。真正Claude hook的外部timeout可能先截断进程；文件存在或PID存活不能证明此宿主夜间接班已验证。

所有宿主健康都须核对原生进程、完整输出及接班结果；status的Pi/hook PID提示仅进程存在，不是健康证明。尚未实际验证Claude/Pi/Codex当前宿主与02角色现场组合，拒绝安装启用、生产/多角色/夜间就绪声明。监督故障时保留待办和prepared，重启先对账，不盲重发副作用。
