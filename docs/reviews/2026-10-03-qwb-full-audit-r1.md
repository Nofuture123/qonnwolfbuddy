# 全仓审核 r1：代码与性能（2026-10-03）

审核者：Claude Code 主控（Fable 5.1，Herdr pane `w14Z:p1`），四个只读子审核并行（复用 / 简化 / 性能 / 层次）。对象：`main` @ `4678ba0`，范围 `bin/*.sh`、`templates/pi-extensions/qwb-watch.ts`、`templates/*.sh`、`tests/`。不含 `docs/`、`tasks/`、角色与说明文档。本轮只审不改；修复经任务书派给 Pi 工人。

## 一、人话结论

**不用换架构，也几乎没有死代码。问题集中在三件事：门有洞、值守空转、同一条规则到处手抄。**

1. **门有洞。** 主仓现在跑全门是红的（一条测试自己写错了），而且有 12 个测试文件根本没接进任何门——1612 行的账本脚本 `qwb-ledger.sh` 在全门里零保护。后果：谁改账本脚本都没人拦。这条要最先修，否则后面的优化没有安全网。
2. **值守空转。** 值守循环每秒把全部任务书重扫一遍，现在 52 个文件一轮要 1.05 秒、起约 308 个进程，等于它一直在全速扫、没有真正「等」过；票数翻倍耗时翻倍。好比门卫每秒把整栋楼所有房间重新敲一遍门，包括早就搬空的。改成一次扫描后原型是 15 毫秒。
3. **规则手抄。** 「什么算未结」「场景门怎么判」「锁主是谁」「herdr 回了什么」这些规则，每个脚本各写一份，bash、perl、python、TS 四种语言都有。已经查实三处抄走样了（见 F14–F16）。后果：改一条规则要同步十几处，漏一处就是隐蔽 bug。

测试耗时方面：装机脚本一次要 0.68 秒，其中四成花在 `basename`/`dirname` 子进程上，而全门里装机被调 60–75 次；另有两处真等待（8 秒、3 秒）。

**「直到没有任何可优化点」不可能一轮清零。** 本轮共 32 条发现，按文件簇分三波派工；每波落地后在新 HEAD 上复审（r2、r3…），哪一轮查不出值得动的就停。

## 二、基线（main @ 4678ba0，本机实测）

机器：macOS（Darwin 27.0.0），PATH 上的 bash 5.3.20，`/bin/bash` 3.2.57。测量时本机还有别的项目的工人在跑（load average 约 4），所以绝对数字偏高，但两次测量互相吻合。

| 项 | 结果 |
|---|---|
| `bash bin/qwb-test.sh fast` | 退出码 0，2.98 秒 |
| `bash bin/qwb-test.sh full`（第一次，四个子审核同时在跑） | **退出码 1**，386.92 秒（user 178.54 / sys 140.05） |
| `bash tests/smoke.sh`（第二次，子审核已结束） | **退出码 1**，394.46 秒（user 177.90 / sys 144.69）；790 PASS / 1 FAIL，共 93 节 |
| 唯一 FAIL | §25「lint 无逐项 PASS 输出」——见 F1 |
| `bash tests/review-identity.sh` | 退出码 0，3.6 秒 |
| `bash bin/qwb-lint.sh` | 退出码 0，`LINT PASS`（10 行 PASS） |

README 记录的旧基线是 `1c500b3` 上 full 88.35 秒 / smoke 567 PASS。现在断言数涨到 791，耗时涨到约 6.5 分钟；sys 时间占四成以上，说明主要花在起进程上。

smoke 最耗时的节（第二次测量，按节标题间的时间差）：

| 节 | 秒 | 内容 |
|---|---|---|
| §79 | 37.6 | `tests/worktree-space.py` |
| §49 | 34.3 | JEV 自动派工 |
| §81 | 30.9 | `tests/r2-cli.py` |
| §82 | 17.6 | `tests/invalid-ledger.py` |
| §83 | 14.2 | `tests/r4-cli.py` |
| §51 | 12.9 | 工人最高权限启动 |
| §74 | 12.7 | `tests/runtime-readiness.sh` |
| §77 | 12.5 | `tests/worker-config.py` |
| §86 | 11.8 | JEV agents 角色层 |
| §17b / §17c | 11.5 / 10.7 | 根 pane 派发 / `--add-dir` |
| §46 | 9.7 | workspace 边界 |

§74–§86 这批子测试脚本合计约 154 秒，占 smoke 的四成（对应 F13）。

未接门的 12 个测试单独跑的结果：

| 测试 | 退出码 | 秒 |
|---|---|---|
| `collab-ci-diagnostics.sh` | 0 | 43.2 |
| `collab-gate.sh` | 0 | 209.9 |
| `collab-handoff.sh` | 0 | 39.1 |
| `collab-herdr.sh` | 0 | 38.8 |
| `collab-land.sh` | **1** | 109.6 |
| `collab-ledger.sh` | 0 | 26.9 |
| `collab-planning.sh` | 0 | 104.3 |
| `collab-posture.sh` | 0 | 44.3 |
| `collab-roles.sh` | 0 | 40.3 |
| `collab-test-policy.sh` | 0 | 64.1 |
| `lint-scenario-stream.sh` | 0 | 0.9 |
| `path-canonicalization.sh` | 0 | 0.0 |

串行合计约 12 分钟。`collab-land.sh` 在 `4678ba0` 上是红的（F34）：第 295 行断言失败，`qwb-worktree.sh land recover-endpoint` 在重新授权后仍返回 1，stderr 为「拒绝：Herdr Space task-space 关闭/焦点读回未确认，Git 未动：Herdr refusal/unknown: query/action failed:」。复跑 3 次（`4678ba0` 主仓一次、`cf4a9c0` 与 `8067347` 的 `git archive` 导出副本各一次）结果完全相同：都是 7 个 PASS 之后在同一断言失败。所以它是确定性失败，且不是今天这几个提交引入的。根因未定：可能是测试的假 herdr 落后于产品（`142cb80` 之后关闭 Space 多了焦点读回），可能是真缺陷，也可能与本机环境有关（Herdr 0.9.3、负载高时 `bin/qwb-herdr.sh:20` 的 2 秒硬超时）。第 1 波收工、机器空下来后单开一张只诊断不修的票：二分找首个变红的提交并给出根因。

## 三、发现清单

风险：低 / 中 / 高。带「已核」的是主控亲自对过代码或复现过的；其余为子审核读码结论，执行者动手前须自行复核。

### A. 门与测试完整性

| # | 位置 | 问题 | 后果 | 风险 |
|---|---|---|---|---|
| F1 已核 | `tests/smoke.sh:1374` | 用 `grep -qE '^[4-9]'` 判断 lint 的 PASS 行数 ≥4。主仓有 `qwbuddy/config.sh` 时 lint 输出 10 行 PASS，「10」以 1 开头 → 判失败。干净副本只有 9 行所以一直绿。 | 主仓全门恒红；lint 再多一项检查，所有环境都红。 | 低 |
| F2 已核 | `tests/collab-*.sh`（10 个）、`tests/lint-scenario-stream.sh`、`tests/path-canonicalization.sh` | 没有任何门或入口调用（`QWB_GATE_FULL` 只跑 smoke + review-identity + lint，smoke 里也不调）。 | 已迁票协议（`qwb-ledger.sh` 约 1000 行）在全门里零覆盖。 | 低 |
| F34 已核 | `tests/collab-land.sh:295`（here-doc 内行号） | 该测试在 `4678ba0` 上退出码 1，因为没人跑所以没人知道。 | 确定性失败（3 个提交上复现），根因待诊断；定性前不接进全门。 | 待查 |

### B. 运行时性能

| # | 位置 | 问题 | 实测 / 估算 | 风险 |
|---|---|---|---|---|
| F3 已核 | `bin/qwb-wake.sh:489-510`（`open_items`）+ `:811-815` | 每轮对每张票起 6 个外部进程，已结票也照付；等待被夹在 1 秒内，所以每秒重扫。 | `--dry-run --once` 1054ms / 约 308 次 exec（52 文件）；104 文件 2077ms，线性。单进程 perl 原型 15.5ms，输出与现实现逐字节一致。 | 低–中 |
| F4 | `bin/qwb-wake.sh:774-786, 791, 817-823` | 等待期每 50ms 一拍，每拍 `$(event_mark)` 起 head、`$(now_ms)` 起 perl、`sleep "$(printf …)"` 再起子 shell。 | 每拍 11.9ms 纯开销，约 48 次 exec/秒。 | 低 |
| F5 | `bin/qwb-status.sh:71-159` | 每票 13 个进程；已迁票读两次（`:86`、`:97`）。 | 1981ms / 约 665 次 exec。 | 低–中 |
| F6 | `bin/qwb-lint.sh:86-101, 191-225, 243-276, 286-291, 298-303` | 对账本跑 5 遍独立循环。 | 3032ms / 约 1030 次 exec；一次全门里对真账本跑 3 次。 | 低–中 |
| F7 | `bin/qwb-herdr.sh:58-76, 101-103`；`bin/qwb-wake.sh:503` → `bin/qwb-lib.sh:211-229` | 每张已迁票每秒一次 `qwb-ledger.sh read`（60.7ms/次）。 | N 张已迁票 → 每秒 N×60ms，还会堵事件接收。本仓现有 0 张已迁票，属推算。 | 中 |
| F8 | `bin/qwb-lib.sh:95` → `bin/qwb-role.sh:283, 240-272` | 身份核验触发全账本义务扫描，结果被丢弃。 | 每次角色写账多付 N×60ms（推算）。 | 低 |

