# 任务书：herdr 查询应答的解析收成一层

```
任务 id:  audit-herdr-parse
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」「我定不了…还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F18）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-herdr-parse.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-herdr-parse（隔离副本，detached HEAD，起点 main bea487d）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。本仓是他之后所有项目的初始化脚本，同一条规则多处手抄造成的不一致会被复制到每个项目里。

`herdr` 的查询应答现在由各脚本各自用内嵌 perl 解析，同一个字段、同一个判定写了很多遍，而且已经宽严不一（审核时的行号以 `4678ba0` 为准，已有偏移，自己用 grep 重新列全）：

- `herdr pane get`：`bin/qwb-run.sh` 约 4 处、`bin/qwb-wake.sh` 的 `pane_info`、`bin/qwb-lib.sh` 的 `worker_lost`。
- 「pane 不存在」的判定两种写法并存：有的 grep 应答原文里的 `pane_not_found`，有的解析 JSON 的 `error.code`。
- `herdr pane process-info` 的「前台是空闲 shell」（`foreground_process_group_id == shell_pid`）：`bin/qwb-run.sh`、`bin/qwb-wake.sh` 的 `pane_probe` 各一份。
- `herdr tab create` 取 `result.root_pane.pane_id` 与 `tab_id`：`bin/qwb-run.sh`（严格校验必须是 JSON 字符串）与 `bin/qwb-wake.sh`（宽松）各一份。
- 「调用者 workspace = 环境变量，否则 pane get」的推导：`bin/qwb-run.sh` 与 `bin/qwb-wake.sh` 各写一遍，深度不同。

白名单：`bin/qwb-lib.sh`、`bin/qwb-run.sh`、`bin/qwb-wake.sh`。

### 工程规格

1. 先把上面每一类的全部出现处列成表（文件、行号、取了哪些字段、失败时怎么处理、对畸形应答的容忍度），写进第一条 `working:` 行。
2. 在 `bin/qwb-lib.sh` 新增解析函数，把 `bin/qwb-wake.sh` 现有的 `pane_info` 契约提升为共享版本（例如输出 TSV `pane_id agent agent_status cwd workspace_id tab_id`，返回码 0 / 3=pane 不存在 / 2=其他失败），以及「前台是空闲 shell」与「tab create 应答取 pane 与 tab」两个函数。函数只负责「查询并解析」，**各调用点原有的报错文案、失败后的处置（拒绝、回滚、警告）留在调用点**。
3. 逐个调用点替换。替换前对该调用点证明：对「正常应答」「pane 不存在」「herdr 非 0 退出」「应答不是 JSON」「字段缺失」「字段类型不对（数字、null、数组）」「字段为空串」这七种输入，新旧的 stdout、stderr、退出码相同。有任何一种不同，就让这个调用点保持原样并写明差异——**不要为了统一去改变任何调用点的宽严**。宽严确实不同的地方，共享函数可以带参数区分，或干脆只让语义相同的那几处共用。
4. 记住制表符 IFS 会合并空字段：共享函数的输出要么保证每列非空（用占位符），要么把可能为空的列放最后，并写进注释。
5. 不动 `bin/qwb-worktree.sh`、`bin/qwb-lock.sh`、`bin/qwb-herdr.sh`、`bin/qwb-role.sh`、`bin/qwb-ledger.sh` 里的同类解析（另有票在动 worktree；其余几个用 python 或有各自的超时与安全语义）。在 `done:` 行里列出这些留下来的地方，供后续参考。
6. `herdr` 的调用次数与顺序不许变（smoke 里有按调用日志断言的用例）。

## 1. 验收场景

### user_正常路径_派发与值守的可见行为逐字节不变

Given 起点提交的 `bin/`（git archive 导出到副本 `.qwb-tmp/` 下）与改后的 `bin/`，以及用假 herdr 的临时项目
When  新旧各跑：`qwb-run.sh` 的首次派发、复用同名 idle 工人续派、`--pane` 复用既有 shell pane、pane-run 派发；`qwb-wake.sh` 的 `--check`、`--ensure`（原 pane 重启与新开 tab 两条路）、`--once`（含工人丢失判定）
Then  stdout、stderr、退出码、任务书写入、假 herdr 调用日志逐字节相同

### user_失败路径_畸形应答下各调用点行为不变

Given 假 herdr 对 `pane get`、`pane process-info`、`tab create` 分别返回：pane 不存在、非 0 退出、非 JSON、缺字段、字段类型不对、字段为空串
When  新旧各跑会走到这些查询的入口
Then  每一种组合下新旧的 stdout、stderr、退出码、是否继续往下发 herdr 调用，逐一相同；原来拒绝的仍然拒绝，原来只警告的仍然只警告

### user_失败路径_工人丢失判定不漏不误

Given 一张 `state: running`、最后一条 `dispatch:` 指向某 pane 的票；该 pane 分别是：存在且有 agent、存在但已回到空闲 shell、不存在、查询失败
When  新旧各跑 `qwb-wake.sh --dry-run --once`
Then  四种情况下是否判为工人丢失、输出与退出码新旧相同——查询失败时不得被当成丢失

### user_正常路径_规则只剩一处

Given 改后的 `bin/qwb-lib.sh`、`bin/qwb-run.sh`、`bin/qwb-wake.sh`
When  grep 这三个文件里解析 `result.pane`、`foreground_process_group_id`、`root_pane` 的内嵌 perl
Then  除了你写明「因语义不同而保留」的调用点外，每一类只出现在 lib 的共享函数里；`done:` 行列出保留的调用点及各自的差异

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程。不许为做压力验收而起烧 CPU 的进程——这台机器是共用的。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 本仓会被装进使用者之后的每一个项目：宁可少做，不可改坏。每一项单独做、单独自检；不能确认等价的就跳过并写明原因。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 这是派发与值守的主路径。共享函数的行为由调用点的旧行为决定，不是反过来。
- 不改 `bin/` 下白名单以外的文件、`templates/`、`tests/`。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 各场景逐个验证，命令与原始结果写进 `done:` 行；逐项写明做了什么、跳过了什么及原因、各文件行数前后变化。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点主仓是 840 PASS / 0 FAIL（副本里没有 `qwbuddy/config.sh`，少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T12:26:07Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-herdr-parse pane=w14Z:pH dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-herdr-parse base=bea487d
working: 2026-10-04T12:27:51Z 阶段1完成；出现处表（起点 bea487d，列=文件:行｜字段｜失败处置｜宽严）：bin/qwb-run.sh:323-330｜cwd/agent｜查询失败拒绝、解析空拒绝｜缺字段变空，数字/数组可字符串化；:334-341｜process_info.foreground_process_group_id/shell_pid｜查询或非idle拒绝｜仅defined+数值相等；:355-358｜workspace_id｜空/不匹配拒绝｜任意非ref标量含数字；:394-399｜调用者workspace_id｜查询拒绝、解析空拒绝｜环境优先、非ref标量；:403-415｜pane_id/agent/cwd/workspace_id｜查询/身份不全拒绝｜HASH+四列非空非ref，数字可接受；:743-764｜root_pane.pane_id/tab_id｜pane缺失拒绝、tab缺失留空供回滚｜pane严格JSON字符串、tab非空非ref标量；:630-643｜worktree open root_pane pane_id/tab_id/workspace_id｜回滚拒绝｜不同端点严格形状，保留。bin/qwb-wake.sh:111-122 pane_info（调用309/319/396/420）｜cwd/agent/workspace_id｜rc0/3不存在/2其他失败，调用点拒绝或检查｜原文含pane_not_found识别，缺字段空、引用字符串化；:127-159 pane_probe（调用196/264/361/392/431）｜process_info/foreground_processes/argv/pid/cwd/两PID｜wake/idle/busy/gone/err交调用点复用或拒绝｜先匹配真实值守再数值idle，非0原文判不存在；:454-459｜root_pane.pane_id｜查询失败/空拒绝｜宽松字符串化含数字/引用；:306-314｜调用者workspace｜环境优先否则pane_info第三列｜与run标量规则不同。bin/qwb-lib.sh:490-515 worker_lost（wake:591调用）｜agent/agent_status｜丢失rc0、存活rc1、未知rc2+stderr｜非0原文判不存在，pane须HASH且agent键存在，空agent判丢失。列外同类点将在done行清单保留；未改代码。
working: 2026-10-04T12:28:39Z 表格补正：lib:505-515 当前worker_lost并不要求agent键存在；缺失/null/空agent返回unknown rc2并保留现场，不证明工人死亡。后续以起点源码实测为准。计划共享wake的pane_info/pane_probe及run的idle/workspace解析，tab字段用严格pane、宽松tab与wake三种既有策略；run --pane身份、reuse身份与worker_lost因契约不同保留。
working: 2026-10-04T12:43:34Z 阶段2/3完成；七类输入加数字/null/数组/空串逐字段和包络反例，候选解析189组字节相同，4组差异仅属保留点（pane_info的agent/cwd/workspace数组与wake tab pane_id数组打印ARRAY地址）；实际入口90 PASS/0 FAIL，worker_lost另10 PASS/0 FAIL。命令：python3 -B .qwb-tmp/hparse.bCAkBC/parsers.py；python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/hparse.bCAkBC/entries.py；python3 -B .qwb-tmp/hparse.bCAkBC/lost.py。入口比较stdout/stderr/退出码/任务书与watch字节/herdr逐参数日志；固定随机op、外部date与writer strftime，项目路径及真实PID/start/session在两版间相同，未替换业务判定。entries-r1夹具遗漏pane-run agent成功响应、r2为writer时间不同，均保留失败日志；r3工具60s中断且无退出回执，已清本次进程组19809；r4后台受监督完整退出0。保留run --pane两列宽松身份/reuse四列身份/worktree open多字段所有权、lib worker_lost独立unknown语义、wake pane_info和宽松tab；不为统一收紧。起点dry-run跳过worker_lost，四种dry-run与四种真实once均已对照；fast退出0、git diff --check退出0，待提交后全门。
working: 2026-10-04T12:44:26Z 阶段4执行中；已提交8dbdd27dc8c4f32fe7deeac7213184b5e9100bac，detached HEAD无分支无push，提交后status为空。全门只启动本轮：python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full，日志=.worktrees/audit-herdr-parse/.qwb-tmp/hparse.bCAkBC/full.log，退出回执=full.rc，监督runner PID=26241；未绕过既有失效关闭、进程登记、socket夹具。
working: 2026-10-04T12:57:58Z 阶段4规格复查补正完成；共享pane_info以-占位保证每列非空，统一一般失败rc2、不存在rc3；因此原wake调用点继续原样，不把新接口差异传给现有用户。pane_probe查询/原文失败判定留在wake，只搬已有应答的解析到lib，查询数与顺序仍不变。最终parser对照181组相同，12组差异仅属未迁移点（空/null占位、旧类型异常255与新2、数组地址）；最终入口90 PASS/0 FAIL退出0，worker_lost10 PASS/0 FAIL退出0，共享接口5 PASS/0 FAIL退出0，fast退出0。此前全门被本次主动中断，rc143且未完成，不当通过；日志full.log及中断PID记录保留，拥有的runner26241/supervisor26244均已退出。两次追加提交中的最终提交=c6bdb700f8ea3d545f4fad736a66bcb19100a044，下一轮为最终提交全门。
done: 2026-10-04T13:17:34Z 全部完成；最终commit=c6bdb700f8ea3d545f4fad736a66bcb19100a044（前置追加提交8dbdd27dc8c4f32fe7deeac7213184b5e9100bac，detached HEAD，无分支无push）。只改bin/qwb-lib.sh、bin/qwb-run.sh、bin/qwb-wake.sh；行数分别516→595、838→821、979→957。共享化：run两处workspace标量提取、--pane空闲判定、tab pane_id/tab_id提取，wake真实值守进程probe解析；查询调用及错误处置留原调用点，idle与probe保留各自输出/优先级。shared pane_info新接口每列用-占位，0/3/2，因与原输出不同暂未接入现有调用者。执行/原始结果：bash bin/qwb-test.sh fast（fast-r2.log，rc0，shellcheck无新增告警）；python3 -B .qwb-tmp/hparse.bCAkBC/parsers.py（parsers-final.log，193组中181同/12差，已替换6类均等价；12差均在未迁移点）；python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/hparse.bCAkBC/entries.py（entries-final.log，rc0，按grep -c计90 PASS/0 FAIL：首发、idle续派、调用者workspace回退、--pane shell、worktree Space、pane-run、check、ensure原pane重启/新tab、once、工人四态真实once及dry-run共18变体，另9查询入口×8畸形/失败输入72组；stdout/stderr/自然退出码/任务书及watch写入/herdr逐参数日志逐字节一致）；python3 -B .qwb-tmp/hparse.bCAkBC/lost.py（lost-final.log，rc0，10 PASS/0 FAIL，查询失败与空标签仍unknown，不当丢失）；python3 -B .qwb-tmp/hparse.bCAkBC/shared-info.py（shared-info.log，rc0，5 PASS/0 FAIL，占位及返回码独立验证）；python3 -B .qwb-tmp/hparse.bCAkBC/ref-address.py（ref-address.log，旧对旧数组地址也不同）。明确保留：run:325-330两列cwd/agent宽松串化、:399-409 HASH且四列非空非ref身份、:622-634 worktree open所有权/回滚；wake:113-124 pane_info旧空列和数组地址/旧Perl类型错误255（新共享接口占位且rc2），:433-436宽松tab数组地址；lib:569-594 worker_lost独立HASH/unknown契约。白名单外全部未动：worktree:189-198/470-475/511-527、lock:88-93、herdr:154-159、role:114-120/196-200/369、ledger:558-575（含各自超时/权限/退出证明），供后票参考。全部提交后最终全门命令=python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full（完整原命令由fixture监督，不缩门不改断言），full-final.log/full-final.rc，rc0，按grep -c核839 PASS/0 FAIL（本副本缺qwbuddy/config.sh，比主仓840少lint一行），SMOKE/REVIEW-IDENTITY/LINT/COLLAB-ALL 12项均过。早期全门full.log主动中断rc143，不作通过，已保留中断记录与协作子日志；临时项目/stub已回收，所有测试进程已退出，只留忽略的验收证据目录。全门后status、进程清单、末5行各前100字符及准确计数原始收据={"sha":"c6bdb700f8ea3d545f4fad736a66bcb19100a044","full_rc":0,"full_pass":839,"full_fail":0,"tail5_100":["PASS  tests/collab-roles.sh（75s）","PASS  tests/collab-test-policy.sh（106s）","PASS  tests/lint-scenario-stream.sh（6s）","PASS  tests/path-canonicalization.sh（0s）","COLLAB-ALL PASS（12 项）"],"git_status_short":"","residual_test_processes":[],"temporary_root_entries":["hparse.bCAkBC"],"line_counts":{"bin/qwb-lib.sh":595,"bin/qwb-run.sh":821,"bin/qwb-wake.sh":957},"changed_files":["bin/qwb-lib.sh","bin/qwb-run.sh","bin/qwb-wake.sh"]}；证据根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-herdr-parse/.qwb-tmp/hparse.bCAkBC。
working: 2026-10-04T13:19:07Z 主控验收（返修 1）：你坚持「共享函数的行为由调用点的旧行为决定」、对有差异的 12 组不硬合，这个取舍我认可。两处须返修：一、bin/qwb-lib.sh 新增的 qwb_pane_info 在全仓没有任何调用方（主控 grep 复核：run 0、wake 0、其余 0）——本轮审核自己就把「零调用的函数」列为要删的死代码，不能再加一个；请删掉它，等将来真有调用方时再加。二、把你测出的那 12 组新旧不一致整理成一张表追加到主账本（一条 working 行即可）：哪个调用点、哪种输入、旧行为是什么、与共享契约差在哪。它是「同一查询在不同调用点宽严不一」的实证清单，主控要写进审核报告，留给以后有真 Herdr 证据时再决定是否对齐。改完追加提交，重跑快门、你那套 90 组入口对比与一次全门后报 done。
working: 2026-10-04T13:24:07Z 返修1阶段1完成：已核全仓无调用方并删除qwb_pane_info，lib从595减至578行，run/wake未改；git diff --check退出0。此前12组差异逐项表如下，保留原调用点，未对齐宽严；遵守本票白名单，经验已记入持久纠正记录，不修改主仓其他文件。

以下是此前 parsers-final.log 的12组原始差异；候选均未接入生产调用点，本轮已删除无调用方的 qwb_pane_info。C 仅在表格展示中代指 /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-herdr-parse，实际比较未归一化 stdout。stdout/stderr 中的 \t 是实际 TAB 的可读表示，\u003cSTDIN\u003e 表示原诊断的 STDIN 标记。前11行对比旧 pane_info 与已删除占位/rc2草稿；第12行对比旧 tab 解析与未落地的宽松 wake 模式草稿。数组地址四行是字节证明受不确定性阻挡，旧对旧重复也会不同，不将它们冒充功能/宽严变化。

| # | 调用点及具体输入 | 旧行为 | 当时未接入的共享候选 | 差异说明 |
| --- | --- | --- | --- | --- |
| 1 | wake pane_info:113；调用286/296/373/397；`result.pane=12` | stdout=`"\t\t"`；stderr=`""`；rc=0 | stdout=`"-\t-\t-"`；stderr=`""`；rc=0 | 旧实现容忍该标量并输出空列；候选把空列改为 -，并未改成类型拒绝。 |
| 2 | wake pane_info:113；调用286/296/373/397；`result.pane.agent=null` | stdout=`"C\t\tw"`；stderr=`""`；rc=0 | stdout=`"C\t-\tw"`；stderr=`""`；rc=0 | 中间 agent 空列变为 - 占位。 |
| 3 | wake pane_info:113；调用286/296/373/397；`result.pane.cwd=null，foreground_cwd缺失` | stdout=`"\tpi\tw"`；stderr=`""`；rc=0 | stdout=`"-\tpi\tw"`；stderr=`""`；rc=0 | 首列 cwd 空串变为 - 占位。 |
| 4 | wake pane_info:113；调用286/296/373/397；`result.pane.workspace_id=null` | stdout=`"C\tpi\t"`；stderr=`""`；rc=0 | stdout=`"C\tpi\t-"`；stderr=`""`；rc=0 | 尾列 workspace 空串变为 - 占位。 |
| 5 | wake pane_info:113；调用286/296/373/397；`result.pane=[]` | stdout=`""`；stderr=`"Not a HASH reference at -e line 5, \\u003cSTDIN\\u003e line 1.\n"`；rc=255 | stdout=`""`；stderr=`"Not a HASH reference at -e line 5, \\u003cSTDIN\\u003e line 1.\n"`；rc=2 | stdout同为空，stderr相同；候选把旧 Perl 原生退出码255统一成2。 |
| 6 | wake pane_info:113；调用286/296/373/397；`result.pane.agent=[]` | stdout=`"C\tARRAY(0x78e5204690)\tw"`；stderr=`""`；rc=0 | stdout=`"C\tARRAY(0x75992386d8)\tw"`；stderr=`""`；rc=0 | 均宽松串化数组；只因进程内引用地址不同而字节不等，不是类型校验规则改变。 |
| 7 | wake pane_info:113；调用286/296/373/397；`result.pane.cwd=[]，foreground_cwd缺失` | stdout=`"ARRAY(0x7a6d118690)\tpi\tw"`；stderr=`""`；rc=0 | stdout=`"ARRAY(0x7b7ee386d8)\tpi\tw"`；stderr=`""`；rc=0 | 均宽松串化数组；只因进程内引用地址不同而字节不等。 |
| 8 | wake pane_info:113；调用286/296/373/397；`result.pane.workspace_id=[]` | stdout=`"C\tpi\tARRAY(0x76ccd50690)"`；stderr=`""`；rc=0 | stdout=`"C\tpi\tARRAY(0x7788e746d8)"`；stderr=`""`；rc=0 | 均宽松串化数组；只因进程内引用地址不同而字节不等。 |
| 9 | wake pane_info:113；调用286/296/373/397；`result.pane.agent=""` | stdout=`"C\t\tw"`；stderr=`""`；rc=0 | stdout=`"C\t-\tw"`；stderr=`""`；rc=0 | 中间 agent 空列变为 - 占位。 |
| 10 | wake pane_info:113；调用286/296/373/397；`result.pane.cwd=""，foreground_cwd缺失` | stdout=`"\tpi\tw"`；stderr=`""`；rc=0 | stdout=`"-\tpi\tw"`；stderr=`""`；rc=0 | 首列 cwd 空串变为 - 占位。 |
| 11 | wake pane_info:113；调用286/296/373/397；`result.pane.workspace_id=""` | stdout=`"C\tpi\t"`；stderr=`""`；rc=0 | stdout=`"C\tpi\t-"`；stderr=`""`；rc=0 | 尾列 workspace 空串变为 - 占位。 |
| 12 | wake _ensure_body:433-436 tab create；`result.root_pane.pane_id=[]` | stdout=`"ARRAY(0x79f511ee88)"`；stderr=`""`；rc=0 | stdout=`"ARRAY(0x7832d2ee88)"`；stderr=`""`；rc=0 | 对照草稿 wake 模式均串化数组但地址不同；当前共享 pane_id 严格模式拒收数组（stdout为空），故不能直接套用。 |
working: 2026-10-04T13:29:04Z 返修1阶段2完成：追加提交7ebd502d40834529880e5e71558d29a6b55bafed，仅bin/qwb-lib.sh删除17行；git grep在bin中无qwb_pane_info，提交后status为空。提交后bash bin/qwb-test.sh fast退出0（rework1-fast.log）；原90组入口脚本在现提交重跑退出0，grep -c核90 PASS/0 FAIL（rework1-entries.log），stdout/stderr/退出码/任务写入/herdr顺序对比全部相同。接续本轮一次全门，结果待退出回执后填写。
done: 2026-10-04T13:43:20Z 返修1完成；最终commit=7ebd502d40834529880e5e71558d29a6b55bafed，追加提交仅删除bin/qwb-lib.sh中无调用方的qwb_pane_info及其注释17行，lib595→578，run821/wake957未变；相对起点行数516→578、838→821、979→957。全仓bin的git grep确认该函数无定义/调用残留；12组差异已按调用点、具体输入、旧stdout/stderr/rc、未接入候选结果及原因整理为主账本返修1工作记录下的Markdown表，来源parsers-final.log，未把数组地址变化混称宽严变化。提交后依次执行：bash bin/qwb-test.sh fast（rework1-fast.log，rc0，无新增shellcheck告警）；python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/hparse.bCAkBC/entries.py（rework1-entries.log/rc，rc0，grep -c计90 PASS/0 FAIL，新旧stdout/stderr/退出码/任务写入/herdr调用顺序全部相同）；本轮仅一次python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full（rework1-full.log/rc，rc0，grep -c计839 PASS/0 FAIL，SMOKE、REVIEW-IDENTITY、LINT、COLLAB-ALL 12项均过，缺qwbuddy/config.sh故比主仓840少一条lint PASS）。未改原取舍、调用者宽严、白名单外解析及测试隔离/进程登记/socket夹具；已删除接口的旧草稿检查不作为现提交的验收。全门后git status --short为空、无残留测试进程，原90组的临时项目与stub已回收，仅留忽略的证据目录。末5行各前100字符、准确计数与状态/进程清单原始收据={"sha":"7ebd502d40834529880e5e71558d29a6b55bafed","full_rc":0,"full_pass":839,"full_fail":0,"tail5_100":["PASS  tests/collab-roles.sh（67s）","PASS  tests/collab-test-policy.sh（94s）","PASS  tests/lint-scenario-stream.sh（5s）","PASS  tests/path-canonicalization.sh（0s）","COLLAB-ALL PASS（12 项）"],"git_status_short":"","residual_test_processes":[],"temporary_root_entries":["hparse.bCAkBC"],"line_counts":{"bin/qwb-lib.sh":578,"bin/qwb-run.sh":821,"bin/qwb-wake.sh":957},"changed_files":["bin/qwb-lib.sh","bin/qwb-run.sh","bin/qwb-wake.sh"]}；证据根=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-herdr-parse/.qwb-tmp/hparse.bCAkBC。
working: 2026-10-04T13:57:17Z 主控验收（返修 1 通过）：无调用方的 qwb_pane_info 已删（主控 grep 复核：定义 0、调用 0）；三个提交 cherry-pick 到 main 与同波的 lib 改动自动合并，合并后 bin/qwb-run.sh、bin/qwb-wake.sh 与工人最终版本逐字节相同，四个共享函数各有调用方；以合并后 main（HEAD=b4ef7c9，含 audit-worktree-tidy 与 audit-pi-profile）全门作验收：rc=0、841 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、746.98s；全门后工作区无改动、.qwb-tmp 为空、无残留进程。12 组新旧不一致的清单已留在本账本，主控另记入审核报告。
