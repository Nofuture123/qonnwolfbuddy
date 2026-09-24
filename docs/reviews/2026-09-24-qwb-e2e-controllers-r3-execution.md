# QWB 三主控真实 E2E r3 执行记录

- 起点：`c289b831f270369a348271a9ba24cd3e2b2d2993`；r3 任务书随第一笔提交入库。
- `README.md`、`README.zh.md`：晚获锁和 exit 2 后恢复值守均写为等待 Pi 的 `agent_settled`；中英文含义一致。
- `docs/DECISIONS.md`：追加 §四十一，记录 Pi 空闲边界、`--block` 摘要输出、Claude/Pi 结束回合规则及 Codex E2E 的 `service_tier="default"` 与无 fast 断言；明确取代旧节中相应的 `turn_end` 设计，旧节保留。
- 变更范围核对命令：`git diff --stat c289b831f270369a348271a9ba24cd3e2b2d2993 HEAD`。范围只含以上三份文档和 `docs/reviews/` 内的 r3 任务书、执行记录；`bin/`、`templates/`、`tests/` 均未改。
- 最终 SHA 后验门：`bash bin/qwb-test.sh fast --project . --report /tmp/qwb-e2e-controllers-r3-fast.md`，原始退出码 **0**；`bash bin/qwb-test.sh full --project . --report /tmp/qwb-e2e-controllers-r3-full.md`，原始退出码 **0**。报告文件记录执行前后 SHA 与工作区状态。
- 未重跑真实 E2E；本轮只修改文档，不改变已复验的主控实现或安装模板。
