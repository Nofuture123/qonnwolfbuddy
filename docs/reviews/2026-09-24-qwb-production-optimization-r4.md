# 生产接入前优化 收尾审核 r4

结论：r3 的 HIGH（账本里的非法 UTF-8）已修复，并独立复验通过。两轮真实 E2E 也已通过：devin + SWE-2、cmdc + deepseek，主控 Codex gpt-6-luna / max。

复验中发现 3 个问题：

1. MEDIUM，r3 引入的回归：全局 `LC_ALL=C` 让唤醒摘要按字节截断，Herdr 拒收，循环值守从此一直叫不醒。
2. LOW：工人名推导依赖 locale；另外，标准日期前缀的中文票会大量重名。重名是旧缺陷，r3 使它更严重。
3. LOW：文档没有随 r3 的新行为更新。

**Standards AMEND；Spec AMEND**。审核者是 Claude Code（Opus 5.5，Herdr pane `wF2:p3`）。

## 冻结对象

- 候选 `0abb697cdc7715bacdb86632ed5c6fd3042e283e`，代码定稿 `a08c7fdbb1cd3652d63ad9243707943fe5474401`，基线 846fcce。候选与代码定稿之间只差 r3 执行报告。
- 真实 Herdr 实验只在 named session `qwbrev-iso3` 中进行，规则同 r2。

## r3 复验（通过）

- **full**：在 0abb697 的导出副本上独立运行。
  - FULL_RC=0，662 条 PASS，0 FAIL。
  - §82「R3 损坏账本仍可点名和值守」是 SMOKE PASS 之前的最后一节。
  - REVIEW-IDENTITY、LINT 均为 PASS。
  - 节标题与 `/tmp/qwb-full-0abb697.log` 一致。
- **审点 1（非法 UTF-8）**：用 r2 真实闭环的原始账本和最小复现（`done: SHA=\x80\x82 ok`）复验，三项都符合预期。
  - status 列出「[未结] … 账本 UTF-8 损坏，须主控查看」。
  - wake `--dry-run` 判定将叫醒，状态为 needs-decision。
  - lint 明确 FAIL。
- **审点 2（zcode/cmd 文档）**：
  - DECISIONS 已追加更正，`templates/worker-launch-guide.md` 与 smoke §47 的样例已按当前版本改写。
  - 活文档里只剩一处 `zcodecli`，就是「旧写法已失效」的说明本身。
- **真实 E2E**：
  - 报告 `/tmp/qwb-e2e-devin-a08c7fd.md` 和 `/tmp/qwb-e2e-cmdc-a08c7fd.md` 的候选都是 a08c7fd，9 条断言全部 PASS，rc=0。
  - 我另外直接核对了两个临时项目的账本和 Git 状态。
- **全局配置**：`~/.codex/config.toml` 里已没有 qwb-e2e 条目；清理 diff 只删了 4 个块（`/tmp/qwb-r3-config-cleanup.diff`）。

## 审点

### 1. MEDIUM（Standards）r3 的全局 `LC_ALL=C` 让唤醒摘要按字节截断成非法 UTF-8，Herdr 拒收，循环值守一直叫不醒

**位置**

- `bin/qwb-wake.sh:532` 的 `"${last:0:160}"`。
- r3 在 5 个入口脚本开头加了 `export LC_ALL=C`（lint/run/status/wake 在第 4 行，worktree 在第 6 行）。从此 bash 子串按字节而不是按字符截取。
- `collect_due` 上方的注释写的是「最后状态行原文截160字符」，说明原意是按字符截。

**已证实**（0abb697 安装副本，Herdr 0.9.1，`qwbrev-iso3`）

- Herdr 拒收非法 UTF-8 参数：
  - 命令：`herdr pane run <pane> "$(printf 'echo A \xe6\x9c\xaa\xe6\x94\xb9\xe5')"`
  - 结果：`error: argument 4 is not valid UTF-8`，rc=2。
