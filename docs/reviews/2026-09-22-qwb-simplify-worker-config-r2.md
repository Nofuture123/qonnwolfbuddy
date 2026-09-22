# 票③正式独立审核 r2

结论：**AMEND**。原 3 审点的生产路径返修已通过定向复核，但 r2 单引号命令直接引入旧运行时夹具不匹配，主控 full 失败。审核者为 Herdr pane `wF2:pG`，仅复审 r1 问题及返修直接引入内容，未递归派发、未改候选源码或提交。

## 冻结对象和执行口径

- 唯一需求：主仓 `tasks/2026-09-22-qwb-simplify-worker-config.md`；候选 worktree：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-worker-config`。HEAD `6bc424c7a19f01d8ce604423f0d8674675fe8ba4`，8 个 tracked 白名单文件的 binary diff SHA-256=`4d160b813ce1c3e92394e8e7383c411a315da7502c37766c740b27be093144e0`；新 `templates/workers.sh`=`5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b`，新 `tests/worker-config.py`=`1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954`。复审末重算一致，工作区仍是原 10 个候选文件。
- 执行者 r2 证据在主仓 `docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md`，SHA-256=`0a4ef8b725e560a2d73167b0af84c435750793979d38bab12584c3ece61de85f`。本审核独立运行 `python3 tests/worker-config.py` rc=0（18 条 PASS）；`git diff --check HEAD`、`bash -n bin/qwb-init.sh`、`bash -n bin/qwb-run.sh`、`bash -n tests/smoke.sh`、`shellcheck bin/qwb-init.sh bin/qwb-run.sh` 均 rc=0。追加独立运行 `bash tests/runtime-readiness.sh`，rc=1，17 PASS / 1 FAIL。主控同冻结对象的唯一 r2 full 收据 `/tmp/qwb-simplify-03-r2-full.json` 记录 rc=1、124.392 秒、候选前后未变；日志 SHA-256=`024ac4f7a24aa177d9b6225f653143e3d86807e0007c2151e7c2ff148f6866b3`，smoke 仅 1 项汇总 FAIL，源于同一 runtime-readiness 负例。本审核未重跑 full，也未运行真实 Herdr/Agent CLI 组合。

## Standards

**AMEND，1 个夹具问题。** r1 的默认唯一性断言漏洞已修：`tests/smoke.sh:2896-2914` 对 `QWB_WORKERS` 每个名字分别核对工人表与声明次数均为 1，同时拒绝未知名字，并保持默认五工人数量约束。返修直接引入的问题见第 3 审点：旧 runtime-readiness 假 Herdr 对启动命令做裸字符串比较，未随安全单引号渲染更新，使原投递失败负例提前失败。没有发现生产运行时的对应行为回退。

## Spec：原三审点

1. **pane-run argv：PASS。** `bin/qwb-run.sh:198-211` 对每个实参做单引号引用，并处理内嵌单引号；不再依赖本机 `printf %q`。`tests/worker-config.py:96-117` 经公开 `qwb-run`、假 Herdr 和真实假执行器进程捕获 `"space value"`、空串、字面 `$(...)`、`~`、`{a,b}`、`#`、`a'b`，逐项一致；该项定向测试本轮独立 rc=0。原 r1 的字面 `~` 展开反例不再出现。

2. **旧配置显式迁移：PASS。** `bin/qwb-init.sh:111-125` 只允许可证明不带旧 shell 解释的 pane-run 词，且在创建备份、新 `workers.sh` 之前拒绝 `~`、花括号、注释等；为迁移生成的 Bash 声明也使用逐项单引号引用。`tests/worker-config.py:133-170,184-219` 验证备份、0600 权限、二次幂等、迁移后 Herdr/pane-run 公开 argv，并先证明旧 pane shell 对 brace/comment/tilde 的效果，再验证迁移拒绝且原 config、backup、workers 状态不变。独立定向运行对应 3 个拒绝 PASS。

3. **安装与回归：AMEND（旧运行时夹具）。** `tests/smoke.sh:381-385` 为 GITP 夹具补 `workers.sh`；`tests/smoke.sh:1165-1181` 要求 `dir` 非空、目录存在并等于预期副本。`tests/worker-config.py:221-277` 经公开入口验证 Git 建副本与复用。已有定制 config 且缺 `workers.sh` 时，`bin/qwb-init.sh:149-169` 不 source 用户 config、不装不匹配的默认模板，明确提示手动声明；定向 sentinel 与补齐后再次升级均 PASS。这些 r1 问题已修。新问题是 `bin/qwb-run.sh:198-211` 现将 pane-run 启动文本渲染为 `'mock-agent'`，而 `tests/runtime-readiness.sh:131-139` 的假 Herdr 只将裸 `mock-agent` 识别为启动；第 294-303 行新写的 workers 声明触发 r2 路径。独立运行中假 Herdr 把启动误作提示词失败，返回 9，`qwb-run` 在启动阶段退出并关闭 tab，原本要验证的“提示词失败撤销 dispatch”路径根本未执行。主控 full 第 703、721-729 行与独立 rc=1 同因。修复：让假 Herdr 识别新的单引号启动文本，并继续检查派发前 state/scenarios-fp/dispatch 门及提示词失败后的 not-sent、tab close；独立重跑 runtime-readiness，再由主控对同一候选重跑 full。不得把失败断言删除或改成只看非零。

主控 r2 full 已有同候选 rc=1 收据；r1 的 5 项 GITP FAIL 只对应 r1 哈希。没有重开①②历史问题。

本轮计数：Standards 1 项（第 3 审点的夹具）；Spec 原 3 审点中 2 项 PASS、1 项 AMEND，最严重问题是 full 门未通过。

**REVIEW_QWB_SIMPLIFY_WORKER_CONFIG_R2 AMEND**
