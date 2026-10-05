# 规划交接向主控回流设计（待主控确认）

基点：`d66d77cba3357179a5a4820e97c8a928c72a4312`。仅设计；范围以主账本 P1–P6 为准。

## 现状与证据
- `collect_due`：已迁票先 `plan-ready`、再 `handoff-pending --due`，提前 continue；没有经过后面的 `worker_lost` 或时间兜底。
- `handoff-pending`：按真实 events 补建 source 交接，工人 working/done/blocked/needs-decision 都会入列；receipt/wake 不再生成来源。
- `route_gate_due` 当前顺序：匹配的测试请求→测试体系（余项留主控）；有效 claim 且 pending/rework→门禁；否则有规划授权→整票规划；其余→主控。
- 因而规划票的 request、ready、进度、阻塞、交付、accepted/rediagnose 后续事件现在都可能给规划；身份两次复核失败才回主控。
- `handled` 只关闭原 event，保存 result_ref/sha256，不生成上行；`transport_count=3` 后停止 due、保留 pending，并无自动升级。
- dispatch 绑定 worker pane/op；工人 append 的 event 保存 actor/op/kind，可据此识别真实工人状态，不能靠 payload 的 done/working 字样判权。

## 分流与最小数据方案
- 保留同票 events/handoffs、现有字段及唯一监督，不增加角色、持久队列、第二套 receipt 或主控锁。
- 新逻辑仅作用于有 planning_authority/planning.authority 且未走既有测试请求分支、未由 pending/rework 门禁 claim 接管的票；P6 两条优先分支原样返回。
- 在此范围内逐 event 分成主控与规划子集；`record_transport` 只处理实际子集，不能为整票一起扣预算；保留批量门铃和两次 gate_proof。
- 分类查 source_event 的真实 kind/actor/op 与派发历史；不依赖正文、自选 event_id 前缀或当前 workers 映射（同 pane 续派会覆盖旧 op）。
- request（授权 source_event）、ready、规划控制事件仍给规划；迁入核查给主控；工人 blocked/needs-decision/question、丢失/停滞给规划。
- 主控专属交接也在 writer 确认入口拒绝规划 received/accept/prepared/handled，防止规划自行读取整票后抢先关闭；pending 仍可读完整集合。

## P1：交付直接到主控
- 改 `route_gate_due` 按上述真实来源把工人 done 留给主控；不等待规划，也不额外复制同一交付。
- `compose_msg` 仅为本票范围的主控交付加动作提示，保留原 JSON/event_id，其他摘要逐字节不动。
- 摘要示例：`① example(running) 工人已交付；下一步：主控安排门禁。来源 source:completion；done: DONE abc123`。
- 门禁已 claim 且 pending/rework 的返修 done 仍先给门禁，这是 P6 对 P1 的明确例外。

## P2：办理结果自动上行与不办理升级
- 选择 handled 原子派生：`handoff-handled` 完成既有身份/op/prepared/result_ref 校验后，同一次 publish 关闭原事件并创建主控交接。
- 只针对规划实际办理的上述工人阻塞/决策/丢失/停滞交接；普通 ready/request 办理不额外叫主控；主控办理上行不再派生。
- 派生 ID/corr 为 `source:planner-result:` 加原 handoff ID 的 SHA-256，attempt=1；source_event 仍指原真实来源事件，payload 带原 handoff ID、规划 actor/op、result_ref、result_sha256。
- 不加 schema 字段；以保留的 source: 命名空间、原 handoff 已 handled/accepted 身份和结果摘要共同识别派生项，不能只认前缀。
- 摘要示例：`① example(running) 规划已办理工人阻塞；原交接 source:blocked-1；op=resolve-1；结果 tasks/result.json；sha256=实际摘要；请主控读回结果。`
- 不选“规划再主动 send”，它依赖模型自觉且在 handled→send 间有崩溃缺口；不加定时扫描器，现有 pending 仅补偿已持久 handled 却缺上行的历史/恢复数据。
- 规划原交接第三次 transport 后，再到重试期限且无有效 activity/wait、仍未 handled，则由 pending 派生一次 `source:planner-escalation:` 加原 ID 摘要的主控交接。
- 摘要示例：`① example(running) 规划交接重投预算已耗尽；原交接 source:question-1 未办理；请主控接管核查。`
- 原事件保持 pending、原预算仍为3；升级交接独立最多3次，不递归升级，不伪造 received/handled、不偷移 prepared/op；超时后迟到的真实 handled 仍补发结果上行。

## P3：accepted 回主控
- 在既有测试请求和 pending/rework claim 分支之后、规划分支之前，accepted（以及既定需主控重诊的 rediagnose）剩余到期交接全部留主控。
- 不改 gate-verdict 的验收条件、claim 或 state；摘要示例：`① example(running) 门禁 accepted；请主控处理落地/清理。`

