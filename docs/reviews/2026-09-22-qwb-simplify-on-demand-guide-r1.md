# ⑤ 按需主控说明正式独立审核 r1

审核身份：⑤正式独立审核者，Sol high；非主控。结论仅针对冻结的未提交候选。

## 冻结对象

- 候选目录：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-on-demand-guide`
- `HEAD`：`8df36a6e5b1b1d46ee5ffbfc4160e474dd977c05`
- 4 个 tracked 文件相对 `HEAD` 的 `git diff --binary` SHA-256：`d77841129709b0a863d4bb8f042de91dbf77c1e4c1511f0daf16de559fa4f3e3`
- 4 个新文件 SHA-256：
  - `templates/ci-guide.md`：`edbc5c11f4bbaa7083c24adb63b6359bda05d9cf24195fb6a574174898716f3a`
  - `templates/host-watch-guide.md`：`194278c0112eee96c04704c7f2a5f72a420bc65aa11eb0558af9ec5681d7693f`
  - `templates/worker-launch-guide.md`：`b945a8282b20f5bb8d6cfba75ed691836453c6e699496db1ebba63ede41570cf`
  - `tests/on-demand-guide.py`：`7c6287fb816af92d9108e6543efa26e156027ce389b4829803b47fec7bc65abd`

审核末尾复算以上身份全部一致；未用 `HEAD^..HEAD` 代替未提交候选。

## 审点 1：普通接手、责任与既有成果

未发现阻断问题。

- 作为新接收者从隔离安装副本 `/private/tmp/qwb-guide-review.yOVYrb/project/AGENTS.md` 进入，实际走读路径为 `AGENTS.md` → `qwbuddy/QWBUDDY.md` → `qwbuddy/roles/主控.md`。总说明仍在 `templates/QWBUDDY.md:11-15` 保留宿主识别、取锁、点名、唯一值守入口；`:30-63` 保留唯一账本、状态行及写权限；`:65-98` 保留派发、独立验收、疑点处置、场景冻结和测试分级；`:100-107` 保留安全收尾；`:125-139` 保留硬禁令与恢复边界。
- Gardening 没有退化：`templates/QWBUDDY.md:111-113` 保留五角色和按需维护入口，`templates/roles/主控.md:15` 保留维护范围、预算、冲突、验收及暂缓记账要求。
- ①至④已经位于冻结 `HEAD`；本候选没有修改其运行时文件。文档仍保留①先识别宿主再取锁及 Codex exit 0 三项复核，②账本末行、疑点和场景协议，③ `workers.sh` 逐 argv 与显式迁移，④ `qwb-dispatch.sh --json` 及 `off/error/ambiguous` 回退约束。这里只核对本轮未造成退化，不重新审查①至④。
- 独立重算“排除所有 Unicode 空白、包含标点/Markdown/命令字符”的字数：根说明 `10290→6615`（`-3675`）；根+主控角色 `11088→7578`（`-3510`）；首次接入路径候选为 `9272`；CI 触发路径候选为 `8195`。与执行报告一致，没有换算或宣称 token 节省。

## 审点 2：专项入口与迁移约束

未发现阻断问题。

- 实际从安装副本 `qwbuddy/QWBUDDY.md:15` 进入 `qwbuddy/host-watch-guide.md`，从 `:78` 进入 `qwbuddy/worker-launch-guide.md`，从 `:98` 进入 `qwbuddy/ci-guide.md`；`qwbuddy/roles/主控.md:9` 也提供相同三入口。五份安装文档与候选模板逐字节 `cmp` 一致。
- 宿主专项保留 workspace 解析、首次信任边界、Claude Stop hook、Pi 的母本模板与安装目标、`/reload` 加真实加载核验、Codex 真前台 `--block --max-ms 180000` 及 2/124/0 处理，见 `templates/host-watch-guide.md:3-19`。
- CI 专项保留同机互斥、超时仅取证、首次失败后成功计数、非绿四分类、先量后改和共享机器清理，见 `templates/ci-guide.md:3-13`。
- 工人专项保留 `workers.sh` 单一声明、逐 Bash argv、交互式最高权限、pane-run 行为、headless 禁令和旧 `QWB_WORKER_LAUNCH` / `QWB_WORKER_ARGS` 的显式保守迁移；迁移失败保留原配置，见 `templates/worker-launch-guide.md:3-9`。

## 审点 3：安全安装、失效负例与配置保留

未发现阻断问题。

- `bin/qwb-init.sh:141-151` 在写入前固定三文件清单并拒绝缺源、`qwbuddy` 符号链接、目标符号链接和非普通文件；`:153-163` 使用同目录临时文件后 `mv`，常规硬链接目标不会把外部 inode 内容覆盖；既有 `config.sh` 仍由 `:167-189` 保留。
- 独立运行 `python3 tests/on-demand-guide.py`，退出 0。该测试真实构造并命中：错链、已装专项缺失、升级恢复、目标 symlink、同名目录、常规硬链接 sentinel、缺源，以及用户 `config.sh` 原字节保留，见 `tests/on-demand-guide.py:30-85`。`bash -n bin/qwb-init.sh` 与 `git diff --check` 也均退出 0。
- 执行报告原先“`QWB_GATE_FAST` 为空、未执行测试”是报告错误，不是候选问题。实际 `qwb.config.sh:2` 声明逐文件 `bash -n` 加 `shellcheck`；执行报告 `:42-44` 已追加更正。只读核对 `/tmp/qwb-simplify-05-fast.json`：`rc=0`、`1.841512250015512s`、`unchanged=true`，身份与本审核冻结对象一致。
- 本审核未跑 full。主控随后生成的 `/tmp/qwb-simplify-05-full.json` 显示同一冻结对象 `rc=0`、`171.1210674579488s`、`unchanged=true`，日志末尾为 `SMOKE PASS`、`REVIEW-IDENTITY PASS`、`LINT PASS`；这是主控收据，不冒充本审核执行。

## 未覆盖

- 未运行真实 Claude Stop、Pi `/reload`、Codex 前台 180000ms 值守或真实 Herdr 派发。
- 未升级现有项目，未提交、合并、推送或清理 worktree。
- 安全负例覆盖确定性文件类型与缺失路径，不声称覆盖并发目录替换等竞态攻击。

## 结论

三个审点均无 Standards 或 Spec 阻断项。冻结候选满足本票四个验收场景，执行报告的 fast 旧说法已被同文件的真实收据更正。

**PASS**