### C. 测试耗时

| # | 位置 | 问题 | 实测 / 估算 | 风险 |
|---|---|---|---|---|
| F9 已核 | `bin/qwb-init.sh:171, 197, 199-200, 218, 301-302` | 每个文件用 `$(basename …)`/`$(dirname …)`，一次装机约 122 个 fork。 | 装机 677ms → 换参数展开后 403ms，产物 `diff -r` 一致。全门约调 60–75 次，推算省 16–20 秒。 | 低 |
| F10 | `tests/smoke.sh:138 + 2555-2559`（§46c）；`:2479` + `bin/qwb-wake.sh:427-430, 453-456`（§45）；`:4300`、`:3607`、`:3757` | 真等待：stub 睡 8 秒；裸 `sleep 0.5`×6 不吃假睡注入；另有 1 秒、0.4 秒×2。 | 合计约 11 秒。 | 低–中 |
| F11 | `tests/smoke.sh` 约 25 处（`:1376, 1619, 1630, …, 4127`） | 只需要「一个装好的项目」的节各自重跑装机。 | 每次 0.67 秒；`cp -R` 黄金安装 21ms。F9 之后还能再省约 9 秒。 | 中 |
| F12 | `tests/smoke.sh:44, 1371, 3412` | §51 重跑整份真仓 lint（§25 已跑过，期间真仓没变）；§2 逐文件 shellcheck。 | 约 3.5 秒。 | 低 |
| F13 已核 | `tests/smoke.sh:4331-4430` | §74–86 的子测试脚本串行，各自独立建临时目录。 | 实测合计约 154 秒（占 smoke 四成）；并发跑预计省 100 秒以上，前提是各给独立 HOME。 | 中 |
| F33 已核 | `tests/smoke.sh` §49（JEV 自动派工） | 单节 34.3 秒，原因未查。 | 第 2 波先定位再决定。 | 待查 |

### D. 同一条规则多处实现（已有漂移的排前）

| # | 位置 | 问题 | 已发生的漂移 | 风险 |
|---|---|---|---|---|
| F14 已核 | `bin/qwb-run.sh:282-292`、`bin/qwb-lint.sh:205-215`、`bin/qwb-ledger.sh:945, 1002, 1499` | 验收场景门规则三份。 | 失败路径关键词：run/lint 是 8 个（`失败\|拒绝\|报错\|异常\|负例\|非法\|fail\|error`），ledger 只有 4 个。只写「报错」的场景过得了派发门，过不了账本修订门。 | 低 |
| F15 已核 | `bin/qwb-ledger.sh:1317` 对 `bin/qwb-lib.sh:226` | 已迁票「未结义务」规则两份。 | ledger 排除 `handoff-\|ci-\|gate-(?!verdict)`，lib 漏了 `ci-`。推演后果：带 CI 事件的已迁票被值守永远算未结，`--block` 回不了 0。 | 低–中 |
| F16 已核 | `bin/qwb-wake.sh:489-510`、`bin/qwb-status.sh:74-94`、`bin/qwb-worktree.sh:86-99` | 「这张票算不算未结」三份。 | worktree 那份不查未结义务，且用文件名子串匹配（`*"$1"*`）——同文件 `unique_task_for` 已是精确匹配。 | 低–中 |
| F17 | `bin/qwb-lock.sh:106, 133`；`bin/qwb-wake.sh:217, 560, 870, 929`；`bin/qwb-send.sh:49`；`bin/qwb-hook-claude-stop.sh:50`；`bin/qwb-role.sh:141`；`bin/qwb-ledger.sh:266, 517, 879`；`qwb-watch.ts:309-318` | 主控锁 owner 解析 13 处、4 种语言、至少 4 种语义（首行去首字段 / 首行末字段 / 末非空行末字段 / 整文件匹配）。 | 今天一致只因写入方只写单行。 | 低 |
| F18 | `pane get`：`qwb-run.sh:339-344, 371-373, 410-414, 419-428`、`qwb-wake.sh:111-122`、`qwb-lib.sh:399-413`、`qwb-worktree.sh:189-196, 470-475, 511-512`、`qwb-lock.sh:88-93` 等；`process-info`「前台是空闲 shell」5 份；`tab create` 2 份 | herdr 查询响应没有共享解析层，每个脚本各自 perl/python 解析。 | `pane_not_found` 两种判法并存（grep 原文 / JSON `error.code`）；空闲 shell 判定宽严不一；`tab create` 取 `root_pane` 一严一宽。 | 中 |
| F19 | `bin/qwb-lib.sh:16-46` 对 `bin/qwb-dispatch.sh:201-235`；`bin/qwb-lib.sh:130-143` 对 `bin/qwb-role.sh:169-186` | `workers.sh` 声明解析两份；Pi 固定档位解析两份。 | 模板自带的 `pi-glm-high`（`--model zai-coding-cn/glm-5.3`，无 `--provider`）能当常驻角色，不能当门禁审核工人。**需裁决**，见第五节。 | 中 |
| F20 | `bin/qwb-herdr.sh:159-163, 184-213` 对 `bin/qwb-worktree.sh:205-254, 448-533` | 删 worktree 前的「写入者已死」证明两份 python。 | worktree 版用 `/bin/ps` 绝对路径加固，herdr 版没跟上。删除安全接缝，排最后。 | 中–高 |
| F21 | state 五值 9 处；状态行前缀集合 12 处 | 值域字面量散落。 | `qwb-dispatch.sh:167` 的头部键集合比别处多。 | 低 |
| F22 | `bin/qwb-ledger.sh:1140` | `known_family` 把三个模型型号写死在账本 writer 里，模板 `workers.sh` 的四个具名型号一个都不在表里。**需裁决**。 | — | 中 |

### E. 单文件内的手抄与死代码

| # | 位置 | 问题 | 风险 |
|---|---|---|---|
| F23 | `bin/qwb-ledger.sh` | 「打开→整读→关闭」手抄 24 处；「子 op 仍在途」判定逐字重复 5 处；另有 8 类判定各抄 2–5 份（已验收历史、规格疑点末事件、场景块合法性、规格正文剥离、identity 八键、旧 owner 已死、就绪指纹、`sha256_hex($owner_raw)` 18 次）。 | 低–中（依赖 F2 先落地） |
| F24 | `bin/qwb-worktree.sh:575-588` 对 `617-634`；`195-199` 对 `511-516`、`524-527`；`281-282` 对 `550-551` | merged 与 archive 的「删 worktree 后删分支」同构；「pane 已回 shell 且 agent 为空」抄 3 份；`LAND_PROOF` 两处各起 2 个 python。 | 中（`partial_fail` 的 stage 字符串须逐字保留） |
| F25 已核 | `bin/qwb-run.sh:828-869`；`:151-153` 对 `:194-196`；`:235-241, 556-558, 563/565, 625/635, 208/229, 474-476, 326-328/390-392, 468-473, 431-434, 768-783` | 「跑命令→判 rc→失败回滚→打印」写了 7 遍；非 auto 时 `start-check` 连调两次；一批零散冗余（一次性别名、连赋两次、恒真嵌套、同一 JSON 起两次 perl）。 | 低 |
| F26 | `bin/qwb-wake.sh:425-437` 对 `451-462`；`681-682` 对 `697-698`；`607` 对 `611`；`585-586`；`870` 对 `929` | 值守启动探测、gate 身份 proof、跳过文案、取锁主各抄两份；`lostrc` 可推导。 | 低 |
| F27 已核 | `bin/qwb-lib.sh:378-383`（`qwb_pane_activity`）；`bin/qwb-wake.sh:788`（`sleep_interval`）；`qwb-watch.ts:100, 153`（`onStdout` 形参）；`qwb-watch.ts:68, 110, 125, 292, 298-300`（`childIsProbe`） | 四处零调用的死代码。 | 低 |
| F28 | `now_ms`/`sleep_ms`：`qwb-run.sh:801-810` 对 `qwb-wake.sh:774-786`；单引号转义：`qwb-run.sh:221-228` 对 `qwb-init.sh:33-40`；任务 id→任务书：`qwb-run.sh:95-99` 对 `qwb-worktree.sh:103-111`；调用者 workspace：`qwb-run.sh:407-416` 对 `qwb-wake.sh:307-314` | 跨文件逐字重复，该进 `qwb-lib.sh`。 | 低 |
| F29 已核 | `qwb-watch.ts:227-244`；`262-268` 对 `282-291` | `onExit` 的 probe 与非 probe 分支逐项相同；失锁清理与 `shutdown` 的状态复位重复。 | 低 |
| F30 | `bin/qwb-status.sh:75-94`；`bin/qwb-dispatch.sh:67-70, 101-108, 401-406` | status 的 `mark` 判两遍；dispatch 的 `no_rules` 单调用点、两次 `jq -e` 接同一句 `die`。 | 低 |
| F31 | `tests/smoke.sh:929, 2598, 2726, 3231, 3859, 3955, 3994`；`:119, 672, 2221`；`:3672, 4316`；`:3252-3288`；`:4341-4431` | 7 个近乎相同的 `mk_*_task`；3 个逐字相同的清洗函数；2 对同体函数；§51 留着旧格式翻译器；§75–85 九节同形包装；`ok/bad` 在三个文件各一份。 | 低–中 |
| F32 | `tests/r2-cli.py`、`worktree-space.py`、`r4-cli.py`、`invalid-ledger.py`、`collab-herdr.sh:313-316`；collab-* 的假 herdr | Python 夹具靠 `runpy`/`exec` 字符串切片互相借用；假 herdr 在 17 个文件各写一份且已互相漂移。 | 低–中 |

