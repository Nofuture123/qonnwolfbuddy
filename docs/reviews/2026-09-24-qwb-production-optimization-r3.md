# 生产接入前优化 收尾审核 r3（含真实 E2E）

结论：r2 六个审点已修复并独立复验通过（见「r2 复验」）。复验中用 r2 真实闭环的原始账本发现 1 个 HIGH，另有工人启动文档过时 1 项；加上使用者 2026-09-24 要求的「真 Herdr + 真主控 + 真工人」E2E，本轮一并完成。**Standards AMEND；Spec AMEND**。审核者为 Claude Code（Opus 5.5，Herdr pane `wF2:p3`）。

## 冻结对象

- 候选 `7ae8cadfe2e826945b8bbfee70d0c894a20c1c26`，代码定稿 `9e9e7c931b5b148d22408ba172dcf1536454eba5`；基线 846fcce。两者之间只差 r2 执行报告。
- 真实 Herdr 实验只在 named session `qwbrev-iso3` 中进行，规则同 r2。

## r2 复验（通过）

- full：在 7ae8cad 导出副本上独立运行，FULL_RC=0，241s，660 条 PASS、0 FAIL；SMOKE / REVIEW-IDENTITY / LINT 均 PASS，§81 是 SMOKE PASS 前的最后一节，节标题与 `/tmp/qwb-full-7ae8cad.log` 一致。`tests/r2-cli.py` 在 87222a2 上第一组即失败（新文件 0600），在 7ae8cad 上五组全部 PASS。
- 审点 1（权限）：umask 022/027 下，已有 0644 文件安装后全部保持 0644；新建文件分别为 644/640；没有残留临时文件。
- 审点 3（Git 布局）：separate-git-dir 与 submodule 根安装都能登记 Space（写入 `worktree-space:`），`finish --merged` rc=0 并清理干净。
- 审点 4/5（续做与配置）：注入删分支失败后，按提示执行一次恢复命令，merged 与 archive 均 rc=0；分支已删，`branch.<名>.*` 已清，账本最后一行是最终动作行。OID 不符时拒绝续做，分支保留。
- 审点 6（警告）：worktree 模式派发时，不再出现「工人 tab 开在调用者 workspace」。
- 审点 2（真实闭环）：`/tmp/qwb-r2-real-9e9e7c9-evidence/` 记录了派发、工人提交、主控核对、合并、`finish --merged` 各步骤的命令和 rc，收尾前后的 Space 列表也有记录。

## 审点

### 1. HIGH（Standards）账本里出现非法 UTF-8 字节时，running 票从点名和值守中消失，主控不会被叫醒

- 触发（已在真实运行中发生）：r2 真实闭环里，pi 执行 `printf '%s\n' "done: … SHA=$FULL。…"`，bash 把变量名后紧跟的多字节句号吃掉半个，账本写进了 `\x80\x82`。本仓已有同类教训 `tasks/lessons/shell-变量后紧跟非ascii字符.md`：工人会犯这种错，运行时必须扛得住。
- 已证实（7ae8cad 安装副本，macOS 系统 sed/awk，UTF-8 locale）：
  - 使用 r2 原始账本 `ticket.raw.md`（`state: running`）时：`qwb-status.sh` 报 `sed: RE error: illegal byte sequence`，整张票不再列为「未结」；`qwb-wake.sh --dry-run` 报同样错误后输出「账本无未结项」；`qwb-lint.sh` 报 sed/awk 多字节错误，但仍显示 LINT PASS。
  - 最小复现：一张干净的 `state: running` 票只追加一行 `done: SHA=\x80\x82 ok`，结果与上面相同。
  - 对照组：`iconv -c` 去掉坏字节后，status 显示「[未结] … state=running」，wake 输出「未结项（将叫醒）」。
