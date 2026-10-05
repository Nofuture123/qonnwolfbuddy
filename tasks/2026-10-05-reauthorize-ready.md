# 任务书：主控对同一规格重新授权后，没有人叫副主控续派

```
任务 id:  reauthorize-ready
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权；2026-10-05「太长了，哪可能30分钟停滞兜底呢」
dispatch-budget: 3
来源:     2026-10-05 第七轮真机演练（主控实测；证据 /Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r7/ 下 timeline.log、notes.md、evidence/，只读）
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-reauthorize-ready.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/reauthorize-ready（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：工人出了状况要很快有人处理，处理完链路要能自己接着走，不能停在那里。

### 真机上发生了什么（主控实测）

第七轮演练里，副主控派出的实现工人被叫停后不回票收工。62 秒后值守叫醒副主控；副主控在票上写了核查结论；再过 182 秒值守升级叫醒主控。主控读票后对同一张实现票、同一个规格版本再做了一次 `plan-authorize`（预算 1），读回 `working: implementation-authorized spec_rev=0 budget=1`，然后结束回合，等副主控在原工人窗口续派。**之后 8 分钟没有任何角色被叫醒**：票上没有新的就绪记录，副主控没有收到门铃，状态页显示「就绪: 未扫描」。演练票的终态在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r7/evidence/2026-10-05-drill-hello.md`。

主控读到的直接原因（请你对照代码复核）：`bin/qwb-wake.sh` 的 `collect_due` 里，产生就绪事件之前有一条「当前规格版本已有派发记录就不再处理」的判断（搜 `已派当前spec不重复派` 一带），所以同一规格派过一次之后，主控再授权也不会再产生就绪事件。规格有修订时版本号会变，所以修订那条路是通的（第四轮演练验证过）。

### 要做的事

1. **同一规格重新授权后要能再次就绪并叫到副主控。** 主控在某次派发之后，对同一规格版本又成功做了一次 `plan-authorize`，值守应当像首次那样产生就绪事件并门铃副主控，由副主控按原有流程（`start-check`、`start-claim`、`qwb-run.sh`）续派；派发仍走原有的全部校验（授权、预算、工人身份、原工人空闲才能在原窗口续派），本票不放宽其中任何一条。判断口径由你对照代码定，原则是「这次授权之后还没有派发过」才算待派，已经按这次授权派过就不再重复。
2. **核实预算与续派能走通。** 对照 `bin/qwb-ledger.sh` 核实：同一规格版本上第二次 `plan-authorize` 之后，预算是怎么计的，副主控的 `start-claim` 与 `qwb-run.sh` 是否会放行这一次续派，续派是否落在原工人窗口与原会话（原工人已证实空闲时）。如果现有账本会拒绝这次续派（例如预算按规格版本累计而不认新授权），先写 `needs-decision:` 说明现状与你建议的最小改法，不要自行放宽预算校验。
3. **说明书写明主控收到升级门铃后的做法。** 门铃文案是「升级主控：工人已收工仍无报告…请主控读工人窗口与票上派工者追加的说明后处理」。在 `templates/roles/主控.md` 与 `templates/roles/常驻流程.md` 的相应位置写清三种处理：工人其实已做完只是没回票且派工者没催成——主控按同一规则催它补写状态行；工人没做完、要它接着做——对同一规格再 `plan-authorize` 一次，值守会叫副主控在原窗口续派（写出可照抄的命令，载荷形状照现有步骤 r04 的写法）；不再继续——按现有的收回流程处理（先核实现有说明里有没有这条流程，没有就只写前两种并在 `done:` 行说明）。演练主控在这里靠猜了两处，原文见上面的 `notes.md` 末尾。
4. 把「工人不回票收工 → 副主控被提醒 → 升级主控 → 主控重新授权 → 副主控续派 → 工人交付」这一整段纳入离线测试（假 Herdr、假时钟），断言每一步的门铃对象与次数。

白名单：`bin/qwb-wake.sh`（仅 `collect_due` 里就绪事件的判断）、`bin/qwb-ledger.sh`（仅当第 1 项的判断必须在 `plan-ready` 里同步，最小改动）、`templates/roles/主控.md`、`templates/roles/常驻流程.md`（各仅相关句子）、`tests/collab-planning.sh` 及其他为验收所需的已接入测试文件。

## 1. 验收场景

