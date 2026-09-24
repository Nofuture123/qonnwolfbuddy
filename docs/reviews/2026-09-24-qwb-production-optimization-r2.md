# 生产接入前优化 收尾审核 r2

结论：r1 三个审点已修复并独立复验通过（见「r1 复验」）。收尾前按计划全量清点，剩余 Standards 3 项、Spec 3 项，**Standards AMEND；Spec AMEND**，本轮一次修完后再验收合并。审核者为 Claude Code（Opus 5.5，Herdr pane `wF2:p3`）。

## 冻结对象与证据

- 需求：`docs/plans/2026-09-23-production-optimization.md`；基线 `846fccea0c34c204e388e37886f49f71c1af5222`；候选 `87222a2dca8fb649b85128b47650921b3806f2da`（分支 `qwb-production-optimization`），审核期间工作区干净。
- 真实 Herdr 实验只在 named session `qwbrev-iso2`、`qwbrev-iso3` 中进行：包装脚本强制 `HERDR_SOCKET_PATH` 指向该会话、清空 `HERDR_PANE_ID/TAB_ID/WORKSPACE_ID`，并先用 `herdr status server` 核对 socket。`qwbrev-iso2` 已 stop 并 delete；default 会话仍是 20 个 workspace，没有任何 workspace 指向实验目录。

## r1 复验（通过）

- full：在 87222a2 导出副本上独立运行 `bash bin/qwb-test.sh full --project <副本>`，FULL_RC=0，耗时 169s；SMOKE / REVIEW-IDENTITY / LINT 均 PASS，659 条 PASS、0 FAIL。节标题与 `/tmp/qwb-full-87222a2.log` 逐行一致，§80 是 SMOKE PASS 之前的最后一节。
- 审点 1：
  - 仓库根安装，注入「open 后第一次 workspace list 失败」：派发 rc=1，QWB 调用 `workspace close` 关掉了新 Space，任务书 `cmp` 不变；随后 `finish --merged` rc=0。
  - 子目录安装：在创建副本和 `worktree open` 之前就拒绝（rc=1），没有新 Space、分支或目录。
  - 手工为子目录项目的副本打开 Space（repo_root 为 Git 根）后执行 `finish --merged`：rc=1，报「repo_root 与项目根不符」，副本、分支、Space 均保留。
- 审点 2：
  - 变异测试：把 `worker_tab` 改成取 workspace ID，`tests/worktree-space.py` 拦下（rc=1）。
  - 真实 Herdr 正例：按 QWB 格式手写 `worktree-space:` 与 `dispatch:`，工人 tab 在本 Space，`finish --merged` rc=0。调用顺序：pane get → tab list → pane list → process-info ×2 → workspace close → git worktree remove → update-ref -d <OID>。
  - 真实 Herdr 反例：工人 pane 在别的 workspace，rc=1「工人 pane 不在本票 Space」，没有关闭，也没有删除。
- 审点 3：
  - 注入 worktree remove 失败：partial 行带 `oid=` 并输出恢复命令，原样执行 rc=0，归档完成，标签不变。
  - 注入 update-ref 失败：输出 `update-ref -d … <OID>`，执行后分支删除。
  - 同名标签指向别的提交：拒绝，不删除任何东西。

## 审点

### 1. MEDIUM（Standards）安装器把生产项目已有的 `.claude/settings.json` 改成 0600；新建的根目录文件不按 umask 建立

- 位置：
  - `bin/qwb-init.sh:397-402`：Python 用 `tempfile.mkstemp` 生成 0600 临时文件，再 `os.replace` 覆盖目标，已有文件和新文件都变成 0600。
  - `bin/qwb-init.sh:265`、`301-304`：`.gitignore`、`AGENTS.md`、`CLAUDE.md` 不存在时，直接把 0600 的 mktemp 临时文件改名到位。
- 已证实（umask 022）：
  - 已有 0644 的 `.gitignore`、`AGENTS.md`、`CLAUDE.md`、`.claude/settings.json` 安装后，前三个保持 0644，`settings.json` 变成 0600。
  - 空项目安装后，这四个文件全是 0600；同一次从模板复制的 `qwbuddy/*`、`.pi/extensions/qwb-watch.ts` 是 0644。
- 附带：`append_hook`（`301-304`）在 `cp -p`、追加或 `mv` 失败时直接 `return 1`，不删临时文件；在 `set -e` 下会留下 `.qwb-hook.*`。
- 后果：安装会悄悄收紧生产项目已有文件的权限，新文件也不遵守 umask。Git 只记录可执行位，`git diff` 看不出来，但同机其他用户、容器或不同 UID 的 CI 读取会失败。
- 修复方向：替换已有文件时保留原权限位；新建文件按 `0666 & ~umask`；失败路径删除本次临时文件。

