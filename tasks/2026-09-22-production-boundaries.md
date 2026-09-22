# 生产边界返修：安装、路由、收尾

state: running

## 0. 范围

根据 docs/reviews/2026-09-22-production-install-routing.md 的三个隔离反例修复。执行 GPT Sol medium，审核 GPT Sol high；仅复用已有窗口，不递归派发。尚未派发，等待前票候选。

白名单：bin/qwb-init.sh、bin/qwb-dispatch.sh、bin/qwb-worktree.sh、tests/smoke.sh、tests/boundary-readiness.sh（可选定向入口）、docs/DECISIONS.md。

- 安装/升级：Stop hook 判重核实实际命令与必要执行结构，不能把 echo/注释里包含脚本名当安装成功；保留用户无关 hook 与配置，不静默重写其自定义指令。无效同名项不能阻止规范 hook 安装。补充 `.pi-watch.err` 忽略，已有旧 marker 的安装也能升级且幂等，不破坏用户原有 .gitignore。
- 路由：非 200 仅回报状态码、耗时及固定错误类别，不把原始远端响应体回显到任何输出。反射 Authorization 的测试 canary 不得出现在 stdout/stderr；不读真实 key、不联网。关闭、非法配置与默认回退原有契约保持。
- worktree：在查账本或 Git 操作前拒绝路径型/越界任务 ID（兼容正常中文、连字符等已有 ID）；核实账本的物理位置仍在 tasks、目标物理位置仍在 .worktrees、目标是本仓登记的对应 worktree。不能借名、符号链接或路径规范化越界；保护非本票目录、分支、账本与未合入提交，保留已文档化的 stopped-writer 前提。

## 1. 验收场景

### 正常路径：已有安装正确升级
Given 旧版忽略 marker、真实既有 hook、自定义 config 与其他 hooks
When 连续运行安装器两次
Then config/其他 hooks 保留，规范 hook 不重复，旧忽略段补齐 Pi 错误日志，第二次安装无重复行。

### 失败路径：伪装成已安装的字符串
Given Stop hook 仅为 echo qwb-hook-claude-stop.sh 或包含名称的注释
When 运行安装器
Then 不误报已有有效 hook，保留原条目并补装规范入口（或明确失败且不损坏配置）。

### 失败路径：HTTP 错误响应反射凭据
Given 假 curl 返回 HTTP 500 且响应体含请求 Authorization 测试 canary
When 路由脚本及上层默认回退执行
Then 输出无 canary/原始响应体，错误状态与默认回退仍正确；不接触真实凭据。

### 失败路径：越界收尾
Given 本项目 tasks/foo、.worktrees/foo 以及另一真实已合入 worktree other
When finish foo/../../other --merged，或路径借符号链接指向外部
Then 前置拒绝，其他 worktree、分支、账本字节与主工作区均保持不变。

### 正常路径：合法本票收尾
Given 已停写、干净、登记属于本项目且提交已合入的合法任务 worktree
When finish --merged 或明确的 archive/keep
Then 既有成功/保留/未合入拒绝语义不回退，中文任务 ID 可用。

## 2. 验证与交付

先定向 red 再修复；新用例接入现有 smoke/full 入口，不能置于 exit 之后。执行者仅快门与本票定向测试，不跑全门、不 push/merge/清理 worktree，不动白名单外源码。提交后报告 SHA、命令、退出码和资源清理。主账本只追加状态，不改 state。
wake: 2026-09-22T07:04:27Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