- 末行过长时投递失败：
  - 条件：票的末行是一条 229 字节的中文 `working:` 行。
  - 命令：`qwb-wake.sh --once --pane <pane>`，连跑两轮。
  - 结果：两轮报同一个错误，随后输出「错误：投递失败（pane …）：本轮 1 张票一行 wake 都不写、保持未叫，下轮重试」，rc=0，wake 行数不变。
  - 下一轮会拼出同一条消息，所以永远失败。
- 末条状态行本身含坏字节时同样失败：
  - 条件：末条状态行是 `done: 已提交 SHA=\x80\x82 请验收`，正是 r3 审点 1 的场景。
  - 结果：同样投递失败。r3 的修复只做到「列为未结」，走循环路径时仍然叫不醒。
- `--block` 路径不受 Herdr 拒收影响，但摘要已损坏：
  - 三种宿主的正式入口都走这条路径：Claude Code Stop hook、pi 扩展、Codex 前台循环。
  - 摘要打到 stdout，不经过 herdr 的参数校验，所以仍能叫醒。
  - 但摘要本身是坏的 UTF-8，实测结尾是 `…未改\xe5`。各宿主如何显示这些坏字节，没有逐一核实。

**影响**

- 一轮只发一条投递，所有要叫的票拼在同一条消息里。只要其中一张票被截断在字符中间，或者含坏字节，这一轮所有票都叫不醒，而且每一轮都会重复失败。
- 中文账本里超过 160 字节（约 53 个汉字）的状态行很常见。

**根因**

- r3 为了让账本按字节解析，在全局设了 `LC_ALL=C`，顺带改变了所有按字符处理文本的语义。
- 我对 5 个入口脚本和 `qwb-lib.sh` 做了全量排查，受影响的只有两处：本处，以及审点 2 的 `cut -c1-32`。
- 其余操作不受影响：`grep -i`、`tr`、`sort`、`printf` 宽度和方括号表达式，要么在两种 locale 下结果相同，要么只处理 ASCII。

**修复方向**（推荐）

- 保留按字节解析，r3 的修复不能退。
- 在 `qwb-lib.sh` 里加一个共用函数：按 UTF-8 字符截断，并把非法字节序列替换成 U+FFFD 或 `?`。perl Encode 已经是现有依赖（见 `qwb_ledger_utf8_ok`）。
- 唤醒摘要一律经过这个函数，保证最终文本是合法 UTF-8，且不超过 160 个字符。循环与 `--block` 共用 `collect_due`/`compose_msg`，改一处两边都生效。
- 在 `docs/DECISIONS.md` 追加一条规定：入口脚本在 `LC_ALL=C` 下运行；凡是按字符处理用户文本，或者把账本文本交给 herdr 的地方，都必须经过这个共用函数。
- 如果执行者认为把 `LC_ALL=C` 收窄到解析调用更好，也可以这样做，但要在执行报告里写明理由，并满足下面全部验收。

**测试要求**

- 做公开 CLI 层回归。测试用的假 herdr 必须像真 Herdr 0.9.1 一样拒收非法 UTF-8 参数（报错，rc≠0），否则测不出这个缺陷。
- 覆盖两种账本：
  - a) 末行是超过 160 字节的中文，并且第 160 字节落在某个字符中间。
  - b) 末条状态行含 `\x80\x82`。
- 两种情况都要断言：
  - `--once` 投递成功，写入 wake 行，投递的文本是合法 UTF-8。
  - `--block` 的 stdout 同样是合法 UTF-8。
  - a) 的摘要恰好是前 160 个字符。
- 反转验证：在 0abb697 上变红，修复后变绿。
- 真实 Herdr 复放：
  - 在执行者自建的 named session 里做，不用 default，也不用 `qwbrev-iso3`。
  - 用一个普通 shell pane 当主控目标，对 a) 和 b) 各跑一次 `--once`。
  - 记录命令、rc 和 wake 行，并用 `pane read` 核对 pane 收到的文本。
  - 跑完后 stop 并 delete 这个会话。

### 2. LOW（Standards）工人名推导依赖 locale，标准日期前缀的中文票大量重名

**位置**

- `bin/qwb-run.sh:237-244`：先 `cut -c1-32 | tr … | tr -cd 'a-z0-9_-'`；只有剩下的字母数字少于 3 个时，才兜底为 `qwb-<sha1 前8位>`。

