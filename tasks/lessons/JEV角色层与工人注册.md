# JEV 角色层与工人注册

## 现象

把分类和工人写在一条规则里，额度变化就要改稳定的分类表。把候选耗尽写成普通 `status:error`，现有 auto 又会回退到 default，仍可能派错人。

## 根因

任务分类、可用工人、启动参数属于不同层。模板 `workers.sh` 的旧名字只是兼容工人启动定义；`config.sh` 的 `QWB_WORKERS` 决定项目注册名单。两者都不是 JEV 的五分类。

## 对策

Rocky 2026-09-27 定“分类稳定、agent 易变”：`rules[].worker` 引用角色，`agents` 保存有序候选。工人名必须在 `QWB_WORKERS` 中且有唯一启动定义；具名工人用 argv 固定 harness × 模型 × 推理级。主控修订六纠正：仅写 harness 名不是三元组候选。新式行 `qwb_worker <agent名> herdr <harness> -- <模型/effort argv>` 将两种身份分开；旧式行仍令 harness=名。Herdr 启动、复用身份、信任预置和 Claude 装机目录授权都要按 harness 处理，路由与账本继续记具名 agent；不能只改 dispatch 的解析器。

额度快照只筛候选，不改分类。禁名单和注册检查始终执行；额度缺失则说明降级。主控修订五明确：default/命中角色候选耗尽属于配置不可派发，`exit 2`，逐候选报告原因，让既有 qwb-run 拒绝；不能沿网络错误的 `exit 0` 回退路径静默派发。

验证要走真实脚本到本地 HTTP server；quota 5/6 假快照做正反对照，另外通过真实 qwb-run 断言耗尽拒派且账本/锁/worktree/Herdr 都无副作用。
