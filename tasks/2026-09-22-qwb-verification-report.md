# 票 03：验收留下对应当前版本的真实记录

state: verified

- 任务 ID：`2026-09-22-qwb-verification-report`
- 类型：测试脚本的小范围增强及对应行为测试。
- 交付状态：交接稿，尚未派发；激活规则见同目录 README。
- 来源：Rocky 确认的三项改进中的“完成后验证真实结果”。
- 核对基线：`main@0eae33bb0625d4df50eada12393885b13b490fa6`；执行前重新核对。
- 前置：票 01、02 已验收并进入本票基线；在途生产修复已收尾，尤其保留其“测试失败不得换执行器重跑后报绿”的修复。

## 0. 背景与范围

当前 `bin/qwb-test.sh` 读取项目质量门、执行并透传输出与退出码；`tests/smoke.sh` 第 23 节已有命令成功、退出码 7、配置回退与缺配置的覆盖。

本票增加可选测试摘要，说明本次在什么目录、什么版本、执行哪个门、得到什么结果。摘要不替代原始测试输出，更不代表浏览器、安装包或生产环境自动验收通过。

### 写入白名单

| 文件 | 允许改动 |
|---|---|
| `bin/qwb-test.sh` | 可选 --report 参数、报告输出和相关 help；不改变原有测试命令执行方式 |
| `tests/smoke.sh` | 在现有 qwb-test 测试段补真实调用用例，保留旧断言；不得重构整套测试入口 |
| `templates/TASK.md` | 仅报告要求和验收门说明，保留票 02 的可验收场景 |
| `templates/QWBUDDY.md` | 仅第 5、6 节补“报告与任务验收结果的区别”、版本核对及复用限制，保留票 01 的审核裁定 |

另外只允许向本票激活后的主账本追加证据。报告与测试样本写临时目录；最终证据按项目既有方式保留，不自动加入 Git。

## 1. 验收场景

### user_旧调用保持兼容

Given 使用现有 fast/full 与 --project 调用，未传 --report
When 质量门执行成功或返回 7
Then 命令仍只执行一次，stdout/stderr 与原有约定一致，分别返回 0 或 7，不新建报告文件，不新增必需依赖。

### user_成功报告绑定实际执行对象

Given 一个干净临时 Git 项目、明确提交和会输出固定文本的 fast 门
When 传 --report 指定一个不存在的文件
Then 固定文本仍出现在原 stdout，报告记录正确项目目录、配置键、机器时间、运行前后提交及工作区状态，门退出码为 0；报告明确只对应 configured gate，不宣称功能或部署通过。

### user_失败结果不能被报告写入掩盖

Given full 门输出 stderr、记录执行次数并返回 7
When 使用 --report 执行
Then 脚本返回 7，stderr 仍可见，报告记录 7，执行次数恰好为 1；报告写入或收尾成功不能把原失败变为 0。

### user_重复路径或不可用路径不得覆盖证据

Given 报告目标已存在、为符号链接、为目录，或其父目录不具备正常写入条件
When 请求 --report
Then 在执行门之前拒绝，返回明确非零结果；不改旧报告、链接目标或测试对象，不自动生成新名字后继续；测试文件的执行计数保持为 0。

### user_报告写入失败也不能假报全成功

Given 已通过报告路径预检并开始执行门，但门结束时报告无法完整落盘
When 质量门自身分别返回 0 或 7
Then 门为 0 时整体返回 3 并提示报告失败；门为 7 时仍返回 7 且额外提示报告失败；不得把残缺文件描述为完整报告，不自动重跑门。

### user_版本未知或变化时如实记录

Given 非 Git 项目、Git 查询失败、脏工作区，或门执行期间产生新提交／修改
When 请求报告
Then 分别记录 unknown 或实际运行前后状态，不猜版本、不强制仓库清理；Git 元信息不可取不影响门本身执行，不把变化前的单一 SHA 宣称为全部验证对象。

### user_新记录不覆盖失败且不复制秘密

Given 先失败后成功两次运行，使用两个不同报告文件；环境变量、配置中的命令原文或测试输出含合成的敏感字符串
When 生成两份摘要
Then 失败与成功记录都保留，报告不复制环境变量、凭据、配置文件全文、CMD 原文或原始 stdout/stderr；控制台仍按既有行为透传，脱敏输出由项目现有测试负责。

