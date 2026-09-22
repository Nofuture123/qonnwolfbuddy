# 生产文档票独立审核

**结论：AMEND。** 基线 `1c500b38c014be9e55aa33fede2735ebaaf17d16`，候选 `59eb8ffe66d3afe146aa6d03d8d941370c63800c`。审核输入为 `git diff 基线..候选 -- README.md README.zh.md templates/QWBUDDY.md` 与逐文件 `git show 候选:路径`；运行时佐证也只取候选 Git 对象，未把主工作区文件当候选。差异仅这三个白名单文件，`git diff --check` 通过。未跑全门，未创建窗口或派发。临时常规文件复现已清理。

## 1. “本次命令环境设置 QWB_WORKSPACE”不会生效

- 问题与位置：候选 `README.md:53`、`README.zh.md:53`、`templates/QWBUDDY.md:13` 均建议跨项目时在本次调用环境设置 `QWB_WORKSPACE`。但候选 `bin/qwb-run.sh:113-115`、`bin/qwb-wake.sh:90-94` 直接 `source` 项目的 `config.sh`，未保留环境优先级；候选 `templates/config.sh:24` 无条件赋值 `QWB_WORKSPACE=""`，`bin/qwb-lib.sh:42-43` 只读取被覆盖后的值。
- 已复现：把候选 `templates/config.sh` 的 Git blob 写入临时常规文件，以 `QWB_WORKSPACE=wTarget` 启动 Bash 并 `source` 该文件；观测 `before=<wTarget> after=<>`。非空的项目配置同样会覆盖环境值。
- 影响：照文档临时指定目标 workspace 时，派发/值守仍使用配置值或自动回退，工人或值守 tab 可能落错 workspace；中英文一致地重复了错误指引。
- 最小修复：本票删去“本次命令环境设置”这一现有运行时不支持的路径，只写真实可行的项目配置与自动匹配规则，并明确跨项目无法自动匹配时的限制；若要临时覆盖，另票先增加并验证运行时显式参数或环境优先级。

## 2. Pi 首次开局先获锁后值守，扩展不会因此启动

- 问题与位置：候选 `templates/QWBUDDY.md:11,15-17,20` 规定先取得锁，Pi 仅靠已安装扩展启动值守，并以状态“未运行”提示修入口；`README.md:35,45` 与 `README.zh.md:35,45` 同样描述这一路径。候选 `templates/pi-extensions/qwb-watch.ts:184-196,276-284` 只在 `session_start` 检查锁并起子进程；未起过子进程时 `idleAfterZero=false`，后续 `turn_end` 直接返回。拿锁动作没有触发扩展重检。
- 已复现：从候选 Git blob 加载 `createWatchCore`，先以无锁主状态调用 `onSessionStart()`，随后把锁主设为当前 pane 并调用 `onTurnEnd()`；子进程启动次数仍为 `0`。这正是新 Pi 会话先启动、按开局指引再抢锁的顺序。
- 影响：删除旧的无条件可见 tab 步骤后，Pi 主控可能没有任何值守进程，任务进展不会自动叫醒它；“安装或更新后重启/`/reload`”不覆盖每次新会话获锁较晚的情况。
- 最小修复：在本票的 Pi 开局步骤明确**获锁后**重新触发扩展的可验证操作（例如 `/reload`）并核实 `pi-ext` 活进程；若要求完全自动，需另票让扩展在获锁后的事件中启动，再据实更新文档。不要以安装完成或扩展文件存在代替值守已启动。

## 3. 跨 workspace 的可见 tab 不能按文档幂等复用

- 问题与位置：候选 `templates/QWBUDDY.md:13,19-20` 将目标项目 workspace 选择与“`--ensure` 幂等确保/未运行重跑”连用；`README.md:48,53`、`README.zh.md:48,53` 提供同一路径。候选 `bin/qwb-wake.sh:274-300` 先要求目标主控 pane 属于调用者 workspace A；`bin/qwb-wake.sh:396-419` 却可按项目配置/根匹配把值守 tab 建在 B。下次从 A 调用时，`bin/qwb-wake.sh:321-323` 只扫描 A，随后 `bin/qwb-wake.sh:354-362` 拒绝已登记的 B pane。
- 静态证据：当主控在 A、项目解析到 B 且 A≠B 时，首次 `--ensure` 可登记 B 的值守；第二次从同一主控调用将命中“登记 pane 属于 workspace B（当前 A）”并拒绝，无法按文档原地复用或重启。未运行该路径，未创建真实或模拟 tab。
- 影响：跨项目值守的重复开局/故障恢复步骤会失败；文档的跨 workspace 配置建议与“幂等确保”承诺不能同时成立。
- 最小修复：本票把可见 tab 兜底的幂等保证限定在调用者与值守 tab 同 workspace 的已支持场景，并说明跨 workspace 需先修运行时；另票统一扫描、登记与复用的 workspace 规则后再恢复该承诺。

其余核查：两份 README 对主控用途、pnpm 示例、依赖角色、历史 E2E 证据和未验证范围的表述一致；`--ensure --pane "$HERDR_PANE_ID"` 与现有参数相符。`fast/full` 数值明确绑定旧源码和主控记录，未被本审核当作候选提交的新测试结果。上述三项修好前，不应判文档票 PASS。
