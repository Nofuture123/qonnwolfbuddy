# 任务书：<主题>

```
任务 id:  <kebab-id>
state:    running
来源:     <谁提出的 / 哪张上游票>
派发:     <主控（模型/会话）> → <执行者（模型/会话）>
主账本:   <本文件的绝对路径>
工作目录: <执行者干活的 worktree 绝对路径>
分支:     <分支名>
```

## 0. 原始意图与范围

原始意图保持使用者原意；工程规格另列，不把技术推荐冒充新增需求。

<为什么做、做到哪算完；用户从哪里操作、依赖哪些现有入口或资料；白名单：允许动哪些路径，明确不许动哪些。入口或依赖尚不存在时写明缺口，别当作已具备。>

### 工程规格（与原始意图区分）

<在已授权范围内的技术落法；规格修订留 spec_rev 与原因，不改原始意图。>

动态规划票由`qwb-ledger.sh new --project <根> --task tasks/<包>.md -- <request.json>`创建，不复制第二张图。request JSON包含request_id、package_id、一次冻结的packages（包→精确票文件名）、source_task/source_event（03持久原话）、intent/spec/constraints/scenarios、paths、needs。needs的start/accept/land均为数组，每条为task/artifact/version/spec_rev/condition（available/accepted/landed），缺票、自依赖、环、歧义及旧版本不解除。

主控可`plan-assign -- <02规划actor> <grant.json>`在来源票绑定该request/包/范围，grant包含request_id/source_event/packages/paths/workers/permissions/evidence/budget；预算是每票首次派工次数，不猜金额，不授权费用。`plan-authorize -- <JSON>`用于明确重授权（workers/permissions/evidence/budget）。未授权票即使state=running也不得启动。未迁旧票不自动切协议，其首次启动须主控显式头部implementation-authorized及正整数dispatch-budget，模板本身不含启动授权。

`plan-artifact`由主控核name/version/ref并保存真实sha256与spec_rev；唯一监督在同票写就绪/阻塞事件及解除证据，不自动派第二次或合并。`plan-revision --expect`登记新source/spec/constraints/scenarios/needs；gate持标准须本人`revision-handoff`交回，之后新CAS的`revise -- <新source_event>`提高spec_rev、保存并失效旧证据，重新核启动授权。accepted/verified原历史不重写，新需求另开后续票。策略/required字段仍采用现有04契约，不覆盖测试体系票的策略。

仅维护任务：在本节写明已合入基线、上轮覆盖与剩余项（首次写指定区间或小模块）、本轮文件范围和问题数量或可观察预算；执行者按 `roles/维护者.md` 工作。普通任务无需填写这些项。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### user_<正常路径场景名>

Given <前置状态及可用入口>
When  <用户动作>
Then  <可观察的结果及重新读取或核对方式>

### user_<失败路径场景名>

Given <失败前的状态>
When  <失败动作或输入>
Then  <可见结果及不得发生的副作用>

（场景命名：项目有测试框架时以 `user_` 开头；没有测试框架时用同名小节标题即可。
失败路径场景**至少一条**——只写 happy path 的任务书不完整。
示例（仅示意，非通用产品/存储要求）：修改标题保存后，重新打开仍显示新标题；保存请求失败时保留输入，且不提示保存成功。
场景定稿后冻结：实现完成后不得回头改写场景以迎合实现，那是自证。）

## 2. 硬约束

<不可违反的规矩：禁什么、只能用什么、格式要求>

## 3. 验收门

- 快门（改一行跑它）：`<命令，如 bash bin/qwb-test.sh fast>`
- 全门（合并前跑）：`<命令，如 bash bin/qwb-test.sh full>`
- <其他本项目验收命令>

<写明从哪个入口执行、如何核对场景结果；持久化结果须重新读取，不能只凭按钮或提示判断完成。>

需要执行记录时，可为质量门加 `--report <尚不存在的文件>`（如 `bash qwbuddy/bin/qwb-test.sh fast --project <项目根> --report <报告路径>`）。先明确哪个命令对应哪个场景；报告记录本次命令与配置摘要、目录、版本、工作区和退出码，不能代替真实 UI、安装包或人工步骤的验收证据。

