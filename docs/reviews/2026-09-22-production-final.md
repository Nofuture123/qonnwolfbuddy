# 生产整合与真实闭环验收

## 固定对象与审核

- 整合候选 `6e9b0f2b0b307357445ecaf24b8c947d424dd257`，生命周期源码与独立复审 PASS 的 `fc0c29ccad205eda91404ef7ffaa95a14c7ab3d8` 相同；整合只加入主线已有账本与报告。
- runtime `856f870`、boundaries `a8eec48`、docs `556d6aa` 与 lifecycle `fc0c29c` 的独立复审报告均在本目录。
- 工具：Herdr 0.9.1、Codex CLI 0.155.1、Node v26.8.1。执行 GPT Sol medium，独立审核 GPT Sol high，沿用用户当日授权；未创建新 pane/tab。

## 整合门：首次结果不得被覆盖

- 候选工作目录 `.worktrees/production-lifecycle-fixes`，运行前干净。
- `bash bin/qwb-test.sh fast --project "$PWD"`：rc=0，1.508 秒。
- `bash bin/qwb-test.sh full --project "$PWD"`：rc=1，103.011 秒。smoke 12 项失败，集中在第 42、45、47、51 节；后续 review-identity 与 lint 因前项失败未执行。
- 原始日志 `/tmp/qwb-production-final-fast.log`、`/tmp/qwb-production-final-full.log`；机器计时 `/tmp/qwb-production-final-gates.json`。不是 timeout，也没有原样重跑洗绿；另交执行者查明并修复后再验。

## 当前源码的真实 Herdr 闭环

- 独立临时 Git 项目位于 `/private/tmp/qwb-production-e2e-bayoulto/project space`；源码从冻结候选归档安装，10 个安装脚本与 Pi 扩展逐字节匹配。归档和安装文件 SHA256 在 `/private/tmp/qwb-production-e2e-bayoulto/receipt.json`。后续整合只改文档，`git diff --exit-code fc0c29c 6e9b0f2 -- bin templates LICENSE` 为 0。
- 复用原执行 pane `wF2:pH`，先退出原执行者，确认空闲 shell 的实际 cwd 与已建任务 worktree 一致。调用真实安装副本 `qwb-run.sh --project <隔离项目> --task live-bayoulto --worker codex --worktree <隔离worktree> --pane wF2:pH --name qwb-live-bayoulto`，rc=0。
- 自动启动参数为 `codex --model gpt-5.6-sol -c model_reasoning_effort=medium --dangerously-bypass-approvals-and-sandbox`，真实会话 `01a0c8a9-c814-7681-8d17-3cb9756b9b2a`。派发后未补发提示词、未人工处理 trust、未干预工人输出。
- 工人提交 `fa801e3a11b16ad194092bdde8749992e022864a`，相对父提交仅 `result.txt`；内容严格为 `QWB_LIVE_OK` 加一个 LF。主控独立检查提交文件清单、字节与工作树干净。
- 项目 fast 检查真实文件字节，full 另检查文件已在 HEAD 且无未提交变化。派发前缺文件 fast=1；正确结果 fast/full=0；主控有意改错后 fast/full=1；恢复原字节后 full=0。详见 `gate-results.json` 及同目录原始日志。
- 安装副本前台 `qwb-wake.sh --block --max-ms 15000 --interval 1000` 两次以 rc=2 返回工作进展、完成记录；无新增进展时 `--max-ms 1000` 为 rc=124，未新增重复 wake；主控验收改为 verified 后为 rc=0，输出账本无未结项。未通过后台任务代替前台 checkpoint。
- 工人结束并退出 CLI 后，临时主仓快进合入产物；候选 `qwb-worktree.sh finish live-bayoulto --merged` rc=0，任务 worktree 与分支均删除。临时锁释放，项目和源码目录已删除，保留脱敏日志、收据与 `final-task.md`。

## 证据边界

这次实测覆盖本机 Codex、显式复用 pane、真实启动/投递/工作/账本/前台值守/验收/收尾。默认新 tab 派发未实测；不把该结果写成所有模式的无人干预证明。跨 workspace 的创建/复用/恢复与查询失败用假 Herdr 验证；Pi 使用真实 Node 扩展宿主和 Bash 子进程强退验证，不是 Pi 应用的 `/reload`；真实 Claude Stop host、跨平台及长期运行未实测。无生产 API、部署、发版、推送或其他项目安装升级。

## 修复后整合门

- `4dbc28a73b01966e520f6b5b213ae3e6e8bee691` 仅修旧 smoke 夹具与失败断言，运行时及模板未变。
- 主控在干净候选执行 `bash bin/qwb-test.sh full --project "$PWD"`：rc=0，110.168 秒；SMOKE PASS、REVIEW-IDENTITY PASS、LINT PASS。
- 原始日志 `/tmp/qwb-production-repaired-full.log`，机器收据 `/tmp/qwb-production-repaired-full.json`。
- `git diff --exit-code fc0c29c 4dbc28a -- bin templates LICENSE` 为 0：本次真实安装闭环的被测文件与最终整合候选相同。

原始门日志 SHA256：

- `qwb-production-final-fast.log`: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`
- `qwb-production-final-full.log`: `9d7073c6f16a0ed1578d9767572dc43632597e8bca9d2f037770be7eeba358e0`
- `qwb-production-repaired-full.log`: `300895a8941b3f491c6710d78e99812942f14b009495d4fcf04915b89445f7ec`

## 收尾

测试夹具增量独立审核 `production-smoke-r1.md` 为 PASS。主线快进到已通过全门的 `4dbc28a`，五张生产票改为 verified；四个 production 工作树和分支均由已合入的 finish --merged 收回。未 push。后续仅账本/证据变更另提交，不宣称进行了未覆盖的宿主验收。
