# 任务书：装机脚本去掉 basename/dirname 子进程

```
任务 id:  audit-init-forks
state: verified
implementation-authorized: Rocky 2026-10-03「你查出的点，可以通过herdr，排pi进行执行和修复，herdr开在本workspace中」
dispatch-budget: 3
来源:     全仓审核 r1（docs/reviews/2026-10-03-qwb-full-audit-r1.md，发现 F9）
派发:     主控（Claude Code Fable 5.1，w14Z:p1）→ 执行者（pi-glm-flash-high）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-10-03-audit-init-forks.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-init-forks（隔离副本，detached HEAD，起点 4678ba0）
分支:     无（detached HEAD；不建分支、不 push）
```

## 0. 原始意图与范围

原始意图（Rocky）：对本项目做彻底审核，优化代码和性能。

本票只做一件事：`bin/qwb-init.sh` 在每个文件上调用 `$(basename …)` / `$(dirname …)`，一次装机约 122 个子进程。实测装机 677ms，换成 bash 参数展开后 403ms，安装产物一致。全门里装机被调 60–75 次。

白名单：**只许改 `bin/qwb-init.sh`**。

### 工程规格

1. 把下列行的子进程换成参数展开（行号以 `4678ba0` 为准，动手前自己重新定位）：
   - `:171` `mktemp "$(dirname "$dst")/.qwb-install.XXXXXXXX"` → `"${dst%/*}/.qwb-install.XXXXXXXX"`
   - `:197`、`:199-200`、`:218`、`:301-302` 的 `$(basename "$src")` / `$(basename "$s")` → `"${src##*/}"` / `"${s##*/}"`
2. 换之前逐处确认：该变量在所有调用路径上都含 `/`、不以 `/` 结尾（否则 `${x%/*}` 与 `dirname` 结果不同）。有任何一处不能确认就保留原写法，并在 `done:` 行里说明。
3. 不动：`:28`（`SRC=` 只跑一次）、`:361`、`:371`、`:388`（低频），`atomic_copy` 的 mktemp+cp+mv 原子写结构，内嵌 Python。
4. 不顺手改格式、不改注释、不改报错文案。

## 1. 验收场景

### user_正常路径_新旧装机产物逐字节一致

Given 一份旧版源码树（`git archive 4678ba0 | tar -x -C <临时目录>/old`，只读取、不改仓库）和当前工作目录的新版源码
When  先用旧版 `bin/qwb-init.sh` 装到 `<临时目录>/proj`（先 `git init`），把结果 `cp -R` 存为 `out-old`；删除并重建 `<临时目录>/proj` 后用新版装到同一路径，存为 `out-new`
Then  `diff -r out-old out-new` 无任何输出、退出码 0；两次装机的 stdout、stderr、退出码也逐字节相同

### user_失败路径_安装目标被拒时行为不变

Given `<临时目录>/proj2/qwbuddy/bin/qwb-run.sh` 预先是一个指向别处的符号链接（`check_install_file` 的拒绝条件；若该条件不是这个，读代码找一个现有的拒绝条件代替并写明）
When  分别用旧版和新版 `qwb-init.sh` 对它装机
Then  两次都以非 0 退出，stdout、stderr、退出码逐字节相同；目标目录在失败后的文件清单（`find . | sort`）相同，不多写任何文件

### user_失败路径_重复装机不覆盖已有配置

Given 一个已用新版装过的项目，手工在 `qwbuddy/config.sh` 末尾加一行标记
When  再跑一次新版 `qwb-init.sh`
Then  标记行仍在；与旧版在同样前置状态下重装的 stdout、stderr、退出码逐字节相同

## 2. 硬约束

- 只在自己的工作目录（隔离副本）里改代码，只动白名单内文件。主仓根 `/Users/rocky/projects/qonnwolfbuddy` 下除了往主账本追加状态行，**什么都不许动**（不改文件、不跑 git 写操作、不跑会写文件的脚本）。
- git：只许在自己的副本里 `git add <白名单文件>` 与 `git commit`（detached HEAD 上直接提交）。禁止建分支、`push`、`stash`、`reset --hard`、`rebase`、`worktree`、改 git 配置。提交信息用英文祈使句一行（如 `perf: drop basename/dirname forks in installer`），不加签名行。`git show <sha>:<path>` 这类只读命令随便用。
- 行为不变：任何可观察输出逐字节不变。
- 临时目录用 `mktemp -d`，自己建自己删（成功失败都删）。
- bash 须兼容 macOS 自带 `/bin/bash` 3.2：不用关联数组、`mapfile`、`${x,,}` 等 4+ 语法。

## 3. 验收门