### 查过、不报

- 主控锁、信任预置、`--add-dir` 等按宿主的特判：有 lesson 支撑的必要差异。
- `qwb-watch.ts` 的空 `onTurnEnd()`：r2 误荐 `turn_end` 后留的回归护栏。
- 可见值守 tab（`qwb-wake.sh:106-468`）、旧 `QWB_WORKER_LAUNCH` 迁移器、`pane-run`：DECISIONS 明确保留的兼容面。
- `qwb-wake.sh` 的 1 秒节奏：`:813` 注释写明的设计，只降每轮成本，不动节奏。
- `qwb-lib.sh` 的 source 期开销：没有值得报的。

## 四、分波计划

按文件簇分票，同一波内白名单互不相交。

| 波 | 票 | 文件 | 覆盖发现 |
|---|---|---|---|
| 1 | audit-gate-repair | `tests/smoke.sh`、`qwb.config.sh` | F1、F2 |
| 1 | audit-init-forks | `bin/qwb-init.sh` | F9 |
| 1 | audit-wake-hotpath | `bin/qwb-wake.sh`、`bin/qwb-lib.sh` | F3、F4、F27（bash 两处） |
| 1 | audit-run-simplify | `bin/qwb-run.sh` | F25 |
| 1 | audit-watch-ts | `templates/pi-extensions/qwb-watch.ts`、`tests/pi-ext.test.mjs` | F27（TS 两处）、F29 |
| 2 | status/lint 复用单遍扫描 | `bin/qwb-status.sh`、`bin/qwb-lint.sh` | F5、F6、F30 |
| 2 | worktree 收敛 | `bin/qwb-worktree.sh` | F16、F24 |
| 2 | lib 下沉 | `bin/qwb-lib.sh` + 调用方 | F14（bash 侧）、F17、F26、F28 |
| 2 | smoke 提速 | `tests/smoke.sh` | F10、F11、F12、F31 |
| 3 | ledger 去重与对齐 | `bin/qwb-ledger.sh` | F14（perl 侧）、F15、F23 |
| 3 | herdr 解析层 | `bin/qwb-lib.sh` + 调用方 | F18 |
| 3 | 测试夹具共享 | `tests/` | F32 |
| 3 | 已迁票读缓存 | `bin/qwb-herdr.sh`、`bin/qwb-role.sh` | F7、F8 |
| 最后 | 写入者死亡证明合一 | `bin/qwb-herdr.sh`、`bin/qwb-worktree.sh` | F20 |

每波落地后在新 HEAD 复审，再决定下一波的确切范围。

## 五、需要 Rocky 裁决（不阻塞第 1 波）

> 2026-10-04 更新：Rocky 把这些技术取舍交给主控裁决，四条均已定并落地，不再是待办。F19 → Pi 档位必须显式写 `--provider`；F22 → 模型家族改由 `workers.sh` 的 `qwb_family` 声明；F16 → 判残留时计入未结义务并改精确匹配；F14 / F15 → 按较新的那份对齐。结论与证据见「第 3、4 波与收尾结果」。

1. **F19**：`provider/model` 合写（如 `zai-coding-cn/glm-5.3`）算不算合法的 Pi 固定档位？现在常驻角色认、门禁审核不认。统一成哪一种。
2. **F22**：`known_family` 模型家族表从账本 writer 的代码里挪到 `workers.sh` 旁的声明——信任锚从代码变成主控可改的配置，是否接受。
3. **F16**：`qwb-worktree.sh list` 判残留时要不要也查未结义务（现在不查，`state=done` 但 claim 未释放的票会被建议 finish）。
4. **F14 / F15** 是对齐漂移，会改变边界行为（账本修订门多认 4 个失败关键词；lib 的义务判断多排除 `ci-`）。我的建议是都以较新的那份为准，排在第 3 波，默认执行。

## 第 1 波结果（2026-10-04，main @ 0b9faef，未 push）

执行模型：起初主控误用 glm-5.3-flash，Rocky 叫停后全部改为 Pi 默认（magpie `codex/gpt-6.1-sol` high），由 Sol 把 glm 留下的改动当草稿逐项复核。四份 glm 改动里三份被查出实质问题并修正（值守扫描吞掉目录读取错误；派发脚本两处解析改变了行为；并发测试入口三处收尾不对）。

| 票 | main 上的提交 | 覆盖发现 | 结果 |
|---|---|---|---|
| audit-init-forks | `07b0656` | F9 | 一次装机 716ms → 430ms（各 7 次取最小，负载约 3） |
| audit-watch-ts | `34a7c50` | F27（TS）、F29 | Pi 扩展 397 → 377 行 |
| audit-wake-hotpath | `d6ca4a3`、`fd446f6` | F3、F4、F27（bash） | 值守一轮扫描 1269ms → 104ms（59 个任务书，各 7 次取最小） |
| audit-run-simplify | `5a052c6`、`38db42b` | F25（A、B1–B4；B5、B6 经反例证明会改行为，保留旧实现；`start-check` 双调未动） | `qwb-run.sh` 877 → 862 行 |
| audit-gate-repair | `90fd3f4` | F1、F2（11/12） | 主仓恒红断言修复；11 个协作测试并发接进全门 |
| audit-test-isolation | `b8d18f9`、`1125c44` | 计划外（Rocky 纠正） | 测试失效关闭、临时目录进仓库内 `.qwb-tmp/` |
| audit-lint-pipe | `011389b` | 合并全门暴露 | smoke 199 处断言去管道；主仓 lint 输出 262510 → 8661 字节 |
| audit-collab-flake | `32cb242`、`f55544e`、`0b9faef` | 合并全门暴露 | 测试进程登记与排空；并发跑批不再偶发清理失败 |

收尾全门（主仓真实布局，负载约 2–3）：`bash bin/qwb-test.sh full` 退出码 0，831 PASS / 0 FAIL，SMOKE / REVIEW-IDENTITY / LINT / COLLAB-ALL（11 项）全过，572.27 秒；跑完工作区无新增改动、`.qwb-tmp/` 为空、无残留进程。

单独的 smoke：346.04 秒、795 PASS（开头基线 394.46 秒、791 条；两次负载不同，只能说没有变慢）。全门总时长因多跑 11 个协作测试而从约 390 秒变为约 572 秒。

第 1 波过程中新暴露、不在最初清单里的问题：

- **F35 产品缺陷**：值守退出时 `event_cleanup` 只回收订阅器，订阅器正在进行的 `qwb-ledger.sh read` 子进程成为孤儿并重建侧车锁文件。修复票 `audit-subscribe-reap`。
- **F36 测试失效开放**：smoke 的假 herdr 只靠 PATH 前置，桩消失后打到真 Herdr（事故见 `tasks/lessons/测试桩失效会打到真Herdr.md`）。已由 audit-test-isolation 修复；顺带发现 smoke 第 13 节的锁释放用例一直在查询真 Herdr。
- **F37 测试断言随账本内容变脆**：大输出下 `printf | grep -q` 在 `pipefail` 下被 SIGPIPE 误判。已由 audit-lint-pipe 修复。
- **F34** `collab-land.sh` 确定性的红：诊断票 `audit-collab-land-red`。

验收上的一次疏漏：值守提速与派发简化验收时，协作测试尚未接进全门，主控没有手动补跑，合并全门才暴露并发清理竞态。此后凡改 `bin/` 的票，全门都已包含协作测试。

第 2 波见下节。

## 第 2 波结果（2026-10-04，main @ 703b44a，未 push）

| 票 | main 上的提交 | 覆盖发现 | 结果 |
|---|---|---|---|
| audit-status-lint-scan | `098c405`、`ce2d235`、`3ead225` | F5、F6、F30（status） | 点名约 2.4s → 0.9s、lint 约 4.1s → 1.8s（执行者各 7 次取最小）；未结义务规则在 lib 只留一处 |
| audit-collab-land-red | `a7722dc` | F34 | 根因：合并提交 `c4403be` 引入新的关闭 Space 协议后测试假件未跟上；补假件、断言未动；接进全门（12 项） |
| audit-socket-path | `734996d`、`7870b65`、`f23cafe`、`ade605c` | F38 | 测试 socket 统一建在 `仓库根/.qwb-tmp/两位十六进制/s`，按字节守卫，超 103 立即报错；仓库根预算 89 字节 |
| audit-socket-land | `b105ee9` | F38 补漏 | collab-land 的 socket 改走统一夹具 |
| audit-subscribe-reap | `abe5830`、`703b44a` | F35 | 值守退出时整组回收订阅器的子命令；回归测试旧 bin 10 次红、修复后 10 次绿；正常路径不加 ps |

