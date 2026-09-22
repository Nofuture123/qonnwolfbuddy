# 票③正式独立审核 r1

结论：**AMEND**。审核者为 Herdr pane `wF2:pG`（Sol high）；只审核冻结的 8 个 tracked 文件与 2 个新文件，未递归派发、未改候选源码或提交。

## 冻结对象与证据

- 唯一需求：`tasks/2026-09-22-qwb-simplify-worker-config.md`。候选 worktree：`/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-simplify-worker-config`，HEAD `6bc424c7a19f01d8ce604423f0d8674675fe8ba4`。按交接的 8 文件顺序计算 tracked diff SHA-256=`09f00bd1f0ad07e79504b2e1ec4e9db72f861caca4e9bd044468a2b95eda4a4d`；新 `templates/workers.sh`=`5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b`，新 `tests/worker-config.py`=`42a9b430d17da0f03a5d3f05acc957d2f106f8e00aaa4e81ff41b1f3e92874df`。审核末重算仍一致。执行报告在主仓 `docs/reviews/2026-09-22-qwb-simplify-worker-config-execution.md`，SHA-256=`c0a713b30d8751ab2ef59732234c1c697009ebf0eb6d1b8e15c357a2cce76bfb`。
- 独立运行 `python3 tests/worker-config.py`，rc=0，13 条 PASS；`git diff --check`，rc=0。以下两个反例均在 `tempfile.TemporaryDirectory` 隔离项目、假 Herdr 与假执行器中运行，无真实派发。主控的 `bash bin/qwb-test.sh full` 收据是 `/tmp/qwb-simplify-03-full.json` 与 `.log`：同一冻结 SHA、前后未变，rc=1、114.096 秒、5 项 GITP 相关 FAIL；这是主控运行，本审核未重跑 full。执行者报告中的 fast、shellcheck 等也未由本审核重跑。

## Standards

本仓未发现适用于本票的项目 `AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING` 或独立编码规范；未见 Fowler smell 阻断项。第 3 审点的回归断言有一处标准问题：`tests/smoke.sh:2897-2906` 用 `sort -u | wc -l == 5` 宣称唯一；五个有效名字之外再重复声明其中一个，断言仍通过。这削弱任务书 §2 要求保留的负例。应改成逐名逐次计数，并让重复声明使该测试变红。

## Spec：三个审点

1. **新 pane-run 的 argv 不保真。** `bin/qwb-run.sh:198-203` 用 `printf %q` 拼接交给 `herdr pane run` 的 shell 命令。隔离项目 `workers.sh` 声明 `qwb_worker cmd pane-run fake-exec '~' '{a,b}' '#'`，公开 `qwb-run.sh --worker cmd --here` rc=0，但假执行器收到 `[临时 HOME 路径,"{a,b}","#"]`，不是配置的 `["~","{a,b}","#"]`。`tests/worker-config.py:96-115` 覆盖空串、空格、`$(...)`，漏掉该反例。影响：用户明确给出的字面特殊字符被静默改值，违背任务书 §1 第一场景。修复：为 pane-run 每个实参生成可证明保真的 shell 单引号引用（正确处理内嵌单引号），并在公开入口测试字面 `~` 的实际进程 argv。

2. **显式迁移接受会改变旧 pane-run 行为的 shell 语义。** `bin/qwb-init.sh:37-45,99-109` 只排除部分 shell 字符，允许 `{a,b}` 与空白后的 `#`，又按空白拆成字面参数。隔离旧配置 `QWB_WORKER_LAUNCH="cmd=pane-run:fake-exec {a,b} # trailing"`：旧 pane shell 的实际 argv 为 `["a","b"]`；显式迁移 rc=0 并生成含字面 `{a,b}`、`#`、`trailing` 的声明；迁移后的公开 `qwb-run.sh` rc=0，实际 argv 为 `["{a,b}","#","trailing"]`。原配置虽有备份，迁移却宣称完成并改变有效启动行为，违背任务书 §1 第三、四场景。字面 `~` 的迁移前后都可能展开，不能用其结果证明新格式保真。修复：对旧 pane-run 字符串只接受能证明 shell 解释后 argv 与生成声明一致的子集；对花括号展开、注释及其他无法证明的 shell 语义明确拒绝，保留原件与备份状态，并加迁移拒绝反例。

3. **安装/回归夹具不完整，定制工人表升级也不能派发。** `tests/smoke.sh:381-384` 的 GITP 临时项目只复制 `config.sh`，`tests/smoke.sh:466` 随后从该项目派发；新增的 `bin/qwb-run.sh:116-117` 要求同目录 `workers.sh`。主控 full 日志第 148-149、339-346 行显示由此产生 5 项 FAIL（残留警告、建副本、默认派发两项、`--worktree` 派发），全门不通过。独立升级反例：已有 `QWB_WORKERS="pi"` 且没有旧长串键的定制 `config.sh` 被普通 `qwb-init.sh` 保留，但 `bin/qwb-init.sh:142-147` 装入五工人默认 `workers.sh`；init rc=0，公开 `qwb-run --worker pi` rc=1，报 `codex` 不在 `QWB_WORKERS`。影响：本票验收门失败，既有定制配置虽字节保留却失去可派发能力。修复：补齐 GITP 夹具的 `workers.sh` 并重跑同候选 full；普通升级遇到定制工人表时安装匹配的启动定义或明确要求人工配置且在安装时报告不可派发，不把成功安装当成可用；补定制升级反例。

未实测真实 Herdr/真实 Claude、Pi、Codex、Devin、OMP 启动。上述问题均指向本轮候选或本轮修改的测试；不重开①②历史结论。

本轮计数：Standards 1 项（第 3 审点的断言）；Spec 3 项，最严重的是第 1、2 审点的 argv 与迁移行为改变。

**REVIEW_QWB_SIMPLIFY_WORKER_CONFIG_R1 AMEND**
