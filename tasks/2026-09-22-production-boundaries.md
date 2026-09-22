# 生产边界返修：安装、路由、收尾

state: verified

## 0. 范围

根据 docs/reviews/2026-09-22-production-install-routing.md 的三个隔离反例修复。执行 GPT Sol medium，审核 GPT Sol high；仅复用已有窗口，不递归派发。基线 1c500b38c014be9e55aa33fede2735ebaaf17d16；独立目录 .worktrees/production-boundaries，不包含前票尚待复审的代码。

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

scenarios-fp: 2597ebc4e193d87182edd3f3d0ca1f94085f1a6f
working: 2026-09-22T07:18:11.604343+00:00 主控复用后台执行 pane 启动新的 Sol medium 原生会话，CLI cwd 即本票独立目录；前票候选在另一目录接受固定 SHA 复审。
wake: 2026-09-22T07:18:32Z state=running fp=adfbfc5e6a8a34733d98f334b10dd7cceccfd63e
done: 2026-09-22T07:31:35Z 执行者 production-boundaries 提交 3b8edbf67f09f003c23300133f0c645a79a89d6b（基线 1c500b3）；规范 Stop hook 判重、旧 .gitignore 补 Pi 错误日志、HTTP 错误固定类别、finish 物理路径/精确任务/本仓 worktree 归属。基线定向 red rc=1（8 FAIL）；候选定向 rc=0（13 PASS），fast rc=0，定向脚本 shellcheck rc=0，diff --check rc=0；日志 /tmp/qwb-boundary-{red,green,fast}.log。未跑 full；隔离测试临时资源已清，未 push/merge/清理 worktree。
wake: 2026-09-22T07:32:36Z state=running fp=e64c7ed6963f99b0507e17d65af8a1fbe821a9e2
working: 2026-09-22T07:38:22.201893+00:00 独立复审 3b8edbf 为 AMEND，唯一余项：不完整旧 ignore marker 只补 Pi 日志，仍漏 controller/watch 等运行态；见 production-boundaries-r1 报告。下一次仅修 bin/qwb-init.sh 对全部必需规则逐项补缺，tests/boundary-readiness.sh 用实际 git status/check-ignore 验证全部运行态并保原有行，必要时联动 tests/smoke.sh 计数。路由与收尾已定向复核，不重改。
wake: 2026-09-22T07:38:39Z state=running fp=5d9485c9b77e51c983e461ae2186bc05413f90c8
done: 2026-09-22T07:41:07Z 返修提交 a8eec488a75d9cec8a006af4deeb310a3b7554b2（基线 3b8edbf）；仅 bin/qwb-init.sh、tests/boundary-readiness.sh。旧 marker 夹具先以 git status/check-ignore 反证 controller/watch 污染：bash tests/boundary-readiness.sh rc=1（14 PASS/1 FAIL，/tmp/qwb-boundary-r2-red.log）；补齐全部七条运行态规则后同命令 rc=0（15 PASS/0 FAIL，/tmp/qwb-boundary-r2-green.log），重复安装 .gitignore 字节不变、用户原有前缀字节不变；bash bin/qwb-test.sh fast --project "$PWD" rc=0（/tmp/qwb-boundary-r2-fast.log）；shellcheck bin/qwb-init.sh tests/boundary-readiness.sh rc=0（/tmp/qwb-boundary-r2-shellcheck.log）；bash -n 两文件 rc=0；git diff --check 与 git diff --cached --check 均 rc=0。定向脚本临时目录由 EXIT trap 清理；未跑 full、未 push/merge、未清理 worktree；提交后工作树干净。
wake: 2026-09-22T07:42:40Z state=running fp=6be88cba72cfa712d330140242cd47841123c10f
working: 2026-09-22T07:49:05.448975+00:00 主控收回候选 a8eec488a75d9cec8a006af4deeb310a3b7554b2 的最后一项独立复核 PASS（docs/reviews/2026-09-22-production-boundaries-r2.md）；与前轮已通过部分共同覆盖本票。state=done，等待最终整合候选全门和真机验收，暂不标 verified。

working: 2026-09-22T10:41:24.995773+00:00 主控验收：最终源码整合 4dbc28a，独立复审全部 PASS；整合 full rc=0/110.168s；当前同源安装副本真实 Codex Herdr 显式复用 pane 闭环通过，正负门与前台 block 2/124/0、worktree 收尾均实测。主线已快进合入；详见 docs/reviews/2026-09-22-production-final.md 的证据及未覆盖边界。state=verified。
worktree: merged branch=production-boundaries tag=-
