# 副主控与门控常驻职责真机演练（2026-10-05）

主控（Claude Code，w14Z:p1）在独立 named Herdr 会话里做的演练记录。默认会话未被触碰；会话结束后已 stop 并 delete。原始证据（各窗口输出、票、角色登记、会话记录、真实 Herdr 应答）在本机 `.qwb-tmp/drill-roles/`，未入库。

## 主控记录

环境：独立会话（名字见 session-name），项目 .qwb-tmp/drill-roles/project；主控 Claude Code opus 5.5 medium（w1:p1），副主控 planner 与门控 gate 均 Pi magpie codex/gpt-6-astra low（w1:p2、w1:p3），工人 pi-sol-high（w2:p1）。

- D1 角色启动在 QWB_WORKSPACE 为空时被拒「须有唯一已登记workspace，不回退focused默认窗口」。真 Herdr 的 workspace list 对 `workspace create --cwd <仓库>` 建出的工作区不返回 worktree.repo_root，自动匹配落空；拒绝信息没写出路（填 config.sh 的 QWB_WORKSPACE）。填 w1 后两个角色启动成功，身份证明 native-session+pid-start+visible-footer，活动 idle。
- D2 第二阶段前半走通且零拒绝：主控开入口票 → migrate → qwb-send 存原话 → plan-assign；副主控被门铃叫醒，办理交接，new 出实现票，派工给 pi-sol-high 成功（01:30:37Z），工人 01:31:47Z 写 done。
- D3 主控的四处猜测（说明书缺口）：入口票怎么开；plan-assign 的 permissions 值域；迁移自动生成的「接班核查」交接该谁办；主控通知副主控的通道。见 stage2-notes.md。
- D4 **链路在工人交付后断开**：工人的 done 事件被路由给副主控，副主控逐条 received→handled，并在自己窗口里写「待主控安排门禁」，但没有任何东西通知主控。主控自 01:27Z 结束回合后再没被叫醒，到 01:51Z 仍空闲；门控一直空闲。qwb-send 有 `--to controller` 通道，规划角色说明里没有「工人交付后向主控报告」这一条。
- D5 工人交付时没有提交（副本里 drill/ 未跟踪，HEAD 仍是基点）；工人的 done 行与副主控的总结都没有 commit sha。门控验收需要固定候选。
- D6 已迁票上工人每条 working 进度仍会门铃副主控一次（01:30:58Z、01:31:21Z、01:31:28Z），收紧叫醒只覆盖未迁旧票。
- 花费（界面显示）：主控 $1.61，副主控 $1.12，工人 $0.17（到 01:51Z）。
- D4 根因（主控 opus 查到代码）：`bin/qwb-wake.sh` 的 `route_gate_due`（约第 651–666 行）只要票上有规划授权，就把整票到期交接全部门铃给规划 pane；规划逐条 handled 后主控的待办集合为空，Stop hook 无事可叫。`verdict=accepted` 也不在门禁分支（只认 pending|rework），同样会落到规划。
- D5 根因：`qwb-ledger.sh new` 生成的票正文只有原始意图/工程规格/必要约束/场景，没有 `templates/TASK.md` 的报告要求（提交、done 行带 commit sha），工人不知道要提交。主控 `gate-assign` 被拒「授权候选必须clean」（rc=255）。
- D5b 死结：候选不干净时想返修，`gate-dispatch rework` 需要先有 `gate-assign`，而 `gate-assign` 要求候选干净。主控改走 spec-defect → spec-resolved → `plan-authorize`（budget=2）让规划重派。
- D7 **续派在真机上会被拒（时序相关）**：规划执行 `qwb-run` 续派原工人，被拒「本代真实活动为 unknown，不凭Herdr idle复用或中断」。根因在 `bin/qwb-herdr.sh` 约第 347–351 行：带 `--task` 的活动探针要求现场观测的 pid、pid_start、session 三项都等于票上最近一条 `working: worker-activity` 记录；而首次派发时那条记录是在 `agent start` 返回后立刻写的，真机上 Herdr 此刻还没报出 Pi 的会话路径（主控事后在隔离会话实测：`agent start` 的应答里没有 `agent_session`，返回后 0.02、0.14、0.28 秒查 `pane get` 都没有，1.52 秒时才出现），探针落到通用分支，记录里只有 pid 与 pid_start、没有 session（票第 37 行：`{"activity": "unknown", "proof": "native-pid; CLI idle not verified", "pid": 60618, "pid_start": …}`）。之后现场观测带 session，三项比对必然不等。不带 `--task` 的同一探针现场返回 `{"activity": "idle", "proof": "native-pid-start+session-branch", …}`。该判定在 `bin/qwb-run.sh` 约第 427–429 行的通用复用路径上，未迁旧票的返工续派同样受影响。假 Herdr 夹具在启动时就给了会话，测不出来。这是时序问题而非每次必现：同日第 11 轮真机验收的首次派发记录就带了 session（`native-pid+unpersisted-session`）。主控最初在任务书里把根因写成「脚本在会话未落盘时丢掉了 session」并称「`agent start` 返回时已给出 `agent_session`」，两句都没核实，被工人读代码推翻；本条已按实测更正，样本存 `.qwb-tmp/real-herdr-samples/`（`agent-start-pi.json`、`pane-get-pi-just-started-no-session.json`、`pane-get-pi-session-unpersisted.json`）。真实应答已存：real-pane-get-worker.json、real-process-info-worker.json。
- D8 规划把给账本命令用的 JSON 载荷文件写在项目根（`.qwb-drill-hello-created.json` 等四个），`git status` 里是未跟踪文件；说明书没规定这些文件放哪。
- 终态（02:15Z 停止演练）：实现票 running，工人副本里文件已写未提交，门控从未被授权也从未动过，main 无新提交。主控共被使用者追问一次才继续。花费（界面显示）：主控 $2.27，副主控 $1.59，工人 $0.17。会话已 stop 并 delete；证据在 evidence/。