**已证实**

- 名字依赖 locale（r3 回归）。同一个 id 在 UTF-8 和 C 下得到不同的名字：

  | 输入 | UTF-8 | C |
  |---|---|---|
  | `qwb-修复登录页面的问题-login-fix` | `qwb--login-fix` | `qwb--`，再兜底成哈希 |
  | `qwb-2026-09-24-首页轮播图改为可配置并补测试-carousel` | `qwb-2026-09-24--ca` | `qwb-2026-09-24-` |

  r3 之前，名字取决于调用者的 locale。
- 大量重名（旧缺陷，r3 使它更严重）：
  - 兜底只看「剩下的字母数字少于 3 个」。但标准任务 id 带 `YYYY-MM-DD-` 日期前缀，天然有 8 个数字，兜底永远不会触发。
  - 本仓 `tasks/` 里的 48 张真票在 UTF-8 下推导出 3 组重名：`qwb-2026-09-15--` 5 张，`qwb-2026-09-15-qwbuddy-` 8 张，`qwb-2026-09-15-fable-` 2 张。在 C 下，qwbuddy 那组还会再多一张。
  - 第 239-241 行的注释写明，兜底的本意就是防止两张票同名。

**后果**

- 同一天的两张中文票都派给 herdr 模式工人（devin、pi）时，只要前一张的工人还在，后一张就会被拒，报错「同名工人…拒绝认领/拒绝复用，请换 --name」。
- 这是失败关闭，不会写坏数据。但生产里同一天并行多张中文票是常态，主控只能反复手工加 `--name`。

**修复要求**

- 名字推导与调用者的 locale 无关。
- 纯 ASCII 的任务 id，推导结果与现在逐字节一致，不打扰已有安装。
- 含非 ASCII 字符的 id：
  - 按字符截取，保留其中可读的 ASCII 部分。
  - 再加上完整任务 id 的哈希短码，保证不同 id 得到不同的名字。
  - 总长不超过 32，只含 `[a-z0-9_-]`。
- 显式给出 `--name` 时，ASCII 输入的结果不变。

**测试要求**（公开 CLI 层）

- 调用者分别在 `LC_ALL=C` 和 `LANG=en_US.UTF-8` 两种环境下派发同一张中文 id 的票，得到的名字相同。
- 同一天的两张中文票得到不同的名字。
- ASCII id 的名字与修复前一致。
- 做反转验证。

### 3. LOW（Spec）非法 state 的行为说明没有随 r3 更新

- `templates/QWBUDDY.md:32` 仍写着：「写了非 5 值域的值（如 `pending`）等于静默丢弃：`qwb-status.sh` 标 `[非法]`、`qwb-wake.sh` 警告且不叫」。
  - r3 之后的实际行为是：status 列出「[未结] … 状态异常，须主控查看」；wake 按 needs-decision 叫主控；qwb-run 拒绝派发；lint FAIL。
  - 这份文件会装进生产项目，是主控的操作手册。
- `bin/qwb-wake.sh:11` 的帮助只写了「未结项 = state ∈ {running, blocked, needs-decision}」，没有提到非法 state 和 UTF-8 损坏也按 needs-decision 计入。
- 改法：
  - 按实际行为改写这两处。
  - 给主控的规矩不变：state 仍然只用五个值。
  - 如果有 lint 或 smoke 断言引用了原句，一并更新。

## 返修任务（执行者：Codex，gpt-6-sol / high）

**起点**

- 工作目录、分支同前，起点 `0abb697cdc7715bacdb86632ed5c6fd3042e283e`。
- 不开新分支，不 push，不合并。
- 本报告随第一笔提交一起提交。

**顺序**

1. 修审点 1 和审点 2，配回归测试并做反转验证。
2. 改审点 3 的文档。
3. 做审点 1 要求的真实 Herdr 复放。
4. E2E 小改：
   - 票名改成含中文的 id，例如 `tasks/2099-01-01-真实闭环-e2e.md`，让真实闭环也覆盖中文工人名、分支和 Space。
   - devin 那一轮加一条断言：`dispatch:` 行里的 `agent=` 等于按新规则推导出的名字。
