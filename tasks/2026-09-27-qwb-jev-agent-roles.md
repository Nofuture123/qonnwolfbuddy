# 任务书：JEV 派工路由加 agents 角色层并落地母仓配置

```
任务 id:  qwb-jev-agent-roles
state: verified
scenarios-fp: 760a7526c15ef14484d9c2d17e984c2c4e53e89c
来源:     Rocky 批准（2026-09-27）：五分类稳定、agent 易变，拆两层；先把 JEV 配置好
派发:     主控（Pi, wT2:p1）→ 执行者（pi worker pane）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-27-qwb-jev-agent-roles.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles
分支:     qwb-jev-agent-roles
```

## 0. 背景与范围

JEV 自动派工（bin/qwb-dispatch.sh）的规则表把「分类→工人」写死在一条 rule 里；Rocky
定为：**分类稳定、agent 易变（额度随时变）**。方案：rules[].worker 写**角色名**，新增
顶层可选 `agents` 映射（角色→当前工人）做唯一换人入口。JEV 请求本就只发 when 文本
（模型看不到 worker 名），角色层不触碰请求构造。

五分类（Rocky 定稿）：复杂架构、跨模块、高风险、纯规划、常规实现。代码审核**不进**
JEV 自动路由（主控按全局规矩人工指定），规则表不写审核条目。

改动范围（白名单）：`bin/qwb-dispatch.sh`、`templates/dispatch-rules.json`、
`tests/smoke.sh`、`.gitignore`（加 `.env` 一行）、`docs/`（仅同主题段落）、
`tasks/lessons.md` + `tasks/lessons/`。
**不改**：`bin/qwb-run.sh`（auto 链路与输出契约不变）、`bin/qwb-lib.sh`、`templates/`
其他文件。母本仓运行配置（`qwbuddy/dispatch-rules.json`、`.env`）由主控在验收后落地，
不进本票 diff（qwbuddy/ 已被 .gitignore 忽略；.env 必须先加入 .gitignore 才许创建）。

## 1. 规格定死（实现照此，不再设计）

新版 dispatch-rules.json 形态（模板与母仓同文）：

```json
{
  "agents": {
    "architect": "codex",
    "cross_module": "codex",
    "high_risk": "codex",
    "planning": "pi",
    "implement": "pi"
  },
  "rules": [
    {"when": "复杂架构：架构设计、核心抽象、跨仓协议", "worker": "architect"},
    {"when": "跨模块改动：一次改动同时穿过多个模块或层", "worker": "cross_module"},
    {"when": "高风险改动：资金、安全、数据删除、生产环境", "worker": "high_risk"},
    {"when": "纯规划：拆解、写规格、调研、不落代码", "worker": "planning"},
    {"when": "常规实现：单模块内的实现、修复、机械改动", "worker": "implement"}
  ],
  "default": { "worker": "implement" }
}
```

引擎语义（qwb-dispatch.sh）：
1. `agents` 可选；存在时必须是对象且每个值满足现有 worker_ok（非空、无空白/控制字符）。
2. rules[].worker 与 default.worker 仍过 worker_ok；若值恰是 agents 的 key → 视为角色，
   输出前解析为 agents[值]；不是 agents 的 key → 视为字面工人名，原样输出（向后兼容
   旧规则文件：无 agents 段时行为与现在完全一致）。
3. 角色解析缺失（key 不在 agents）→ 该条规则视同不可用：命中的规则角色缺失时落
   default 路径并在输出 reason 注明 `role <名> 未映射`；default 角色缺失 → status:error
   reason 同理（不许静默派错人）。解析不做递归（agents 值必须是字面工人名，角色套角色
   拒绝：agents 值若又是 agents 的 key → schema 校验直接 die）。
4. 输出：`worker:` 输出解析后的最终工人名；新增一行 `role: <原始 worker 字段或->`；
   JSON 模式同理（worker=最终、role=原始）。`default_worker` 同样输出解析后的。
5. 新增环境变量 `QWB_TYPESAFE_BASE` 覆盖 TS_BASE（默认仍 https://api.typesafe.ai），
   仅供测试；文档注明。