1. 首次派发之后，主控对同一规格再次 `plan-authorize`：下一轮值守产生就绪事件并门铃副主控一次；副主控续派成功。这条在起点提交上必须是红的，先跑出红并留证。
2. 没有重新授权时：与改动前逐字节相同，不产生就绪事件、不门铃（基线写成「当前脚本只撤掉本票改动」）。
3. 重新授权后已经续派过：不再重复就绪、不重复门铃。
4. 修订路径（规格版本变化后授权）：行为与改动前相同。
5. 门控已持有 claim、票已通过或已结案时重新授权：不产生就绪事件。
6. 第 4 项的整段流程测试通过，每一步的门铃对象与次数符合上面的描述。
7. `bash tests/roles-walkthrough.sh` 照旧通过。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话（包括 `claude`）。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。真机行为以本票列出的实测事实与样本文件为准；实测没有覆盖而你又需要的行为，写 `needs-decision:` 让主控去真机上试，不要猜。
- 当前没有别的在途票与本票改同一批文件。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。测试不许读写真实的 `~/.claude/`：用到会话文件位置的地方必须能由测试指到临时目录。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh` 与 `tests/roles-walkthrough.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**。在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的测试文件名，写死了通过条数或清单的地方同步改，并在 `done:` 行写明。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改任何放行条件、身份校验与权限；不让未授权的派工变得可行；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T13:11:08Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-reauthorize-ready pane=w14Z:p1K dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/reauthorize-ready base=7321f8a
needs-decision: 2026-10-05T13:12:00Z 执行者核实 bin/qwb-ledger.sh:995 按当前 spec_rev 累计所有非门控 dispatch；plan-authorize 仅替换 authorization 并清空 ready，不重置已用次数。因此一次派发后再次 budget=1，start-check/start-claim/qwb-run 仍拒绝「启动预算已耗尽/事件已派，不重复派发」。建议保持累计预算契约，主控同规格续派时明确把总上限从1提高至2，说明书解释是总上限而非新增次数；就绪判断改为最新 plan-authorize 之后未 dispatch。若必须 budget=1 表示再给一次，须主控另行明确扩白名单与按授权代计预算，执行者不自行放宽。正在用假Herdr公开入口补复现证据，等待本条裁决才能实现完整续派。
working: 2026-10-05T13:12:35Z 主控裁决：采纳你的建议，预算保持「按规格版本累计的总上限」，start-check、start-claim、qwb-run 的预算校验一律不动。三点：一、就绪判断改为「最新一次 plan-authorize 之后还没有派发，并且授权的总上限大于本规格版本已用次数」，两个条件都满足才产生就绪事件并门铃副主控；总上限不够时不产生就绪（否则副主控被叫醒后只会被拒）。二、扩白名单到 bin/qwb-ledger.sh 的 plan-authorize 校验：新授权的 budget 小于等于本规格版本已用派发次数、且不是对现有授权的逐字节重放时，直接拒绝，拒绝信息写明预算是本规格版本的总上限、已用几次、要再派一次应把 budget 写成几，并给出一行样例。真机上主控就是照「再给一次」的直觉写了 budget=1，脚本接受了，然后全员停住；宁可当场拒绝并教它怎么写。对现有授权的逐字节重放保持现状。如果现有测试里有依赖「已用完后仍接受同额新授权」的用例，先写 needs-decision 列出来，不要直接改断言。三、说明书写明预算是总上限、怎么读到已用次数（给出公开入口）、续派时的载荷样例把 budget 写成已用次数加一。验收场景相应调整：场景 1 用总上限 2；新增一条「已用完后再授权同额被拒，拒绝信息含已用次数与应填的值」；新增一条「重新授权但总上限不够时不产生就绪、不门铃」。
working: 2026-10-05T13:16:20Z 执行者已按最新裁决完成调用链核对；既有 tests 中实际 plan-authorize 用例仅首次授权和修订新spec，没有依赖已耗尽同额新授权的断言。已接入同票同spec总上限2的整段假Herdr/假时钟回归，起点运行日志=.worktrees/reauthorize-ready/.qwb-tmp/reauthorize-ready-evidence/red.log；说明书补公开read统计已用次数及已用加一载荷，并对照 QWBUDDY §7 与 qwb-worktree.sh 核实既有 --archive 废弃收尾。代码预算/身份放行检查保持原样。
working: 2026-10-05T13:18:59Z 起点红已证实：QWB_REAUTHORIZE_ONLY=1 bash tests/collab-planning.sh rc=1，失败断言为最新授权后缺 planner-ready，实际门铃只含 implementation-authorized spec_rev=0 budget=2；原始日志=.worktrees/reauthorize-ready/.qwb-tmp/reauthorize-ready-evidence/red.log。现已最小修改 collect_due 判断与 plan-authorize 入口拒绝；start-check/start-claim/qwb-run 校验未改。正跑定向绿与说明书检查，首次fast rc=0；lint发现变量后中文括号，已改为花括号包裹并复验。
working: 2026-10-05T13:25:12Z 实现与文档阶段完成：collect_due 按最新 plan-authorize 事件序号、当前spec非门控dispatch数与累计总上限判就绪；plan-authorize 对不足且非原授权重放直接拒绝并给已用/应填值及完整JSON样例。已完成原窗口原会话续派与done路由断言；快门rc=0、lint rc=0/LINT PASS，roles-walkthrough最终实现版本rc=0。逐字节测试夹具曾误用未冻结事件ID副本，已修复并续跑；源码仍仅5个白名单文件，未碰真Herdr/模型/主仓文件。
working: 2026-10-05T13:32:16Z 定向阶段已收敛：Bash3.2及CLI bash路径固定为/bin/bash，QWB_REAUTHORIZE_ONLY=1 tests/collab-planning.sh rc=0 PASS=14 FAIL=0；三条stdout/stderr/rc/票/原生调用逐字节对照均通过（未重授权、重放额度不足、新spec授权），门控claim/accepted/verified边界及原窗口原会话续派通过，安装后文档授权块原样执行。fast rc=0 PASS=0 FAIL=0；lint rc=0 PASS=9 FAIL=0/LINT PASS；roles-walkthrough rc=0 PASS=22 FAIL=0。正跑最终完整collab-planning，日志均在本副本 .qwb-tmp/reauthorize-ready-evidence/；smoke无引用，两测试仍在collab-all固定清单，未改文件数无需调固定条数；没有跑全门。
working: 2026-10-05T13:44:03Z 最终完整collab-planning（Bash3.2）中的本票整段续派回归、预算拒绝、三条逐字节对照及claim/accepted/verified边界已全过，原silent-end与升级主控回归也正常；整份脚本仍在运行，继续等待后续既有检查与最终退出回执，不采信部分PASS当全绿。最终文件哈希与candidate-files.sha256一致，无后续源码变更。
done: 2026-10-05T13:50:13Z 执行者完成 commit=69c7b960b89c847f38a67a748b9fe9455a64faa7；累计预算不变，最新授权后未派且额度充足再就绪；不足新授权拒绝并给已用/应填值及JSON例，原授权重放保留既有交接。Bash3.2定向rc0 PASS14 FAIL0、完整collab-planning rc0 PASS60 FAIL0；roles-walkthrough rc0 PASS22 FAIL0；fast rc0 PASS0 FAIL0；lint rc0 PASS9 FAIL0/LINT PASS；起点红rc1 PASS14 FAIL0（缺新ready断言）。原窗口原会话完整链、claim/accepted/verified边界、三条逐字节对照及安装后文档命令均过；三种处置含现有--archive。日志目录=.worktrees/reauthorize-ready/.qwb-tmp/reauthorize-ready-evidence/，上述六项同名.log/.rc（红red、定向targeted）。smoke无引用，collab-all清单/条数无需改；仅5白名单文件且副本clean；未跑全门、未碰真Herdr/模型。
working: 2026-10-05T14:30:53Z 主控验收：提交 69c7b96 合入 main 为 641a5cb。新就绪判断读取的字段对着第七轮演练的真实票核对过。第八轮真机演练（docs/reviews/2026-10-05-real-herdr-roles-drill-r8.md）：工人不回票收工后 64 秒副主控被提醒、再 181 秒主控被升级叫到，主控照说明书把总上限写成 2，值守随即叫副主控，副主控在原窗口续派，链路走到两票结案，人工介入 0 次、被拒 0 次。全门：第一次与演练同时跑，rc=1、864 PASS、1 FAIL（tests/process-entry-cleanup.py，已知受负载影响的计时类测试，单独重跑 rc=0）；串行重跑 rc=0、865 PASS、0 FAIL、1119 秒（.qwb-tmp/ctl-full-merge17.log）。