## 演练中 Claude Code 主控自己写的笔记（原文）

开始：2026-10-05 03:25 (Europe/Madrid)

## 猜测点 / 说明书不清

- G1 需求入口：规划.md 说「用户请求先由03的qwb-send持久保存；主控plan-assign绑定真实source_event」，收件箱约定.md 说「未开票请求须先开票」「旧票拒绝send」；`new` 的 durable_source 要求 source_task 是**已迁 qwb-collab-v1 票**且有 handoff。说明书没写「入口票」怎么开。判断：主控按 TASK.md 写一张旧格式入口票 → `qwb-ledger.sh migrate`（新票无旧writer，confirm 各项写真实证据）→ `qwb-send.sh send` 存原话 → `plan-assign` 绑在入口票。这是从代码反推的路径，不是说明书明写的。
- G2 plan-assign 的 `permissions` 字段：代码只校验为非空字符串数组，说明书无值域。我填 ["new","dispatch"]，属猜测。budget 填 "1"（每票首次派工次数）。
- G3 迁移入口票会自动生成一条发给主控的 `source:<migrate事件>` 交接（「接班核查迁入前正文与旧义务」）。入口票挂 planning_authority 后，qwb-wake route_gate_due 会把整票待办路由给规划 pane，迁移核查也会被一起门铃给规划。说明书没写这条该谁办。判断：迁移核查是主控义务，主控先 received→accept→prepared→handled 关掉（result-ref=.qwb-receipt-intake-migrate.json，已被 .gitignore 的 .qwb-receipt-* 覆盖），只把原话事件留给规划。
- G4 通知规划的「规定通道」：说明书无 role 直发命令；qwb-wake.sh route_gate_due 是唯一门铃（herdr pane run 到登记 pane），由 Claude Code Stop hook 驱动；主控禁止自己跑 qwb-wake.sh，也不应直接 herdr 打字绕过唯一监督。判断：结束回合交给 Stop hook。

## 03:52 使用者追问后查到的现状与问题

