# 任务书：派发后确认提示词真的提交了，卡在输入框时补一次回车

```
任务 id:  prompt-submit
state: running
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
