# JEV 角色层配置

任务依据：`tasks/2026-09-27-qwb-jev-agent-roles.md` 及主控追加修订四、五、六。模板见 [`templates/dispatch-rules.json`](../templates/dispatch-rules.json)。

`agents` 是可选对象，值为非空、有序的字面工人名数组。`agents_disabled` 是可选工人名数组，缺省为空。候选名不能同时是角色 key，直接自引用与角色套角色均为配置错误。未命中角色 key 的 `worker` 继续按字面工人处理，不受角色候选筛选；最终注册校验仍由 `qwb-run` 完成。

## 工人与启动参数

`config.sh` 的 `QWB_WORKERS` 是项目工人名单；`workers.sh` 每个名字必须有唯一 `qwb_worker` 声明。模板保留 codex/pi/claude/devin/omp 旧名字兼容显式派发，新增具名三元组供路由候选引用；启动表不是五种任务分类。

agent 身份是 harness × 模型 × 推理级。例如，项目主控可以把以下两个名字加入 `QWB_WORKERS`，并在项目 `workers.sh` 固定参数，再把角色候选改为这些名字：

```bash
qwb_worker sol-medium herdr codex -- --dangerously-bypass-approvals-and-sandbox --model gpt-6-sol -c model_reasoning_effort=medium
qwb_worker sol-high herdr codex -- --dangerously-bypass-approvals-and-sandbox --model gpt-6-sol -c model_reasoning_effort=high
```

新式 schema 为 `qwb_worker <agent名> herdr <harness> -- <argv...>`：第三列显式指定 harness，分隔符被运行时消费，不会额外传给 CLI。以 harness 后紧跟 `--` 识别新式行；没有该分隔符的旧式 `qwb_worker <名> herdr <argv...>`（包括位置实参或无 argv）仍以名为 harness，不吞旧参数。`pane-run <executable> <argv...>` 保持兼容。路由输出和 dispatch 账本记录 agent 名，Herdr `--kind`、复用 pane 身份与信任预置使用 harness。

模板路由候选为 codex-sol-high、claude-fable-high、pi-glm-high、devin、omp-gemini；分别固定 GPT Sol high、Claude Fable high、GLM high、SWE-2 high、Gemini high。Devin 没有独立 effort 旗标，使用 `--model swe-2-high` 固定模型与档位。Pi 选 `zai-coding-cn/glm-5.3`，OMP 选 `google-antigravity/gemini-3.1-pro`；模型目录已核实，未启动模型会话。项目 `QWB_WORKERS` 与 `workers.sh` 必须同步注册。

安装器按显式 Claude harness 为具名 agent 注入 `--add-dir <项目根>`，同时保留旧式 Claude 行的升级与幂等行为。模板不写死项目路径；母仓三份运行配置由主控落地。`--model VALUE`、`--model=VALUE`、`-m VALUE` 用来提取额度账户 lane，`pane-run` 从 executable 的 basename 识别 harness。

2026-09-28 本机帮助核实（只查契约，没有启动模型会话）：

| CLI | 版本 | 模型/推理参数 |
|---|---|---|
| Codex | 0.157.1 | `--model` / `-m`、`-c key=value`；示例固定 `model_reasoning_effort` |
| Pi | 0.87.1 | `--model` 支持 provider/id，`--thinking` |
| Claude Code | 2.1.283 | `--model`、`--effort` |
| Devin | 3000.11.3 | `--model`；帮助未提供独立 effort 参数，不能臆造 |
| OMP | 18.3.2 | `--model`、`--thinking` |
| Herdr | 0.9.1 | `agent start NAME --kind KIND --pane ID [-- AGENT_ARG...]`，kind 为固定枚举 |
| quota-axi | 0.1.40 | `--json`；实现兼容 schema 5/6 |

模型是否可用与 CLI 参数存在是两件事；实际模型/档位运行验收由主控完成。本次 Codex 路径为 `/Users/rocky/.local/libexec/herdr-codex/bin/codex`，`HERDR_ENV=1` 且当前 pane 的 cwd 与本 worktree 一致。

## 额度与退出语义

角色解析使用同一次额度快照。schema 5 按 provider 取行；schema 6 优先绑定账户 lane，否则取 `default` 账户，不取其他账户冒充当前账户。沿用 firstmate 的绑定规则：Codex lane 为 `codex-home`；Pi 的 provider/id 前缀作为 lane（`codex-native` 归为 `codex-home`）；其余 lane 为空。provider 按修订六直接取显式 harness，不使用 agent 名或按模型改写 provider。schema 5 要求 provider 唯一，schema 6 要求 provider+accountKey 唯一；重复行使快照整体降级，结果与行顺序无关。

weekly 窗口存在时优先使用 weekly，无 weekly 才用 session；同种窗口取已知有效余量的最小值，未知窗口不能掩盖已知耗尽；部分窗口未知时说明只核对了已知窗口。`QWB_QUOTA_FLOOR` 缺省 10，合法范围 0–100，等于阈值可用。无额度命令、命令失败、坏快照、无匹配账户或无有效窗口均在 stderr 标明降级，保留注册与禁名单筛选。关闭 JEV 时跳过 quota，保证零网络查询。

default 或高置信度命中角色全部候选不可用：stderr 逐项列出未注册、禁用、低额度原因，`exit 2`，不输出可派发的 worker。`qwb-run` 沿既有非零退出路径拒绝，发生在锁、worktree、Herdr 和账本写入前。未命中的不可用角色不阻止其他角色派发。低置信度仍 ambiguous；HTTP/API/响应错误仍 error，均 `exit 0` 并保留已解析 default。

`QWB_TYPESAFE_BASE` 只用于测试地址覆盖，默认 `https://api.typesafe.ai`。key 的环境摘除、私有变量、fd 3 传头规则保持不变；quota 子进程不获得 key。生产 `.env` 应先被 `.gitignore` 忽略，再由主控创建。

## 验证范围

`tests/smoke.sh` 的 `JEV_ROLES_BEGIN` 至 `JEV_ROLES_END` 是可提取的定向段：真实 dispatch/curl → Python 本地 HTTP server，随机端口由 server 持有，退出时 kill/wait 回收。额度命令使用 schema 5/6 假快照，覆盖阈值、账户绑定、禁用、注册、诚实降级和耗尽；auto 拒派断言检查账本字节不变、无锁/worktree、无 Herdr 调用。curl 护栏拒绝非本地请求，全部使用假 key。

`bash bin/qwb-test.sh fast` 仅证明 shell 语法和 ShellCheck；主控仍需独立跑 full 门和真实任务的 JEV 路由验收，再负责母仓运行配置落地。
