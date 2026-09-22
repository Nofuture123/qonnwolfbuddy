# 生产运行时三项返修

state: done

## 0. 目标与范围

修复 docs/reviews/2026-09-22-production-runtime.md 在 1c500b38c014be9e55aa33fede2735ebaaf17d16 上复现的三个审点。执行 GPT Sol medium，独立审核 GPT Sol high（用户今日指定，覆盖模板跨家族默认）。不得创建 pane/tab 或递归派发。

源码白名单：bin/qwb-lock.sh、bin/qwb-run.sh、bin/qwb-lib.sh、bin/qwb-lint.sh、templates/pi-extensions/qwb-watch.ts。
测试白名单：tests/smoke.sh、tests/pi-ext.test.mjs、tests/runtime-readiness.sh（如需要独立定向入口）、tests/fixtures/herdr/ 内仅本票必需的夹具。
文档白名单：docs/DECISIONS.md、templates/config.sh（仅新增必要依赖/明确契约时）。不要改 README、历史任务和主工作区源码。

1. 主控锁：普通获得、死锁回收及释放的互斥必须正确，防止已判死的竞争者删除另一方刚取得的活锁。采用最小可靠的跨 macOS/Linux 方案；若增加运行依赖，必须检查可用性并明确报错，不得静默绕过锁。死锁和无法判活原有 fail-closed 语义保留。不以新增无法恢复的永久锁替换旧问题。
2. Pi：turn_end 的 --block --max-ms 1 探测返回 2 时，交付摘要并立即恢复常规值守，与普通 exit 2 一致，不增加故障计数、不进入退避。保持 0/124、shutdown 与单飞原约定。增加真实行为断言，不只匹配源代码。
3. 派发：任何模式的提示词投递失败都必须明确非零退出，并回滚仅属于本次的 dispatch 及新创建资源，保护历史和并发追加行；不能让失败看起来像成功派发。复用前核对实际 worker、物理 cwd、workspace 和任务归属（对第一次同名但无本票历史的工人要明确拒绝，不能靠名字猜）。错误工人/异目录/异 workspace/未知查询应在提示词投递前拒绝；不得关闭非本次创建的已有窗口。兼容已有 --pane 与 pane-run 路径的明确授权，先读现有契约，不借机砍功能。

## 1. 验收场景

### 失败路径：两个竞争者回收同一死锁
Given 存在已死 owner，A 已判死但未完成回收，B 竞争获取
When 按可控交错放行两个调用
Then 最多一个有效持锁者；另一方不得删除新活锁并报告获锁。不得靠概率循环、sleep/retry 掩盖竞态。

### 正常路径：锁生命周期
Given 无锁、仍存活的锁、已死的锁及无法查询的锁
When 分别 acquire/release
Then 无锁可获、活锁拒绝、死锁可安全回收、未知 fail-closed；异常终止不会遗留无法自行恢复的互斥门。

### 正常路径：Pi 探测发现新进展
Given 主值守 exit 0 后进入 turn_end 探测
When probe exit 2 返回非空摘要
Then 恰好交付一条摘要，故障数不增，立即启动一个常规 block，且普通 0/124/shutdown 行为不回退。

### 失败路径：派发投递失败
Given 新建工人或有完整本票历史且身份匹配的复用工人
When 提示词投递 API 返回失败
Then 命令非零，无本次成功 dispatch 残留，无本次创建的孤儿 tab；历史/并发追加行保留，已有复用窗口保留。

### 失败路径：复用身份不符
Given 同名 agent 但 worker/cwd/workspace/本票归属任一不符或查询未知
When 尝试重派
Then 投递前拒绝，账本与既有工人均不被破坏。

## 2. 验证与交付

先用定向负例复现，再修复。执行者跑快门与本票定向测试，不跑全门；新增测试必须纳入现有全门（可由 smoke 调用定向脚本），不得放在 exit 之后。对 Pi 用例数量变化同步现有 smoke 的精确计数断言，避免假红或假绿。

每条报告命令、退出码、首次红和修复后结果。临时资源自己清理。仅提交白名单文件到本票 worktree 分支，不 push/merge、不清 worktree。主账本只追加 working/done/blocked，不改 state。主控在独立审核与全门通过后合入。
wake: 2026-09-22T06:48:22Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa

scenarios-fp: 999802e2d02b7ca521a2778ba3cfa5097c8c1d17
working: 2026-09-22T06:49:14.194251+00:00 主控通过现有 Herdr 执行会话交接，已观察 working。执行 GPT Sol medium；实现目录 .worktrees/production-runtime-fixes；现有 CLI 仍起于 production-docs，要求每条工具显式 workdir，两个 worktree 均暂留。此为主控人工调度，未把它记作 qwb-run 自动派发成功。
wake: 2026-09-22T06:50:23Z state=running fp=865061aa5a881ef5981c8032b85c8c708f1efb4f
working: 主控定向核对发现新增 not-sent: 记录若紧接最后的验收场景块，会被现有 scenario_block 算入场景：原 sha1=9d3c091285ea132f9b9a4f2dd738f1267f91cb12，失败记账后=8e967eb697228b6a31904303c4da23d8c124c106（Given/When/Then 未变）。补 bin/qwb-lint.sh 到源码白名单，仅同步新运行时记录前缀的场景边界；验收场景正文未改，不改冻结值。要求加场景为末节的失败后重派/ lint 回归，不放宽断言。
wake: 2026-09-22T07:12:30Z state=running fp=9f293a086c674fe2022a39e8282ff53845bf56a8
done: 2026-09-22T07:15:44Z executor=codex commit=d9ed8052ccbcfbc1e286ade07853026a3ae5d470 base=1c500b38c014be9e55aa33fede2735ebaaf17d16; whitelist only: bin/qwb-lock.sh, bin/qwb-run.sh, bin/qwb-lint.sh, templates/pi-extensions/qwb-watch.ts, tests/smoke.sh, tests/pi-ext.test.mjs, tests/runtime-readiness.sh, docs/DECISIONS.md. First red: bash tests/runtime-readiness.sh rc=1, fixed interleaving A_rc=0 B_rc=0; new prompt failure rc=9 left dispatch and tab, same-name without history and mismatched worker/cwd/workspace delivered; node tests/pi-ext.test.mjs rc=1 probe exit=2 messages=[]; last-section not-sent regression before boundary fix: lint rc=1 scenario fingerprint mismatch and retry rc=1, original scenarios-fp unchanged. Final: bash bin/qwb-test.sh fast rc=0; bash tests/runtime-readiness.sh rc=0, 17 PASS; node tests/pi-ext.test.mjs rc=0, 10 passed; bash bin/qwb-lint.sh rc=0 LINT PASS; git diff --check rc=0. No full gate, real Herdr/E2E, push, merge or worktree cleanup. Source state remains running for controller audit.
wake: 2026-09-22T07:16:31Z state=running fp=bc01abb480d598699f06370de3fdd8aef8f7200d
working: 2026-09-22T07:26:48.750984+00:00 独立复审 d9ed805 为 AMEND，仅剩 Perl flock 父进程被 SIGKILL 后内层回收仍存活的真实交错；见 docs/reviews/2026-09-22-production-runtime-r2.md。未人为注入 QWB_LOCK_GUARDED。Pi probe 与派发 diff 的定向复核通过（runtime 17 PASS、pi 10 passed）；不算全门。下一次返修仅修同一内核锁在完整临界区存续并补受控父死测试，不重改已通过部分。state 保持 running，候选不合入。
wake: 2026-09-22T07:28:35Z state=running fp=6b9022c62fb0c6972f003940af253bebb0ba0fb0
done: 2026-09-22T07:36:41Z executor=codex second-amend commit=856f87049bab37eb9e42dcf3fe491373003ca864 base=d9ed8052ccbcfbc1e286ade07853026a3ae5d470; only bin/qwb-lock.sh, tests/runtime-readiness.sh, tests/smoke.sh, docs/DECISIONS.md. Directed red: bash tests/runtime-readiness.sh rc=1, B entered before A resumed (B rc=0), 2 FAIL; raw /tmp/qwb-production-runtime-r3-red.log. Fix: locked FD explicitly inherited by inner Bash for full recovery/release critical section. Final: bash bin/qwb-test.sh fast rc=0; bash tests/runtime-readiness.sh rc=0, 18 PASS; bash -n and git diff --check rc=0. Raw logs /tmp/qwb-production-runtime-r3-fast.log and /tmp/qwb-production-runtime-r3-runtime.log. Test temp directory removed by trap; ps found no matching residual process; worktree clean. No full gate, push, merge, worktree cleanup, or Pi/run/lint changes. state remains running for controller audit.
wake: 2026-09-22T07:38:39Z state=running fp=6b1c1acd2b4ae50ea777882f0bcf4c32270fe19d
working: 2026-09-22T07:49:05.448441+00:00 主控收回候选 856f87049bab37eb9e42dcf3fe491373003ca864 的最后一项独立复核 PASS（docs/reviews/2026-09-22-production-runtime-r3.md）；与前轮已通过部分共同覆盖本票。state=done，等待最终整合候选全门和真机验收，暂不标 verified。