### 2. MEDIUM（Spec 计划第 6 条）最终 SHA 缺少真实工人闭环

- 计划第 6 条要求：在隔离 Git 项目安装冻结候选，用默认新建 worktree 派发一个无害任务，确认 Space、工人会话、账本、主控独立验收和收尾，收尾前后对比 workspace list；返修产生新 SHA 后，要对最终 SHA 重跑受影响的真实步骤，交付证据只认最终 SHA。
- 现状：r1 执行记录写明「完整工人闭环未实跑」。派发和收尾代码在 r1、r2 都有改动，属于受影响的真实步骤。
- 要求：在代码定稿的 SHA 上完成一次真实闭环，具体见「返修任务」。

### 3. LOW（Spec 计划第 3 条）主工作树根判定误拒 separate-git-dir 和 submodule 布局，报错给出错误路径

- 位置：`bin/qwb-run.sh:502-508`，把 `dirname(--git-common-dir)` 当作主工作树根。
- 已证实：
  - `git init --separate-git-dir` 的仓库根安装、submodule 根安装，各派发一次均 rc=1。报错里的「主工作树根」是 gitdir 的父目录（`…/layout`、`…/super/.git/modules`），且未建副本。
  - 真实 Herdr 0.9.1 对这两个布局执行 `worktree open --cwd <根> --path <根>/.worktrees/x` 都成功，`repo_root` 分别等于项目根（`sep`、`super/sub`）。也就是说 Herdr 支持，只有 QWB 判断错了。
  - `git worktree list --porcelain` 的首行在这两种布局下给出的是 gitdir，不能用来当主根。
- 修复方向：主工作树根的判定改为同时满足两条——`rev-parse --show-toplevel` 的物理路径等于项目根；`--absolute-git-dir` 与 `--path-format=absolute --git-common-dir` 的物理路径相同（即当前不在 linked worktree 中）。子目录安装和 linked worktree 根仍须拒绝，报错写出真实原因。

### 4. LOW（Spec 计划第 4 条）`branch-delete` 阶段按提示恢复后，任务书停在 partial

- 位置：`bin/qwb-worktree.sh:217-219`，这一阶段的恢复命令只有 `update-ref -d`；最终记账在 `402-405`。
- 已证实：注入 update-ref 失败后执行打印出的恢复命令，分支已删，但任务书最后一条 worktree 记录仍是 `worktree: partial … stage=branch-delete …`，没有最终的 `worktree: archive|merged …` 行。
- 修复方向：让这一阶段的恢复路径以 OID 为条件删分支（包括第 5 项的配置清理），并写入最终记账行。推荐做法：让 `finish` 能识别「worktree 已删、分支仍指向 partial 记录里的 OID」并续做；OID 不符仍然拒绝。

### 5. LOW（Standards）收尾删分支后遗留 `branch.<名>.*` 配置

- 位置：`bin/qwb-worktree.sh:345-346`、`389-390`，`update-ref -d` 只删 ref。
- 已证实：设置 `branch.case.remote/merge` 后执行 `finish case --merged`，rc=0，ref 已删，但两项配置仍在；以后新建同名分支会继承旧的上游设置。
- 修复方向：按 OID 条件删除 ref 成功后，移除 `branch.<名>` 配置节（不存在不算错）。移除失败只警告并给出可执行命令，不回滚，也不改变已完成的删除。

### 6. LOW（Standards）worktree 模式派发时打印误导性的「工人 tab 开在调用者 workspace」警告

- 位置：`bin/qwb-run.sh:496-499` 在判定任务 Space 之前调用 `resolve_workspace`；项目主 workspace 未打开时，它会打印回退警告（`bin/qwb-lib.sh` resolve_workspace 内）。`672` 随后把 `TAB_WS` 改成任务 Space。
- 已证实：隔离会话中两次 worktree 模式派发，stderr 第一行都是「警告：工人 tab 开在调用者 workspace （未知）——本项目未声明 QWB_WORKSPACE…」，但工人 tab 实际开在任务 Space。
- 后果：主控会被引导去填本来不需要的 `QWB_WORKSPACE`。
- 修复方向：进入任务 Space 的派发不打印「调用者 workspace 回退」一类警告；`--here` 等非 Space 模式保持现状；workspace list 查询失败或响应不合契约时，仍要在任何副作用之前拒绝。

## 已排除的怀疑

