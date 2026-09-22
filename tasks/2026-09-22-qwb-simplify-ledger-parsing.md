# 任务书：统一账本读取与场景提取

state: verified

任务 id: qwb-simplify-ledger-parsing
优先级: P1
状态说明：现任主控激活；仅本账本副本维护进度。
来源：用户要求将 buddy 精简建议开票，交由现任主控实施。

## 0. 背景与范围

run、wake、status、lint、worktree 多处重复解析 state；run/status 重复判断规格疑点；run/lint 重复提取场景块。目标是保留少量共享的领域函数，让协议只有一个实现来源。

白名单：bin/qwb-lib.sh、bin/qwb-run.sh、bin/qwb-wake.sh、bin/qwb-status.sh、bin/qwb-lint.sh、bin/qwb-worktree.sh，相关 tests/ 定向用例；新增必要共享文件时须同步 bin/qwb-init.sh 的安装和升级覆盖。
仅合并相同语义的纯读取逻辑；调用方特有的警告、退出策略保留。已抽到共享库的 workspace/worker_lost 不再重写。
不改账本格式、状态集合、指纹算法、场景边界和现有读写事务。不同入口对旧票缺基线的不同策略先列出，不能在重构时静默统一。

预期改进：同一张任务书在各入口按同一协议读取，未来调整协议只需修改共享实现；用重构前后差分验证证明兼容，而不只检查函数是否被抽取。

## 1. 验收场景

### user_正常路径_历史账本行为不变
Given 覆盖正常票、无 state 文档、前后空白、连续状态行及带运行时追加行的真实格式夹具
When 分别经 status/lint/派发预检/worktree 查询读取，比较重构前后结果
Then 状态、场景字节和指纹、公开输出及退出码在约定范围内保持一致，纯读取不修改票。

### user_失败路径_疑点和场景仍拦截
Given 存在未处置 spec-defect，或派发后场景被无痕修改，或 state 非法
When 执行相应预检和查询入口
Then 原有拒绝、警告及无副作用语义不变，后续普通 done/working 行不能解除规格疑点。

### user_正常路径_安装副本可用
Given 一个全新临时目标项目和一个既有安装副本
When 分别安装与升级后使用 status/lint 及相关预检
Then 共享函数可加载，用户配置保留，无缺库或 source 时意外执行动作。

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

working: 2026-09-22T13:56:19.910466+00:00 激活②；①实现239c2ce已验收，基线7ddb341b5873d7e70b6671c1420e4a75077e15d0。主控wF2:p3；执行Sol medium/审核Sol high，复用pH/pG。工作目录/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-ledger-parsing，分支qwb-simplify-ledger-parsing，主账本/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-ledger-parsing.md。预存未跟踪docs/plans/保留；无其他在途票。限定bin/qwb-lib.sh、run/wake/status/lint/worktree及相关tests，仅纯读取抽取，保留调用者无fp差异/拒绝策略及一切写事务。三场景指定的公开CLI差分/隔离安装为本票测试边界。
wake: 2026-09-22T13:56:31Z state=running fp=6704764c1e36c58c73dd5ffab21425b86c017436

working: 2026-09-22T13:56:58.207819+00:00 已复用现有Herdr原生交互入口交接②至pH，启动界面核实gpt-5.6-sol medium与正确cwd。逐字调用当前qwb-run场景读取函数冻结真实字节，不伪造qwb-run dispatch事件；源规格未变。
scenarios-fp: 7f40bb691cfbe5aa700f46186099a62397602d6c
wake: 2026-09-22T13:58:32Z state=running fp=b012c6117d44a71a07676e053f372818c7d64ffa

done: 2026-09-22T14:03:26Z ②纯读取提取完成待主控正式审核，未提交未推送。基线7ddb341b5873d7e70b6671c1420e4a75077e15d0；候选仅bin/qwb-lib.sh、bin/qwb-run.sh、bin/qwb-wake.sh、bin/qwb-status.sh、bin/qwb-lint.sh、bin/qwb-worktree.sh；git diff --binary SHA-256=b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2。冻结基线真实脚本对拍9类夹具39组公开CLI比较rc=0，场景字节/fp、stdout/stderr/rc与账本只读均相同；隔离初装升级配置保留、source无输出/选项副作用；bash bin/qwb-test.sh fast rc=0，git diff --check rc=0。证据及各候选文件哈希见docs/reviews/2026-09-22-qwb-simplify-ledger-parsing-execution.md；原始日志/tmp/qwb-ledger-parsing-diff-final.log。未跑full、真实Herdr派发与pane（主控唯一全门）。state/场景/fp/旧记录未改，缺fp策略及规格诊断stderr差异保留。

working: 2026-09-22T14:03:51.283097+00:00 主控冻结六文件候选diff b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2；已交现有pG Sol high独立三审点审核，并启动唯一full，日志/tmp/qwb-simplify-02-full.log。执行者35组差分、fast0仅为当前执行证据，待独立核实与全门回收。
wake: 2026-09-22T14:04:33Z state=running fp=bb3203059ff0760f1dfae26dc2bd2899941b5ef6

working: 2026-09-22T14:06:01.167515+00:00 主控full rc=0，111.614s；/tmp/qwb-simplify-02-full.log 与 .json，执行前后diff b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2完全一致。独立审核尚在收尾，未提前验收。执行者已正常退出，准备通过后收尾。
wake: 2026-09-22T14:06:34Z state=running fp=762773cc48e83b6f5b70e0c865dd6454763da852
working: 2026-09-22T14:07:01.738106+00:00 ②正式独立审核 PASS（Standards 0/Spec 0 阻断）；冻结HEAD 7ddb341b5873d7e70b6671c1420e4a75077e15d0、六路径diff sha256=b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2，候选无新文件。独立重跑9类39组CLI差分rc=0，九种尾部事件边界与缺库诊断rc=0，隔离初装/升级status/lint/run预检及配置保留rc=0；执行证据“五个state入口”应为四个，主账本先前“35组”以实际39组为准。报告docs/reviews/2026-09-22-qwb-simplify-ledger-parsing-r1.md；fast为执行者证据，本审核未跑full/真实Herdr。
worktree: merged branch=qwb-simplify-ledger-parsing tag=-

done: 2026-09-22T14:07:45.169302+00:00 主控验收②完成；实现bb86f960a87d846508f054cf46709bf18fee32fa 已ff进入主线，仅bin/qwb-{lib,run,wake,status,lint,worktree}.sh共六文件+37/-25。独立r1 PASS；准确口径为四个state读取入口、39组公开CLI差分（35为早期记录），另九类尾行边界，初装/升级/配置保留/缺库/source无动作验证通过；报告docs/reviews/2026-09-22-qwb-simplify-ledger-parsing-r1.md。fast0、主控full0 111.614s，/tmp/qwb-simplify-02-full.json及.log，前后diff b4638f75e7efeb71b63c8b62937d67b09f267739d2f7ccb42483766850d390b2一致。未新增真Herdr成功派发/宿主证明；仅本票读取兼容范围。执行者退出，worktree finish --merged实际成功，无push或副本升级。
