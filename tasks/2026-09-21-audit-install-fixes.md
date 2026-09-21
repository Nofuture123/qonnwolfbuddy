# 任务书：收敛审核修复 02——安装与派发五处（.gitignore / dispatch-rules 落点 / 母本仓双配置守卫 / 开局点名用 status / 重派复用工人）

```
任务 id:  audit-install-fixes
state:    verified
scenarios-fp: 976400aac2c088a3607d89adb3f5aa63221a2ac0
来源:     2026-09-21 主控收敛审核（docs/reviews/2026-09-21-收敛审核-opus.md 发现 P1-3/P1-4/P2-母本仓/token-开局）
派发:     主控 claude-opus-5（Claude Code，pane wF2:p3） → pi（zai-coding-cn/glm-5.3-flash）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-21-audit-install-fixes.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-install-fixes
分支:     audit-install-fixes
前置:     audit-runtime-fixes 已合并 main（9db9208）；本票基于该基线
```

## 0. 背景与范围

对照真实生产项目 `/Users/rocky/projects/qonnwolfai-student`（pnpm monorepo；根目录已有 `config/`（放的是 app 角色提示词）、`tasks/`（282 份规划文档，无 `state:`）、`tasks/lessons.md`）审出的安装问题。**先读**：`bin/qwb-init.sh`、`bin/qwb-dispatch.sh` 头注释、`tests/smoke.sh` §3 与 §49、`templates/QWBUDDY.md` §1。

### A. `qwb-init.sh` 写 `.gitignore`

现象：装进项目后 `.worktrees/<id>/`（内含嵌套 `.git` 文件）、`qwbuddy/.controller.lock/`、`qwbuddy/.watch`、`qwbuddy/.watch.lock/`、`qwbuddy/.hook.lock/`、`qwbuddy/.hook.err`（watch-invisible 新增）全是运行态，会污染生产项目 `git status`，主控验货时的脏检查也被干扰。

做法：`qwb-init.sh` 往 `<项目根>/.gitignore` 追加一段（幂等：已有 `# QW buddy 运行态` 标记行则跳过；文件不存在则新建）：
```
# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）
.worktrees/
qwbuddy/.controller.lock/
qwbuddy/.watch
qwbuddy/.watch.lock/
qwbuddy/.hook.lock/
qwbuddy/.hook.err
```
stdout 一行「写入：.gitignore 追加 QW buddy 运行态」/「跳过：.gitignore 已有」。

### B. `dispatch-rules.json` 落点移到 `qwbuddy/`

现象：`qwb-dispatch.sh` / `qwb-run.sh auto` 读 `<项目根>/config/dispatch-rules.json`；生产项目根的 `config/` 是 app 自己的目录，QW buddy 其余文件都在 `qwbuddy/` 下，只有这一个例外；且 `qwb-init.sh` 不拷模板，装完 `--worker auto` 永远 `no rules`。

做法：路径改为 `<项目根>/qwbuddy/dispatch-rules.json`（`bin/qwb-dispatch.sh` 的 `RULES_PATH`、`bin/qwb-run.sh` 的默认工人回退读取处、两处 `--help`/头注释、`templates/QWBUDDY.md` §4/§9 提到的路径、`docs/DECISIONS.md` 对应条目）；`qwb-init.sh` 拷 `templates/dispatch-rules.json` → `qwbuddy/dispatch-rules.json`（目标已有不覆盖，同 brief-include.md 做法）；`tests/smoke.sh` §49 里造规则文件的路径跟着改。**不做**旧路径兼容/回退（功能 2026-09-17 才合入、无外部安装）。

### C. 母本仓双配置守卫

现象：母本仓自己既有 `qwb.config.sh`（跟踪）又被主控开局建了 `qwbuddy/config.sh`（未跟踪，因为 `qwb-lock.sh`/`qwb-wake.sh` 要 `qwbuddy/` 目录）；`qwb-test.sh`/`qwb-lint.sh` 优先读后者——改前者的门不生效、无人知道。

做法：
1. 母本仓 `.gitignore` 加 `qwbuddy/`（母本仓不给自己装 qwbuddy/，该目录只是主控运行态；`docs/DESIGN.md` §8.2 或 §1「安装」行补一句说明）。
2. `bin/qwb-lint.sh` 第 3 项之前加一条母本仓布局专属检查（只在 `templates/QWBUDDY.md` 布局下启用）：`qwb.config.sh` 与 `qwbuddy/config.sh` 同时存在时，两者的 `QWB_GATE_FAST`/`QWB_GATE_FULL` 值必须相同，否则 FAIL 并打印两边的值。

