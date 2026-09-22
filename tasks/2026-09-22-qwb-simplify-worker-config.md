# 任务书：简化工人启动配置

state: verified

任务 id: qwb-simplify-worker-config
优先级: P1
状态说明：现任主控激活；仅本账本副本维护进度。
来源：用户要求将 buddy 精简建议开票，交由现任主控实施。

## 0. 背景与范围

当前 QWB_WORKER_LAUNCH / QWB_WORKER_ARGS 把多个工人配置塞在长字符串里，边界由 QWB_WORKERS 决定，且参数按空格切词。目标：每个工人只有一个启动定义，参数边界明确，不再吞并未知工人名或依靠“同名最后一项生效”。

白名单：templates/config.sh、bin/qwb-run.sh、bin/qwb-init.sh、bin/qwb-lint.sh，必要的 templates/ 工人配置模板及 tests/ 用例，templates/QWBUDDY.md 和对应 README/安装文档。
先比较“一工人一配置文件（Bash 参数数组）”与等价显式结构，选择满足现有支持平台且最少改动的一种；不要引入框架或要求全平台 Bash 4 关联数组。
保留 Herdr 与 pane-run、现有工人种类、禁止 headless 和参数政策，不顺带改权限默认。

迁移要求：旧配置必须可检测；能无歧义迁移的提供显式迁移路径；无法可靠解释的在任何派发副作用前拒绝并指出工人和修复方式。升级不能静默覆盖定制配置，不能长期同时维护两套运行时解析器。若需要拆迁移阶段，主控先明确阶段边界。

预期改进：每个工人的配置边界和最终 argv 可验证，减少串参数与静默吞并；本票兼容性风险最高，若迁移复杂度超过收益，先由主控收窄方案，不能为减少代码行数强行替换格式。

## 1. 验收场景

### user_正常路径_参数边界保真
Given 两个工人分别配置 Herdr 和 pane-run，参数包含空格、空字符串和字面特殊字符
When 经派发入口传给假执行器
Then 工人和参数 argv 与配置逐项一致，不丢边界、不串到另一工人、不执行意外命令替换。

### user_失败路径_配置歧义提前拒绝
Given 未知工人、重复启动定义、两处重复参数或被禁止的 headless 配置
When 请求派发
Then 在创建 worktree/tab、写 dispatch 和启动进程之前报明确错误，不默认吞并或覆盖。

### user_正常路径_旧项目显式迁移
Given 含用户定制的旧配置和可备份的临时安装副本
When 执行显式迁移并再次运行迁移
Then 保留原始配置备份及既有有效启动行为，第二次幂等；正常安装升级不擅自改写定制值。

### user_失败路径_无法可靠迁移
Given 旧配置存在无法无歧义解释的项
When 升级或尝试派发
Then 明确指出待处理项，保持用户数据和原始配置，不猜测成新配置后继续启动。

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

working: 2026-09-22T14:08:14.396702+00:00 激活③；①239c2ce/②bb86f96已验收，基线6bc424c7a19f01d8ce604423f0d8674675fe8ba4。主控wF2:p3；仅复用pH Sol medium执行/pG Sol high审核，不新开窗口。工作目录/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-worker-config，分支qwb-simplify-worker-config；主账本/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-worker-config.md。预存docs/plans/保留，无其他在途票。严格原白名单，先比较每工人Bash数组文件与等价显式结构，选择最小且macOS Bash3兼容方案；明确迁移边界，普通升级保留定制，歧义先拒绝。四场景公开派发/隔离迁移是已授权验证边界，不使用真实计费服务或升级现有项目。
wake: 2026-09-22T14:08:35Z state=running fp=c28ddb4bee79d9ffc4cd74fdbcfc99e6c8b957af

working: 2026-09-22T14:08:56.137707+00:00 已经现有Herdr原生交互入口交接pH，核实Sol medium/正确cwd；沿用②共享的原字节场景提取，真实SHA1冻结，不伪造qwb-run dispatch事件。
scenarios-fp: 83210c8f1232a124710ca7b80320eb58fb2630d4
working: 2026-09-22T16:15:00+02:00 执行比较：每工人一 Bash 数组文件能保 argv，但安装/迁移要管理多个文件且缺失/重名需扫目录；单独 workers.sh 里每工人一条 qwb_worker 声明由 qwb-run 唯一加载，用 Bash 3 索引数组保参数边界，config.sh 仍被 status/wake/lock/test 原样 source，改动更小。选择单文件显式声明；旧长串仅显式迁移读取，run 对旧/歧义配置先拒绝，不长期双解析。迁移只自动处理旧解析能无歧义表达的值；未知名、重复项、无法证明边界者拒绝并保留原件。
wake: 2026-09-22T14:10:35Z state=running fp=72679cc851f0c257807736098bad693a8db8b50f
working: 2026-09-22T14:11:29.536275+00:00 更正：上一条 working 的 16:15:00+02:00 是手填错误时间；实际追加时间以本机器时间为准。方案更新：pane-run 也逐项配置 argv，运行时安全引用生成 herdr pane run 命令字符串。
wake: 2026-09-22T14:12:36Z state=running fp=2ca2c2f269184a2cc5eddc63765aa5c0dfc7ed6b

