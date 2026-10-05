# 任务书：独立审核的身份规则从「必须换模型家族」改为「模型不同、会话不同」

```
任务 id:  review-model-rule
state: verified
implementation-authorized: Rocky 2026-10-05「没必要审核换家族」「模型不一样即可」
dispatch-budget: 3
来源:     2026-10-05 Rocky 定模型分工时的裁决：常规实现用 gpt-6.1-sol，独立审核用 gpt-6-astra，两者同属 GPT 家族
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-review-model-rule.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：审核不需要换模型家族，审核者的模型和实现者不一样就行。他的日常搭配是 sol 实现、astra 审核，两者同家族，现有规则会拒绝，或要求他每一轮单独批准一次。

### 现状（主控已读代码确认）

家族规则落在两处代码：

1. `bin/qwb-lint.sh` 第 8 节「需独立审核票的审核身份可核验」：只对带 `review-required: yes` 的票启用。要求 `review-impl:` 与 `review-rev:` 两行各有 `model/family/session/evidence`；`family` 不得为 unknown；**两方 family 相同即 FAIL**；两方 session 相同也 FAIL。
2. `bin/qwb-ledger.sh` 的 `gate-review`：对已迁协作票，用 `qwb_model_family` 从项目 `workers.sh` 的 `qwb_family` 声明解析家族，**解析不出即拒绝**；`同family审核冲突` 时拒绝，除非审核 JSON 带 `authorization` 且对应一份 `qwb-sol-astra-review-v1` 的用户批准。

说明文档里同样写着「审核必须换模型家族」：`templates/roles/审核者.md`、`templates/roles/门禁.md`、`templates/QWBUDDY.md` 第 8 节、`bin/qwb-lint.sh` 的帮助文字，可能还有 README。

### 主控裁决的新规则

**审核者与实现者必须是不同的模型，且是不同的原生会话。家族不再比较，也不再要求可解析。**

1. **「同一个模型」的判定**：取两方 `model` 值最后一个 `/` 之后的部分，忽略大小写后相等即为同一模型。渠道前缀不算（`magpie/codex/gpt-6-astra` 与 `openai-codex/gpt-6-astra` 是同一模型）；推理档位不算（astra low 审 astra high 是同一模型，**拒绝**）。
2. **会话规则不变**：两方原生 session 相同照旧拒绝；`gate-review` 里「审核会话不得等于门禁自身会话」等现有会话判定原样保留。
3. **family 字段降为可选附记**：
   - `bin/qwb-lint.sh`：身份行必填字段改为 `model/session/evidence`；`family` 可有可无，值为任意（含 unknown）都不影响结论。已有的带 `family=` 的历史身份行照常通过。
   - `bin/qwb-ledger.sh gate-review`：审核 JSON 里 `family` 键改为可选；存在时不再去 `workers.sh` 解析比对，缺少或解析不出都不拒绝。`qwb_model_family` 函数与 `qwb_family` 声明的解析代码**不删**（别处与测试仍引用），只是 `gate-review` 不再调用它做放行判定。
4. **原有的 Sol→Astra 批准协议**（`authorization` 与 `qwb-sol-astra-review-v1`）：不再是放行的必要条件。不同模型的审核无须任何批准即可通过。审核 JSON 若仍带 `authorization`，照现有逻辑校验它本身的合法性（非法照旧拒绝），但它不能让「同一模型」的审核通过——同模型一律拒绝，没有例外通道。协议的解析代码保留，不在本票删除。
5. 其余身份核对一项不松：型号须与主控授权的工人配置一致、原生 session 与 model 证据须匹配、证据文件须存在、会话目录须属于候选或本项目。
6. **文案**：两处拒绝信息改为说「同模型」（例如 lint 报「实现者与审核者同一模型(型号)」，ledger 报「同模型审核冲突」）；说明文档里「必须换模型家族」的句子统一改成「审核者的模型须与实现者不同，且为独立会话；同一会话换角色不算独立审核」。写法与密度照各文件现有句子，不另起小节。

白名单：`bin/qwb-lint.sh`、`bin/qwb-ledger.sh`（仅 `gate-review` 的身份判定段）、`templates/roles/审核者.md`、`templates/roles/门禁.md`、`templates/QWBUDDY.md`（仅提到换家族的句子）、`README.md` 与 `README.zh.md`（仅提到换家族的句子，没有就不动）、`tests/` 下为验收所需的已接入文件（现有用例主要在 `tests/review-identity.sh` 与 `tests/collab-gate.sh`）。

## 1. 验收场景

### user_正常路径_同家族不同模型通过

Given 一张 `review-required: yes` 的票，实现者 `model=magpie/codex/gpt-6.1-sol`，审核者 `model=magpie/codex/gpt-6-astra`，会话不同，证据齐全；身份行分别带 `family=gpt`、不带 family、带 `family=unknown` 三种写法
When  运行 `bash bin/qwb-lint.sh`
Then  三种写法第 8 节都通过

### user_失败路径_同一模型不同档位或不同渠道拒绝

Given 同样的票，两方模型分别是：完全相同的型号；同型号不同渠道前缀（`magpie/codex/gpt-6-astra` 对 `openai-codex/gpt-6-astra`）；同型号仅大小写不同
When  运行 lint
Then  三种都 FAIL，信息指出是同一模型并带出型号

### user_失败路径_同一会话照旧拒绝

Given 两方模型不同但原生 session 相同；另一组缺 `session` 或缺 `evidence` 或证据文件不存在
When  运行 lint
Then  都 FAIL，文案与起点提交相同

### user_正常路径_协作票门禁放行同家族不同模型且无须批准

Given 一张已迁协作票，门禁已 claim，实现者为 sol、审核者为 astra，原生 JSONL 证据与授权的工人配置一致，审核 JSON **不带** `authorization`；项目 `workers.sh` 里**没有**这两个模型的 `qwb_family` 声明
When  运行 `gate-review`
Then  接受并记录审核；起点提交在同样输入下是拒绝的（先在起点上跑出红，再在改后跑出绿，两份结果都留证）

### user_失败路径_协作票门禁拒绝同一模型且批准也不放行

Given 同上，但两方都是 astra（会话不同、档位不同）；另一组在此基础上带一份格式完整的 `qwb-sol-astra-review-v1` 批准
When  运行 `gate-review`
Then  两组都拒绝，信息为同模型审核冲突；票内容不变

### user_失败路径_其余身份核对不松

Given 模型不同、会话不同，但分别制造：型号与授权配置不一致、JSONL 证据里的 model 或 session 对不上、审核会话等于门禁自身会话、会话目录不属于候选或项目、`authorization` 键存在但内容非法
When  运行 `gate-review`
Then  各自按起点提交的原文案拒绝

### user_正常路径_其余行为逐字节不变

Given 起点提交与改后的两个脚本
When  对不涉及审核身份的 lint 各节，以及 `gate-review` 之外的 ledger 子命令现有用例各跑一遍
Then  stdout、stderr、退出码新旧相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 这是合入前的把关规则：只放宽「同家族」这一条，并新增「同模型拒绝」；其余任何核对不许顺手放松。拿不准的一律拒绝。
- 第四个场景要求项目 `workers.sh` 里没有 `qwb_family` 声明。如果 `gate-assign`、`claim` 等 `gate-review` 之前的步骤自己就因为缺声明而拒绝，不要去放松它们：停下，写 `needs-decision:` 说明是哪一步、哪一行代码拒绝的。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。
- 另一张票 `harness-roster` 同时在别的副本里进行，它改 `templates/workers.sh`、`templates/config.sh`、`templates/dispatch-rules.json`、`templates/host-watch-guide.md`、`templates/worker-launch-guide.md`、真机验收脚本、`tests/smoke.sh` 等，以及 `templates/QWBUDDY.md` 里与 Codex 有关的句子——**这些地方本票不要碰**；`templates/QWBUDDY.md` 本票只改提到换家族的那几句。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 七个场景逐个验证，命令与结论写进 `done:` 行。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`（四段并发，约 6–8 分钟），重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
`done:` 行里另列：改完后仓库里还有哪些地方引用 `qwb_family` 或 `qwb_model_family`（文件与行号），供主控之后决定是否另开票清理。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不删 `qwb_model_family`、`qwb_family` 的解析代码与 Sol→Astra 批准协议的解析代码；不改工人表与派工规则；不改会话判定。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T23:52:28Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-review-model-rule pane=w14Z:pW dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule base=70581f9
working: 2026-10-04T23:53:30Z 执行者完成规格与调用链核对；基点70581f928c7629c1d305ed17158f2fa8b0d84bb5、工作区clean；证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG；准备在已接入测试补无family声明和同模型反例，真实Herdr/模型会话均不触碰。
working: 2026-10-04T23:54:53Z 起点红测已保存：bash tests/review-identity.sh rc=1；QWB_GATE_MODEL_RULE_ONLY=1 bash tests/collab-gate.sh rc=1，公开gate-assign/claim均通过，gate-review因缺qwb_family声明拒绝；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG/lint-red.log,/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG/gate-red.log。
working: 2026-10-04T23:59:53Z 实现与窄验完成：9个白名单文件；lint新规则rc=0；/bin/bash审核窄验rc=0，覆盖无family声明放行、同模型三组含完整批准拒绝、其余身份/授权拒绝；fast rc=0；lint非第8节及会话/缺字段/缺证据文案新旧逐字节一致；证据=.qwb-tmp/review-rule.jeLcJJxG/{lint-green,gate-green,fast,lint-bytes}.log。白名单外templates/TASK.md:107与templates/config.sh:30仍写旧规则，未改；继续非review ledger字节对照与提交后full。
working: 2026-10-05T00:02:21Z 候选已提交=aba698ad9287790495e975c31d76043c14135d8f，git status --short为空；fast-final rc=0、Bash3.2语法及scope字节边界检查通过。非review ledger逐调用stdout/stderr/退出码对照仍执行中（根PID12839）；已登记full监督器，等对照成功回执后串行执行唯一一次提交后bash bin/qwb-test.sh full，日志与退出回执=.qwb-tmp/review-rule.jeLcJJxG/full.log,full.rc。
working: 2026-10-05T00:07:53Z 非review ledger逐调用对照完成rc=0：170次公开CLI调用stdout/stderr/退出码一致，覆盖原collab-gate全部后段；原始双份记录=.qwb-tmp/review-rule.jeLcJJxG/call-*.json（文件枚举，仅报告）；lint非身份各节及原拒绝文案对照rc=0；全门已开始，候选仍aba698ad9287790495e975c31d76043c14135d8f，等待自然退出回执full.rc。
working: 2026-10-05T00:10:46Z 提交后full继续原轮，lint/review-identity两段已PASS；额外原生Bash3.2 lint对照因20秒工具上限中断（退出码未知，保留lint-bash32.log），已改后台独立日志lint-bash32-final.log和退出回执继续补验，不改源码、不重启full。
done: 2026-10-05T00:17:36Z 执行完成 sha=aba698ad9287790495e975c31d76043c14135d8f；提交后唯一一次 bash bin/qwb-test.sh full：rc=0，PASS=846、FAIL=0（grep -c列首计数），耗时534秒；git status --short输出为空；测试残留进程清单=[]、lint临时fixture残留=[]。完整日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG/full.log；退出码full.rc，汇总summary.json及residual-processes.json。
done: 2026-10-05T00:17:36Z 场景1/2/3：/bin/bash tests/review-identity.sh rc=0（lint-green.log）；同家族Sol/Astra的family=gpt/缺省/unknown/任意附记通过；完全同型号、不同渠道、仅大小写及high/low附记同型号均拒绝并点名；同session、缺model/session/evidence及证据不存在均拒绝。原缺字段文案按规格保留，family判定已可选。实际脚本Bash3.2逐例对照rc=0（lint-bash32-final.log）。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG。
done: 2026-10-05T00:17:36Z 场景4：起点70581f9下 QWB_GATE_MODEL_RULE_ONLY=1 bash tests/collab-gate.sh rc=1，gate-assign/claim通过，gate-review自然255因缺qwb_family声明拒绝（gate-red.log）；相同已接入夹具改后接受无authorization的Sol/Astra，项目workers无任何qwb_family声明。QWB_GATE_REVIEW_AUTH_ONLY=1 /bin/bash tests/collab-gate.sh rc=0（gate-green.log）；只用临时Git/JSONL/fakeHerdr，非真实模型会话。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG。
done: 2026-10-05T00:17:36Z 场景5/6：同一gate-green.log窄验rc=0；Astra high/low三个型号变体，各在无批准/格式完整批准下均同模型审核冲突且票字节不变；型号授权不符、原生model/provider/effort/session错配、门禁自审、同session、非法cwd、缺证据/字段及非法authorization按原诊断零写入拒绝；合法可选Sol→Astra批准仍核验并保留。首轮新测试误写open:预期已纠正，记录见attempt-notes.txt。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG。
done: 2026-10-05T00:17:36Z 场景7：QWB_COMPARE_DIR=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG /bin/bash /Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG/compare-gate.sh rc=0，170次非gate-review公开入口的新旧stdout/stderr/退出码一致（gate-bytes.log及逐调用call-N.json）；compare-lint.sh rc=0，非第8节及原拒绝诊断一致（lint-bytes.log）；help/invalid/read/metrics另作原始字节对照ledger-raw-bytes.json。scope.json证明ledger范围外、lint帮助/第8节外、解析器和隔离夹具字节不变；fast-final rc=0，无新ShellCheck告警。
done: 2026-10-05T00:17:36Z 范围外旧文案仍在templates/TASK.md:107与templates/config.sh:30（后者属harness-roster），按白名单未改；家族解析器、qwb_family声明解析和Sol→Astra批准协议解析保留。下列引用为本固定候选的完整仓内索引，原始文本=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule.jeLcJJxG/family-references.log；精简索引family-reference-index.txt。
done: 2026-10-05T00:17:36Z 保留的qwb_family/qwb_model_family引用：bin/qwb-dispatch.sh:242；tests/collab-land.sh:26；bin/qwb-lib.sh:91,196,201；tests/collab-planning.sh:30；templates/workers.sh:24,25,26,27,28,29,31,32,33；tests/pi-profile.sh:98,100,101,102,124；tasks/2026-10-04-audit-pi-profile.md:37,105,106,112；templates/worker-launch-guide.md:8；tests/collab-gate.sh:189,191,487,488,489,492,510；tests/collab-test-policy.sh:27。
done: 2026-10-05T00:17:36Z 保留的qwb_family/qwb_model_family引用：tests/collab-posture.sh:92；tests/smoke.sh:1314；tasks/2026-10-04-audit-readme-refresh.md:22,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,227,229,236。
done: 2026-10-05T00:17:36Z 保留的qwb_family/qwb_model_family引用：docs/reviews/2026-10-03-qwb-full-audit-r1.md:165,244,310,321。
working: 2026-10-05T00:20:39Z 主控验收返修（第1轮，候选 aba698a 之上追加一个提交）：主控独立探针九项符合预期，全门回执认可。两处要补：① bin/qwb-lint.sh 第8节两条「身份字段不全(需model/family/session/evidence)」文案改为「(需model/session/evidence)」——family 已非必填，原文案会误导；这是任务书场景三「文案与起点相同」写得过死，以本行为准，同步改断言。② bin/qwb-ledger.sh gate-review：family 键存在时其值必须是非空字符串（沿用 string_ok），否则按「审核身份unknown/字段不全」拒绝且零写入——现在任意 JSON 值都会被收下并写进票；补一条失败用例（family 为对象、为空串各一）。③ 白名单追加 templates/TASK.md：把第107行附近仍写「换模型家族」的句子改成新规则，句子级改动。templates/config.sh 第30行不归本票，不要动。补完跑快门与 tests/review-identity.sh、tests/collab-gate.sh，提交后再跑一次全门，done 行报新 sha 与结果。
working: 2026-10-05T00:20:55Z 主控补充上一条第③点：templates/TASK.md 里讲审核身份行的整段（约第100–108行，含「family 只写模型家族…写 unknown」「cli=/provider= 绝不充当 family」两条）都按新规则改写——必填是 model/session/evidence，family 可选附记不影响判定，两方模型须不同（同型号换渠道或换档位算同一模型），两方 session 不得相同。仍是句子级改动，不另起小节。
working: 2026-10-05T00:22:00Z 执行者接手第1轮返修与00:20:55Z补充；基点aba698ad9287790495e975c31d76043c14135d8f、工作区clean；范围为两脚本、两已接入测试和templates/TASK.md审核身份段；本轮证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF；先补文案与非法family零写入反例，再最小返修、定向门和提交后full。
working: 2026-10-05T00:26:03Z 第1轮返修红测完成：lint-red rc=1，四条实际必填字段文案反例均失败；gate-red rc=1，family对象被旧gate-review自然rc=0接受，确认反例命中产品缺口。现已最小修正：两条文案、gate-review可选family的非空JSON字符串校验（复用string_ok）、TASK审核身份段和对应断言；保留数字字符串合法、数字拒绝的类型区分；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF/{lint-red,gate-red}.log。
working: 2026-10-05T00:35:34Z 第1轮返修已追加提交=c858884c35cb1bd40bfdb949c19a751bb9549b9b（父aba698ad9287790495e975c31d76043c14135d8f，仅5文件22增10删）；fast、完整tests/review-identity.sh、完整tests/collab-gate.sh均自然rc=0；非法family两方各对象/空串/数字均零写入拒绝，字符串1/unknown/省略通过；scope核对TASK仅100–108行及隔离/另一票文件不变。已启动提交后唯一一次full；日志和回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF/{full.log,full.rc}，等待完成。
done: 2026-10-05T00:45:26Z 第1轮返修完成 sha=c858884c35cb1bd40bfdb949c19a751bb9549b9b；在aba698ad9287790495e975c31d76043c14135d8f之上仅追加1提交，5授权文件22增10删。提交后 bash bin/qwb-test.sh full rc=0，PASS=847、FAIL=0（grep -c列首计数），耗时501秒；git status --short输出为空，残留测试进程清单=[]。完整日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF/full.log；回执full.rc，汇总summary.json、residual-processes.json。
done: 2026-10-05T00:45:26Z 返修①：两条lint缺字段提示改为需model/session/evidence；实现者缺model/session/evidence及审核者缺session四条文案断言均通过。返修③：TASK第100–108行的两条身份示例、family与cli/provider说明按必填三字段、可选family、不同模型（去渠道前缀/忽略大小写/忽略档位）、独立session重写；仅句子级修改，无新小节。templates/config.sh、workers、家族解析器及隔离夹具相对父提交字节不变，证据scope.json。目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF。
done: 2026-10-05T00:45:26Z 返修②：仅gate-review复用string_ok并核JSON字符串类型；family存在时对象/空串/数字均以审核身份unknown/字段不全拒绝，两方共6条失败反例均核票字节不变；省略/unknown/任意非空串及字符串1仍通过，同模型和其余身份/批准守卫保持。旧候选红测lint-red rc=1（4条旧文案不符）、gate-red rc=1（对象被旧gate-review自然0接受）；两份原始日志保留。目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF。
done: 2026-10-05T00:45:26Z 指定提交前验收：bash bin/qwb-test.sh fast rc=0（无ShellCheck告警）；bash tests/review-identity.sh rc=0，PASS=19、FAIL=0；bash tests/collab-gate.sh完整执行rc=0，PASS=23、FAIL=0；四个脚本逐文件/bin/bash3.2 -n通过。原始日志fast.log、review-identity.log、collab-gate.log及同名rc均在/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF。未操作真Herdr、未启动模型会话、未改state或另一票文件。
done: 2026-10-05T00:45:26Z 保留qwb_family/qwb_model_family解析及Sol→Astra批准协议；模板TASK旧同家族拒绝文案已撤除，templates/config.sh:30旧文案留给harness-roster。更新后的完整仓内引用原文=/Users/rocky/projects/qonnwolfbuddy/.worktrees/review-model-rule/.qwb-tmp/review-rule-rework.brNYkPAF/family-references.log；精简索引family-reference-index.txt，下列为本固定候选的文件与行号。
done: 2026-10-05T00:45:26Z 保留的qwb_family/qwb_model_family引用：bin/qwb-dispatch.sh:242；tasks/2026-10-04-audit-pi-profile.md:37,105,106,112；tasks/2026-10-04-audit-readme-refresh.md:22,108,109,110,111,112,113,114,115,116,117,118,119,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,174,175,176,177,178,179,180,181,182,183,184,185,186,187,188,189,190,191,192,193,194,195,196,197,198,227,229,236。
done: 2026-10-05T00:45:26Z 保留的qwb_family/qwb_model_family引用：bin/qwb-lib.sh:91,196,201；templates/workers.sh:24,25,26,27,28,29,31,32,33；tests/collab-land.sh:26；templates/worker-launch-guide.md:8；tests/collab-planning.sh:30；tests/collab-test-policy.sh:27；tests/collab-posture.sh:92；tests/smoke.sh:1314；docs/reviews/2026-10-03-qwb-full-audit-r1.md:165,244,310,321；tests/collab-gate.sh:189,191,491,492,493,496,514。
done: 2026-10-05T00:45:26Z 保留的qwb_family/qwb_model_family引用：tests/pi-profile.sh:98,100,101,102,124。
working: 2026-10-05T01:20:25Z 主控验收：独立核对改动与探针，返修项已补；提交已 cherry-pick 进 main，合并后 main @ 4bdd2fd 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、429 秒（.qwb-tmp/ctl-full-merge.log）；真机验收第 10 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS。详见 docs/reviews/2026-10-03-qwb-full-audit-r1.md「工具与角色调整」。