## 2. 新接口与报告契约

新增可选参数，以下命令是本票要实现的接口，不是当前已有能力：

```bash
bash bin/qwb-test.sh fast --project "$PWD" --report /tmp/qwb-check-unique.md
```

- 不传 --report：保持当前行为。
- --report 缺值、重复出现或目标不合法：返回 2，门不执行。
- 报告父目录须已存在；绝对路径直接使用，相对路径以调用时 cwd 解析，不受随后 cd 到 --project 的影响。
- 不覆盖既有目标或符号链接；错误只处理本次自己创建的临时文件，不删他人报告。
- 报告采用 UTF-8 Markdown 文本，不增加 JSON/YAML 库、外部服务或新进程守护机制。复用仓库现有依赖；新增依赖须另行申请，本票不授权。
- 只保存精简元信息；按配置路径和 QWB_GATE_FAST/QWB_GATE_FULL 定位命令，不保存可能含秘密的 CMD 原文。脱敏后的具体命令、输出及人工步骤由本票证据另行给出。

必需内容如下，标签可保持直接可读，不建立新的账本状态：

| 内容 | 口径 |
|---|---|
| 报告版本 | 固定 `qwb-test-report-v1` |
| 检查 | fast 或 full |
| 项目目录 | 实际执行质量门的规范化目录 |
| 配置来源 | 实际选择的配置文件路径 + QWB_GATE_FAST 或 QWB_GATE_FULL |
| 开始／结束时间 | 机器生成、带时区，不手写预计时间 |
| 运行前／后提交 | 实际 Git HEAD；无法取得写 unknown |
| 运行前／后工作区 | clean / dirty / unknown；dirty 包括可见的未跟踪文件 |
| 门退出码 | 实际执行结果 |
| 证明范围 | 仅证明这次配置命令的执行记录，不自动等于产品验收或部署成功 |

工作区状态在本次报告及其临时文件创建前采样，结束状态在完整报告落盘前采样，避免报告自身把 clean 错标 dirty。若实现不能做到，必须标明该采样限制，不能伪报 clean。无需快照全部文件或构建完整哈希账本。

## 3. 失败语义与实现约束

1. 已启动的门恰好执行一次。不加 retry，不换执行器洗绿，不用报告处理的最后一个退出码代替门退出码。
2. 门返回非零时始终保留该退出码；门成功但请求的报告无法完成时返回 3。参数与路径预检错误返回 2；既有缺配置／缺门行为保持原规则。
3. stdout/stderr 继续分别透传，不为自动保存日志改成会吞掉失败的管道。报告不包含原始输出；用户明确要求的摘要不是秘密扫描工具。
4. 正常报告完整写入后才提示报告可用。中断或异常可以没有完整报告，但不能留下可误认为已完成的成功记录；不新增复杂的进程管理系统。
5. 不新增任务状态、不自动写 verified、不修改合并／部署策略，也不把报告当成可信签名或防伪机制。
6. 模板要求主控核对实际验收对象：仓库 HEAD 不等于某个安装包或线上版本；真实 UI／安装包／人工步骤沿用各项目原工具并另附证据。
7. 可信结果复用以同对象、版本、命令和条件为前提；工作区脏、依赖／环境变化或关键场景未覆盖时不能凭旧报告放行。本票不实现结果缓存。
8. 检查框架兼容现有 Bash 支持范围；不顺手改其他脚本、格式化全仓或增加第四项改进。

## 4. 验收门与证据

- 快门：`bash bin/qwb-test.sh fast --project "$PWD"`；为避免自证，先用不带报告的旧接口跑快门。
- 静态检查：`bash -n bin/qwb-test.sh && bash -n tests/smoke.sh`、`shellcheck bin/qwb-test.sh`、`git diff --check`。
- 定向行为验证：在隔离临时项目中直接调用真实 qwb-test.sh，覆盖本票各场景；可用临时驱动脚本，不新增常驻测试系统。正式回归用例追加到现有 smoke 的相关段，不能只 grep 源码字符串或自己造报告后断言。
- 负例至少保留：旧脚本不支持 --report；新脚本下门 exit 7；报告目标重复；报告写入失败；次数必须为 1。路径拒绝场景执行次数必须为 0。
- 兼容覆盖：已存在的配置优先级、qwb.config.sh 回退、缺配置／缺门、help、非 Git 目录继续按现有规则工作。
- 全门：由主控在实际候选上执行 `bash bin/qwb-test.sh full --project "$PWD"`，确认新用例接在 smoke 最终退出之前；不与同机 CI 同时跑全量。
- 清理只回收本次测试临时项目，先保留脱敏后的代表性报告和原始检查结果到本票证据位置；不删原有证据。

