# 任务书：统一开局唤醒入口

state: verified

任务 id: qwb-simplify-wake-entry
优先级: P1
状态说明：现任主控激活的账本副本；进度只维护本票。
来源：用户要求将 buddy 精简建议开票，交由现任主控实施。

## 0. 背景与范围

最初开票时 templates/QWBUDDY.md 存在先无条件 --ensure、再按宿主选择值守的说明冲突。本次复核 HEAD f628a387cec897346d47e3382a342167addbf8e8：第 5 步已改为按宿主只选一种入口，该历史冲突已修正，不得重复重写。当前模板仍有其他/未知 harness 的 tab fallback，与本交接包既有三种主控范围不一致；实施时核对最新基线并收敛剩余入口。

目标：用户明确主控只使用 Claude Code、Codex、Pi。每次开局先选择一种值守方式，再检查该方式的健康：Claude Code 用 Stop hook；Pi 复用 buddy 已有的 templates/pi-extensions/qwb-watch.ts（安装到目标项目 .pi/extensions/qwb-watch.ts）；Codex 用前台 checkpoint。不支持其他主控，不为未知宿主自动启动可见 tab fallback。健康查询未知不当作缺失，也不自动并行启动另一种方式。

本票不新建 Pi 扩展、不引入第三方插件。该范围限制针对主控，不缩减工人 CLI 种类。历史 tab 值守脚本是否仍被手工排障或其他调用使用，需要另行核对调用链；本票先收敛默认入口与说明，不无证据删除运行时代码。

白名单：templates/QWBUDDY.md、templates/claude-hook.md、templates/agents-hook.md、templates/brief-include.md；确有冲突的 templates/roles/主控.md；必要的同主题文档。默认不改 bin/、Pi 扩展或安装器。
若真实能力不支持目标流程，列出阻塞证据由主控修订范围，不能只改文档声称支持。

不改变已知“主控退出/机器重启后不自动恢复”的能力边界。

### 已核实的接入机制与预期改进

- Pi：源文件 `templates/pi-extensions/qwb-watch.ts`；`bin/qwb-init.sh` 的 `install_pi_ext()` 安装至目标项目 `.pi/extensions/qwb-watch.ts`，重启 Pi 或 `/reload` 后加载。扩展验证 `HERDR_PANE_ID` 与主控锁，持有 `qwb-wake.sh --block` 子进程；退出码 2 的摘要经 `pi.sendUserMessage(text, { deliverAs: "followUp" })` 注入。启动时持锁或之后 turn_end 获锁均有入口；status 可报告 pi-ext。不要另找第三方扩展。
- Codex：`bash qwbuddy/bin/qwb-wake.sh --block --max-ms 180000` 作为前台工具调用循环；2 处理摘要，124 无变化续跑，0 无未结项收工。这是 buddy 的阻塞值守协议，不能改写为仅在若干操作后主动检查，也不能宣称结束本轮后可凭空自动恢复。
- 预期改进：入口、安装与健康说明一致，用户能明确知道加载哪个文件、运行哪条命令及何时会接续；保留已实现的值守内核。

## 1. 验收场景

### user_正常路径_按宿主单选
Given 分别为已正确安装的 Claude Code、Pi、Codex，且值守尚未启动或已经健康运行
When 主控按新的唯一开局入口走读
Then 三种宿主各只有一条明确启动或接续路径，已健康实例被复用；都不先无条件执行 tab --ensure。

### user_失败路径_健康未知
Given 值守健康查询报错、宿主扩展未加载或必要能力缺失
When 主控执行开局检查
Then 明确报告未知或缺失和对应恢复步骤，不宣称运行正常，不启动竞争的第二种值守来掩盖故障。

### user_正常路径_交接入口一致
Given 安装时注入的 Claude/agents/brief 入口与主控总说明书
When 分别从这些入口接手同一宿主
Then 都导向同一选择规则，保留已有锁和恢复约束。

### user_失败路径_未知主控不回退
Given 当前宿主不属于 Claude Code、Codex、Pi，或无法可靠识别
When 按主控开局入口操作
Then 明确报告不支持或无法识别，不猜宿主、不自动启动 tab 值守；识别为受支持宿主后才能继续。

