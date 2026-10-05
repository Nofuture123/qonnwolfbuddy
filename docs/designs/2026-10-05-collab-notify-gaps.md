# 协作通知缺口 A–E 设计（主控已确认）

基点：`4b1f2e2f7a0f4a2a26997467d9baa894c2dd1914`。唯一规格：主账本 `tasks/2026-10-05-collab-notify-gaps.md` 及末尾最新裁决；05:25:45Z 接受三点补充前提，05:27:43Z 确认完整方案；B原话办结规则写入主控/规划说明，D摘要明确claim、land-authorize命令名。

## 已核对前提与边界
- 仅已迁票；未迁旧票的扫描、输出、票字节、Herdr 写序列保持不变。不增 watcher、不写角色 inbox、不动 claim/权限/验收条件/五值 state。
- A 确认：`handoff-pending` 明确排除 gate-assign；wake 仅在已有门禁 claim 时路由门禁。role 的 inbox 只有未读义务检查，没有投递入口。
- B 补充：send 只支持 `recipient=controller`，没有历史实际目标；不能宣称已持久记录“发给规划”。按下面的真实事件与 grant 身份限定请求。
- C 补充：现有 count>=3 判断早于 wait，且 fallback 排除已 received；只删 activity 间隔判断仍不能保证等待到期提醒。
- E 确认并补充：land-close 直接检查全部未 handled，尚未复用纯进度分类；普通 working 即使已静默也会挡它。拒绝原文两类分别是“收尾义务/用户问题仍未结”“收尾问题未恢复”，保留。
- D 选择 release 独立通知，保留原结论通知；提前知道结论仍有用，不能因门禁漏 release 而把结论一并藏住。

## A：首次授权由现有交接门铃送到门禁
- gate-assign 成功发布时，同次用 `new_handoff` 建立 `source:<授权事件ID>`，payload 明示“待接手，请先 claim”；不让主控再调用发送或手写文件。
- pending 扫描允许补齐旧 gate-assign 的同键交接；仅当前授权有效且尚未接手的那次参与通知。按最新授权事件、spec、绑定身份核对，不能仅凭 payload 或 ID 前缀。
- 授权之后已发生合法根 claim，首次接手通知即已满足；通常是绑定门禁，现主控合法接手也不能再催门禁抢 claim。用持久 claim 事件判定，释放后不重叫首次授权。
- 已删除/替换的 gate 授权不再形成首次接手义务；保留事件和已有 handoff 审计，不伪造四步 handled。A 的满足分类同步进入 due 与义务读模。
- wake 在既有测试请求/已 claim 门禁路由之后，把未接手授权交接子集送绑定门禁；混批余项保留原分流。门铃明确 claim 在 received/accept 前，不扩大门禁的 writer 权限。
- 复用两次 gate_proof；任何一次身份失效，该子集转主控并带“门禁不可用、actor/pane、原授权ID”。不向旧 pane 投递，不把未知当死亡。
- 首次授权使用既有 transport 计数/时间，最多正常三投；fallback 的原目标分类增加未接手授权门禁，耗尽升级主控及低频重提复用现有规则。
- 重启从同票事件与收据恢复；授权/交接原子发布，API 前崩溃沿用有界尝试语义，不能承诺网络严格一次。claim 后下一轮零首次门铃、零新增传输。

## B：规划办完主控请求，原子上行
- 新增来源分支：真实事件 kind=handoff-send，原 handoff 的 ID/source/seq/actor 与事件完全对应，来源 actor 等于本票 planning grant 的 identity.controller；排除自动 source 和派生结果。
- grant 可来自入口票 planning_authority 或实现票 planning.authority；办理者必须是该 grant 的本代规划，accepted/owner_fp 按原守卫核对。工人/规划自发 send、伪造正文不算主控请求。
- plan-assign 绑定的需求原话交接由规划接收、prepared 后执行 request/package 工作并读回，再 handled；主控完成授权不等于替规划办结原话。原话符合上述来源时也回报一次。
- 主控已自行 handled 的历史原话不重开、不补造规划结果；仍须显式发送新请求。无规划 grant 的 send 保留现状，不猜收件人。
- 复用 ensure_planner_result 的稳定键、结果引用及单次 publish；保留原工人阻塞分支的 payload 字节，为主控请求使用准确的“规划已办理主控请求”摘要。
- 结果识别同时支持原交接键为 send ID 或自动 source ID；从实际原 handoff 验来源、handled、accepted、op、结果摘要，不把所有 source:planner-result 前缀都当可信。
- 规划结果交主控；四个确认入口仍拒绝规划办理主控专属结果。重复 handled 不新增，上行被主控 handled 不递归；pending 同键补偿符合条件的历史规划 handled。
- 不扩规划可办理来源的权限；已有测试请求/门禁 pending-rework 的优先路由与权限保持，B 不把它们变成规划请求。

## C：本代显式等待到期立即提醒
- due 在 count>=3 前处理本代 accepted 的有效 wait：未到 wait_until 一律不催；到期且 transport_at<wait_until 时立即 due，不再叠加 activity 或普通 retry。
- 首次到期通知后，用 transport_at 去重；同一个到期 wait 后续最多每 `max(30分钟,retry-ms)` 提醒一次。传输总计仍封顶3，不能每轮重叫，也不清 accepted/prepared/op。
- 新的真实 activity 会按原协议清除或更新 wait；无 wait 的近期活动保护、旧代 owner 的恢复规则、普通未接收三投升级均保持现状。“回复迟到不是失活”仍成立，到期只提示读回结果，不推断工人死亡。
- send transport 增加受限 wait-expired 模式；writer 验本代 accepted、到期与重提间隔后，仅更新现有 transport_at/count 并记录 handoff-transport 事件，不造新 handoff。
- 收据仍在 API/宿主输出前发布；崩溃可能推迟到低频重试，不冒充已接收。每个新登记 wait 可立即提醒一次，无新 activity 时上限每30分钟一次。

