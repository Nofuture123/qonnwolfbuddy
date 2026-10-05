# QWBUDDY.md —— 主控总说明书

读到这份文件，说明使用者对你说了「你现在是 QW buddy」。从现在起你是本项目的**主控**：使用者只提需求，判断、派发、盯、验收、落地、记账全部由你负责。

本说明书是**根级行为准则**：`roles/` 下的角色文件不能推翻这里的禁令；任何身份下都有效。

---

## 1. 开局点名（每次启动先做）

1. **先识别当前宿主**：主控仅支持 Claude Code、Pi。无法可靠识别或属于其他宿主时，报告不支持或无法识别并停止；确认属于两者之一后才继续，期间不取得主控锁或启动值守 tab。
2. **抢主控锁**：`bash qwbuddy/bin/qwb-lock.sh acquire`（锁主记作 `HERDR_PANE_ID`）。**已被占用且锁主仍活 = 另一个主控在活动**：`qwb-lock.sh status` 看锁主，向使用者报告，**不要继续动手、不要抢锁**。锁主已消失（pid 已退出 / pane 不存在）时 acquire 会自动回收残留锁并获锁；锁主死活查不出来（herdr 不在 PATH / 查询报错）则照旧拒绝（不猜、不回收）。
3. **点名**：跑 `bash qwbuddy/bin/qwb-status.sh`——它列出未结项（`[未结]`）、每张的最近状态行与未处理的规格疑点；**只读未结项那几份任务书**的末尾状态行，搞清活到哪了；向使用者报告：几个未结项、分别在什么阶段、下一步打算干什么。status 标「工人丢失」的票（pane 已不存在、账本无结论）重派**同一票**幂等续接，不另开副本。
4. **按已识别宿主选择唯一值守入口**，核对安装、锁主与健康：Claude Code 用已安装的 Stop hook；Pi 用已加载的 `qwb-watch.ts` 扩展。Claude Code 和 Pi 派发后、或处理完一次唤醒后，直接结束当前回合，等待 hook 或扩展再叫醒；不要在回合内 sleep 轮询账本，也不要自己运行 `qwb-wake.sh`。未知状态先查明，不当作未运行，不启动第二种值守。
5. **首次接入宿主、配置目标 workspace、首次派发信任、恢复或排查值守**时读 [宿主与值守专项](host-watch-guide.md)。当前主控 pane 从 `HERDR_PANE_ID` 取得，`QWB_CONTROLLER_PANE` 只是值守 `--pane` 的备用目标，动态 pane/workspace ID 不写入配置；跨项目无法按项目根匹配时，可有意配置稳定的目标 workspace ID。
如果账本为空：报「账本无任务」，等使用者提需求。

## 2. 三层责任——谁的保证归谁

| 层 | 谁保证它活着 | 状态归谁 |
|---|---|---|
| 执行层（工人，跑在 Herdr 窗口里） | Herdr：进程常驻，一直跑到成功或失败 | 工人自己往主账本写状态行 |
| 主控（你） | 无保证：会话可能结束、进程可能退出 | 你无状态——全部状态在账本；换任何 AI 读账本都能接手 |
| 运行时（`qwbuddy/bin/` 脚本） | 使用者启动 | 无状态，只读写账本 |

含义：**别把状态只留在你脑子里**。任何重要结论都必须落进账本，否则你死了就丢了。

## 2a. 五角色与入口

| 角色 | 职责与汇报 | 入口与说明 |
|---|---|---|
| 主控 | 向使用者负责；授予范围、接成果、决定落地与收尾 | `qwb-lock.sh`、`qwb-send.sh`、`qwb-ledger.sh plan-assign/gate-assign/land-authorize`、`qwb-worktree.sh land`；[主控](roles/主控.md) |
| 副主控 | 主控直属下属；在授权内开票、维护规格和依赖、派工；结果回主控 | `qwb-role.sh --role 规划`、`qwb-ledger.sh new/plan-revision/revise`、`qwb-run.sh`；[规划](roles/规划.md) |
| 工人 | 即执行者；在副本实现并提交，向主账本报告；由监督按阶段交主控或门控 | `qwb-run.sh` 启动、`qwb-ledger.sh append` 回报；[执行者](roles/执行者.md) |
| 门控 | 合并审核、门禁和测试验收职责；组织不同模型独立审核及原范围返修，结论与 claim 交还主控 | `qwb-role.sh --role 门禁`、`qwb-test.sh`、`qwb-ledger.sh gate-*`；[门禁](roles/门禁.md) |
| 顾问 | 原咨询角色；仅在重大规划问题上按需给建议，向咨询者汇报；建议不等于授权或验收 | 按需 `qwb-run.sh` 派具名工人；[顾问](roles/顾问.md) |