收尾全门（主仓真实布局）：`bash bin/qwb-test.sh full` 退出码 0，840 PASS / 0 FAIL，SMOKE（末节第 88 节）/ REVIEW-IDENTITY / LINT / COLLAB-ALL（12 项）全过，625.04 秒；跑完工作区无新增改动、`.qwb-tmp/` 为空、无残留进程。

第 2 波新暴露：**F38 测试 socket 路径随仓库路径变长而超过 macOS 的 103 字节上限**（临时目录进仓库后带出），已修。主控裁决不改产品（`bin/qwb-herdr.sh` 要求绝对 socket 路径是安全校验，真实 Herdr 的 socket 在项目外的短路径上）。

仍未处理（按价值排序）：全门提速（F10–F13、F33：smoke 重复装机、子测试串行、真等待）；规则多处实现的收敛（F14、F15、F17、F18、F21、F26、F28）；`qwb-worktree.sh` 简化（F16、F24）；`qwb-ledger.sh` 去重（F23）；已迁票读缓存（F7、F8）；测试夹具共享（F31、F32）；写入者死亡证明合一（F20）；需裁决的 F19、F22。

## 收口实测（2026-10-04，main @ 703b44a 对比起点 4678ba0，同一台机器、负载约 3–5、各 7 次取最小）

| 项 | 起点 | 现在 | 变化 |
|---|---|---|---|
| 值守一轮账本扫描（`qwb-wake.sh --dry-run --once`，65 个任务书） | 1311 ms | 59 ms | −95% |
| 点名（`qwb-status.sh`） | 2428 ms | 998 ms | −59% |
| lint（`qwb-lint.sh`） | 3765 ms | 1885 ms | −50% |
| 一次装机（`qwb-init.sh`） | 684 ms | 407 ms | −40% |
| smoke 单独 | 394 s / 791 条 | 381 s / 803 条 | 基本持平 |
| 全门 | 约 390 s，主仓恒红，12 个测试未接入 | 约 570–625 s，主仓全绿，840 条，12 个协作测试并发接入 | 变长约 200 s |

smoke 没有变快：装机与值守的提速被新增的测试进程监督、两节新回归和 12 条新断言抵消。全门变长是把此前没人跑的 12 个协作测试接进来的代价。全门提速（F10–F13、F33）尚未动手，是下一波的主体。

本轮收口时：13 张票全部 `verified`，代码与账本均已提交到本地 `main`（未 push）；11 个隔离副本与 11 个工人 Tab 已清理；主控锁已释放。各票 `done:` 行里引用的执行者证据路径（`.worktrees/…/.qwb-tmp/…` 与 `/tmp/qwb-*`）随清理一并删除，存留的验收证据是各票里主控的 `working:` 验收行。

## 第 3、4 波与收尾结果（2026-10-04，main @ 20ea2cc）

执行模型：全部为 Pi（`--provider magpie --model codex/gpt-6.1-sol --thinking high`，Rocky 2026-10-04 指定）。Rocky 当天把技术取舍交给主控裁决，并说明本仓是他之后所有项目的初始化脚本；主控据此把优先级定为「会被装进各项目的运行时先保正确与不漂移」，只影响本仓测试的整理排后或不做。

| 票 | 覆盖 | 结果 |
|---|---|---|
| audit-lib-sink | F14（bash 侧）、F15、F17、F26、F28、F39、F40 | 锁主解析（语义相同的两处）、计时睡眠、引号转义、场景判定下沉到 lib；三处有意修正：已迁票义务判定补排除 `ci-`、值守在所有退出路径清理 `qwb-due.*`、派发门不再因 SIGPIPE 误拒大场景块 |
| audit-ledger-dedupe | F23、F14（perl 侧） | 11 类手抄各收成一个函数，14 个提交逐类过协作测试；失败关键词由 4 个对齐到 8 个。行数 1612 → 1660，收益是规则单点定义 |
| audit-reap-window | F41 | 订阅回收测试把「没赶上观察窗口」归为无结论并重试；进程快照解码不再因坏字节抛错 |
| audit-smoke-speed | F10–F13、F33 | smoke 单独 394 s → 190 s；合并前后 843 行节标题与 PASS/FAIL 按序逐行一致 |
| audit-worktree-tidy | F16、F24 | 收尾脚本三类重复收敛；残留判定改精确匹配并计入未结义务 |
| audit-pi-profile | F19、F22 | Pi 档位必须显式 `--provider`；模型家族改由 `workers.sh` 的 `qwb_family` 声明；模板新增 `pi-sol-high` |
| audit-herdr-parse | F18（部分） | 只合并了确实等价的解析；12 组宽严差异保留（见下） |
| audit-orphan-tests | F42 | 三个未接门的回归脚本接入（并发跑批 15 项）；全门启动前自检「测试文件必须有入口」；33 处测试等待上限放宽 |
| audit-death-proof | F20（收窄）、F43 | `qwb-herdr.sh` 的「进程已死」判定对齐到加固版；同名前台进程多于一个时取前台进程组组长 |
| audit-readme-refresh | — | README 逐句核对更新；真机验收脚本认得现在的 Codex 与 Pi 界面；Pi 主控默认改为 magpie sol |
| audit-writer-proof-missing | F44 | 收尾新增显式、留痕的兑底参数 `--writer-proof-missing=<原因>`，两层各自复核 |

过程中新暴露的问题：

- **F39** 值守被终止时在系统临时目录残留 `qwb-due.*`（清理时发现 41 个）。已修。
- **F40** 派发场景门对约 1 MB 的合法场景块误报「无可识别场景」（`pipefail` 下 `grep -q` 的 SIGPIPE 假阴性）。已修。
- **F41** 订阅回收的回归测试在高负载下把「没赶上产品 2 秒超时前的窗口」当成失败。已修。主控验收时只在低负载下验过，是疏漏。
- **F42** 第 2 波新增的三个回归脚本没有接进任何门——与 F2 同类，主控验收时未查。已修并加自检。
- **F43（真机验收抓到）** devin 运行时有两个同名前台进程，`activity()` 的「名字匹配恰好一个」认不出原生进程，派发证据缺 PID，`finish` 永远被拒且无合规出路。假 Herdr 的全部测试都没发现。已修。Pi 与 Claude Code 的进程形态不受影响。
- **F44** 派发时身份绑不上的票没有任何合规的收尾出路。已加显式兑底；未改成派发时拒绝，因为缺少各工人在真环境下的进程形态数据。
- **F45（真机演练抓到）** 真 Herdr 0.9.3 对没有 agent 的 pane 不返回 `agent` 键，产品四处要求该键存在且为 null；假 Herdr 一律返回 null。pane 仍在时的 `--writer-proof-missing` 兑底在真机上永远被拒（实测），land 收尾的两处判定同样（读代码得出，未演练）。方向是拒绝不是误删。起点已有。已修（`audit-finish-real`，`9e86d98`）：键不存在与为 null 同样算没有 agent，其余核对未放松；修复后真机重演通过（pane 仍在的兑底放行），land 两处仍只有假 Herdr 证据。[演练记录](2026-10-04-real-herdr-finish-drill.md)
- **F46（真机演练抓到）** 工人停在自己界面里时，默认 `finish --merged` 必然因「候选写入者仍持cwd/FD」被拒，而拒绝信息与主控说明都不写出路。第 7 轮真机验收里 Claude Code 主控被拒两次，自己读源码摸出「让 devin 退出、把工人 shell 挪出副本」才收尾。实测通用出路是关闭工人 pane。已修（同上）：拒绝时追加一行提示，列出占着副本的进程与可直接执行的 `herdr pane close`；两份主控说明补了收尾前先让工人退出的做法；真机重演通过。
- **F47** `tests/process-entry-cleanup.py`（整份 smoke 被 TERM 后夹具应清空自己的目录）在高负载下会残留空的登记目录而失败：合入 F45/F46 后的 main 在另一工人同时跑整门时 rc=1（843 PASS / 1 FAIL），低负载单跑三次均通过；`47de4b6` 源码的基线在同样负载下也红在这一条。是测试夹具的清理竞态，不涉及运行时。交 `audit-gate-parallel` 收口。
- **F48（Rocky 提问引出）** Claude 值守钩子在「有未结票但无任何变化」时每两个周期（真实为 4 小时）以「值守接班未就绪」叫醒主控一次并无限循环，包括只剩等人裁决的票这种没有任何可做之事的情形；9 月的版本到期是安静退出，这条是 10-01 的 `90aa764` 加的。已修（`audit-hook-quiet`，`a53942e`、`41fc0bd`）：未结项全是等裁决的未迁旧票时到期安静退出；有 `running` 旧票或任何未结的已迁票、或判定失败时保留原门铃。`QWB_REWAKE_MS` 的 30 分钟兜底重叫未动。只在假 Herdr 与临时项目里验证，没有在真会话里等过真实周期。