### D. 开局点名改用 `qwb-status.sh`（省 token）

现象：`templates/QWBUDDY.md` §1 第 2–5 步让主控「列出 tasks/ 下全部任务书，读每份头部 state:」——生产项目 `tasks/` 有 282 个文件，模型自己 cat 一遍是纯浪费；`qwb-status.sh` 已经给出未结项 + 最近状态行 + 规格疑点 + 值守健康。

做法：§1 第 2–5 步合并为：「跑 `bash qwbuddy/bin/qwb-status.sh`：它列出未结项（`[未结]`）、每张的最近状态行与未处理的规格疑点；**只读未结项那几份任务书**的末尾状态行，搞清活到哪了；向使用者报告」。`templates/claude-hook.md` / `agents-hook.md` 第 2 条同步改为「开局先跑 qwb-status.sh」。不改任何脚本。

### E. 返工重派复用既有工人，agent start 失败不留副作用

现象：2026-09-21 主控对 audit-runtime-fixes 返工重派：原工人 agent `qwb-audit-runtime-fixes`（pane wF2:pA，状态 done/idle）还在，`herdr agent start` 报 `agent_name_taken`，但 `qwb-run.sh` 此前已写 `dispatch:` 行并新开了 tab——留下一条死 dispatch 与一个空 tab；且错题本已有「执行者产物的修订退回执行者窗口」，重派却总是新开窗口。

做法（`bin/qwb-run.sh`，herdr 模式；pane-run 模式不动）：
1. 在开 tab 之前 `herdr agent get <NAME>`（或 `agent list` 按 name 匹配）：同名 agent 存在且 `agent_status` ∈ {idle, done} → **复用**：不建 tab、不 `agent start`，`dispatch:` 行的 pane 写它现有的 pane，直接 `herdr agent prompt <NAME> "<提示词>"`（提示词前加一句「这是返工/续派，读主账本末尾主控最新一条 working: 行」）；stdout「复用既有工人 <NAME>（pane …）」。同名 agent 存在但 `working`/`blocked` → 拒绝派发并提示（工人还在干，别打断）。查询失败 → 拒绝（fail-closed）。
2. 新开路径：`herdr agent start` 失败 → 关掉刚建的 tab（`herdr tab close`）、把刚追加的 `dispatch:` 行去掉（只删最后一行且必须是本次写的那行，行数回到写前）、exit 1 并打印 herdr 原始错误。

**白名单**：`bin/qwb-init.sh`、`bin/qwb-dispatch.sh`、`bin/qwb-run.sh`（dispatch-rules 路径、帮助文本、§E 复用/回滚）、`tests/fixtures/herdr/`、`bin/qwb-lint.sh`、`.gitignore`（母本仓）、`templates/QWBUDDY.md`、`templates/claude-hook.md`、`templates/agents-hook.md`、`docs/DESIGN.md`、`docs/DECISIONS.md`、`tests/smoke.sh`。**不许动**：`bin/qwb-wake.sh`、`bin/qwb-lock.sh`、`bin/qwb-worktree.sh`、`templates/roles/*`、`templates/TASK.md`。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### init 写 .gitignore 且幂等

Given 临时项目已有 `.gitignore`（含别的条目）
When  `qwb-init.sh` 跑两次
Then  `.gitignore` 原有条目字节不变；QW buddy 段恰好出现一次，含 `.worktrees/` 与 `qwbuddy/.controller.lock/`；另一临时项目无 `.gitignore` 时被新建

### init 后 git status 干净（失败路径反证）

Given 临时 git 项目装完 QW buddy 并提交；随后 `qwb-lock.sh acquire`、`mkdir -p .worktrees/x`
When  `git status --porcelain`
Then  不含 `.worktrees` 与 `.controller.lock`；把 `.gitignore` 的 QW buddy 段删掉后再跑则**出现**（证明段落有效）

### dispatch-rules 新落点

