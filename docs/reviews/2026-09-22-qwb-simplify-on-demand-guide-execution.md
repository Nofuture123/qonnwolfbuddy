# ⑤ 按需主控说明执行报告

时间：2026-09-22（UTC）；执行基线 `8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05`。起始 worktree 干净，无 staged、unstaged 或 untracked 预存改动。候选未提交，未升级真实项目。

## 修改路径

- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/templates/QWBUDDY.md`：保留宿主识别→锁→点名、唯一账本、主控状态权、派发、独立验收、收尾、禁令及三宿主选择入口；把分支细则改为按触发链接。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/templates/roles/主控.md`：标注三个专项触发。五角色清单不变。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/templates/ci-guide.md`：CI 互斥、超时取证、非绿分类、实测基线和共享机器规则。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/templates/host-watch-guide.md`：workspace、信任、三宿主值守接入和恢复；明确 Pi 模板 `.pi/extensions/qwb-watch.ts`、`/reload` 与真加载验证，以及 Codex 真前台命令和 2/124/0 边界。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/templates/worker-launch-guide.md`：`workers.sh` 逐 argv、最高权限与显式旧配置迁移。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/bin/qwb-init.sh`：只安装三个已知专项；缺源、目标符号链接／目录／非普通文件明确失败；临时文件替换避免覆盖常规硬链接的外部内容，不改用户 `config.sh`。
- `/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/tests/on-demand-guide.py`、`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide/tests/smoke.sh`：定向负例并接入现有 smoke，无新门。

## 四场景证据

1. **普通任务完整接手**：保留安装副本 `/private/tmp/qwb-guide-review.yOVYrb/project`，安装日志 `/private/tmp/qwb-guide-review.yOVYrb/install.log`。实际从 `AGENTS.md:6-7` 到 `qwbuddy/QWBUDDY.md:11-15` 宿主、锁、点名与唯一值守入口，再到 `:30-63` 唯一账本及状态权、`:66-78` 派发、`:80-89` 独立验收与场景冻结、`:100-107` worktree 收尾、`:125-133` 禁令。普通任务无需读 CI 专项。该走读验证文档路径和指令完整性，未实际启动 Herdr、创建任务或派工。
2. **专项触发可发现**：安装副本总说明 `:15` 在首次接入／排障指向 `host-watch-guide.md`，`:78` 在启动配置／迁移指向 `worker-launch-guide.md`，`:98` 在 CI 改动／非绿分析指向 `ci-guide.md`。CI 走读从总说明场景与快全门 `:93-98` 到安装副本 `ci-guide.md:7-13`，可找到同机互斥、首次失败后成功计数、非绿四分类、量测与真机清理。宿主专项 `:15-17` 可找到 Claude/Pi/Codex 入口；工人专项 `:7-9` 可找到逐 argv 与迁移。所有链接在保留副本可读；未执行真实 CI 改动、Pi reload 或 Codex 值守。
3. **缺失或错链明确失败**：`python3 tests/on-demand-guide.py` 先红（缺 CI 入口），最终退出 0。测试从安装副本解析 Markdown 目标并验证角色链接；删去已装专项会失败，显式重装恢复；错链失败；目标 symlink、同名目录拒绝；硬链接外部 sentinel 不变；缺源报「缺少专项文档源文件」。测试亦核对用户配置原字节保留。未在真实项目安装或升级。
4. **缩短且不退化**：计数集合为 `templates/QWBUDDY.md`（日常根），以及根+`templates/roles/主控.md`（角色已加载时）；首次接入加 `templates/host-watch-guide.md`，CI 触发加 `templates/ci-guide.md`。用 Python 对 `git show 8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05:<路径>` 与候选文件逐 Unicode 码点计数，排除所有空白，**包含标点、Markdown 和命令字符**：根 10290→6615（−3675）；根+主控角色 11088→7578（−3510）；首次接入候选根+角色+宿主专项 9272；CI 候选根+角色+CI 专项 8195。基线没有独立专项，后两组以基线根+角色 11088 作内容路径参照，不虚构同名基线集合或 token 数。§1 每次选择入口所需命令和 Codex 退出边界留在根，宿主专项仅在首次接入／配置／故障触发。三流程、五角色、`--worker auto` JSON 路由、`workers.sh` 显式迁移、场景冻结和疑点处置仍由候选根与专项覆盖。

## 验证与界限

- `python3 tests/on-demand-guide.py`：退出 0；已先见旧候选 `AssertionError: missing link: ci-guide.md` 的 red。
- `bash -n bin/qwb-init.sh`、`git diff --check`：退出 0。
- `bash bin/qwb-lint.sh --project .`：退出 0，`LINT PASS`；存在历史任务书占位行等警告。
- `bash bin/qwb-test.sh fast`：退出 0，但本仓 `qwb.config.sh` 的 `QWB_GATE_FAST` 为空，此命令未实际执行测试，不以它宣称绿门。
- `bash tests/smoke.sh > /tmp/qwb-simplify-smoke-final.log 2>&1`：最终候选退出 0，`SMOKE PASS`，含第 78 节新增负例；日志保留。未运行 `qwb-test.sh full`，未提交、合并或推送。
- 宿主假件和文档走读不证明真实 Claude/Pi/Codex/Herdr 的安装、前台值守或真实 CI 性能；这些由主控／审核者在独立验收时判定。

审核者从保留副本的 `AGENTS.md` 开始独立走读；候选源码仍在上述 worktree，主账本位于 `/Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-22-qwb-simplify-on-demand-guide.md`。

## 最终未提交差异与新增文件哈希

`git diff --check` 退出 0；`git diff --name-status` 为四个 tracked 修改：`bin/qwb-init.sh`、`templates/QWBUDDY.md`、`templates/roles/主控.md`、`tests/smoke.sh`。`git diff --stat`：4 files changed, 38 insertions(+), 38 deletions(-)。另有下列四个未跟踪新增源码文件（SHA-256）：

- `templates/ci-guide.md` `edbc5c11f4bbaa7083c24adb63b6359bda05d9cf24195fb6a574174898716f3a`
- `templates/host-watch-guide.md` `194278c0112eee96c04704c7f2a5f72a420bc65aa11eb0558af9ec5681d7693f`
- `templates/worker-launch-guide.md` `b945a8282b20f5bb8d6cfba75ed691836453c6e699496db1ebba63ede41570cf`
- `tests/on-demand-guide.py` `7c6287fb816af92d9108e6543efa26e156027ce389b4829803b47fec7bc65abd`

## 主控复核更正

2026-09-22T19:10:52.060684+00:00：上文 fast 配置为空的说明错误。当前候选 qwb.config.sh 的 QWB_GATE_FAST 明确执行逐文件 bash -n 与 shellcheck，且候选没有优先覆盖的 qwbuddy/config.sh。本轮主控实际重跑 bash bin/qwb-test.sh fast --project <候选绝对路径>，rc=0，1.841512250s，候选前后不变；证据 /tmp/qwb-simplify-05-fast.json 与 .log。旧执行回合不据此补造，以上为本轮新验证。
