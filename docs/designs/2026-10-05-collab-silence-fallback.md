# 协作进度静默、工人失联兜底与传输耗尽升级（待主控确认）

基点：`44ab8ac60f7f65591b87f5291b68cd95250feff8`；唯一规格为主账本及其最新 working 裁决。此提交只交设计。

## 范围与需确认的前提
- 建议 A/B/C 均只启用于有 `planning_authority` 或 `planning.authority` 的已迁票；授权身份失效仍在范围内，但实际通知回主控。无规划授权已迁票、未迁旧票保持原行为。
- 任务 B 的“票上没有规划授权则叫主控”与“无规划授权已迁票影响为零/逐字节不变”冲突；建议本票优先后者，前者仅指有授权记录但身份失效，真正无授权留后续票。请主控明确范围。
- `handoffs.recipient` 恒为 controller，并未保存每次实际收件角色；原目标只能按到期时原路由规则判定，不能声称还原历史三次真实目标。建议升级摘要明确“原路由目标（当前判定）”，历史实际目标写 unknown。
- “直到接收、不会无界增长”建议解释为重提频率有上限、transport_count 封顶、每条交接不派生无限新交接；既有逐次审计 events/wake 行仍随提醒次数增长。若要求整票字节恒定，会改变审计模型，需另行裁决。
- 工人丢失只认 `worker_lost` 的 pane_not_found；空 agent、查询失败均 unknown，不推断死亡。沿用最近一条有效 dispatch 的工人边界，不在本票扩成多工人监控。

## A：纯进度分类与静默
- 在 ledger 按真实来源事件分类，不能只看 payload/行首。静默仅针对自动 source 交接中 kind=working 的普通 append；已存在的同类交接也在 due 投影中静默。
- 工人 working：现状通常叫规划；有 pending/rework 门禁 claim 则叫门禁；身份失效叫主控。建议全部静默，仍保留正文、events 和 pending(all) 原义。
- 规划 working：现状也可能叫自己（或优先门禁/失效后主控）；建议普通 append 静默，避免自激。
- 门禁 working：当前 append 只允许本人已派 child 的 worker-activity 绑定，通常叫门禁自己；建议静默。其余普通 working 本来就被 writer 拒绝，不扩大权限。
- 主控 working：有授权时通常叫规划，门禁 claim 优先，accepted/rediagnose 后归主控；建议普通 append 静默。
- 例外：`working: spec-resolved:` 是显式规格处置，保留；answer/resume、plan-ready/start-claim、新票/修订/恢复等有独立 kind 的动作事件保留；绑定 test-request 来源保留。显式 send 即使 payload 写 working 也不是纯进度。
- blocked、needs-decision、question、done、request、门禁 verdict 和规划结果上行照旧；筛出纯进度后才按测试请求→门禁→规划/主控做原分流，不让新 working 遮住较早动作。
- 只改变 due，不伪造 received/handled、不删除已有 handoff。完整 pending/status 仍能看到进度义务；收尾由接收者按既有协议读回处理，静默不等于自动清债。
- 不改 events/handoffs schema；静默项不耗预算、不参与 C 升级、不单独写 wake。修改规划测试中“working仍叫醒”的已过期断言，保留对伪造 done 正文的独立断言。

## B：复用已有丢失判定、时间与去重
- 在已迁 collect_due 提前 continue 前补检查；仅有规划授权、phase 非 done/verified、最近有效 dispatch 尚无对应 op 的 done/not-sent，且没有 accepted 门禁结论的票参与。
- 调用现有 worker_lost，不改 lib；时间仍用 now_ms/QWB_REWAKE_MS 和 ts_epoch。已迁票用最近业务事件的 at，不能用每轮 pending/transport/wake 都会更新的 mtime。
- “任何新事件”指外部业务动作/工人进度/received/accept/activity 等；排除监督自身 handoff-pending、handoff-transport、wake，避免通知本身无限推迟兜底。新业务事件立即重置静默计时。
- 路由按最近 dispatch 的真实 ops.owner：等于本票规划 grant pane 且双 identity proof 有效才给规划；主控派发、其他 owner、身份未知/失效均给当前主控。不借兜底扩大门禁或规划权限。
- 与普通 handoff 分成独立 due 条目，复用 compose_msg/route_gate_due 与 wake-check/wake；有 pending 不遮失联，失联也不吞 pending。B 不扣 handoff 预算。
- 失联指纹为 sha1(固定用途标记+dispatch event/op+工人 pane+最终收件身份)，只查同一指纹的持久 wake；同一派发/同一收件人只成功通知一次，其他交接写 wake 不抹掉去重。规划失效换主控是不同指纹，可补叫主控一次。
- 停滞指纹另加最近业务事件 seq；比较 max(业务事件 at, 此指纹最近 wake at)，到 QWB_REWAKE_MS 才叫；成功后按同间隔低频再提。QWB_REWAKE_MS<=0 或 quiet 关闭停滞计时，不关闭已确认丢失告警。
- 当前有已 accepted 且本代合理 wait/近期 activity 的交接时，沿用 handoff_due 的保护，不用 B 绕开 wait；明确 pane 丢失仍须告警，绝不代做 claim 接管/重派。
- 摘要：`工人丢失：pane=… op=…；请派工者核查` 或 `工人无进展：…ms（阈值…ms）pane=… op=…`。记录成功 wake 前崩溃允许重复，不承诺网络严格一次。
- 无新增持久字段，重启从 events/wake 恢复；投递失败不写成功 wake，同轮后续票继续。--once/--block 共用；--dry-run 保持只读旧契约。