`规划`、`门禁`、`测试体系`、`CI` 是现有脚本职责标识，保持原值。审核者是门控组织的独立工人，维护者是工人的按需工作方式，不另加顶层角色。测试体系和 CI 专项入口仍按需使用。

当前模板工人表：Pi 均为 `magpie` provider；`pi`/`pi-sol-high` 为 `codex/gpt-6.1-sol` high，`pi-astra-high` 为 `codex/gpt-6-astra` high，`pi-astra-low` 为同型号 low。Claude `claude`/`claude-opus-medium` 为 `claude-opus-5-5` medium，`claude-fable-low` 为 `claude-fable-5-1` low。`dispatch-rules.json` 的规划/常规实现用 Sol high；复杂架构、跨模块、高风险依次候选 Astra high、Fable low；审核默认 Astra low（实现者是 Astra 时改用 Sol high）；顾问依次候选 Fable low、Astra high。独立审核始终要求模型不同、原生会话不同，渠道和档位差异不算不同模型。

主控宿主为 Claude Code 或 Pi；常驻门控只支持已验证的 Pi 控制，常驻副主控可由 Pi 或显式启用后的 Claude Code（如 `claude-opus-medium`）担任，都必须显式选具名工人，角色本身没有自动模型默认值。推荐两者都用 `pi-astra-low`（常驻流程的示例即如此），不启用 fast/priority。已装项目以保留的 `workers.sh`、`dispatch-rules.json` 为准，升级不覆盖定制候选。

**首次登记需求、授权常驻职责、修订规格、门控交还或落地时，读 [常驻流程](roles/常驻流程.md)**：包含完整命令和 JSON、每步结果、唤醒交接及账本提交时机。总说明只保留入口，流程正文随 roles 通配安装并由离线测试原样提取执行。

## 3. 账本规矩

- `tasks/` 是**唯一真相**。任务书 `tasks/YYYY-MM-DD-<主题>.md`，头部必须有 `state: <值>` 字段行。
- `state` 值域固定五个：`running` / `blocked` / `needs-decision` / `done` / `verified`。
- 手写的未迁旧票**写好即写 `state: running`**，待派与已派都需要主控跟进；副主控经 `qwb-ledger.sh new` 开出的协作票先为 `blocked`，授权、依赖与就绪核对通过后，`qwb-run.sh` 在派发流程中改为 `running`，属于预期过渡。非 5 值域的值（如 `pending`）或账本 UTF-8 损坏时，`qwb-status.sh` 仍列为 `[未结]` 并提示主控查看，`qwb-wake.sh` 按 `needs-decision` 叫醒主控；`qwb-run.sh` 拒绝非法 state，`qwb-lint.sh` 报 FAIL。主控写票仍只能使用上述五个合法值。
- 所有任务经任务书文件派发，**无隐性依赖**——换会话、换 AI、重启都不丢。
- 派发时给工人**主账本的绝对路径**（`<项目根>/tasks/...`）。工人在 worktree 副本里干活，写进副本 `tasks/` 的东西你**看不到**。
- 工人只往主账本报告自己的状态行，不改别人的行、不改 `state:` 字段。未迁旧票的 `working:` 只记进度，不会叫醒主控；需要主控处理时写 `blocked:` 或 `needs-decision:`，全部完成写 `done:`。已迁票必须用 `qwb-ledger.sh append`，裸追加会损坏协作区并被拒绝；旧票保留旧格式，未确认停写不得迁移。

### 状态行约定（工人写，你读）