- 根因：`bin/qwb-lib.sh:9` 的 `qwb_task_state` 等账本读取在 UTF-8 locale 下用 sed/awk 解析，遇到非法字节即报错退出，已读到的输出也来不及写出；`bin/` 里没有任何 `LC_ALL` 设置。
- 后果：工人报 done 后，值守看不到这张票，主控永远不会被叫醒；点名也看不到它。这是静默失败，违背「失败关闭」。
- 修复方向：
  - 所有账本读取（state、末行、疑点、场景块、dispatch、worktree 记录，以及 status、wake、lint、run、worktree 里的同类解析）按字节处理，例如在这些调用上设 `LC_ALL=C`，或统一经过同一个安全读取函数。
  - 任何一张票解析失败时一律按「未结、需要主控查看」处理，不得当作已结丢掉。
  - lint 对含非法 UTF-8 的账本行给出明确提示，不能在检查中途报错后仍显示 PASS 却漏检。
- 测试要求：公开 CLI 层回归。state 行之后、done/working 行、场景块内、疑点行里各放一处非法字节，断言 status 列为未结、wake `--dry-run` 判定将叫醒、lint 不漏检也不崩溃、`qwb-run` 场景指纹与门判定不受影响。反转验证：在 7ae8cad 上变红，修复后变绿。

### 2. LOW（Spec）zcode 与 cmd 的工人启动文档已过时（使用者 2026-09-24 要求按当前最新版更新）

- zcode（2026-09-24 主控在 `qwbrev-iso3` 实测 zcode 0.16.9 + Herdr 0.9.1）：
  - 入口是 `zcode` 或 `zcode tui`；`zcodecli chat` 和 `zcodecli chat-open` 已不存在。
  - 在 pane 里启动 30 秒后，`herdr agent get <pane>` 仍返回 `agent_not_found`。前台进程为 `node`（argv0 `zcode-cli`），Herdr 不识别。本机也没装 `herdr-zcode` 插件，而且该插件的 TUI 入口只是 execv zcode，不上报状态。
  - 发出写文件任务后，界面停在「Approval required: Write」，默认选中 Deny，期间 Herdr 仍认不出它；`--help` 里没有免审批参数。
  - 因此，照 `zcode=pane-run:…` 配置派发，会在「pane-run 工人检测」超时失败。
- cmd：Command Code 1.65.0 同时提供 `cmd` 和 `cmdc`（同一个入口）；交互启动用 `cmdc --yolo --trust --skip-onboarding`，需要时加 `-m <模型>`。任何调用都可能自动升级全局安装，使用者已允许。Herdr 靠已安装的 `commandcode.integration` 插件（Command Code 钩子调用 `herdr pane report-agent`）识别它，标签为 `cmd`。
- 要改的位置：
  - `docs/DECISIONS.md` 第 368 行「zcode 归一」和第 407-408 行启动参数表，追加更正或新决定，不删历史结论。
  - `templates/worker-launch-guide.md` 第 8 行示例（改为 `cmdc`），并写明 zcode 目前的限制：Herdr 识别不了，且默认需要审批；在出现上报状态的集成之前，不能作为 pane-run 工人。
  - `tests/smoke.sh` §47 里把 `zcodecli chat` 当多词命令样例的地方，改用当前等价写法（如 `zcode tui` 或 `cmdc --yolo`），保持原测试意图。
  - 真录夹具不改。

## 真实 E2E（使用者 2026-09-24 要求；加强计划第 6 条）

- 使用者要求：
  - 真 Herdr、真工人，接受花费。
  - 主控用 Codex，`-m gpt-6-luna -c model_reasoning_effort=max`。
  - 工人：使用者 2026-09-24 最终确定只跑两种——devin + SWE-2（`--model swe-2-max`，免费额度）和 cmdc + deepseek V4 flash（`-m deepseek/deepseek-v4-flash`）。herdr 模式与 pane-run 模式各覆盖一个。
  - zcode：因上文审点 2 的限制，使用者确认不用 zcode，也不做集成；报告里写明原因。
