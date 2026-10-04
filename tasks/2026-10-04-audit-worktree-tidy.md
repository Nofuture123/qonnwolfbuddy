# 任务书：收尾脚本内部去重，并让残留判定与点名口径一致

```
任务 id:  audit-worktree-tidy
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」「我定不了…还是你定，你要知道qonnwolfbuddy是我后续所有项目的初始化脚本」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F16、F24）；F16 的口径由主控按 Rocky 2026-10-04 的委托裁决
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-worktree-tidy.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy（隔离副本，detached HEAD，起点 main bea487d）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。本仓是他之后所有项目的初始化脚本。

`bin/qwb-worktree.sh` 负责隔离副本的清点与收尾（`list` / `finish` / `land`），其中 finish 与 land 会删除副本与分支，是丢活风险最高的一段。审核查出两件事（行号以 `4678ba0` 为准，已有偏移，自己重新定位）：

**内部重复（F24）**
- `--merged` 与 `--archive` 两条分支里「删 worktree 之后删分支」的一段同构（分支 tip 未变才删、别处检出则记 partial、`update-ref -d` 带旧 OID、清分支配置）。
- 「pane 已回到 shell 且 agent 为空」的内嵌 perl 抄了三份。
- `LAND_PROOF` 在两处各起两个 python 进程解析同一个值。

**残留判定与别处口径不一（F16）**
- `open_task_for` 用文件名子串匹配（`*"$1"*`）找任务书，同文件的 `unique_task_for` 已是精确匹配；子串匹配会让 `watch-invisible` 误中 `watch-invisible-pi` 这类名字。
- 它只看 `state:` 与 UTF-8，不看已迁票的未结义务；而值守与点名都看（`qwb_task_obligations`）。后果：一张 `state: done` 但认领还没释放的票，点名说未结，`qwb-worktree.sh list` 却把它的副本标成残留并建议收尾。

白名单：`bin/qwb-worktree.sh`；F16 需要时可在 `bin/qwb-lib.sh` **新增**函数（不改现有函数）。

### 工程规格

1. **F24 等价抽取**：三类重复各提成一个本地函数或只解析一次。`partial_fail` 的各个 stage 字符串、`worktree:` 与 `worktree: partial …` 记账行的格式、两条分支各自的提示文案，逐字保留在原位置或原样传入。git 与 herdr 的调用次数、顺序、参数不变。
2. **F16 有意的行为修正（两处，分开提交）**：
   - `open_task_for` 改为精确匹配任务 id（与 `unique_task_for` 同一口径）。先把它的全部调用点列出来，逐个确认改成精确匹配后各调用点的行为变化只发生在「名字是另一个任务名的子串」这种输入上。
   - 判断「这张票是否未结」时把已迁票的未结义务算进去，与值守、点名一致。实现上调用 lib 里现成的判定，不要再抄一份规则。
3. 这是删除副本的脚本：凡是你不能确认等价的抽取，一律不做。

## 1. 验收场景

### user_正常路径_收尾各路径逐字节不变

Given 起点提交的 `bin/` 与改后的 `bin/`，以及用假 herdr 的临时 git 项目
When  新旧各跑：`finish --merged`（已合入）、`finish --archive`、`finish --keep`、`finish --merged` 但未合入、带 `--root-tab-missing`、`land` 成功路径；以及每条路径上在「worktree remove 失败」「分支在别处检出」「update-ref 失败」「Space 关闭失败」处中断后的续做
Then  stdout、stderr、退出码、任务书里的 `worktree:` 与 partial 行、git 的引用与副本目录最终状态、假 herdr 与 git 的调用日志，新旧逐一相同

### user_失败路径_工人还没停时拒绝收尾

Given 副本对应的 pane 仍有 agent、或前台不是空闲 shell、或查询失败
When  新旧各跑 `finish --merged` 与 `finish --archive`
Then  都拒绝，文案与退出码相同，副本、分支、Space、任务书都没被动过

### user_失败路径_相似名字不再被误认

Given 两张任务书 `…-demo.md`（已结）与 `…-demo-extra.md`（未结），以及只属于 `demo` 的副本
When  跑改后的 `qwb-worktree.sh list`
Then  `demo` 的副本按「已结」处理，不再因为 `demo-extra` 未结而被当成未结；同样输入在起点提交上会被误判——证明修的是这个问题。反过来，`demo` 未结时它的副本照旧标为未结

### user_失败路径_还有未了结义务的票不被建议收尾

Given 一张 `state: done` 的已迁票，认领尚未释放（或有未处理的交接）
When  跑改后的 `qwb-worktree.sh list`
Then  它的副本不被标为残留、不被建议收尾，与 `qwb-status.sh` 对同一张票的结论一致；同样输入在起点提交上会被标为残留。没有任何未结义务的 `done` 票照旧标为残留

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程。不许为做压力验收而起烧 CPU 的进程——这台机器是共用的。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 本仓会被装进使用者之后的每一个项目：宁可少做，不可改坏。每一项单独做、单独自检；不能确认等价的就跳过并写明原因。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 收尾会删副本与分支：`partial` 恢复协议、根 tab 身份核对、`--root-tab-missing` 的兑底与留痕、land 的授权核对一律不改。
- 不改 `bin/qwb-herdr.sh`（关闭 Space 与写入者死亡证明在那里，另有票）、`templates/`、`tests/`。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 各场景逐个验证，命令与原始结果写进 `done:` 行；逐项写明做了什么、跳过了什么及原因、各文件行数前后变化。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。起点主仓是 840 PASS / 0 FAIL（副本里没有 `qwbuddy/config.sh`，少 lint 的 1 行）。`done:` 行写退出码、PASS 行数、FAIL 行数、末尾 5 行各自的前 100 个字符、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T12:26:10Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-worktree-tidy pane=w14Z:pJ dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy base=bea487d
working: 2026-10-04T12:27:54Z 阶段1读码完成：open_task_for 唯一调用点 bin/qwb-worktree.sh:list，参数为.worktrees目录 basename；精确匹配只改变非精确文件名子串命中。F24先独立等价抽取；第三处shell解析含eval与不同异常语义，若不能证明等价则保留。证据目录=.qwb-tmp/audit-tidy，起点=bea487dd8c9c433f1a6916ecb3f11e9d173ad9c1；工作区起点干净。
working: 2026-10-04T12:40:33Z 阶段2实现完成，F24独立自检执行中：分支删除公共块仅在原elif分支内部调用，保留set-e语义与全部stage/文案/git/herdr参数；两处严格shell判定复用同一Perl字串，第三处eval版保留；LAND_PROOF每路径一次Python解析。fast退出0且/bin/bash语法通过。首轮对照夹具缺空调用日志及失败标记串场已修，日志保留；land首轮遗漏TMPDIR落系统临时目录且已确认回收，现显式仓内TMPDIR/进程与短socket夹具。最终对照日志=.qwb-tmp/audit-tidy/compare-f24-final.log与land-f24-final.log，尚未宣称阶段通过。
working: 2026-10-04T12:43:43Z 阶段2 F24通过并提交：sha=7df7a60828d063c9216fbd921e79005dda4c705b；/bin/bash语法与bash bin/qwb-test.sh fast退出0；python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/compare.py退出0（24 PASS/0 FAIL）；同入口land-compare.py退出0（4 PASS/0 FAIL）；agent-compare.py退出0（2 PASS/0 FAIL）。比较stdout/stderr/退出码/worktree及partial行/refs/目录/git与fakeHerdr调用；land仅剔除原生RPC随机id、根tab夹具仅剔除独立真实死进程PID证据，未改产品结果。第三处eval版Perl因坏JSON异常语义不同未抽；全部删除安全/身份/授权协议未改。bin/qwb-worktree.sh 652→662行；bin/qwb-lib.sh仍516行。
working: 2026-10-04T12:44:34Z 阶段3 F16精确匹配通过并独立提交：sha=7de5823de329f9342abbeec1627b04be70164430；open_task_for唯一调用=list的目录basename，无finish/land调用；与unique_task_for采用同一去日期前缀与.md的精确判定。f16-exact.py进程隔离入口退出0，10 PASS/0 FAIL：旧版done demo误中running demo-extra、新版残留；demo运行中照旧未结，7种单票state逐字节一致，缺精确票不借用相似票。bash bin/qwb-test.sh fast退出0；文件662→663行，lib未改。
working: 2026-10-04T12:46:35Z 阶段4 F16未结义务通过并独立提交：sha=09c0917037fd855722c1ae5e80d397affbba7fa8；done/verified分支调用现成qwb_task_obligations，状态异常/UTF8损坏继续保守未结，lib无需新增；帮助文案同步。f16-obligations.py进程隔离入口退出0（6 PASS/0 FAIL）：已迁done无义务仍残留、claim未释放未结、release后残留、handoff未处理未结、handled后残留、损坏协议未结；每项与status同票一致且3项在起点误判残留。初轮夹具result-ref越项目与残留提示含未结项导致弱断言已改，失败日志保留；最终日志=f16-obligations-3.log。加强列首分类后的f16-exact-final.log 10 PASS/0 FAIL退出0；fast退出0且/bin/bash语法通过。bin/qwb-worktree.sh 663→667行；lib仍516行。进入全部提交后唯一一次full。
working: 2026-10-04T12:47:32Z 阶段5全门已启动：final=09c0917037fd855722c1ae5e80d397affbba7fa8；命令=python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full，cwd为本副本，日志=.qwb-tmp/audit-tidy/full.log，退出回执=full.rc，耗时回执=full.seconds；阶段4计数复核grep-c：义务6 PASS/0 FAIL、精确匹配10 PASS/0 FAIL；全门前git status --short为空。代码冻结，等待完整回执与自有残留检查。
working: 2026-10-04T12:59:55Z 阶段5全门通过：final=09c0917037fd855722c1ae5e80d397affbba7fa8；python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full自然退出0，耗时691s；grep-c严格列首计数839 PASS/0 FAIL（符合主仓840减副本无qwbuddy/config.sh的1条lint）。SMOKE/REVIEW-IDENTITY/LINT/COLLAB-ALL 12项完整。全门后git status --short为空，.qwb-tmp除audit-tidy证据目录外为空；full-summary.json保存末尾5行各前100字与完整回执。阶段6补验land所有Git argv日志、Space关闭失败与真实另一worktree检出分支中断后的拒绝/对账续做，源码冻结不重复全门。
done: 2026-10-04T13:06:25Z {"sha":"09c0917037fd855722c1ae5e80d397affbba7fa8","completed":"F24分支清理公共块、两处严格shell Perl复用、LAND_PROOF每路径一次Python解析；F16精确任务ID与现成qwb_task_obligations分别独立提交，帮助文案同步","commits":["09c0917037fd855722c1ae5e80d397affbba7fa8 Keep migrated worktree tasks open while obligations remain","7de5823de329f9342abbeec1627b04be70164430 Match worktree tasks by exact task ID","7df7a60828d063c9216fbd921e79005dda4c705b Deduplicate worktree finish cleanup without changing safety checks"],"files":{"bin/qwb-worktree.sh":{"before":652,"after":667},"bin/qwb-lib.sh":{"before":516,"after":516}},"skipped":"第三处shell Perl带eval捕获坏JSON且异常输出语义不同，按不能确认等价即跳过的规格保留；lib无需新增，不改已有函数；partial、根tab、root-tab-missing留痕和land授权协议保持原样","call_sites":"open_task_for只有list调用，参数是.worktrees目录basename；精确匹配仅排除非精确任务名子串命中","checks":[{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/compare.py","rc":0,"pass":24,"fail":0,"log":".qwb-tmp/audit-tidy/compare-f24-final.log","raw_pass_lines":["PASS byte-equivalence --merged normal no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal no-mode root-tab-missing=False unmerged=False detached=True","PASS byte-equivalence --merged remove no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged delete no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged elsewhere no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal close-fail root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal busy root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal foreground root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal query-fail root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --merged normal root-missing root-tab-missing=True unmerged=False detached=False","PASS byte-equivalence --merged remove root-missing root-tab-missing=True unmerged=False detached=False","PASS byte-equivalence --merged normal no-mode root-tab-missing=False unmerged=True detached=False","PASS byte-equivalence --archive normal no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal no-mode root-tab-missing=False unmerged=False detached=True","PASS byte-equivalence --archive remove no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive delete no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive elsewhere no-mode root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal close-fail root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal busy root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal foreground root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal query-fail root-tab-missing=False unmerged=False detached=False","PASS byte-equivalence --archive normal root-missing root-tab-missing=True unmerged=False detached=False","PASS byte-equivalence --archive remove root-missing root-tab-missing=True unmerged=False detached=False","PASS byte-equivalence --keep"]},{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/agent-compare.py","rc":0,"pass":2,"fail":0,"log":".qwb-tmp/audit-tidy/agent-f24.log","raw_pass_lines":["PASS byte-equivalence agent still present --merged keeps checkout branch Space and ticket","PASS byte-equivalence agent still present --archive keeps checkout branch Space and ticket"]},{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/land-compare.py","rc":0,"pass":4,"fail":0,"log":".qwb-tmp/audit-tidy/land-f24-final.log","raw_pass_lines":["PASS land-byte-equivalence normal with precise OID, receipts, refs, directory and native calls","PASS land-byte-equivalence remove with precise OID, receipts, refs, directory and native calls","PASS land-byte-equivalence delete with precise OID, receipts, refs, directory and native calls","PASS land-byte-equivalence endpoint with precise OID, receipts, refs, directory and native calls"]},{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/land-trace.py","rc":0,"pass":6,"fail":0,"log":".qwb-tmp/audit-tidy/land-trace-final.log","raw_pass_lines":["PASS land complete Git/native byte trace normal","PASS land complete Git/native byte trace remove","PASS land complete Git/native byte trace delete","PASS land complete Git/native byte trace endpoint","PASS land complete Git/native byte trace close","PASS land complete Git/native byte trace elsewhere"]},{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/f16-exact.py","rc":0,"pass":10,"fail":0,"log":".qwb-tmp/audit-tidy/f16-exact-final.log","raw_pass_lines":["PASS exact task ID regression: baseline misreads demo-extra, candidate reports done demo as residual","PASS exact task ID preserves sole exact ticket state='running'","PASS exact task ID preserves sole exact ticket state='blocked'","PASS exact task ID preserves sole exact ticket state='needs-decision'","PASS exact task ID preserves sole exact ticket state='done'","PASS exact task ID preserves sole exact ticket state='verified'","PASS exact task ID preserves sole exact ticket state='unknown'","PASS exact task ID preserves sole exact ticket state=''","PASS exact task ID keeps unfinished demo open despite similar unfinished ticket","PASS unmatched similar ticket cannot own demo checkout"]},{"command":"python3 -B tests/process_fixture.py --command python3 -B .qwb-tmp/audit-tidy/f16-obligations.py","rc":0,"pass":6,"fail":0,"log":".qwb-tmp/audit-tidy/f16-obligations-3.log","raw_pass_lines":["PASS obligations migrated done no obligations remains residual baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep）","PASS obligations done retained claim matches status baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=未结项  /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation  ← obligation.md state=done","PASS obligations released claim no longer open baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep）","PASS obligations done unhandled handoff matches status baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=未结项  /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation  ← obligation.md state=done","PASS obligations handled handoff permits residual baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep）","PASS obligations damaged migrated protocol stays open baseline=残留    /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation（账本中无对应未结项任务书；建议 qwb-worktree.sh finish obligation --merged|--archive|--keep） candidate=未结项  /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-worktree-tidy/.qwb-tmp/71/qwb-land-l03d3t53/project/.worktrees/obligation  ← obligation.md state=done"]}],"fast":{"command":"bash bin/qwb-test.sh fast","rc":0,"new_shellcheck_warnings":0,"logs":[".qwb-tmp/audit-tidy/fast-f24-final.log",".qwb-tmp/audit-tidy/fast-exact.log",".qwb-tmp/audit-tidy/fast-obligations.log"],"bash32":"各定向脚本使用/bin/bash且/bin/bash -n通过"},"full":{"command":"python3 -B tests/process_fixture.py --command bash bin/qwb-test.sh full","log":".qwb-tmp/audit-tidy/full.log","rc":0,"pass":839,"fail":0,"seconds":691,"runs_after_all_commits":1,"count_commands":["grep -c '^PASS' .qwb-tmp/audit-tidy/full.log","grep -c '^FAIL' .qwb-tmp/audit-tidy/full.log"],"tail5_first100":["PASS  tests/collab-roles.sh（67s）","PASS  tests/collab-test-policy.sh（92s）","PASS  tests/lint-scenario-stream.sh（4s）","PASS  tests/path-canonicalization.sh（0s）","COLLAB-ALL PASS（12 项）"],"git_status_short":"","baseline":"主仓840减副本缺qwbuddy/config.sh的1条lint=839"},"limits":"新旧CLI结果逐字节比较；只剔除独立真实死进程PID/start证据和原生RPC随机id。land分支别处检出重试两版都拒绝，私有夹具核旧OID、移除另一worktree与按旧OID清分支后同op续做；未改恢复协议。首轮夹具失败日志完整保留，首轮land TMPDIR误用系统目录已确认回收，后续全部显式仓内临时目录/原进程及短socket夹具；无真实Herdr写操作。","final_git_status_short":"","residual_processes":[],"residual_temp_scopes":[],"evidence_directory":".qwb-tmp/audit-tidy","final_check":".qwb-tmp/audit-tidy/final-check.json"}
working: 2026-10-04T13:18:32Z 主控验收：三个提交的 diff 逐行审过（delete_finished_branch、parse_land_proof、foreground_is_shell 三处等价抽取；open_task_for 改精确匹配任务 id 并计入已迁票未结义务；第三处语义不同的空闲 shell 判定保留原样）；在副本 09c0917 上独立跑 bash bin/qwb-test.sh full：rc=0、839 PASS / 0 FAIL（副本少 lint 的 1 行）、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、623.88s、无残留进程、工作区干净。已 ff-only 合入 main（HEAD=09c0917）。