### user_正常路径_Pi扩展可定位并接续
Given 临时目标项目已安装 buddy，Pi 加载 qwb-watch.ts 且取得主控锁
When 从说明定位扩展并验证工人进展触发消息
Then 能追溯模板、安装目标和加载步骤；正常进展产生 [qwb-wake] follow-up，晚获锁能在 turn_end 启动，未加载或非锁主不被误报为正常；复用已有生命周期测试并记录适用版本。需要真实接续证据时不能只用模拟 sendUserMessage 背书。

### user_正常路径_Codex阻塞等待
Given Codex 主控仍在前台值守循环，工人在其等待期间交付
When qwb-wake.sh 返回
Then 2 触发摘要处理、124 继续等待、0 结束；文档明确循环中断或主控退出后需重新接入，不将普通主动检查当成此机制的等价替代。

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

working: 2026-09-22T13:14:00.173720+00:00 激活①；基线 33ab7e4d15926c21fe9199efdbaffeff7f8393cd，无其他在途票，Gardening已验收ff753e2/33ab7e4不重复执行；此前三项流程保留。工作目录 /Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-wake-entry，分支qwb-simplify-wake-entry；主账本 /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-wake-entry.md。主控仍wF2:p3；仅复用现有pH/pG执行审核窗口，用户今日指定Sol medium执行/high审核。母仓仅预存未跟踪docs/plans/，全部保留；②至⑤未激活。默认写入模板四入口，必要同主题README.md/README.zh.md允许；不改bin、Pi扩展、安装器或其他生产机制。先辨别已修问题与剩余入口，不预填审核或派发结论。
wake: 2026-09-22T13:14:20Z state=running fp=d9ef7c68057bebc183b4df44fa2cf648ffa1d4f3

working: 2026-09-22T13:14:47.427681+00:00 复用既有Herdr交互派发入口向wF2:pH交接本票，已核实Sol medium及正确cwd；未伪造qwb-run生成的dispatch行。场景提取逐字复用当前bin/qwb-run.sh的scenario_block并冻结实际字节SHA1，未改算法或预填假指纹；实现开始后不无痕改场景。
scenarios-fp: 2284f1f6a95041db1d4437152357b50c72fdf9fc
wake: 2026-09-22T13:16:21Z state=running fp=d8df12712532822153caa7f0c1be4e5d45c3e9af

done: 2026-09-22T13:18:27Z 执行者候选完成，保持未提交待独立审核与主控 full。固定 HEAD 33ab7e4d15926c21fe9199efdbaffeff7f8393cd，候选 diff SHA256 18047fc0a40424d020ff32d7e96f925ca28197edc6d1cf4f81604f；改 templates/QWBUDDY.md、templates/claude-hook.md、templates/agents-hook.md、README.md、README.zh.md。已按宿主单选的历史修复仍在，现仅去掉未知/其他主控默认 tab fallback，保留运行时历史 --ensure 手工排障与工人 CLI；明确 Claude Stop、Pi 源模板/安装目标/reload/晚获锁/`followUp`、Codex 真前台 --block --max-ms 180000 的 2/124/0 与中断重开局；健康未知须排查，不推断正常或另启值守。Gardening 入口、角色主控文件及工人附页保留不改，未改 bin/Pi 扩展/安装器/测试源/state/场景。证据 /tmp/qwb-simplify-wake-entry-walkthrough.md（SHA256 ad0710db2e3fe50c206606cf827a469e19d4128eeefe3ae59ff66803b0a013d0）逐项列出六场景和边界；隔离初装/复装 qwb-init.sh 均 rc=0，最终模板/安装目标 cmp=0，Stop hook 唯一，日志 /tmp/qwb-simplify-wake-entry-install.log、/tmp/qwb-simplify-wake-entry-reinstall.log。`bash bin/qwb-test.sh fast` rc=0（Bash -n + ShellCheck，stdout 空，日志 /tmp/qwb-simplify-wake-entry-fast.log）；`git diff --check` rc=0；未跑 full。Pi 扩展与 wake 脚本当前 SHA256 分别 c2aa32e5abd8e297767070edcce7c09737b6d37e47b84bbcadedb0997a2746f2、f770cb0f2a43d7bf6170e7909829be3e30cf256c22c5cab0c3cb2e81b2a0653f，与既有真实闭环 receipt.json 相同；复用 lifecycle-r2 Pi 15/15 旧证据，真实 Pi /reload、真实 Claude Stop、本轮 Codex 180000ms 等待未实测，不称新真机 PASS。白名单外 docs/DECISIONS.md:438 仍记旧“其他/未知” fallback，为历史决策文档冲突，先报告主控未改；README 双语旧生产状态段亦保留原文。无提交、push、merge 或副本升级。
wake: 2026-09-22T13:20:22Z state=running fp=9e4312728104e212003e9a5dd7d20753ef34eb7d

