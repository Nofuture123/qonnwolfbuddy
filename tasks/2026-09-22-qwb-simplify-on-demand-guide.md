# 任务书：缩短主控必读说明，按需加载专项规则

state: verified

任务 id: qwb-simplify-on-demand-guide
优先级: P2
状态说明：现任主控激活；仅本账本副本维护进度。
来源：用户要求将 buddy 精简建议开票，交由现任主控实施。

## 0. 背景与范围

目标：总说明书只承载主控必须知道的协议与入口，把 CI 优化、宿主配置细节、特殊工人启动和故障排查移到按需文档。
白名单：templates/QWBUDDY.md、templates/ 下少量专项文档、templates/roles/主控.md 及安装注入入口；bin/qwb-init.sh 仅允许为新增文档提供安全安装/升级；相关文档验证。
四个角色文件当前合计约 88 行，不以减少角色数为目标；不引入完整 pstack 或新增技能系统。

必读必须保留：主控锁、任务唯一事实来源、状态写权限、选择值守的入口、验收责任、恢复入口及明确禁止事项。专项规则移走后必须从触发点可发现，不能仅缩短文字却丢失约束。
继承已有 three-improvements 交接包实施后的审核裁定、任务可验收、验收报告规则；本票最后执行，不能将其覆盖。

预期改进：减少每次开局必读内容，同时保证专项规则在任务触发时可发现。唤醒专项说明必须点名 buddy 自带 qwb-watch.ts 及安装路径，并写出 Codex 前台阻塞值守命令，避免仅用“扩展/checkpoint”简称造成误解。

## 1. 验收场景

### user_正常路径_普通任务完整接手
Given 一个只读取总说明书并按其中链接行动的新主控
When 接手普通编码任务
Then 能找到锁、点名、派工、验收和收尾入口，不需预先通读 CI 专项细则，责任和禁止事项完整。

### user_正常路径_专项触发可发现
Given 主控需要修改 CI、排查唤醒或配置特殊启动参数
When 从总说明书对应触发条件进入专项文档
Then 能找到迁移前的有效要求与命令，专项文档存在且安装副本可读。

### user_失败路径_链接或安装缺失
Given 某专项文件缺失、路径错误或旧安装副本未更新
When 验证文档入口及安装升级结果
Then 检查明确失败或报告缺失，不能宣称交接完整，也不能把关键禁止事项随链接一起丢失。

### user_正常路径_缩短且不退化
Given 优化前后的主控必读集合及已有三项流程改进成果
When 比较必读内容并用普通任务、CI 任务各走读一次
Then 必读字数和重复条款减少，专项查找路径明确，既有职责及改进成果完整保留；报告实测字数而不杜撰 token 节省。

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

working: 2026-09-22T15:07:52.350250+00:00 激活⑤；①239c2ce/②bb86f96/③f649a2d/④5104dfd已验收，基线8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05。主控wF2:p3；仅复用pH Sol medium执行/pG Sol high审核。工作目录/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide，分支qwb-simplify-on-demand-guide，主账本/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-on-demand-guide.md；预存docs/plans/保留，无其他在途票。原白名单templates/QWBUDDY.md、少量专项模板、roles/主控.md/注入入口；bin/qwb-init.sh仅新文档安全安装，相关docs验证tests可改。旧票四角色计数为历史，当前Gardening使五角色必须保留；①三宿主先识别后取锁、Codex0不得等同空账本、③workers.sh/显式迁移、④JSON路由均以新基线为准。四场景用安装副本走读及缺文件/链接负例，字数实测；不另建门/账本/模型，不改唤醒锁派发实现或升级真实安装副本。

working: 2026-09-22T15:08:33.861053+00:00 已复用原pH的Sol medium新会话并核实cwd，经现有Herdr原生交互入口交接⑤；共享读取函数冻结场景真实字节，不伪造qwb-run dispatch事件。独立审核pG准备新会话从安装入口接手走读。
scenarios-fp: ac0582847a8d06fbc3a067583103ae8b4fe8a862
wake: 2026-09-22T15:08:53Z state=running fp=0a9e204f61d6d309a1c4c0b0452154b7306c6652

working: 2026-09-22T15:16:04.727735+00:00 ⑤已完成按需文档与安全安装候选；定向安装/失效负例通过，保留隔离安装副本 /private/tmp/qwb-guide-review.yOVYrb/project；最终 smoke 正在运行。
wake: 2026-09-22T15:16:58Z state=running fp=ce85a8ab345963472c689ae16ef117c58a9b308f