`audit-herdr-parse` 留下的宽严差异（193 组输入中 12 组新旧不一致，均未合并）：11 组在 `bin/qwb-wake.sh` 的 `pane_info`——字段为空、为 `null` 或为数组时它输出空列或把数组引用原样串化，不报错；1 组在值守新建 tab 处——对 `root_pane.pane_id` 不做类型校验，而派发脚本严格校验。没有「该拒绝的没拒绝并导致错误动作」的情形。是否把值守一侧收紧，留待有真 Herdr 畸形应答证据时再定。

### 真机端到端验收（Herdr 0.9.3，各轮独立 named session，默认会话未被触碰）

| 轮 | 候选 | 主控 | 工人 | 结果 |
|---|---|---|---|---|
| 1 | `ded7d88` | Pi magpie sol high | devin | 未进入产品流程：验收脚本认不出 Pi 现在的状态栏 |
| 2 | `ded7d88` | Codex luna max | cmdc | 未进入产品流程：验收脚本认不出 Codex 现在的界面 |
| 3 | `ded7d88` | Claude Code opus high | devin | 派发、值守唤醒（5 次送达）、验收、合入均成功；`finish --merged` 被拒（F43）。[记录](2026-10-04-e2e-real-claude-devin-blocked.md) |
| 4 | `ded7d88` + 4 个修复提交 | Pi magpie sol high | devin | 通过，断言全 PASS |
| 5 | 同上 | Claude Code opus high | cmdc | cmdc 报额度不足，未产出改动；主控按规则标 `blocked` 并停下 |
| 6 | `20ea2cc`（最终 main） | Pi magpie sol high | devin | **通过，rc=0，断言全 PASS**。[记录](2026-10-04-e2e-real-pi-sol-devin.md) |
| 7 | `47de4b6`（运行代码同 `20ea2cc`，其后只有文档提交） | Claude Code opus high | devin | **通过，rc=0，13 项断言全 PASS**；Stop hook 唤醒 2 次送达、逐轮跳过行 0、收尾后送达 0；主控提示投递到输出 DONE 约 2.5 分钟。其间 `finish --merged` 被拒两次，主控自行摸索出路后成功（见 F46）。[记录](2026-10-04-e2e-real-claude-devin.md) |

已证实：Pi 主控加 devin 工人、Claude Code 主控加 devin 工人这两种组合，在当前源码上无人工介入走完派发、值守唤醒、验收、合入、删副本、关 Space；`--writer-proof-missing` 兑底在 pane 已关与 pane 仍在两种情形下的真机放行与拒绝（[演练记录](2026-10-04-real-herdr-finish-drill.md)）。未证实：Codex 主控（周额度仅剩 19%，未跑）；cmdc 工人（额度不足）；其余工人的原生进程形态；land 收尾（已迁协作票）的真机演练；首次信任提示、长时间值守与重启恢复、生产场景试用。

### 最终实测（main @ 20ea2cc 对比起点 4678ba0，同机、负载约 2–4、新旧背靠背各 7 次取最小）

| 项 | 起点 | 现在 | 变化 |
|---|---|---|---|
| 值守一轮账本扫描（76 个任务书） | 1564 ms | 103 ms | −93% |
| 点名 `qwb-status.sh` | 2860 ms | 1051 ms | −63% |
| `qwb-lint.sh` | 4214 ms | 1961 ms | −53% |
| 一次装机 | 696 ms | 405 ms | −42% |
| smoke 单独 | 394 s / 791 条 | 190 s / 804 条（两次：190.13、191.28） | −52% |
| 全门 | 约 390 s，主仓恒红，12 个测试未接入 | 457–574 s，主仓全绿，844 条，15 项并发协作测试 | 变长约 70–180 s |

全门仍比起点长，是把此前没人跑的 15 个测试接进来的代价；其中 `collab-gate.sh` 一项约 240 秒，决定了并发跑批的下限。

代码量：`bin/` 合计 7312 → 7602 行（`qwb-lib.sh` 419 → 616、`qwb-worktree.sh` 652 → 764、`qwb-herdr.sh` 256 → 358、`qwb-ledger.sh` 1612 → 1660；`qwb-run.sh` 877 → 821）。这一轮的产出是正确性、可验证性与规则单点定义，不是代码变短。

### 全门并发（2026-10-05，`audit-gate-parallel`，main @ c2079f0）

全门四段（smoke、review-identity、lint、collab-all）改为同时运行、输出按原顺序打印；collab-all 内部限六个并发并先启动最慢的几项；`socket-path-regression.py` 的四个正例与 `collab-herdr.sh` 的八段各自在独立范围里并发。运行时脚本与模板零改动。顺带收口 F47：被中断时由父级监督器按登记回执清理嵌套范围，修复了高负载下残留空登记目录的竞态。

| 对象 | 条件 | 结果 |
|---|---|---|
| 候选 f21b1d0（主控测，重启后顺序执行） | 负载 13–23 | 383 秒、440 秒，均 rc=0、843/0 |
| 依次运行的 main b1a95f6（同一时段，主控测） | 负载 13–23 | 769 秒、1044 秒，均 rc=0、844/0 |
| 候选 a63304f（工人顺序五连） | 负载 5–47 | 385、421、492、502、487 秒，五次 rc=0、843/0 |
| 合入后的 main（主控测） | 负载约 55 | 502 秒，rc=0、844/0，无残留目录 |

隔离副本少的 1 条 PASS 是「两份配置一致」检查，副本里没有本地配置，按原规则不适用。失败注入（smoke 段失败、collab 段失败时全门 rc=1 且四段仍按原顺序）与中断回归（TERM 后 5 秒无残留进程与目录）由已接入的 `tests/process-entry-cleanup.py`、`tests/process-fixture-check.py` 覆盖。原定「不超过 300 秒」的线未达到，主控中途作废：最慢的 `collab-gate.sh` 与 `socket-path-regression.py` 单项就要四到八分钟，其中没有可删的空等。并发后全门用时约为依次运行的一半。工人第 3 至 5 次的用时受主控同时在两个真项目里测速的干扰，偏慢。

### 已装项目升级（2026-10-04，Rocky 指示，安装源 main @ f88eb7a，F48 修复后以 96d60d0 重装）

`qonnwolf-sites`（原 9-27 版）、`qonnwolfmcp`、`video_analysis/class-video-analysis`（原 9-24 版）三个项目用 `bash bin/qwb-init.sh <项目>` 升级。先在本仓库临时目录里对三份安装文件的拷贝试装，确认新版能读旧式 `qwb_worker 名字 herdr 参数…` 声明后再动真项目。结果：三个项目的 15 个运行脚本与母本逐字节相同（安装器自身不装进项目）；`config.sh`、`brief-include.md`、`dispatch-rules.json` 未动；`workers.sh` 只给 claude 行加了 `--add-dir 项目根`；Pi 扩展更新，旧文件留为 `qwb-watch.ts.bak`；`qwb-status.sh` 三处 rc=0；`qwb-lint.sh` 在 sites 与 class-video-analysis 通过，在 qonnwolfmcp 有 1 条失败（`2026-09-27-t3d-fold-count.md` 验收场景在派发后被改动），升级前的旧版 lint 同样报这一条。改动均未提交，留给各项目自己审。新增的 `pi-sol-high` 等具名工人与 `qwb_family` 声明不会自动出现在已有的 `workers.sh` 里。升级后没有在这三个项目里实际派过票。

### 已装项目第二次升级（2026-10-05，安装源 main @ c6524e0）

`qonnwolfmcp` 与 `video_analysis/class-video-analysis` 升级到当前主干并换成五角色工人表：先在本仓临时目录对两个项目的配置副本试装，再动真项目。做法：备份 `config.sh`、`workers.sh`、`dispatch-rules.json` 到本仓 `.qwb-tmp/upgrade-2026-10-05/<项目>/`；`workers.sh` 与 `dispatch-rules.json` 换成当前模板，`config.sh` 只改 `QWB_WORKERS` 一行；再跑安装器（给三条 Claude 工人声明加上 `--add-dir 项目根`）。结果：两个项目的运行脚本与母本逐字节相同；`qwb-status.sh` 均 rc=0；`qwb-lint.sh` 在 class-video-analysis 通过，在 qonnwolfmcp 仍是升级前就有的那 1 条失败（`2026-09-27-t3d-fold-count.md` 验收场景在派发后被改动）。改动均未提交，留给各项目自己审。两个项目的 `config.sh` 没有新增 `QWB_SILENT_END_MS`、`QWB_ROLE_PI_CONTROL`、`QWB_ROLE_CLAUDE_CONTROL` 三行（脚本对它们有默认值：收工未报告 60 秒、两个常驻职责开关默认关闭）。升级后没有在这两个项目里实际派过票。

`qonnwolf-sites` 当时没有升级（它的主控当天仍在用旧工人表，`2026-10-05-web-cover.md` 09:40Z 派给 `codex`、状态 `blocked` 未结案）。Rocky 同日指示安装后，以 main @ `dec0af6` 用同样的做法升级：运行脚本与母本逐字节相同，`qwb-lint.sh` 通过，`qwb-status.sh` rc=0；它 9 月 26 日定的派工规则（执行用 codex、审核用 Claude）已换成五角色规则，旧文件备份在 `.qwb-tmp/upgrade-2026-10-05/qonnwolf-sites/`。那张未结案的票若要续派，须改用新工人表里的名字。

