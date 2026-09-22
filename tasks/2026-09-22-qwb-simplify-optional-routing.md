# 任务书：将 JEV 自动选工人隔离为可选步骤

state: verified

任务 id: qwb-simplify-optional-routing
优先级: P2
状态说明：现任主控激活；仅本账本副本维护进度。
来源：用户要求将 buddy 精简建议开票，交由现任主控实施。

## 0. 背景与范围

当前 qwb-dispatch.sh 输出展示文本，qwb-run.sh 再用 sed 提取 status/worker/reason。目标是让确定工人的派发路径不依赖 JEV，并让自动选择经明确的结构化契约接入。
本票不授权删除 JEV 或取消现有 --worker auto 的可用性；缺少成本收益数据不能推断其无价值。可保留薄兼容入口，由它先调用可选路由，再进入共用的显式工人派发逻辑。

白名单：bin/qwb-dispatch.sh、bin/qwb-run.sh、templates/dispatch-rules.json、必要的安装/配置说明和相关 tests/ 用例。
保留 clear/off/error/ambiguous 及已定义的默认回退；损坏规则配置仍失败关闭。机器输出不夹日志，说明写 stderr 或单独展示模式；不要引入另一个网络服务。
不读取或打印真实凭据，不用真实计费 API 验收；使用假 HTTP/进程响应。

预期改进：展示文字不再充当机器接口，显式工人派发与自动选工人分别验证。当前问题是接口耦合，不预先断言显式派发已经调用 JEV；回归用调用计数证明显式路径的 JEV 调用为零。

## 1. 验收场景

### user_正常路径_显式工人无需路由
Given 已明确 worker，JEV 无凭据或服务不可用
When 派发该工人
Then 不调用 JEV，不读取路由专用凭据，不受路由服务状态影响。

### user_正常路径_自动路由结构化
Given JEV 返回 clear 或 off/error/ambiguous 的受支持响应
When 使用 --worker auto
Then 通过结构化数据选择工人或执行原有默认回退，诊断文本变化不改变选择结果。

### user_失败路径_损坏规则和非法工人
Given 规则文件损坏、结构化输出不合法或结果指向未配置工人
When 自动路由进入派发预检
Then 按明确且有测试的失败分类处理；坏规则和非法工人拒绝派发，无 worktree/tab/账本副作用，不泄露凭据。

## 2. 硬约束

- 本文件是待激活任务书，不含 state 字段，不参与值守；激活、账本路径和执行顺序见 README.md。
- 以主控确认的最新已验收基线为准；先核对本票问题是否仍存在，已解决的部分引用实际提交和证据，不重复重写。
- 保留主控互斥、工人丢失检测、单实例值守、唤醒去重、规格疑点门、场景冻结与显式修订、独立验收和 worktree 安全收尾。
- 不新增主控、服务、数据库或第二套账本，不安装 pstack；不改其他项目、全局 CLI 配置、模型家族或权限政策。
- 共享文件串行修改；保留生产修复和已有三项流程改进的成果，不以旧模板覆盖。
- 不追求行数下降指标，不以放宽断言、删负例或增加重试掩盖退化。

## 3. 验收门

- 执行者：运行本票定向验证及 `bash bin/qwb-test.sh fast`，记录实际命令、源码版本、退出码和未覆盖项。
- 主控：对实际整合候选运行 `bash bin/qwb-test.sh full`；同版本、同命令、同环境的可信收据可复用，禁止各工人并发跑全门。
- 文档票以实际走读、试填和入口可发现性为主要证据，不能用纯关键词匹配代替；涉及行为变化时补行为验证。
- 宿主假件通过不等于真实 Claude/Pi/Codex/Herdr 验收；未实测的组合须明确记录，不伪报全支持。

## 4. 报告要求

向激活后的主账本追加真实 working / done / blocked / needs-decision 状态行；本交接文件不维护进度。
报告问题是否仍存在、实际修改路径、提交号、运行证据、保留行为、未覆盖项。
发现票本身有缺陷，按既有 spec-defect / spec-resolved 协议处置；不自行放宽场景或伪造身份、指纹、派发和 PASS。
执行者不改 state；审核、提交、合入由现任主控按用户当次授权安排。

