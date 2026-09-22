# qwb-simplify-worker-config 执行证据

- 时间：2026-09-22T14:21:23.530685+00:00
- 基线 / 当前 HEAD：`6bc424c7a19f01d8ce604423f0d8674675fe8ba4`；执行前工作区干净，保持未提交。
- 候选：仅本票白名单中的源码、测试和文档；主账本只追加状态行。
- 已跟踪候选 diff SHA-256（`git diff --binary 6bc424c7a19f01d8ce604423f0d8674675fe8ba4 -- README.md README.zh.md bin/qwb-init.sh bin/qwb-run.sh templates/QWBUDDY.md templates/config.sh tests/runtime-readiness.sh tests/smoke.sh`）：`09f00bd1f0ad07e79504b2e1ec4e9db72f861caca4e9bd044468a2b95eda4a4d`。
- 新文件 `templates/workers.sh` SHA-256：`5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b`。
- 新文件 `tests/worker-config.py` SHA-256：`42a9b430d17da0f03a5d3f05acc957d2f106f8e00aaa4e81ff41b1f3e92874df`。

## 命令与退出码

- `python3 tests/worker-config.py`：rc=0；PASS ambiguous migration multiline refusal。
- `bash bin/qwb-test.sh fast`：rc=0；无输出。
- `bash -n tests/smoke.sh`：rc=0；无输出。
- `bash -n tests/runtime-readiness.sh`：rc=0；无输出。
- `shellcheck bin/qwb-run.sh bin/qwb-init.sh`：rc=0；无输出。
- `git diff --check`：rc=0；无输出。
- 接入 smoke 第 77 节后重跑 `python3 tests/worker-config.py`、`bash bin/qwb-test.sh fast`、`bash -n tests/smoke.sh`、`git diff --check`：各 rc=0。

## 四场景的实际边界

- 正常 argv：`python3 tests/worker-config.py` 的公开 qwb-run 假 Herdr / 假 pane-run 执行器捕获 Herdr argv 和 pane-run 实际进程 argv；含空格、空串、字面 `$(touch ...)` 均逐项一致，未生成命令替换标记。
- 配置歧义：同一脚本验证未知工人、重复声明、headless、旧键与新 workers.sh 共存；拒绝后假 Herdr 零调用、假执行器零调用、无 worktree/锁/dispatch。
- 显式迁移：隔离 HOME 与临时项目，普通 init 保留旧配置；迁移保留原配置备份和 0600 权限，二次运行字节幂等；迁移后 pi 与 cmd 分别经公开 qwb-run 捕获 `--approve` / `--trust` 实际 argv。
- 无法可靠迁移：未知工人、glob、显式空 launch、pane-run 与 ARGS 两处参数、同一行附命令和真正跨行赋值均拒绝，原 config、backup、workers.sh 状态按断言保持。

## 未覆盖

- 未运行 `bash bin/qwb-test.sh full`；由主控在整合候选执行。
- 假 Herdr 和假执行器不证明真实 Herdr、Claude/Pi/Codex/Devin/OMP 组合可启动。
- 已改的 smoke 与 runtime-readiness 夹具仅完成 `bash -n`；未运行整个 smoke / runtime-readiness，等待主控 full 门验证。
- 新增定向测试已由 `tests/smoke.sh` 第 77 节直接调用并沿用 `ok` / `bad`；母仓 `qwb.config.sh` 的 full 门执行 smoke，因此主控 full 将回归此测试。该接线只完成语法及命令路径核对，未执行整个 smoke/full。

## 工作区状态（写报告前）

```
M README.md
 M README.zh.md
 M bin/qwb-init.sh
 M bin/qwb-run.sh
 M templates/QWBUDDY.md
 M templates/config.sh
 M tests/runtime-readiness.sh
 M tests/smoke.sh
?? templates/workers.sh
?? tests/worker-config.py
```

## r2 定向返修与最终候选（2026-09-22T14:39:00.307728+00:00）