6. 头部注释与 usage 补 agents 层语义。

## 2. 验收场景（冻结后不得回改迎合实现）

### user_正常路径_角色解析

Given 新版规则文件（agents 层如上）与假 typesafe server（QWB_TYPESAFE_BASE 指向）
When 命中 rule_2（cross_module）
Then stdout `worker: codex` 且 `role: cross_module`；JSON 模式 worker=codex、role=cross_module

### user_正常路径_无agents段向后兼容

Given 旧格式规则文件（无 agents、worker 为字面工人名）
When 命中任意规则
Then 行为与改动前一致：worker 输出字面名、无 role 残留歧义（role: -）

### user_失败路径_角色未映射落default

Given agents 缺 cross_module 映射，命中 rule_2，default 为字面工人
When 派发
Then status:clear、worker=default 工人、reason 含 `role cross_module 未映射`，不派给未知工人

### user_失败路径_default角色未映射

Given default.worker 为角色且 agents 缺该映射
When 派发
Then status:error、reason 含角色未映射，无 worker 输出

### user_失败路径_角色套角色拒绝

Given agents 某角色的值又是另一个角色的 key
When 运行
Then schema 校验 die（exit 2），报「agents 值必须是字面工人名」类错误

### user_正常路径_key缺省仍off

Given 无 TYPESAFE_API_KEY
When 运行
Then 与现在一致：stderr off 一行、exit 0、零网络调用（default_worker 输出解析后的工人名）

### user_正常路径_smoke假server全链路

Given smoke 内嵌本地假 typesafe server（python3，处理 POST /v1/systemone 返回合法 Choice）
When QWB_TYPESAFE_BASE 指向它跑 qwb-dispatch
Then 上述角色/兼容/失败路径断言全部走真实脚本路径验证（不 mock 脚本内部函数）

## 3. 硬约束

- 既有输出格式不破坏：TOON 风格块、exit 码语义（除配置错 exit 2 外一律 0）、key 纪律
  段（fd/3 + unset）一行不动。
- smoke 每条新断言正负例齐全；假 server 用 python3 内嵌（smoke 已依赖 python3），端口
  随机、用完即杀，不留进程。
- `.gitignore` 追加 `.env` 一行（先加再允许建 .env，防 key 入库）。
- 文档：docs/DESIGN.md 或 docs/DECISIONS.md 同主题段补一句 agents 层决策（分类稳定、
  agent 易变，Rocky 2026-09-27 定）。
- lessons：tasks/lessons/ 新篇（JEV 角色层：分类稳定 agent 易变； workers.sh 模板五行
  与 config.sh QWB_WORKERS 的关系），索引加一行。
- 收工前 `bash bin/qwb-test.sh fast` 退出 0，报告附输出尾部。

## 4. 验收门

- 执行者：fast 门退出 0；报告附 herdr agent start --help 式的契约核实（如有）、改动
  清单、断言计数。
- 主控：独立跑 full 门；用真实 key 对一张真实任务书真调 JEV 验证路由结果，并落地
  母仓 qwbuddy/dispatch-rules.json 与 .env。

## 5. 报告要求

往本文件追加 working:/done:/blocked: 状态行（只追加）；done: 附改动清单、fast 门输出
尾部、新增断言数、未覆盖项。
worktree-space: id=wTM root-tab=wTM:t1 path=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles
dispatch: 2026-09-28T10:12:57Z worker=pi agent=qwb-qwb-jev-agent-roles pane=wTM:p1 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles
working: 2026-09-28T10:40:00Z 主控修订场景 4：default.worker 为角色且未映射 → 改为 schema 校验 die（exit 2，配置错误类），不走到运行时 status:error——default 是兜底，兜底解析不了就是配置坏，与「规则文件坏则拒绝派发」同性质；规则 worker 角色未映射仍按场景 3 运行时落 default。off 路径的 default_worker 因此恒为已解析值，无需特判。
dispatch: 2026-09-28T10:19:12Z worker=claude agent=qwb-jev-roles-c2 pane=wTM:p2 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles
dispatch: 2026-09-28T10:21:39Z worker=codex agent=qwb-jev-roles-c3 pane=wTM:p3 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles

working: 2026-09-28T10:22:51Z 执行者 Codex 完成规格与现状读取；baseline=090259b15ca18625a9b99f299f405c852528d5f6，git status --porcelain=v1 为空。白名单限 dispatch 脚本/规则模板/smoke/.gitignore/同主题 docs/lessons；default 未映射按账本修订 exit 2。已请求澄清未知字面工人与缺失角色的判别，先推进独立部分。
working: 2026-09-28T11:20:00Z 主控修订场景 3：agents 存在时，worker 值非 agents key 一律视为字面工人名（无保留字）；「角色未映射落 default」场景废除——拼错/删漏角色时以字面名输出，由 qwb-run 工人整词校验拒绝（fail-closed、错误可定位）。场景 2（无 agents 段）行为不变。原场景 3 改为负例：字面工人名不在 QWB_WORKERS 时 qwb-run 拒绝派发。
dispatch: 2026-09-28T10:25:01Z worker=devin agent=qwb-jev-roles-c4 pane=wTM:p4 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles
blocked: 2026-09-28T12:55:00Z 主控：引擎代码（bin/qwb-dispatch.sh agents 解析）未能落盘——四轮工人各自受阻：pi 无限设计循环、claude/codex 周额度见底限速挂起、devin 深思挂起（规划 buffer 6408c 未输出）。已就绪待收尾：测试（tests/smoke.sh §86 本地 HTTP 全链路）、模板与 .gitignore、母仓规则文件与 .env（主控已落地）、规格 100% 冻结（含两条主控修订）。待有额度窗口重派一击完成：先读 §86 测试确认契约→写引擎→fast 门。
working: 2026-09-28T13:10:00Z 主控修订四（Rocky 定）：1) agent=harness×模型×推理级三元组，workers.sh 具名工人行以 argv 固化模型/effort（各家 CLI 语法执行者查 --help，herdr argv 透传已实测）；2) agents 层改为有序候选列表（role → [工人名...]），解析取第一个「已注册+不在 agents_disabled+quota 余量达标」者；3) 额度门用 quota-axi --json（本机 0.1.40/schema 5，jq 兼容 5/6 可抄 firstmate bin/fm-quota-axi-lib.sh 的 FM_QUOTA_ROW_JQ）；余量判定：windows 中 kind=weekly（无则 session）percentRemaining ≥ 阈值（默认 10，QWB_QUOTA_FLOOR 可调）；quota-axi 未装/失败/快照无该 provider → 跳过额度门只按注册+禁名单（诚实降级）；4) 全部候选不可用 → status:error reason 注明，不静默派错人；5) rules[].worker 与 default.worker 写角色名；字面工人名仍兼容。母仓 qwbuddy/dispatch-rules.json 已同步候选列表形态。
dispatch: 2026-09-28T10:44:36Z worker=codex agent=qwb-jev-roles-c5 pane=wTM:p5 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles

working: 2026-09-28T10:45:10Z 执行者 Codex 收到主控最新补充，开始按顺序核实 harness/model/effort argv 契约、候选列表解析、quota schema 5/6 与降级、耗尽拒绝、角色/字面兼容；保留现有 .gitignore/templates/dispatch-rules.json/tests/smoke.sh WIP，仅改白名单。
working: 2026-09-28T13:40:00Z 主控修订五：agents 存在且全部候选不可用（未注册/agents_disabled/quota 余量低于门槛且无额度外候选）→ qwb-dispatch exit 2（配置错误），reason 逐候选注明排除原因；qwb-run 不改（非零=拒绝派发+显示 reason 的既有处置）。status:error 仅保留给网络/API/响应错（既有语义）。
working: 2026-09-28T10:47:10Z 阶段1完成：已核实 PATH codex=/Users/rocky/.local/libexec/herdr-codex/bin/codex 0.157.1；pi 0.87.1 --model/--thinking；claude 2.1.283 --model/--effort；devin 3000.11.3 --model（无 effort 参数）；omp 18.3.2 --model/--thinking；quota-axi 0.1.40。HERDR_ENV=1，herdr 0.9.1 pane current=wTM:p5/cwd 匹配，agent start --help 验证 --kind 枚举与 -- [AGENT_ARG]...；未创建或启动新工人。模板改为与母仓相同候选列表，扩充 §86 冻结额度正反例，进入引擎实现。待裁定：候选耗尽 status:error 被现有 auto 回退 default 与禁止改 qwb-run 的冲突。
working: 2026-09-28T10:52:57Z 阶段2完成：引擎已实现 agents 有序候选、config+workers 注册核对、禁名单、quota schema5/6 weekly/session 阈值与诚实降级；按修订五 default/命中角色耗尽 exit 2 并逐候选说明原因，qwb-run/lib 未改。§86 本地 HTTP 53 项 PASS，TARGET_EXIT=0；bash bin/qwb-test.sh fast 原始 stdout/stderr 为空，FAST_EXIT=0（前次三条 shellcheck 提示已以动态 source/回调精确注释修复）。初始红灯 RED_EXIT=1。日志在本 worktree .worktrees/jev-validation/{red,target,fast}.log；继续补文档/lessons 与额度门反转验证、既有 routing 契约回归。
working: 2026-09-28T10:58:41Z 阶段3完成：docs/DESIGN.md 同主题决策、docs/jev-agent-roles.md CLI/配置/验证边界、lessons 新篇与索引已写。额度门反转（仅临时副本将阈值条件替换为 false）MUTATION_EXIT=1，7 条业务断言红 + 全链路汇总红；最终原实现恢复验证 TARGET_EXIT=0、56 PASS。旧 routing 契约 19 PASS、exit=0。临时 mutation 副本与测试 tmp 已清理，原始日志保留在本 worktree .worktrees/jev-validation/。
done: 2026-09-28T10:58:41Z 执行者交付（未代替主控验收）：agents 有序角色解析 + 注册/禁名单 + quota schema5/6/weekly-session 阈值/诚实降级 + 候选耗尽 exit 2 逐项原因；role/worker/default_worker 解析与字面兼容。改动清单=.gitignore、bin/qwb-dispatch.sh、templates/dispatch-rules.json、tests/smoke.sh、docs/DESIGN.md、docs/jev-agent-roles.md、tasks/lessons.md、tasks/lessons/JEV角色层与工人注册.md（8 文件，全部白名单）。检查原始结果：bash bin/qwb-test.sh fast => exit=0，输出尾部=<stdout/stderr 均为空>；bash .worktrees/jev-validation/run.sh（提取 smoke §86 原文）=> exit=0，新增断言相对 HEAD=56 PASS/0 FAIL（接手 WIP 21 项，续增35项），输出尾部="PASS  JEV agents 坏配置拒绝且零网络：{"architect":["has space"]}" / "PASS  JEV 假 server 已退出并回收"；bash tests/optional-routing.sh => exit=0、19 PASS，尾部="PASS diagnostic text cannot select worker" / "PASS auto unknown worker before side effects"；git diff --check => exit=0。初始 RED_EXIT=1；额度门反转 MUTATION_EXIT=1，恢复 TARGET_EXIT=0。key-env/key-fd/request=UNCHANGED；bin/qwb-run.sh、bin/qwb-lib.sh、templates/workers.sh、templates/config.sh 与 HEAD 字节一致；模板与母仓规则 JSON 同义；TEST_TEMP_CLEANUP=PASS（HTTP server kill/wait 回收，临时目录/反转副本清理，证据日志保留）。HEAD=090259b15ca18625a9b99f299f405c852528d5f6，dirty=本票8文件未提交；dispatch SHA256=041f41c7f126ce434e1b3fe5774fd7312798e9b2b59ea307cfe0874bc3276970。Herdr/各 CLI 帮助核实见阶段1与 docs/jev-agent-roles.md。未覆盖项：full 门、真实 key/真实任务 JEV、真实 quota provider 联网、具名模型会话运行、母仓 workers/config/.env 落地均留主控；本执行者未写母仓运行配置、未提交/推送/合并。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles/.worktrees/jev-validation（target-final.log、fast-final.log、routing-final.log、mutation.log、red.log）。
working: 2026-09-28T11:12:22Z 执行者接 Sol P2 唯一返修：仅改 bin/qwb-dispatch.sh 快照唯一性校验与 tests/smoke.sh §86；先冻结 schema5 同 provider、schema6 同 provider+accountKey 的高低余量重复行正反顺序负例，要求均丢弃额度快照并明确降级。
done: 2026-09-28T11:13:16Z Sol P2 唯一返修完成：仅增量修改 bin/qwb-dispatch.sh 与 tests/smoke.sh §86；快照校验新增 schema5 provider 唯一、schema6 provider+accountKey 唯一；重复行进入既有 QUOTA=null / QUOTA_NOTE="quota-axi 快照不合法，降级为注册+禁名单" 分支，不再首行决定工人。新增4条断言（两种 schema × [0,80]/[80,0] 顺序），均断言同一 {status:clear,worker:sol,role:cross_module,default_worker:pi} 与明确降级提示。先测未修复引擎 P2_RED_EXIT=1，四条新增断言全红；修复后 bash .worktrees/jev-validation/run.sh => P2_TARGET_EXIT=0，60 PASS/0 FAIL，输出摘录="PASS  JEV schema5 重复身份降级且与行序无关：[0,80]" / "PASS  JEV schema5 重复身份降级且与行序无关：[80,0]" / "PASS  JEV schema6 重复身份降级且与行序无关：[0,80]" / "PASS  JEV schema6 重复身份降级且与行序无关：[80,0]"，尾部="PASS  JEV 假 server 已退出并回收"。bash bin/qwb-test.sh fast => P2_FAST_EXIT=0，输出尾部=<stdout/stderr 均为空>；git diff --check => exit=0；TEST_TEMP_CLEANUP=PASS。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles/.worktrees/jev-validation/{p2-red,p2-target,p2-fast}.log；dispatch SHA256=c1e79710e0132a6da6d0941ae02709515e79b4639121bdc2cefe7fbe189acb63。未跑 full/真实 key/真实 quota；未改 state: 或他人状态行，未提交/推送/合并。
working: 2026-09-28T13:55:00Z 主控修订六（Rocky 纠正：agent=harness×模型×effort 三元组，路由候选不得只写 harness）：1) workers.sh 升级为 agent 定义表：qwb_worker <名> 'herdr' <harness> -- <argv 固化模型与 effort（CLI 支持到什么写什么）>；harness 显式第三列，旧式无 harness 列的行向后兼容（harness=名）。2) dispatch-rules.json 的 agents 候选一律用 agent 名（三元组具名），不再出现裸 harness 名（devin/omp 等单层 worker 除外——它们本来就只有一层）。3) 引擎 worker_registry 改读显式 harness 列；quota provider=harness、lane 按 harness+model（沿用 firstmate 契约）；model/effort 解析不变。4) 模板 workers.sh 给出具体三元组行示例（codex+gpt-6-sol+high、claude+fable+high、pi+glm、devin、omp+gemini；各家 CLI 的模型/effort 旗标执行者查 --help 核实，effort 无旗标的在定义注释注明由模型默认）。5) 母仓 config.sh/workers.sh/dispatch-rules.json 由主控同步落成三元组形态。6) smoke/optional-routing 断言同步。
working: 2026-09-28T11:18:31Z 执行者收到主控修订六：候选改为 harness×模型×effort 的具名 agent；先核对全部 workers.sh schema 读取/启动点，再实现 herdr 显式第三列 harness + -- argv，并兼容旧行 harness=名；同步 dispatch 注册解析、模板及 smoke/optional-routing。母仓 workers/config/dispatch-rules 三份运行配置由主控落地，本执行者不写。
working: 2026-09-28T11:26:47Z 修订六实现阶段：qwb-run 以 agent 名记账、显式 harness 用于 --kind/复用身份/信任预置；dispatch 用显式 harness 作 quota provider（lane 仍按 harness+model）；模板新增 codex-sol-high/claude-fable-high/pi-glm-high/omp-gemini 并固定 devin=swe-2-high，config 名单同步，旧名字保留兼容；init 同步具名 Claude --add-dir，文档/lessons 已更新。已核实五家 --help 与 Pi/OMP/Devin 模型目录。初始新式 argv 断言 RED_EXIT=1；首轮定向与 optional-routing=0。发现旧契约允许 herdr 位置实参，解析已收窄为仅以 harness 后 -- 识别新式，避免破坏旧 argv；正在跑 worker-config/smoke 回归。
working: 2026-09-28T11:29:26Z 修订六验证阶段：首轮 smoke 完整脚本 SMOKE PASS/exit=0；worker-config 旧式位置实参/空串/迁移回归 exit=0；optional-routing 新增别名启动、harness 信任/复用、同 harness 不同 agent 拒绝复用、五个模板 agent 实际安装参数断言均 PASS（exit=0）。测试扩大覆盖 Pi lane 与 OMP provider=harness 后已冻结修改，进入最终 fast/定向/smoke 验证；未运行真实模型会话。
done: 2026-09-28T11:34:12Z 主控修订六交付：新式 qwb_worker <agent名> herdr <harness> -- <argv> 已实现，旧式（包括位置实参/空串）仍 harness=名；新式分隔符不泄漏进 CLI argv。dispatch 读显式 harness，quota provider=harness、lane 保持 harness+model 绑定；qwb-run --kind/复用身份/信任预置按 harness，路由/dispatch 账本仍按 agent 名；init 给具名 Claude harness 注入 --add-dir 并保持幂等。模板候选=codex-sol-high(gpt-6-sol/high)、claude-fable-high(claude-fable-5/high)、pi-glm-high(zai-coding-cn/glm-5.3/high)、devin(swe-2-high，模型ID含档位)、omp-gemini(google-antigravity/gemini-3.1-pro/high)；config 注册表与 workers 模板同步，旧名只为显式派发兼容保留。同步 smoke/optional-routing、同主题 docs/lessons。本票累计13个变更文件（含之前WIP），新增必要运行时触点 bin/qwb-run.sh、bin/qwb-init.sh 与模板 config/workers 属修订六；qwb-lib 与 key-env/key-fd/JEV请求构造仍与 HEAD 字节一致。检查原始结果：初始新式 argv 断言 R6_RED_EXIT=1；最终 bash .worktrees/jev-validation/run.sh => TARGET_FINAL_EXIT=0、66 PASS（本轮§86新增6条）；bash tests/optional-routing.sh => ROUTING_FINAL_EXIT=0、33 PASS（本轮新增14条，含实际安装的5个具名agent启动参数与Claude目录授权）；python3 tests/worker-config.py => WORKER_CONFIG_EXIT=0、18 PASS；冻结后 bash tests/smoke.sh => SMOKE_FINAL_EXIT=0、755 条 PASS，原始尾部="PASS  JEV 假 server 已退出并回收" / 空行 / "SMOKE PASS"；bash bin/qwb-test.sh fast => FAST_FINAL_EXIT=0，输出尾部=<stdout/stderr均为空>；git diff --check=0。FROZEN_FILES_UNCHANGED=PASS，最终检查前后13文件SHA256一致（/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles/.worktrees/jev-validation/r6-hashes.json）；TEST_TEMP_CLEANUP=PASS，假server均回收，无定向tmp残留。HEAD=090259b15ca18625a9b99f299f405c852528d5f6，工作区dirty未提交。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-jev-agent-roles/.worktrees/jev-validation（r6-red.log、r6-target-final.log、r6-routing-final.log、r6-worker-config.log、r6-smoke-final.log、r6-fast-final.log）。未运行 qwb-test full/真实key JEV/真实模型会话，母仓三份运行配置未写，未提交/推送/合并；以上留主控独立验收和落地。
worktree: merged branch=qwb-jev-agent-roles tag=-