## 5. 报告要求

本票交付包括：源码基线与提交、实际 diff、门返回 0 与 7 的两份代表性报告、输出透传和执行次数结果、报告路径／写入失败结果、工作区与版本记录结果、秘密不复制的合成 canary 结果、命令退出码及未覆盖项。

报告只能证明脚本观察到的事实。人工流程验证写清实际操作者与步骤，未验证就保留待验收；不回填猜测的 PASS。

## 6. 不做什么

不改安装器、值守、锁、派发器、模型路由、权限、qwb-lint 或质量门配置；不新增包／数据库／队列／UI；不自动更新现有项目安装副本；不运行生产 API、付费调用、发版或测试发布。不以本票为由清理他人工作树或整机进程。

working: 2026-09-22T10:59:37.317989+00:00 激活票03；票01 7c4c3d4、票02 bb9bbb6均已验收，当前基线 c7dddc4ca8518fd3aa0e3b004631ae7eedd82d6d；生产修复（含单次执行器选择与smoke夹具）已在基线。工作目录 /Users/rocky/projects/qonnwolfbuddy；主账本 /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-verification-report.md。主控沿用wF2:p3，既有pane新Sol medium执行、新Sol high审核；无staged/unstaged，预存docs/plans/保留；仅本票活跃。
scenarios-fp: 436dd5c1acc75ae189b6584d7e47d2b619b3e68c
wake: 2026-09-22T10:59:42Z state=running fp=8fd3f272a7e70e949fba678cb269ceb1bd3806b9
working: 2026-09-22T13:05:56+0200 票03执行证据；冻结基线 HEAD=c7dddc4ca8518fd3aa0e3b004631ae7eedd82d6d，未提交；仅改 bin/qwb-test.sh、tests/smoke.sh 现有第23节、templates/TASK.md 报告/验收门、templates/QWBUDDY.md §5/6。预存未跟踪 docs/plans/ 保留；无 staged。旧脚本真实 CLI red：/tmp/qwb-ticket03-red.EjAcdh，`bash bin/qwb-test.sh fast --project <临时项目> --report <新文件>` rc=2，stderr=错误：未知参数 --report，门未执行。
working: 2026-09-22T13:05:56+0200 最终定向驱动=/tmp/qwb-ticket03-smoke.M942fM/run.sh，原始日志=/tmp/qwb-ticket03-smoke.M942fM/final-section.log，真实 tests/smoke.sh 第23节 `SECTION_FAILS=0`、驱动 rc=0；独立临时项目=/tmp/qwb-ticket03-section.i2Qqbz。代表性报告 report-files/zero.md（门0）与 report-files/seven.md（门7）；对应零门 stdout/stderr、旧调用 stdout/stderr、七门 stderr 均在同目录。第23节确认旧 0/7 单次执行、原 stdout/stderr、旧调用不生成报告；报告 0/7 单次执行和透传；已存在/符号链接/目录/缺父目录/缺值/重复参数及不可写父目录均预检 rc=2 且计数0；门后落盘失败为门0→3、门7→7，计数1；门期间目标新出现不覆盖；元信息失败时门7仍7且无完整报告；非Git/Git查询失败 unknown、dirty 和门期间新提交的前后版本、symlink 项目物理目录、相对路径 caller cwd、项目内报告不污染落盘前采样均通过；合成 CMD/env/stdout canary 未进报告。
working: 2026-09-22T13:05:56+0200 `bash bin/qwb-test.sh fast --project "$PWD"`（无报告）rc=0，stdout/stderr 均0字节，原始输出=/tmp/qwb-ticket03-smoke.M942fM/fast.out 与 fast.err；`bash -n bin/qwb-test.sh && bash -n tests/smoke.sh && shellcheck bin/qwb-test.sh && git diff --check` rc=0。未跑 full（主控统一跑）；未做 UI/安装包/线上或人工验收；报告只证明临时配置门。未提交、未调审核者，留未提交四文件供独立审核。
wake: 2026-09-22T11:07:44Z state=running fp=c093c561ef3c5eba81bd9a47e7da3f5c31bbe92f
working: 2026-09-22T13:10:10+02:00 票03独立审核（本既有 Herdr pane wF2:pG，Codex 原生 session 01a0c8c5-7006-79a2-89bb-9ec7bf89626b）；固定 HEAD c7dddc4ca8518fd3aa0e3b004631ae7eedd82d6d，未提交四文件 final-content 审核，cached=0、白名单 untracked=0、仅 unstaged。冻结 /tmp/qwb-ticket03-audit.etIgXe/qwb-test.sh SHA256=11bf7ff4c1ad4bbcc18eda6d50acd2cc2ef87bc3b951edbd7f44b8c7d3082cc8，smoke.sh SHA256=f265c9eb08b422c40bdc31297b1c61263dc0605f8af9e763cf0e6d9a8bbbcac2；模板 TASK SHA256=a813a8fb50fb0a9ec0c30a6ce0056695cc28ed02c3f9f0382026b7919127229b、QWBUDDY SHA256=e7e158d29a98b088a2d9b90b6d47101be580e7d3693dd4e7e5570bbabf3c434c。预存 docs/plans/ 未动。Spec=AMEND（2 项必须修复）；Standards=PASS（0 项文档标准违反/实质 smell）；整体 AMEND。
working: 2026-09-22T13:10:10+02:00 审点① Spec 必修1：bin/qwb-test.sh:43 将旧调用 PROJECT_ROOT 从逻辑 pwd 改为 pwd -P；无 --report 的隔离项目 QWB_GATE_FAST=pwd、--project 指向 symlink 时，基线 stdout 以 /alias 结尾，候选以 /physical 结尾（两者 rc=0，stderr 空），违背“旧调用 stdout 原约定一致”，且可能改变依赖 PWD 的门行为。独立基线/候选证据 /tmp/qwb-ticket03-audit.etIgXe/independent-legacy-symlink.json，基线脚本 SHA256=371fb17cb0e3b120c3a3d1f605e49290cbcaff96ae665c1f5d4046ab822623db。最小方向：保留旧门运行用逻辑 PROJECT_ROOT/PWD，只为报告“项目目录”字段单独求物理规范路径，补无报告 symlink 旧接口回归。
working: 2026-09-22T13:10:10+02:00 审点① Spec 必修2：bin/qwb-test.sh:35-37、66，`fast --project <隔离项目> --report --project`（或 `--report --help`）把选项误作路径，macOS dirname 报 illegal option，脚本 rc=1、门计数0；票据要求 --report 缺值/目标不合法 rc=2 且清楚报错。独立证据 /tmp/qwb-ticket03-audit.etIgXe/independent-results.json。最小方向：参数解析时识别下一 token 是选项或在路径规范化前统一把解析/路径错误映射为 rc2，补真实 CLI 回归；避免将合法相对文件名误判。
working: 2026-09-22T13:10:10+02:00 审点②/③：独立运行 tests/smoke.sh 第23节定向驱动 `bash /tmp/qwb-ticket03-smoke.M942fM/run.sh` rc=0、SECTION_FAILS=0（本轮临时目录 /tmp/qwb-ticket03-section.UnKP0d）；报告0/7、stdout/stderr、单次执行、版本/前后状态、合成秘密 canary、路径预检/写失败均有真实 CLI 断言，旧第23节断言未删改。独立冻结脚本在门运行中新增普通文件/目录/符号链接三例均 rc3、计数1、原目标保留（independent-results.json）；与主控补测一致。TASK 报告/验收门及 QWBUDDY §5/6 保留前票场景、审核裁定与模型政策，明确报告非产品验收及复用条件。`git diff --check`、两个 `bash -n`、`shellcheck bin/qwb-test.sh` 均 rc0。未运行 full（主控正在执行）；未覆盖 UI、安装包、线上及人工验收。新 smoke 未覆盖上述两项失败路径，须随修复补例；本轮未改源码、未采信执行者结论。