working: 2026-09-22T14:49:52.038930+00:00 激活④；①239c2ce/②bb86f96/③f649a2d已验收，基线e74a7edaa62303a49c99c272ca2e6fd26436659b。主控wF2:p3；复用pH Sol medium执行/pG Sol high审核，不新窗口。工作目录/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-optional-routing，分支qwb-simplify-optional-routing，主账本/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-optional-routing.md。预存docs/plans/保留，无其他在途票。原白名单bin/qwb-dispatch.sh/run.sh、dispatch-rules模板、必要安装/配置说明及相关tests；保留JEV与auto，只移除展示文本机器解析耦合。三个场景以假HTTP/假Herdr公开CLI为验证边界，不读取真实凭据不访问计费API；不改模型/唤醒/锁/worktree管理。

working: 2026-09-22T14:50:27.123550+00:00 已核实原pH的新Sol medium会话与正确cwd，经现有Herdr原生交互入口交接；使用现有共享场景读取函数冻结实际字节，不伪造qwb-run dispatch行。
scenarios-fp: e17508ed3a8256c2e1edaa6af4dcb03b6ce06a2f
wake: 2026-09-22T14:50:47Z state=running fp=c594e7cb69fa42b34686efaf8d71bf5502171682
done: 2026-09-22T14:56:00Z ④执行者完成未提交候选；基线e74a7edaa62303a49c99c272ca2e6fd26436659b，tracked diff=bin/qwb-dispatch.sh/bin/qwb-run.sh/templates/QWBUDDY.md/tests/smoke.sh，新文件tests/optional-routing.sh sha256=494679707d11d5d64eba294b0618bce187552373f89296de1754741e6b0be25a；定向bash tests/optional-routing.sh exit0、bash bin/qwb-test.sh fast exit0、bash tests/boundary-readiness.sh exit0/BOUNDARY PASS、shellcheck/bash -n/git diff --check exit0；初始red exit2；假HTTP/假Herdr/隔离HOME，无真API；full与真实宿主未跑，留主控。报告=/Users/rocky/projects/qonnwolfbuddy/docs/reviews/2026-09-22-qwb-simplify-optional-routing-execution.md
wake: 2026-09-22T14:56:50Z state=running fp=3f0466fdcd53c68d9c6ebe1a2566a06748f8bcdb

working: 2026-09-22T14:58:40.924967+00:00 执行者done后主控核实tracked diff03a5fd04f0c7c612457858cfad71558db084d07512c10e2503711fabf593f0f3，新tests/optional-routing.sh 494679707d11d5d64eba294b0618bce187552373f89296de1754741e6b0be25a；现有pG Sol high session01a0c998-c456-75e2-bceb-8d99cb75b829已working独立审核，唯一full实际启动/tmp/qwb-simplify-04-full.log。未提前提交/验收。
wake: 2026-09-22T14:58:50Z state=running fp=f448265eca8786106d12bdf30037a243c80ab0df