working: 2026-09-22T13:21:20.612334+00:00 主控明确必要同主题文档白名单含docs/DECISIONS.md，仅追加本次三宿主默认入口决定并保留历史；不改运行时。执行者原diff哈希标签/位数错误已要求机器重算追加纠正。当前Pi与wake文件sha256经主控实算均与生产闭环receipt一致，可复用对应已测范围，未测宿主组合继续明示。
wake: 2026-09-22T13:22:22Z state=running fp=945248204152c8e8cc10474997737366de1319b9

working: 2026-09-22T13:22:36+00:00 纠正上一条 done 中的候选 diff SHA256：原写值 18047fc0a40424d020ff32d7e96f925ca28197edc6d1cf4f81604f 仅 54 位，非有效 SHA256；原账本行保留。主控本轮授权的最终候选以固定 HEAD 33ab7e4d15926c21fe9199efdbaffeff7f8393cd + 未提交 `git diff --binary HEAD` 为对象，机器 `hashlib.sha256` = 018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438（64 位，21566 字节），补入 docs/DECISIONS.md §三十七，仅追加取代旧其他/未知默认 fallback 的裁定，旧段及运行时代码不动；与上一轮五文件候选不同。最终 diff 保存 /tmp/qwb-simplify-wake-entry-final.diff；六场景更正证据 /tmp/qwb-simplify-wake-entry-walkthrough.md SHA256 8c6a3fa7f06191609927a83b9cecad31eba520d343be0d637aa168b4eff3ee41。本轮 `bash bin/qwb-test.sh fast` rc=0（/tmp/qwb-simplify-wake-entry-final-fast.log）；`git diff --check` rc=0，未跑 full。Python 实算当前 bin/qwb-wake.sh 与 templates/pi-extensions/qwb-watch.ts SHA256 均逐项等于旧生产闭环 receipt.json 的安装文件记录，仅复用该运行时适用范围；真实 Pi/Claude 宿主组合及本轮 Codex 180000ms 等待仍未实测。工作树保持未提交，待独立审核与主控 full。
wake: 2026-09-22T13:24:23Z state=running fp=65efa3234228a5aadcdad8343481eb245ba6708a

working: 2026-09-22T13:47:31.764263+00:00 用户要求继续后恢复推进；已向现有 wF2:pG Sol high 会话 01a0c940-79c1-7243-8568-95bbc774caea 发起固定 diff 018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438 独立三审点审核，观察到 working；主控同候选 full 已启动，日志 /tmp/qwb-simplify-01-full.log，尚未出结果。不新建 pane，②至⑤尚未激活。
wake: 2026-09-22T13:48:29Z state=running fp=1c4cec1347eeded9f12dace5ef1e1437e48c36ee

working: 2026-09-22T13:49:18.074517+00:00 主控全门 bash bin/qwb-test.sh full --project .worktrees/qwb-simplify-wake-entry rc=0，113.446s；执行前后候选 diff SHA256 均018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438，源码未变。原始日志/tmp/qwb-simplify-01-full.log，收据/tmp/qwb-simplify-01-full.json；独立审核仍进行中，尚未提交或验收。
working: 2026-09-22T13:49:52Z 票①独立审核 r1 完成；对象 HEAD 33ab7e4d15926c21fe9199efdbaffeff7f8393cd + 未提交 diff SHA256 018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438；Standards 0、Spec 2，AMEND：未知宿主先占锁后拒绝；Codex block 退出 0 亦可为失锁，文档误称账本为空。报告 docs/reviews/2026-09-22-qwb-simplify-wake-entry-r1.md；仅走读、隔离失锁复现 rc=0、git diff --check rc=0；未跑 fast/full，未改候选、state、场景或旧记录。

working: 2026-09-22T13:50:09.149707+00:00 主控采纳独立r1两项AMEND：未知宿主须先识别后取锁，Codex0不得无条件推断空账本；已交原执行pane定向改同六文档，并保持注入总说明书责任与历史tab排障表述一致。不改运行时代码。初轮full0保留历史候选证据，返修后重新绑定验收。
wake: 2026-09-22T13:50:30Z state=running fp=fe0ef782f0c3c68c4aee3b34c237615ce8ee76cc