working: 2026-09-22T11:10:32.232995+00:00 主控首次full=0/112.556s（/tmp/qwb-ticket03-full.log，未提交文件hash见/tmp/qwb-ticket03-full.json），但独立对照发现无--report的symlink项目入口使pwd输出从旧alias变physical，证据/tmp/qwb-ticket03-legacy-symlink.json，待审核裁定；暂不放行。另主控/tmp/qwb-ticket03-controller-check.py三项真实门运行中目标新建file/directory/symlink均rc3、门次数1、目标保留，输出/tmp/qwb-ticket03-controller-check.json。

working: 2026-09-22T11:11:11.116250+00:00 主控裁定审核两项均成立并采纳：无report逻辑目录语义必须兼容；report缺值/选项误作路径的错误码必须2。已仅交这两项返修，白名单收窄至qwb-test与smoke第23节，模板保持。本轮全门PASS保留作历史候选证据，返修后重验，不把它当新候选PASS。
wake: 2026-09-22T11:11:45Z state=running fp=3bd267d48fe5e3edf06989975d73bc437799c1da
working: 2026-09-22T13:13:11+0200 票03 AMEND 两项返修；固定 HEAD c7dddc4ca8518fd3aa0e3b004631ae7eedd82d6d，未提交。仅改 bin/qwb-test.sh 与 tests/smoke.sh 第23节；templates/TASK.md SHA256=a813a8fb50fb0a9ec0c30a6ce0056695cc28ed02c3f9f0382026b7919127229b、templates/QWBUDDY.md SHA256=e7e158d29a98b088a2d9b90b6d47101be580e7d3693dd4e7e5570bbabf3c434c，与独立审核冻结值相同。返修后 qwb-test.sh SHA256=fd133e0c2559f98e166151b8dabf9dc35cd5aabd3c754600ed4d6d251f33ba1d，smoke.sh SHA256=0d64e5bd16f93ed98be5994d704c642c85b65c11c6005d31c5baa2f1a845688e。
working: 2026-09-22T13:13:11+0200 red 证据 /tmp/qwb-ticket03-amend-red.1StEKr/section.log：真实第23节 SECTION_FAILS=7、驱动rc1，涵盖 --report 后接 --project/--help/-h/--report 各rc1、合法前导横线相对路径rc1、无报告及带报告 symlink PWD 回归；同目录 baseline-qwb-test.sh 从固定 HEAD 提取，baseline symlink stdout=/tmp/qwb-ticket03-amend-red.1StEKr/alias，返修前候选 stdout=/private/tmp/qwb-ticket03-amend-red.1StEKr/physical，两者rc0。green 证据 /tmp/qwb-ticket03-amend-green.6hictT/section.log：真实第23节 SECTION_FAILS=0、驱动rc0；选项 token 均rc2且计数0，合法 -relative-sub/report.md rc0。最终独立 CLI 同一 symlink 项目 baseline 与候选无报告 stdout/stderr cmp均rc0、脚本均rc0；带报告 stdout仍alias、报告项目目录为/private/tmp/qwb-ticket03-amend-red.1StEKr/physical且门rc0，输出与报告见 red 目录 *-final.out/err、symlink-report.md。
working: 2026-09-22T13:13:11+0200 返修后 `bash bin/qwb-test.sh fast --project "$PWD"` 无报告rc0（/tmp/qwb-ticket03-amend-green.6hictT/fast.out 与 fast.err）；`bash -n bin/qwb-test.sh && bash -n tests/smoke.sh && shellcheck bin/qwb-test.sh && git diff --check` rc0。第23节旧断言、0/7/3/2语义、单次执行、采样、合成秘密 canary 回归均绿。主控上一候选 full rc0/112.556s 属历史证据；本轮未跑 full，由主控决定新候选统一验收。未提交、未自行调审核者，冻结当前未提交内容供原 Sol high 增量复审。
wake: 2026-09-22T11:13:46Z state=running fp=bd75466d0351a72b4178563bd083b582cce61c41
working: 2026-09-22T13:15:39+02:00 票03原审核会话增量复审（Herdr wF2:pG，Codex 原生 session 01a0c8c5-7006-79a2-89bb-9ec7bf89626b）：固定 HEAD=c7dddc4ca8518fd3aa0e3b004631ae7eedd82d6d；仅对首次冻结 /tmp/qwb-ticket03-audit.etIgXe/qwb-test.sh、smoke.sh 与本轮未提交候选的增量 diff 及直接依赖复审，cached=0、白名单 untracked=0。返修候选冻结 /tmp/qwb-ticket03-recheck.LgJ0HV/candidate-qwb-test.sh SHA256=fd133e0c2559f98e166151b8dabf9dc35cd5aabd3c754600ed4d6d251f33ba1d，candidate-smoke.sh SHA256=0d64e5bd16f93ed98be5994d704c642c85b65c11c6005d31c5baa2f1a845688e；模板 TASK/QWBUDDY SHA256 分别 a813a8fb50fb0a9ec0c30a6ce0056695cc28ed02c3f9f0382026b7919127229b、e7e158d29a98b088a2d9b90b6d47101be580e7d3693dd4e7e5570bbabf3c434c，均与前轮相同。Spec=PASS（原两项已修，新 diff 无新增问题）；Standards=PASS；整体增量复审 PASS。
working: 2026-09-22T13:15:39+02:00 复审独立证据：/tmp/qwb-ticket03-recheck.LgJ0HV/results.json 的真实 CLI：无 --report 的同一 symlink 项目 baseline/候选脚本 rc 均0、stdout/stderr 逐字节相同；带 --report 门 stdout 保持基线逻辑 alias，stderr 保留门输出并追加报告提示，报告项目目录为物理规范路径，rc0。`--report` 后接 --project/--help/-h/--report 四例均 rc2、计数0；合法 `-relative.md` 和 `-relative-sub/report.md` 均 rc0、计数1并生成目标。新增 smoke 断言覆盖这两项，旧第23节断言未删改。独立运行 `bash /tmp/qwb-ticket03-smoke.M942fM/run.sh` rc0、SECTION_FAILS=0，日志 /tmp/qwb-ticket03-recheck.LgJ0HV/section23.log；`bash -n bin/qwb-test.sh && bash -n tests/smoke.sh && shellcheck bin/qwb-test.sh && git diff --check` rc0。未跑 full（主控正在跑新候选）；本次未重审原已通过的其他报告路径，也未覆盖 UI、安装包、线上及人工验收；本轮未改源码。
wake: 2026-09-22T11:15:47Z state=running fp=5191efe26bb6caab46000f0d51eb98279c048b3a

