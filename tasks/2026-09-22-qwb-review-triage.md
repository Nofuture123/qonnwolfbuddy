# 票 01：审核先裁定，减少无效返工

state: verified

- 任务 ID：`2026-09-22-qwb-review-triage`
- 类型：现有流程与角色模板改进，不改运行时。
- 交付状态：交接稿，尚未派发；激活规则见同目录 README。
- 来源：Rocky 确认的三项改进中的“审核分清问题轻重”。
- 核对基线：`main@0eae33bb0625d4df50eada12393885b13b490fa6`；执行前重新核对。
- 前置：在途生产修复收尾，现任主控确认可用基线及当前权限。

## 0. 背景与范围

当前审核者模板已要求区分“必须补”和“可以不要”，但没有明确意见分类、主控裁定与返修范围；其“禁止提方案”也容易让执行者只收到问题、缺少修复方向。

目标：真错误不能放过，个人偏好不能阻断交付；主控不再把所有审核意见原样转发。

只读依据：`templates/roles/审核者.md` 第 7–27 行、`templates/roles/主控.md`、`templates/QWBUDDY.md` 第 5 节。行号以编写基线为准。

### 写入白名单

| 文件 | 允许改动 |
|---|---|
| `templates/roles/审核者.md` | 意见分类、证据要求、首轮与返修轮范围、最小修复方向的边界 |
| `templates/roles/主控.md` | 审核意见的核对与返修清单职责；引用审核者规则，不复制整套内容 |
| `templates/QWBUDDY.md` | 仅第 5 节验货门，衔接审核分类、争议处理与原有验收流程 |

另外只允许向本票激活后的主账本追加进度与验收记录。试审夹具放独立临时目录，不修改任何真实产品源码。

## 1. 验收场景

### user_真实错误与个人偏好分开

Given 一个隔离小改动同时存在“保存失败仍显示成功”的真实错误，和“不喜欢该函数命名”的偏好意见
When 已授权审核者按新模板审查，主控形成返修清单
Then 保存失败却报成功的错误列入“必须修复”，命名偏好不构成阻断；记录包含问题位置、触发条件、用户影响和可核验依据。

### user_有依据地驳回不成立意见

Given 审核意见声称缺少权限检查，但可定位到实际调用路径中的既有有效校验
When 主控与审核者核对调用路径
Then 将该意见标为“不成立”并记录依据，不为迎合意见增加重复实现；证据不能证明安全时不得直接驳回。

### user_返修后不重新制造偏好任务

Given 首轮已列出的必须修复项已修改，新 diff 未引入其他真实问题
When 审核者复审原问题和新增 diff
Then 对原问题逐项闭环，不以未违反约定的新命名或结构偏好延迟交付；若出现新的真实缺陷，仍如实列出并处理。

### user_争议不能静默放行

Given 主控和审核者对一条正确性或安全问题仍有实质分歧，或现有证据不足
When 准备放行任务
Then 保持未通过，复用现有疑点处置流程；不得为减少返工轮数强制 PASS，不新增新的顶层任务状态。

## 2. 实现要求与硬约束

1. 审核意见使用三类：**必须修复 / 可选建议 / 不成立**。有待调查的争议保留为未决，不冒充任何结论。
2. 必须修复项给出位置、触发条件、影响和验证依据。动态复现、有效测试和充分静态证据均可；推断必须标明，不强制每个问题制作复杂复现。
3. 首轮在约定范围内完成相关风险检查。可优先汇报前三个重点，但不得故意隐藏其余已发现的阻断项、留到下一轮。
4. 返修轮检查原问题、新增 diff 和必要直接依赖；不默认重审全仓，不承诺一次审核穷尽所有未知缺陷。
5. 主控负责核对事实、去除重复、提出有依据的裁定，不得自行豁免已成立的安全或契约缺陷。真实产品取舍按原授权升级。
6. 审核者可以说明最小修复方向和复验要求；不得改被审代码，不顺带新增功能、不接管实现。
7. 不以模型多数票代替证据，不增加默认审核人数、窗口或额外模型调用。
8. 新规则以一处定义、其他文件引用为主，不堆成长篇重复检查清单。保留现有模型家族、会话身份、权限与场景冻结规则。

## 3. 验收门

