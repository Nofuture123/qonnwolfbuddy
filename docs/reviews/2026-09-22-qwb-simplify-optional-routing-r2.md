# ④ 可选路由结构化接口正式独立审核 r2

**结论：PASS（仅 r1 唯一 AMEND 的返修）。** 审核者为 Herdr pane `wF2:pG`（Sol high），未递归派发、未修改候选源码或提交。需求仍为主仓 `tasks/2026-09-22-qwb-simplify-optional-routing.md`；执行报告 r2 追加段见主仓 `docs/reviews/2026-09-22-qwb-simplify-optional-routing-execution.md`。①②③及 r1 已结范围未重开。

## 冻结身份与范围

- 候选 worktree `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-optional-routing`；HEAD `e74a7edaa62303a49c99c272ca2e6fd26436659b`。`git diff -- bin/qwb-dispatch.sh bin/qwb-run.sh templates/QWBUDDY.md tests/smoke.sh | shasum -a 256` = `346b86073418cb4afb8a6f5d60dda3e95836988752990fbc32037c56e1c70864`；未跟踪 `tests/optional-routing.sh` SHA-256 = `e3656f8a5c7bd789f4752c4d3995ad3190110fdae6a83a2656322290d8743463`。复核与交接一致。
- 对照 r1 冻结差异与本轮执行报告，直接相关返修为 `bin/qwb-dispatch.sh:114-115` 的单对象计数门，以及 `tests/optional-routing.sh:50-65,178-191` 的空文件、双对象直接 CLI 和上层 auto 负例。其他白名单改动沿用 r1 候选；本轮只对上述返修作判断。

## Standards

**PASS，0 项新问题。** `jq -s 'length'` 在既有 schema 检查前约束输入数量；不改变后续已验收字段规则，也没有引入额外服务、路由路径或重复接口。新增测试沿用该文件的假 HTTP、假 Herdr、隔离项目与统一前置拒绝检查。

## Spec

**PASS，r1 唯一问题已闭环。** `bin/qwb-dispatch.sh:114-115` 在规则快照为空或含两个 JSON 值时以 exit 2 拒绝，之后才提取默认工人及进入无 key 的 off 门；恰好一个顶层值仍由原 schema 校验为对象。独立隔离复现：无 key 时，空文件和两个有效对象串接均为 exit 2、stdout 空、stderr 指向规则文件；有效单对象为 exit 0，输出 `{"status":"off","default_worker":"pi"}`。

独立运行 `bash tests/optional-routing.sh`：exit 0，19 项 PASS。新增直接 CLI 负例断言 exit 2、stdout 空、零 curl；新增 auto 负例在默认 worktree 模式断言 exit 2、配置错误、任务书 shasum 不变、零 Herdr、零 `.worktrees`、零 curl。`shellcheck bin/qwb-dispatch.sh tests/optional-routing.sh`、两文件 `bash -n`、`git diff --check` 均 exit 0。执行者报告中的 red exit 1、green 19 PASS 与 fast exit 0 属执行者证据，本审核未重跑 fast；主控 r2 full 正在运行，未将其结果计入本报告。未使用真实 key、真实 API 或真实 Herdr 派发。

本轮计数：Standards 0；Spec 0 个剩余问题。

**REVIEW_QWB_SIMPLIFY_OPTIONAL_ROUTING_R2 PASS**
