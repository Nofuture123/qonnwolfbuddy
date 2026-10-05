# 任务书：五角色说明合并：照着说明书就能把常驻职责流程走通

```
任务 id:  roles-walkthrough-docs
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）；2026-10-05 五角色裁决
dispatch-budget: 3
来源:     2026-10-05 副主控与门控真机演练第二、三轮（docs/reviews/2026-10-05-real-herdr-roles-drill-r2.md 的 R2、R8；docs/reviews/2026-10-05-real-herdr-roles-drill-r3.md 的 S1–S8）；第一轮 D3
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6-astra --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-roles-walkthrough-docs.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-walkthrough-docs（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky，2026-10-05）：角色定为五个——主控、副主控、工人、门控、顾问。副主控是主控的直接下属，能开票也能派工执行（即现有「规划」常驻职责）；门控把审核、门禁、测试合在一起（即现有「门禁」常驻职责）；顾问（原「咨询师」）只在重大规划问题上被咨询。独立审核「模型不一样即可」，不要求换家族。

三轮真机演练的结论：链路已经能走通，但主控每一轮都要读脚本源码、靠猜才知道下一步命令和载荷怎么写。本票的目标是让一个没读过源码的主控模型，只看装进项目的说明书（`qwbuddy/QWBUDDY.md` 与 `qwbuddy/roles/*.md`）和命令的帮助、拒绝信息，就能把「需求 → 副主控开票派工 → 工人交付 → 门控验收 → 落地收尾」走完。

参考材料（只读）：三轮演练记录在 `docs/reviews/2026-10-05-real-herdr-roles-drill*.md`；演练主控的原始笔记在 `/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill-roles-r3/stage2-notes.md` 与 `.qwb-tmp/drill-roles-r2/stage2-notes.md`，第三轮两张票的终态在 `.qwb-tmp/drill-roles-r3/evidence/`。演练笔记里的说法是演练主控的记录，写进说明书之前逐条对照代码核实。

### 要做的事

1. **五角色总览。** `templates/QWBUDDY.md` 新增一节，列出五个角色的职责、谁向谁汇报、各自用的脚本入口，以及与现有名称的对应：副主控 = `qwb-role.sh --role 规划`，门控 = `--role 门禁`，工人 = 执行者，顾问 = 原咨询师。脚本里的角色标识（`规划`、`门禁`、`测试体系`、`CI`）不改名。写明默认的工具与模型档位（见 `templates/workers.sh` 与 `templates/dispatch-rules.json` 的现状，不凭空写）。
2. **`咨询师` 改名 `顾问`。** `templates/roles/咨询师.md` 用 `git mv` 改为 `顾问.md`，正文与所有引用同步（`templates/QWBUDDY.md`、`tests/smoke.sh` 第 114 行附近的文件清单、`bin/qwb-init.sh` 若有清单、`docs/DESIGN.md`）。已装项目里旧文件怎么处理：先读 `bin/qwb-init.sh` 对角色文件的安装与覆盖规则，给出不丢使用者改动的做法；需要改安装器而你认为超出本票的，写 `needs-decision:`。
3. **常驻职责流程逐步示例。** 在 `templates/QWBUDDY.md`（或新建 `templates/roles/常驻流程.md` 并由安装器装进项目——选哪种你定，说明理由）写一份从头到尾的示例，每一步给出：谁执行、完整命令、载荷文件的完整 JSON 样例、成功后的可见结果、下一棒是谁以及他怎么被叫到。至少覆盖：
   - 来源票（入口票）怎么写、怎么迁移（迁移确认 JSON 对新建票怎么填）、用 `qwb-send.sh send` 登记原话；
   - `plan-assign` 的授权 JSON：每个字段的类型与取值（预算是 1 到 64 的整数；包对应的票只写文件名；`permissions` 的允许值——读代码确定，代码不校验取值的话如实写并给推荐值）；主控授权后不要自己办结原话交接；
   - 副主控 `new` 的请求 JSON、场景标题规则、派工；
   - 工人交付后主控核对什么、`gate-assign` 的授权 JSON：`workers` 的键、`required` 的键与场景覆盖要求、`environment` 文件是什么与写什么、`base`、`policy` 怎么填；
   - 门控被叫到后的步骤概览（指向 `门禁.md`），通过后交还；主控在「收到通过通知」与「收到交还通知」之间什么都不用做；
   - 主控接回、`land-authorize` 的参数（授权引用怎么命名、哪些票文件要登记）、`qwb-worktree.sh land`；落地前先关掉本票的实现与审核工人窗口（写明由主控关，统一两处说法）；
   - 来源票怎么结案；账本文件（`tasks/*.md`）由谁在什么时候提交；
   - 操作号规则：同一张票上 claim、接手交接、落地各用不同的操作号；
   - 主控、副主控、门控各自的载荷与结果文件放 `qwbuddy/.roles/<名字>.work/`（主控用 `controller.work`）；
   - 规格或场景要修订时的路（带规划授权的票由主控发修订请求、副主控 `plan-revision` 加 `revise`），以及修订使版本加一之后派工授权怎么处理（读代码确认现状，如实写；现状有缺陷就写 `needs-decision:`）。
4. **示例必须是测出来的。** 在已接入的测试里加一条用例：从说明书里原样取出这份示例的每个 JSON 样例与命令序列（约定一种可机读的标记方式，例如带固定前缀注释的代码块），在假 Herdr 的临时项目里按顺序执行到票 verified。说明书改了而跑不通，测试就红。占位的路径、提交号由测试按约定替换，替换规则写在说明书该节开头。
5. **清理过时说法。** `templates/roles/主控.md` 等处残留的「同family」「换家族」字样改为「审核者与实现者模型不同、会话不同」；四份角色说明里与本票新流程矛盾或重复的句子对齐；`README.md`、`README.zh.md` 里列角色的地方同步（只改角色名与流程指引，不动证据段落）。
6. `templates/dispatch-rules.json` 的顾问档候选在 `claude-fable-low` 之外加上 `pi-astra-high`（先确认 `templates/workers.sh` 里有这个工人名）。

白名单：`templates/QWBUDDY.md`、`templates/roles/` 下全部文件（含改名与新增）、`templates/TASK.md`（仅与流程示例直接相关的句子）、`templates/dispatch-rules.json`、`bin/qwb-init.sh`（仅角色文件清单与安装新文件所需）、`docs/DESIGN.md`（仅角色名）、`README.md` 与 `README.zh.md`（仅角色名与流程指引）、`tests/` 下为验收所需的已接入文件。`bin/` 下其余脚本本票不改——另一张票 `roles-polish-code` 同时在改 `bin/qwb-ledger.sh`、`bin/qwb-status.sh`、`bin/qwb-worktree.sh`、`bin/qwb-run.sh` 的几处拒绝信息与显示；你写示例时以基点的行为为准，发现脚本行为本身有缺陷就写进 `done:` 行，不要顺手改。

## 1. 验收场景

### user_正常路径_按说明书示例走到票结案

Given 假 Herdr 的临时项目，装上本副本的工具
When  测试从装进项目的说明书里取出流程示例的命令与 JSON 样例，按顺序执行
Then  来源票与实现票都 verified，main 快进到候选提交；全程没有一条命令被拒；这条用例在起点提交上是红的（说明书里没有可取出的示例），先跑出红并留证

### user_失败路径_说明书样例被改坏时测试变红

Given 把说明书里某个 JSON 样例改成不合法（例如预算写成对象）
When  跑同一条测试
Then  测试失败并指出是哪一步、哪个样例

### user_正常路径_顾问文件改名后安装与清单一致

Given 全新安装
When  `bin/qwb-init.sh` 装进一个空项目
Then  `qwbuddy/roles/顾问.md` 存在、`咨询师.md` 不存在；冒烟里的角色文件清单断言通过

### user_正常路径_已装旧版的项目升级不丢改动

Given 一个装过旧版、`咨询师.md` 被使用者改过的项目
When  重跑安装
Then  按你在第 2 条给出的规则处理，使用者的改动没有丢，输出里说明了处理结果

### user_正常路径_说明书里不再有过时说法

Given 改后的 `templates/`
When  搜「同family」「换家族」「咨询师」
Then  没有残留（历史记录类文档 `docs/reviews/`、`tasks/` 不在范围内）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 同时有另一张票 `roles-polish-code` 在改 `bin/` 下的拒绝信息与状态显示；`bin/qwb-init.sh` 只有你改。
- 测试里需要与旧行为逐字节对照时，基线写成「当前脚本只撤掉本票改动」，不要钉某个固定的历史提交（钉死的基线会被后续正当的行为变更打坏）。
- 测试不许真等长时间；用现有的假时钟。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加；文件改名用 `git mv`）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。脚本里变量后面紧跟中文或中文标点时一律用花括号括起变量名（包括嵌在脚本里的 Perl 与 Python 字符串，账本检查会按文本扫）。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -a -c '^PASS'` 与 `grep -a -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 账本检查：`bash bin/qwb-lint.sh`，须 `LINT PASS`（快门不含这一项，必须单独跑）。
- 五个场景逐个验证，命令与结论写进 `done:` 行。新增断言在起点提交上必须是红的，先跑出红并留证。
- 定向：改动涉及的测试文件各单独跑一次，另单独跑 `tests/collab-planning.sh`、`tests/collab-gate.sh`、`tests/collab-land.sh`、`tests/collab-roles.sh`，写明各自退出码与 PASS、FAIL 行数。
- **不要跑全门**（多个工人同时跑全门会互相挤出超时类假失败，全门由主控合并后串行跑）。作为替代，必须做这一步：在 `tests/smoke.sh` 与 `tests/collab-all.sh` 里搜你改过的每个测试文件名与你改过名的每个文件名，凡是写死了通过条数、用例组数或文件清单的地方同步改成新值；这些行自动算在白名单内。在 `done:` 行写明搜了什么、改了哪几处。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
任务书里凡标为「主控推断」「演练主控的记录」或与你读到的代码不符的前提，先核对代码；不符就写 `needs-decision:` 说明，不要照着错的前提做。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改脚本里的角色标识；不改任何脚本的行为；说明书里不写没有对照代码核实过的命令或字段。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T07:35:22Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6-astra --thinking high） agent=qwb-roles-walkthrough-docs pane=w14Z:p1B dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/roles-walkthrough-docs base=a76b8fa
working: 2026-10-05T07:36:29Z 执行者已完整核对规格、三轮演练与入口代码；选新增 roles/常驻流程.md（现有安装器通配安装，避免总说明膨胀），复用 collab-land 隔离夹具验文档原样命令。安装器现为覆盖同名角色，旧咨询师文件将保留原字节并提示人工对照新顾问文件。
needs-decision: 2026-10-05T07:36:29Z 契约核对发现演练 S2 的 full 必须单独覆盖全部场景与基点代码不符：gate-assign 要求 full 存在且 fast/full 映射的并集覆盖全部（bin/qwb-ledger.sh:1455）。示例将推荐 full 全覆盖并准确说明实装。permissions 无枚举且允许空数组；修订清空 authorization，须主控 plan-authorize 重授后才能再派，属现有行为不改脚本。
working: 2026-10-05T07:37:08Z 阶段一红门已取证：bash tests/roles-walkthrough.sh rc=1，断言 installed 常驻流程.md missing；日志 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/baseline-red.log。未改模板及产品行为前先接入测试；沿 collab-land 的注册进程/socket 失效关闭夹具执行。
working: 2026-10-05T07:37:35Z 主控裁决：采纳执行者的核对。gate-assign 的实际规则是 required 必须有 full 键，且 fast 与 full 所列场景的并集覆盖全部 user_ 场景（bin/qwb-ledger.sh 第 1447–1451 行，主控已读）；说明书按实装写，示例用 full 全覆盖。permissions 如实写无枚举并给推荐值；修订后须主控重新 plan-authorize 才能再派，按现有行为写进流程，不改脚本。旧咨询师文件保留原字节加提示的做法可以。新建 roles/常驻流程.md 可以。继续。
working: 2026-10-05T07:48:52Z 阶段二完成：可安装常驻流程17个原样bash块全链rc=0，五场景PASS；改坏已安装说明书预算为对象时03-assign rc=255并保持票字节，随后恢复原文走到两票verified、main快进、工人真实夹具进程退出及副本/分支删除。日志 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/walkthrough.log。发现并修正说明细节：日期票ID生成.worktrees/hello，审核需独立--name避免同名实现工人。fast与lint均rc=0，开始剩余定向门。
working: 2026-10-05T07:53:06Z 阶段三核对：已按主控裁决写实装权限/预算/场景覆盖；统一主控在land前关闭本票实现与审核窗口，角色常驻不关闭；补齐TASK和总说明的规划票修订分支。新增入口已接collab-all默认清单（15→16），smoke角色清单换顾问并加常驻流程；搜改动文件名及固定计数的证据在 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/entry-inventory.log。定向门进行中，未跑全门。
working: 2026-10-05T07:57:30Z 修订分支补验完成：python3 -B tests/roles-walkthrough.py 从已安装说明书提取17个正常步骤与4个修订步骤，修订source_event/CAS/spec_rev加一/authorization清空/主控plan-authorize后派发全部rc=0，6PASS/0FAIL；预算破坏负例按预期拒绝且票不变。日志 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/walkthrough-revision.log。
working: 2026-10-05T08:00:22Z 已完成门禁：fast rc=0（无ShellCheck告警），lint rc=0/9PASS/0FAIL且LINT PASS，smoke rc=0/816PASS/0FAIL，collab-roles rc=0/24PASS/0FAIL，collab-gate rc=0/27PASS/0FAIL。原始输出与.rc收据均在 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/。规划、落地、入口检查继续执行，保留串行定向节奏；本票未执行仓库full。
done: 2026-10-05T08:15:42Z 执行者交付 commit=4f9a344601457fc7d68596100c120367b29ad079；detached HEAD，工作区干净。五角色总览、顾问改名与旧定制文件保留提示、完整常驻流程、4步修订重授权、主控关本票实现/审核窗口及账本提交时机均完成；17个正常步骤和4个修订步骤从安装文档原样执行。只改白名单，未触真Herdr/模型、未建实际仓分支或push、未跑仓库full。汇总证据 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/verification.json。
done: 2026-10-05T08:15:42Z 快门 bash bin/qwb-test.sh fast rc=0/0PASS/0FAIL（无ShellCheck告警）；bash bin/qwb-lint.sh rc=0/9PASS/0FAIL且LINT PASS；bash tests/smoke.sh rc=0/816PASS/0FAIL。单独 bash tests/collab-roles.sh=0/24/0、collab-gate.sh=0/27/0、collab-planning.sh=0/34/0、collab-land.sh=0/54/0（依次rc/PASS/FAIL）。所有原始.log及自然.rc收据均在 .worktrees/roles-walkthrough-docs/.qwb-tmp/roles-walkthrough-evidence/。
done: 2026-10-05T08:15:42Z 五场景逐验：python3 -B tests/roles-walkthrough.py rc=0/6PASS/0FAIL，覆盖两票verified/main先快进候选后窄提交账本、坏预算经同一正常执行器报03-assign与plan-assign.json且票字节不变、空目录实装顾问无旧文件、旧定制文件两次升级字节不丢且提示、模板无过时称谓；另验修订CAS和重授权。起点先红rc=1缺installed常驻流程，baseline-red.log留证。最终原始输出 walkthrough-final.log。
done: 2026-10-05T08:15:42Z 入口核对：在smoke与collab-all搜smoke.sh/collab-all.sh/collab-land.sh/roles-walkthrough.py/roles-walkthrough.sh及新旧角色名，清单记录entry-inventory.log；smoke改角色清单并加常驻流程，collab-all默认15改16并接新入口，无其他固定PASS数需改。bash tests/collab-all.sh tests/roles-walkthrough.sh rc=0/1PASS/0FAIL（入口自检45文件；单项85秒）。资源查无本票测试进程；核owner后清理早期工具超时残留两目录，仅留日志，见resource-check.json。
working: 2026-10-05T08:42:39Z 主控验收：工人提交 4f9a344 合入主干为 0f00d54。主控通读了常驻流程全文与各角色说明改动；把示例里两个常驻职责的档位由 Sol high 改为 Astra low（a4ddc78），改后与链路收尾票合并在一起重跑按说明书原样执行的测试 6/0。合并后主干 a4ddc78 全门 rc=0、861 PASS、0 FAIL（724 秒，.qwb-tmp/ctl-full-merge11.log）；真机端到端第 15 轮 15 项断言全 PASS（docs/reviews/2026-10-05-e2e-real-claude-pi-r7.md）。