- 快门：`bash bin/qwb-test.sh fast`
- 三个场景：按上文写一个一次性对比脚本放在临时目录里跑（不提交、不放进仓库），把命令和原始结果写进 `done:` 行。
- 计时：新旧各装 5 次取最小值，报两个数字。
- 全门：全部改完并提交后，在自己的副本里跑**一次** `bash bin/qwb-test.sh full > <临时文件> 2>&1`（本机约 7–15 分钟，别反复跑；调试用上面的定向检查）。基线是 `4678ba0` 干净副本上 791 PASS / 0 FAIL，末尾有 `SMOKE PASS` 与 `LINT PASS`。`done:` 行里写：退出码、PASS 行数（`grep -c "^PASS"`）、FAIL 行数、输出的最后 5 行原文。PASS 数不得少于基线。
- 全门或定向测试失败：先判断是不是自己的改动引起的（对照 `git show 4678ba0:<文件>` 或在临时目录用旧版复现）。是就修；不是就原样写进 `done:`，不去修白名单外的文件。

## 4. 报告要求

往主账本绝对路径追加状态行（列首、不缩进）：`working:` / `done:`（含跑了什么命令与原始结果）/ `blocked:` / `needs-decision:`。本票是未迁旧票，直接用 `printf '%s\n' 'working: …' >> <主账本>` 追加；不改别人的行，**不改 `state:` 字段**。
最后打印 `DONE <commit sha>` 或 `STOP <原因>`，并把同样的 sha 写进 `done:` 行。

票本身有缺陷时用疑点行（示例缩进两格，真写时顶格）：

```
  blocked:  spec-defect: <票的哪一条条款；反例或证据路径；继续照做会错在哪里>
```

## 6. 本票不允许做的事

- 不改 `bin/qwb-init.sh` 以外的任何文件（含测试、文档、其他脚本）。
- 不重构装机流程、不合并预检清单与安装清单、不动 Python 段。
- 不建分支、不 push、不动主仓根的任何文件（主账本追加状态行除外）。
working: 2026-10-03T20:35:51Z 主控手工派发（同 Space 独立 Tab，未经 qwb-run）：worker=pi-glm-flash-high agent=qwb-audit-init-forks pane=w14Z:p2 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/audit-init-forks base=4678ba0
working: 2026-10-03T20:40:00Z 执行者开工：已读任务书与 r1 审核 F9；步骤=核验 6 处替换点调用路径 → 改 bin/qwb-init.sh → 定向对比脚本（3 场景）→ 快门 → 计时 → commit → 全门一次
done: 2026-10-03T20:49:54Z 执行者(pi-glm-flash-high) 改 bin/qwb-init.sh 恰 6 处 7 行（:171 dirname→${dst%/*}；:197/:199-200/:218 basename→${src##*/}；:301-302 s 同改；diff +7/−7，bash -n 过）。替换前逐处核验：atomic_copy 全部 12 个 dst 调用点与 TPL/SRC glob 遍历项均含 / 且不以 / 结尾（ROOT/SRC/TPL 均为 pwd 绝对路径；roles/*.md、qwb-*.sh glob 不中时字面量同样成立），6 处全部可安全替换，无一处保留原写法。定向对比（一次性脚本在 /tmp，git archive 4678ba0 展开旧版 vs 本工作目录新版）：场景1 diff -r out-old out-new 无输出退出 0、stdout/stderr/rc 逐字节一致 rc=0；场景2 预置 qwbuddy/bin/qwb-run.sh→/etc/hosts 符号链接，两侧 rc=1、stderr 同为「错误：安装目标不是普通文件：…」、失败后 find . | sort 一致；场景3 重装两侧 config.sh 标记行均保留、stdout/stderr/rc 逐字节一致 rc=0；三场景全过。计时各 5 次取最小：旧 813ms → 新 511ms。快门 bash bin/qwb-test.sh fast 退出码 0 无输出（=bash -n 全部脚本+shellcheck bin/*.sh 零发现，本门无 PASS 行属正常）。全门提交后跑一次 bash bin/qwb-test.sh full：退出码 0、grep -c '^PASS'=815（基线 791，不少于基线）、grep -c '^FAIL'=0；末 5 行原文=「== 10. 任务书正文无占位状态行（只警告，不 FAIL）==」/「警告：发现列首占位状态行…（约 8KB 历史票占位警告长行，与本改动无关）」/「PASS  占位状态行仅警告不 FAIL（详情见上方 stderr；新写票必须删掉或缩进，不补历史票）」/空行/「LINT PASS」；log 内另有 SMOKE PASS 与 REVIEW-IDENTITY PASS。commit=08376595af50d47f891edaa56739e9ec52ba0566（detached HEAD 直接提交，仅白名单文件，工作区干净）。临时目录已自建自删。
working: 2026-10-03T21:00:46Z 主控验收：diff 仅 bin/qwb-init.sh +7/−7 与票一致；独立对比新旧装机（同一路径先后安装）目录树 diff -r 无差异、stdout/stderr 归一化路径后 cmp 相同、rc=0；在工人副本 0837659 上独立跑 bash bin/qwb-test.sh full：rc=0、815 PASS / 0 FAIL、SMOKE PASS / REVIEW-IDENTITY PASS / LINT PASS、末节 §86（本机负载 10，耗时 495.65s，不作性能结论）。已 cherry-pick 到 main=07b0656，未 push。