同日 Rocky 确认「禁止使用 subagent」：`templates/QWBUDDY.md` 硬规矩新增第 7 条，`templates/brief-include.md` 新增一行（提交 `dec0af6`，全门 rc=0、865 PASS / 0 FAIL）。三个已装项目都重跑了安装器拿到新的总说明，并在各自的 `brief-include.md` 末尾补了同一行（该文件安装器不覆盖，由主控手工追加）。

### 工具与角色调整（2026-10-05，main @ 4bdd2fd）

Rocky 2026-10-05 裁决：工具只留 Claude Code 与 Pi（Pi 下模型全走 magpie）；独立审核「模型不一样即可」，不再要求换家族；角色定为主控（Claude Code opus 5.5 medium）、副主控（Claude Code opus 5.5 或 Pi astra low）、工人（Pi sol high，复杂架构 astra high 或 fable low）、门控（Pi astra low，工人是 astra 时用 sol high）、顾问（fable 或 astra high）。副主控即现有「规划」常驻职责，门控即「门禁」常驻职责，这两条路仍未在真机上跑过。

本波四张票（均由 Pi magpie `codex/gpt-6.1-sol` high 执行，主控独立验收后 cherry-pick）：

| 票 | 提交 | 内容 |
|---|---|---|
| `harness-roster` | `6cd9bbb`…`2183765` | 新装工人表只剩七个（Claude Code 与 Pi），派工规则按上述档位；说明与真机验收脚本去掉 Codex、devin、cmdc 入口 |
| `review-model-rule` | `9929c85`、`deea7cd` | lint 第 8 节与 `gate-review` 改为「模型不同、会话不同」：取最后一个 `/` 后的型号、忽略大小写比较，同型号换渠道或换档位算同一模型；`family` 降为可选附记；原 Sol→Astra 批准不再是放行条件，也不能放行同模型 |
| `wake-tighten` | `acbdbd4`、`4bdd2fd` | 未迁 running 票、工人未丢失、末行是 `working:` 时不叫醒；兜底时钟取票文件修改时间与最近 `wake:` 时间戳中较晚者 |
| `runtime-ignore` | `f360ed7`、`3b99fe3`、`1dc4760` | 安装器忽略规则由 9 条补到 27 条；真机验收预置票补授权票头，新增「收尾后工作区干净且历史无票锁文件」断言 |

合并后 main @ `4bdd2fd`：`bash bin/qwb-test.sh full` rc=0，859 PASS / 0 FAIL，429 秒（主控独立跑，同时在跑一轮真机验收）。

本波真机验收（Herdr 0.9.3、Pi 1.0.2、Claude Code 2.1.289）：

| 轮 | 候选 | 主控 | 工人 | 结果 |
|---|---|---|---|---|
| 8 | `2183765` | Claude Code opus 5.5 medium | Pi sol high | **通过，13 项断言全 PASS**，约 2.5 分钟。首次派发被拒一次（F50）；主控被进度行白叫醒三次（F51）；主控 `git add tasks` 误提交票锁文件后自行撤下（F49）。[记录](2026-10-05-e2e-real-claude-pi.md) |
| 9 | `2183765` | Pi sol high | Claude Code opus 5.5 medium | 流程走通（派发、验收、合入、收尾一次成功），`host_wake` 一项断言失败：主控在处理一次进度行叫醒时工人恰好交付，没有出现「被完成行叫醒」（F51）。未在修复后重跑。[记录](2026-10-05-e2e-real-pi-claude-hostwake-fail.md) |
| 10 | `4bdd2fd` | Claude Code opus 5.5 medium | Pi sol high | **通过，14 项断言全 PASS**。首次派发未被拒；工人三条进度行均未叫醒主控；收尾后工作区干净。派发后提示词停在 Pi 输入框未提交，主控被 30 秒兜底叫醒后补回车（F52）。[记录](2026-10-05-e2e-real-claude-pi-r2.md) |

本波发现：

- **F49（真机抓到，已修）** 票锁文件 `tasks/<票>.md.qwb-lock`、`qwbuddy/.supervisor.guard`、`qwbuddy/.roles/` 等运行态路径不在安装器的忽略规则里；qonnwolf-sites 与 qonnwolfmcp 的 `git status` 里都挂着未跟踪的守卫文件。
- **F50（真机抓到，已修）** 真机验收预置票缺 `implementation-authorized:` 与 `dispatch-budget:`，主控首次派发必被拒一次。
- **F51（已修）** 进度行叫醒：qonnwolf-sites 与 qonnwolfmcp 历史账本 95 张票 904 次叫醒，57.0% 发生在末行为 `working:` 时，17.1% 为时间兜底重叫，15.6% 为 `done:`，7.7% 为尚无状态行，2.6% 为 `blocked:` 或 `needs-decision:`。
- **F52（真机抓到，已修，见下节）** `herdr` 启动方式在 `herdr agent prompt` 之后不确认工人开工；当天约七次 Pi 启动里两次提示词停在输入框未提交，派工脚本仍报「已派发」。`pane-run` 启动方式原有确认与补回车。票 `prompt-submit`。
- **F53（已修，见下节）** `tests/subscribe-reap.py` 要求 2 秒内观察到事件，高负载下五次重采样都会超时而使全门 rc=1；当天两个工人各因此多跑一轮全门，单独复跑均通过。
- 未修的小项：工人与主控在未迁旧票上都会先试 `qwb-ledger.sh append` 被拒（rc=25）再改用直接追加；`templates/roles/主控.md` 与 `bin/qwb-run.sh` 发给审核者的提示里仍有「同family」字样；派工规则的顾问档只配了 fable 一个候选。

### 副主控链路与派发可靠性（2026-10-05，main @ adfb7b4）

当天把副主控（规划）与门控（门禁）两个常驻职责第一次放到真机上演练（隔离会话；主控 Claude Code opus 5.5 medium，规划与门禁 Pi astra low，工人 Pi sol high）：职责启动、主控授权、规划开票、规划派工都成功，工人交付后链路断掉，门禁没有被用到。发现 D1–D8 见[演练记录](2026-10-05-real-herdr-roles-drill.md)。据此开票修复，另有两张票来自当天的全门与真机验收。

| 票 | 执行者 | 提交 | 内容 |
|---|---|---|---|
| `prompt-submit` | Pi sol high | `6d906c9`…`57d6e7a` | 派发后确认工人开工：比较 `herdr agent get` 的 `state_change_seq` 或状态为 working；5 秒未开工补一次回车，仍未开工则派发失败并给排查命令。首次派发、续派、`pane-run` 三条路共用。修 F52 |
| `planner-ticket-body` | Pi sol high | `abf5d05` | 规划 `new` 开出的票固定带报告要求一节（与 `templates/TASK.md` 同文，测试断言两处一致）；`gate-assign` 拒绝候选不干净时列出路径并写明由谁续派；`qwb-role.sh start` 缺工作区时写明填 `QWB_WORKSPACE` 并列出可选 id；规定角色的载荷文件放 `qwbuddy/.roles/<actor>.work/`。修 D1、D5、D5b、D8 |
| `planner-upward` | Pi astra high | `e7113c0`…`b6366c8` | 带规划授权的票：工人 `done` 留给主控（门禁已接手且在 pending 或 rework 时仍先给门禁）；门禁 accepted 与需主控重诊的结论留给主控；规划办理完工人的阻塞类交接时，同一次写入里派生上行交接给主控；规划不能替主控确认主控专属的交接。修 D4。[设计](../designs/2026-10-05-planner-upward.md) |
| `reap-test-load` | Pi sol high | `015fb4f` | 订阅回收测试挪到全门四段并发之后串行执行（冒烟单跑时照旧实测）；错过观察窗口后退避 1、2、4、8 秒再试；五次都量不到仍判失败。修 F53 |
| `wake-exit-hang` | Pi sol high | `1624688` | 值守退出清理有时限：对订阅器发 TERM、再发 TERM、最后 KILL，总上限 4 秒；订阅器两层循环检查停止标志，退出异常被吞也最多多跑一轮。修 F57 |
| `reuse-binding` | Pi sol high | `1ac7a81`、`44ab8ac` | 首次派发 Pi 工人时最多等 10 秒会话路径再记身份；续派的三项比对不变；旧记录没有会话时拒绝并给出换名重派或关闭原 pane 两条出路。修 F55（演练 D7） |
| `prompt-start-window` | Pi sol high | `5e4a160`、`4b1f2e2` | 补回车仍在 5 秒时做，补回车后的等待放宽到 60 秒；补回车的说明改为打印到标准输出（原先写进票，门禁派工时会被账本拒绝而使派发失败）。修 F56 |
| `collab-silence-fallback` | Pi astra high | `fd2c8c2`…`538803f` | 已迁票：纯进度行不门铃任何角色，也不算未结义务；工人窗口丢失或超过重叫间隔无动静时叫醒派工者（副主控派的叫副主控，其余叫主控）；交接投满三次未接时升级主控一次，之后最短每 30 分钟重提。修演练 D6。[设计](../designs/2026-10-05-collab-silence-fallback.md) |
| `land-env-digest` | Pi astra high | `a18134c` | 落地各步核对「验收条件未变」时沿用门控通过时记录的环境摘要，候选的提交、规格、场景、命令、工人配置仍现场重算；采样环境时统一语言环境，消除包装脚本造成的差异；门控自己各步的环境比对不变。修演练二 R5 |
| `scenario-names` | Pi sol high | `0b72de8`、`adfb7b4` | 规划开票与修订时按门控的标准校验场景标题（每个三级标题须为 `### user_名字`）；`gate-assign` 与 `revise-scenarios` 两处拒绝写出路；模板里矛盾的说法改掉。修演练二 R1、R2 |
| `collab-notify-gaps` | Pi astra high | `f08f07c`…`39e6966` | 门控授权成功即派生「待接手」交接并由值守门铃门控；规划办完主控发来的请求（含需求原话）时原子上报主控；本代登记的等待到期即重提，之后最短每 30 分钟一次；门控给出结论并交还后单独通知主控；落地各步自己写的行不再成为主控自己的待办，门控结论在主控完成落地授权后视为已处理。修演练二 R3、R4、R6、R7。[设计](../designs/2026-10-05-collab-notify-gaps.md) |

