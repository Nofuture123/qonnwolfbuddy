# 任务书：Pi 档位解析统一、模型家族表改为项目声明、模板补 sol 工人

```
任务 id:  audit-pi-profile
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」「我定不了…还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F19、F22）；口径由主控按 Rocky 2026-10-04 的委托裁决
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-pi-profile.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-pi-profile（隔离副本，detached HEAD，起点 main bea487d）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。本仓是他之后所有项目的初始化脚本，模板里的工人声明就是他每个新项目的默认配置。

三件事（行号以 `4678ba0` 为准，已有偏移，自己重新定位）：

**F19：Pi 固定档位的解析有两份，宽严不一。**
`bin/qwb-lib.sh` 的 `qwb_gate_profile` 要求 argv 里 `--provider` 恰好出现一次；`bin/qwb-role.sh` 的 `model_profile` 在没有 `--provider` 时会从 `--model` 的前缀里拆出渠道。于是模板自带的 `pi-glm-high`（`--model zai-coding-cn/glm-5.3`，无 `--provider`）能当常驻角色，却不能当门禁审核工人。主控裁决：**必须显式写 `--provider`，不从模型名里猜**。理由：使用者现在的主力模型 ID 是 `codex/gpt-6.1-sol`（渠道 `magpie`），模型 ID 本身带斜杠，按斜杠拆一定拆错。

**F22：模型家族表写死在账本脚本里。**
`bin/qwb-ledger.sh` 里 `%known_family` 只有三个 `渠道/模型` 到家族的映射，模板 `workers.sh` 里的具名工人一个都不在表里；每换一次模型都要改脚本并重装所有项目。主控裁决：**挪到项目的工人配置里声明**，没声明的仍判 `unknown` 并拒绝。

**模板缺使用者现在的主力工人。**
使用者现在派 Pi 用的是 `--provider magpie --model codex/gpt-6.1-sol --thinking high`，模板 `templates/workers.sh` 与 `templates/config.sh` 的工人表里没有这一项，每个新项目都得手工加。

白名单：`bin/qwb-lib.sh`、`bin/qwb-role.sh`、`bin/qwb-ledger.sh`、`bin/qwb-dispatch.sh`（仅在它的工人声明解析受影响时）、`bin/qwb-init.sh`（仅在安装器需要认识新声明时）、`templates/workers.sh`、`templates/config.sh`、`templates/worker-launch-guide.md`（同步写法说明）、`tests/` 下为验收所需的文件。

### 工程规格

1. **统一 Pi 档位解析**：让 `qwb-role.sh` 与 `qwb_gate_profile` 用同一套规则——`--provider`、`--model`、`--thinking` 各恰好出现一次且非空。规则只留一处实现（role 是 python、lib 是 bash 加 python，选一个合适的落点让两边共用，或两边调用同一个入口）。`qwb-role.sh` 原来能接受的「无 `--provider`、`--model` 带渠道前缀」写法，现在给出清楚的中文拒绝信息，告诉使用者怎么改。这是有意的行为收紧。
2. **模板里的工人声明全部改成显式渠道**：`pi-glm-high` 改为 `--provider zai-coding-cn --model glm-5.3`；其余用 `渠道/模型` 合写的 pi 与 omp 声明先确认各 CLI 是否接受分开写法（只读地查 `pi --help`、`pi --list-models`；omp 没法确认就不动并写明）。
3. **模板新增 `pi-sol-high`**：`qwb_worker pi-sol-high herdr pi -- --approve --provider magpie --model codex/gpt-6.1-sol --thinking high`，并加进 `templates/config.sh` 的 `QWB_WORKERS`。同步检查 smoke 里对模板工人表的断言（有断言整份清单的地方），按新清单更新这些断言——这是本票唯一允许改的既有断言，改之前先列出来。
4. **家族声明**：在工人配置里增加声明（例如 `qwb_family <渠道>/<模型ID> <家族>`，模型 ID 可含斜杠，所以按「第一个参数整体是键」处理，不要按斜杠拆）。`bin/qwb-ledger.sh` 判家族时读项目的声明，脚本里不再写死映射；声明缺失、重复、家族不在允许的集合里（先看现有代码与 `templates/TASK.md` 第 5 节认哪些家族）都按 `unknown` 处理并拒绝，文案沿用现有的。声明文件已经被 `workers_sha256` 绑定进授权，确认新增的声明同样在这个指纹的覆盖范围内。
5. 模板 `workers.sh` 为它自带的每个具名模型补上家族声明；原来写死的三个映射也要以声明的形式出现在模板里（保持已有项目重装后行为不倒退）。
6. `bin/qwb-lib.sh` 的 `qwb_load_workers`、`bin/qwb-dispatch.sh` 的工人声明解析、`bin/qwb-init.sh` 的迁移与预检：新声明出现在 `workers.sh` 里时它们不能报「未知声明」或把它当成工人。逐个确认并写明。
7. 已经装过的项目，`workers.sh` 是保留不覆盖的：没有家族声明的旧配置在需要判家族时会被拒绝。拒绝信息里要写明「在 `qwbuddy/workers.sh` 里补哪一行」。

## 1. 验收场景

### user_正常路径_显式渠道的Pi工人既能当角色也能当门禁审核

Given 新装的项目（模板里的 `pi-sol-high` 与 `pi-glm-high` 都是显式 `--provider`）
When  分别用它们走常驻角色的档位核对与门禁审核工人的档位核对（用现有协作测试里的办法，假 herdr）
Then  两条路都接受，取到的渠道、模型、思考档位与声明一致；`pi-sol-high` 的模型 ID `codex/gpt-6.1-sol` 没有被按斜杠拆开

### user_失败路径_没写渠道的Pi声明被明确拒绝

Given `workers.sh` 里一条只有 `--model 渠道/模型`、没有 `--provider` 的 pi 声明
When  拿它当常驻角色或门禁审核工人
Then  两条路都拒绝，信息写明缺 `--provider` 以及正确写法；不发生任何 herdr 调用与账本写入。同样输入在起点提交上，常驻角色那条路是接受的——这是有意的收紧

### user_正常路径_家族来自项目声明

Given 项目 `workers.sh` 声明了 `magpie/codex/gpt-6.1-sol` 属于 `gpt`、某个 claude 模型属于 `claude`
When  走门禁审核的家族核对（实现与审核须不同家族）
Then  不同家族通过，同家族被拒，行为与原来用写死映射时相同；换一个模型只需改 `workers.sh`，不用改脚本

### user_失败路径_没声明家族的模型被拒并告诉怎么补

Given 一个在 `workers.sh` 里有工人声明、但没有家族声明的模型
When  走需要判家族的路径
Then  按 `unknown` 拒绝；信息指出要在 `qwbuddy/workers.sh` 里补的那一行；重复声明、家族名不合法同样被拒

### user_正常路径_新装项目自带sol工人且其余入口不受新声明影响

Given 用改后的安装器新装一个临时项目
When  读它的 `qwbuddy/workers.sh` 与 `qwbuddy/config.sh`，并跑 `qwb-run.sh --worker pi-sol-high`（假 herdr）、`qwb-lint.sh`、`qwb-dispatch.sh` 的工人清单
Then  `pi-sol-high` 在工人表里且恰有一条声明；派发时假 herdr 收到的 argv 逐项是 `--approve --provider magpie --model codex/gpt-6.1-sol --thinking high`；lint 通过；家族声明没有被任何入口当成工人或报成未知声明

### user_失败路径_旧项目重装不被破坏

Given 一个用起点提交装好的项目（旧 `workers.sh`、旧 `config.sh`）
When  用改后的安装器重装
Then  使用者已有的 `workers.sh` 与 `config.sh` 原样保留；普通派发照常工作；只有走到需要判家族的路径时才提示补声明

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程。不许为做压力验收而起烧 CPU 的进程——这台机器是共用的。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 本仓会被装进使用者之后的每一个项目：宁可少做，不可改坏。每一项单独做、单独自检；不能确认等价的就跳过并写明原因。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 模板是使用者每个新项目的默认配置：除本票写明的三处（显式渠道、新增 `pi-sol-high`、家族声明）外，不改任何默认值、权限参数与注释含义。
- 常驻角色那套「未验证即拒绝」的限制（仅 herdr pi、`QWB_ROLE_PI_CONTROL=verified` 等）一条都不放宽。
- 不改 `bin/qwb-run.sh`、`bin/qwb-wake.sh`、`bin/qwb-worktree.sh`（另有票在动）。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 各场景逐个验证，命令与原始结果写进 `done:` 行；逐项写明做了什么、跳过了什么及原因、各文件行数前后变化。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点主仓是 840 PASS / 0 FAIL（副本里没有 `qwbuddy/config.sh`，少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T12:26:14Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-pi-profile pane=w14Z:pK dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-pi-profile base=bea487d
working: 2026-10-04T12:28:13Z 阶段1完成：已完整读取任务书、审核r1和TASK第5节；定位共享解析与家族核对。改前列出唯一允许更新的既有断言：tests/smoke.sh:94整份QWB_WORKERS清单、:893模板工人遍历清单、:896声明数9改10；:881的source夹具须增加qwb_family空入口（断言不改）。pi --help与--offline --list-models确认显式provider及含斜杠model；omp --help列出legacy --provider，进一步只读核对后决定是否拆分。现有lint不设家族枚举且测试认可qwen；本票声明允许gpt/claude/gemini/glm/qwen/swe（swe对应模板Devin自带型号），在说明中明确。
working: 2026-10-04T12:38:52Z 阶段2完成：共享qwb_pi_profile已接role与gate；角色start缺provider先拒绝，保留opt-in/adapter白名单；模板GLM显式渠道且新增pi-sol-high；qwb_family从项目workers整体键取家族并沿用workers_sha256。qwb_load_workers与dispatch添加独立家族入口；init逐项复核不执行/解析已有workers，预检与迁移无需改动。快门bash bin/qwb-test.sh fast退出0、无新增shellcheck告警；新增场景补齐真实role与旧起点收紧对照，现继续家族与全门验收。
working: 2026-10-04T12:43:43Z 阶段3场景完成：bash tests/pi-profile.sh退出0；collab-roles正常角色、新旧provider对照均已PASS，后续将完整复跑；bash tests/collab-gate.sh退出0（日志.qwb-tmp/pi-profile-gate.log，完整回执pi-profile-gate.exit）。补充改前清单：tests/optional-routing.sh:370-374整份具名模板候选表须加入pi-sol-high并把GLM预期model改为glm-5.3；这是smoke调用的模板工人表断言，逐项argv判定逻辑不变。tests/smoke.sh:3418旧名夹具过滤表须排除新增pi-sol-high（夹具修订、断言不改）。另查实dispatch额度lane原从model首段取渠道，显式provider后须按provider构造额度键，防GLM额度错账户及Sol误认codex为渠道。
working: 2026-10-04T12:47:46Z 阶段4完成并提交809420c174949303be65ff686bdc4e6ee8d0a23d：快门退出0；场景r2退出0、5 PASS/0 FAIL；/bin/bash tests/collab-roles.sh退出0、20 PASS/0 FAIL；/bin/bash tests/optional-routing.sh退出0、48 PASS/0 FAIL；bash tests/collab-gate.sh退出0、19 PASS/0 FAIL。计数逐项grep -c核过原始日志；git diff --check通过，提交后git status --short为空。现在冻结提交并跑一次bash bin/qwb-test.sh full，日志.qwb-tmp/pi-profile-full.log，退出回执pi-profile-full.exit。
working: 2026-10-04T12:56:04Z 全门首轮失败：809420c上bash bin/qwb-test.sh full退出1、803 PASS/1 FAIL（grep -c已核）；唯一FAIL=smoke第51h节默认workers自洽，miss为空但总数仍硬编码9。改前补列允许更新的模板清单断言：tests/smoke.sh:3527的QWB_WORKERS词数9改10；不改名称/唯一性判定。首轮日志pi-profile-full.log及退出回执保留；修正该遗漏后追加提交并重新冻结全门。
working: 2026-10-04T12:56:48Z 模板清单漏项已修：第51h节只把总数9改10，名称与唯一性断言保留；逐段真实断言对照previous rc1/FAIL、corrected rc0/PASS（pi-profile-count-check.log）；快门r3退出0。追加提交ff79a1e429db3359b8b0f0d5969f6301bb1869c2，git status --short为空；现在最终提交上重跑完整full，独立r2日志与退出回执保留首轮失败证据。
done: 2026-10-04T13:11:41Z 最终commit=ff79a1e429db3359b8b0f0d5969f6301bb1869c2；完成：Pi的provider/model/thinking唯一共享解析，缺provider中文说明正确写法且role/gate零Herdr及角色/账本写入；role原adapter/opt-in/参数白名单保留，Sol modelId codex/gpt-6.1-sol未拆斜杠；模板新增pi-sol-high、GLM显式渠道与9项家族声明（允许gpt/claude/gemini/glm/qwen/swe，含原3映射）；家族从workers完整键读取，跨家族通过、同家族及缺失/重复/非法声明拒绝，拒绝指出qwbuddy/workers.sh补声明键；只改家族使workers_sha256授权失效；qwb_load_workers与dispatch识别家族非工人，dispatch quota消费显式provider；新装sol唯一声明且run argv逐项为--approve --provider magpie --model codex/gpt-6.1-sol --thinking high，lint与dispatch清单通过；真实起点安装重装workers/config逐字节保留、普通派发及显式迁移幂等通过、旧配置在判家族时unknown。跳过：OMP拆分（help有legacy provider但未证明型号解析等价，合写保留并已说明）；qwb-init无需修改（预检/迁移不执行解析workers，新声明兼容已验）。既有断言只更新模板清单/总数/型号预期，其他只补夹具与新增回归。验证原始结果：bash bin/qwb-test.sh fast最后r3 rc0；bash tests/pi-profile.sh r2 rc0 5 PASS/0 FAIL；/bin/bash tests/collab-roles.sh r2 rc0 20 PASS/0 FAIL；/bin/bash tests/optional-routing.sh rc0 48 PASS/0 FAIL；bash tests/collab-gate.sh rc0 19 PASS/0 FAIL；起点bea487d真实role对相同无provider输入rc0（有意收紧对照）；默认表计数断言previous rc1/FAIL→corrected rc0/PASS。全门首轮809420c rc1 803 PASS/1 FAIL（漏改51h总数9，追加ff79a1e修为10，首败日志保留）；最终提交后bash bin/qwb-test.sh full r2 rc0、840 PASS/0 FAIL，grep -c逐项核过完整日志，SMOKE/REVIEW-IDENTITY/LINT/COLLAB-ALL(12项)全过。全门末5行各前100字符=["PASS  tests/collab-roles.sh（94s）", "PASS  tests/collab-test-policy.sh（114s）", "PASS  tests/lint-scenario-stream.sh（6s）", "PASS  tests/path-canonicalization.sh（0s）", "COLLAB-ALL PASS（12 项）"]；行数前后={"bin/qwb-dispatch.sh": [431, 440], "bin/qwb-ledger.sh": [1660, 1660], "bin/qwb-lib.sh": [516, 554], "bin/qwb-role.sh": [442, 441], "templates/config.sh": [32, 32], "templates/worker-launch-guide.md": [11, 13], "templates/workers.sh": [19, 33], "tests/collab-gate.sh": [456, 494], "tests/collab-land.sh": [360, 360], "tests/collab-planning.sh": [352, 352], "tests/collab-posture.sh": [229, 229], "tests/collab-roles.sh": [260, 301], "tests/collab-test-policy.sh": [183, 183], "tests/optional-routing.sh": [425, 426], "tests/pi-profile.sh": [0, 128], "tests/smoke.sh": [4854, 4854]}；bin/qwb-init.sh未改485→485；全门后git status --short=""；残留进程清单=[]、全部登记gate/narrow/full/r2根PID均已自然退出、临时目录无残留。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-pi-profile/.qwb-tmp，最终全门pi-profile-full-r2.log/exit、首败pi-profile-full.log/exit、场景与定向日志及pi-profile-final-metadata.json保留。
working: 2026-10-04T13:24:51Z 主控验收：模板与账本脚本的 diff 已审（模板新增 pi-sol-high 并入默认工人表、pi-glm-high 改显式渠道、9 条家族声明；Pi 档位解析只留一处，缺 --provider 明确拒绝；家族由 qwb_model_family 读项目声明，账本不再写死映射）；在副本 ff79a1e 上独立跑 bash bin/qwb-test.sh full：rc=0、840 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、651.82s；bash tests/pi-profile.sh rc=0、5 PASS；无残留进程、工作区干净。已 cherry-pick 809420c、ff79a1e 到 main（HEAD=68d0e63），与同波已落地的 audit-worktree-tidy 无冲突。omp 那条声明仍为渠道与模型合写，执行者无法证明分写等价而保留，主控认可。
