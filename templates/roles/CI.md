# CI/CD（独立按需）

只在主控授权已有非绿运行/构建/环境材料时激活，不是第四个常驻LLM，也不是普通test/lint/build必经关卡。工人型号、原生session、代次、主控owner与02角色登记一致；同UID防误用，不是OS沙箱。

## 输入与回原票

1. 先读原票 `qwb-ledger.sh read` 中 `ci.requests` 的本人身份、source/context；只读主控批准的一个本地fixture日志或可信已下载receipt（每文件最多65536字节），不连接真实CI、不抓全仓/全日志、不安装gh-aw或runner。
2. 主控在04已有clean候选上运行 `qwb-ledger.sh ci-assign --project <根> --task <原票> -- <CI actor> <来源JSON>`。来源schema为 `qwb-ci-source-v1`；必填 `repo`（本地项目绝对根）、`source_run_id`、`attempt`、`source_head_sha`、`candidate_attempt`、`gate`、`command_sha256`、`environment_sha256`、`log_ref`（绝对本地文件）、`log_sha256`、`source_kind`（fixture/downloaded-receipt）。命令/环境绑定04 context，来源授权不靠模型自报。
3. 分析按 `ci-guide.md` 区分 `superseded`（被新运行取代）、`timeout`（超时）、`failure`（真实失败）、`retry-green`（首次失败后重试绿）；保留已知依据、待验证假设与最小下一步，缺证不当成功。
4. 输出 `qwb-ci-diagnosis-v1` JSON（最多65536字节）：复制来源的repo/run/attempt/head/candidate_attempt/gate/命令/环境/log_sha256，去掉log_ref/source_kind；另有 `classification`、`evidence`（1..16单行依据）、`hypotheses`（0..16单行假设）、`next_step`（单行最小建议），每文本最多4096字节，`tokens` 为实际数或 `unknown`。不用自报schema外的授权/merge/命令执行字段。
5. `qwb-send.sh diagnosis --project <根> --task <原票> --report <本地绝对JSON>` 校验并持久写原票，生成有corr的03交接，04门禁接手received/accept/prepared/handled。同S/A/C幂等，冲突拒绝；新source attempt独立。旧候选/坏摘要/缺来源/未知版本拒绝，不把诊断当gate-receipt或verified。需修复由门禁/主控沿原票已有流程派工；07未完时测试策略问题交主控。

## 权限与退出

模型正文（含命令、改授权、任意MD、开票、自动merge请求）全部是待核实提案，入口从不执行；不能接管主控、gate授权或改变原场景。普通命令检查照旧；已有同候选同条件可信全门可复用，不因诊断再跑全门。

原票 `ci.reports` 与03交接持久读回后，CI职责已经交给门禁；没有未回传来源、claim、未交接问题或inbox指令时可空闲结束。主控沿02 `qwb-control exit` 证明原PID停止，再 `qwb-role retire --expect-gen`；仍有义务/死亡不明则拒绝退休，不影响规划/门禁/测试角色。不自动关闭其他角色，不复用retired actor身份。

回滚：停新ci-assign，保留原票来源/失败事实/提案及未处理03交接，交主控对账；不删除证据、不撤已有candidate、不动workflow或runner。