working: 2026-09-22T14:21:35.125432+00:00 执行者仍在收尾定向测试与旧夹具适配；主控尝试依据中间hash启动前，身份断言发现候选已更新，故full未执行。独立审核已要求等待最终冻结对象，不形成旧hash结论。两路径argv与迁移定向已有执行证据，仍待最终报告、独立复核及全门。
done: 2026-09-22T14:21:50.457396+00:00 ③执行候选冻结，基线/HEAD=6bc424c7a19f01d8ce604423f0d8674675fe8ba4；8个tracked+2个新源文件，保持未提交。公开qwb-run真假执行器 argv 与显式迁移/歧义拒绝定向 python3 tests/worker-config.py rc=0；bash bin/qwb-test.sh fast rc=0；bash -n smoke/runtime-readiness、shellcheck run/init、git diff --check 均rc=0。full及正式审核未跑，交主控。执行证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-worker-config/docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md（sha256=2c1fe345ca3544d50596fa4aaa555cb3b6b4ec36f5632028c046325a6d1f80f1）；tracked diff sha256=0afef30165589b77ffde5069c058937f109d1ebc81939b40e8a7912b5479be68；新文件 templates/workers.sh sha256=5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b、tests/worker-config.py sha256=42a9b430d17da0f03a5d3f05acc957d2f106f8e00aaa4e81ff41b1f3e92874df。
wake: 2026-09-22T14:22:38Z state=running fp=c75c6b9ce8644f44b269854769c7ab0ea62e3e43
done: 2026-09-22T14:23:03.860577+00:00 ③最终候选更新冻结：tests/smoke.sh 第77节直接调用 tests/worker-config.py，沿用 ok/bad；母仓 qwb.config.sh full 包含 smoke。接线后独立定向 rc=0、fast rc=0、smoke bash -n rc=0、git diff --check rc=0；整套 smoke/full 未跑，由主控执行。8个 tracked 文件 diff SHA-256=09f00bd1f0ad07e79504b2e1ec4e9db72f861caca4e9bd044468a2b95eda4a4d；新增 templates/workers.sh SHA-256=5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b，tests/worker-config.py SHA-256=42a9b430d17da0f03a5d3f05acc957d2f106f8e00aaa4e81ff41b1f3e92874df。执行证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-worker-config/docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md SHA-256=c0a713b30d8751ab2ef59732234c1c697009ebf0eb6d1b8e15c357a2cce76bfb；候选保持未提交。

working: 2026-09-22T14:24:35.361650+00:00 已核实最终tracked diff09f00bd1f0ad07e79504b2e1ec4e9db72f861caca4e9bd044468a2b95eda4a4d及workers/test两个新文件hash；正式复审继续，唯一full现已实际启动/tmp/qwb-simplify-03-full.log。执行报告原误放worktree，已原样移至主仓docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md，内容sha256 c0a713b30d8751ab2ef59732234c1c697009ebf0eb6d1b8e15c357a2cce76bfb；旧路径不再作为留存路径。
wake: 2026-09-22T14:24:39Z state=running fp=796af552f6ecc9c73cb78d2f3f7ad70a5b79d4fb

working: 2026-09-22T14:27:37.047938+00:00 首轮full rc=1，114.096s，执行前后候选未变；仅5项FAIL，集中GITP临时项目未带workers.sh，详/tmp/qwb-simplify-03-full.log及.json。独立审核仍核对argv字面~与迁移shell语义；主控实测本机bash printf %q输出裸~，已要求在原审点内验证。执行者仅只读归因，待审核报告后统一返修，不提前改候选。
wake: 2026-09-22T14:28:40Z state=running fp=0d457c5e2d08fe2c5c0b16ae473bf55333fa31a6