## D：交还 claim 的独立通知
- 仅绑定门禁 release 本人根 claim 且 verdict=accepted/rediagnose 时，release 事件写明确状态行并同次派生 `source:<release事件ID>`；释放 child 或普通工人/规划 claim 不新增通知。
- payload 引用原 claim op、verdict、attempt/head 与最新结论事件；来源验证核 release 事件及此前真实 claim/结论序列，不能靠正文冒充门禁交还。
- 该交接固定提示主控接回；规划不能四步确认。与原 verdict 同轮到期时并入一次主控门铃，不重复调用 pane run；已经提醒过结论，释放仍有自己的新交接可叫醒。
- 主控收到后可按原入口 claim，再 land-authorize；此时不会因门禁仍占 claim 被拒。环境/候选/权限等独立门仍可能拒绝，绝不保证无条件可落地。
- pending 可从已有真实 release 事件及前序归属补齐旧已交还的通知；稳定键、三投与重启规则同 A，不新增 schema 字段。

## E：完成动作不派生同角色四步自办义务
- 在 lib 的 qwb_task_obligations_json 内扩展可信分类出口，ledger 复用；区分纯进度、已履行动作、真实待办。source/handoff 对应关系必须核对，显式 send 永不因正文相似被消音。
- 静默自办动作名单：land-authorize、land-prepare、land-apply、land-close（含恢复授权的同类事件），以及仅主控可执行且后续仍须本人对账的 recover-claim；这些命令的 writer 权限保证来源，不按当前主控 pane 猜历史身份。
- 对上述动作不新派生 source handoff；旧已生成交接不删除、不伪填 handled，仅在 due、义务读模与 land-close 的有效未结判断中排除。完整 pending/read 保留历史事实及原 handled 值。
- 其他现有自派生候选按职责保留：plan-assign/authorize、new、plan-needs/artifact/land、plan-ready/start-claim、plan-revision/revise/revise-scenarios、revision-handoff、test-request/reply、answer/resume；它们有规划就绪/依赖/规格/测试/恢复接力，不能仅因写入者当前也是主控就全吞。
- 普通 working 沿用前票静默；spec-resolved、done、blocked、needs-decision、question、not-sent、显式 send 与规划上行保留。gate-review/receipt/candidate/dispatch 等本已不派生，维持排除。
- gate-verdict 是真通知，保留；当前 accepted 结论及对应 D release 通知，在同票后续成功 land-authorize 后视为已处理，无须再手工四步。按当前 land 或 land_history 中该次授权 context 的 spec/attempt/head、授权事件顺序和原结论/释放链绑定；换候选不复活已由旧匹配授权满足的通知，不以“存在任意 land”吞历史或新结论。
- 仅对自动来源的精确结论/释放交接应用上述满足判定；其他 blocked、待答/待 resume 问题、未办理请求不受 land 授权影响。land-close 保留原两类拒绝文本和其余收尾检查。
- land-close 的未结检查复用分类，覆盖已有 handoff 与尚未 materialize 的真实 source；排除本已静默纯进度，关闭自身也不造新待办；verified 后 status 应已结。

## 数据与验收安排
- A/B/D/E 不改 events/handoffs schema；增加的都是现有形状事件/交接与读时分类。C 只增加 transport 模式参数，复用原字段；不修改 gate_context 或 land 条件摘要。
- 待确认后 A→B→C→D→E 各一个提交，每次 `bash bin/qwb-test.sh fast`；四角色说明只随对应提交更新本票相关句子。设计先单独提交，不先实现。
- A 在 tests/collab-gate.sh 复用公开角色登记/授权与 fake Herdr，先对固定起点跑“授权后首轮门铃”红证据；覆盖 claim 后静默、混批、两次身份失效、三投升级、重启。
- B 在 tests/collab-planning.sh 覆盖主控请求/原话原子回流、工人/规划伪装反例、结果专属、重放、发布失败与历史补偿；不改工人阻塞上行原断言。
- C 在 tests/collab-handoff.sh 用现有私有 writer 假钟验证19分钟不叫、21分钟叫、同轮/重启不重复、count=3仍叫、后续30分钟上限及新activity保护。
- D/E 在 tests/collab-land.sh 增加真实门禁 claim→verdict→release→主控通知→claim/authorize/prepare/apply/close，移除正常用例人工清自己动作的绕路；既有私有 Git/fake Herdr 夹具不降级。
- E 同时验证未处理工人 blocked、未答与未 resume 用户问题保留原拒绝，旧纯进度/旧自派生交接不挡收尾；绑定不符的历史 verdict 不被新授权误吞。
- 新增行为断言各在起点红、候选绿；仅用本副本 .qwb-tmp 的私有运行时切换基点脚本。保留进程登记、失效关闭、短 socket 夹具，不碰真 Herdr/模型。
- 八场景逐项报告；单跑所有改动测试及 planning/handoff/gate/land/test-policy/wake-block-output，记录命令、rc、grep -c '^PASS' / '^FAIL' 与日志。不跑仓库 full。
- 未命中 A–E 的已迁票复用 planning 冻结同路径/时间/随机源的字节对照；未迁票复用 wake-block-output 基点接口；比较 stdout/stderr/rc/票/Herdr 写序列，不过滤业务差异。
- 改测试后逐文件名搜索 tests/smoke.sh、tests/collab-all.sh 及关联组数断言，按实际 PASS/组数更新；完成行说明搜索范围与确切改动。设计阶段只跑快门，不声称八场景已验收。
