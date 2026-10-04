# 任务书：smoke 提速：不重复装机、不真等、子测试并发

```
任务 id:  audit-smoke-speed
state: verified
implementation-authorized: Rocky 2026-10-04「继续推进，pi指定magpie渠道gpt 6.1 sol」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F10、F11、F12、F13、F33）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-smoke-speed.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-smoke-speed（隔离副本，detached HEAD，起点 main 8d897cd）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

`tests/smoke.sh` 单独跑约 380 秒（88 节、803 条断言），是全门里最慢的一段，也是每次验收都要付的钱。审核时量过的浪费（行号以 `4678ba0` 为准，现在已有偏移，自己重新定位）：

- **F13**：第 74–86 节是十来个独立的子测试脚本，各自建临时目录，现在串行跑，合计约 154 秒（其中 `worktree-space.py` 约 38 秒、`r2-cli.py` 约 31 秒、`invalid-ledger.py` 约 18 秒、`r4-cli.py` 约 14 秒）。
- **F33**：第 49 节（JEV 自动派工）单节约 34 秒，原因没查过。
- **F11**：全篇约 25 处「只需要一个装好的项目」的节各自重跑一遍 `qwb-init.sh`（每次约 0.4 秒，全文件 63 处提到它）；而 `cp -R` 一份装好的项目只要约 20 毫秒。
- **F10**：真等待——第 46 节有一个 stub 睡 8 秒；另有 1 秒、0.4 秒×2 的 `sleep`。第 45 节那 3 秒来自产品 `bin/qwb-wake.sh` 里的裸 `sleep 0.5`，本票不动产品，跳过它。
- **F12**：同一份真仓 lint 在 smoke 里被完整跑了不止一次（第 25、51 节等），期间真仓没变；第 2 节对每个脚本各起一次 shellcheck。

白名单：`tests/smoke.sh`；确有必要时可在 `tests/` 下新增辅助文件。**不改 `bin/`、`templates/` 与其余测试文件的断言。**

### 工程规格

**先量再改，每一步单独提交、单独报数。**

1. **量基线**：`bash tests/smoke.sh | perl -MTime::HiRes=time -pe 'BEGIN{$t=time} printf "%7.2f ", time-$t'`（或等价办法）拿到每节耗时，列出最慢的 15 节。之后每一步都用同样的办法复量，在 `working:` 行报「总耗时、被改动各节的前后耗时」。
2. **子测试并发（F13）**：把第 74–86 节里互不相干的子测试脚本改成并发启动、全部收齐后按原顺序逐节打印标题与结果。每个子测试必须有自己独立的临时目录、假 HOME 与测试 socket（它们现在是否共享 smoke 的 `HOME`、`HERDR_TEST_SOCKET`、`TMPDIR`，逐个读代码确认；共享了就各给一份）。并发安全由你证明：连续跑 5 次 smoke 全绿。任何一对子测试确实不能并发的，放进同一个串行小组并在注释里写明原因。失败时照旧打印该子测试的日志。
3. **第 49 节（F33）**：先定位 34 秒花在哪（真等待、超时、重试、起进程），在 `working:` 行报结论；能在不改断言的前提下去掉的浪费就去掉，去不掉的写明原因。
4. **黄金安装（F11）**：第 3 节装好之后留一份未被污染的拷贝；其余只需要「一个装好的项目」的节改用 `cp -R` 得到自己的那份。**专门测装机行为的节保持真跑**（装机的预检、拒绝路径、迁移、重复安装、权限等）——逐节判断并列出哪些改了、哪些保留真跑及理由。注意安装产物里写有项目绝对路径的文件（如 `workers.sh` 里的 `--add-dir`），拷贝后要改写成新路径，并与真装的产物逐字节对比证明一致。
5. **真等待（F10）**：第 46 节那个 8 秒的 stub，改成不需要真睡这么久的做法（缩短到仍有余量的时长，或在测试发出终止信号后顺带结束 stub 的睡眠），保持该用例验证的东西不变；其余 `sleep` 能用确定性手段替代的就替代。
6. **重复的真仓检查（F12）**：同一份、期间不会变的真仓 lint 输出复用，不重跑；第 2 节的 shellcheck 改成一次调用后按文件拆结果。测「lint 自己会不会检出问题」的那些用例（对临时坏项目跑 lint）不动。
7. 每一步如果不能确认「断言集合、输出顺序、PASS 行数」都不变，就跳过并写明原因。

## 1. 验收场景

### user_正常路径_smoke明显变快且结果不变

Given 起点提交与改后提交
When  在同一台机器、相近负载下各跑 3 次 `bash tests/smoke.sh` 取最小值（记下每次跑前的 `uptime` 负载）
Then  改后总耗时不超过起点的 65%；两边的 PASS 行数相同、FAIL 为 0；把两边输出里的节标题与 PASS/FAIL 行按顺序提取出来对比，除耗时类数字外逐行相同

### user_正常路径_全门与窄入口不回归

Given 改后提交
When  跑 `bash bin/qwb-test.sh full` 与 `bash tests/smoke.sh root-tab-missing`
Then  全门退出码 0、840 PASS（起点主仓数；副本里没有 `qwbuddy/config.sh` 时少 1 行，写明）、0 FAIL；窄入口退出码 0；全门后 `git status --short` 无输出、无残留进程、`.qwb-tmp/` 下不留本次的目录

### user_失败路径_并发的子测试有一个失败时照样报出来

Given 在临时拷贝里把其中一个被并发的子测试改成必然失败（不提交）
When  跑 smoke
Then  对应那一节报 FAIL 并打印该子测试的日志，其余各节照常报结果，smoke 退出码非 0，末行是 SMOKE FAIL 及失败项数——并发没有吞掉失败，也没有让别的节跟着红

### user_失败路径_黄金拷贝被污染时能发现

Given 在临时拷贝里让某一节往黄金安装目录里写东西（不提交）
When  跑 smoke
Then  有一条检查能发现黄金拷贝在使用期间被改动并报失败——证明各节拿到的确实是互不影响的副本

### user_失败路径_连续多次并发不偶发

Given 改后提交
When  连续跑 5 次 `bash tests/smoke.sh`
Then  5 次都退出码 0、PASS 行数相同；报出 5 次各自的耗时

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 五个场景逐个验证，命令与原始结果写进 `done:` 行；每一步的前后耗时表也写进去。
- 全门：全部提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件，按场景二的要求报。

## 6. 本票不允许做的事

- 不删、不跳过、不合并任何断言；不改 `bin/`、`templates/`；不把 smoke 拆成多个文件；不合并各节的夹具函数（那是另一张票）。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**。
- **绝对不许对真 Herdr 做任何写操作**；只读查询可以。不要移除或绕过测试的失效关闭隔离（死路径 `HERDR_SOCKET_PATH`）、进程登记夹具与 socket 路径夹具。
- 临时文件与 socket 只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 或进程组的进程，禁止按名字模式批量杀。
- git：只读命令（`git log`、`git show`、`git archive`）随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（追加提交，不改写历史）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 macOS 自带 `/bin/bash` 3.2；perl 与 python 只用系统自带模块。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。
- 留意本仓教训：`$VAR` 后紧跟全角字符一律写 `${VAR}`；`set -e` 下函数末行不要用 `[[ cond ]] && cmd` 收尾；制表符做 IFS 时空字段会被合并；把变量喂给会提前退出的命令用 here-string，不用管道。
- 不改任何断言的匹配内容、`ok`/`bad` 文案与各节内部的先后顺序；提速只能来自「少做重复的准备工作」「不真等」「并发跑互不相干的东西」，不能来自删测试、跳过测试或放宽断言。
- smoke 输出里各节标题与 PASS/FAIL 行的**出现顺序**必须与现在一致（并发跑的子测试要先收齐结果再按原顺序打印），PASS 行数不变。
- `tests/smoke.sh:14-37` 的 `root-tab-missing` 窄入口用字面量切片重组脚本；你动到的行若是它的锚点，必须同步，并单独跑 `bash tests/smoke.sh root-tab-missing` 验证。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。
working: 2026-10-04T09:16:56Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-audit-smoke-speed pane=w14Z:pD dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-smoke-speed base=8d897cd
working: 2026-10-04T09:18:11Z 阶段0执行中：已完整阅读规格和点名审核报告；HEAD=8d897cd，工作区干净；三次基线串行测量已启动（每次记录uptime、原始输出和逐行时间戳），证据目录=.worktrees/audit-smoke-speed/.qwb-tmp/smoke-speed.HCihMQnn；代码未改。
working: 2026-10-04T09:24:31Z 阶段0诊断：逐个核对§74–85脚本；§80消费§79日志，保留依赖。shell子测试使用独立process-fixture作用域，Python脚本mktemp/tempfile目录均随机且在本副本.qwb-tmp；runtime/boundary/lifecycle/r2/invalid/r4/on-demand/wake-block有继承假HOME路径，并发需分别提供。§49主要由optional-routing.sh完整公开CLI测试和后续路由用例组成，无sleep/重试等待；正在用基线逐行时间戳分拆两部分成本。
working: 2026-10-04T09:29:09Z 阶段0基线首轮：610.041s，退出1，grep计数待复核；唯一失败§88 subscribe-reap.py missed live-reader window，read_age=2.722s超过既有2s窗口，日志同时有ledger read timed out after 2 seconds；§1–87均通过，代码未改。该测试不在本票允许修改范围，保留原断言，先独立复核再继续基线。原始证据baseline-1.log/.timed/.json；§49=86.036s，其中optional-routing=64.983s，内联约21.05s。
working: 2026-10-04T09:32:37Z 阶段0停止前核验：起点8d897cd，bash tests/smoke.sh经逐行Time::HiRes等价计时总610.041s、rc=1；grep -c "^PASS"=795，grep -c "^FAIL"=1，末行SMOKE FAIL（1 项），唯一FAIL=订阅子进程回收公开入口回归（§88）。跑前uptime=11:18 up 4 days 21:32 load averages 30.24 21.95 22.19。最慢15节（秒）：§49=86.036，§17b=37.642，§79=31.915，§81=24.925，§51=22.141，§17c=19.966，§23=16.273，§86=15.126，§82=15.094，§48=14.975，§50=13.687，§74=13.296，§83=12.450，§17=12.320，§46=11.957。§74–86串行合计142.262s。
blocked: 2026-10-04T09:32:37Z STOP 起点smoke已有失败，无法建立本票所需零FAIL基线：tests/subscribe-reap.py:145断言read_age < 2 and timed out after 2 seconds not in err；完整smoke读龄2.722063625s，独立命令python3 -B tests/subscribe-reap.py读龄2.941202667s，git archive 8d897cd导出到本副本.qwb-tmp/base后同一命令仍rc=1、读龄2.104358458s（跑前load=26.63/31.63/30.36）；三次stderr均含ledger read timed out after 2 seconds和AssertionError: missed live-reader window。高负载可能影响窗口，但未定根因；没有修改该断言、产品或其他测试。bash bin/qwb-test.sh fast rc=0；git status --short为空，已检查无本次测试进程。代码未改、无新提交；仅生成未应用草稿，随本次两个临时目录清理。三次完整全绿基线、提速阶段及最终全门尚未执行；需主控先处理既有§88失败或恢复可稳定通过的测量环境，再恢复本票。state字段未改。
working: 2026-10-04T09:34:01Z 主控处置（回应 09:32:37Z 的 blocked）：你报的属实——第 88 节的 tests/subscribe-reap.py 把「没赶上产品 2 秒超时前的观察窗口」当成了失败，机器负载 26 以上时必红；这是该测试的缺陷，不是产品缺陷，也不是本票的范围，已另开 audit-reap-window 修。本票恢复执行，按以下口径：一、基线与每一步的对比都把第 88 节单独列出，它的红不计入本票的零 FAIL 要求，其余各节必须零 FAIL；二、本机当前负载很高（别的项目在跑），耗时对比一律用「同一时段新旧背靠背各跑一次、记下跑前 uptime」的相对值，不要拿不同时段的绝对值比；三、「总耗时不超过起点的 65%」这条验收，以负载回落后（1 分钟负载低于 6）补测的一组新旧对比为准，补测前先把其余工作做完；四、audit-reap-window 落地后主控会通知你，届时最终全门须连同第 88 节全绿。
working: 2026-10-04T09:36:11Z 根据主控09:34:01Z处置恢复：第88节原样执行并单列，其他节零FAIL；先完成实施与场景验收，65%待一分钟负载低于6时补测。新证据目录=.worktrees/audit-smoke-speed/.qwb-tmp/speed.HioVxmD7；起点8d897cd归档固定在本副本.qwb-tmp/old，每阶段新旧背靠背测量并记录uptime。
working: 2026-10-04T09:48:07Z 阶段1旧版对照出现独立环境异常：651.688s、§83 R4失败；原始栈为tests/process_fixture.py:23 probe.communicate读取全机ps时报UnicodeDecodeError（byte 0xfc position141580），产品调用已输出已叫醒，但监督器因此返回1；属于未改动8d897cd归档的失败，不放宽断言、不改夹具。该轮不计有效零FAIL对照；当前候选测试结束后同一时段补跑旧版。旧版跑前load=55.41/32.81/30.34。
working: 2026-10-04T09:56:22Z 阶段1提交bc9543c：候选首轮385.710s、rc=0、grep ^PASS=803/^FAIL=0（包含§88全绿）；Bash3.2语法、函数export与快门rc=0；原节标题顺序、ok/bad文案多重集一致，§80在§79结束后消费原日志。采用最多4个并发命令；每命令独立HOME、监督器进程组和helper登记的短socket，保留失效关闭HERDR_SOCKET_PATH。5连跑安排在最终候选上统一验证。旧版650s轮因全机ps非法UTF8失效，已在候选之后立即启动8d897cd归档补测；补测后紧接bc9543c归档复测，形成有效相邻对照。
working: 2026-10-04T10:28:10Z 阶段1有效相邻复量（8d897cd→bc9543c）：总643.414→828.812s；旧跑前11:54  up 4 days, 22:09, 6 users, load averages: 60.58 34.55 31.12，新跑前12:05  up 4 days, 22:20, 5 users, load averages: 53.78 57.48 52.30；两边非88均grep计795 PASS/0 FAIL，整份795 PASS/1 FAIL（仅88）。高负载波动使总耗时更长，本组不作为65%门槛证据。并发候选先收齐再回放，等待计入§73→74；旧§74–86合计190.420s，新§73–86（含原§73及并发等待）合计159.096s。逐节标题时间差：§73=0.980→159.027s，§74=12.884→0.025s，§75=5.638→0.000s，§76=5.561→0.000s，§77=11.147→0.000s，§78=2.737→0.007s，§79=31.969→0.000s，§80=0.012→0.030s，§81=24.818→0.000s，§82=24.886→0.000s，§83=32.243→0.000s，§84=0.127→0.000s，§85=5.756→0.000s，§86=32.642→0.007s；§88单列=15.753→20.422s。原始日志与逐行时间戳在证据目录stage1-old-retry-1和stage1-new-retry-1。
working: 2026-10-04T10:31:14Z 阶段2提交786d803：旧bc9543c→新总828.812→375.712s，§49=93.994→27.324s；旧跑前load53.78/57.48/52.30，新72.17/72.15/65.33（随后负载下降，暂不作为65%证据）。两边非88均795 PASS/0 FAIL，原始整份795 PASS/1 FAIL（仅88）；§88=20.422→7.217s。快门rc=0。§49耗时来自公开CLI起进程与用例总量，未发现sleep/重试可删；optional-routing拥有独立项目/HOME，与使用DT/TMP的内联用例重叠执行，完整日志依原顺序回放，断言和文案未变。后续每阶段沿用紧邻前一候选实测作为旧样本，记录每次uptime。
working: 2026-10-04T10:38:55Z 阶段3提交6f78545：总375.712→324.444s（旧load72.17/72.15/65.33，新1.44/12.50/34.73；负载不同，待低载正式对照）；新整份803 PASS/0 FAIL/rc0，旧795 PASS/1 FAIL（仅88），双方非88均795 PASS/0 FAIL。快门rc0、四路径真装逐字节/权限比较rc0、顺序比对890行一致。23处改为黄金cp-R：HL、ES、EK、HX、MP、LK、SG、SG2、SG3、ENSP、LM、WSJ、MPX、TPLP、LP、OP、BP2、RWP、GP2、WLP、ANP、RUP、LBIG；全部是纯安装准备。保留真装：§3首次/幂等，§17c升级/拒绝/空格/单引号，§20保配置/旧配置，§33整装默认门/安装副本拒绝，§50附页幂等，§55settings合并/非法拒绝，§67gitignore/规则幂等，§72Pi扩展新建/幂等/备份。黄金取自§3首次安装后，复制时仅改写workers.sh已生成的原项目实参；check成功静默，仅污染时新增FAIL，PASS数未变。逐节表：§3=3.551→0.834s，§25=2.730→2.133s，§30=1.954→0.900s，§31=2.307→3.239s，§36=0.921→0.926s，§38=2.563→3.684s，§39=1.576→1.937s，§41=6.237→10.066s，§42=3.285→5.160s，§47=3.899→5.096s，§48=6.227→7.839s，§51=10.605→10.782s，§57=1.236→1.066s，§59=1.333→1.080s，§60=1.126→2.027s，§61=1.524→1.488s，§62=1.222→1.116s，§63=3.329→3.176s，§64=2.230→1.923s，§66=2.921→2.603s，§69=3.421→3.038s，§87=1.438→0.501s；§88=7.217→26.792s。
working: 2026-10-04T10:39:19Z 报数复核更正：阶段3上一行§88新值应为28.850秒，以stage3-new-1.json及逐行时间戳为准；上一行该字段误填，不影响非88的795 PASS/0 FAIL与其他阶段表。
working: 2026-10-04T10:48:01Z 阶段4提交a8b4f02：总324.444→330.367s；旧load1.44/12.50/34.73，新4.88/7.25/22.84。两边803 PASS/0 FAIL/rc0；快门rc0、890行顺序比较一致。逐节表：§46=10.879→1.780s，§54=1.226→0.540s，§59=1.080→0.463s，§72=2.216→1.246s，§88=28.850→28.793s。§46仍真实启动8秒sleep，但以PID+父PID握手后先TERM值守、随即结束自己启动的sleep，让Bash立即执行待处理的TERM trap；原锁清/非0/可续跑断言保留。§54/59由真实退出并wait的子进程提供死PID，取消固定0.4秒；§72设置已知旧mtime后测真装幂等，取消1秒。保留§12e的1.3秒真实节奏观察、启动就绪轮询、看门狗和活PID夹具；产品§45裸sleep0.5不动。
working: 2026-10-04T11:02:17Z 主控通知：audit-reap-window 已落地 main（1441b63）——第 88 节的测试现在把「没赶上窗口」归为无结论并重试，进程夹具也不再因全机进程命令行里的坏字节而抛错。你的副本仍在旧起点上，不用同步；你这边照原口径把第 88 节单列即可。当前全机负载已回落到 2 左右，适合补测耗时对比。
working: 2026-10-04T11:04:18Z 阶段5提交8002ea2：总330.367→298.915s，旧load4.88/7.25/22.84，新18.16/10.56/16.88（期间下降）；两边803 PASS/0 FAIL/rc0，快门rc0、890行顺序比对一致。逐节表：§2=3.944→4.915s，§25=5.320→2.540s，§51=10.373→8.481s，§70=1.947→0.035s，§88=28.793→28.638s。§25真仓lint输出与退出码缓存，§51/70复用，所有临时坏项目lint仍真实运行；§2只调一次shellcheck-json，按文件打印原有结果。真实ShellCheck对照合法/警告/语法错误三个临时脚本，旧新逐字stdout一致、1 PASS/2 FAIL/FAILCOUNT=2，验证未吞掉单文件错误。正在补充F13早启动：各独立子测试与主smoke前段重叠，仍保持最多4个任务和§74前全部回收；root-tab窄入口的字面量范围不包含此启动块。
working: 2026-10-04T11:13:09Z 阶段6补充F13提交3e83371：总298.915→218.318s；旧load18.16/10.56/16.88，新2.77/2.82/7.33；两边803 PASS/0 FAIL/rc0，快门rc0、890行顺序比较一致。独立测试由后台控制器在§3结束后启动，最多4项，主smoke同步继续；§74前wait控制器后按原节序报告。§4–73正文、原启动前缀和§74以后正文分别逐字节比对一致，只移动定义和调度位置；窄入口切片不包含新启动块。逐节表：§3=2.060→0.823s，§4=0.141→0.062s，§12=5.017→2.408s，§12=2.581→1.370s，§12=4.127→2.350s，§73=55.040→1.005s，§74=0.008→0.009s，§79=0.000→0.000s，§81=0.000→0.000s，§86=0.002→0.003s，§88=28.638→29.126s。低载正式8d897cd→最终候选背靠背补测已启动；第88节继续按主控11:02:17Z通知原样单列，不同步main的修复。
working: 2026-10-04T11:27:16Z 65%正式补测未达门槛：8d897cd=368.393s（跑前load2.38/2.99/6.21），3e83371=243.902s（1.90/2.30/4.73），比例66.207%，允许上限239.455s；双方803 PASS/0 FAIL/rc0。§88单列28.796/29.387s。取消尚未完成的候选五连跑，已保存cancelled-prefix部分日志；仅按记录的链PID、测量PID和直接测试监督器PID发送TERM，未修改测试断言。继续F33最小调度优化：optional-routing作为第13个独立早启动队列项（仍最多4项），§49结束时wait控制器并依原顺序报告，§74直接使用已收齐的日志。当前在复量这一改动，随后重新低载新旧背靠背与最终5连跑。
working: 2026-10-04T11:38:51Z 阶段7补充F33提交887ba02：3e83371正式新样本→本轮总243.902→237.433s；旧load1.90/2.30/4.73，新1.96/5.55/5.89；均803 PASS/0 FAIL/rc0，快门rc0、890行顺序对比一致。逐节表：§49=27.434→7.214s，§74=0.010→0.007s，§88=29.387→28.802s。仅把optional-routing加入早启动队列、将收齐点移至§49末，删除原§49单独启动；原内联断言和回放顺序不变。8d897cd与887ba02新的低载背靠背补测正在执行；新样本接续4轮同提交形成5连跑。临时mc副本仅前置worker-config必失败（exit7+日志canary），mg副本仅在§87结束写黄金污染；随后顺序运行窄入口、两条完整smoke负例及Bash3.2全门，均不改提交候选。
working: 2026-10-04T11:42:41Z 最终5连跑链执行中；第二组对照旧版402.816s、803 PASS/0 FAIL/rc0，但跑前一分钟load6.15（6.15/6.64/6.53）超过严格低于6的条件，该组不计65%证据。后续先完整收齐当前5连跑，再在启动前严格检查低载条件补测一组背靠背；停止的仅是尚在等待、未启动测试的后续门调度器，未中断本组5连跑。
working: 2026-10-04T12:01:21Z 最终候选887ba02连续5次完整smoke已全绿，按原始日志grep ^PASS/^FAIL逐项复核：benchmark2-new-1: 224.881s rc=0 PASS=803 FAIL=0 uptime=13:41  up 4 days, 23:55, 5 users, load averages: 5.73 6.79 6.71；final-five-1: 196.015s rc=0 PASS=803 FAIL=0 uptime=13:44  up 4 days, 23:59, 5 users, load averages: 6.94 7.83 7.22；final-five-2: 230.391s rc=0 PASS=803 FAIL=0 uptime=13:48  up 5 days, 2 mins, 5 users, load averages: 3.37 5.79 6.50；final-five-3: 217.550s rc=0 PASS=803 FAIL=0 uptime=13:52  up 5 days, 6 mins, 5 users, load averages: 5.03 6.75 6.89；final-five-4: 195.465s rc=0 PASS=803 FAIL=0 uptime=13:55  up 5 days, 10 mins, 5 users, load averages: 7.09 7.18 7.03。当前源与提交无改动；最终两种负例、窄入口与Bash3.2全门已排队在严格低载背靠背组之后，测试目录与socket均归属于本副本。.qwb-tmp清理安排在全部收据入账后。
working: 2026-10-04T12:11:12Z 场景1严格低载背靠背补测已通过：lowload-1-old-1: 377.489s rc0 PASS803 FAIL0 load1=3.392 uptime=13:58  up 5 days, 13 mins, 5 users, load averages: 3.39 5.65 6.43 §88=28.877s；lowload-1-new-1: 239.536s rc0 PASS803 FAIL0 load1=4.548 uptime=14:05  up 5 days, 19 mins, 5 users, load averages: 4.55 5.07 5.87 §88=28.638s；比值=63.455%（上限65%），节省=137.953s；原始逐行时间戳与JSON为对应lowload标签。候选887ba02与8d897cd的第88节以外890行标题/结果按序比较一致（只归一化随机临时ROOT/TMP、临时Git OID、真钟扫描次数；实际测试输出未改），整份PASS803、FAIL0相同。正式65%门槛达标，五连跑已全绿；后续正在执行窄入口与两种完整smoke失败注入，之后执行Bash3.2全门。
working: 2026-10-04T12:14:23Z 场景2窄入口与场景3并发子测试失败已验证：narrow-1: 8.486s rc=0 PASS=14 FAIL=0 last=SMOKE PASS；mutation-child-1: 207.123s rc=1 PASS=802 FAIL=1 last=SMOKE FAIL（1 项）。窄入口用/bin/bash运行原root-tab-missing字面量切片，rc0；mc临时副本仅给worker-config前置canary+exit7，§77报原FAIL并打印FORCED_SMOKE_CHILD_FAILURE，其余节继续正常报告，末行SMOKE FAIL（1 项），退出1，未吞失败。正式代码未改；黄金污染整份smoke正在跑，之后执行Bash3.2全门。
working: 2026-10-04T12:17:40Z 场景4完整smoke黄金污染负例已通过：202.700s rc1 PASS803 FAIL1 last=SMOKE FAIL（1 项）。mg临时副本只在§87末写GOLDEN/contamination，完整smoke报唯一黄金完整性FAIL并退出1，其余原有803条PASS保留；成功完整性检查仍静默，不改变正常PASS计数。正式候选未改；场景1/3/4/5与窄入口均已通过，现用PATH=/bin优先、/bin/bash bin/qwb-test.sh full跑最终质量门（实际Bash3.2及其子脚本），等待真实退出回执。
working: 2026-10-04T12:26:04Z 最终Bash3.2全门首轮计时观察器失败：在§12读取输出时Python严格UTF8解码异常（byte0xef position31 invalid continuation），尚无测试退出回执，未计全门通过。进程检查确认该轮监督器已排空，本副本无遗留测试进程。仅改本票临时观察器为原始bytes日志+展示层replace解码，不改提交或任何断言；全门以full-bash32-retry标签重新完整运行，保留首轮部分日志与异常栈。
working: 2026-10-04T12:31:40Z 全门执行器复核：强制PATH=/bin优先让所有产品子脚本使用Bash3.2时，原第12节触发tests/smoke.sh的FC_RC紧跟中文标点未绑定变量，观察器按字节收齐后真实rc1，未计通过；此轮属于额外环境验证，非任务指定默认bash命令。按规格正在执行bash bin/qwb-test.sh full（full-default标签），随后以/bin/bash tests/smoke.sh保留宿主PATH验证本次改动入口兼容，保留所有原始日志；不改产品或断言迎合额外环境。
working: 2026-10-04T12:48:00Z 默认最终全门887ba02已通过：bash bin/qwb-test.sh full=448.799s/rc0/grep PASS839 FAIL0，SMOKE、REVIEW-IDENTITY、LINT、COLLAB-ALL 12项全过；副本无qwbuddy/config.sh，比主仓840少1行。兼容探针在8d897cd原脚本实际得到FC_RC=143，但原PASS文案$FC_RC紧跟全角右括号使Bash3.2误认变量名并set-u退出；并非退出断言失败。按本票硬约束补齐现有成功/失败文案中命名变量的花括号，保持插值后文案、匹配和顺序不变，保留两个刻意的坏变量负例及原所有断言。快门rc0；正在/bin/bash入口完整复验，该语法修正单独提交和报数。
working: 2026-10-04T13:00:32Z 阶段8兼容提交f88625b：修正原文案命名变量紧跟全角字符的Bash3.2解析（运行时文案不变）；并修复本票导出JEV函数时Bash3.2序列化后台here-doc会产生非法后台符号的问题，改为后台子shell exec同一个Python server，PID/等待/HTTP断言均保留。原8d897cd兼容探针确认FC_RC实际143、仅插值语法出错；修复后导出的函数由/bin/bash和宿主bash导入检查rc0，快门rc0。此前887ba02五连跑/65%/两种负例/默认全门839均已通过，但不冒充最新提交收据；现冻结f88625b，执行/bin/bash完整5連跑，再严格低载对照、窄入口、完整两种负例和默认全门复验。
working: 2026-10-04T13:03:51Z 阶段8首次完整Bash3.2复量：/bin/bash tests/smoke.sh（宿主PATH保留）=211.153s、rc0、803 PASS/0 FAIL；与修正前887ba02正常输出的890行按序对比一致，函数导入与各真实HTTP/退出断言都过。原Bash3.2 probe实际FC_RC143，原文案解析失败只发生在语法层；修正后并未放宽该143判断。第二次完整Bash3.2运行206.020s也rc0/803 PASS/0 FAIL；继续收齐5次最新提交与其余场景。
working: 2026-10-04T13:15:57Z 最终候选f88625b已完成/bin/bash完整连续5次；第1–4轮整份803 PASS/0 FAIL/rc0，第5轮仅原第88节失败（795 PASS/1 FAIL/rc1），按主控11:02:17Z通知原样单列，不洗绿、不改该测试。五次非88均按截取原始日志grep计795 PASS/0 FAIL，所有本票子测试、HTTP、黄金复制与信号断言通过。逐项回执：final32-five-1: 211.153s rc0 raw PASS803/FAIL0 non88 PASS795/FAIL0 uptime=14:56  up 5 days,  1:11, 5 users, load averages: 10.17 10.06 7.52；final32-five-2: 206.020s rc0 raw PASS803/FAIL0 non88 PASS795/FAIL0 uptime=14:59  up 5 days,  1:14, 5 users, load averages: 5.45 8.27 7.35；final32-five-3: 289.777s rc0 raw PASS803/FAIL0 non88 PASS795/FAIL0 uptime=15:03  up 5 days,  1:18, 5 users, load averages: 4.92 7.08 7.06；final32-five-4: 207.906s rc0 raw PASS803/FAIL0 non88 PASS795/FAIL0 uptime=15:08  up 5 days,  1:22, 5 users, load averages: 7.74 10.41 8.87；final32-five-5: 188.058s rc1 raw PASS795/FAIL1 non88 PASS795/FAIL0 uptime=15:11  up 5 days,  1:26, 5 users, load averages: 3.68 7.57 8.03。最终严格低载新旧对照/窄入口/两个负例/全门链继续执行中。
working: 2026-10-04T13:27:38Z 最终提交f88625b场景1严格低载新旧背靠背已达标：final-load-1-old-1: 393.847s rc0 PASS803 FAIL0 load1=5.880 uptime=15:17  up 5 days,  1:31, 5 users, load averages: 5.88 7.37 7.83 §88=28.554s；final-load-1-new-1: 195.774s rc0 PASS803 FAIL0 load1=3.331 uptime=15:23  up 5 days,  1:38, 5 users, load averages: 3.33 5.55 6.80 §88=28.870s；比值=49.708%；省时=198.073s；890行按序一致。两边同一机器、紧邻执行，启动负载分别严格低于6，803 PASS/0 FAIL/rc0相同；仅归一化随机临时ROOT/TMP、临时Git OID、真钟扫描数，不改实际输出。8d897cd固定归档与最终源均未在测量中改动；最终窄入口/负例/全门链正在续接。
working: 2026-10-04T13:31:07Z 最终f88625b场景2窄入口与场景3负例复验收齐：final-narrow-1: 8.792s rc0 PASS14 FAIL0 last=SMOKE PASS；final-mutation-child-1: 205.469s rc1 PASS802 FAIL1 last=SMOKE FAIL（1 项）。mc临时副本沿用同一最终smoke，只前置worker-config canary+exit7，§77唯一FAIL、日志完整、其余节全部继续、SMOKE FAIL（1项）及自然rc1正确；窄入口/bin/bash直接跑原字面量切片rc0。源候选不变，黄金污染和默认全门继续执行。
working: 2026-10-04T13:34:55Z 最终f88625b场景4复验通过：208.737s rc1 PASS803 FAIL1 last=SMOKE FAIL（1 项）；mg临时副本仅在§87末写GOLDEN/contamination，所有原有803 PASS保留，唯一黄金完整性FAIL、自然rc1、末行SMOKE FAIL（1项）均符合。场景1/3/4、窄入口和非88的Bash3.2五連跑已收齐；最新提交默认命令bash bin/qwb-test.sh full已启动，结束后独立检查退出码、839 PASS/0 FAIL、Git状态与本次进程/临时目录。
working: 2026-10-04T13:47:13Z 最终全部质量收据独立复核：sha=f88625b51cd7ec8e62593849e4ae5c4f2aa0a474；bash bin/qwb-test.sh full=473.332s rc0 grep PASS839/FAIL0（无qwbuddy/config.sh，较主仓840少1行）；SMOKE/REVIEW-IDENTITY/LINT/COLLAB-ALL12全过。最终低载393.847→195.774s/49.708%、两端load5.880/3.331/803 PASS0FAIL，890行按序一致；/bin/bash入口5連跑非88均795 PASS0FAIL，原88第五次单列。窄入口8.792s rc0 PASS14FAIL0，mc完整负例205.469s rc1 PASS802FAIL1，mg完整负例208.737s rc1 PASS803FAIL1，均末行SMOKE FAIL（1项）且准确保留日志。Git状态空、白名单仅2文件、进程检查无本次测试行；正在精确清理5个自建目录。
done: 2026-10-04T13:47:13Z DONE f88625b51cd7ec8e62593849e4ae5c4f2aa0a474；最终代码仅tests/smoke.sh和新增tests/smoke-install.py，无bin/templates/其余测试断言改动、无分支/push/真Herdr写操作。场景1：8d897cd固定归档与f88625b同机低载背靠背bash tests/smoke.sh，393.847→195.774s，49.708%≤65%，启动load=5.880/3.331，两端grep PASS803/FAIL0/rc0；标题及非88结果890行按序相同（仅规范化既有随机ROOT/TMP、临时Git OID和真钟扫描数，实际输出未改）。场景2：bash bin/qwb-test.sh full=473.332s/rc0/PASS839/FAIL0，SMOKE、REVIEW-IDENTITY、LINT、COLLAB-ALL12全部通过；副本缺qwbuddy/config.sh按规格少1行；/bin/bash tests/smoke.sh root-tab-missing=8.792s/rc0/PASS14/FAIL0。场景3：临时mc前置worker-config canary+exit7，完整bash tests/smoke.sh=205.469s/rc1/PASS802/FAIL1，唯一§77 FAIL及FORCED_SMOKE_CHILD_FAILURE日志，其余节继续，末行SMOKE FAIL（1项）。场景4：临时mg在§87末污染GOLDEN/contamination，完整smoke=208.737s/rc1/PASS803/FAIL1，唯一黄金完整性FAIL，末行SMOKE FAIL（1项）；tests/smoke-install.py verify的普通/空格/单引号/中文路径真装字节及权限对照、副本隔离和黄金污染均过。场景5：最终/bin/bash tests/smoke.sh连续5次=211.153s/rc0/raw[803, 0],206.020s/rc0/raw[803, 0],289.777s/rc0/raw[803, 0],207.906s/rc0/raw[803, 0],188.058s/rc1/raw[795, 1]；各轮非88均原始grep PASS795/FAIL0，原第88节第五轮按主控授权单列、不洗绿且不改该测试。快门bash bin/qwb-test.sh fast及Bash3.2语法、函数导入、正负ShellCheck文件结果对照都rc0。阶段前后总耗时（高载样本不作65%证据）：阶段1=643.414→828.812s,阶段2=828.812→375.712s,阶段3=375.712→324.444s,阶段4=324.444→330.367s,阶段5=330.367→298.915s,阶段6=298.915→218.318s,阶段7=243.902→237.433s；阶段8兼容旧入口10.712s/rc1无完整可比样本→最终首轮211.153s/rc0，仅插值语法和导出函数的后台here-doc形式修正，既有文案/匹配保留。逐节表：stage3[§3=3.551→0.834s，§25=2.730→2.133s，§30=1.954→0.900s，§31=2.307→3.239s，§36=0.921→0.926s，§38=2.563→3.684s，§39=1.576→1.937s，§41=6.237→10.066s，§42=3.285→5.160s，§47=3.899→5.096s，§48=6.227→7.839s，§51=10.605→10.782s，§57=1.236→1.066s，§59=1.333→1.080s，§60=1.126→2.027s，§61=1.524→1.488s，§62=1.222→1.116s，§63=3.329→3.176s，§64=2.230→1.923s，§66=2.921→2.603s，§69=3.421→3.038s，§87=1.438→0.501s]；stage4[§46=10.879→1.780s，§54=1.226→0.540s，§59=1.080→0.463s，§72=2.216→1.246s，§88=28.850→28.793s]；stage5[§2=3.944→4.915s，§25=5.320→2.540s，§51=10.373→8.481s，§70=1.947→0.035s，§88=28.793→28.638s]；stage6[§3=2.060→0.823s，§4=0.141→0.062s，§12=5.017→2.408s，§12=2.581→1.370s，§12=4.127→2.350s，§73=55.040→1.005s，§74=0.008→0.009s，§79=0.000→0.000s，§81=0.000→0.000s，§86=0.002→0.003s，§88=28.638→29.126s]；stage7[§49=27.434→7.214s，§74=0.010→0.007s，§88=29.387→28.802s]；阶段1§74–86旧190.420s→新§73–86含并发等待159.096s；阶段2§49=93.994→27.324s。所有测量startup uptime、原始结果和分阶段明细已在working行记录，§88误填处已单列更正。提交链bc9543c/786d803/6f78545/a8b4f02/8002ea2/3e83371/887ba02/f88625b，均逐阶段追加提交。清理后独立确认git status --short为空、无本次进程、.qwb-tmp空；不改state字段，源码已提交。
working: 2026-10-04T14:05:41Z 主控验收：8 个提交以 cherry-pick 合入 main，与 audit-pi-profile 对 tests/smoke.sh 的 6 行改动自动合并——合并后的 smoke.sh 与工人最终版本逐行对比，差异恰为那 6 行；bash 与 /bin/bash 语法检查通过。因 diff 过大（忽略缩进后 1471 行加、1345 行减）不逐行审，改以输出对比验收：把合并前（main b4ef7c9 全门日志）与合并后 smoke 输出里的全部节标题与 PASS/FAIL 行按顺序提取，各 843 行，归一化路径、哈希与耗时数字后完全相同。合并后 main（HEAD=ef0e105）全门：rc=0、841 PASS / 0 FAIL、SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过、456.24s（合并前同一门为 571–747s，负载不同）；全门后工作区无改动、.qwb-tmp 为空、无残留进程。执行者报的 smoke 单独耗时 393.8s → 195.8s（低载背靠背）待主控空闲时复测。