现状（03:52 读回）：
- 规划 planner 已用 new 开出 tasks/2026-10-05-drill-hello.md（spec_rev=0，场景 user_hello / user_错误内容拒绝），并派工 pi-sol-high（op=bd744789…，pane w2:p1，worktree .worktrees/drill-hello，Space w2）。预算 1 次，已用完。
- 工人 01:31 写了两行 done:；候选 .worktrees/drill-hello 未提交（`?? drill/`），drill/hello.txt 字节 = "QWB ROLE DRILL OK\n"（xxd 已核）。分支 drill-hello 仍在 77583ed。
- 票 state 仍是 running，无 gate、无 claim；门禁 gate 从未被授权（无 gate-assign）。

问题 P1（为什么主控一直没被叫醒，根因）：qwb-wake.sh route_gate_due 只要票上有 planning_authority 或 planning.authority，就把**整票全部到期交接**（包括工人的 done:）门铃给规划 pane，不再留给主控。规划随后把这 8 条事件全部 received→accept→handled（op=planner-observe-*），03 义务被关闭，主控的 keep 集合为空，Stop hook 无事可叫。也就是说，工人交付后应交给主控安排门禁的事件，被规划「观察式」处理掉了。代码证据：qwb-wake.sh 第 665-666 行的 elsif 分支；impl 票 handoffs 全部 accepted=w1:p2 handled=1。
- 说明书冲突：门禁.md / 主控.md 说 gate-assign 由主控显式绑定，但没写「工人 done 后由谁通知主控」；规划.md 只说规划不自动验收。规划在自己窗口写「待主控安排门禁」，但这句话不在账本里，没有任何通道把它送到主控。
- 观察：wake: 行写进了票（看起来像「已叫醒」），实际叫的是规划，不是主控；qwb-status 的「最近: wake: …」容易误读成主控已被通知。
- 观察：主控 Stop hook（pid 11326，03:27:52 起）一直存活，但 qwb-status 只报「仅进程存活；接班健康未验证」，没有发出任何告警。
- P2：工人写了 done:，票 state 仍是 running（只有主控能改 state），值守的 running 兜底重叫是 QWB_REWAKE_MS=1800000（30 分钟），所以 20 分钟内不会再叫醒主控。

### 拒绝 R1
- 命令：`bash qwbuddy/bin/qwb-ledger.sh gate-assign --project <根> --task tasks/2026-10-05-drill-hello.md -- gate <scratchpad>/gate-assign.json`（candidate=.worktrees/drill-hello，base=77583ed…，attempt=1，policy=qwb-v1，required.full=[user_hello,user_错误内容拒绝]，review=pi-astra-low，rework=pi-sol-high）
- 拒绝原文：`账本拒绝：授权候选必须clean`（rc=255）
- 判断：工人只在 worktree 里新建了文件，没有 commit（`?? drill/`，分支仍在 77583ed）。根因是 `qwb-ledger.sh new` 生成的票正文只有原始意图/工程规格/必要约束/场景，**没有 TASK.md 的「报告要求」节**（「最后打印 DONE <commit sha>」），工人不知道要提交。这是规划开票模板的缺陷，不是工人的问题。正路：主控挂 spec-defect 并以 spec 处置补上「须提交」的要求，再用 plan-authorize 显式重授权预算，交给规划按原通道重派同一张票（复用 worktree）；主控不替工人 commit，也不替规划派工。
- 猜测：说明书没写「门禁之前候选不合格」时怎么返修（gate-dispatch rework 要先有 gate-assign，而 gate-assign 又要求候选 clean，这是个死循环），所以只能走主控 spec 处置 + 重授权。
- 已做：主控 append `blocked: spec-defect:` + `working: spec-resolved: spec；…须 commit…`；`plan-authorize`（workers=[pi-sol-high]，budget=2）rc=0；`start-check -- pi-sol-high` 输出 ready。
- 交给规划：按 G4 结束回合，由 Stop hook→qwb-wake 门铃规划重派。**预判风险 P3**：P1 的路由缺陷还在，工人第二次 done 仍会被门铃给规划并被它 handled，主控大概率又不会被叫醒；gate-assign 以后，`verdict=accepted` 也不在 route_gate_due 的门禁分支（只认 pending|rework），会落回规划分支。说明书没有给主控留绕过这条路由的合法读取入口，只能靠使用者再追问，或者主控下一回合主动读账本。