done: 2026-09-22T15:17:51.870471+00:00 ⑤文档按需整理完成，未提交；基线8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05。定向 tests/on-demand-guide.py rc0（先red后green）、bash -n rc0、git diff --check rc0、qwb-lint LINT PASS、bash tests/smoke.sh rc0 SMOKE PASS；qwb-test.sh fast rc0但配置为空未执行测试，full未跑。实际隔离安装副本 /private/tmp/qwb-guide-review.yOVYrb/project；执行报告 /Users/rocky/projects/qonnwolfbuddy/docs/reviews/2026-09-22-qwb-simplify-on-demand-guide-execution.md SHA256 12c3c03a168f0cefdd9aadfb8cbb21f1a2437d7e8025cb67d0aa3141fadfe1aa。真实Herdr/Claude/Pi/Codex接入与全门未覆盖，留主控独立验收；未改state。
wake: 2026-09-22T15:18:58Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T15:49:07Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T16:19:18Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T16:49:28Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T17:19:42Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T17:49:53Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T18:20:14Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a
wake: 2026-09-22T18:50:26Z state=running fp=5caf3bdc03464983fda379927be6f4d7c976ee4a

working: 2026-09-22T19:10:52.059863+00:00 用户授权提交推送，恢复⑤收尾；复用pG Sol high正式审核，已观察working，冻结8文件身份/tmp/qwb-simplify-05-freeze.json，tracked diff d77841129709b0a863d4bb8f042de91dbf77c1e4c1511f0daf16de559fa4f3e3。主控独立fast rc0/1.842s，配置实际非空，执行报告“为空未执行”错误，旧行保留；本次证据/tmp/qwb-simplify-05-fast.json及.log。唯一full执行中，未提前提交。
wake: 2026-09-22T19:12:39Z state=running fp=f370a23bdbfe2a0a662fa3374defe4dda8af6c24

working: 2026-09-22T19:13:03.574154+00:00 主控最终候选full rc0，171.121s，候选8文件身份前后完全一致；/tmp/qwb-simplify-05-full.json及.log，含smoke/review-identity/lint。独立审核尚在运行，未提交；用户已授权通过后推送。
wake: 2026-09-22T19:14:40Z state=running fp=a56eed52fa7ad571bb4637e5af794885b4bbb239

working: 2026-09-22T19:16:31.941265+00:00 ⑤正式独立审核r1 PASS；冻结对象HEAD=8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05，4个tracked工作区diff SHA256=d77841129709b0a863d4bb8f042de91dbf77c1e4c1511f0daf16de559fa4f3e3，4个新文件hash与/tmp/qwb-simplify-05-freeze.json一致。三个审点Standards 0/Spec 0：普通接手责任/三流程/Gardening及已验收①至④在本轮diff中保留；安装副本三专项入口可实际走通且迁移约束完整；安全安装、错链/缺失/symlink/目录/硬链接负例及config原字节保留成立。实测非空白Unicode码点root 10290→6615、root+主控11088→7578；执行报告fast旧说法确认为报告错误，末尾更正及同冻结fast rc0/1.842s收据成立。本审核定向on-demand-guide.py、bash-n、diff-check均rc0，未跑full；主控同冻结full rc0/171.121s只作其收据。未覆盖真实Claude/Pi/Codex/Herdr接入和现有项目升级。报告=docs/reviews/2026-09-22-qwb-simplify-on-demand-guide-r1.md SHA256=1ed92125cd911210f10d689f5e6c8195fa7c5267b1b34e5e54c88eb7ec87f7ae；未改候选源码/state/场景/历史行，未提交。
wake: 2026-09-22T19:16:41Z state=running fp=45596b596b2c56351fdcfbce81133b1e8544eacf
worktree: merged branch=qwb-simplify-on-demand-guide tag=-

done: 2026-09-22T19:17:45.963753+00:00 主控验收⑤完成；实现bd520d7b4432c4e939846eeb8ce685d451966b9b已ff进入main，8白名单文件+166/-38。独立r1 PASS；四场景安装走读/触发路径/缺失错链与安全安装负例/实测字数均通过。主控真实fast rc0 1.842s、full rc0 171.121s，身份前后不变，证据/tmp/qwb-simplify-05-{fast,full}.json及.log；执行报告旧fast空配置说法已明确更正。根+主控11088→7578非空白Unicode字符，不换算token。执行会话已退出且离开目录，worktree finish --merged实际成功；真实Claude/Pi/Codex/Herdr接入、并发目录替换攻击、真实CI性能未覆盖。用户授权提交推送，推送结果待实际回收；无部署/发版/其他项目升级。