Given 临时项目装完 QW buddy
When  查看 `qwbuddy/dispatch-rules.json`；再跑一次 init
Then  文件存在且与 `templates/dispatch-rules.json` 字节相同；先改它再跑 init 不被覆盖；`qwb-dispatch.sh`（有 key、stub curl，沿 §49 写法）读的是该路径；旧路径 `config/dispatch-rules.json` 存在而新路径不存在时报 `no rules`（不读旧路径）

### 母本仓双配置守卫

Given 母本仓布局的临时副本，`qwb.config.sh` 与 `qwbuddy/config.sh` 的 `QWB_GATE_FULL` 不同
When  `qwb-lint.sh`
Then  FAIL 且输出两边的值；改成相同后 PASS；只有一份配置时该项不报

### 重派复用既有工人

Given stub `herdr agent get qwb-t` 返回 idle 的同名 agent（pane wX:p5）
When  `qwb-run.sh --task t --worker pi --here`
Then  stub 日志无 `tab create`、无 `agent start`，有 `agent prompt qwb-t …`；新 `dispatch:` 行 `pane=wX:p5`；stdout 含「复用既有工人」

### 同名工人仍在干则拒绝（失败路径）

Given 同上但 agent 状态 `working`
When  派发
Then  退出非 0；任务书无新 `dispatch:` 行；stub 日志无 prompt/start/tab create

### agent start 失败不留副作用（失败路径）

Given 无同名 agent；stub 让 `agent start` 返回 `agent_name_taken` 错误（fixture 新增真录）
When  派发
Then  退出非 0；任务书行数与派发前一致（无残留 dispatch 行）；stub 日志有 `tab close <刚建的 pane 所属 tab>`

### 开局点名文案

Given `templates/QWBUDDY.md`、两份 hook 模板
When  grep
Then  §1 含「qwb-status.sh」且不再含「读每份头部」；两份 hook 第 2 条含「qwb-status.sh」；`qwb-lint.sh` 第 1 项仍 PASS

## 2. 硬约束