- 快门：在本票实际工作目录执行 `bash bin/qwb-test.sh fast --project "$PWD"`。
- 文档检查：`git diff --check`；核对实际 diff 仅含白名单及自己的任务记录。
- 方法验证：用一个隔离小改动与至少一条不成立意见做一次试审，记录“原意见 / 分类 / 依据 / 最终返修要求”。复用现有授权审核者，不为了试审额外扩大编排。
- 本票交付证明规则可执行，不宣称已量化提升长期效率；未做实际试审时不得用关键词检查冒充。
- 全门：主控在可合入候选上按既有策略安排 `bash bin/qwb-test.sh full --project "$PWD"`，不与同机 CI 重复争抢资源。

## 4. 报告要求

向本票主账本追加：实际基线和提交号、改动文件、快门退出码、试审原始结果与最终分类、未覆盖项。证据绑定候选源码；截图／转储不含凭据。

实现者报告完成不等于验收通过；由现任主控依据实际审核和验收结果改写账本状态。修改冻结场景仍走既有显式修订，不自行改票消除失败。

## 5. 不做什么

不修改任何 `bin/`、`tests/`、模型／权限配置、安装器或在途修复票；不安装 pstack，不新增审核框架；不替主控推送、部署、清理他人工作树。需要超白名单修改时返回原因，不能自行扩大。

working: 2026-09-22T10:42:32.939781+00:00 激活票01；主控为现有 wF2:p3 会话；执行 GPT Sol medium，审核 GPT Sol high（用户今日授权）。工作目录 /Users/rocky/projects/qonnwolfbuddy，实际基线 7ee4fe4a22386c02fe595b4142c0ffd93dea283b；主账本 /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-review-triage.md。开工前 staged/unstaged 均空；预存未跟踪 docs/plans/ 为交接来源，保留且不纳入实现提交。票02/03未激活。
scenarios-fp: c5de20c54dd8f4335d6e3578ffdaa2c20e3bbb66

