# 生产整合 full 后 smoke 夹具返修独立复审

**结论：PASS。** 固定基线 `6e9b0f2b0b307357445ecaf24b8c947d424dd257`，候选 `4dbc28a73b01966e520f6b5b213ae3e6e8bee691`（直接父提交即基线）；唯一变更白名单为 `tests/smoke.sh`。仅核对新增 diff 与 `qwb-wake.sh`/`qwb-run.sh` 的直接运行时契约。主控首次 full 的 `/tmp/qwb-production-final-full.log` 记录 `rc=1`、12 FAIL，这是历史运行证据，本轮未重跑 full。候选 `git archive` 中 `tests/smoke.sh` 的 SHA-1 与 `git show 4dbc28a:tests/smoke.sh` 一致：`4921bf833f73c795fb8bb6d89ea3f3b44314b343`。

## 1. workspace 夹具与新契约：PASS

`tests/smoke.sh:1541-1544` 给 §42c 的 status 调用补齐与 `ensrun` 一致的 `HERDR_WORKSPACE_ID=wtestW`/`HERDR_PANE_ID=wtest:ctl`；否则 `resolve_workspace` 无项目匹配时按调用者 workspace 回退，旧日志正是把 `workspace=wtestW` 的登记报成“目标不符”。`:1719-1730` 将 §45a 的候选 pane list 与 pane get 同设 `wtestW`，仍保留“目标主控错误时拒绝、目标一致时复用”的正反断言。候选归档的定向驱动覆盖 §42a-c、§45a，`rc=0`、无 FAIL（`/tmp/qwb-smoke-r1-candidate-targeted.log`）。使用假 Herdr，未实测真实跨 workspace。

## 2. `agent get` 按 pane/name 桩：PASS（限本轮场景）

`tests/smoke.sh:125-131` 修正 heredoc 中第 3 参数的转义；生成后的 stub 确实使 `agent get w93:p7` 返回成功，名称 `qwb-disp` 返回失败。§47 成功路径仍核对 `pane run w93:p7 cmd`、至少三次 `agent get w93:p7`、随后同 pane 的 rename/提示词和最终 dispatch；99 次失败路径仍精确跑到 300ms，并进入失败记账。候选归档定向 §47、§51e 全部 PASS（`/tmp/qwb-smoke-r1-candidate-targeted.log`），完整 full 的相应场景也通过。新增 diff 未发现被桩掩盖的当前运行时问题。

**未覆盖的假件边界：** 原有 `agent-get-cmd.json` 的 `pane_id` 固定为 `wAB:p3`，而本轮启用的 `*:*` 回退会让任意形如 pane ID 的查询返回成功；隔离探针中 `agent get wOther:pBad` 为 `rc=0`（`/tmp/qwb-smoke-r1-stub-probe.log`）。这不能证明真实 Herdr 对任意 pane 的身份校验，也不作为本轮真实回归：本轮 §47 断言已核对运行时实际查询的是预期 `w93:p7`，并另有始终查不到时的超时反例。将来若要用此桩验证“查询错误 pane 必须失败”，需另加按目标身份的定向夹具。

## 3. timeout 失败记账与清理断言：PASS

`tests/smoke.sh:1920-1937` 仍要求 300ms 假时钟精确超时、非零退出、包含 pane 与排查命令、没有第二次 `pane run`；新增核对 `not-sent:` 原位标记、`blocked:` 失败记录、无残留 `dispatch:`，以及关闭本次新 tab。直接依赖 `bin/qwb-run.sh:749-777,820-823` 正是超时后执行该记账和清理的现行契约。旧“保留完整 dispatch”断言的历史记录目的由 `not-sent:` 保留 worker/pane 与追加 `blocked:` 承接，原失败路径并未被删除。候选归档的 §47 定向为 `rc=0`，这些断言均打印 PASS（`/tmp/qwb-smoke-r1-candidate-targeted.log`）。

## 本轮命令与未覆盖

- 从候选归档运行与原 `smoke.sh` 同段抽取的定向驱动：`bash /tmp/qwb-smoke-r1-candidate-driver.sh` → `rc=0`、`TARGETED FAILS=0`；覆盖 §42a-c、§45a、§47 全段、§51e，未覆盖 §42d-j、§45b-f、§51 其余项。驱动日志留 `/tmp/qwb-smoke-r1-candidate-targeted.log`。
- `bash -n tests/smoke.sh` → `rc=0`；`shellcheck -S error tests/smoke.sh` → `rc=0`；冻结增量 `git diff --check` → `rc=0`（ShellCheck 日志 `/tmp/qwb-smoke-r1-static.log`）。本审核未独立运行完整 smoke/full 或真实 Herdr/Pi。主控补充称候选完整 full `rc=0`、110.168 秒；`/tmp/qwb-production-repaired-full.log` 可见 `SMOKE PASS`、`REVIEW-IDENTITY PASS`、`LINT PASS` 且无 `FAIL` 行，耗时与进程退出码采用主控记录。三张改进票未激活。本轮未改候选源码、未创建窗口或派发。

PASS
