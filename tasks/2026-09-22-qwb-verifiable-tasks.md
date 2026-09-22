# 票 02：任务写成可验收的结果

state: verified

- 任务 ID：`2026-09-22-qwb-verifiable-tasks`
- 类型：现有任务模板与角色说明改进，不改运行时。
- 交付状态：交接稿，尚未派发；激活规则见同目录 README。
- 来源：Rocky 确认的三项改进中的“开工前说清楚结果”。
- 核对基线：`main@0eae33bb0625d4df50eada12393885b13b490fa6`；执行前重新核对。
- 前置：票 01 已验收并纳入现任主控指定的下一票基线。

## 0. 背景与范围

现有 TASK 已有 Given/When/Then、正常与失败路径；派发器和 lint 也能识别并冻结场景。本票不重新建设场景系统，只让任务内容能真正回答“如何判断做对了”。

目标：读票的执行者即使没有聊天上下文，也知道该从哪里操作、预期什么结果、如何验证，以及哪些事情不做。

只读依据：`templates/TASK.md`、`templates/roles/主控.md`、`templates/roles/执行者.md`；必要时只读 `bin/qwb-run.sh` 的场景解析和 `bin/qwb-lint.sh` 对应检查，保持兼容。

### 写入白名单

| 文件 | 允许改动 |
|---|---|
| `templates/TASK.md` | 背景／范围提示、验收场景提示、验证入口与一组短示例；不重写后续审核身份机制 |
| `templates/roles/主控.md` | 派发前简短检查：目标可验证、依赖可用、排除项明确；保留票 01 的审核裁定规则 |
| `templates/roles/执行者.md` | 按结果实现；发现验收不可操作或规格冲突时复用 spec-defect，不猜测或擅自改标准 |

另外只允许向本票激活后的主账本追加证据。演示任务写独立临时目录，不向生产 `tasks/` 注入测试票。

## 1. 验收场景

### user_新会话能独立理解任务

Given 使用修订模板填写一张“修改作品标题”的示例任务，接收者未参与此前讨论
When 接收者只读该任务及其明确引用的资料
Then 能指出作者操作入口、允许修改的字段、成功后重新读取结果的步骤、失败时应保留的输入，以及不属于本票的功能。

### user_失败提示不能冒充保存成功

Given 示例任务涉及持久化标题
When 编写成功与失败场景
Then 成功检查“保存后重新打开仍是新标题”，失败检查“请求失败保留输入且不得提示成功”；仅断言按钮或 toast 出现不能作为完成条件。

### user_发现规格缺陷不擅自补功能

Given 任务要求全站搜索，但引用的当前接口只支持列表且无搜索能力
When 执行者核对现有实现
Then 按 spec-defect 说明条款、依据与缺口，交主控裁定；不得偷偷增加接口、只搜索当前页却冒充全站，或自行删掉验收条件。

### user_保留场景冻结与框架兼容

Given 新模板保留现有场景标题、Given/When/Then 与失败路径的约定
When 在隔离样本上使用仓内现有解析规则核对场景块，并核对冻结与修订说明
Then 模板不产生列首伪造状态事件，不要求新增头部字段，不削弱场景冻结；语义是否充分仍由主控判断，不声称现有脚本能理解业务需求。

## 2. 实现要求与硬约束