合并后 main @ `015fb4f`：`bash bin/qwb-test.sh full` rc=0，859 PASS / 0 FAIL，731 秒（主控独立跑；同时有一个工人在跑另一轮全门，负载 25–41）。再合入 `wake-exit-hang` 与 `reuse-binding` 后 main @ `44ab8ac`：全门 rc=0，859 PASS / 0 FAIL，669 秒。再合入 `prompt-start-window` 与 `collab-silence-fallback` 后 main @ `4b1f2e2`：全门 rc=0，859 PASS / 0 FAIL，611 秒（其前一轮在 `538803f` 上 rc=1：冒烟第 74 节写死的通过条数没有随 `prompt-start-window` 新增用例更新，主控补了条数）。此前两轮主干全门失败过：`57d6e7a` 上 857 PASS / 2 FAIL（`process-entry-cleanup` 入口超时、`socket-path-regression`，当时六轮全门并发，负载约 85）；`abf5d05` 上 858 PASS / 1 FAIL（`socket-path-regression`，单独重跑 rc=0）。再合入 `land-env-digest`、`scenario-names`、`collab-notify-gaps` 后 main @ `adfb7b4`：全门 rc=0，859 PASS / 0 FAIL，825 秒（其前一轮在 `3f26a6d` 上 rc=1、43 项失败，根因一处：`scenario-names` 的拒绝信息里变量后紧跟中文标点，被账本检查拦下；工人只跑了快门）。

真机验收：

| 轮 | 候选 | 主控 | 工人 | 结果 |
|---|---|---|---|---|
| 11 | `57d6e7a` | Claude Code opus 5.5 medium | Pi sol high | **通过，14 项断言全 PASS**，约 2 分钟。首次派发未触发补回车；身份记录带会话路径。[记录](2026-10-05-e2e-real-claude-pi-r3.md) |
| 12 | `44ab8ac` | Claude Code opus 5.5 medium | Pi sol high | **通过，14 项断言全 PASS**，约 2 分钟（同时在跑一轮全门）。[记录](2026-10-05-e2e-real-claude-pi-r4.md) |
| 13 | `4b1f2e2` | Claude Code opus 5.5 medium | Pi sol high | **通过，14 项断言全 PASS**。[记录](2026-10-05-e2e-real-claude-pi-r5.md) |
| 14 | `adfb7b4` | Claude Code opus 5.5 medium | Pi sol high | **通过，14 项断言全 PASS**。[记录](2026-10-05-e2e-real-claude-pi-r6.md) |

本节发现：

- **F54（已随 `prompt-submit` 修）** 旧的 `pane-run` 开工确认把 `herdr agent wait --timeout 300` 当成 300 秒，实际单位是毫秒，只等 0.3 秒。
- **F55（真机抓到，已修）** 续派原工人会被拒：Herdr 在 `agent start` 返回约 1.5 秒后才报出 Pi 的会话路径（主控实测 0.02、0.14、0.28 秒时没有，1.52 秒时有），派工脚本在启动返回后立刻记身份，记录里就没有会话；续派时三项比对永远不等。时序相关，第 11 轮真机验收没撞上。票 `reuse-binding`（演练记录 D7）。
- **F56（已修）** 派发后的开工确认窗口偏短：补回车后只再等 5 秒就判派发失败。当天负载约 40 时一次手工派发里 Pi 超过 20 秒才显示开工。高负载下可能把已经开工的工人判成派发失败。
- **F57（现场取证，已修）** 值守退出时可能永久卡住：一个 `qwb-wake.sh --block --max-ms 1` 运行 16 分钟不退，调用栈停在退出清理 `event_cleanup` 的 `wait "$EVENT_PID"`；订阅器收到终止信号后没有退出、仍在正常循环。主控的推断（未证实是这次现场的原因）：订阅器靠信号处理函数抛 `SystemExit` 退出，异常若落在对象析构期间会被 Python 丢弃。票 `wake-exit-hang`。
- **F58（未查明）** 多轮全门并发、负载 60–85 时，`process-entry-cleanup`（入口 60 秒超时；一次在全门 TERM 用例后观察到临时目录残留）与 `socket-path-regression` 会失败，低负载单跑通过。失败输出被截断，没有拿到具体断言。做法上改为：工人只跑快门与定向测试，全门由主控在合并后串行跑。
- 演练记录里的 D6（已迁票的进度行会叫规划）已由 `collab-silence-fallback` 修；D3（说明书四处缺口）未修，归入角色说明合并票。
- **第二轮真机演练**（候选 `59f6734`，04:27Z–05:18Z）：整条链第一次走到落地与收尾，但靠主控模型读源码与绕路，其中一处绕开了官方落地脚本。发现 R1–R10 见[记录](2026-10-05-real-herdr-roles-drill-r2.md)。R1–R7 已由 `land-env-digest`、`scenario-names`、`collab-notify-gaps` 修（见上表）；R8（说明书缺口）归入角色说明合并票。
- **第三轮真机演练**（候选 `adfb7b4`，07:17Z–07:32Z）：15 分钟走完全链，没有使用者介入、没有全员空等、没有绕开任何脚本；门控被自动叫到，交还通知叫醒主控，官方落地脚本可用。R1、R3（回报部分）、R4–R7 在真机上确认已修；R2（修订路径）与等待到期本轮没有触发，未验证。主控仍被拒 5 次，其中 2 处要读脚本源码才知道载荷怎么写。发现 S1–S8 见[记录](2026-10-05-real-herdr-roles-drill-r3.md)，已开票 `roles-walkthrough-docs`（说明书与可执行示例）与 `roles-polish-code`（拒绝信息、状态显示口径、落地前置检查），在做。
- **F59（未修）** 测试里有多处「与某个固定历史提交逐字节对照」的写法（`tests/collab-planning.sh` 钉 `44ab8ac`、`4b1f2e2`、`d66d77c`，`tests/collab-herdr.sh` 钉 `57d6e7a` 等）。后续任何一次正当的行为变更都可能让它们失效；本波已有两处因此失败，改成了「当前脚本只撤掉本票改动」作基线。其余几处目前未失败。
- **做法上的教训**：不让工人跑全门之后，写死在冒烟里的通过条数没人更新，合并后全门才暴露。现在任务书要求工人搜冒烟与协作总入口里写死的条数并同步，并单独跑一次账本检查（快门不含「变量后紧跟中文」这类规则）。

### 五角色、Claude 副主控与收工不回票（2026-10-05，main @ 24a8a88）

Rocky 当天定了五角色（主控、副主控、工人、门控、顾问）。据此与第三到第六轮真机演练的发现，又落地九张票：