## C：原交接三次耗尽后回主控
- 仅 A 未静默、未 handled、尚未 received 的交接进入耗尽处理；既有已 received/accepted 的处理与有界 wait 语义不变，不凭耗尽抢 claim。正常前三次及其审计字节保持原样。
- 第三次尝试后下一轮，按原路由（含测试请求/门禁优先）计算每条交接的原目标；规划/门禁/测试体系目标升级主控一次；本来归主控的交接先等低频间隔再重提。
- 采用原 handoff ID，不另造升级交接。给 pending/due 增加瞬时耗尽提示；值守先拆出耗尽子集交主控，再将余项走原路由，避免升级又被门禁/测试请求抢走。
- `qwb-send.sh transport` 增加可选耗尽模式与原路由角色/pane 参数；仍仅沿用当前 controller/watcher 权限。ledger 校验仅适用本票范围、count=3、未 received/handled，角色值与相关 grant/claim/request 绑定；参数只记录通知事实，不授予办理权。
- 首次升级在现有 events 中写一条 kind=handoff-transport 的专用收据，line 明确 mode=escalation、event_id、原路由角色/pane、count=3；transport_count 不增长，transport_at 更新。扫描此交接的该收据判幂等，重启不再发“首次升级”。
- 重提周期固定 `max(1800000ms, min(86400000ms, 有效QWB_REWAKE_MS或INTERVAL))`，最多每30分钟一次、无需新配置；quiet 不抑制无人接收的动作交接。
- 主控原交接和已升级交接都按该周期继续提，直到 received/handled；仍使用原 event_id，transport_count 恒为3，transport_at 及普通审计事件记录重提，不递归新建 handoff 或新增无限计数。
- 耗尽收据在 API/--block 输出前原子发布，保留既有“先记尝试”的崩溃语义：发布失败不投；发布后崩溃最多等一个低频周期再提，不能声称 API 已成功或 received。
- 摘要带原交接 ID、原路由角色/pane（历史实际投递目标 unknown）、已尝试3次和升级/重提标记。规划后来按原权限 received/handled 后停止本条提醒，既有 planner-result 原子上行照常且唯一。
- 不修改 events/handoffs schema、计数上限、owner_fp/op/prepared、接班证明或 wait；需修改 send 薄参数入口，这一点请求随设计确认。旧耗尽交接没有升级收据时按上述规则补一次。

## 验收与提交
- 设计先提交并写 needs-decision，待主账本 working 裁决后再做 A、B、C 三次实现提交；每次运行 `bash bin/qwb-test.sh fast`，不跑全门、不启动真 Herdr/模型。
- A：在已接入 tests/collab-planning.sh 复用公开授权/派发与隔离 fake Herdr；同一“连续三条 working 后零门铃”用例先对基点44ab8ac跑红并留 stdout/stderr/rc，再跑候选绿。覆盖四角色进度、显式 send、answer/resume、混批、历史未接进度。
- B：同文件新增丢失一次/重复扫描/重启去重/身份两次复核失效、主控实际派工、未派工/已done不误报、停滞与进度重置/quiet/wait；使用现有私有运行时替换时钟及 QWB_NOW_MS_CMD，不真等阈值。
- C：同文件覆盖规划/门禁/测试体系三种目标耗尽、同批正常与耗尽交接隔离、主控低频、重启、API失败、收据发布失败、后来接收/办理；断言原交接/计数/权限不变、无重复 planner-result；collab-handoff 保留无授权三次停投与 prepared/wait 的全部断言。
- 第七场景：复用 planning 的同路径冻结票/时钟/随机源字节对照，把基点固定为44ab8ac；比 stdout、stderr、rc、票字节、Herdr序列，不过滤业务差异。门禁 pending/rework、测试优先级只以非纯进度、未耗尽输入要求等价，A/C 命中输入是明确行为变化。
- 旧票值守用例复用 tests/wake-block-output.sh 的 QWB_TEST_WAKE_BASELINE；无规划授权用例与普通门禁/测试批次保持基点逐字节。不修改或移除失效关闭、进程登记和短 socket 夹具。
- 最终分别跑所有改动测试及 collab-planning、collab-handoff、collab-gate、collab-test-policy、wake-block-output；记录 rc 和 grep -c '^PASS'/grep -c '^FAIL'，七个场景逐项映射。原始日志仅本副本 .qwb-tmp；代码仅白名单、detached HEAD 正常提交。
- 四份角色说明只更新静默/失联通知/耗尽提醒相关句子；run/herdr/role/lib 与权限、主控锁、验收门、五值state、落地授权不动。
