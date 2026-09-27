# 任务书：claude worker 启动加 --add-dir 项目根（Claude Code 2.1.257+ 目录外读取坑）

```
任务 id:  qwb-claude-add-dir
state: verified
scenarios-fp: bf34cdb299b8f083822f48ca7a29c82ef04b9431
来源:     Rocky 同意吸收 firstmate upstream c19c2402 的同类修复（2026-09-27 评估）
派发:     主控（Pi, wT2:p1）→ 执行者（claude worker pane）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-27-qwb-claude-add-dir.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-claude-add-dir
分支:     qwb-claude-add-dir
```

## 0. 背景与范围

Claude Code 2.1.257 起，工作目录之外的文件读取（Read/Glob/Grep 及 Edit 前置读）在
`--permission-mode auto` 下弹一次性交互确认；一旦有人答 Block，会持久化
`permissions.blockReadsOutsideWorkingDirectories`，此后连 bypass 模式也拒绝同样读取
（firstmate upstream c19c2402 的修复说明，已核实）。qwb 派发的 claude worker cwd 在
worktree，而提示词让它开工先读主项目根 `tasks/` 下的任务书——正是目录外读取。本机
Claude Code 2.1.283，条件成立；本机 settings 尚无 Block 记录，属「未踩但真」的坑。

修法（firstmate 同款思路，qwb 形态）：`qwb-init.sh` 装机生成 `qwbuddy/workers.sh` 时，
给 claude 行附加启动参数 `-- --add-dir <项目根>`，使 claude worker 天然可读任务书与
主项目文档。qwb-run.sh 的 WORKER_ARGV 透传机制已存在，预期不改 qwb-run.sh。

白名单：`bin/qwb-init.sh`、`tests/smoke.sh`、`tests/worker-config.py`、
`docs/`（仅同主题段落）、`tasks/lessons.md` 与 `tasks/lessons/`。
**不改** `bin/qwb-run.sh`、`bin/qwb-lib.sh`、`templates/`（argv 机制与文档已存在；
确需改先 `blocked:` 列证据等主控裁决，不得硬编）。

实现前必须核实（写入报告）：`herdr agent start --kind claude -- <argv>` 是否把 argv
拼进 claude CLI 本体（`herdr agent start --help`、herdr 文档/源码或无副作用实测）。
结论两种都有出路：透传 → 按本票实现；不透传 → `blocked:` 上报主控裁决，不得伪实现。

## 1. 验收场景（场景冻结后不得回改迎合实现）

### user_正常路径_新装workers带add-dir

Given 一个未装 buddy 的临时 git 项目，装机项目根为 P
When 运行 qwb-init.sh 装机
Then 生成的 workers.sh 中 claude 行含 `--` 与 `--add-dir` 且其值恰为 P；pi/codex 行与旧版字节一致

### user_正常路径_旧装机窄升级且幂等

Given 已装项目的 workers.sh 为旧格式（claude 行无参数），且用户已自定义（codex 行带自定义 argv、文件含注释/重排）
When 重跑 qwb-init.sh，然后再跑一次
Then 第一次：仅 claude 行被改写为带 `-- --add-dir P`，其余行字节不变；第二次：文件不再变化（幂等，不重复追加）

### user_正常路径_派发argv透传

Given workers.sh claude 行带 `-- --add-dir P`（背景核实结论=透传）
When stub 环境跑 qwb-run.sh --worker claude 派发
Then stub 日志中 agent start 命令含 `-- --add-dir P`（qwb-run 现有 WORKER_ARGV 透传）

### user_失败路径_路径含空格

Given 项目根含空格（如 `<tmp>/my project`）
When init 装机并跑派发断言
Then workers.sh 该参数按 Bash 实参逐项保真，--add-dir 值完整为一个实参（不裂开、不丢引号）

### user_正常路径_无argv向后兼容

Given 未升级的旧 workers.sh（claude 行无任何 argv）
When qwb-run.sh --worker claude 派发
Then 行为与升级前一致（argv 为空不报错、agent start 不带多余 `--`）

## 2. 硬约束

- `--add-dir` 值 = init 时的项目根物理路径（`pwd -P`）；装机时写入，运行时不再解析。
- 已存在 workers.sh 的升级必须是**窄改写**（只动 claude 行），不得整文件重写、不得重排、不得吞注释；幂等。
- claude 信任预置逻辑（qwb-run 的 hasTrustDialogAccepted 段）不动。
- smoke 每条新断言正负例齐全；不得放宽/删除既有断言换通过。
- 错题本：`tasks/lessons/` 新增一篇（Claude Code 2.1.257 目录外读取坑、Block 持久化、吸收决定），索引加一行。
- 收工前跑 `bash bin/qwb-test.sh fast`（bash -n + shellcheck + smoke）退出 0，报告附实际输出尾部。
- 共享文件串行修改；不 push、不合 main、不删分支——收尾由主控执行。

## 3. 验收门