- 安装器去掉 `chmod +x` 后：Git 中 `bin/*.sh` 除 `qwb-dispatch.sh`、`qwb-lib.sh` 外都是 100755，`cp -p` 会保留；`qwb-dispatch.sh` 只经 `bash "$DISPATCH_BIN"` 调用，Claude Stop hook 和模板里的命令也都用 `bash` 调用，不受影响。
- 87222a2 的 diff 没有引入新错误：`abort_opened_space` 只关闭 `already_open=false` 的 Space；Space 匹配改为 linked + checkout_path，repo_root 不符即拒绝；归档标签已存在时，只接受指向当前实际 HEAD 的情况。
- 计划第 3 条的复用与 `--pane` 路径：复用工人会核对任务 Space、cwd、workspace 和最后一条 dispatch 身份，旧工人仍在主 workspace 时拒绝并提示换 `--name`；`--pane` 在目标 worktree 还没有 Space 时提前拒绝。

## 仍未验证的生产边界

- 真实闭环只要求 pi；Claude、Codex、pane-run 工人在 Space 中的完整闭环不在本轮范围。
- Herdr 重启后，根 tab 和工人 pane 能否查询。
- 主仓 workspace 未打开时，`worktree open --cwd` 会顺带新建主仓 workspace；这是 Herdr 的行为，QWB 不记录也不清理。
- 生产安装（qonnwolf-sites）由使用者自己处理，本轮不涉及。

## 返修任务（执行者：Codex，gpt-6-sol / high）

- 工作目录、分支同 r1，起点 `87222a2dca8fb649b85128b47650921b3806f2da`。不开新分支，不 push，不合并。本报告随第一笔返修提交一并提交。
- 范围：只处理上文审点 1-6。不做：主仓 workspace 被自动新建的处理、Claude/Codex 工人闭环、与本清单无关的重构或格式调整；不碰 `qonnwolfai-student`、`qonnwolf-sites` 及其他项目。
- 做法：
  - 同 r1：先读后写，最小实现，注释和报错沿用现有中文风格，每项修复配公开 CLI 层回归测试。
  - 每个新测试都做反转验证：在 87222a2 上变红，修复后变绿。反转只在临时副本里做，不提交。
  - 审点 1 的测试要覆盖两点：已有 0644 文件安装后权限不变；新建文件权限等于 `0666 & ~umask`，umask 至少测 022 和 027 两种。
  - 审点 3 的测试要覆盖：separate-git-dir 和 submodule 放行；子目录安装和 linked worktree 根拒绝。
  - 审点 4 的测试要断言：恢复后任务书最后一条 worktree 记录是最终动作行，分支和配置节都已删除。
- smoke 新节加在 `tests/smoke.sh`「新节必须加在本行之前」之前；汇报时核对输出里该节确实是 SMOKE PASS 之前的最后一节。
- 真实 Herdr 只能在自建 named session 中使用，规则同 r1，不得改动 default 会话。
- 真实闭环（审点 2），在代码定稿的 SHA 上执行：
  - 新建 named session。在隔离临时 Git 项目的仓库根安装最终候选，写一张无害票（例如在副本里新增一个固定内容的文件并提交）。
  - 用默认新建 worktree 方式，派发给真实 pi 工人（herdr 模式，即本机 pi 默认配置）。
  - 逐项确认：任务 Space 以 linked worktree 出现在 Spaces；工人会话在该 Space；账本有 `worktree-space:`、`scenarios-fp:`、`dispatch:`；工人完成。
  - 主控独立核对工人产出，并入后执行 `finish --merged`，确认 Space 已关闭、副本和分支已删、账本有最终记录。
  - 收尾前后对比 workspace list，确认主 Space 和其他 Space 没变。
  - 记录每条命令和 rc；临时项目不得放进任何真实项目目录；结束后 stop 并 delete 该会话。
- 验收：
  - 提交后工作区干净。在最终 SHA 上运行 `bash bin/qwb-test.sh fast --project "$PWD"` 和 `bash bin/qwb-test.sh full --project "$PWD" --report /tmp/qwb-full-<SHA前7位>.md`。
  - 日志存 `/tmp/qwb-full-<SHA前7位>.log`；报告文件必须事先不存在。
  - 记录命令、原始退出码、耗时、前后工作区状态。
- 报告：
  - 写 `docs/reviews/2026-09-24-qwb-production-optimization-r2-execution.md`，逐项写明：改动位置、测试名、红/绿证据、隔离 Herdr 与真实闭环的命令和 rc、未验证项。与返修一起提交。
  - 真实闭环在代码定稿的提交上运行，报告写明该 SHA；它之后的提交只允许改 `docs/reviews/`，用 `git diff --stat <闭环SHA> <最终SHA>` 证明。full 在含该报告的最终提交上运行。
  - 最后在对话中单独输出一行 `QWB_PROD_OPT_R2_FIX DONE <完整SHA>`，或 `QWB_PROD_OPT_R2_FIX BLOCKED <原因>`。

**REVIEW_QWB_PRODUCTION_OPTIMIZATION_R2 AMEND**