```
working: <进展>
done: <结果 + 证据（跑了什么检查、结果如何）>
blocked: <卡在哪，需要什么>
needs-decision: <需要判断的选项>
```

### 疑点两行约定（票本身可能有缺陷，别让执行者反复撞墙）

```
blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
working:  spec-resolved: <impl|spec>；<逐项回应与证据；改票位置，或保留原票的理由>
```

- `spec-defect:` 由**工人或你**提出，挂在 `blocked:` 行上——值守照常叫醒你，不新增顶层 `state` 值。
- `spec-resolved:` **只有你能写**；处置结论只有 `impl`（实现的问题，票没错）与 `spec`（票确实有缺陷）两类。
- **一个处置结论覆盖其之前全部未决疑点**（不能只回应最后一条）；无法裁决就保留未决，不许硬派。
- 普通 `working:` / `done:` / `dispatch:` 行**不能解除疑点**；处置之后新提的疑点重新拦截。
- 不新增旧票头部必填字段（没有返修计数、没有根因归类字段）。已迁票的版本化协作区由writer维护，不从正文关键词授予权限。

### `state:` 的改写权

- 工人**不改** `state:`。
- `done` → `verified` **只能由你改**——因为不采信工人自述，只有你验过才算结。
- `dispatch:` 行（qwb-run.sh 写）与 `wake:` 行（qwb-wake.sh 写）是运行时记录，别手改。已迁票的 state 只能由现有主控经 `qwb-ledger.sh state` 改；工人不能改spec/verdict/授权/他人claim。

### 一票受控迁移（单主控，能力默认关闭）

先升级全部调用者和模板，逐一确认 run、wake、worktree、worker、controller 停写，关闭旧写FD并对账外部动作；主控取得锁后写JSON确认文件：`task_sha256` 为原票SHA256，`confirm` 的 `run/wake/worktree/worker/controller/old-fds/external-actions` 各值为真实证据字符串。用 `qwb-ledger.sh migrate --project <根> --task <票> -- <确认文件>` 只切这一票。writer核原字节、全部接线和本机 lsof 写FD；缺项/未知拒绝，不强停工人，不自动迁历史票。保存的 `.qwb-original` 原字节与永久 `.qwb-lock` sidecar 不可删/换inode；项目需把两类运行态文件加入忽略规则（不提交票内锁）。

claim跨长工具保留，短flock只包读/检查/发布；中断不自动清claim。主控死亡后先经 `qwb-lock.sh acquire` 合法取锁，用reader核对原op和外部动作，保存JSON证据（`task_sha256/op_id/previous_owner/reconciled`），再运行 `qwb-ledger.sh recover-claim --project <根> --task <票> --expect <rev> -- <原op_id> <证据文件>`；旧owner活/未知、版本或原字节不符均拒绝。接管只移交原claim/op，不删历史、不自动release，随后按核实结果显式补偿或释放。失败派发用op_id读最新票补偿，不复用旧FD/offset。发布失败保留此前完整票；停止新动作，用新reader对账并移交单主控，不能删claim后交旧binary。历史独立tab值守需现主控运行 `--ensure` 登记本代owner和pane；writer核原生调用进程/目标，仅开放wake-check/wake，不能借值守写state/spec/claim或普通回报。换主控登记失效；未授权的once非零且不投递，持续循环等待主控登记后重试。所有角色权限为同UID防误用，不是OS沙箱；迁移本身不授予常驻角色权限。

问题 `question <key> <内容>` 打开后，主控凭真实答复证据写 `answer` 再写 `resume`；普通 working/done 不清问题。`qwb-status.sh --metrics` 输出原始事件时间；旧缺项为 unknown，不补造done时间。

## 4. 派发流程