1. 在现有段落里表达三项内容：**操作入口 / 可观察结果 / 验证方式**。不新增每票必填的大型 spec 或第二份任务表。
2. 具体实现任务写允许改动的路径与排除项；依赖未具备时说明所缺事实，不默认要求 Rocky 回答可直接检查的代码问题。
3. 正常场景和至少一条失败场景保持原约定。失败不能只写“正确处理错误”，要写明可见结果或不得发生的副作用。
4. 模板只保留一组短示例：修改标题后重新读取、保存失败保留输入。说明它是示例，不把 Sites 路由、产品名称或存储结构变成所有项目的硬要求。
5. 用户原话“做一个功能”由主控补充工程验收条件，不要求用户替 agent 写测试步骤。真正产品取舍仍按原规则询问或裁定。
6. 执行者发现规格问题时沿用现有 spec-defect / spec-resolved 和显式修订机制；实现困难本身不等于规格有错。
7. 示例状态行保持缩进，避免被现有账本解析为真实事件。保留 review-required 和现有身份记录格式。
8. 不给每张票增加预审模型，不调用新服务判断任务好坏；格式检查仍由既有脚本完成，内容判断由主控承担。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast --project "$PWD"`。
- 文档检查：`git diff --check`；确认票 01 的改动没有被覆盖。
- 实际试填：选择一张已存在、范围窄的任务需求，用新模板在临时目录生成一份样本；由未参与写样本的已授权接收者检查是否足以独立执行。保存样本及反馈摘录到本票证据，不实际开发或发布产品功能。
- 验收重点是可检查的结果与缺口处理，不以“包含三个关键词”证明质量，不为本票增加新的语义 lint 或 agent benchmark。
- 全门：现任主控按既有资源策略在候选上统一安排 `bash bin/qwb-test.sh full --project "$PWD"`；格式兼容问题应修模板，不准删既有测试。

## 4. 报告要求

向本票主账本追加：基线与提交号、三份模板实际 diff、试填样本、接收者指出的入口／结果／验证方式、失败场景与规格缺陷场景核对结果、检查退出码及未覆盖项。

遵守既有身份记录要求；未完成试填／接收检查就如实标未验证，不写“已经避免需求误解”。

## 5. 不做什么

不修改 `bin/`、`tests/`、`templates/QWBUDDY.md`、质量门、任务状态枚举；不引入 skills 库，不新增产品功能、不重写历史任务、不改当前在途生产修复。出现上级规范实质冲突时返回阻断，由主控处理，不能越白名单顺手修。

working: 2026-09-22T10:49:29.628415+00:00 激活票02；票01实现7c4c3d4已验收，当前基线 eacc8bf791db516cdf38827db7ce535b6320e2e2。工作目录 /Users/rocky/projects/qonnwolfbuddy；主账本 /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-verifiable-tasks.md；现任主控wF2:p3安排原pane新Sol medium执行、新Sol high独立接收审核，未增加模型/窗口。开工前无staged/unstaged，预存未跟踪docs/plans/保留。仅本票激活，票03尚未激活。
scenarios-fp: 91c65c222dd7ad334c74edea9a0d90dbff24f60e
wake: 2026-09-22T10:49:39Z state=running fp=263c3939edf1e9022cfd79d748570464aca2786b
working: 2026-09-22T10:53:09Z 票02未提交候选完成，基线 HEAD=eacc8bf791db516cdf38827db7ce535b6320e2e2，候选无提交号。仅改 templates/TASK.md、templates/roles/主控.md、templates/roles/执行者.md（3 文件 +14/-7）：TASK 在原段落提示入口/依赖、重新读取结果、失败副作用和验证入口，并留一组短示例；主控补派发前可验收与依赖核对；执行者复用 spec-defect/主控裁定。票01审核意见分类段原样保留；未改 state、验收场景或既有 scenarios-fp。
  试填目录：/tmp/qwb-ticket02-samples.qFXWnY。标题票 title-task.md 完整引用 title-contract.md（两者均明确为演示，非真实产品）；入口 /demo/my-works → /demo/works/w-17，允许字段仅 title，成功离开重开并 GET 读新标题，503 时保留“待保存标题”、无成功提示、重开仍是旧标题，排除内容/封面/搜索/权限改动。规格缺陷样本 search-spec-defect.md 引用 search-list-contract.md：全站搜索条款与仅分页列表且无搜索/全量枚举保证的演示接口冲突；缩进的 blocked: spec-defect: 示例交主控裁定，未擅加接口或修订场景。
  核对：bash bin/qwb-test.sh fast --project "$PWD" → rc=0；git diff --check → rc=0；bash bin/qwb-lint.sh --project "$PWD" → LINT PASS rc=0（仅历史票已有警告）；bash bin/qwb-lint.sh --project /tmp/qwb-ticket02-samples.qFXWnY/lint-project → LINT PASS rc=0（隔离副本引用样本，无伪造 scenarios-fp）；bash /tmp/qwb-ticket02-samples.qFXWnY/check-scenarios.sh → rc=0（从 bin/qwb-run.sh 原样提取 scenario_block，标题样本与模板各有 2 个 Given/When/Then 场景且识别失败路径）；模板及样本无列首伪状态事件。第一次用进程替换提取函数的核对 rc=127，已改为先落临时函数文件并重跑成功。
  未覆盖：未参与本轮的新 Sol high 接收检查尚未进行；full 由主控统一安排；演示无真实产品/部署环境，因此未声称产品功能验证。候选保留未提交，等待独立审核和主控后续提交。
wake: 2026-09-22T10:53:40Z state=running fp=0385aa21c8e03e8f6fa265e54bfad48eadb842c8
working: 2026-09-22T10:57:47Z 票02独立接收与未提交候选审核：现有 Herdr pane=wF2:pG，Codex 原生 session=01a0c8bc-2b89-7692-8649-40581ab50745；未开窗口、未派发。基线/HEAD=eacc8bf791db516cdf38827db7ce535b6320e2e2，审核三份模板的工作树最终内容，整体 PASS；Spec 0 个发现，Standards 0 个发现。详细原始证据：/tmp/qwb-ticket02-samples.qFXWnY/receiver-evidence.md（SHA256 a9b2883b250c789434286db0de4ce1142d4eca75653ad6e51d1aa9f999d636a9）。
  第一阶段在读主票、候选 diff、作者反馈及搜索样本前，只读 title-task.md 与操作契约 title-contract.md，并保存 /tmp/qwb-ticket02-samples.qFXWnY/receiver-first.md（SHA256 4630219fd17d16861fbacc0d81dc6c490eb1554923feec9ea71c3b9a03242d1f）。原文摘录：“作者登录后从演示 `/demo/my-works` 打开自己的 `w-17`，进入 `/demo/works/w-17`，在详情点‘编辑标题’”；“只编辑和提交 `title`”；“离开详情再从作品列表进入 `w-17`，新的 GET 应返回‘新标题’”；“编辑框保留‘待保存标题’以便重试，显示失败信息且不显示成功”；并写明内容、封面、作者、搜索、权限、部署排除及真实路径/契约/质量门尚缺。演示协议不冒充真实产品事实。
  第二阶段样本：/tmp/qwb-ticket02-samples.qFXWnY/title-task.md（SHA256 53d5c29df74277eba089215f5ee149b75152938338de5bffaa4586c9f4e777a2）及 title-contract.md（146ec14d34a52cb4b89d870f4ac70a5b5d70e797ef6dd34ea4a8b261369a473b）说明 PATCH 仅 title、成功重新 GET 验持久化、503 保留输入且重进仍旧标题；search-spec-defect.md（324b3e9cc8389f439e97dbe001e0e5c1542beb210bf01ccd377a48580ca97ff7）及 search-list-contract.md（084901e48b205fcb0fec78c12802844228796c412963d37ecd7bd80e82fe3b5b）说明“全站所有公开作品”与仅分页列表、无搜索参数及全量枚举保证之间的缺口，缩进 `blocked: spec-defect:` 报条款/依据/漏后续页后果，交主控 `spec-resolved:` 裁定；未擅加接口、当前页冒充全站或删除验收条件。
  三审点：①可执行性/失败与规格缺口 Spec PASS，首阶段能独立指出入口、字段、复读结果、失败可见行为与排除项；搜索例按契约报告缺口。②冻结及格式/身份兼容 Standards PASS，模板保留 user_、Given/When/Then、失败路径、缩进状态示例、scenarios-fp/显式修订及 review-required 身份格式；用户本轮指定 Sol medium 执行与 Sol high 审核，仅此票例外，不改模板政策。③范围与前票保留 Spec/Standards PASS：候选只改 templates/TASK.md、templates/roles/主控.md、templates/roles/执行者.md（+14/-7）；cached diff 和白名单 untracked 均空；票01主控审核分类段保留，templates/QWBUDDY.md 无 diff，预存 docs/plans/ 保留。原始差异与状态见样本目录 receiver-candidate.diff、receiver-cached.diff、receiver-untracked-whitelist.txt、receiver-status.txt。
  本会话实际命令及 rc：bash /tmp/qwb-ticket02-samples.qFXWnY/check-scenarios.sh → 0（标题样本和模板各 2 个 Given/When/Then 场景且识别失败路径；这是解析检查，不代替语义审核）；bash bin/qwb-test.sh fast --project "$PWD" → 0；bash bin/qwb-lint.sh --project "$PWD" → 0、LINT PASS（仅历史票占位状态行/缺旧指纹警告）；git diff --check → 0。原始日志见 receiver-check-scenarios.log、receiver-fast.log、receiver-lint.log、receiver-diff-check.log。未覆盖：full 由主控统一安排；演示无真实产品/部署环境，未声称产品功能验证。本会话未提交、未改源码。

working: 2026-09-22T10:58:58.751527+00:00 主控验收票02：实现提交 bb9bbb60d228debf9b47d717b93c63221fdf10b3，仅TASK/主控/执行者三份模板；票01规则保留。独立接收首阶段摘录与Spec/Standards PASS已核对；标题样本与搜索规格缺陷样本均满足方法验收。fast=0、解析检查=0、lint=0、diff check=0；主控full=0/106.954s，日志/tmp/qwb-ticket02-full.log与文件hash收据/tmp/qwb-ticket02-full.json。执行session=01a0c8bc-2b74-79f1-a218-b8ddb4fd2e47，审核session=01a0c8bc-2b89-7692-8649-40581ab50745。未开发或验证真实产品功能、未量化长期误解率。state=verified，票03前置成立。