working: 2026-09-22T13:53:31+00:00 r1 两项 AMEND 返修交付，保持未提交待复审。对象固定 HEAD 33ab7e4d15926c21fe9199efdbaffeff7f8393cd + 当前六文档未提交 diff：README.md, README.zh.md, docs/DECISIONS.md, templates/QWBUDDY.md, templates/agents-hook.md, templates/claude-hook.md；`git diff --binary HEAD` 28653 字节，Python hashlib.sha256=a20d2e75f485f4d387d7922e6a46faec186f5cf00659443652c18d93cf879eb8，文件 /tmp/qwb-simplify-wake-entry-r2-final.diff。§1/注入/README/DECISIONS 统一先确认 Claude Code/Codex/Pi 宿主、未知先停且不 acquire，再取锁和点名；注入明确总说明书全文必读。Codex exit 0 改为本轮值守结束，须核对输出、锁主和账本才可认空账本；孤儿提示按既有锁恢复，工具表 --ensure 标历史 tab 手工排障。不改 bin、Pi 扩展、安装器、测试源、state、场景或工人 CLI。六场景定向走读及隔离安装/无锁孤儿复现见 /tmp/qwb-simplify-wake-entry-r2-walkthrough.md，SHA256=cdd2671ff92c7355f74b5ddc3246fed4e29d6f9c91e0c3850628109626f76792；隔离安装 rc=0、目标/源字节比对通过，无锁 --block --max-ms 1 实得 rc=0 且孤儿提示。`bash bin/qwb-test.sh fast` rc=0（/tmp/qwb-simplify-wake-entry-r2-fast.log，stdout 空）；`git diff --check HEAD` rc=0。当前 wake/Pi 模组 SHA256 逐项等于旧生产 receipt 安装项，旧运行时证据仅按相同 blob 复用；主控先前 full rc=0、113.446s 仅绑定旧 diff 018450855cbcc9c5560dcc909c9c1ef72cb92cb91e23ca2a6187e76096cf1438，不作为本返修候选 full。本轮未跑 full、真实 Pi /reload、真实 Claude Stop 或 Codex 180000ms 等待；无提交、push、merge、委派。
wake: 2026-09-22T13:54:31Z state=running fp=861635f831772d548ae81fd176a8c4cd8ee6b0b9
working: 2026-09-22T13:53:58Z 票①独立审核 r2 完成；固定 HEAD 33ab7e4d15926c21fe9199efdbaffeff7f8393cd + 六文件未提交 diff 28653 字节 SHA256 a20d2e75f485f4d387d7922e6a46faec186f5cf00659443652c18d93cf879eb8。仅复审 r1 两项及相关文档一致性：未知宿主先识别后取锁、Codex 0 核输出/锁/账本均闭环；注入全文必读及历史 tab 手工排障说明一致。结论 PASS，报告 docs/reviews/2026-09-22-qwb-simplify-wake-entry-r2.md。审核独立复核哈希、git diff --check rc=0、隔离安装总说明书/Pi 扩展 cmp rc=0；执行者本候选 fast rc=0 为其收据，主控旧 diff full rc=0 不适用当前候选，本审核未跑 full/fast、未改源码或提交。
working: 2026-09-22T13:54:43Z 更正上一条 r2 审核 working 时间：13:53:58Z 是审查身份复核时间，账本实际追加在其后；保留原行不改写。r2 PASS 结论、固定 diff 身份及报告路径不变。
worktree: merged branch=qwb-simplify-wake-entry tag=-

done: 2026-09-22T13:55:58.129910+00:00 主控验收①完成；实现239c2ceaabe9a4e8e01ad942dbd3f2c1e1fd5afb 已ff进入主线，仅README.md、README.zh.md、docs/DECISIONS.md、templates/QWBUDDY.md、templates/agents-hook.md、templates/claude-hook.md，+33/-36。独立r2 PASS见docs/reviews/2026-09-22-qwb-simplify-wake-entry-r2.md；最终候选a20d2e75f485f4d387d7922e6a46faec186f5cf00659443652c18d93cf879eb8，fast0、主控full0 109.200s，/tmp/qwb-simplify-01-r2-full.json及.log，前后diff一致。六场景走读和隔离安装通过；真实Pi /reload与Claude Stop、本轮精确180000ms等待未覆盖，历史同blob证据仅限原适用范围。执行会话已正常退出，实际worktree finish --merged成功并记账；无push/发布/其他项目升级。