- 已核实的前提：
  - named session 里的 pane 自带 `HERDR_SESSION=<名>` 和指向该会话的 `HERDR_SOCKET_PATH`，pane 内的 `herdr` 只看得到该会话。
  - pane-run 工人只要 Herdr 在该 pane 识别出任意 agent 就算启动成功，不要求工人名与 Herdr 标签一致。
  - 派给 claude 或 codex 工人时，`qwb-run.sh` 会写全局信任配置；本矩阵的两种工人都不会写。

### 交付物：`tests/e2e-real.sh`（不进 fast/full 门）

**用法**

- `bash tests/e2e-real.sh --worker devin|cmdc [--controller-model gpt-6-luna] [--controller-effort max] [--timeout-ms 2700000] [--report <新文件>] [--keep]`
- `--help` 写明：前提（已登录的 CLI）、花费、旁观方式（另开终端执行 `herdr --session <名>` 附着）。

**两个工人预设**，写在脚本里保证可复现，并与 `templates/worker-launch-guide.md` 一致：

| 预设 | 启动方式 | 参数 |
|---|---|---|
| devin | herdr | `--model swe-2-max --permission-mode dangerous --respect-workspace-trust false` |
| cmdc | pane-run | `cmdc --yolo --trust --skip-onboarding -m deepseek/deepseek-v4-flash` |

**隔离**

- 每次运行新建一个唯一名字的 named session，后台起 server。
- 脚本里每次 herdr 调用都强制使用该会话的 socket，并先用 `herdr status server` 核对；核对失败立即中止。
- EXIT trap 里 stop 并 delete 该会话；带 `--keep` 时保留会话并打印名字。
- 临时项目只能放在 `mktemp -d` 目录，不得放进任何真实项目目录。
- 不写任何全局配置文件。Codex 主控的目录信任用 `-c` 命令行覆盖；如果仍然弹出信任框，只对识别出的确定文本做处理，否则失败退出，不盲目按键。

**搭建**

- 建临时 Git 仓库并做种子提交；用被测候选的 `bin/qwb-init.sh` 在仓库根安装，并提交安装带来的改动。
- `qwbuddy/config.sh`：`QWB_WORKERS` 只含本次工人；门用确定性检查——FAST 检查文件存在，FULL 检查内容与 nonce 完全一致。
- `qwbuddy/workers.sh`：只声明本次工人。
- 写一张 `state: running` 的无害票：新增 `e2e/hello.txt`，内容恰为一行 `QWB E2E OK <nonce>`，然后提交；票里要有 Given/When/Then 场景，并包含失败路径场景。

**主控**

- 用 `herdr workspace create --cwd <项目>` 建主 workspace，在它的根 pane 里以交互方式启动 `codex -m <model> -c model_reasoning_effort=<effort> --dangerously-bypass-approvals-and-sandbox`。禁用 `codex exec`。
- 等到 idle，核对 TUI 上显示的模型和推理档；不符就判失败。
- 用一次 `pane run` 发送下面这段主控提示：

  > 你现在是 QW buddy。按 qwbuddy/QWBUDDY.md 开局；账本里的未结票派给 <worker> 工人（默认新建 worktree），按 Codex 宿主规则前台值守。工人报 done 后独立验收（跑 qwb-test.sh fast/full 并核对产出），合格则合并进 main、把 state 改为 verified、执行 qwb-worktree.sh finish <票> --merged。全部完成后单独输出一行 QWB_E2E_CONTROLLER_DONE；无法完成则输出 QWB_E2E_CONTROLLER_BLOCKED <原因>。

- 除此之外，脚本不能代替主控做任何派发、验收或收尾动作。

**监控**

- 按固定间隔记录 workspace list、各 agent 状态和账本末行（按字节读取）。
- 工人 pane 存在期间定期保存它的转录。
- 出现以下任一情况即结束等待：主控输出 DONE 或 BLOCKED；任一 agent 进入 blocked；超时。

**断言**（全部通过才返回 rc=0）

