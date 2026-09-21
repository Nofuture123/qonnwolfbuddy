# 任务：移植 firstmate 的 JEV 自动派工到 qwbuddy（bin/qwb-dispatch.sh）

```
任务 id:  jev-dispatch
state:    verified
日期:     2026-09-17
派发:     主控（Pi）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-17-jev-dispatch.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/jev-dispatch
分支:     jev-dispatch
```
## 背景与源实现

- 源文件（先通读）：`/Users/rocky/projects/firstmate/bin/fm-dispatch-resolve.sh`（404 行 bash），
  契约文档：`/Users/rocky/projects/firstmate/docs/configuration.md` 搜 "Typed dispatch resolution"。
- JEV = typesafe.ai 的 System One 模型（`jev-latest`）。它不是对话式 LLM，而是校准分类器：
  给它一段 state（任务简报）和一个 choice 问题（每个选项=一条规则的匹配条件文本），
  返回 `{choice, confidence, probabilities(各选项和为1)}`。实测单次 123–348ms，约 800 in / 60 out tokens。
  端点：`POST https://api.typesafe.ai/v1/systemone`，body 形如
  `{model:"jev-latest", state:{task:{project,brief}}, questions:{rule:{type:"choice", instructions, criteria:{rule_1:..., rule_2:..., default:"No listed rule applies to this task."}}}}`。
- 设计精髓：**模型只回答"该走哪条规则"这一个问题；置信度门槛、后续决策全部是纯代码（jq）**。
  模型永远看不到额度、审批等策略数据。

## 移植范围

新增 `bin/qwb-dispatch.sh`，并把 firstmate 特有的部分全部删掉（多 profile、quota-axi、floor、spendPriority、
harness 校验表、captain 审批流——这些是 firstmate 机队特有的，qwb 派工只是"选一个工人"）：

1. **开关（opt-in）**：`TYPESAFE_API_KEY` 取进程环境变量，否则读项目 `.env`；两处都无 →
   stderr 打一行 `qwb-dispatch: off`，exit 0，零网络调用，行为与今天完全一致。
2. **规则文件**：`config/dispatch-rules.json`（模板放 `templates/dispatch-rules.json`）。schema 最小化：
   ```json
   {
     "rules": [
       {"when": "复杂架构、跨模块重构、高风险改动", "worker": "codex"},
       {"when": "常规实现、机械改动、调研", "worker": "pi"},
       {"when": "代码审核、对抗性审查", "worker": "claude"}
     ],
     "default": {"worker": "pi"}
   }
   ```
   jq 校验结构（rules 数组、每条非空 when + 合法 worker、default 存在）；坏文件 exit 2（配置错误，
   不许被绕过或静默跳过）。
3. **请求**：与上游同形（state 带 project + 全文 brief；一个 choice 问题）。key 安全纪律照抄上游：
   key 只存一个 shell 变量、经文件描述符 `3< <(...)` 传给 curl 的 Authorization 头、
   启动任何子进程前 `unset TYPESAFE_API_KEY`；不打印、不落日志、不落盘。
4. **后处理（纯 jq/bash，无模型参与）**：
   - `confidence < 0.6` → `status: ambiguous`（附完整 probabilities，人工裁决）
   - 命中某条 rule → `status: clear` + `worker: <name>`
   - 选了 default → `status: clear` + default worker
   - 网络/API 错/响应不合法（choice 不在选项集、probabilities 键不全或和≠1、confidence 越界）→
     `status: error` + 原因
   - **永远 exit 0**（只有 usage/配置错误 exit 2）——派工流程永不被这个工具卡死
5. **输出**：TOON 风格文本块（status / model / latency_ms / tokens / rule+when 摘录 / confidence /
   probabilities / worker），主控可直接读。
6. **qwb-run.sh 集成**：worker 参数支持 `auto`——调用 qwb-dispatch.sh 解析；返回 off/error/ambiguous
   时按现有默认工人继续派发并在 stderr 一行说明。不许阻塞派发。
7. **测试**：沿 `tests/` 现有写法加 fake curl（上游 tests 里有 FAKE_CURL_MUTATE_SOURCE 手法可参考，
   在 firstmate 仓 `tests/` 搜）。覆盖：off 门、clear、ambiguous、坏规则文件、响应校验、
   key 不出现在任何子进程环境。全部通过。
8. **质量门**：`bin/qwb-lint.sh` 与 `bin/qwb-test.sh` 全绿（本仓 Definition of Done）。

## 边界

- 在 `.worktrees/jev-dispatch/` worktree 里干活，不动主工作区；完成后分支留在 worktree 等验收。
- **key 纪律**：真 key 只许从 `~/projects/jev/.env` 读入内存做一次活体冒烟（真调一次 API，
  用一条明显命中的规则验证 clear 输出），验证完即弃；严禁把 key 写进 qwb 仓任何文件、测试或日志。
- bash 3.2 兼容（上游在 bash 3.2 空数组展开上栽过跟头，`set -u` 下注意）。
- 不引入 jq/curl 之外的新依赖。
- 最小实现：不做上游没被本任务引用到的功能，不顺手重构别的文件。

## 验收（Given/When/Then）

1. Given 未配 key，When 运行 `qwb-dispatch.sh <brief>`，Then stderr 一行 off、exit 0、无网络请求。
2. Given 配 key + 合法规则 + 明确命中的任务简报，When 运行，Then `status: clear` 且 worker 与规则一致。
3. Given 置信度 < 0.6，When 运行，Then `status: ambiguous` 且 probabilities 完整打印。
4. Given `qwb-run.sh` 传 `auto` 且 dispatch off/error，Then 派发照常落到默认工人并有一行 stderr 说明。
5. `bin/qwb-lint.sh`、`bin/qwb-test.sh` 退出码 0。
working: 2026-09-18T15:14:40Z 移植完成，等验收。worktree=.worktrees/jev-dispatch 分支=jev-dispatch（bf5de3d）；bin/qwb-dispatch.sh + templates/dispatch-rules.json + qwb-run --worker auto + smoke §49；质量门 bin/qwb-test.sh full 全绿（SMOKE/REVIEW-IDENTITY/LINT PASS，468 PASS/0 FAIL/exit 0）；活体冒烟真调 1 次 API：status clear、rule_1→codex（confidence 1.0，770ms）；key 只从 ~/projects/jev/.env 读入内存、未落仓、已弃（grep 零残留）
done: 2026-09-21 Rocky 授权合并。已跑 bin/qwb-test.sh full 全绿通过（468 PASS / 0 FAIL），验证端到端场景正常，正式合入 main。
worktree: merged branch=jev-dispatch tag=-
