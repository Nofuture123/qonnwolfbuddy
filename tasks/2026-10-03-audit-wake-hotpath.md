# 任务书：值守循环改单遍扫描账本，去掉等待期的子进程空转

```
任务 id:  audit-wake-hotpath
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F3、F4、F27 的 bash 两处）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi；起初误用 glm-5.3-flash，2026-10-03T21:10Z 起改为 magpie codex/gpt-6.1-sol high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-03-audit-wake-hotpath.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-wake-hotpath（隔离副本，detached HEAD，起点 4678ba0）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

现状：`bin/qwb-wake.sh` 的 `open_items`（`:489-510`）每轮对 `tasks/` 下每个 `.md` 起约 6 个外部进程（`grep -q`、`sed|head|tr`、带 Encode 的 perl、再一次 `grep -q`），已结票也照付。等待被夹在 1 秒内（`:811-815`），所以每秒重扫一次。实测 `qwb-wake.sh --dry-run --once` 一轮 1054ms / 约 308 次 exec（52 个文件），票数翻倍耗时翻倍。等待期每 50ms 一拍，每拍还要起 `head`、`perl`、一个 `printf` 子 shell（每拍约 12ms 纯开销）。

白名单：**只许改 `bin/qwb-wake.sh` 与 `bin/qwb-lib.sh`**。

### 工程规格

分三步，**每步做完先自检再做下一步**。

**第一步：单遍扫描（F3）。**

1. 在 `bin/qwb-lib.sh` 新增 `qwb_ledger_scan`：参数是若干任务书路径，起**一个** perl 进程，按参数顺序逐文件输出一行 `路径<TAB>state<TAB>utf8ok<TAB>collab`：
   - 没有列首 `state:` 行的文件不输出（等价于现在的 `grep -q '^state:' || continue`）。
   - `state` 与 `qwb_task_state`（`:150-152`）逐字节等价：取**第一个**列首 `state:` 行，去掉 `state:` 及其后的空白，再删掉值里**全部**空白字符（等价 `tr -d '[:space:]'`）。值可能为空串。
   - `utf8ok` 与 `qwb_ledger_utf8_ok`（`:155-159`）等价：整文件按严格 UTF-8 解码成功为 1，否则 0。注意文件读不出来时旧实现的结果是什么，新实现要一样。
   - `collab`：文件含「已迁票协作区标记」为 1，否则 0。标记的字面量就是 `qwb_task_obligations`（`bin/qwb-lib.sh:212`）第一行 `grep -q` 的那个固定串，照抄它（本任务书故意不写出该字面量，否则本票自己会被当成已迁票）。
   - 文件按原始字节读（不要加 `:utf8` 层）；行匹配规则要与 `sed`/`grep` 的「按行、列首」语义一致。
   - 路径含 TAB 或换行会破坏输出格式：这种文件名直接让函数返回非 0 并在 stderr 报错（现有账本不存在这种文件名）。
2. `open_items` 改成：用原来的 glob（`"$LEDGER"/*.md`，保持同样的遍历顺序）把路径交给 `qwb_ledger_scan`，再用 `while IFS=$'\t' read -r …` 逐行做原来的判断。`state` 可能为空，而制表符 IFS 会合并空字段——设计输出列顺序或占位时要处理这一点（例如把可能为空的 `state` 放最后一列，或用不可能出现在值里的占位符），并在注释里写明。
3. 必须逐字保持：stdout 每行 `文件<TAB>state` 的内容与顺序；两条 stderr 警告的文案与出现顺序；`done|verified` 票只在 `collab=1` 时才调 `qwb_task_obligations`（`collab=0` 时它本来就立即返回空，跳过它不改变结果）；glob 无匹配、`tasks/` 为空时的行为。
4. `qwb_task_state`、`qwb_ledger_utf8_ok`、`qwb_task_obligations` 这三个旧函数**保留不动**（别的脚本还在用）。

**第二步：等待期去子进程（F4）。** 都在 `bin/qwb-wake.sh:774-823` 一带：

1. `now_ms`：`QWB_NOW_MS_CMD` 非空时行为不变（测试靠它注入假时钟，**调用次数不得变**）。否则若 `${EPOCHREALTIME:-}` 非空（bash 5+），用它算毫秒：它的小数点可能是 `.` 也可能是 `,`（跟随 locale），先去掉非数字字符得到微秒整数，再整除 1000。否则回落到现在的 perl。输出格式与现在一致（纯整数、无换行）。
2. `sleep_ms`：`QWB_SLEEP_CMD` 路径不变。真睡路径用 `printf -v` 拼小数秒，不起子 shell。
3. `event_mark`：用 bash 内建 `read` 读 `$EVENT_DIR/notice` 首行代替 `head -1`。要保持：`EVENT_DIR` 为空时无输出；文件不存在时无输出且不报错、返回 0；首行没有结尾换行时仍输出该行内容。
4. 不动 1 秒节奏与 50ms 一拍（`:813` 注释写明的设计），不改 `wait_round` / `event_start` 的控制流。

**第三步：删两处死代码（F27）。** 先 `grep -rn 'sleep_interval\|qwb_pane_activity' bin/ templates/ tests/` 确认除定义行外零命中，再删：`bin/qwb-wake.sh:788` 的 `sleep_interval`、`bin/qwb-lib.sh:378-383` 的 `qwb_pane_activity`（连同它的注释）。有命中就不删并写明。

## 1. 验收场景

### user_正常路径_未结项输出与旧实现逐字节一致

Given 一组临时账本夹具，至少包含：`running` / `blocked` / `needs-decision` / `done` / `verified` 各一张；非法值（如 `pending`）一张；`state:` 后值为空一张；`state:   running  ` 带多余空白一张；CRLF 行尾一张；`state:` 行出现两次且取值不同一张；`state:` 只出现在缩进行（非列首）一张；完全没有 `state:` 的 `.md` 一张；含非法 UTF-8 字节且 state 合法一张；含非法 UTF-8 字节且没有 `state:` 行一张；文件名含中文与空格各一张
When  分别用旧实现（`git show 4678ba0:bin/qwb-wake.sh` 与 `4678ba0:bin/qwb-lib.sh` 另存到临时目录的 `bin/` 下，其余脚本从当前目录拷贝）和新实现对这组夹具跑 `qwb-wake.sh --dry-run --once --project <夹具项目> --pane x:p1`
Then  stdout、stderr、退出码逐字节相同；对真账本（本仓 `tasks/`）同样对比也逐字节相同

### user_正常路径_一轮扫描明显变快且不随已结票线性增长

Given 本仓真账本（约 52 个 `.md`）
When  各跑 5 次 `qwb-wake.sh --dry-run --once` 取最小值，新旧对比
Then  新实现耗时不超过旧实现的 30%，并报出两个数字；把账本复制成两倍文件数后新实现增量不超过 100ms

### user_失败路径_坏账本仍被当未结项叫出来

Given 一张含非法 UTF-8 字节的 `state: done` 任务书、一张 `state: pending` 任务书
When  新实现跑 `--dry-run --once`
Then  两张都作为未结项列出（按 `needs-decision`），stderr 分别有「账本 UTF-8 损坏，按未结项叫主控查看」与「state=pending 非法，按未结项叫主控查看」两条警告，与旧实现逐字节相同；不得因为解析失败而漏报、崩溃或静默跳过

### user_失败路径_假时钟与假睡眠注入不受影响

Given `QWB_NOW_MS_CMD` 与 `QWB_SLEEP_CMD` 指向测试桩
When  跑 `bash tests/wake-block-output.sh`，并把 `/bin/bash`（3.2，无 `EPOCHREALTIME`）与 PATH 上的 bash（5.x）各试一次：`/bin/bash bin/qwb-wake.sh --dry-run --once …` 与 `bash bin/qwb-wake.sh --dry-run --once …`
Then  `wake-block-output.sh` 退出码 0 且 PASS 数与改动前相同；两种 bash 下 `--dry-run --once` 输出相同；`now_ms` 在两种 bash 下各调一次，结果都是 13 位整数且彼此相差小于 1000

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根 `/Users/rocky/projects/qonnwolfbuddy` 下除了往主账本追加状态行，**什么都不许动**（不改文件、不跑 git 写操作、不跑会写文件的脚本）。
- git：只许在自己的副本里 `git add <白名单文件>` 与 `git commit`（detached HEAD 上直接提交）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行（如 `perf: drop basename/dirname forks in installer`），不加签名行。`git show <sha>:<path>` 这类只读命令随便用。
- `bin/qwb-lib.sh` 被所有脚本 source：对它只做**新增函数**与删除 `qwb_pane_activity` 两件事，不改任何现有函数的签名与行为（下一波有别的票要在它上面继续加函数，改动越小越好合并）。
- 行为不变：除耗时外，stdout / stderr 文案、退出码、账本写入逐字节不变。
- 兼容 macOS 自带 `/bin/bash` 3.2 与 Homebrew bash 5.x；perl 只用系统自带模块。
- 留意本仓两条教训：`set -e` 下函数末行用 `[[ cond ]] && cmd` 收尾，cond 为假时函数返回 1（`tasks/lessons/set-e-下函数末尾短路返回值.md`）；`$VAR` 后紧跟全角字符一律写 `${VAR}`（`tasks/lessons/shell-变量后紧跟非ascii字符.md`）。
- 这是值守主路径：**绝不允许漏报未结项**。拿不准等价性的地方保留旧写法。

- **临时文件**：只许删除你自己用 `mktemp -d` 建出来并记在变量里的确切路径，一次一个。禁止任何带 `*` 的 `rm`（如 `rm -rf "$TMPDIR"/tmp.*`）——那会删掉本机其他进程正在用的临时目录，本轮已因此出过一次事故。
- 状态行里的时间戳取自机器（`date -u +%Y-%m-%dT%H:%M:%SZ`），不要估。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`（不得新增 shellcheck 告警）。
- 定向测试：`bash tests/wake-block-output.sh`、`bash tests/lifecycle-readiness.sh`、`python3 tests/invalid-ledger.py`、`python3 tests/r4-cli.py`。先在动手前跑一遍记下各自 PASS 数与退出码，改完再跑，两次必须一致。
- 四个场景：写一次性对比脚本放临时目录（不进仓库），把命令和原始结果写进 `done:` 行。
- 全门：全部改完并提交后，在自己的副本里跑**一次** `bash bin/qwb-test.sh full > <临时文件> 2>&1`（本机约 7–15 分钟，别反复跑；调试用上面的定向检查）。基线是 `4678ba0` 干净副本上 791 PASS / 0 FAIL，末尾有 `SMOKE PASS` 与 `LINT PASS`。`done:` 行里写：退出码、PASS 行数（`grep -c "^PASS"`）、FAIL 行数、输出的最后 5 行原文。PASS 数不得少于基线。
- 全门或定向测试失败：先判断是不是自己的改动引起的（对照 `git show 4678ba0:<文件>` 或在临时目录用旧版复现）。是就修；不是就原样写进 `done:`，不去修白名单外的文件。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:`（含三步各自的结果、新旧计时数字、跑了什么命令与原始结果）/ `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf '%s\n' 'working: …' >> <主账本>` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 `DONE <commit sha>` 或 `STOP <原因>`，并把同样的 sha 写进 `done:` 行。

票本身有缺陷时用疑点行（示例缩进两格，真写时顶格）：

```
  blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
```

## 6. 本票不允许做的事

- 不改 `bin/qwb-status.sh`、`bin/qwb-lint.sh`（它们复用 `qwb_ledger_scan` 是下一波的票）。
- 不把 `now_ms` / `sleep_ms` 挪进 lib、不动 `bin/qwb-run.sh` 里的同名函数（下一波）。
- 不改值守的去重指纹、兜底重叫、投递、锁复核、`--ensure` / `--check` 逻辑。
- 不加缓存、不加增量索引。
- 不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-03T20:36:13Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi-glm-flash-high agent=qwb-audit-wake-hotpath pane=w14Z:p4 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-wake-hotpath base=4678ba0
working: 2026-10-03T21:09:46Z 主控更正执行模型：Rocky 叫停 glm 工人并要求切换，同一 Pi 会话已用 /model 切到 magpie codex/gpt-6.1-sol（high），状态栏已核对。此前 glm 在本副本留下的改动与结论行不作为验收证据，由新模型对照任务书逐项复核后重新报 done。硬约束新增「禁止通配 rm」「时间戳取自机器」两条。
working: 2026-10-03T21:10:47Z 接手复核4512b4d；重跑基线与四场景，所有证据另建mktemp目录，时间戳取机器。
done: 2026-10-03T21:15:42Z 第一阶段独立自检：verify.py scan rc=0，夹具22张/真账本/空账本/缺tasks/坏UTF8-done及pending/19张旧helper逐字节/TAB换行拒绝/读取目录错误/断链接均PASS；修复4512b4d吞目录读取错误，原始结果=/tmp/qwb-wake-sol.QKkQmn/scan-after.log；快门rc=0。
done: 2026-10-03T21:16:40Z 第二阶段独立自检：verify.py wait rc=0；/bin/bash 3.2及PATH bash 5.x的event_mark五边界、sleep_ms实参均与旧版一致；now_ms=1791062170107/1791062170115，均13位无换行，相差8ms；点/逗号微秒转换一致；假钟/假睡调用日志严格相同N,N,S50,N,S50,N,S20,N；CLI stdout/stderr/rc逐字节相同。修复4512b4d首行末换行丢失；第一阶段helper实际18张（此前状态行19张为笔误）。原始结果=/tmp/qwb-wake-sol.QKkQmn/wait-after.log。
done: 2026-10-03T21:16:40Z 第三阶段独立自检：旧版grep -rn sleep_interval|qwb_pane_activity bin/ templates/ tests/仅两处定义（wake:788、lib:378）；最终零命中，删除含注释准确；三个既有lib函数以及wait_round/event_start逐字节未改。
done: 2026-10-03T21:18:39Z 四场景与定向门独立复验：旧版4678ba0与当前版四定向命令wake-block-output/lifecycle-readiness/invalid-ledger/r4-cli退出码全0，含PASS的行数1/7/1/2（列首PASS为0/6/0/0），基线与最终相同；fast rc=0，无新shellcheck告警。verify.py scan/wait/bench全0：旧52票1534.515ms、新52票64.653ms（4.213%），新104票77.400ms，增量12.747ms。五轮原始计时与各夹具stdout/stderr在/tmp/qwb-wake-sol.QKkQmn。追加提交86f53d7b8fcfb087a34a8f5841816b6f508c2f42；仅两白名单改动、detached HEAD干净。
working: 2026-10-03T21:18:39Z 独立全门已启动一次，候选86f53d7b8fcfb087a34a8f5841816b6f508c2f42；命令bash bin/qwb-test.sh full，完整串行、不缩范围，隔离宿主HERDR/QWB环境（清单见full-meta.json）；日志=/tmp/qwb-wake-sol.QKkQmn/full.log，退出回执=full-receipt.json。
done: 2026-10-03T21:24:28Z 全门首败归因：第13节FAIL release 失败；旧/新qwb-lock.sh逐字节相同且不source lib。python3 /tmp/qwb-wake-sol.QKkQmn/release-repro.py rc=0：相同隔离HERDR环境与假HOME，新旧均rc=1、stderr原文「拒绝释放：非本人且旧owner仍活或未知（wtest:p9）」且保留锁；属既有环境依赖，不扩修白名单外。全门仍在执行，完整退出码稍后记录。
done: 2026-10-03T21:28:48Z 独立全门一次完成：HEAD=86f53d7b8fcfb087a34a8f5841816b6f508c2f42；bash bin/qwb-test.sh full > /tmp/qwb-wake-sol.QKkQmn/full.log 2>&1；退出码=1，grep -c "^PASS"=790，grep -c "^FAIL"=1，耗时491.584s。未满足791 PASS/0 FAIL基线且无SMOKE PASS；唯一FAIL原文「FAIL  release 失败」。相同隔离宿主环境+假HOME下4678ba0与当前锁释放均rc=1、相同拒绝文案；readonly Herdr查询rc=1/server_not_running（连接路径落入假HOME）。qwb-lock.sh与旧版字节相同且不source lib，按任务书不扩修。完整回执=/tmp/qwb-wake-sol.QKkQmn/full-receipt.json；原始最后5行：尾1「PASS  JEV agents 坏配置拒绝且零网络：{"architect":["has space"]}」；尾2「PASS  JEV 假 server 已退出并回收」；尾3「」；尾4「SMOKE FAIL（1 项）」；尾5「门失败（full）：bash tests/smoke.sh && bash tests/review-identity.sh && bash bin/qwb-lint.sh 退出码=1」
done: 2026-10-03T21:28:48Z full的&&链短路后独立补跑（未重跑full）：bash tests/review-identity.sh rc=0、15 PASS、REVIEW-IDENTITY PASS；bash bin/qwb-lint.sh rc=0、9 PASS、LINT PASS，既有账本警告保留，未修改范围外文件；原始stdout/stderr与remaining-gates.json均在/tmp/qwb-wake-sol.QKkQmn。
done: 2026-10-03T21:28:48Z 接手最终交付：逐项复核4512b4d并追加86f53d7，修正目录读取错误被吞和event_mark首行换行丢失；缩减冗余注释/处理并正确说明FB_CROAK消耗源串。三既有lib函数及wait_round/event_start保持逐字节不变，死代码仅删除原定义。四场景命令python3 /tmp/qwb-wake-sol.QKkQmn/verify.py scan|wait|bench均rc=0；所有临时脚本/夹具和原始结果保留供复核，代码只留两白名单、detached HEAD工作区干净。最终HEAD sha=86f53d7b8fcfb087a34a8f5841816b6f508c2f42。完整全门既有环境失败已单列，不声称全绿。
working: 2026-10-03T21:38:46Z 主控验收：逐行审 diff（bin/qwb-lib.sh 新增 qwb_ledger_scan、删 qwb_pane_activity；bin/qwb-wake.sh open_items 改读单遍扫描、now_ms/sleep_ms/event_mark 去子进程、删 sleep_interval）；独立对比新旧 qwb-wake.sh --dry-run --once 于真账本：stdout/stderr 逐字节相同、rc=0，/bin/bash 3.2 下亦同；各 5 次取最小 旧 1442ms → 新 303ms（机器负载约 7）；在工人副本 86f53d7 上常规环境独立跑 bash bin/qwb-test.sh full：rc=0、815 PASS / 0 FAIL、SMOKE/REVIEW-IDENTITY/LINT 均 PASS（467.10s）。工人自跑全门的 §13 FAIL 系其自加的隔离环境+假 HOME 所致，常规环境不复现。已 cherry-pick 4512b4d、86f53d7 到 main（HEAD=fd446f6），未 push。
