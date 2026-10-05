# 任务书：派发后确认提示词真的提交了，卡在输入框时补一次回车

```
任务 id:  prompt-submit
state: verified
implementation-authorized: Rocky 2026-10-04 起的整仓审核与修复授权（「你查出的点，可以通过herdr，排pi进行执行和修复」）
dispatch-budget: 3
来源:     2026-10-05 真机验收（Pi 工人 + Claude Code 主控，候选 4bdd2fd）主控会话记录；同日主控手工派发 Pi 工人时也出现一次
派发:     主控（Claude Code，w14Z:p1）→ 执行者（Pi，--provider magpie --model codex/gpt-6.1-sol --thinking high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-05-prompt-submit.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit（隔离副本，detached HEAD，基点见派发行）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：派出去的活要真的开工，不能派完了工人坐着不动。

### 真机上看到的事实（主控已核实）

1. 2026-10-05 真机验收：`qwb-run.sh` 用 `herdr` 启动方式派 Pi 工人（Herdr 0.9.3、Pi 1.0.2），`herdr agent start` 与 `herdr agent prompt` 都返回成功，票上也写了派发行，但提示词停在 Pi 的输入框里没有提交：工人状态一直是 idle、用量为 0。主控是靠值守的时间兜底被叫醒后读工人窗口才发现的，手工 `herdr pane send-keys <pane> enter` 之后工人才开工。
2. 同一天主控手工派发另一个 Pi 工人（同样的 `agent start` 加 `agent prompt`）也出现一次，处理办法相同。当天共启动约七个 Pi 工人，出现两次。
3. `bin/qwb-run.sh` 的 `pane-run` 启动方式在投递提示词之后已经有确认：`herdr agent wait <pane> --until working --until done --until blocked --timeout 300` 等不到就补一次 `herdr pane send-keys <pane> enter`（约第 811–814 行）。`herdr` 启动方式（现在 Pi 与 Claude Code 工人都走它，约第 783–794 行，首次派发与复用续派两条路径）在 `herdr agent prompt` 之后没有任何确认。
4. 生产配置的时间兜底是 30 分钟。进度行不再叫醒主控之后，这种情况在生产里意味着工人白坐最长 30 分钟。

### 要做的事

1. `herdr` 启动方式下，首次派发与复用续派两条路径在 `herdr agent prompt` 之后都要确认工人已经开工：等待工人状态变为 working、done 或 blocked 之一。
2. 在限定时间内没等到：对该工人 pane 补发一次回车，再等一次。只补一次，不循环。
3. 补过之后仍没等到：派发按失败处理，走现有的投递失败路径（`delivery_failed`），信息里写明「提示词已投递但工人未开工」、pane 与排查命令；不得打印「已派发」。投递失败后票与副本的处置沿用该路径现有约定，不另造。
4. 等待时长：先读现有 `pane-run` 分支与 `herdr agent wait --help` 确认 `--timeout` 的单位；首次等待要比现有的 300 明显宽裕（工人刚启动时进入 working 可能要一两秒），避免给已经开工的工人多敲一个回车。具体数值由你根据帮助文本与现有常量决定，写成具名变量并在 `done:` 行说明依据；不新增配置项。
5. `pane-run` 分支若与新逻辑重复，抽成一个共用函数，三处调用同一份；其现有行为（等不到就补回车）要保持，只是补完之后同样要再确认一次。
6. 补发回车这件事要留痕：在票上追加一行 `working:` 记录（照 `record_worker_activity` 的写法，带本次派发的 op 与 pane），让主控事后能看到这次派发补过回车。
7. `templates/worker-launch-guide.md` 里如有描述「提示词停在输入框需主控手工补回车」的句子，改成与新行为一致；没有就不动。

白名单：`bin/qwb-run.sh`、`templates/worker-launch-guide.md`、`tests/` 下为验收所需的已接入文件。

## 1. 验收场景

### user_正常路径_工人立刻开工时不补回车

Given 假 Herdr 在 `agent prompt` 之后让工人状态立即变为 working
When  用 `herdr` 启动方式首次派发一张票
Then  派发成功；假 Herdr 的调用记录里没有 `send-keys`；票上没有补回车的记录行

### user_失败路径_提示词卡住时补一次回车后开工

Given 假 Herdr 在 `agent prompt` 之后保持 idle，收到一次 `send-keys enter` 之后才变为 working
When  首次派发；另一组用复用续派路径
Then  两组都派发成功；调用记录里恰好一次 `send-keys <pane> enter`；票上各有一行补回车的记录，带 op 与 pane

### user_失败路径_补过回车仍不开工则派发失败

Given 假 Herdr 始终保持 idle
When  首次派发
Then  退出码非 0，stderr 说明提示词已投递但工人未开工并带 pane；stdout 没有「已派发」；`send-keys` 恰好一次；票与副本的状态与现有投递失败路径一致（在起点提交上人为让 `agent prompt` 失败得到对照，新旧处置相同）

### user_失败路径_工人秒完成或秒阻塞也算开工

Given 假 Herdr 在 `agent prompt` 之后状态直接是 done；另一组是 blocked
When  首次派发
Then  都派发成功，不补回车

### user_正常路径_pane-run方式行为不退化

Given `pane-run` 启动方式的现有用例
When  跑现有测试
Then  全部通过；新增一条：补回车后仍不开工时同样按派发失败处理

### user_正常路径_其余派发路径逐字节不变

Given 起点提交与改后的脚本，假 Herdr 让工人立即开工
When  跑现有派发用例（首次派发、复用续派、门禁续接、自动派工）
Then  stdout、stderr、退出码、票内容新旧相同（新增的等待调用除外）

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；不许碰任何已装项目。
- **绝对不许对真 Herdr 做任何操作；不许启动任何模型会话。** 等待与补回车全部用测试里的假 Herdr 验证。不要移除或绕过测试的失效关闭隔离、进程登记夹具与 socket 路径夹具。
- 不改 Herdr 调用以外的派发逻辑：授权、预算、锁、副本创建、提示词内容都不动。
- 新测试放进已经在全门里的测试文件，不新建没人跑的测试文件。假 Herdr 的响应形状照现有夹具，不凭空造字段。
- 临时文件只许建在本副本的 `.qwb-tmp/` 之内；只许删除自己建出并记在变量里的确切路径，禁止任何带 `*` 的 `rm`。不许起烧 CPU 的压力进程。
- git：只读命令随便用；写操作只许在自己的副本里 `git add` 白名单文件与 `git commit`（在基点之上追加）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 兼容 `/bin/bash` 3.2。状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数。`done:` 行每条 600 字以内，原始输出留在自己的日志文件里并写明路径。
- 隔离副本里没有 `qwbuddy/config.sh`，全门的 PASS 行数比主仓少 1 条，属正常，不要造配置凑数。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 六个场景逐个验证，命令与结论写进 `done:` 行。新测试在起点提交上必须是红的，先跑出红并留证。
- 全门：提交后跑一次 `bash bin/qwb-test.sh full`，重定向到自己建的日志文件。`done:` 行写退出码、PASS 行数、FAIL 行数、全门后 `git status --short` 的输出与残留进程清单。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 5. 本票不允许做的事

- 不改常驻角色的启动路径（`bin/qwb-role.sh`），不改值守与收尾。
- 不碰真 Herdr、不启动模型会话；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-05T01:17:18Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi（--provider magpie --model codex/gpt-6.1-sol --thinking high） agent=qwb-prompt-submit pane=w14Z:pZ dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit base=4bdd2fd
working: 2026-10-05T01:17:59Z 执行者已完整读取任务与启动专项；基点4bdd2fd，副本clean。herdr agent wait帮助确认timeout为毫秒（仅本地help，无真服务操作）；计划共用5000ms等待、最多补一次Enter并二次确认，先扩充已接入runtime-readiness负例留红证。
working: 2026-10-05T01:21:31Z 基点4bdd2fd上 /bin/bash tests/runtime-readiness.sh 有效红证rc=1：新增8条断言失败，既有20条通过；旧脚本在idle上错误成功且无首次/续派确认。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/red-valid.log。开始实现共用确认函数，超时5000ms，补Enter追加op/pane后再次确认。
working: 2026-10-05T01:27:32Z 实现完成：首次、复用、pane-run三处共用确认函数；5000ms等待、最多一次Enter、op/pane留痕、二次失败沿用delivery_failed。/bin/bash tests/runtime-readiness.sh rc=0 PASS=28 FAIL=0，快门rc=0；首次/复用/auto及旧prompt失败字节对照rc=0，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/{green-final.log,fast-final.log,bytes-runtime.log}；门禁对照仍执行中，未宣布全门通过。
working: 2026-10-05T01:27:54Z 已提交5a32ac5；开始按票执行唯一一次提交后全门 /bin/bash bin/qwb-test.sh full，PID=12466，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full.log，退出回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full.rc；仍在执行，尚未全门验收。
working: 2026-10-05T01:31:26Z 提交5a32ac5后快门rc=0、定向门rc=0（28 PASS/0 FAIL）；首次/续派/auto/原prompt失败的stdout、stderr、rc、票与非wait调用逐字节对照rc=0。四个既有协作集成文件汇总PASS（4项）；正式全门仍执行。门禁字节对照首轮仅事件随机ID不同，原因是比较夹具Perl内建time未冻结，已修夹具重跑；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/bytes-gate-fixed.log，未改正式代码。
working: 2026-10-05T01:35:51Z 首轮提交后全门仍待协作段结束；smoke已结束且FAIL=1，定位为tests/smoke.sh第74节仍硬编码runtime-readiness PASS=20，而新增8项后实测rc=0/PASS=28。源代码与定向用例均通过；执行者漏改入口计数，等本轮结束后最小修正20→28、追加提交并复跑全门，保留首轮日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full.log。
working: 2026-10-05T01:38:40Z 首轮full最终rc=1（PASS=903/FAIL=8，含失败日志内预期负例），root失败为smoke计数、collab-herdr尾调用假设、lint-stream未模拟wait、process-entry清理反例及socket嵌套同一collab断言。已保持原断言适配三个本票接缝；定向native suite rc=0、lint-stream rc=0、快门rc=0；门禁精确字节对照重跑rc=0。正在独立验进程清理，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a。
working: 2026-10-05T01:40:13Z 最终候选126bac7，补齐所有已发现wait调用接缝且快门rc=0；native定向与lint-stream各rc=0，门禁4次精确字节对照rc=0，process-entry单独完整运行rc=0（未改清理/监督器）。现仅运行最终提交后全门 /bin/bash bin/qwb-test.sh full，PID=62402，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full-final.log，回执=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full-final.rc；首轮失败全保留。
done: 2026-10-05T01:49:37Z 最终提交=��首次派发、复用续派、pane-run三处共用confirm_prompt_submitted：等待working/done/blocked，超时只补一次Enter并二次确认；补发working行带op/pane，二次失败走delivery_failed且不打印已派发。PROMPT_SUBMIT_WAIT_MS=5000：帮助证实毫秒；覆盖启动1–2秒、明显宽于旧300ms且小于默认START_MS=30000，不新增配置。启动指南没有手动补Enter描述，按票不改。
done: 2026-10-05T01:49:37Z 场景1/2/4：/bin/bash tests/runtime-readiness.sh rc=0、PASS=28、FAIL=0；立即working/done/blocked不补回车，首次与复用idle只补一次且正确记录本次op/pane、第二次working成功。最终定向输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/green-final.log；基点4bdd2fd同一新增检查先红rc=1、8个新增断言失败、旧20项通过，红证=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/red-valid.log。
done: 2026-10-05T01:49:37Z 场景3：/bin/bash tests/runtime-readiness.sh 验证始终idle非零、stderr含未开工/pane/排查命令、stdout无已派发、一次Enter、二次等待；not-sent替代本次dispatch、blocked/state/fp与端点/目录保留符合原prompt失败路径。并发行保留；仅归一动态op/时间、失败step/rc及新增补Enter记录后票字节一致。另用基点agent prompt失败与候选相同失败逐字节对照rc=0，原始票/输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/failed-baseline.ticket及failed-candidate.ticket。
done: 2026-10-05T01:49:37Z 场景5：/bin/bash bin/qwb-test.sh full 的pane-run既有顺序、检测超时、多词argv与权限检查全部通过；补Enter后仍idle的新负例在runtime-readiness通过。原生派发绑定定向 /bin/bash /Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/native-suite.sh rc=0；严格场景流 /bin/bash tests/lint-scenario-stream.sh rc=0；保持失效关闭、进程登记与socket夹具，未改清理逻辑。
done: 2026-10-05T01:49:37Z 场景6（首次/复用/自动派工）：QWB_COMPARE_LOGS=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a /bin/bash /Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/compare-runtime.sh rc=0；固定外部时间与随机op，两版stdout/stderr/退出码/票内容/非wait调用逐字节一致，含原prompt失败对照。原始成对out/err/rc/ticket/calls及汇总=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/bytes-runtime.log；正式候选脚本与最终提交bin/qwb-run.sh字节相同。
done: 2026-10-05T01:49:37Z 场景6（门禁续接）：QWB_COMPARE_LOGS=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a /bin/bash /Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/compare-gate.sh rc=0，4次公开入口均对基点核对stdout/stderr/退出码/所有票内容/其余调用字节一致，只排除新增wait；固定时间、op和事件随机源的比较夹具不改正式代码。成对gate JSON与汇总=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/bytes-gate-fixed.log。比较夹具首轮time未冻结失败另留bytes-gate.log，已定位修正并完整重跑。
done: 2026-10-05T01:49:37Z 最终提交=��/bin/bash bin/qwb-test.sh fast rc=0、无新增ShellCheck告警，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/fast-fixtures.log。提交后 /bin/bash bin/qwb-test.sh full rc=0、PASS=��FAIL=��15项协作全通过；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/full-final.log、回执full-final.rc。全门后git status --short输出为空；残留测试进程清单=[]，测试scope目录=[]，独立证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/final-residuals.json。
done: 2026-10-05T01:49:37Z 首轮full.log保留真实rc=1；已适配固定20→28项、严格wait调用清单及提示词日志定位，未放宽断言；首轮进程清理失败后 python3 -B tests/process-entry-cleanup.py 单独完整rc=0，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-submit.U9QqNz8a/process-entry.log；最终全门内该项与socket嵌套回归均rc=0。代码仅9个白名单文件、均在本副本；主仓仅追加本票状态行。未操作真Herdr服务、未启动模型、未建分支/push。
working: 2026-10-05T01:51:16Z 主控验收返修（第1轮，候选 126bac7 之上追加提交）：首次派发与 pane-run 两条路径认可。复用续派路径有一个漏洞要补：herdr agent wait 是「当前状态命中即返回」（帮助原文 Wait until an agent reaches one of the requested states），而被续派的工人上一轮结束后状态通常就停在 done 或 blocked（当天真机上多个 Pi 工人收工后都是 done），所以续派时 --until done/blocked 会立刻命中，提示词卡在输入框也会被当成已开工，等于没确认。要求：续派路径在投递提示词**之前**先读一次该工人的当前状态与 state_change_seq（真 Herdr 的 pane get 与 agent get 都返回这个字段，例如 "state_change_seq":185）；投递后的确认条件改为「状态为 working，或 state_change_seq 相对投递前已变化」，在同一个等待时限内轮询；不满足则补一次回车后按同样条件再确认一次，仍不满足按派发失败处理。首次派发与 pane-run 也用同一个函数、同一条件，不要留两套。投递前读不到状态或字段缺失时不要猜：按现有 Herdr 应答不合契约的处理方式报错并拒绝派发。假 Herdr 夹具补上 state_change_seq，形状照上面的真实字段；补测试：续派前状态为 done 且提示词卡住（序号不变）时补回车一次并在序号变化后成功；续派前为 done、始终不变时派发失败；续派前为 done、投递后直接变为新的 done（序号变化）时不补回车。提交后跑快门、tests/runtime-readiness.sh 与一次全门，done 行报新 sha 与结果。
working: 2026-10-05T01:53:09Z 执行者完整重读第1轮返修裁决；当前HEAD=126bac74dfe3a7db8e81c70044b9b00882007ed0，副本clean。确认旧done会立即命中agent wait；三条路径将投递前采样状态/数值state_change_seq，投递后共用working或序号变化的有界轮询。先补done卡住/不变/新done红证，保持授权、预算、锁与既有失败处置，证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX。
working: 2026-10-05T01:56:17Z 在126bac7原实现上新增8项有效红证：续派前done补回车/不变失败/新done三项及缺seq、字符串seq、null seq、缺状态、查询失败五项均错误rc=0；原28项仍通过。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/red.log、回执red.rc=1。已实现投递前严格状态/seq采样及共用5000ms轮询，使用现有now_ms/sleep_ms，不增加依赖或配置。
working: 2026-10-05T02:05:24Z 返修定向已收敛：原候选上的done三场景+5项失效关闭先红rc=1；额外延迟新done用例也在126bac7上先红rc=1（red-delayed.log）。当前 /bin/bash tests/runtime-readiness.sh rc=0、PASS=37、FAIL=0，包含旧28项；路由、Pi档位、原生活动绑定和严格场景流均rc=0。三路径共用严格预采样与5000ms轮询，比较原始基线序号；保持本票失败补偿与一次Enter。证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX。
working: 2026-10-05T02:06:43Z 第1轮返修提交=9b304d6243fa57d99b78b736dc3e2f592ec5cc5c；已按裁决在提交后运行快门rc=0、tests/runtime-readiness.sh rc=0（37 PASS/0 FAIL），日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/postcommit-fast.log与postcommit-runtime.log。现启动一次完整全门 /bin/bash bin/qwb-test.sh full，PID=28087，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/full.log、退出回执full.rc；尚在执行，不采信部分通过。
working: 2026-10-05T02:08:54Z 返修全门执行中，已出现smoke锁release负例失败；定位为本次假Herdr pane-run状态补充过宽，对qwb-wake shell命令也创建了pane应答，使原应缺失的wtest:p9被判活。业务锁未改、提交后定向37项通过；当前轮输入冻结，收齐退出回执后只收窄测试桩到工人启动命令，再追加提交验全门。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/full.log。
working: 2026-10-05T02:20:56Z 首轮返修full已结束rc=1：smoke五处失败为状态补充误覆盖通知shell及worker-config/R2共用旧桩返回ok；协作14/15通过，process-entry中断清理失败保留原证。已仅收窄pane-run桩到带引号的工人命令、排除qwb-wake，并给两个已接入夹具补实际pane字段；worker-config/R2/损坏账本/R4定向均rc=0，快门rc=0，process-entry单独完整rc=0，未改监督器/清理断言。日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX。
working: 2026-10-05T02:25:37Z 最终返修候选=85347f23b62b153c843e9e7a4570172cfc382586；提交后快门rc=0（final-fast.log），tests/runtime-readiness.sh rc=0、37 PASS/0 FAIL（final-runtime.log）。现只运行该提交的完整全门 /bin/bash bin/qwb-test.sh full，PID=73182，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/full-final.log、退出回执full-final.rc；首轮失败、失效关闭红证及进程清理独立rc=0证据均保留。
done: 2026-10-05T02:36:55Z 第1轮返修完成，新SHA=85347f23b62b153c843e9e7a4570172cfc382586，在126bac7之上追加9b304d6与85347f2。三条投递路径都先严格读取agent_status和数值state_change_seq，投递后共用5000ms轮询，只认可working或序号相对投递前变化；首轮超时最多补一次Enter，第二轮仍比较原始基线，仍不满足沿用delivery_failed。缺字段、非法类型、查询失败均拒绝投递提示词。授权/预算/锁/提示词内容与收尾逻辑未改。
done: 2026-10-05T02:36:55Z 新增红证：126bac7上续派前done卡住需Enter、done始终不变失败、投递后新done不补Enter三项和5项应答失效关闭检查都先红rc=1，原28项通过；日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/red.log。另一个时限内延迟新done用例在126bac7上先红rc=1，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/red-delayed.log；最终新实现全部变绿，未把夹具错误当产品反例。
done: 2026-10-05T02:36:55Z 按裁决提交后 /bin/bash bin/qwb-test.sh fast rc=0，无新增ShellCheck告警，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/final-fast.log；/bin/bash tests/runtime-readiness.sh rc=0，PASS=37、FAIL=0，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/final-runtime.log。包含done卡住仅一次Enter且新done序号变化成功、序号始终不变失败、新done直接到达不补Enter、下一次轮询才变化不误补Enter、以及投递前字段/查询异常失败关闭。
done: 2026-10-05T02:36:55Z 最终提交=85347f23b62b153c843e9e7a4570172cfc382586；提交后 /bin/bash bin/qwb-test.sh full rc=0，PASS=858、FAIL=0，15项协作回归全通过。原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/full-final.log，退出回执full-final.rc。全门后 git status --short 输出为空；残留测试进程清单=[]、测试scope目录=[]，独立ps/cwd清点及Git证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/final-residuals.json。
done: 2026-10-05T02:36:55Z 首轮返修full.log保留真实rc=1，已补齐worker-config/R2共用旧桩的真实状态字段，并把pane-run状态模拟限定于工人命令，普通通知和值守shell不创建工人pane。未改进程监督器、隔离、socket或清理断言；python3 -B tests/process-entry-cleanup.py 单独完整rc=0（/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/process-entry.log），最终全门该项也rc=0。其他路由、档位、原生绑定、worker-config/R2/损坏账本/R4定向均rc=0，日志均在同一证据目录。
done: 2026-10-05T02:38:48Z 账本读回补充：本轮新追加5行UTF-8有效，新SHA与PASS=858/FAIL=0逐字节核对正确，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-rework.pHfO4IbX/ledger-readback.json。历史偏移12600存在坏UTF-8，来自我上一轮done行紧邻中文符号的未加花括号变量插值，旧SHA/计数不可读；当前已用明确新行补全。遵守本票只允许追加的约束，未改任何历史行或state字段，历史坏字节留给主控按权限处理。
working: 2026-10-05T02:40:35Z 主控验收返修（第2轮，候选 85347f2 之上追加提交）——**这是主控上一条返修指令写错造成的，不是你的错**：我写「真 Herdr 的 pane get 与 agent get 都返回 state_change_seq」，实测只有 agent get 返回。真 Herdr 0.9.3 的 `herdr pane get` 的 result.pane 里没有 state_change_seq（只有 agent、agent_session、agent_status、cwd、revision 等），`herdr agent get` 的 result.agent 里才有 agent_status、state_change_seq、completion_seq。按现在的实现，真机上每次派发都会在「提示词状态校验」处被拒。真实应答已保存，请照它们的形状改代码与假 Herdr 夹具：/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/real-herdr-samples/agent-get-pi-done.json（Pi 工人，done）、agent-get-claude-working.json（Claude Code，working）、pane-get-pi-done.json（对照：没有该字段）、agent-get-missing.json（目标不存在时的错误应答，退出码非 0）。要求：read_prompt_state 改用 `herdr agent get <pane>`，取 result.agent.agent_status 与 result.agent.state_change_seq；其余逻辑不变。假 Herdr 的 pane get 应答里**去掉**你加的 state_change_seq（真机没有，留着会让别的测试建立在不存在的字段上），agent get 应答按真实形状给。提交后跑快门、tests/runtime-readiness.sh 与一次全门，done 行报新 sha 与结果。
working: 2026-10-05T02:43:56Z 执行者完整重读第2轮裁决与4份真实0.9.3应答；当前HEAD=85347f23b62b153c843e9e7a4570172cfc382586，副本clean。真实agent get提供result.agent.state_change_seq，pane get没有；Claude working样本不要求completion_seq。将仅改确认查询及夹具契约，去掉模拟pane序号，保留等待/回车/失败逻辑；真实样本只离线回放，不操作真Herdr。证据目录=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V。
working: 2026-10-05T02:51:51Z 已按真实样本将状态确认改为agent get读取result.agent；生产改动仅3处查询/字段/诊断替换，等待条件和预算不变。修正pane夹具无序号后，85347f2旧实现定向rc=1（19项因错误pane契约失败，red.log）；新实现rc=0。新增4份原样样本离线契约/回放与pane无序号断言；正在完成既有夹具接缝，快门与原生绑定、严格场景流已rc=0。证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V。
working: 2026-10-05T02:54:31Z 第2轮返修已追加提交=3b296872096bea21dd12310cf1a6620f3336542e；模拟pane应答已全部移除state_change_seq，agent查询返回result.agent真实形状，增加4份原样样本；确认代码只改查询命令、解析节点及诊断名。提交前快门、42项定向、原生绑定、路由、worker-config、Pi档位、严格场景流均rc=0，旧85347f2错误契约红证已留。即按裁决验证提交后快门/定向/一次全门，证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V。
working: 2026-10-05T02:56:03Z 第2轮候选=3b296872096bea21dd12310cf1a6620f3336542e；提交后快门rc=0、tests/runtime-readiness.sh rc=0、42 PASS/0 FAIL，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/postcommit-fast.log与postcommit-runtime.log。现在仅执行一次提交后全门 /bin/bash bin/qwb-test.sh full，PID=30286，日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/full.log、退出回执full.rc；不把部分通过当完整验收。
done: 2026-10-05T03:06:03Z 第2轮返修完成，新SHA=3b296872096bea21dd12310cf1a6620f3336542e，在85347f2之上追加提交。read_prompt_state现用herdr agent get该pane，读取result.agent.agent_status/state_change_seq；生产代码仅3处查询/解析节点/诊断替换，原基线、5000ms两轮等待、一次Enter和失败补偿逻辑不变。所有本票增加的pane序号字段已移除，agent应答按实际接口提供；未操作真实Herdr或启动模型会话。
done: 2026-10-05T03:06:03Z 已加入4份原样真实应答样本，cmp逐字节确认与主控保存文件一致；新增离线形状检查、Pi done恒定样本正确走超时失败而非校验错误、Claude working且无completion_seq成功、目标缺失非零且不投递、模拟pane不携带序号检查。修正夹具后85347f2旧实现先红rc=1（19项失败，/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/red.log）；新实现42项全绿，不从pane或revision猜序号，不把completion_seq设为共同必需字段。
done: 2026-10-05T03:06:03Z 已按裁决在提交后执行 /bin/bash bin/qwb-test.sh fast rc=0，无新增ShellCheck告警，原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/postcommit-fast.log；/bin/bash tests/runtime-readiness.sh rc=0、PASS=42、FAIL=0，原始日志=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/postcommit-runtime.log。原生绑定、严格场景流、自动路由、工人配置、Pi档位等定向也rc=0；进程登记、socket和失效关闭夹具均保留。
done: 2026-10-05T03:06:03Z 最终提交=3b296872096bea21dd12310cf1a6620f3336542e；提交后一次 /bin/bash bin/qwb-test.sh full rc=0、PASS=858、FAIL=0，15项协作回归全部通过。原始输出=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/full.log，退出回执full.rc。全门后git status --short输出为空，残留测试进程清单=[]、测试scope目录=[]，独立ps/cwd/Git/真实样本字节核对证据=/Users/rocky/projects/qonnwolfbuddy/.worktrees/prompt-submit/.qwb-tmp/prompt-round2.rzxjdj8V/final-residuals.json。
working: 2026-10-05T04:12:24Z 主控验收：对照真实应答样本逐字段核对（第 2 轮返修改用 herdr agent get）；六个提交已 cherry-pick 进 main（6d906c9…57d6e7a）。57d6e7a 上真机验收第 11 轮（Pi 工人 + Claude Code 主控）14 项断言全 PASS，首次派发未触发补回车。合并后 main @ 015fb4f 上 bash bin/qwb-test.sh full rc=0、859 PASS、0 FAIL、731 秒（.qwb-tmp/ctl-full-merge5.log）。遗留：补回车后只再等 5 秒就判失败，高负载下可能误判，另票处理。
