# 任务书：工具层只留 Claude Code 与 Pi，模型一律经 magpie，按 Rocky 的模型分工重排工人表与派工规则

```
任务 id:  harness-roster
state: verified
implementation-authorized: Rocky 2026-10-05「停止使用codex,工具层harness只是用claude code+pi两个，codex和其他harness从清单去除」「pi下17个模型均通过magpie接入」及随后逐条给出的模型分工
dispatch-budget: 3
来源:     2026-10-05 Rocky 与主控逐条确认的调整（原话见下）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-harness-roster.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/harness-roster（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

### Rocky 原话

- 「停止使用codex,工具层harness只是用claude code+pi两个，codex和其他harness从清单去除」
- 「我现在本机安装了magpie，可以直接使用pi去对接其他所有模型，所以只保留claude code 和pi即可」「pi下17个模型均通过magpie接入」
- 「claude默认模型为opus 5.5，fable只作为adviser或者复杂规划等」
- 「主控默认为opus 5.5 medium，或者pi+astra low／常规实现目前默认pi+ 6.1 sol high／复杂架构，pi+astra high或者fable low／独立审核使用astra low／机械改动批量小活，纯规划，调研，目前都集中使用pi+6.1 sol high，这个额度足够／常驻职责，pi+astra low」「常驻职责也可以跟实现档为走 不限制」
- 关于审核：「没必要审核换家族」「模型不一样即可」（**审核规则的代码改动不在本票**，由另一张票 `review-model-rule` 做；本票只管工人表、规则与说明里涉及工具和模型的部分）

### 主控据此定的落地口径

**工具**：产品清单里只出现 `claude`（Claude Code）与 `pi` 两种工具。Codex、devin、omp、cmdc 从工人表、默认工人清单、派工规则、家族声明、说明文档、README 里去掉。Pi 工人一律显式写 `--provider magpie`，不出现其他渠道。

**模型型号**（本机 `pi --list-models` 实测可用）：`codex/gpt-6.1-sol`、`codex/gpt-6-astra`；Claude 为 `claude-opus-5-5` 与 `claude-fable-5-1`。执行者须用 `claude --help`、`pi --list-models` 只读核对型号与参数写法，**不启动任何模型会话**；模板里现有的 `claude-fable-5` 改为 `claude-fable-5-1`。

**工人表**（`templates/workers.sh`，全部用新式 `qwb_worker 名字 herdr 工具 -- 参数…`）：

| 工人名 | 工具 | 模型 | 档位 | 用途 |
|---|---|---|---|---|
| `pi` | pi | magpie `codex/gpt-6.1-sol` | high | 兼容旧名，等同 `pi-sol-high` |
| `claude` | claude | `claude-opus-5-5` | medium | 兼容旧名，等同 `claude-opus-medium` |
| `pi-sol-high` | pi | magpie `codex/gpt-6.1-sol` | high | 常规实现、机械改动、批量小活、纯规划、调研、维护 |
| `pi-astra-high` | pi | magpie `codex/gpt-6-astra` | high | 复杂架构、跨模块、高风险 |
| `pi-astra-low` | pi | magpie `codex/gpt-6-astra` | low | 独立审核（验证工人产出） |
| `claude-opus-medium` | claude | `claude-opus-5-5` | medium | 备用审核档：默认规则不引用，仅票面明确点名时使用 |
| `claude-fable-low` | claude | `claude-fable-5-1` | low | 复杂架构的备选；顾问、复杂规划 |

`templates/config.sh` 的 `QWB_WORKERS` 与之一致。家族声明只保留这四个模型各一行（`magpie/codex/gpt-6.1-sol` 与 `magpie/codex/gpt-6-astra` 为 gpt，两个 Claude 型号为 claude；具体键的写法照现有 `qwb_family` 行与 `qwb_model_family` 的取键规则，别猜）。

**派工规则**（`templates/dispatch-rules.json`）：

| 活的类型 | 候选（按顺序） |
|---|---|
| 常规实现、机械改动、批量小活、纯规划、调研、维护（默认） | `pi-sol-high` |
| 复杂架构、跨模块改动、高风险改动 | `pi-astra-high` → `claude-fable-low` |
| 独立审核 | `pi-astra-low`；规则文字里写明「审核优先用 GPT 模型；实现者是 astra 时改用 `pi-sol-high`（审核者模型须与实现者不同）」 |
| 顾问、复杂规划 | `claude-fable-low` |

额度用尽的口径：只有一个候选的类别不自动换模型，照现有逻辑报不可用并停下，由主控报使用者；不要为此新增顺延候选。

**主控宿主**：只支持 Claude Code（Stop hook）与 Pi（扩展）。说明文档里 Codex 当主控的做法（前台循环 `--block --max-ms 180000`）整段去掉；未知宿主照旧报告并停止。本票**不写**「主控该用哪个模型」的推荐：Rocky 随后决定把主控拆成「首脑」与「调度」两个角色并各定了模型，那部分由后续的角色票落地；本票里凡提到主控的句子只做去掉 Codex 所需的最小改动，不重写角色职责。

**真机验收脚本**（`tests/e2e-real.sh`、`tests/e2e-real.py`、`tests/e2e-controllers-cli.py`）：`--worker` 改为只接受 `pi|claude`，`--controller` 只接受 `claude|pi`。默认：主控 claude 为 `claude-opus-5-5` medium（Rocky 2026-10-05 终裁「还是用opus当主控了」，取消调度角色与 sonnet）、pi 沿用现有的 `magpie/codex/gpt-6.1-sol` high；工人 pi 为 magpie `codex/gpt-6.1-sol` high、claude 为 `claude-opus-5-5` medium。工人是 Pi 时会话存到临时目录、`~/.pi/agent/trust.json` 跑前跑后不变（照主控是 Pi 时的现有做法）；工人是 Claude 时信任框照主控是 Claude 时的现有做法处理。脚本只需能离线通过自己的用例；真机运行由主控做，**执行者不许真跑**。

### 范围边界（保守口径，主控已向 Rocky 说明）

- **只改清单、规则、说明与测试，不删脚本里识别其他工具的代码。** `bin/` 里对 codex 等的识别与处理（如 `bin/qwb-run.sh` 的信任预置、`bin/qwb-role.sh` 的工具枚举、`bin/qwb-dispatch.sh` 的额度 lane）保持不动；只允许改 `bin/` 里的帮助文字与注释中把 codex 当例子的句子。
- 旧式声明行（`qwb_worker 名字 herdr 参数…`，无 `--` 分隔）的兼容解析不动——已装项目的 `workers.sh` 仍是旧式。
- 不改审核身份规则的代码（`bin/qwb-lint.sh`、`bin/qwb-ledger.sh` 的家族判定）与 `tests/review-identity.sh` 的判定用例——那是另一张票。
- 不动 `docs/` 下的历史记录与决策文档，不动 `tasks/` 下的旧票。

白名单：`templates/` 下全部文件；`README.md`、`README.zh.md`；`bin/*.sh` 仅限帮助文字与注释；`tests/` 下为适配所需的文件；`qwb.config.sh` 不改。

### 测试怎么处理

测试里大量把 `codex`、`devin` 当工人名用（`tests/smoke.sh` 约 170 行、`tests/optional-routing.sh` 约 30 行等）。原则：

1. 测的是**仍然存在的代码路径**（例如 codex 信任预置、旧式声明解析、额度 lane）的用例保留，测试自己在临时项目里声明所需的工人，不依赖模板默认带这些名字。
2. 只是「需要随便一个工人」的用例，改用 `pi` 或 `claude`。
3. 断言模板内容（工人表、默认清单、派工规则）的用例，按新内容更新。
4. 不许为了让测试通过而删断言；每删或改一条断言，在 `done:` 行说明属于上面哪一类。

## 1. 验收场景

### user_正常路径_新装项目只有两种工具

Given 一个全新的临时项目
When  运行 `bash bin/qwb-init.sh 项目`
Then  `qwbuddy/workers.sh` 与 `qwbuddy/config.sh` 里只有上表七个工人，工具列只有 `pi` 与 `claude`，每个 Pi 工人都带 `--provider magpie`；`qwbuddy/dispatch-rules.json` 与上表一致且通过现有 schema 校验；安装出的全部说明文件里搜不到 codex、devin、omp、cmdc（大小写不敏感，历史记录目录除外）

### user_正常路径_具名工人按声明的模型与档位启动

Given 新装项目与假 Herdr
When  分别用七个工人名派发一张票
Then  假 Herdr 收到的启动参数里，工具、渠道、模型、档位与上表逐项一致；Claude 工人仍被注入读项目根的授权参数

### user_正常路径_自动派工按新规则解析

Given 新装项目、假的分类服务分别命中四类规则
When  用 `--worker auto` 派发
Then  依次解析为 `pi-sol-high`、`pi-astra-high`、`pi-astra-low`、`claude-fable-low`；复杂架构的首选被停用时顺延到 `claude-fable-low`

### user_失败路径_只有一个候选的类别不可用时停下

Given 新装项目，`pi-sol-high` 被列入停用，或额度快照显示其余量低于阈值
When  对常规实现类的票用 `--worker auto` 派发
Then  按现有逻辑报配置或候选不可用并拒绝派发，不自动换成别的模型；没有任何副作用

### user_失败路径_已去掉的工人名派不出去

Given 新装项目
When  用 `--worker codex`、`--worker devin` 派发
Then  按现有的「工人未注册」规则拒绝，信息清楚，无副作用

### user_正常路径_已装项目的旧配置照常工作

Given 一个带旧式 `workers.sh`（含 `qwb_worker codex herdr …`、`qwb_worker devin herdr …`）与旧 `dispatch-rules.json` 的已装项目
When  重新运行安装器，再用其中的旧工人名派发
Then  安装器保留这两个文件不覆盖；旧工人照旧能派出，启动参数与升级前相同——本票不破坏已装项目

### user_正常路径_真机验收脚本只认两种工具

Given 改后的 `tests/e2e-real.sh`
When  分别传 `--worker devin`、`--controller codex`、`--worker pi --controller claude --help` 等参数（只走到参数校验与离线用例）
Then  前两种按参数错误退出并说明只接受 `pi|claude`、`claude|pi`；帮助文字写明新的默认主控与工人模型；`tests/e2e-controllers-cli.py` 的离线用例全过

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话**（不跑 `tests/e2e-real.sh` 的真实流程，不用 `pi`、`claude` 发起对话；只读的 `--help`、`--version`、`--list-models` 可以）。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改任何运行时判定；`bin/` 只许动帮助文字与注释。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。分成几个主题清楚的提交（模板与规则、说明文档、真机验收脚本、测试适配）。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 另一张票 `review-model-rule` 可能同时在别的副本里进行，它改 `bin/qwb-lint.sh`、`bin/qwb-ledger.sh`、`tests/review-identity.sh`、`templates/roles/审核者.md` 与 `templates/QWBUDDY.md` 第 8 节里关于换家族的句子——**这些地方本票不要碰**，避免合入冲突。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`（现在是四段并发，约 6–8 分钟），重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
`done:` 行里另列一份清单：`bin/` 中仍然识别 codex、devin 等工具的代码位置（文件与行号），供主控之后决定是否另开票删除。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不删 `bin/` 里的任何判定代码；不改审核身份规则；不改值守、收尾、派发的行为。
- 不动三个已装项目（`qonnwolf-sites`、`qonnwolfmcp`、`class-video-analysis`），它们的配置由主控在真机验收后处理。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T23:52:24Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-harness-roster pane=w14Z:pV dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/harness-roster base=70581f9
working: 2026-10-04T23:53:11Z 执行者已完整读规格、模板主说明/工人启动/宿主值守/CI专项与双语README；基点70581f9、工作区clean。只读claude --help和pi --list-models均rc0，magpie两个指定型号可见，Claude支持--model/--effort（help不证明服务端型号可用）；日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-{claude-help,pi-models}.log。开始模板规则阶段；规格中说明搜不到codex按工具名理解，指定模型ID中的codex/必须保留。
working: 2026-10-04T23:54:00Z 模板与规则阶段完成，七工人均为显式herdr工具声明，Pi均magpie，四模型家族键沿qwb_model_family完整键规则。bash bin/qwb-test.sh fast rc0，日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-fast-template.log；已提交模板与规则，继续说明文档阶段。
working: 2026-10-04T23:54:50Z 说明文档阶段完成并提交：双语README、模板宿主/启动说明已去其他工具推荐与Codex主控前台流程；保留指定模型ID及另一票负责的审核身份段落。bin仅qwb-run帮助与注释示例变化，运行时未改。继续真机脚本的离线适配。
working: 2026-10-04T23:57:29Z 主控裁决修订（Rocky 2026-10-05「门控优先gpt模型」）：独立审核默认仍是 pi-astra-low；实现者是 astra 时改用 pi-sol-high，不再改用 claude-opus-medium。claude-opus-medium 留在工人表里作备用审核档，用途写「默认规则不引用，仅票面明确点名时使用」，派工规则与说明文字里不得把它写成默认或顺延候选。票正文工人表与派工规则两行已同步改写，以正文现状为准；已提交的模板、规则、说明与测试里凡写过「实现者是 astra 时改用 claude-opus-medium」的地方一并改掉，追加一个提交即可。
working: 2026-10-04T23:57:51Z 已重读最新正文与23:57:29Z主控裁决：规则文字与config说明均改为审核优先GPT、astra实现改用pi-sol-high；claude-opus-medium留作仅票面点名备用，不进入默认或顺延候选。修订已单独提交，继续离线脚本及测试适配。
working: 2026-10-04T23:58:59Z 真机脚本离线阶段完成并提交：入口只收pi/claude，主控sonnet low或Pi Sol high，工人Pi Sol high/Claude Opus medium。Pi工人独立临时session-dir、两参与方全局trust前后核字节；Claude工人复用严格信任框确认。python3 -B tests/e2e-controllers-cli.py rc0、/bin/bash -n rc0；日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-e2e-cli.log。未运行真机流程，继续其余测试适配。
working: 2026-10-05T00:05:44Z 新装七工人、四类自动路由和禁用顺延已通过；worker-config定向rc0。首轮smoke正在收齐，已定位失败为17c安装授权断言仍期待旧Claude argv尾部（新模板额外固定model/effort），属于模板内容断言第3类，待本轮结束后修正并保留首败日志；另发现collab-roles/pi-profile仍依赖已删pi-glm-high模板，将分别更新真实模板覆盖与自声明兼容夹具，不动运行时。日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-smoke.log。
working: 2026-10-05T00:06:10Z 主控裁决修订二（Rocky 2026-10-05「不要调度了」「还是用opus当主控了」）：真机验收脚本里 claude 主控的默认模型由 sonnet low 改回 claude-opus-5-5 medium；pi 主控默认不变。票正文真机验收脚本一段已同步改写，以正文现状为准。已提交的脚本、帮助文字、说明与测试里凡把 claude 主控默认写成 sonnet 的地方一并改掉，追加一个提交即可；其余条款不变。
working: 2026-10-05T00:10:39Z 已重读真机脚本条款及00:06:10Z修订二，主控Claude默认已改回claude-opus-5-5 medium，帮助、双语README与TUI型号离线断言同步；单独追加提交，Pi默认不变。离线CLI rc0、Bash3.2语法rc0，日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-e2e-opus-cli.log。首轮smoke已完整退出rc1，保存原日志，现修模板/分类夹具断言后继续验收。
working: 2026-10-05T00:15:17Z 测试适配阶段已提交：新装七工人/四家族/说明扫描、逐项argv、四类auto及禁用顺延、单候选禁用和低额零副作用、旧codex/devin重装字节及启动argv不变；旧工具兼容夹具自声明。模板断言按第3类更新，通用optional-routing工人按第2类改claude，旧lane/解析/信任按第1类保留。Pi profile定向rc0（Bash3.2公开入口），快门rc0；正在取得最终routing回执，然后在提交候选上跑全门。
working: 2026-10-05T00:16:31Z 最终定向routing rc0、Pi profile rc0、Opus E2E离线CLI rc0，全部七场景均接入既有smoke/collab入口。候选2183765，git status --short为空；开始提交后bash bin/qwb-test.sh full，日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-full.log，退出回执同名.rc。首轮smoke除已修模板/夹具断言外，订阅回收5次读龄均超过产品2秒观察窗（机器负载问题），保留原始首败日志，不降低门禁。
done: 2026-10-05T00:31:02Z 全部完成，最终提交=21837659b7c592130044706b26e7fc0cfa446290。提交后 bash bin/qwb-test.sh full rc0，grep -c '^PASS'=854、grep -c '^FAIL'=0，00:16:31Z—00:27:06Z共635秒；SMOKE/REVIEW-IDENTITY/LINT/COLLAB-ALL（15项）全部通过。快门rc0、无新增ShellCheck告警。全门后 git status --short 输出为空，记录=.worktrees/harness-roster/.qwb-tmp/harness-roster-final-status.log；完整全门日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-full.log，退出回执同名.rc。
done: 2026-10-05T00:31:02Z 场景1通过：python3 -B tests/worker-config.py（已在smoke入口），新装仅七工人、工具pi/claude，Pi均magpie，四完整family键与当前规则逐项一致，全部已装Markdown扫描无旧工具名；规格指定codex/模型ID保留。定向rc0，日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-worker-config.log；最终候选全门内同用例亦通过。
done: 2026-10-05T00:31:02Z 场景2/3通过：bash tests/optional-routing.sh rc0，七工人启动工具/provider/model/effort/权限逐项验证，Claude含项目根--add-dir；auto四类分别为pi-sol-high/pi-astra-high/pi-astra-low/claude-fable-low，架构首选停用顺延Fable。最新裁决文字为astra实现改由Sol审核，Opus仅票面点名备用。最终定向与全门均过，日志=.worktrees/harness-roster/.qwb-tmp/harness-roster-routing-final.log（同名.rc=0）。
done: 2026-10-05T00:31:02Z 场景4/5通过：同一公开optional-routing入口，Sol唯一候选禁用或magpie额度0均rc2且不投递、不改票/不建副本；新工人表下codex/devin显式派发均拒绝且票字节/Herdr调用保持不变。quota、分类服务与Herdr均使用自有桩，全程失效关闭；完整证据=.worktrees/harness-roster/.qwb-tmp/harness-roster-routing-final.log。
done: 2026-10-05T00:31:02Z 场景6通过：worker-config公开入口把旧式codex/devin及旧规则自行声明于临时项目，普通重装保留config/workers/rules原字节，重装前后两工人的agent start argv相同。Pi profile另验旧基点安装/迁移幂等与旧多渠道lane/family；/bin/bash 3.2公开入口全部通过。证据=.worktrees/harness-roster/.qwb-tmp/harness-roster-worker-config.log、harness-roster-pi-profile-final.log（rc0）；正式全门同样通过。
done: 2026-10-05T00:31:02Z 场景7通过：python3 -B tests/e2e-controllers-cli.py及--worker pi --controller claude --help rc0，旧worker devin/cmdc与controller codex/other均参数错误rc2。主控Claude默认claude-opus-5-5 medium，Pi默认不变；参与方trust字节、Pi临时session与Claude确认选择均离线验证。证据=.worktrees/harness-roster/.qwb-tmp/harness-roster-e2e-opus-cli.log；未运行真实E2E、未启动模型对话或操作真Herdr。CLI只读型号/参数日志为harness-roster-claude-help.log、harness-roster-pi-models.log。
done: 2026-10-05T00:31:02Z 断言改动第1类：smoke旧声明/权限/信任及JEV旧quota-lane回归改用自声明夹具；pi-profile保留旧GLM/其他family断言并自行声明，family负例只删family行以保留工人；worker-config新增旧装前后字节与argv比较。第2类：optional-routing通用JSON clear/explicit/envkey/auto clear/权限等候选与断言由codex改claude。逐hunk原始清单=.worktrees/harness-roster/.qwb-tmp/harness-roster-assertion-changes.diff；无为变绿删除原有契约断言。
done: 2026-10-05T00:31:02Z 断言改动第3类：smoke §5七名默认值、§17c三条新式Claude授权/非Claude字节一致/新版Fable/10项声明argv及8项启动尾部、§51g五个固定参数/Pi启动/§51h工人数7、JEV实际模板Astra/Sol/Fable映射；optional-routing七工人精确flag值与新路由；pi-profile工人数7/四family；collab-roles模板Sol/Astra high/low与gate同档。E2E帮助/错误/身份断言按仅两工具及Opus终裁更新，Codex专用TUI/fast断言随取消该入口替换为新入口拒绝和Pi/Claude状态/信任断言。清单同前述diff。
done: 2026-10-05T00:31:02Z 首败留证：独立smoke rc1（8 FAIL），5项旧Claude模板断言、2项分类/额度夹具已修；另订阅回收因5次读龄超2秒无法测量，未降阈值。正式全门中同探针4次INCONCLUSIVE后取得有效窗口并通过，非零重采样。首败=.worktrees/harness-roster/.qwb-tmp/harness-roster-smoke.log及同名.rc；正式全门全文与rc0已保留。工具时限截断的定向运行保留routing-fixed/collab-roles日志，不冒认其缺失退出码；最终定向及正式全门另有完整回执。
done: 2026-10-05T00:31:02Z bin仍保留的旧工具识别清单：qwb-dispatch.sh:281/283（codex/codex-native额度lane），qwb-role.sh:156（主控工具枚举含codex），qwb-run.sh:697/698/700/704（codex信任预置）；旧工具注释/帮助另见qwb-dispatch.sh:20、qwb-run.sh:665/667（含devin）、qwb-wake.sh:42/830。完整扫描=.worktrees/harness-roster/.qwb-tmp/harness-roster-retained-tools.log。运行时及qwb.config.sh未改，bin只改qwb-run帮助/注释两处；证明=.worktrees/harness-roster/.qwb-tmp/harness-roster-runtime-scope.log。
done: 2026-10-05T00:31:02Z 残留进程清单：测试残留=[]，lsof cwd扫描rc0且stderr空；登记的全门6027、smoke97710、最终routing73765、Pi-profile55363均已退出。仅执行者node21845及其宿主shell21737保持本票cwd，瞬时验收进程另标inspection；无本票测试服务存活。证据=.worktrees/harness-roster/.qwb-tmp/harness-roster-final-processes.json。工作目录保持隔离detached候选，未建分支/未push/未碰已装项目，主账本只追加本人状态行，state字段未改。最终提交=21837659b7c592130044706b26e7fc0cfa446290。
working: 2026-10-05T01:20:25Z 主控验收：独立核对改动与探针，返修项已补；提交已 cherry-pick 进 main，合并后 main @ 4bdd2fd 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、429 秒（.qwb-tmp/ctl-full-merge.log）；真机验收第 10 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS。详见 docs/reviews/2026-10-03-qwb-full-audit-r1.md「工具与角色调整」。