working: 2026-09-22T14:29:54+00:00 ③正式独立审核 r1：REVIEW_QWB_SIMPLIFY_WORKER_CONFIG_R1 AMEND；冻结 HEAD 6bc424c7a19f01d8ce604423f0d8674675fe8ba4、tracked diff 09f00bd1f0ad07e79504b2e1ec4e9db72f861caca4e9bd044468a2b95eda4a4d、新文件哈希见审核报告。三个审点：pane-run 字面~公开 argv 被展开；显式迁移接受 {a,b}/# 导致旧 pane-shell argv 改变；GITP 夹具缺 workers.sh 致主控 full rc=1/5 FAIL，普通升级定制 QWB_WORKERS=pi 也不可派发，§51h 唯一性断言变弱。独立 python3 tests/worker-config.py rc=0 但漏反例；本审核未重跑 full、未改候选源码或 state/场景。报告 docs/reviews/2026-09-22-qwb-simplify-worker-config-r1.md sha256=0527c294627c2499cd0e5c8ba79f9018940ac1e4625d8bfed96a80b90c03a580。
wake: 2026-09-22T14:30:41Z state=running fp=7cc9e95ebe26d2f27c86e47be1d56673fd6d0715

working: 2026-09-22T14:30:57.826783+00:00 主控采纳独立r1 AMEND三审点：新argv字面~被展开；旧pane-run的花括号/注释等迁移改变语义；GITP缺workers夹具与定制表升级无对应定义。另默认唯一性断言及dir空值假PASS在同测试范围补强。已交pH统一返修，不改①②或锁/值守机制，不扩自动迁移，不跑并行全门。报告docs/reviews/2026-09-22-qwb-simplify-worker-config-r1.md。
wake: 2026-09-22T14:32:41Z state=running fp=7e8ddfabebc4a409c1600761b282842edc8715b6
done: 2026-09-22T14:39:00.308178+00:00 ③r2定向返修候选冻结：HEAD=6bc424c7a19f01d8ce604423f0d8674675fe8ba4，8 tracked+2新文件未提交；tracked binary diff sha256=4d160b813ce1c3e92394e8e7383c411a315da7502c37766c740b27be093144e0，templates/workers.sh sha256=5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b，tests/worker-config.py sha256=1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954。python3 tests/worker-config.py rc=0（18 PASS）、bash bin/qwb-test.sh fast rc=0、bash -n smoke/runtime/templates、shellcheck run/init、git diff --check 均rc=0。r1主控full rc=1/114.096s 5项GITP保留；r2 full未跑由主控重验。执行证据=/Users/rocky/projects/qonnwolfbuddy/docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md sha256=0a4ef8b725e560a2d73167b0af84c435750793979d38bab12584c3ece61de85f。

working: 2026-09-22T14:40:13.355605+00:00 执行者done并停止写源后启动r2：原10文件tracked diff4d160b813ce1c3e92394e8e7383c411a315da7502c37766c740b27be093144e0，新测试1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954。pG独立复审原3审点；唯一r2 full实际运行，/tmp/qwb-simplify-03-r2-full.log。旧rc1证据保留。
wake: 2026-09-22T14:40:43Z state=running fp=e9d647f81efde4d92f47569f40d1fee78d4b2052

working: 2026-09-22T14:43:06.584559+00:00 r2 full rc=1，124.392s，候选前后未变，/tmp/qwb-simplify-03-r2-full.json及.log。仅余runtime-readiness pane-run提示词失败负例：假Herdr仍按裸mock-agent识别启动，新引用命令使故障误注入启动阶段。真实argv/迁移定向18项已独立通过，仍不算全票完成；等待独立r2报告后只修夹具匹配，保留原回滚断言。