- 执行者：`bash bin/qwb-test.sh fast` 退出 0，报告附命令、退出码、断言计数变化。
- 主控：另跑 full 门 + 真实 herdr 观察本票派发行为（本票即以 claude worker 派发，属真实链路观察样本）。

## 4. 报告要求

往本文件追加 `working:/done:/blocked:` 状态行（只追加）；done: 附：背景核实结论（herdr 透传与否及证据）、改动文件清单、fast 门输出尾部、新增断言数与场景编号、未覆盖项。
worktree-space: id=wTG root-tab=wTG:t1 path=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-claude-add-dir
dispatch: 2026-09-27T21:42:04Z worker=claude agent=qwb-qwb-claude-add-dir pane=wTG:p1 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/qwb-claude-add-dir
working: 2026-09-27T21:46:14Z 执行者(claude wTG:p1) 开工：核实 herdr agent start -- argv 透传 → 改 bin/qwb-init.sh claude 行窄改写 + smoke/worker-config 断言 → fast 门
done: 2026-09-27T21:55:10Z 执行者(claude wTG:p1) ①背景核实=透传：`herdr agent start --help` 用法 `[-- [AGENT_ARG]...]`；`herdr --skill` 第131行「Pass native agent arguments only after --」；本 worker 进程祖先链实测 `claude --dangerously-skip-permissions --autocompact 500k`（workers.sh 的 argv 原样进 claude CLI，herdr 只附加自己的 --autocompact）。②改动：bin/qwb-init.sh（quote_worker_arg 提到顶层；新增 upgrade_claude_add_dir：perl 逐行只改 `qwb_worker claude herdr` 行、在 herdr 后插 `--add-dir <pwd -P 单引号实参>`，已含 --add-dir/--add-dir= 则跳过、pane-run/无 claude 行/符号链接不动、bash -n 后原子 mv、无尾换行保真）；tests/smoke.sh 新节 §17c（插在 §17b 与 §18 之间，14 条断言：S1×3 新装值恰为物理路径+其余4行与模板字节一致+模板不含 add-dir；S2×7 窄升级/幂等报跳过/4 种不动负例/符号链接负例；S3×1 stub 日志 agent start 以 `-- --add-dir P --dangerously-skip-permissions` 结尾且 -- 恰一个；S4×2 含空格路径 argv 恰 4 项单实参+派发含完整路径；S5×1 旧行无 argv 派发 agent start 无 --）。③门：`bash bin/qwb-test.sh fast` 退出 0、无输出（bash -n + shellcheck 全过）；局部 smoke（§1–§17c 截取脚本）155 PASS / 0 FAIL，§17c 14/14 PASS；完整 smoke 未由我跑（按主控缩围指令），主控独立跑 full。④偏离说明：workers.sh claude 行**不写字面 `--`**——qwb-run.sh:906-908 已在 WORKER_ARGV 前加 `--`，再写一个会以字面 `--` 进 claude CLI 把 `--add-dir P` 变成位置参数（提示词）；场景 S3 的「agent start 命令含 `-- --add-dir P`」按 stub 日志字面满足（--add-dir 插在 herdr 后首位）。⑤未覆盖：tests/worker-config.py 未加 JSON argv 断言、tasks/lessons/ 新篇+索引、docs/ 段落均未写（主控 23:51 缩围为仅 smoke+fast）；--migrate-worker-config 生成的 claude 行要再跑一次普通 init 才补 --add-dir；未 push、未合 main。
done: 2026-09-27T22:28:07Z 执行者(claude wTG:p1) 返修 Sol 审点 3（只动 tests/smoke.sh）：①stub herdr 的 agent start 分支在原 `herdr $*` 日志行后追加一行逐项 JSON（`perl -MJSON::PP=encode_json` 对 `${@:3}` 编码，形如 {"cmd":"agent start","argv":[...]}，键序不保证故断言按 `"cmd":"agent start"` 匹配而非行首），原日志行保留、既有断言格式不变；②新增 ad_json_tail：解析唯一 JSON 行，断言 argv 末 4 项恰为 ["--","--add-dir",P,"--dangerously-skip-permissions"] 且 P 单元素、"--" 恰一个；S3 在原 $* 断言之外加此 JSON 断言，S4 派发断言改为只信 JSON（含空格路径单元素实证）；③新增 S4b：项目根 `<tmp>/it's proj`，断言 workers.sh 用 `'\''` 转义、bash -n 过、qwb_worker 解析回原路径为一个实参，派发 JSON argv 单元素等于物理路径。§17c 现 16 条断言（+2）。门：`bash bin/qwb-test.sh fast` 退出 0 无输出；局部 smoke（§1–§17c 截取）157 PASS / 0 FAIL。中途一次夹具错误（JSON 键序按行首匹配、$* 对照断言用 printf 多参拼接写错）已改掉，对照断言删除。说明：tasks/lessons.md 在 00:01 被本 worktree 另一方追加了一行索引（非我所写，未动）；完整 smoke/full 门留主控。
worktree: merged branch=qwb-claude-add-dir tag=-