working: 2026-09-22T11:18:47.661407+00:00 主控最终验收票03：实现提交 e7e0ad3e43e64f0da4fcb646b7a07955fe0d649a；仅bin/qwb-test.sh、tests/smoke.sh第23节、templates/TASK.md报告/验收门、templates/QWBUDDY.md§5/6。两项AMEND已独立闭环，Spec/Standards PASS；最终full=0/162.738s，SMOKE/REVIEW-IDENTITY/LINT PASS（/tmp/qwb-ticket03-r2-full.log，四文件hash收据/tmp/qwb-ticket03-r2-full.json与已提交blob一致）。fast无报告=0；提交后fast带报告=0，实际提交报告 /tmp/qwb-ticket03-final-woovtq29/fast.md；该报告如实记录dirty（预存docs/plans/与本票未跟踪），不假报clean。
working: 最新冻结候选的代表性报告：/tmp/qwb-ticket03-section.KjHcIC/report-files/zero.md（门0），/tmp/qwb-ticket03-section.KjHcIC/report-files/seven.md（门7）；与独立r2定向日志/tmp/qwb-ticket03-recheck.LgJ0HV/section23.log对应。旧调用和新调用单次执行/透传、参数路径错误2且次数0、门0报告失败3、门7报告失败仍7、运行中目标新建不覆盖、版本变化/dirty/unknown、合成CMD/env/stdout不复制、symlink兼容均有实际CLI证据。门前后版本属于实际测试项目，源脚本hash由本票复审及full收据另绑定；报告不是签名或产品验收。
working: 执行session=01a0c8c5-7006-7921-a6a2-17a912cc3f69，独立审核session=01a0c8c5-7006-79a2-89bb-9ec7bf89626b，复用既有Herdr窗口且沿用用户今日模型授权。未覆盖真实UI、安装包、线上或人工产品验收；无部署/发版/push/自动升级客户端或Sites。票01与02改动完整保留；三票总核心改动恰为交接包七个文件。state=verified。
