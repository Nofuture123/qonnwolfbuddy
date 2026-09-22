# 五张简化票交付与验收

记录时间：2026-09-22T19:17:45.963753+00:00。①→⑤逐票执行并验收，全部实现已进入本地 main。用户已授权推送；本文件不提前宣称远端成功。

生产修复、三项流程改进与 Gardening 已验收成果均保留。未部署、发版、安装整套 pstack 或自动升级其他项目。预存 docs/plans/ 草案不纳入本次提交。

执行使用现有 Herdr Sol medium 会话，独立审核使用现有 Sol high 会话；未创建 pane。复用 [Herdr 技能](/Users/rocky/.agents/skills/herdr/SKILL.md) 完成交接和审核回收。

## ① 唤醒入口

- 实现：`239c2ceaabe9a4e8e01ad942dbd3f2c1e1fd5afb`；[实际 diff](https://github.com/Nofuture123/qonnwolfbuddy/commit/239c2ceaabe9a4e8e01ad942dbd3f2c1e1fd5afb)。
- 改动文件：`README.md`、`README.zh.md`、`docs/DECISIONS.md`、`templates/QWBUDDY.md`、`templates/agents-hook.md`、`templates/claude-hook.md`。
- full：实际执行 `bash bin/qwb-test.sh full --project <当票候选绝对目录>`，rc=0，109.200s，候选前后身份一致。
- 收据：`/tmp/qwb-simplify-01-r2-full.json`；日志：`/tmp/qwb-simplify-01-r2-full.log`。
- 结果与未覆盖：六场景走读及隔离安装通过；真实Pi reload、Claude Stop及本轮精确180000ms等待未覆盖。
- 详细账本：[任务与审核记录](../../tasks/2026-09-22-qwb-simplify-wake-entry.md)。

## ② 账本读取

- 实现：`bb86f960a87d846508f054cf46709bf18fee32fa`；[实际 diff](https://github.com/Nofuture123/qonnwolfbuddy/commit/bb86f960a87d846508f054cf46709bf18fee32fa)。
- 改动文件：`bin/qwb-lib.sh`、`bin/qwb-lint.sh`、`bin/qwb-run.sh`、`bin/qwb-status.sh`、`bin/qwb-wake.sh`、`bin/qwb-worktree.sh`。
- full：实际执行 `bash bin/qwb-test.sh full --project <当票候选绝对目录>`，rc=0，111.614s，候选前后身份一致。
- 收据：`/tmp/qwb-simplify-02-full.json`；日志：`/tmp/qwb-simplify-02-full.log`。
- 结果与未覆盖：39组公开CLI差分、九类尾部事件、隔离安装升级与缺库诊断通过；未新增真实Herdr派发验收。
- 详细账本：[任务与审核记录](../../tasks/2026-09-22-qwb-simplify-ledger-parsing.md)。

## ③ 工人配置

- 实现：`f649a2d023e7235c44e458e6a528c723942fb42a`；[实际 diff](https://github.com/Nofuture123/qonnwolfbuddy/commit/f649a2d023e7235c44e458e6a528c723942fb42a)。
- 改动文件：`README.md`、`README.zh.md`、`bin/qwb-init.sh`、`bin/qwb-run.sh`、`templates/QWBUDDY.md`、`templates/config.sh`、`templates/workers.sh`、`tests/runtime-readiness.sh`、`tests/smoke.sh`、`tests/worker-config.py`。
- full：实际执行 `bash bin/qwb-test.sh full --project <当票候选绝对目录>`，rc=0，174.067s，候选前后身份一致。
- 收据：`/tmp/qwb-simplify-03-r3-full.json`；日志：`/tmp/qwb-simplify-03-r3-full.log`。
- 结果与未覆盖：argv/显式迁移18项和runtime定向18项通过；复杂旧shell配置仍需人工处理，真实多CLI组合未覆盖。
- 详细账本：[任务与审核记录](../../tasks/2026-09-22-qwb-simplify-worker-config.md)。

## ④ 可选路由

- 实现：`5104dfde94fe8be04c5973a2c66f55dc788e9b7f`；[实际 diff](https://github.com/Nofuture123/qonnwolfbuddy/commit/5104dfde94fe8be04c5973a2c66f55dc788e9b7f)。
- 改动文件：`bin/qwb-dispatch.sh`、`bin/qwb-run.sh`、`templates/QWBUDDY.md`、`tests/optional-routing.sh`、`tests/smoke.sh`。
- full：实际执行 `bash bin/qwb-test.sh full --project <当票候选绝对目录>`，rc=0，123.370s，候选前后身份一致。
- 收据：`/tmp/qwb-simplify-04-r2-full.json`；日志：`/tmp/qwb-simplify-04-r2-full.log`。
- 结果与未覆盖：19项定向通过，显式工人零路由读取及坏规则零副作用通过；HTTP与Herdr为假件，真实API未调用。
- 详细账本：[任务与审核记录](../../tasks/2026-09-22-qwb-simplify-optional-routing.md)。

## ⑤ 按需说明

- 实现：`bd520d7b4432c4e939846eeb8ce685d451966b9b`；[实际 diff](https://github.com/Nofuture123/qonnwolfbuddy/commit/bd520d7b4432c4e939846eeb8ce685d451966b9b)。
- 改动文件：`bin/qwb-init.sh`、`templates/QWBUDDY.md`、`templates/ci-guide.md`、`templates/host-watch-guide.md`、`templates/roles/主控.md`、`templates/worker-launch-guide.md`、`tests/on-demand-guide.py`、`tests/smoke.sh`。
- full：实际执行 `bash bin/qwb-test.sh full --project <当票候选绝对目录>`，rc=0，171.121s，候选前后身份一致。
- 收据：`/tmp/qwb-simplify-05-full.json`；日志：`/tmp/qwb-simplify-05-full.log`。
- 结果与未覆盖：四场景独立通过：普通任务接手、专项可发现、缺失错链与安全安装负例、缩短且责任保留。真实宿主接入与并发目录替换攻击未覆盖。
- 详细账本：[任务与审核记录](../../tasks/2026-09-22-qwb-simplify-on-demand-guide.md)。

## ⑤补充证据

- 独立审核：[r1 PASS](2026-09-22-qwb-simplify-on-demand-guide-r1.md)；[执行报告及更正](2026-09-22-qwb-simplify-on-demand-guide-execution.md)。
- 固定基线 8df36a6；tracked diff SHA256 d77841129709b0a863d4bb8f042de91dbf77c1e4c1511f0daf16de559fa4f3e3，四个新文件hash见审核报告。最终实现提交文件字节与该对象相同。
- 主控本轮 fast 实际运行逐文件 bash -n 与 ShellCheck，rc0，1.842s。原执行报告“配置为空”错误已追加更正，不补造旧回合执行。
- 主控 full 包含 SMOKE PASS、REVIEW-IDENTITY PASS、LINT PASS；正式审核未并发重跑 full。
- 非空白 Unicode 码点（包含标点、Markdown、命令字符）：根说明10290→6615，根+主控11088→7578；首次接入含宿主专项9272，CI触发含专项8195。不是token统计。
- 执行者退出并离开工作目录后，实际 qwb-worktree.sh finish --merged 成功，分支和任务worktree已收尾。