working: 2026-09-22T14:43:27+00:00 ③正式独立审核 r2：REVIEW_QWB_SIMPLIFY_WORKER_CONFIG_R2 AMEND。冻结 HEAD=6bc424c7a19f01d8ce604423f0d8674675fe8ba4、tracked diff=4d160b813ce1c3e92394e8e7383c411a315da7502c37766c740b27be093144e0，两个新文件哈希与交接一致。原审点1公开pane-run含~及内嵌单引号实际argv PASS；审点2旧pane-run花括号/#/~迁移拒绝且原件保留 PASS；审点3仅余tests/runtime-readiness.sh:132,138裸mock-agent匹配未适配新启动文本'mock-agent'，假Herdr在启动阶段误报提示词注入失败，原not-sent负例未测到。独立python3 tests/worker-config.py rc=0/18 PASS；独立bash tests/runtime-readiness.sh rc=1/17 PASS 1 FAIL；主控唯一r2 full rc=1/124.392s、候选未变、smoke汇总1 FAIL同因，本审核未重跑full。返修限该夹具两处匹配并保留原断言，随后runtime定向与同候选full复验。报告 docs/reviews/2026-09-22-qwb-simplify-worker-config-r2.md sha256=1909e115a877d87772d64183bb2b1a50cd126799d04d0e277182b8c7b439df09；未改候选源码或state/场景。
wake: 2026-09-22T14:44:45Z state=running fp=42155fb2d73a2663eb7bd446feed0614e5814a88
done: 2026-09-22T14:44:55.748904+00:00 ③r3夹具定向返修候选冻结：仅 tests/runtime-readiness.sh 两处假Herdr启动文本匹配改为单引号mock-agent，保留state/scenarios-fp/dispatch和not-sent/tab close断言。原r2定向17PASS1FAIL；本轮 bash tests/runtime-readiness.sh rc=0/18PASS，fast rc=0，git diff --check rc=0，未跑full。HEAD=6bc424c7a19f01d8ce604423f0d8674675fe8ba4，8 tracked diff sha256=eb74a9a225f476cef6d09a830b0833b2dadbb72e761f3151ba90c262a9f44f5b；新 templates/workers.sh sha256=5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b、tests/worker-config.py sha256=1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954 未变；主仓执行证据=/Users/rocky/projects/qonnwolfbuddy/docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md sha256=395a3165ef11551dcebfe666e6d8b98702ab93f0c51457e0dac840b03ec65fea。保持未提交。

working: 2026-09-22T14:45:50.437797+00:00 r3定向18PASS/rc0，仅runtime-readiness两处启动匹配改动，主控已核实最终tracked diff eb74a9a225f476cef6d09a830b0833b2dadbb72e761f3151ba90c262a9f44f5b、新文件哈希不变；独立单点复审与唯一r3 full已启动，日志/tmp/qwb-simplify-03-r3-full.log。
wake: 2026-09-22T14:46:46Z state=running fp=e91cb11a52580bb68da249abcfd7ea42ecb72afa

working: 2026-09-22T14:46:55+00:00 ③正式独立审核 r3：REVIEW_QWB_SIMPLIFY_WORKER_CONFIG_R3 PASS（仅r2审点3的夹具残项）。冻结 HEAD=6bc424c7a19f01d8ce604423f0d8674675fe8ba4、tracked diff=eb74a9a225f476cef6d09a830b0833b2dadbb72e761f3151ba90c262a9f44f5b，新workers/test哈希与r2一致。对照r2留存仅tests/runtime-readiness.sh:132,138把裸mock-agent比较改为单引号启动文本；state/scenarios-fp/dispatch前置门及agent rename、提示词pane run、not-sent、tab close断言均保留。独立bash tests/runtime-readiness.sh rc=0/18 PASS（r2为17 PASS/1 FAIL），bash -n与git diff --check均rc=0；原argv/迁移闭环不重审，未跑full、未改候选源码或state/场景。主控唯一r3 full正在运行，审核PASS不代替其收据。报告 docs/reviews/2026-09-22-qwb-simplify-worker-config-r3.md sha256=177877c56cdcde675731f56626a6665c3a2254553c648edc86d99b8420380a5a。
wake: 2026-09-22T14:48:47Z state=running fp=2ea79e8994a5d60d19a58d7aff6b4f5268815480
worktree: merged branch=qwb-simplify-worker-config tag=-

done: 2026-09-22T14:49:28.694808+00:00 主控验收③完成；实现f649a2d023e7235c44e458e6a528c723942fb42a已ff进入主线。10文件+584/-139，明确workers.sh逐参数定义/显式保守迁移及测试；实际diff /tmp/qwb-simplify-03-implementation.diff。独立r1→r2→r3所有AMEND闭环，最终PASS报告docs/reviews/2026-09-22-qwb-simplify-worker-config-r3.md；定向worker-config18PASS、runtime18PASS、fast0；最终主控full0 174.067s，/tmp/qwb-simplify-03-r3-full.json及.log，前后候选身份一致。此前full1/5FAIL和full1/1FAIL均原样保留，不算绿。四场景证据见execution报告；仅假Herdr+真实假执行器进程，未新增真实多CLI宿主验收，复杂旧shell配置需人工处理；无自动升级现有项目或全局配置，无push发布。执行者退出、worktree finish --merged成功并记账。
