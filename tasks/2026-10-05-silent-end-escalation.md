# 任务书：工人收工不回票，派工者没处理时自动升级到主控

```
任务 id:  silent-end-escalation
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权；2026-10-05「太长了，哪可能30分钟停滞兜底呢」
dispatch-budget: 3
来源:     2026-10-05 第六轮真机演练的故障注入（docs/reviews/2026-10-05-real-herdr-roles-drill-r6.md 的 W2）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，沿用 worker-silent-end 的原窗口与原会话）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-silent-end-escalation.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-silent-end（沿用原隔离副本，在你的提交 a4e1c68 之上追加提交）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：工人收工不回票时要很快有人处理，不能停在那里等 30 分钟。

你在 `worker-silent-end` 做的一分钟门铃已在真机上验证成立：工人不回票收工后约 64 秒，值守叫醒了派工的副主控（记录见 `docs/reviews/2026-10-05-real-herdr-roles-drill-r6.md`，主仓 main 上有；你的副本里没有这份文件，直接读主仓绝对路径）。但后半段断了：副主控读了工人窗口，判断工人没做完、自己无权催也没有预算重派，只在自己窗口里说「需要主控处理」。`roles-r5-docs` 的工人对照代码核实过：规划与门控现在都没有能保证叫到主控的正式上报入口（规划自己的追加行会路由回规划，门控的会路由回门控）。所以这件事不能指望派工者自己上报，要由值守兜住。

### 要做的事

1. **值守自动升级。** 「已收工未报告」的门铃发给了主控以外的派工者（规划或门控）之后，如果同一次收工（同一个 `silent_end` 指纹）在首次门铃之后再过 3 倍 `QWB_SILENT_END_MS`（默认 3 分钟）仍然成立——该操作号仍没有 `done`、`blocked`、`needs-decision`，工人仍是已证实的空闲、会话末条没变——值守直接门铃主控一次。文案写明：哪个工人窗口与操作号、派工者是谁、派工者在什么时间已被提醒、请主控读工人窗口与票上派工者追加的说明后处理。不新增配置键，倍数写成一处常量。
2. **不该升级的情形**：首次门铃本来就是发给主控的（主控自己派的工）不再重复叫；工人在这期间报告了、又开始干活了、或再次收工形成了新的指纹（新指纹从它自己的首次门铃重新计时）；`QWB_SILENT_END_MS` 关闭、quiet 或 away 模式。升级对同一个指纹只发一次。
3. **性能口径不变**：工人为 working 时本轮不做任何额外查询（你已有的断言保留）；等待升级的这段时间内，每轮的重检查次数不得比现在多。
4. **说明书各加一句**（`templates/roles/规划.md`、`templates/roles/门禁.md`、`templates/roles/常驻流程.md`，以及 `templates/config.sh` 里 `QWB_SILENT_END_MS` 那行注释）：派工者被提醒后约 3 分钟仍未解决，值守会直接叫主控一次。

白名单：`bin/qwb-wake.sh`（仅 `collect_worker_due`、`worker_due_row`、`route_gate_due` 的 `[qwb-worker]` 分支及其文案）、`bin/qwb-lib.sh`（仅 `qwb_worker_silent_end` 及其直接辅助）、上面第 4 项的四个模板文件（各仅相关一句）、`tests/collab-planning.sh` 与你上一张票用过的其他已接入测试文件。

## 1. 验收场景

1. 规划派的工人不回票收工：60 秒叫规划一次；规划不处理，再过 180 秒叫主控一次，文案含工人窗口、操作号、「规划已于某时被提醒」；此后不再重复。升级这一条在起点（你的提交 a4e1c68）上必须是红的，先跑出红并留证。
2. 门控派的审核工人同理：先叫门控，再升级主控。
3. 升级到期之前工人写了 `done:`、`blocked:` 或 `needs-decision:`：不升级。
4. 升级到期之前工人被催后又干活、再次不回票收工：按新指纹重新叫派工者，升级从这一次重新计时；旧指纹不再升级。
5. 主控自己派的工人不回票收工：只在 60 秒叫主控一次，没有第二次。
6. 关闭、quiet、away：与现在逐字节相同，没有任何门铃。
7. 工人 working 时本轮零额外查询；等待升级期间每轮查询次数不多于现在（数假 herdr 的调用记录）。
8. 未触发新路径时，值守的输出、票内容、调用序列与改动前逐字节相同（基线写成「当前脚本只撤掉本票改动」）。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 同时有另一张票 `roles-r5-docs` 在改说明书（含 `templates/roles/规划.md`、`templates/roles/门禁.md`、`templates/roles/常驻流程.md` 里「收到这条门铃先读窗口、做完没回票可催补写、情况不明在票上写明核查结论」这三点）；本票在这三份说明里只各加一句升级行为，不改它写的句子（它的改动还没合并，你看不到，按新增独立一句来写，主控合并时处理相邻行）。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`。
- 定向：改动涉及的测试文件各单独跑一次，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**。在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的测试文件名，写死了通过条数或清单的地方同步改，并在 `done:` 行写明。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T11:39:39Z 主控手工派发（沿用 worker-silent-end 的原窗口与原会话，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-worker-silent-end pane=w14Z:p1F dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-silent-end base=a4e1c68
working: 2026-10-05T11:47:21Z 已完整读新票、主仓第六轮实测W2及现有路由/提示/模板；副本clean、HEAD=a4e1c68。拟复用现有wake回执及收件人指纹识别首次提醒，非主控首次提醒后同silent_end持续3倍阈值直接升级主控一次；不加配置/权限/重检查。先在现有隔离planning夹具补升级红证；代码只本副本，状态只本新票。
working: 2026-10-05T11:53:45Z 红证成立：QWB_PLANNING_UPWARD_ONLY=1 QWB_SILENT_END_ONLY=1 QWB_ESCALATION_ONLY=1 bash tests/collab-planning.sh 在a4e1c68运行时rc1，规划60秒首提醒后180秒仍零主控升级（red-upgrade.log）。实现已补纯回执推导：已有非主控收件指纹匹配首次wake，3倍阈值届满再直达主控，独立升级去重且投递前复核同指纹/仍成立；无新增配置/原生查询轮次。四模板仅新增独立一句/相关注释。fast rc0、lint rc0 LINT PASS；八场景及调用/字节对照继续，日志本副本.qwb-tmp/silent-end-escalation-evidence/。
working: 2026-10-05T12:02:04Z 聚焦八场景green-focused rc0，验证规划/门控首次60秒提醒后再180秒升级主控一次，含首次时间/工人窗口/op/派工者说明；提前done/blocked/needs-decision取消；working零额外查询、新指纹重计时、主控首次无二次、关闭/quiet/away无升级；等待期间及未触发路径stdout/stderr/rc/票内容/假Herdr全调用序列与仅撤本票基线逐字节一致。原起点升级red-upgrade rc1已留。继续Bash3.2 tests/collab-planning.sh整文件验收，不跑全门。
working: 2026-10-05T12:11:33Z 主控裁决（预读你副本里的改动后追加）：升级逻辑用的主控窗口取自变量 PANE（qwb_worker_silent_notice 的第五个参数，以及 worker_due_row 里与 target 的比较）。真机上主控的值守是挂钩调起的 qwb-wake.sh --project 根 --block --max-ms 数值，不带 --pane，配置里的 QWB_CONTROLLER_PANE 按说明书留空，所以 PANE 是空串：controller 为空时你的升级分支整段跳过，真机上永远不会升级。你的测试用的是 --once --pane ctl，所以是绿的。block 模式下主控目标是 block_round 传给 route_gate_due 的那个值（HERDR_PANE_ID，缺省时为 pid 加父进程号），首次门铃在真机上能送到副主控走的就是这条路。改法：升级逻辑里的主控身份与本轮 route_gate_due 收到的主控目标保持同一个来源，两种模式（--once/--pane 与 --block/HERDR_PANE_ID）都成立；不要另造来源。补场景 9：按挂钩的真实调用方式（--block --max-ms，不带 --pane，环境里有 HERDR_PANE_ID，配置的 QWB_CONTROLLER_PANE 为空）跑一遍场景 1，升级的摘要必须出现在该次 block 的标准输出里且退出码为 2；这条在你当前实现上应当是红的，先留红证。其余不变。
working: 2026-10-05T12:25:17Z 按12:11:33Z裁决补场景9红证：真实--block --max-ms、不带pane、QWB_CONTROLLER_PANE为空；原实现先叫规划，但升级stdout空且rc124（red-block.log），断言应rc2准确失败。现升级判定放到[qwb-worker]路由分支，直接使用route_gate_due已有controller实参；worker_due_row复核显式传同一实参，lib不再读取PANE另造来源。纯回执推导/原生重检查次数不变。前一整文件所有Python检查已过，但运行中改测试文件导致Bash读取尾部偏移EOF，planning-full rc2不计绿证；后续文件冻结后完整重跑。
working: 2026-10-05T13:10:52Z 主控接手收尾并验收：工人上下文用到 98%，未写 done、未提交；主控取其副本全部改动（.qwb-tmp/escalation-takeover.patch）应用到 main，工人已按要求停止。主控独立跑 /bin/bash tests/collab-planning.sh rc=0、57 PASS、0 FAIL、854 秒（.qwb-tmp/ctl-esc-planning.log，含升级各场景与按挂钩调用方式的 block 场景），快门 rc=0，LINT PASS。真机验证（第七轮演练，脚本与安装进演练项目的逐字节一致）：工人 12:41:59Z 不回票收工，12:43:01Z 副主控被提醒，12:46:03Z 升级门铃送到主控，主控 12:46:09Z 开始处理。全门见本票之后的主控记录。遗留：主控重新授权后无人叫副主控续派，已开票 reauthorize-ready。
