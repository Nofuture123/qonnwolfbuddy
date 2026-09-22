# ④ 可选路由结构化接口正式独立审核 r1

**结论：AMEND。** 审核者为 Herdr pane `wF2:pG`（Sol high），未递归派发。唯一需求为主仓 `tasks/2026-09-22-qwb-simplify-optional-routing.md`；执行报告为主仓 `docs/reviews/2026-09-22-qwb-simplify-optional-routing-execution.md`。仅审本轮候选，未重审①②③已验收成果。

## 冻结范围与验证

- 候选 worktree：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-optional-routing`；HEAD `e74a7edaa62303a49c99c272ca2e6fd26436659b`。`git diff -- bin/qwb-dispatch.sh bin/qwb-run.sh templates/QWBUDDY.md tests/smoke.sh | shasum -a 256` = `03a5fd04f0c7c612457858cfad71558db084d07512c10e2503711fabf593f0f3`；未跟踪 `tests/optional-routing.sh` 全文已审，SHA-256 `494679707d11d5d64eba294b0618bce187552373f89296de1754741e6b0be25a`。候选文件与交接白名单一致。
- 独立运行 `bash tests/optional-routing.sh`：exit 0，15 项 PASS；`bash bin/qwb-test.sh fast`：exit 0；`shellcheck bin/qwb-dispatch.sh bin/qwb-run.sh tests/optional-routing.sh`、逐文件 `bash -n`、`git diff --check`：exit 0。另对整个 `tests/smoke.sh` 跑 ShellCheck 为 exit 1，输出大量提示；该单独命令未作为本轮通过证据。未运行 full、真实 Herdr 派发或真实 API；定向测试使用假 HTTP/假 Herdr。
- 三个审点：显式 worker 在 `bin/qwb-run.sh:153` 的 auto 条件之外；`tests/optional-routing.sh:111-127` 的显式负控与 auto 正控分别检查 dispatch、`.env` 读取和 curl 调用。`bin/qwb-run.sh:158-188` 只解析同一 `DP_OUT` 的 JSON，`bin/qwb-dispatch.sh:109-126,211-215` 从规则快照生成结果及默认工人；四态与诊断文本负例在新测试中覆盖。坏规则、非法结构、未知工人的前置拒绝测试在 `tests/optional-routing.sh:147-193`，且由 `tests/smoke.sh:2306` 接入。下述缺口属于第三审点。

## Standards

0 项本轮新问题。改动局限于路由接口、消费端、配置说明和相应测试，未发现与仓内约定相冲突的新增标准问题。代码气味基线未构成需单列的本轮问题。

## Spec

1. **AMEND：空文件或串接两个 JSON 对象的规则快照被当成有效配置。** 任务书 §0、§1 要求损坏规则失败关闭、坏规则在派发预检中拒绝；模板说明也承诺坏规则 exit 2。`bin/qwb-dispatch.sh:114-126` 的 `jq -r` 校验在零个输入时成功且无输出，在多个有效对象时逐个校验成功，未约束规则快照恰为一个对象。随后 `:128-137` 的无 key 分支返回 exit 0 的 `off`。独立隔离复现：空规则文件、无 key、`--json` 得到 exit 0、`{"status":"off","default_worker":""}`；两个有效对象串接则得到 exit 0、`{"status":"off","default_worker":"pi\\npi"}`。没有联网或真实凭据。上层 `qwb-run.sh` 会因默认工人非法而拒绝，因而未观察到实际派发副作用；但直接 `qwb-dispatch.sh` 的坏规则分类与单一已验证快照契约均不成立，且上层报“结构化结果非法”而非配置错误。修复：规则快照校验时强制恰好一个顶层 JSON 对象，再提取默认工人；在 `tests/optional-routing.sh` 补空文件和多对象、无 key、exit 2 且零 curl/派发副作用的定向负例。

本轮计数：Standards 0；Spec 1（最重为坏规则分类与快照契约缺口）。审核未改候选源码、未提交。

**REVIEW_QWB_SIMPLIFY_OPTIONAL_ROUTING_R1 AMEND**
