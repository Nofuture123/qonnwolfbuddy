# 生产审核第二轮：安装、可选路由、worktree 收尾

**结论：AMEND。** 冻结源码 `1c500b38c014be9e55aa33fede2735ebaaf17d16`；只用 `git show <SHA>:<path>` 读取源码白名单 `bin/qwb-init.sh`、`bin/qwb-dispatch.sh`、`bin/qwb-worktree.sh` 及必要模板。未把当前 main 当候选源码，未重审前轮锁、Pi、派发复用问题，未跑全门、未创建 Herdr 窗口或派发。以下三项均在临时目录用冻结源码隔离复现；Python `TemporaryDirectory` 退出时自动清理源码副本、假命令、仓库与 worktree，未触碰真实项目。

## 1. 安装器把无效的同名字符串当成已安装 Stop hook

- **位置与证据**：`bin/qwb-init.sh:171-180` 的 `has_qwb()` 只检查现有 Stop hook 的 `command` 是否含 `qwb-hook-claude-stop.sh`，没有核实它执行的是安装器要求的命令（`bin/qwb-init.sh:137-142`）。隔离项目预置唯一 Stop hook 命令为 `echo qwb-hook-claude-stop.sh`，保留自定义 `qwbuddy/config.sh`，再运行冻结安装器：`rc=0`，输出“已有 qwb-hook…”，Stop hooks 仍只有该 `echo`，配置字节保持不变。
- **影响**：项目表面安装成功、配置也保留了，但 Claude Code 没有实际值守 hook；重复安装继续误判，任务进展不会经 Stop hook 唤醒主控。
- **最小修复**：判重核实 Stop hook 的完整结构和实际执行命令；仅有名称字符串而非有效调用时补装规范 hook 或明确失败。加带 `echo`/注释型同名字符串的重复安装反例。

## 2. 路由 HTTP 错误会把服务端反射的 API key 打到日志和 stdout

- **位置与证据**：`bin/qwb-dispatch.sh:143-146` 把 key 放进 Authorization 头；非 200 响应在 `bin/qwb-dispatch.sh:149` 取原始响应前 200 字符拼进 `emit_error()`，而 `bin/qwb-dispatch.sh:66-69` 同时写 stderr 与供上层读取的 stdout `reason`。隔离复现用假 `curl` 读取脚本给它的头文件，将该头作为 HTTP 500 响应体：脚本 `rc=0/status: error`，测试 canary `review-secret-canary` 同时出现在 stdout 和 stderr。未发网络请求。
- **影响**：若 API、代理或故障页面反射请求头，凭据会进入终端、上层派工错误输出及可能的日志；与脚本 `bin/qwb-dispatch.sh:17-18` 的“不打印 key”承诺冲突。普通错误回退状态仍是 `error`，但不能以回退成功掩盖泄露。
- **最小修复**：HTTP 非 200 只输出状态码和固定错误类别，不回显未经验证的远端响应体；保留本地私有诊断也须先排除凭据。加“响应体反射 Authorization”反例，断言所有输出不含 canary 且仍走默认工人回退。

## 3. `finish` 可越出任务目录，删掉另一处真实 worktree 并向账本外写入

- **位置与证据**：`bin/qwb-worktree.sh:43-53,108-115` 接受未校验的 `TASK_ID` 并拼成 `$WT_BASE/$TASK_ID`；`unique_task_for()` 的回退 glob（`bin/qwb-worktree.sh:77-90`）也未限定最终任务书必须在 `tasks/` 下。`--merged` 经祖先检查后按拼出的路径执行 `git worktree remove` 并删实际分支（`bin/qwb-worktree.sh:185-207`）。隔离 Git 项目中创建 `tasks/foo/`、`.worktrees/foo/`、项目根 `other.md` 和项目根 `other/` 真实 worktree（其 HEAD 已并入 main）；调用 `finish foo/../../other --merged --project <根>` 返回 `rc=0`，`other/` worktree 与 `other` 分支被删，`worktree: merged ...` 被追加到项目根 `other.md`，而非 `tasks/`。
- **影响**：任务 ID 中的路径分隔符能让清理越界，误删非本票 worktree/分支并污染账本外文件；在真实提交已落地的场景也会破坏任务目录边界。
- **最小修复**：在任何文件查找/Git 操作前拒绝含 `/`、`..` 等路径组件的任务 ID；再核对任务书物理路径在 `tasks/`、目标物理路径在 `.worktrees/` 且是本项目登记的对应 worktree。加上述越界输入的拒绝断言，确认外部 worktree、分支、任务书字节不变。

**安装附项（主控先前已复现，本轮未重复运行）**：`bin/qwb-init.sh:75-83` 写入的忽略段缺 `qwbuddy/.pi-watch.err`；该运行态错误文件会进入 `git status`，应补入安装/升级路径及相应检查。这不改变本轮三项的排序。

其余范围：安装器对现有 `config.sh` 的保留在上述隔离复现中成立；可选路由的正常/关闭/错误默认回退与其他收尾分支未被本报告宣称全面通过。源码修复及候选验证仍待主控完成。