- a. 账本里有 `scenarios-fp:`、`worktree-space:`、`dispatch:`（worker 为本次工人）、工人的 `done:`、至少一条 `wake:`、`worktree: merged`，且 `state: verified`。
- b. main 上 `e2e/hello.txt` 的内容与 nonce 完全一致。
- c. 任务 worktree 目录已删、分支已删、`branch.<票>.*` 配置不存在。
- d. 运行期间观察到任务 Space：`is_linked_worktree=true`，`checkout_path` 是任务副本，`repo_root` 是项目根。工人 pane 的 `workspace_id` 等于该 Space。
- e. 收尾后的 workspace list 与派发前基线相比：任务 Space 已消失，主 workspace 还在，没有新增 workspace。
- f. 主控输出了 DONE，没有 BLOCKED。
- g. 只读核对 default 会话：没有任何 workspace 或 pane 指向临时项目路径。
- h. 账本若含非法 UTF-8，照实记录在报告里（此时仍须满足 a-g，用来验证审点 1 的修复）。

**报告**

- markdown 格式，内容包括：候选 SHA，各工具版本（herdr/codex/devin/cmdc），模型与推理档，会话名，临时目录，时间线，每条断言的 PASS/FAIL，转录文件路径，最终 rc。
- 报告文件必须事先不存在。

### 另需：`docs/DECISIONS.md` 追加一条决定

写明两点：真实 E2E 为什么不进 full 门（花钱、结果不确定、需要登录）；什么时候必须跑（合并生产相关改动前、装生产项目前）。

## 返修任务（执行者：Codex，gpt-6-sol / high）

- 工作目录、分支同前，起点 `7ae8cadfe2e826945b8bbfee70d0c894a20c1c26`。不开新分支，不 push，不合并。本报告随第一笔提交一并提交。
- 顺序：
  1. 先修审点 1，配回归测试并做反转验证。
  2. 再改审点 2 的文档与 smoke 样例。
  3. 然后写 E2E 脚本。
  4. 在代码定稿的 SHA 上依次运行 `--worker devin`、`--worker cmdc`，两轮串行，各得一份报告且 rc=0。
- 某个工人失败时，先判断属于哪一类：
  - QWB 缺陷：修复后，受影响的轮次全部重跑。
  - 脚本缺陷：修复后重跑。
  - 外部工具限制：不得绕开，也不得伪造通过；如实写成 BLOCKED 或「部分通过」，由主控裁决。
- 做法同 r1/r2：先读后写，最小实现，中文注释与报错风格，公开 CLI 层回归测试；smoke 新节加在「新节必须加在本行之前」之前，并核对它是 SMOKE PASS 前的最后一节。
- 约束：
  - default 会话只读。
  - E2E 在执行者自己的 Space（wGR）新开 tab 前台运行，方便使用者旁观；不用 nohup、launchd。
  - cmdc 的自动升级已获允许；其他 CLI 不主动升级。
  - 真实花费只限这两轮加必要重跑，每次运行前打印将使用的模型。
- 验收：
  - 提交后工作区干净。在最终 SHA 上运行 `bash bin/qwb-test.sh fast --project "$PWD"` 和 `bash bin/qwb-test.sh full --project "$PWD" --report /tmp/qwb-full-<SHA前7位>.md`；日志存 `/tmp/qwb-full-<SHA前7位>.log`；报告文件必须事先不存在。
  - E2E 在代码定稿的 SHA 上运行；之后的提交只允许改 `docs/reviews/`，用 `git diff --stat` 证明。
- 报告：写 `docs/reviews/2026-09-24-qwb-production-optimization-r3-execution.md`（逐项改动、测试名、红/绿证据、两轮 E2E 的报告路径与 rc、未验证项），与返修一起提交。最后单独输出一行 `QWB_PROD_OPT_R3_FIX DONE <完整SHA>` 或 `QWB_PROD_OPT_R3_FIX BLOCKED <原因>`。

**REVIEW_QWB_PRODUCTION_OPTIMIZATION_R3 AMEND**
