# 生产生命周期 r1 返修独立复审

**结论：PASS。** 固定基线 `aa1c710e7148c952a522740691038be0c809903b`，候选 `fc0c29ccad205eda91404ef7ffaa95a14c7ab3d8`（直接父提交即基线）。只审增量中的 `bin/qwb-wake.sh`、`templates/pi-extensions/qwb-watch.ts`、`tests/pi-ext.test.mjs`、`tests/lifecycle-readiness.sh`、`tests/smoke.sh`、`docs/DECISIONS.md`，以及运行定向测试所需的直接依赖。候选与基线均由 `git archive` 冻结到 `/tmp`；共享工作树的未提交 `tasks` 与 `docs/plans` 未作为候选源码。逐项对照 [r1 审核](2026-09-22-production-lifecycle-r1.md)的三项 AMEND，本轮新增内容未发现新的可行动问题。

## 1. Pi 旧 child close 前单飞、旧回调隔离：PASS

`templates/pi-extensions/qwb-watch.ts:82-96,112-136` 在 `kill()` 后保留 `child` 与 `retiring`，到 `close` 才释放位置、按当前锁主决定重启；`settled` 阻止重复 close 再清新登记。`tests/pi-ext.test.mjs:331-353` 覆盖失锁后立刻重获、仅 exit/stdout end 尚不能重启、stderr 排空并 close 后恰起第二个、旧 close 重复回调不清新登记。独立隔离交错探针：基线在旧 close 前 `spawns=2`，候选为 `1`，候选 close 后为 `2`，重复旧回调后新 PID 登记保持（`/tmp/qwb-lifecycle-r2-race-base.log`、`-race-candidate.log`，两命令 `rc=0`）。候选 `node tests/pi-ext.test.mjs` 为 15/15、`rc=0`（`/tmp/qwb-lifecycle-r2-pi.log`）。

## 2. 跨 workspace 缺登记关键查询失败：PASS

`bin/qwb-wake.sh:354-364` 在补登记前要求 `pane_info` 成功、其 workspace 等于已解析的 `tabws`，失败即返回且不写 `.watch`。`tests/lifecycle-readiness.sh:245-251` 注入 B 值守的 `pane get` 失败，断言非零、无登记，并验证查询恢复后登记 B。候选生命周期定向 `rc=0`；将冻结基线 `qwb-wake.sh` 注入同一候选测试，恰在“缺登记时 pane get 失败仍误认领”断言处 `rc=1`（`/tmp/qwb-lifecycle-r2-cross-red.log`）。这确认了新增断言能检出 r1 原缺陷；测试使用假 Herdr，未创建真实窗口。

## 3. 宿主 SIGKILL 孤儿清自身登记、保护新 owner：PASS

扩展 `templates/pi-extensions/qwb-watch.ts:101-107,283-300,303-322` 为每个会话生成实例 ID，传给子进程，写/清登记时同时比对 PID 与实例。`bin/qwb-wake.sh:622-647` 在 PPID 已改变时持同一项目目录 flock，只条件删除自己的登记，再退出；`block_round` 写 `wake:` 前仍复核宿主（`:658-670`）。`tests/lifecycle-readiness.sh:70-135` 用真实 Node 进程加载扩展、派生真实 Bash 子进程，SIGKILL 后分别断言旧登记消失、替换的新 owner 登记保持、子进程退出且不新增 `wake:`。候选测试 `rc=0`；把测试源切回冻结基线时，在“宿主 SIGKILL 后仍残留旧 Pi 登记”断言处 `rc=1`（`/tmp/qwb-lifecycle-r2-orphan-red.log`）。这是 Node 扩展宿主模拟，不是 Pi 应用的真实 `/reload` 验证。

## 命令、覆盖与边界

- 候选归档：`node tests/pi-ext.test.mjs` → `rc=0`，15/15；`bash tests/lifecycle-readiness.sh` → `rc=0`，5 个 PASS（`/tmp/qwb-lifecycle-r2-pi.log`、`-readiness.log`）。其中执行器假件仍检查实际测试只执行一次、失败不换执行器。
- `bash -n bin/qwb-wake.sh tests/lifecycle-readiness.sh tests/smoke.sh` 与 `shellcheck bin/qwb-wake.sh tests/lifecycle-readiness.sh` → `rc=0`（`/tmp/qwb-lifecycle-r2-static.log`）；固定增量 `git diff --check` → `rc=0`。`tests/smoke.sh:3453-3456` 已把 Pi 期望改为 15 项；runtime、boundary、lifecycle 三段仍位于最终 `exit`（`:3533`）前。
- 未跑 full/完整 smoke、真实 Pi `/reload`、真实 Herdr 跨 workspace 或跨平台宿主；本结论只覆盖冻结增量及上述本机定向证据。未创建窗口、派发、联网或改动候选源码。

PASS