wake: 2026-09-22T10:43:36Z state=running fp=07de92789de6896a714a6e4dfda54473e39c4e8e
working: 2026-09-22 票01未提交候选已备；基线 HEAD 7ee4fe4a22386c02fe595b4142c0ffd93dea283b，改动仅 templates/roles/审核者.md、templates/roles/主控.md、templates/QWBUDDY.md §5；无提交号。`bash bin/qwb-test.sh fast --project "$PWD"` rc=0；`git diff --check` rc=0。独立临时夹具 `/tmp/qwb-ticket01-trial.bDbhXD`，运行 `cd /tmp/qwb-ticket01-trial.bDbhXD && node run.mjs` rc=0；原始输出：`original/storage-failure: {"message":"Saved successfully"}`；`original/viewer: forbidden`；`fixed/storage-failure: {"message":"Save failed","error":"storage unavailable"}`；`disputed/foreign-editor: {"message":"Saved successfully"}`；`disputed/contract: owner-only rule unspecified; classification pending evidence`。夹具还列有命名偏好与“缺权限校验”意见供核对；上述仅为执行者自测，正式试审及原意见/分类/依据/最终返修要求待原授权独立审核者和主控记录。未跑 full，未提交、推送或部署；预存未跟踪 docs/plans/ 保留。
wake: 2026-09-22T10:45:37Z state=running fp=f4dca8e2c6469173b6ec1617c1dec5038d76616e
working: 2026-09-22T10:47:49Z 票01独立审核者 GPT Sol high；实际 Herdr pane wF2:pG、session 01a0c8b5-ceb9-7700-9ad6-c1d478a3c9f4；固定基线/HEAD 7ee4fe4a22386c02fe595b4142c0ffd93dea283b，审核模式为未提交最终内容，无候选提交号。Spec PASS；Standards PASS；模板候选整体 PASS。主控另行核对并裁定，审核者未改被审代码、未提交。
working: 审核范围：git diff BASE -- templates/roles/审核者.md templates/roles/主控.md templates/QWBUDDY.md 仅三文件，QWBUDDY.md 仅 §5 第91行；git diff --cached 白名单为空，git diff 未暂存为上述三文件，白名单内无 untracked；主账本为本票未跟踪文件，预存 docs/plans/ 未跟踪且未触碰。候选 diff SHA256 bdf25bf02cac9285d5a1b3815a7bfc1fa089598029759209fa901ff049ef6dd1。文件 SHA256：审核者.md 74d0ff5cb4e183b9d5a81979c951a0f991313b09fe89f85a9236ab56c462595a；主控.md fb3e538cd1703ca067834627599b7e83b269024a2fa69c1b60477bc2eabf33d6；QWBUDDY.md 0c445bd1dd9c4604e7bd16a83ef09d110bceda359a916795afa9af71b2b04658。
working: Standards依据：templates/roles/审核者.md:9-15 一处定义三类意见、未决和复审范围；templates/roles/主控.md:9 与 templates/QWBUDDY.md:91 引用并衔接裁定，无长清单复制。审核者.md:3,25 模型家族，QWBUDDY.md:86 权限、:127-130 会话身份、:95-101 疑点/场景冻结均未改。Spec依据：票要求三类、证据、首轮/返修轮、主控裁定、最小修复方向、争议不放行均可在上述新增行定位；无阻断发现。
working: 独立试审命令：在 /tmp/qwb-ticket01-trial.bDbhXD 先读 README.md 与 run.mjs/original.mjs/fixed.mjs/auth.mjs/disputed.mjs；node run.mjs rc=0（Node v26.8.1），输出 original/storage-failure: {"message":"Saved successfully"}；original/viewer: forbidden；fixed/storage-failure: {"message":"Save failed","error":"storage unavailable"}；disputed/foreign-editor: {"message":"Saved successfully"}；disputed/contract: owner-only rule unspecified; classification pending evidence。run.mjs 是输出夹具而非断言测试，分类由审核者核对调用路径得出。README.md SHA256 acb6d592c3d468ec66aa989cc54eb7848033bb6ac96063624ba9dfa739811ea1；run.mjs SHA256 38550783fd901f3f58896e71194b856d0916b13e901abd396069b107f4d49921。
working: 试审原意见1「store.write 拒绝后仍报保存成功」→ 必须修复。位置 original.mjs:5-10；触发为有 edit:notes 的用户遇到 write 抛错；用户被告知已保存但数据未落盘；run.mjs 输出与 catch 吞错的静态路径相符。最终返修要求：失败路径返回失败或传播错误，并复验拒绝写入不再显示成功。fixed.mjs:5-10 已返回 Save failed，原问题闭环；不新增偏好返修项。
working: 试审原意见2「saveNote 应改名 persistNote」→ 可选建议。位置 original.mjs:3 / fixed.mjs:3；仅名称偏好，README.md:3 明确未给命名约定，未见错误触发或用户影响；最终返修要求：无，不阻断，fixed 复审不重新制造命名任务。
working: 试审原意见3「original.mjs 没有权限检查」→ 不成立。位置 original.mjs:1,4 → auth.mjs:1-3 的真实调用路径；无 edit:notes 的 viewer 被抛 forbidden，run.mjs 输出可核；重复加校验没有相应缺陷依据。最终返修要求：无，记录调用路径反证；此反证仅覆盖 edit:notes 权限，不代替异主所有权契约。
working: 试审原意见4「disputed.mjs 应禁止异主 editor 修改」→ 未决，不通过该争议场景。位置 disputed.mjs:1-8；foreign editor 有 edit:notes、ownerId 不同，实际返回 Saved successfully，若产品要求 owner-only 将越权；但 README.md:3 和代码均未给所有权契约，现有证据不能判定必须修复，也不能判为不成立。最终返修要求：先取得有权威的所有权规则/验收场景并复核调用路径；若要求 owner-only，则补相应限制与拒绝复验；证据未补足前不得放行。主控按现有疑点流程裁定，不由审核者替代产品决定。
working: 独立验证：bash bin/qwb-test.sh fast --project "$PWD" rc=0；git diff --check rc=0；node run.mjs rc=0。未跑 full（留给主控合入候选全门）；未覆盖长期效率量化、真实产品所有权规则与主控最终裁定。模板 Spec PASS / Standards PASS / 整体 PASS；试审 disputed 场景保持未通过直到证据齐备。

working: 2026-09-22T10:48:58.038415+00:00 主控验收票01：提交 7c4c3d4986215162b94b315ebd497b90cfdb70c2，仅三份模板（QWBUDDY限§5）。Spec/Standards独立PASS；主控逐条采纳试审分类：保存失败误报必须修且fixed已闭环、命名可选、缺权限意见有调用路径反证不成立、所有权争议保持未决不得放行该样本，不增加产品规则。实际fast=0，full=0/160.819s（/tmp/qwb-ticket01-full.log；候选文件hash见/tmp/qwb-ticket01-full.json），diff check=0。执行session=01a0c8b5-ceb0-7d83-8032-0bdcd5ca2af9；审核session=01a0c8b5-ceb9-7700-9ad6-c1d478a3c9f4，沿用用户今日同家族授权，未改模板政策。未覆盖长期效率量化/真实产品所有权契约；票01证明流程可执行，不宣称这些已验证。state=verified，票02前置成立。