- 基线与当前 HEAD：`6bc424c7a19f01d8ce604423f0d8674675fe8ba4`；保持未提交。r1 审核指出的 pane-run argv、旧迁移 shell 语义、安装夹具与默认唯一性断言已在原 10 文件白名单内返修。
- 8 个已跟踪文件的最终 binary diff SHA-256（沿本报告开头相同路径顺序）：`4d160b813ce1c3e92394e8e7383c411a315da7502c37766c740b27be093144e0`。
- 新文件 `templates/workers.sh` SHA-256：`5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b`。
- 新文件 `tests/worker-config.py` SHA-256：`1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954`。
- `python3 tests/worker-config.py`：rc=0，18 条 PASS；公开 qwb-run 假 Herdr / 假 pane-run 执行器实际 argv 覆盖空格、空串、字面 `$()`、`~`、`{a,b}`、`#` 和内嵌单引号；旧 pane-run 的 brace/comment/tilde 先在假执行器演示原 shell 语义，再验证显式迁移拒绝且原 config、backup、workers 状态不变。旧 Herdr 参数迁移后同样以公开 argv 验证引用保真。
- 同一定向测试：已有 `QWB_WORKERS=pi` 无 workers 的普通 init 保留 config 字节、未执行 sentinel、明确报告手动配置与当前不可派发；补齐完整 workers 后再次普通 init 不覆写；隔离 Git 项目经公开 qwb-run 验证创建 worktree、残留警告与 --worktree 复用。
- `bash bin/qwb-test.sh fast`：rc=0，无输出。`bash -n tests/smoke.sh`、`bash -n tests/runtime-readiness.sh`、`bash -n templates/workers.sh`、`shellcheck bin/qwb-run.sh bin/qwb-init.sh`、`git diff --check`：均 rc=0，无输出。
- GITP 夹具现在补装 workers.sh；原路径断言增加目录存在与 dir 非空条件；pane-run 旧裸命令文本预期改为逐项单引号渲染，同时保留 pane 寻址、顺序与参数完整性断言；默认工人声明改为逐名逐次计数。
- 首轮主控 full 证据保留：`/tmp/qwb-simplify-03-full.log` SHA-256=`2c2b8cc5780548b1291973d249dd7697384a42607c704cee77e879e9cedf9694`，rc=1、114.096 秒、5 项 GITP FAIL，对应 r1 候选。r2 候选未跑 full，待主控同版本重验；真实 Herdr 与实际 Agent CLI 组合未实测。

## r3 假 Herdr 启动文本夹具返修（2026-09-22T14:44:55.748214+00:00）

- 基线 / HEAD：`6bc424c7a19f01d8ce604423f0d8674675fe8ba4`，候选仍为原 8 个已跟踪文件和 2 个新文件，保持未提交。本轮源码只改 `tests/runtime-readiness.sh` 的假 Herdr `pane run` 启动文本两处比较，识别 `'mock-agent'`；state、scenarios-fp、dispatch 前置检查与 not-sent、tab close 断言保留。
- r2 独立定向原结果：`bash tests/runtime-readiness.sh` rc=1，17 PASS / 1 FAIL；r2 主控 full rc=1、124.392 秒收据及原报告保留。
- r3 执行 `bash tests/runtime-readiness.sh`：rc=0，18 PASS，末行 `RUNTIME READINESS PASS`。`bash bin/qwb-test.sh fast`：rc=0，无输出。`git diff --check`：rc=0，无输出。未运行 full。
- 最终 8 文件 binary diff SHA-256（同本报告开头路径顺序）：`eb74a9a225f476cef6d09a830b0833b2dadbb72e761f3151ba90c262a9f44f5b`。新文件 `templates/workers.sh` SHA-256：`5b530980d259c9e213e6dde4c3887328238e2ef8e4a7c73245a2ea4e4efbea9b`；`tests/worker-config.py` SHA-256：`1396f473fd69376aef9eaf33723b1bc2dab8fb8b62261f2186bf8096bba67954`（两者与 r2 一致）。