working: 2026-09-22T15:01:06.461796+00:00 初轮full0 120.151s，/tmp/qwb-simplify-04-full.json及.log，候选前后未变；独立r1 AMEND仅空规则/多JSON规则未按配置错误拒绝。主控采纳并仅交dispatch规则单对象校验与对应定向负例返修。旧full0保留，不作为新候选验收。
working: 2026-09-22T15:01:11.020258+00:00 ④正式独立审核r1 AMEND；报告=docs/reviews/2026-09-22-qwb-simplify-optional-routing-r1.md sha256=68d17f52599de72f074c3be5d34781b217e3a16259e2d3e73904155aca72b4b1；候选HEAD=e74a7edaa62303a49c99c272ca2e6fd26436659b tracked-diff=03a5fd04f0c7c612457858cfad71558db084d07512c10e2503711fabf593f0f3 新tests/optional-routing.sh=494679707d11d5d64eba294b0618bce187552373f89296de1754741e6b0be25a；本轮仅1项新问题：空/多对象规则无key时qwb-dispatch --json错误exit0 off（空文件输出default_worker空，多对象输出含换行）；定向15 PASS、fast exit0、隔离复现两例均exit0；未跑full/真实Herdr/真实API，未改候选源码。
done: 2026-09-22T15:02:47Z ④r2返修独立审核r1唯一AMEND：规则快照先验恰好一个顶层JSON对象，空文件/双对象无key时direct CLI exit2且零curl，上层exit2且任务书字节不变/零Herdr/零worktree；red定向exit1（empty直调实际exit0），green定向19 PASS exit0，fast exit0，shellcheck/bash-n/git diff --check exit0；HEAD=e74a7edaa62303a49c99c272ca2e6fd26436659b，最终tracked-diff-sha256=346b86073418cb4afb8a6f5d60dda3e95836988752990fbc32037c56e1c70864，新tests/optional-routing.sh-sha256=e3656f8a5c7bd789f4752c4d3995ad3190110fdae6a83a2656322290d8743463；初轮full0/120.151s只属r1旧候选，r2未跑full；报告追加r2=/Users/rocky/projects/qonnwolfbuddy/docs/reviews/2026-09-22-qwb-simplify-optional-routing-execution.md；未提交未push。
wake: 2026-09-22T15:02:52Z state=running fp=8c21b922d2de89223cbef7ae7aadc54ef6570bbf

working: 2026-09-22T15:04:09.779220+00:00 r2最终tracked diff346b86073418cb4afb8a6f5d60dda3e95836988752990fbc32037c56e1c70864、新测试e3656f8a5c7bd789f4752c4d3995ad3190110fdae6a83a2656322290d8743463已核实；pG独立单点复审及唯一r2 full运行中，/tmp/qwb-simplify-04-r2-full.log；执行者已退出停止写源。
wake: 2026-09-22T15:04:52Z state=running fp=91d2932eaf3088632295700574c6ff8f2d3aafcc
working: 2026-09-22T15:04:56.388530+00:00 ④正式独立审核r2 PASS（仅r1唯一AMEND返修）；报告=docs/reviews/2026-09-22-qwb-simplify-optional-routing-r2.md sha256=43d2346bd788db25bb6df29da013b0fea344ee48cdf6f6853478a5a23107ac84；候选HEAD=e74a7edaa62303a49c99c272ca2e6fd26436659b tracked-diff=346b86073418cb4afb8a6f5d60dda3e95836988752990fbc32037c56e1c70864 新tests/optional-routing.sh=e3656f8a5c7bd789f4752c4d3995ad3190110fdae6a83a2656322290d8743463；独立定向19 PASS exit0，空/双对象无key隔离复现direct exit2且stdout空，合法单对象exit0 off；shellcheck/bash-n/git diff --check exit0；未跑fast/full/真实Herdr/真实API，执行者fast0仅转引，主控r2 full未计入；未改候选源码未提交。
wake: 2026-09-22T15:06:53Z state=running fp=005ca01fcd9df62714d7dfa666c6e40e655727a7
worktree: merged branch=qwb-simplify-optional-routing tag=-

done: 2026-09-22T15:07:20.729919+00:00 主控验收④完成；实现5104dfde94fe8be04c5973a2c66f55dc788e9b7f已ff进入主线；仅bin/qwb-dispatch.sh/run.sh、templates/QWBUDDY.md、tests/smoke.sh/optional-routing.sh。独立r2 PASS，定向19PASS、fast0、boundary0；最终full0 123.370s，/tmp/qwb-simplify-04-r2-full.json及.log，前后tracked/new文件hash一致。实际diff /tmp/qwb-simplify-04-implementation.diff；三场景含显式dispatch/env-read/curl全0且auto正控、四态与快照回退、无key坏规则与非法结构/worker零派发副作用均通过。未用真实key/API/Herdr，假件不证明真实计费或宿主；已退出执行会话并实际finish --merged收尾，无push部署或其他项目升级。