- 只用 Herdr；零通知使用者；bash 3.2 兼容；shellcheck 干净；零新依赖。
- 不改 `dispatch:`/`wake:` 行格式；不加 config 键。
- 最小实现，不顺手重构。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`
- 全门：`bash bin/qwb-test.sh full`
- 主控另跑：`bash tests/smoke.sh` 两次；在 `/Users/rocky/projects/qonnwolfai-student` 的**临时副本**（`git worktree` 或 cp）上跑一次 `qwb-init.sh` 看 `.gitignore`/`qwbuddy/dispatch-rules.json` 落点，不动真项目。
- 完成前 `git merge main` 到本分支并解决冲突，保证主控能 fast-forward。

## 4. 报告要求

往主账本绝对路径追加 `working:` / `done:`（含跑了什么命令与原始结果、PASS 数、HEAD sha）/ `blocked:` / `needs-decision:`。**不要改本文件的 `state:` 字段。**
票有缺陷用 `blocked: spec-defect: <条款；反例；照做会错在哪>`（列首写）。

## 5. 本票不允许做的事

- 不动真实生产项目 `/Users/rocky/projects/qonnwolfai-student` 的任何文件。
- 不给旧规则路径做兼容层。
wake: 2026-09-21T19:30:18Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T20:00:28Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T20:30:39Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T21:00:48Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T21:31:00Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T22:01:29Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
wake: 2026-09-21T22:31:38Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
working: 2026-09-21T22:45:00Z 主控派发说明：与 watch-invisible-pi 并行（它改 qwb-init.sh/qwb-status.sh/templates/QWBUDDY.md/smoke/DECISIONS 的不同段落）。**完成前先 `git merge main` 到本分支解冲突，smoke 新节号接在现有最大号 66 之后；新节必须加在 smoke.sh 收尾判定（SMOKE PASS; exit 0）之前，done: 行贴输出最后一个节标题与 PASS/FAIL 计数**（上一票执行者把新节加到 exit 0 之后，十节从未执行仍自述全绿——别重蹈）。
dispatch: 2026-09-21T22:38:52Z worker=pi agent=qwb-audit-install-fixes pane=wF2:pC dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-install-fixes
wake: 2026-09-21T22:40:36Z state=running fp=bf93e099e7b17cbc60db76f3b90fd84873a7dab9
working: 2026-09-21T23:05:00Z 工人开工：规格与点名文档已完整读（qwb-init/dispatch/run/lint/status、QWBUDDY.md、smoke §3/§49/§57-66、fixtures、herdr CLI agent get/tab close 已实测）；五处改动点已定位，先写 smoke 场景（新节 67-70，加在 SMOKE PASS 判定之前），再改实现
wake: 2026-09-21T22:48:38Z state=running fp=a3c82e564c26f7f7fd934506f2c6497aaf789592
done: 2026-09-21T23:55:00Z 五处全部落地于 worktree audit-install-fixes（HEAD=8e471d9c8544aa6919fddddc52527be3b55a69a9，12 文件 +447/−80，全部在票内白名单，qwb-wake/lock/worktree/roles/TASK.md 未触碰，git status 干净）。改动：A=init 写 .gitignore（标记行幂等、只追加、无文件新建）；B=dispatch-rules 落 qwbuddy/（dispatch.sh RULES_PATH+头注释、run.sh auto 回退+帮助、QWBUDDY.md §4/§9、init 拷模板不覆盖、smoke §49 全部路径迁移，无旧路径兼容）；C=母本仓 .gitignore 加 qwbuddy/ + lint 新第 3 项双配置质量门一致（仅母本仓布局，单配置连标题都不打印），原 3-8 项顺延为 4-9；D=QWBUDDY.md §1 第 2-5 步合并为跑 qwb-status.sh 只读未结项（含工人丢失重派指引），两份 hook 第 2 条同步，未改脚本；E=qwb-run.sh herdr 模式开 tab 前按名查 agent（idle/done 复用不建 tab 不 start、prompt 前加返工/续派说明、stdout「复用既有工人」；working/blocked 拒绝；查询失败 fail-closed），agent start 失败关刚建 tab（tab close <root_pane.tab_id>）+回滚 dispatch 行（只删最后一行且必须字节等于本次写的行，行数自检回到写前）+exit 1 原样上报原始错误；为此 brief-include 追加上移到 dispatch 之前（新不变量：dispatch 恒为启动工人前最后一行），smoke §50 顺序断言相应更新。跑过的检查与原始结果：bash bin/qwb-test.sh fast → rc=0；bash bin/qwb-test.sh full → rc=0（末三段 SMOKE PASS + REVIEW-IDENTITY PASS + LINT PASS）；bash tests/smoke.sh → 末节标题「== 70. 开局点名改用 qwb-status.sh（省 token）==」其下 5 项全 PASS，总计 560 PASS / 0 FAIL（基线 539，新增 21：§67×10/§68×3/§69×3/§70×5，其余为 §50 顺序不变量 +1 的重排）；shellcheck bin/*.sh → 0 告警；git merge main → Already up to date（main=9db9208 已是本分支祖先，主控可直接 fast-forward）；生产项目 mktemp 临时副本（未动真项目）跑 qwb-init.sh：stdout「写入：.gitignore 追加 QW buddy 运行态」，原 node_modules/、dist/ 条目字节不变，qwbuddy/dispatch-rules.json 与模板 cmp 字节相同，config/（app 自己的目录）未被触碰。fixture 新增真录 tests/fixtures/herdr/agent-start-name-taken.json（本机 herdr 实录：tab create 临时 pane → 同名二次 agent start → 捕获 stderr 原始字节 → tab close 录完即清，agent get 复查 not_found 确认无残留）。
wake: 2026-09-21T23:12:45Z state=running fp=3516c4560152812967dea97959e74638e363be8f
working: 2026-09-21T23:16:00Z 主控验货（独立复跑于 worktree 8e471d9）：`qwb-test.sh fast` rc=0；`tests/smoke.sh` rc=0、560 PASS / 0 FAIL，末节「== 70.」后 SMOKE PASS；`qwb-lint.sh` LINT PASS；diff main 12 文件 +447/−80 全在白名单；main 可 fast-forward。读码：复用既有工人按名 agent get → idle/done 复用、working/blocked 拒绝、查询失败 fail-closed；start 失败关 tab + 只删本次写的 dispatch 行；brief-include 上移到 dispatch 之前以保「dispatch 恒为启动前最后一行」不变量。反转：把 undo_dispatch_line 换成 true → §69「回滚路径不对」变红，恢复后 shasum aa266162… 一致、工作树干净。结论：通过，state → verified，fast-forward 合并。
worktree: merged branch=audit-install-fixes tag=-