5. 在代码定稿的 SHA 上依次运行 `--worker devin` 和 `--worker cmdc`：两轮串行，各得一份报告，rc=0。

**失败分类**（同 r3）

- QWB 缺陷：修复后重跑受影响的轮次。
- 脚本缺陷：修复后重跑。
- 外部工具限制：如实写成 BLOCKED 或「部分通过」。

**做法**（同 r3）

- 先读后写，最小实现，中文注释和报错风格，公开 CLI 层回归。
- smoke 新节加在「新节必须加在本行之前」这一行之前，并核对它是 SMOKE PASS 之前的最后一节。

**约束**（同 r3）

- default 会话只读。
- E2E 在 wGR 里新开 tab 前台运行。
- 不写全局配置：跑前跑后比对 `~/.codex/config.toml`，做法同 r3。
- 真实花费只限这两轮，加上必要的重跑。

**验收**

- 提交后工作区干净。
- 在最终 SHA 上跑 fast，再跑 `full --report /tmp/qwb-full-<SHA前7位>.md`，日志存到 `/tmp/qwb-full-<SHA前7位>.log`。报告文件必须事先不存在。
- E2E 在代码定稿的 SHA 上运行。之后的提交只允许改 `docs/reviews/`，用 `git diff --stat` 证明。

**报告**

- 写 `docs/reviews/2026-09-24-qwb-production-optimization-r4-execution.md`，与返修一起提交。内容包括：
  - 逐项改动；
  - 测试名；
  - 红/绿证据；
  - 真实复放记录；
  - 两轮 E2E 的报告路径与 rc；
  - 未验证项。
- 最后单独输出一行 `QWB_PROD_OPT_R4_FIX DONE <完整SHA>` 或 `QWB_PROD_OPT_R4_FIX BLOCKED <原因>`。

**REVIEW_QWB_PRODUCTION_OPTIMIZATION_R4 AMEND**

## 更正（2026-09-24T02:38:40Z，验收时追加，原文保留）

**1. 审点 2 的重名分析用错了输入**

`bin/qwb-run.sh:104` 在得出任务 id 时会去掉日期前缀（`sed 's/^[0-9][0-9-]*-//'`）。所以默认名是 `qwb-<去掉日期后的主题>`，不是 `qwb-<完整文件名>`。据此更正如下：

- 「标准任务 id 带日期前缀，天然有 8 个数字，兜底永远不会触发」这一说法不成立。纯中文主题会正常兜底成哈希名，不会重名。
- 实际的重名机制：中文主题里夹着 3 个以上 ASCII 字母或数字时（如 `qwbuddy返修-…`、`fable终审-…`），净化后只剩这段 ASCII，数量已达到兜底门槛，不会触发兜底。结果是 ASCII 片段相同的票，不论是不是同一天，都会同名。
- 按正确的输入重算本仓 48 张真票：
  - 共有 2 组、10 张重名：`qwb-qwbuddy-` 8 张，`qwb-fable-` 2 张。UTF-8 与 C 下结果相同。
  - locale 差异对这 48 张票一张都不改变。它只出现在中文段较长、后面才接 ASCII 的 id 上，例如 `修复登录页面的问题-login-fix`。
  - 表中第二个例子带 `2026-09-24-` 前缀，实际不会出现这样的输入。
- 「同一天的两张中文票」应改为「ASCII 片段相同的中文票（不限同一天）」。
- 结论和修复要求不变。在 d807f27 上按正确输入复核：
  - 29 个 ASCII id 的名字与修复前逐字节一致。
  - 55 个 id（48 张真票加 7 个构造例）没有任何重名。
  - UTF-8 与 C 两种 locale 下结果相同。

**2. 「r3 复验」对全局配置的说法不准确**

原文说 `~/.codex/config.toml` 里已没有 qwb-e2e 条目，这不准确。准确情况是：

- r3 测试写入的 4 个条目已经删除。
- 更早之前就存在的临时条目还在，例如 `/private/tmp/qwb-e2e-codex`，清理前的备份里第 504 行已有这一条。
- 这些旧条目是否清理，由使用者决定。