已迁票可由主控显式`gate-assign`授权02登记门禁续接03成果：同票持久claim、按票candidate-bound收据、独立两轴审核与原范围返修，流程详见`roles/门禁.md`。授权JSON须冻结原base、candidate/attempt、policy、候选外环境依赖记录、required门→全部`user_`场景映射、review/rework具名Pi工人；不把已有full降成fast。按票质量门示例：

`bash qwbuddy/bin/qwb-test.sh full --project <candidate> --ledger-project <主项目根> --task <原票> --op <门禁claim> --report <候选外新JSON>`

审核JSON字段为context（`gate-context`精确输出）、implementer/reviewer（model/family/session/evidence原生Pi JSONL）、standards/spec（pass|fail）、covered（场景名数组）、findings（id/original/classification/root/evidence）。classification为must-fix/suggestion/not-founded/unresolved，原意见历史不能删除；修复复核须绑定当前候选。按票rc0仅记收据，accepted只记verdict，仍待land/cleanup、不自动verified/合并，五值state不扩。报告不写进候选。

## 4. 报告要求

往主账本绝对路径报告 `working:` / `done:`（含跑了什么命令与原始结果）/ `blocked:` / `needs-decision:`。未迁旧票仍按旧追加约定；已迁票只能调用 `qwb-ledger.sh append --project <主项目根> --task <绝对路径> -- 'working: 内容'`，不得裸追加、改协作区或 state。身份取已绑定工人的 HERDR_PANE_ID；越权由writer拒绝。

使用者问题用 `qwb-ledger.sh question --project <根> --task <票> -- <key> <内容>` 打开；key不变。只有主控基于真实答复及证据写 `answer`，之后写 `resume`，普通 working/done 不解除未结义务。规格疑点仍遵守以下两行约定，问题key不能代替 spec-resolved。
若生成质量门报告，附报告路径并核对运行前后 HEAD、工作区状态、门退出码、实际验收对象与命令；工作区脏、环境或依赖变化、关键场景未覆盖时，写明差异与待验收项，不直接复用旧报告。安装包或线上版本须另附身份与实际验证证据。
最后打印 `DONE <commit sha>` 或 `STOP <原因>`。**不要改本文件的 `state:` 字段。**

疑点两行约定（工人或主控认为**票本身有缺陷**时用，不是实现遇到困难）：

```
  blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
  working:  spec-resolved: <impl|spec>；<逐项回应与证据；改票位置，或保留原票的理由>
```

（以上两行是**缩进示例**：状态行前缀只认列首，文档/模板里的示例必须缩进两格，
否则照模板新建的票会被值守与疑点门当成真实状态行。）

- `spec-defect:` 由工人或主控提出，挂在 `blocked:` 行上（复用现有值守唤醒，不新增顶层 `state` 值）。
- `spec-resolved:` 只有主控能写；**一个处置结论覆盖其之前全部未决疑点**（不能只回应最后一条）。
- 普通 `working:` / `done:` / `dispatch:` 行**不能解除疑点**；处置之后新提的疑点重新拦截。
- 票上有未决疑点时派发会被拒（先处置再派）；改验收场景须用 `--revise-scenarios=<原因>` 显式修订留痕，`spec-resolved:` 本身不授权改场景。

## 5. 审核身份（可选——仅「要求独立审核」的票；普通票整节删掉）

要求独立审核的票在头部加 `review-required: yes`，验收时由**主控据真实会话证据**补记两行：

```
  review-impl: model=<实际型号> family=<模型家族> session=<原生会话标识> evidence=<证据位置>
  review-rev:  model=<实际型号> family=<模型家族> session=<原生会话标识> evidence=<证据位置>
```

- `family` 只写模型家族（如 `gpt` / `claude` / `gemini`），据真实 TUI/会话记录判断；**无法可靠判断就写 `unknown`**——lint 会报缺证据不通过，不许按名字猜。
- `cli=` / `provider=` 可附记，**绝不充当 family**：同 CLI 不同家族合法，不同 CLI 同家族会被拒。
- 两方 `session` 不得是同一原生实例——同一会话换角色 ≠ 独立审核。
- `evidence` 是证据位置（会话转储/审核文档路径）；写成路径时 lint 核对文件存在。
- 不补历史票：没标记的票不需要也不许凭空补身份。

## 6. 本票不允许做的事

<明确的排除项，防范围蔓延>