| 票 | 执行者 | 提交 | 内容 |
|---|---|---|---|
| `roles-polish-code` | Pi sol high | `534f966` | 授权载荷、门控授权的拒绝信息写出期望形状与样例；状态页「交接待办」只列真正未结的；落地在写入者未退出时先拒绝并给出关闭窗口的命令。修第三轮 S1、S2、S4、S5 |
| `roles-walkthrough-docs` | Pi astra high | `0f00d54`、`a4ddc78` | 五角色总表；`templates/roles/常驻流程.md` 从开局到结案的可照抄步骤，测试从安装后的说明书原样取块执行；咨询师改名顾问 |
| `claude-prompt-length` | Pi sol high | `d397fe1` | 发给 Claude Code 的提示词保持单行且不超过 600 字符，超出的原文写进 `qwbuddy/.roles/.prompts/` 下按内容哈希命名的文件，提示词只指路。修第二、三轮 R9（根因见[探测记录](2026-10-05-claude-code-herdr-probe.md)第 12 条） |
| `claude-role-adapter` | Pi astra high | `b2157c9`、`7488ed0`、`d0acdff` | Claude Code 可当规划常驻职责：启动时指定会话号，握手后按会话文件核对实际模型与档位，活动判定按未配对的工具调用；接受安装器写入的 `--add-dir`，回合结束接受 `idle` 与 `done`；拒绝信息写明当前代次与不被允许的参数 |
| `roles-r4-followups` | Pi astra high | `a643238` | 说明书补「工人已派出后来了修订」一支并纳入原样执行的测试；同一规格重新授权并就绪后旧阻塞自动算已满足；自检不再把导出给内嵌解释器读取的配置判成死配置；`pending` 的含义、空门不能单独作证、指令文件回收条件写清 |
| `worker-silent-end` | Pi sol high | `f279162` | 审核工人的提示词要求把结论写成票上的 `done:` 行；工人已证实空闲、会话末条满 `QWB_SILENT_END_MS`（默认 60 秒）仍没回票，值守叫派工者一次（门控派出的叫门控）；工人在干活时不做额外查询，取时间只读会话文件末尾 |
| `pi-aborted-tool-activity` | Pi sol high | `24a8a88` | Pi 被 `esc` 中止的助手消息里的工具调用不再算未完成（真机实测它永远等不到结果，活动判定此前一直报忙） |
| `roles-r5-docs` | Pi sol high | `7e7db04` | 说明书修订：Claude 活动判定的现行口径、主控窗口不写进配置、新票派工前为 `blocked`、落地前怎样确认工人已退出、收到「工人已收工但没有报告」后派工者的三步做法（读窗口；做完没回票可催补写；情况不明在票上写核查结论） |
| `silent-end-escalation` | Pi sol high，主控接手收尾 | `3bfae0f` | 「收工未报告」的门铃发给副主控或门控之后，同一次收工再过 3 倍阈值（默认 3 分钟）仍未报告，值守直接门铃主控一次；主控身份与首次门铃取同一来源（挂钩的 block 模式下也成立）。修 F62 |
| `reauthorize-ready` | Pi sol high | `641a5cb` | 主控对同一规格重新授权后，值守在「最新授权之后未派且累计总上限够」时再次产生就绪并门铃副主控；授权的额度不够再派一次时当场拒绝，拒绝信息写明已用次数与该填的值；说明书写明主控收到升级门铃后的三种做法。修 F63 |

另有主控直接修的两处：`f946faf`（冒烟启动器没有导出进程登记夹具的变量，F60）与 `198d7da`（`tests/collab-herdr.sh` 逐字节对照在提示词改为指路后失效，改为比较所指文件的内容）。

全门：main @ `198d7da` rc=0，863 PASS / 0 FAIL（其前一轮 2 项失败，即上面那处逐字节对照）；main @ `24a8a88` rc=0，865 PASS / 0 FAIL，1143 秒（同时在跑真机验收与三名工人）；main @ `7321f8a`（含后两张票）rc=0，865 PASS / 0 FAIL，1084 秒。main @ `641a5cb`：与第八轮演练同时跑的一次 rc=1、864 PASS / 1 FAIL（`tests/process-entry-cleanup.py`，即 F58 那类受负载影响的计时测试，单独重跑通过）；串行重跑 rc=0，865 PASS / 0 FAIL，1119 秒。

真机验收（Claude Code opus 5.5 medium 主控加 Pi sol high 工人）：第 15 轮 `a4ddc78`、第 16 轮 `198d7da`、第 17 轮 `24a8a88` 均通过（[记录](2026-10-05-e2e-real-claude-pi-r7.md)、[记录](2026-10-05-e2e-real-claude-pi-r8.md)、[记录](2026-10-05-e2e-real-claude-pi-r9.md)）。

常驻职责真机演练：

| 轮 | 候选 | 副主控 | 用时 | 人工介入 | 被拒 | 结果 |
|---|---|---|---|---|---|---|
| 四 | `d397fe1` | Pi astra low | 40 分钟（含 20 分钟全员空等） | 1 | 0 | 含一次派工后修订，走通；审核工人收工不回票。[记录](2026-10-05-real-herdr-roles-drill-r4.md) |
| 五 | `198d7da` | Claude Code opus 5.5 medium | 34 分钟 | 3 | 6 | Claude 副主控首次真机启动暴露两处缺陷（`--add-dir`、`done`），介入后走通。[记录](2026-10-05-real-herdr-roles-drill-r5.md) |
| 六 | `a508d7c` 加 `worker-silent-end` 的脚本改动 | Claude Code opus 5.5 medium | 9 分 35 秒 | 0 | 0 | 零介入走通；另做故障注入，工人不回票收工后约 64 秒副主控被叫醒。[记录](2026-10-05-real-herdr-roles-drill-r6.md) |
| 七 | `7e7db04` 加 `silent-end-escalation` 的改动 | Claude Code opus 5.5 medium | 16 分钟后终止 | 0 | — | 打断式故障注入：工人不回票收工 62 秒后副主控被提醒，再 182 秒后主控被升级叫到并重新授权；此后无人叫副主控续派，全员停 8 分钟。[记录](2026-10-05-real-herdr-roles-drill-r7.md) |
| 八 | `641a5cb` | Claude Code opus 5.5 medium | 17 分 20 秒 | 0 | 0 | 同样的故障注入，链路自己走到结案：副主控被提醒、主控被升级叫到并把总上限写成 2、副主控在原窗口续派、工人交付、门控通过、落地。[记录](2026-10-05-real-herdr-roles-drill-r8.md) |

本节发现与遗留：

- **F60（已修）** 冒烟启动器把进程登记夹具的路径当普通变量用，内层命令读不到。
- **F61（已修，`pi-aborted-tool-activity`）** Pi 被中止的工具调用让活动判定永远报忙。
- **F62（已修，`silent-end-escalation`，第七轮真机验证）** 「收工未报告」的门铃发给副主控或门控之后，派工者若不处理，原先没有任何东西把这件事送到主控；规划与门控也没有能保证叫到主控的正式上报入口。现在值守在首次提醒后约 3 分钟自动叫主控一次。
- **F63（已修，`reauthorize-ready`，第八轮真机验证）** 主控对同一规格重新授权后没有人叫副主控续派：值守只在该规格版本从未派过工时才产生就绪事件；且预算是按规格版本累计的总上限，主控照「再给一次」的直觉写同样的额度，脚本接受后续派仍会被拒。做法：就绪看最新授权之后未派且总上限够；额度不够时授权当场拒绝并写明该填几。
- **做法上的教训**：当天六次任务书前提写错（照模板写没看安装产物、把演练主控的笔记当事实、把不存在的路由写成现有行为），都是工人或真机拦下的，已记入 `tasks/lessons/任务书前提要对着真实产物核对.md`。探测只在窗口位于前台时做，漏掉了 `done` 这个状态。

### 未做与遗留

- **F7、F8** 已迁票读缓存：没有项目在用已迁票，属提前优化，未做。
- **F31、F32** 测试夹具共享：只影响本仓测试，不装进任何项目，未做。
- **F18 余下部分**：值守一侧的解析宽严未统一（见上）。
- **F20 余下部分**：两份「进程已死」实现只对齐、未合并。
- **F21** state 五值与状态行前缀的字面量仍散落多处。
- 第 88 节（订阅回收测试）单节约 29 秒，是 smoke 现在最慢的一节。
- `bin/qwb-wake.sh` 可见值守启动探测里的裸 `sleep 0.5` ×6（约 3 秒真等待）未动。
- 已装项目：`qonnwolfmcp`、`class-video-analysis`、`qonnwolf-sites` 均已在 2026-10-05 升级到 `dec0af6` 并换成五角色工人表；改动未提交，留给各项目自己审。升级后没有在这三个项目里实际派过票。
- 副主控（规划）与门控（门禁）常驻职责真机演练过八次：正常全链零介入走通（第六次），派工后修订走通（第四次），工人收工不回票的整条故障链自己走到结案（第八次）。尚未在真机上验证的：中止的工具调用不再算未完成（两次打断都没有复现那种记录）、门控派出的审核工人不回票时的升级、门控验收阶段来修订、等待到期重提。第八次演练主控记下的四条小问题（门铃摘要乱码、未结义务筛选的归属、状态页分不清挂钩模式、说明书缺 Claude 副主控启动样例）未核实、未开票。

## 返修任务

执行者：Pi（`pi --approve --model zai-coding-cn/glm-5.3-flash --thinking high`，即工人表里的 `pi-glm-flash-high`）。每张票的细则在各自任务书里（`tasks/2026-10-03-audit-*.md`），这里只列共同约束：

- **布局**：每张票一个隔离副本 `.worktrees/<任务id>`（`git worktree add --detach`，不建分支），工人 Tab 开在主控所在的 Herdr workspace `w14Z`，中文标签。没有走 `qwb-run.sh`：它对项目 worktree 一律另开 Space，与 Rocky 2026-10-03「工人在同 Space 独立 Tab、不另建 Space」的要求冲突；手工派发的事实由主控写进各票的 `working:` 行。
- **行为不变是硬线**：除任务书明确要求的修正外，任何可观察输出（stdout/stderr 文案、退出码、账本写入、herdr 调用序列）逐字节不变。
- 工人只在自己的副本里改白名单内文件并提交（detached HEAD），不建分支、不 push、不动主仓根（往主账本追加状态行除外）。
- 主控验收不采信自述：在工人副本的最终提交上独立跑 `bash bin/qwb-test.sh full`，对照基线 PASS 数与末节标题，再把提交 cherry-pick 到 `main`（只在本地，不 push）。
