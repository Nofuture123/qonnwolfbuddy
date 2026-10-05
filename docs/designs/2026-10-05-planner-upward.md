# 规划交接向主控回流设计（按 2026-10-05T02:53:19Z 主控裁决收窄）

基点：`d66d77cba3357179a5a4820e97c8a928c72a4312`；初稿提交 `eae86b0`。唯一规格为主账本及上述裁决。

## 范围与现状
- 本票做 P1、P3、P2 的 handled 原子结果上行，以及规划不能办理主控专属来源的 writer 守卫；迁入核查归主控。
- 不做 P4、工人丢失/停滞兜底、plan-watch、预算耗尽升级、义务读模修改；工人 working 仍门铃规划，三次后仍 pending 且不升级。
- 基点 `collect_due` 的已迁分支提前 continue，确无丢失/停滞兜底；`handoff_due` 三次后停止 due，并没有自动升级。这两个缺口另票处理。
- 基点路由优先级：匹配测试请求→测试体系（余项主控）；有效 claim 且 pending/rework→门禁；否则规划授权→整票规划；其余→主控。
- 因而工人 done、迁入核查、accepted/rediagnose 后续交接会误给规划；规划 handled 后原事件关闭，无主控上行。
- dispatch 记录 pane/op；append 事件保存真实 actor/op/kind；question 没有 op，须按事件之前最近一次匹配 pane 的真实 dispatch 识别工人来源。

## 路由与权限
- 保留 events/handoffs schema、字段、received/accept/prepared/handled 语义、单监督、主控锁与两次 gate_proof。
- `qwb-ledger.sh` 内共用真实来源分类：自动 source 交接+派发历史绑定工人；不依据 payload 或可自选的 event_id 前缀判权。
- `handoff-pending` 为需交主控的规划票事件增加瞬时 `controller_hint`（不持久化进 schema）；wake 仅把这部分留主控，规划子集仍按原 proof 路由。
- `record_transport` 只扣实际子集的预算；同票 done+blocked 同轮分别通知主控和规划，完整 event_id 不丢失。
- P6 优先分支保持：已 claim 的 pending/rework 门禁照旧接整批；有匹配测试请求的批次保留既有输出/切分，不添提示。
- `planner_controller_hint` 同时供 writer 使用：拒绝规划 received/accept/prepared/handled 主控专属事件；pending 仍返回完整未办理集合。
- 规划 request/ready/working/blocked/needs-decision/question 照旧；迁入核查交主控。
- P1 摘要：`① example(running) 工人已交付；下一步：主控安排门禁；最近: [qwb-handoff] ...`；保留原 payload 和 event_id。
- P3 在既有优先分支之后截住 accepted/rediagnose，剩余交接归主控；不改验收门、claim、五值 state 或落地授权。
- P3 摘要：`① example(running) 门禁 accepted；下一步：主控安排落地/清理；最近: ...`；rediagnose 对应“主控安排技术重诊”。

## P2：规划 handled 原子派生结果
- 选择 handled 同次发布上行，避免模型主动 send 的遗漏与 handled→send 崩溃窗口；不新增监督者或命令。
- 仅规划真实办理的工人 blocked/needs-decision/question 自动交接派生；request/ready/纯进度不额外上报，不扩规划 answer/resume/state/验收权限。
- 原 handled 通过身份、op、prepared、result_ref 内容与路径校验后，在同一原子 publish 中创建上行 handoff。
- 新 ID/corr=`source:planner-result:`+原 handoff ID 的 SHA-256，attempt=1；source_event/source_seq/source_actor 仍引用原真实来源。
- payload 保存原交接 ID、规划 actor 与 pane/op、result_ref、result_sha256；结果正文仍由既有 result JSON 承载。
- 示例：`规划已办理工人阻塞/决策；原交接 source:blocked-1；actor=planner pane=planner-pane op=handle-1；result_ref=项目内路径；result_sha256=实际摘要；请主控读回结果。`
- 派生来源识别同时核原 handoff、handled/accepted 归属与结果摘要，不只认 ID 前缀；source: 仍禁止普通 send 占用。
- 不回改已存在结果；重复 handled 返回既有结果，冲突拒绝；主控办理上行不再派生。pending 可按同键补偿历史已 handled 而无上行的数据。

## 幂等与恢复
- 原交接关闭与上行创建共用唯一 writer 的锁/原子发布；发布前失败两者皆不落盘，发布后重试同键不造第二条。
- 规划换代失效仍双 proof 回主控，原 accepted/prepared/op 不自动移交；主控换代按 owner_fp 与既有 reconcile/旧 owner 死亡证明恢复。
- 值守重启读完整同票 events/handoffs；API 传输成功不冒充 received/handled，预算/activity/wait 原义不变。
- 保证业务交接幂等；传输仍为有界至少一次，API 后崩溃可能重复门铃，不能宣称严格一次。

## 测试与交付
- 有效验收：场景1（done直达）、2（blocked先规划、结果上行）、4（accepted）、6（身份回落）、7（兼容字节），新增主控专属 handled 拒绝且票字节不变；原场景3/5不在本票。
- `tests/collab-planning.sh` 最小扩展：真实公开授权/派发与 fake Herdr；混合来源、用户伪装正文、working保持、question、结果重放、专属来源四入口拒绝、accepted、失效身份与恢复。
- 复用既有 `collab-handoff`、`collab-gate`、`collab-test-policy`：三次预算、wait/prepared接班、单监督、pending/rework claim、测试请求优先级保持原断言。
- P1 同一新增用例在 d66d77c 为红，在候选为绿；P6 私有同路径夹具固定时钟/随机输入并比较 stdout/stderr/退出码/票字节/Herdr 调用，不过滤业务输出。
- 不修改 lib、run、herdr 或 new 票正文；只改 wake、ledger、现有测试、此设计及四份角色说明相关句子。
- 至少三次提交：路由+设计；派生+writer守卫；角色说明。运行 fast、定向用例，提交后一次 full；日志仅本副本 .qwb-tmp，记录退出码/PASS/FAIL/工作区/残留进程。
- 真实 Herdr 与模型会话仍禁止；本票测试不声称真机演练已通过。
