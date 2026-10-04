# 任务书：collab-land 的 socket 改走统一夹具（补齐 socket 路径守卫的漏网之处）

```
任务 id:  audit-socket-land
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     主控验收 audit-socket-path 时发现的遗留（见该票 2026-10-04 的验收行）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（Pi，magpie codex/gpt-6.1-sol high；沿用 audit-socket-path 的会话）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-04-audit-socket-land.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2（新的隔离副本，detached HEAD，起点 main ade605c；目录名故意取长）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：测试建的东西只能在本项目内；对本项目做彻底审核与优化。

你上一张票（audit-socket-path）已验收并合入 main：测试 socket 统一经 `tests/process_fixture.py` 的 `socket_path()` 建在 `仓库根/.qwb-tmp/两位十六进制/s`，并按「固定后缀 14 字节、仓库根最多 89 字节」做启动守卫。

与它并行落地的另一张票（audit-collab-land-red，提交 a7722dc）给 `tests/collab-land.sh` 新加了一个假 RPC 服务，socket 是它自己拼的：`Path(os.environ['QWB_TEST_SCOPE_DIR'])/'land.sock'`，即 `仓库根/.qwb-tmp/两位十六进制/land.sock`，后缀 22 字节，比守卫假设的多 8 字节。后果：仓库根在 82 到 89 字节之间时，守卫放行，`collab-land.sh` 却会因为 socket 路径超限而失败——正是上一张票要消灭的那种「莫名红」。

### 工程规格

1. `tests/collab-land.sh` 的假 RPC socket 改用 `socket_path()` 夹具，目录登记与退出清理都走夹具，不再自己拼路径。
2. 全仓 `tests/` 再扫一遍：凡是建 AF_UNIX socket 的地方（`bind(`、`.sock`、`AF_UNIX`）都必须经 `socket_path()`，逐处列出文件与行号及结论。`tests/fixtures/herdr/wire-server.py` 这类由调用方传入路径的，确认调用方传的是夹具给的路径。
3. `tests/socket-path-regression.py` 增补一条覆盖 `tests/collab-land.sh` 的检查，写法照它现有的三条。
4. 不改断言，不改 `bin/` 与 `templates/`。

白名单：`tests/` 下的文件。

## 1. 验收场景

### user_正常路径_长路径副本里collab-land与全门通过

Given 本副本（先报出仓库根的字节数；它应在 82 到 89 之间，不在这个区间就在 `.qwb-tmp/` 下导出一份使其落入该区间再测）
When  跑 `bash tests/collab-land.sh` 两次，再跑 `bash bin/qwb-test.sh full`
Then  全部退出码 0；全门 0 FAIL、COLLAB-ALL PASS（12 项）；全门后 `git status --short` 无输出、仓库根目录 `ls -A` 无新增项、无残留进程

### user_失败路径_修复前在该区间确实失败

Given 起点提交在同样字节数的仓库根下
When  跑 `bash tests/collab-land.sh`
Then  因 socket 路径超限而失败，报出实际路径与字节数——证明这个漏网之处是真的

### user_失败路径_超预算时仍然早报

Given 仓库根超过 89 字节
When  跑 `bash tests/collab-land.sh`
Then  在任何断言之前以清晰中文信息失败退出，写明实际字节数与上限

## 2. 硬约束

- 只在自己的工作目录（上面那个新副本）里改代码，只动白名单内文件。主仓根下除了往主账本追加状态行，**什么都不许动**；你上一张票的旧副本也不要再动。
- **绝对不许对真 Herdr 做任何写操作**；不要移除或绕过测试的失效关闭隔离与进程登记夹具。
- socket 与临时文件只许建在本副本的 `.qwb-tmp/` 之内；仓库根下不得出现新目录。
- 临时文件只许删除自己建出并记在变量里的确切路径；禁止任何带 `*` 的 `rm`。杀进程只许杀自己启动并记下 PID 的进程。
- git：只许在自己的副本里 `git add` 白名单文件与 `git commit`。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行，不加签名行。
- 状态行时间戳取自机器；状态行里不要出现尖括号占位写法；阶段性进展用 `working:`，只有全部完成才写 `done:`；PASS 与 FAIL 的行数用 `grep -c '^PASS'` 与 `grep -c '^FAIL'` 数，写进结论前对照日志核一遍。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`。
- 三个场景逐个验证，命令与原始结果写进 `done:` 行。
- 全门结果按场景一的要求报。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:` / `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 DONE 加最终提交的 sha，或 STOP 加原因，并把同样的 sha 写进 `done:` 行。

## 6. 本票不允许做的事

- 不改 `bin/`、`templates/`、文档；不改断言。
- 不碰真 Herdr 的任何状态；不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-04T06:45:38Z 主控手工派发（同 Space 独立 Tab「socket路径·pi」，沿用 audit-socket-path 的 Pi 会话，新副本）：worker=pi（magpie codex/gpt-6.1-sol high）agent=qwb-audit-socket-path pane=w14Z:pB dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2 base=ade605c
working: 2026-10-04T06:49:27Z 新票执行者已切换新副本，起点ade605c7c25cb88edc0ef79b162637fcf66ae60a，根82字节处于82..89区间，旧副本未动。新副本原无.qwb-tmp，按规格初始化唯一已忽略临时容器后保存根ls -A基线；其余产物全在其中。修复前bash tests/collab-land.sh已复现rc1、AF_UNIX path too long，实际旧socket路径104字节，完整路径与异常帧已记baseline-audit.jsonl。守卫按14字节后缀放行96字节，但旧land.sock后缀22字节，证实漏网。扫描已保存socket-inventory-before.txt，接下来统一land夹具并补回归，不改原断言/产品/状态字段。
working: 2026-10-04T06:54:52Z 最小实现完成并提交b105ee9，仅tests/collab-land.sh与tests/socket-path-regression.py，原land全部AST断言相同；land用socket_path()分配登记清理，回归按原三条增加land第四条。快门rc0、Python语法与diff检查通过；已按规格依序运行land两次，均成功后自动开始全门，同时运行增补回归。所有动作位于新副本，旧副本未动；PASS/FAIL使用规定grep -c前缀计数并与原日志复核。
working: 2026-10-04T06:59:45Z 全tests静态扫描阶段完成，逐处文件/行号/结论已写socket-inventory.json：land:14/95/96、herdr三个bind:43/113/267及路径来源28/84/250、worktree-space:158/159、wire-server:8-10（调用方smoke:116-118）、regression原生103字节探针:58-63都追溯统一fixture的分配登记/守卫。land的def bind(raw)只是PID证据写入；/dev/null/*.sock均失效关闭标记。另列人工e2e-real.sh:57/95真实Herdr服务身份路径（不进fast/full、非Python假bind），未执行/未改、不把它冒充socket_path覆盖。只修本票离线fixture漏网点，旧副本与真Herdr始终未动。超预算场景已git archive导出本提交到本副本.qwb-tmp内105字节根，collab-land rc2，stdout空，中文实际119字节/上限103/根最多89，无断言FAIL；该确切导出目录已清理。
working: 2026-10-04T07:00:44Z 正常定向验收阶段完成：本82字节根下bash tests/collab-land.sh两次均rc0、grep前缀计数各9 PASS/0 FAIL、git status --short均空；各一次真实成功AF_UNIX bind为96字节，地址来自统一fixture，目录在退出后已清理。增补回归rc0，含land第四条通过；本深副本导出根93/97字节的既有早报回归输出实际107/111字节，另本票独立land超预算119字节早报也通过。两个land完成后全门已启动，仍执行中；未把部分通过当全门完成。
working: 2026-10-04T07:12:32Z 最终验收阶段完成：b105ee99cd47500d11e5f21c28719d6a7cb63c14，本82字节根下land两次各rc0、9 PASS/0 FAIL；随后全门rc0、grep规定计数831 PASS/0 FAIL、COLLAB-ALL PASS（12项），前后sha相同。快门与增补回归均rc0；full共29次成功bind全部.qwb-tmp内、最大96字节，登记socket目录全已清理、无自己启动的测试残留进程；全门后git status --short为空，ls -A与初始化标准忽略临时容器后的基线完全相同。临时审计Python模块已精确删除；全仓扫描逐处文件与实际行号见socket-inventory.json（land证据bind函数应为209行，清理器178行，最终清单已校准），原始结果与三场景均保存report.json。
done: 2026-10-04T07:12:32Z {"sha":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","base":"ade605c7c25cb88edc0ef79b162637fcf66ae60a","root":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2","root_bytes":82,"scenarios":{"user_正常路径_长路径副本里collab-land与全门通过":{"sequence":{"land-1":{"command":"bash tests/collab-land.sh","rc":0,"PASS":9,"FAIL":0,"head_before":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","head_after":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","git_status_short":"","last5_first100":["EVIDENCE {\"phase\": \"running\", \"claim\": {\"op_id\": \"land-recover-publish-reauthorize\", \"owner\": \"ctl\"}","RC=0 qwb-worktree.sh land recover-publish-reauthorize --op land-recover-publish-reauthorize --auth-r","RC=0 qwb-ledger.sh read --task /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long","EVIDENCE {\"phase\": \"verified\", \"claim\": null, \"land\": {\"after\": \"1f1a8ee4dd2356d1eeea41f2fdd6b23ad87","PASS user_合并成功记账或清理失败 publish-reauthorize 同op补事实/partial，无重复merge"],"raw_log":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/land-1.log"},"land-2":{"command":"bash tests/collab-land.sh","rc":0,"PASS":9,"FAIL":0,"head_before":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","head_after":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","git_status_short":"","last5_first100":["EVIDENCE {\"phase\": \"running\", \"claim\": {\"op_id\": \"land-recover-publish-reauthorize\", \"owner\": \"ctl\"}","RC=0 qwb-worktree.sh land recover-publish-reauthorize --op land-recover-publish-reauthorize --auth-r","RC=0 qwb-ledger.sh read --task /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long","EVIDENCE {\"phase\": \"verified\", \"claim\": null, \"land\": {\"after\": \"09af74e327216e05810e2f0781ca89b1759","PASS user_合并成功记账或清理失败 publish-reauthorize 同op补事实/partial，无重复merge"],"raw_log":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/land-2.log"},"full":{"command":"bash bin/qwb-test.sh full","rc":0,"PASS":831,"FAIL":0,"head_before":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","head_after":"b105ee99cd47500d11e5f21c28719d6a7cb63c14","git_status_short":"","last5_first100":["PASS  tests/collab-roles.sh（66s）","PASS  tests/collab-test-policy.sh（95s）","PASS  tests/lint-scenario-stream.sh（2s）","PASS  tests/path-canonicalization.sh（0s）","COLLAB-ALL PASS（12 项）"],"raw_log":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/full.log"}},"audit":{"land-1":{"successful_binds":1,"max_bytes":96,"outside_ignored_tmp":0,"remaining_socket_directories":0,"new_root_directories":0,"record":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/land-1-audit.jsonl"},"land-2":{"successful_binds":1,"max_bytes":96,"outside_ignored_tmp":0,"remaining_socket_directories":0,"new_root_directories":0,"record":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/land-2-audit.jsonl"},"full":{"successful_binds":29,"max_bytes":96,"outside_ignored_tmp":0,"remaining_socket_directories":0,"new_root_directories":0,"record":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/full-audit.jsonl"}}},"user_失败路径_修复前在该区间确实失败":{"command":"bash tests/collab-land.sh","rc":1,"PASS":0,"FAIL":0,"socket":{"event":"exception","source":"<stdin>","line":83,"path":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/2b/land.sock","bytes":104,"error":"AF_UNIX path too long"},"raw_output":"Traceback (most recent call last):\n  File \"<stdin>\", line 83, in <module>\nOSError: AF_UNIX path too long\n"},"user_失败路径_超预算时仍然早报":{"command":"git archive HEAD | tar -x -C /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/over-ioco3592; cd /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/over-ioco3592; bash tests/collab-land.sh","root":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/over-ioco3592","root_bytes":105,"socket_bytes":119,"rc":2,"stdout":"","stderr":"测试 socket 路径超限：实际 119 字节，上限 103 字节；仓库根实际 105 字节，最多 89 字节（固定后缀 14 字节）：/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/over-ioco3592/.qwb-tmp/00/s\n"}},"fast":{"command":"bash bin/qwb-test.sh fast","rc":0},"regression":{"command":"python3 -B tests/socket-path-regression.py","rc":0,"raw_output":"仓内最短导出根 93 字节超过 89；正例使用当前源码根，导出副本验证断言前早报\nPASS tests/smoke.sh: root=82 bytes, socket=96 bytes\nPASS tests/worktree-space.py: root=82 bytes, socket=96 bytes\nPASS tests/collab-herdr.sh: root=82 bytes, socket=96 bytes\nPASS tests/collab-land.sh: root=82 bytes, socket=96 bytes\nPASS native 103-byte bind/connect inside .qwb-tmp: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/6b/ssssssss\nPASS over-budget checkout exits 2 before assertions: 测试 socket 路径超限：实际 107 字节，上限 103 字节；仓库根实际 93 字节，最多 89 字节（固定后缀 14 字节）：/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/3/.qwb-tmp/00/s\nPASS UTF-8 root uses bytes before assertions: 测试 socket 路径超限：实际 111 字节，上限 103 字节；仓库根实际 97 字节，最多 89 字节（固定后缀 14 字节）：/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/3/长/.qwb-tmp/00/s\n"},"inventory":{"command":"rg -n -F -e AF_UNIX -e 'bind(' -e .sock -e socket_path -e createServer -e node:net tests","points":[{"file":"tests/collab-land.sh","lines":[14,95,96],"conclusion":"socket_path()返回绝对地址；原RPC协议与断言保留，目录登记与退出清理归共享监督器"},{"file":"tests/collab-herdr.sh","lines":[14,28,43,68,84,113,235,250,267],"conclusion":"三个AF_UNIX bind的sockpath/socketpath均来自socket_path()；第四片段复用worktree-space项目构造器，也走统一夹具"},{"file":"tests/worktree-space.py","lines":[16,158,159,169],"conclusion":"fixture_socket_path为socket_path别名；bind与假Herdr状态给客户端的QWB_TEST_SOCKET共用该绝对地址"},{"file":"tests/fixtures/herdr/wire-server.py","lines":[8,9,10],"conclusion":"路径由argv传入；唯一定向调用点smoke.sh:116-118先执行共享helper socket子命令，再把HERDR_TEST_SOCKET传入，地址来自socket_path()"},{"file":"tests/smoke.sh","lines":[116,117,118,135],"conclusion":"socket_path CLI返回地址传wire-server并用于status stub，服务端/客户端同一fixture地址"},{"file":"tests/socket-path-regression.py","lines":[58,59,60,61,62,63],"conclusion":"103字节原生边界探针先调用socket_path()获得登记的私有目录，在同目录内扩展文件名并对实际地址check_socket_path再bind；故意边界探针，不是未校验/未登记的独立服务"},{"file":"tests/process_fixture.py","lines":[84,93,97,117,132,178],"conclusion":"统一分配/守卫/登记/先排空后清理实现；没有自行新增bind"},{"file":"tests/collab-land.sh","lines":[209],"conclusion":"def bind(raw)只是追加PID/start死亡证据的本地函数，不是socket.bind"},{"file":"tests/e2e-real.sh","lines":[2,55,57,94,95],"conclusion":"人工真实E2E、不进fast/full；herdr.sock为真实named Herdr服务身份引用，socket由外部Herdr服务管理，不是Python假AF_UNIX bind。脚本还声明/tmp工作目录；本票未执行、未启动真实服务，保留原状并明确列出此非离线夹具边界，不宣称它经socket_path()"},{"file":"tests/e2e-real.py","lines":[20,64,107,108],"conclusion":"接收并核验外部真实服务SOCKET身份，不创建AF_UNIX socket；本票未运行"}],"fail_closed_sentinel_references":["tests/collab-land.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/r2-cli.py:6:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/collab-ci-diagnostics.sh:8:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-roles.sh:8:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/pi-ext.test.mjs:11:process.env.HERDR_SOCKET_PATH = \"/dev/null/qwb-test.sock\";","tests/r4-cli.py:6:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/optional-routing.sh:8:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-posture.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/wake-block-output.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/on-demand-guide.py:6:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/collab-handoff.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/review-identity.sh:13:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-test-policy.sh:8:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-all.sh:16:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/lint-scenario-stream.sh:8:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/invalid-ledger.py:5:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/e2e-controllers-cli.py:6:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/collab-ledger.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-planning.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/lifecycle-readiness.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/worktree-space.py:6:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/boundary-readiness.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/collab-gate.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/runtime-readiness.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/smoke.sh:5:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock","tests/worker-config.py:7:os.environ[\"HERDR_SOCKET_PATH\"] = \"/dev/null/qwb-test.sock\"","tests/collab-herdr.sh:10:export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock"],"sentinel_conclusion":"全部/dev/null/qwb-test.sock是失效关闭标记，不是创建可用socket的位置；保留。","node_server_conclusion":"未发现Node Unix域服务或额外createServer创建点。","raw_inventory":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/socket-inventory-after.txt"},"cleanup":{"git_status_short":"","root_ls_A":".git\n.gitignore\n.qwb-tmp\nbin\ndocs\nLICENSE\nqwb.config.sh\nREADME.md\nREADME.zh.md\ntasks\ntemplates\ntests\n","root_inventory_unchanged":true,"remaining_test_processes":[],"owned_launcher_pids":["60709","60707"],"source_pycache_exists":false,"removed_instrumentation":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/audit-python"},"changed_files":["tests/collab-land.sh","tests/socket-path-regression.py"],"original_land_assertions_unchanged":true,"count_commands":["grep -c '^PASS'","grep -c '^FAIL'"],"old_worktree_untouched":true,"evidence":"/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-socket-land-long-name-check-2/.qwb-tmp/socket-land.tu84NGvR/report.json","scope":"仅新副本tests/collab-land.sh与tests/socket-path-regression.py；原断言、bin/templates与共享失效关闭/进程登记均保留；不动旧副本，不合并main，不建分支/push，不写真Herdr；仅新票追加状态，state字段未改","budget":"原shared guard预算不变：socket后缀14字节、根最多89字节；本根82，旧land.sock后缀22/实际104，新fixture地址实际96。原生边界探针仍在fixture登记目录内检查实际103字节，所有临时文件只在新副本.qwb-tmp内。"}
working: 2026-10-04T07:27:35Z 主控验收：diff 已审（tests/collab-land.sh 的假 RPC socket 改经 socket_path 夹具；回归脚本增补 collab-land 一项）；在仓库根 82 字节的副本 b105ee9 上独立验证：bash tests/collab-land.sh 连跑 2 次均 rc=0、各 9 PASS；bash bin/qwb-test.sh full：rc=0、831 PASS / 0 FAIL、COLLAB-ALL PASS（12 项）、595.96s；全门前后仓库根目录无新增项、git status 干净、无残留进程。已 ff-only 合入 main（HEAD=b105ee9），未 push。