## P4：仅工人进度静默，兜底补接
- `handoff-pending` 不再为上述范围内真实工人 working 新建交接；已有此类交接只从 due 排除，保留原记录和 pending，不自动冒充 handled。
- 不能过滤 planner-ready、answer/resume、not-sent 或主控规格处置等 working 正文；历史进度仍需显式办理，保留原收尾义务语义。
- `qwb_task_obligations_json` 同步排除“尚未生成交接的纯进度”虚假来源，避免 done/verified 被仅有进度重新列为未结；已有 handoff 义务保持。
- `collect_due` 在上述已迁规划分支补调用既有 worker_lost；只认 pane_not_found，查询失败/标签退回仍 unknown；已完成或旧 dispatch 不报丢失。
- 仅 state=running、QWB_REWAKE_MS>0 且非 quiet 时补停滞兜底；时钟取当前 dispatch/最新真实工人进度，不能被 pending/wake 自身写盘刷新。
- 由窄 writer 命令 `plan-watch` 记录 worker-lost/worker-stalled 来源（blocked 正文）；仅现主控或已核验监督可调用，规划/工人不能自授该入口。
- collect 在锁外探测，writer 锁内复核 owner、授权范围、当前 spec/op/最新工人事件及超时条件；陈旧观察不写入，下轮重读；不在短锁内等待工具。
- ID 固定为 `planner-watch:` 加 spec/op/进度来源/原因摘要；同一观察重放不加事件，丢失/停滞交接先到规划并沿 P2 上行。

## 幂等与恢复
- handled 与结果上行同次原子发布，重复 handled 仍读回既有结果、冲突拒绝；pending 补偿按原 ID 查存在，不因时间/重启换 ID。
- 升级/兜底同样在唯一 writer 锁内查稳定键；新进度或新 dispatch 才形成新兜底来源；三次预算、activity/wait 和原 op 全保留。
- 规划换代/失效仍两次 proof 后回主控；不把旧 accepted 交给新规划。主控换代按现 owner_fp 复核，已有 prepared 须原 reconcile+死亡证明，不能自动重新执行。
- 值守重启重扫同票完整 events/handoffs；投递仍是有界至少一次，API 后崩溃可能重复门铃，但不重复业务交接或副作用。

## 测试与改动清单
- `tests/collab-planning.sh`：把“任意一条 planner-pane 门铃即通过”加强为按来源核对完整收件子集；补七场景、混合 done+blocked、伪造正文、旧 op、迟到 handled、身份两次复核间换代。
- 同文件复用已存在 request/handled 夹具和 accepted 私有 gate 路径；保留原请求映射、预算、依赖、CAS、权限拒绝断言；新增拒绝规划办理主控专属来源的原字节断言。
- `tests/collab-handoff.sh`：保留无规划票 working 仍交接、三次后仍 pending、prepared 接班、corr 保留和单监督断言；补规划结果/升级的重放、不递归、有效 wait 不升级和发布恢复边界。
- `tests/collab-gate.sh`、`tests/collab-test-policy.sh` 的 pending/rework、--block、测试请求优先级断言不改；现有 smoke 旧票/进度/丢失断言不改。
- P6 在已接入测试中做起点/候选差分：同一路径串行重置私有夹具，固定时钟/事件随机源，逐字节比 stdout/stderr/rc/票/Herdr 调用；安装摘要用同份冻结 fixture 排除工具版本元数据差异，不过滤业务差异。
- P1 用同一公开用例跑 d66d77c 为红、候选为绿；补 --once/--block，以及静默三条进度后丢失/停滞、quiet、配置关闭、unknown 探针。
- 实现文件预计 wake、ledger、lib（共享义务读模必须对齐）及四份角色说明直接相关句子；send 保持薄入口。测试全部落现有全门文件，夹具/日志仅在本副本 .qwb-tmp。
- 确认后执行 fast、定向场景、提交后一次 full，记录自然退出码、PASS/FAIL、git status 与本任务残留进程；本阶段不声称任何实现测试通过。

## 需明确的边界
- P2 描述“现有预算耗尽最终落主控”、P4 描述“已迁票现有丢失/挂起兜底”与基点实现不符；本方案把两者作为本票需要补齐的机制，请主控确认。
- 现有 planner_allowed 不含 question/answer/resume；不扩该权限，规划可按已授权工具处理技术阻塞并回报，真正用户决策仍须主控原协议。
- P6“逐字节”包含随机 ID、时间、安装脚本 SHA；差分固定这些非业务输入，保留原始输出与未过滤差异；未知真实 Herdr/模型时序只能在后续获授权真机演练验证。