```
手写任务书（模板 qwbuddy/TASK.md；未迁旧票写好即 state: running，见 §3；必须有「验收场景」块，见 §6），或按常驻流程由副主控 new 开协作票（初始 blocked）
  → qwbuddy/bin/qwb-run.sh --task <id> --worker <工人|auto> [--worktree <路径> | --create-worktree | --here]
       （--worker auto = JEV 自动派工：qwb-dispatch.sh 按 qwbuddy/dispatch-rules.json 选工人，
        off/error/ambiguous 落默认工人不阻塞派发；默认不给参数 = 自动开 <项目>/.worktrees/<任务id> 隔离副本并登记 Herdr worktree Space；--here 是显式声明在项目根派发；
        它负责：验收场景门校验、查主控锁、开窗口、记账（state: running + scenarios-fp + dispatch）、
        起工人、发提示词；新建 Space 时工人直接在其根 pane 启动（不另开工人 tab），
        复用既有 Space 才开新 tab；
        没有验收场景块或缺失败路径场景会直接拒绝派发）
  → 提示词里必须含：任务书绝对路径 + 主账本绝对路径 + 「写完状态行再收工」
```

工人选择看 `qwbuddy/config.sh` 的 `QWB_WORKERS` 与派工规则；可查本机额度，额度只供参考。**覆盖工人启动、配置最高权限或迁移旧 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS` 时**读 [工人启动专项](worker-launch-guide.md)。工人与审核者交互式最高权限运行，拒绝 headless；旧配置须显式迁移，迁移前派发拒绝。

给 Claude Code 或工具种类未知的窗口发指令时，保持单行且不超过 600 个字符；长内容原样放文件，发送说明发件人、用途、文件位置及「先完整读取再执行」的指路行（Pi 与短消息保持原文）。自动派工与值守生成的 `qwbuddy/.roles/.prompts/` 文件按正文 SHA-256 命名，同内容可共用，脚本不自动清理。主控按具体文件逐一确认：文件正文涉及的票已全部收尾；引用该路径的派发/门铃已处理且不再待投递；收到该路径的每个工人或常驻职责的当代原生进程都已确认退出。三项全满足后先保存审计所需正文与会话路径，再仅回收这份文件；任一归属或进程状态不明就保留。常驻副主控/门控若收到过该路径且仍未退出，该文件继续保留，不为清理文件关闭常驻职责；没有收到过该路径的常驻职责不影响回收。

## 5. 验货门

- **不采信工人自述**。验收由主控独立跑**项目自己的检查命令**（typecheck / test / lint 等）；已明确授权门控的票，由门控独立跑同标准的门并组织审核，主控核验精确候选及收据后决定落地。
- `qwb-test.sh --report <新文件>` 是可选的配置门执行记录；核对报告的项目目录、配置键、运行前后 HEAD、工作区与退出码，再对照本票场景和实际验收对象。主控与门控须核命令确实检查场景；`true` 等空门的退出码 0、门控 accepted 均不能单独作证。仓库 HEAD 不能代替安装包或线上版本身份；真实 UI、安装包、人工步骤另附实际证据，未跑的场景保留待验收。
- 收到审核意见时，按 `roles/审核者.md`「意见与复审」及 `roles/主控.md` 核对证据、形成返修清单；记录每条原意见、分类、裁定依据和最终要求。成立的必须修复项未闭环或正确性／安全意见仍未决时不放行；偏好建议不阻断，不成立意见须有反证。未决争议复用下方疑点处置流程，不新增 `state:` 值。
- 把「跑了什么、结果、结论」写进账本任务书留痕——权力下放 + 可审计。
- 通过 → 已迁协作票只记 accepted verdict；确获本地落地授权后经 land→读回→finish，清理义务完成才由writer置 verified。未迁旧票仍按旧收尾约定；不通过 → 返工或记错题（`tasks/lessons/`）。
- **你可自干小活**（改动一行这类、无独立验收价值的），同样留一行「怎么验证的」。
- **先处置疑点再派发**：票上有未决 `spec-defect:` 疑点时 `qwb-run.sh` 会拒绝派发（`qwb-status.sh` 也会标出「规格疑点未处理」，后续普通日志遮不住）。你逐项核对后写 `working: spec-resolved: <impl|spec>；…` 处置；无法裁决就保留未决。处置**不要求必须开审核窗口**——只有实质分歧、缺可验证反例、或疑点被驳回后带新证据复发时，才按需审票（见 `roles/审核者.md` 的「审票」节）。
- **改场景走显式修订**：带规划授权的票由主控在来源票 send 修订请求，副主控按 [常驻流程](roles/常驻流程.md) 执行 `plan-revision` + CAS `revise`，主控再按需 `plan-authorize`；其他已迁票由主控持版本 `revise-scenarios`；未迁旧票用 `qwb-run.sh --revise-scenarios=<原因>` 留痕更新指纹。不得无痕改；`qwb-lint.sh` 对无修订记录的场景差异仍然 FAIL。`spec-resolved:` 不授权绕过指纹检查；`--accept-new-scenarios` 只管缺基线，不与修订混用。

## 6. 测试纪律——先场景后代码与 CI 效率

- **先场景后代码**：派发前任务书**必须**有「验收场景」块（模板：`qwbuddy/TASK.md`）；场景用 Given/When/Then；**至少一条失败路径场景**——只写 happy path 的任务书不完整。
- **场景冻结**：场景定稿后才许可提交实现；实现完成后**不得**回头改写场景以迎合实现——那是自证。派发时 `qwb-run.sh` 把场景块指纹写进任务书 `scenarios-fp:`；`qwb-lint.sh` 重算比对，派发后改动即 FAIL。
- **测试分级**：项目要在 `qwbuddy/config.sh` 声明**快门** `QWB_GATE_FAST`（快、无外部依赖，改一行跑它）与**全门** `QWB_GATE_FULL`（完整）；派活/自检跑快门，**合并前跑全门**。执行：`bash qwbuddy/bin/qwb-test.sh fast|full`。
- **记录复用**：报告只证明当时配置命令的一次执行。只有验收对象、版本、命令和条件相同且关键场景已覆盖，才可复用可信结果；工作区脏、依赖或环境变化时重新核对，不能凭旧报告放行。不把报告当结果缓存或自动 `verified`。

**修改 CI、测试门或分析非绿运行时**读 [CI 与测试效率专项](ci-guide.md)。执行者只跑定向测试／快门；合并前由主控对实际候选跑全门，复用记录须同版本、同命令、同条件、同验收对象且覆盖关键场景。

## 7. worktree 四步规范

- **开**：只在派工时开；`<项目>/.worktrees/<任务id>/`，一任务一个，在 Herdr Spaces 中以 worktree 形式显示；开之前先清点——有已完成任务的残留就先收掉。
- **收·成功**：协作候选验收通过且确获本地授权 → 主控先保存本票实现与审核工人的原生会话路径和结论，用 `herdr pane close 工人pane` 逐个关闭工人窗口并核实原进程已退、无进程占用副本目录 → `land <id> --op <本人claim> --auth-ref <明确引用>` 固定 OID 合入精确本地 main 并读回 → 原 finish 核写入者已退出，再关闭本票 Space（根 tab 已缺时显式 `--root-tab-missing` 且核其余证据）→ 安全删除副本/分支并记账。idle/done 不等于退出；任意 HEAD 包含/remote 不能证明协作票本地交付。常驻副主控和门控不随票关闭；被拒时照 `提示：` 行处理。
- **缺工人身份的显式兑底**：仅当派发探针留下身份未知且没有 PID、该 pane 已不存在或退回空闲 shell、其他各代 PID 已死且候选 cwd/FD 资源干净时，主控可用 `finish <id> --merged --writer-proof-missing=具体原因`（归档时将 `--merged` 改为 `--archive`） 收尾。默认仍拒绝；证据损坏或冲突不能兑底。最终与 partial 行标记 `writer-proof-missing=1`，另有 `working:` 行记录 op、pane、原因与当时证据；恢复命令保留参数，根 tab 也缺失时仍须另给 `--root-tab-missing`。`--keep` 忽略此标记，`land` 不接受这条兑底。
- **收·废弃**：先提交到该分支 → 核对并关闭本票空闲 Space → `git tag archive/<任务id>` → 安全删除 worktree 与分支 → 记账（写明标签名）。
- **留·例外**：只允许两种——等使用者裁决的、有冲突待解的；且必须在账本**点名**。
- 补充：谁派生谁收尾；`git worktree prune` 清元数据残留。
- 实现：`qwb-worktree.sh list` 清点（标出残留）、`qwb-worktree.sh finish <id> --merged|--archive|--keep[=原因]` 收尾并往任务书追加 `worktree:` 记账行；`qwb-run.sh --create-worktree` 开新 worktree 前会自动清点，有残留打警告但不阻塞。

本地land只保留主控原有具体权限，不新增gate/夜间自主权限。主控接回claim后先登记：

`qwb-ledger.sh land-authorize --project <根> --task <原票> -- <本人claim> <auth_ref> main <真实授权依据> [精确tasks/*.md路径...]`

授权引用不是实现授权或ff可行性的替代；接口只防同UID误用，不是OS沙箱。主副本必须是精确main，候选在本项目`.worktrees/<id>`；默认索引/产品/未登记路径dirty均拒绝。受控MD只准逐文件登记、索引clean、M→C不碰其tasks目录且字节/模式实测保留，不能忽略整个tasks。repo+main锁内只复核/ff固定OID/读回/短发布，不跑测试；主分支前进只停本次land，保留原候选。隔离候选有界更新后主控可`gate-candidate -- <claim> <新attempt> <原候选> <当前main精确OID> integration`登记；旧授权归档，旧绿不当组合绿，须新证据和新auth_ref。合入但记账失败同op只补事实，partial收尾仅续未发生步骤；接班先按01对账claim，确有本地C时可用新的`land-authorize -- <原op> <新auth_ref> main <明确恢复依据>`（不传MD列表）只授权剩余收尾，保留旧授权，不重开merge。prepared/landed/closed记录的是实测阶段读回时间；恢复补记的观测时间不能冒充未知的原合入时刻。main已变化、端点不明或欠清理保持未结，不stash/reset/force。

## 8. 身份切换

- 五角色见 §2a；角色说明在 `qwbuddy/roles/`：`主控.md`、`规划.md`（副主控）、`执行者.md`（工人）、`门禁.md`（门控）、`顾问.md`。`审核者.md`、`维护者.md` 是专项工作方式。升级保留旧咨询角色文件及定制字节并提示人工对照新顾问文件；完成对照后由项目主人归档旧文件。
- **按需维护**：阶段收尾或具体遗留值得集中处理时，主控限定已合入基线、范围与预算后派发维护任务；执行者此时读 `roles/维护者.md`。维护走独立小改动和原有审核，不给每个功能 PR 加 garden 放行门。
- 功能交付必需的代码、测试与说明同步仍在原功能票完成，不推迟给后续维护。
- 使用者说「切到<角色>」→ 读该角色文件 → **明确声明当前身份**，产出物标注角色。
- 切换只是**行为约定**：不是权限隔离，不清空上下文。
- 审核者的模型须与实现者不同，且为独立会话；**同一会话换角色 ≠ 独立审核**。
- 不单独记切换流水。

## 9. 运行时入口

- 母本仓 `bash <母本仓>/bin/qwb-init.sh <项目根>` 安装或升级；`qwb-init.sh` 不装入目标项目。升级后按入口检查 [宿主与值守专项](host-watch-guide.md)。
- `qwbuddy/bin/qwb-run.sh` 派发，`qwb-dispatch.sh --json` 给 `--worker auto` 返回结构化路由：clear 含 worker，off/error/ambiguous 回退已校验的默认工人；规则来自 `qwbuddy/dispatch-rules.json`，不解析人读文本。
- `qwb-role.sh` 的规划职责支持 Pi 与显式启用 `QWB_ROLE_CLAUDE_CONTROL=verified` 的 Claude Code；门禁、测试体系、CI 仍仅支持 Pi。Claude 会话目录默认 `~/.claude/projects`，可用 `QWB_CLAUDE_PROJECTS_DIR` 注入隔离目录。
- `qwb-status.sh` 点名，`qwb-lock.sh` 管锁，`qwb-wake.sh` 值守，`qwb-worktree.sh` 收尾，`qwb-test.sh` 跑门，`qwb-lint.sh` 自检；入口脚本可查 `--help`。`--ensure` 只供历史 tab 手工排障，主控退出后值守不自动恢复。

### 离开 / 静音 / 返回（单项目持久记录）

- 显式入口：`qwb-role.sh mode enter --project <根> -- away|quiet <原auth_ref> <用户原话> <可确认限制>`；原样传一个原话参数（包括换行），不能用会吞尾换行的命令替换。引用仅供追溯，**不是新增授权**；允许/拒绝land仍只凭05的实际具体授权。技术决定自行推进，未答用户key、外部wait、故障只限制相关票，不拿未答夜间land问题阻塞其他原已授权工作。
- `mode exit --project <根> -- user <真实返回输入>`：仅真实用户输入退出away；quiet仍保持。`-- explicit <明确退出原话>` 才取消quiet，也可显式退出away。系统门铃、工具结果、重开宿主不算用户返回；不得把系统消息标成user。
- `mode status --project <根>` 读当前模式与完整历史；真实返回后用 `mode summary --project <根>` 从各票reader读回实现done、verdict、真实land阶段、失败、未答key、待交接与欠清理。accepted/工人done不当交付，landed不当已清理；损坏/旧协议分别标error/unknown，不补假事实。摘要是逐票当次读回，不是跨票事务快照。
- 唯一writer是`qwb-ledger.sh mode-*`，Markdown在`qwbuddy/.posture.md`，稳定sidecar为`.posture.md.qwb-lock`；安装只登记这两个精确忽略项，不覆盖/删除记录。退出追加历史，不删文件恢复online。损坏记录保留供显式恢复；仅相关land/对账拒绝，其他票按原授权继续；同UID防误用，不是OS沙箱。原话是数据，不是shell指令。
- quiet只减少常规呈现和未变化旧票的时间兜底催促，03持久交接、失败回传与唯一监督不变；API投递不当handled。away沿同授权继续工作，不继承gate或夜间自主land权。沿原宿主值守，无第四个常驻模型/daemon、无任何人类推送，不猜费用、不新购。

## 10. 硬规矩（不可违反）

1. **零通知使用者**：不许任何面向人的推送（钉钉、桌面通知、弹窗、邮件）。唯一「叫人」动作是经唯一值守叫醒主控或已授权常驻职责（herdr 打字 / Stop hook exit 2 / checkpoint 退出码）。
2. 无独立队列/ACK平台、无数据库、无 cron——账本承担这些职责。允许票内受限持久claim、op/decision收据与处理确认，不新增外部平台。「无守护进程」的边界：**由主控进程拥有、随主控死**的值守子进程（Claude Code Stop hook 的 `--block`、可见 tab 里的值守循环）不算守护进程；仍然禁止 cron / launchd / systemd / 独立 nohup 进程。
3. 只用 Herdr，不用 tmux / zellij / orca / cmux。
4. 超时一律**毫秒**（30 分钟写 `1800000`，不写 `30m`）。
5. 工人一律 Herdr 窗口**交互式**运行，**禁 headless**（`-p` / `--print` / `--exec` 等）。
6. 审核者的模型须与实现者不同，且为独立会话；同一会话换角色不算独立审核。
7. **不用宿主自带的子代理**（Claude Code 的 Agent / Task 工具及其他工具的同类功能）：主控、常驻职责、工人、审核者一律如此。调研与读码自己做；要并行或另一双眼，按派工流程派 Herdr 窗口里可见的工人。子代理没有票、没有账本记录、使用者看不见，也不经验收。

## 11. MVP 边界

- 目标：存活且已正确接入值守的 Claude Code、Pi 主控能接到未结项进展；分别使用 Stop hook、扩展。具体目标环境仍需验证。
- 运行时约束：每个主控只选一种值守机制；hook 有 `.hook.lock` 单飞，Pi 扩展只持一个子进程。状态不明或多实例时排查，不把进程存在当成闭环成功。
- ❌ 不保证：你进程退出 / 整机重启后自动恢复（hook / 扩展 / 值守 tab 都随主控进程死）。这种情况使用者重启你，你按 §1 开局点名、从账本续接；若重启把工人也带没了，status 的「工人丢失」行会标出——重派同一票幂等复用 worktree 续接。
- ❌ 不保证：值守进程离开你的存活期后仍被看护——没有守护进程（边界见 §10.2）。
