# 任务书：派发前预置目录信任，新 worktree 不弹信任框

```
任务 id:  worker-trust-preseed
state:    verified
scenarios-fp: 6c1cd57b18ff0293998eaaed7281adc50d91aa76
来源:     worker-max-permission E2E：codex/claude 新目录信任框不被权限参数跳过，每个 worktree 都要人按
派发:     主控 claude-opus-5 → <待派>
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-16-worker-trust-preseed.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-trust-preseed
分支:     worker-trust-preseed
前置:     worker-max-permission 合并后再派
```

## 0. 做什么

`qwb-run.sh` 在起工人前，对本次工作目录 `$DIR`：

- **claude**：`~/.claude.json` 里 `projects["$DIR"].hasTrustDialogAccepted = true`（perl JSON::PP 读改写；已 true 不动）
- **codex**：`~/.codex/config.toml` 尾部追加 `[projects."$DIR"]\ntrust_level = "trusted"`（已有同路径块不动）
- **devin**：`templates/config.sh` 默认 ARGS 加 `--respect-workspace-trust false`
- cmd/pi 已有 `--trust`/`--approve`；omp/zcode 不管

只对 `QWB_WORKERS` 里实际派的那个工人做；文件不存在或非法 JSON 就跳过并 stderr 一行警告（不拒绝派发——让信任框照弹，人来按）。QWBUDDY §1.7 改一句：装了本功能后 codex/claude 不再需要人过框。

白名单：`bin/qwb-run.sh`、`templates/config.sh`、`templates/QWBUDDY.md`、`tests/smoke.sh`。测试用 `HOME=$TMP/home`，不碰真家目录。

## 1. 验收场景

### claude 写入

Given `HOME=$TMP/home`，`$HOME/.claude.json` 有别的项目
When  `--worker claude --here`
Then  该文件多了 `projects["<项目根>"].hasTrustDialogAccepted: true`，原有项目保留，仍是合法 JSON；再派一次文件不变

### codex 追加

Given `$HOME/.codex/config.toml` 有别的 `[projects."…"]` 块
When  `--worker codex --here`
Then  文件尾多一个本项目根的块，原内容不变；再派一次不重复追加

### 文件非法则跳过不阻塞（失败路径）

Given `$HOME/.claude.json` 内容 `{bad`
When  `--worker claude --here`
Then  stderr 一行警告，文件不动，派发照常 rc=0

## 2. 验收门

快门 `bash bin/qwb-test.sh fast`；全门 `bash bin/qwb-test.sh full`。真机：执行者自己派一次 claude 到新 worktree，首屏无信任框，把 `herdr pane read` 贴账本，事后把 `~/.claude.json` 里那条临时目录删掉。

## 3. 报告

往主账本追加 `working:` / `done:`（含检查命令与结果）/ `blocked:`；不改 `state:`。票有缺陷用 `blocked: spec-defect:`。
wake: 2026-09-21T19:24:16Z state=running fp=9e4009665c768ce5dd4c3baf1cbec80f824c97aa
working: 2026-09-21T19:42:00Z 主控（claude-opus-5，pane wF2:p3）派发说明：前置 worker-max-permission 已合并 main（d10b0d6，`QWB_WORKER_ARGS` 与 `worker_map_get` 已在 bin/qwb-run.sh）。改派 pi（zai-coding-cn/glm-5.3-flash）。与 watch-invisible 并行（它改 qwb-wake.sh/qwb-init.sh/qwb-status.sh，本票不碰这些）；两票都改 tests/smoke.sh 尾部与 templates/QWBUDDY.md——**完成前先 `git merge main` 到本分支解冲突（smoke 新节号接在现有最大号 51 之后），保证主控能 fast-forward**。真机验证只用临时 worktree/临时 HOME，事后把写进真 `~/.claude.json` / `~/.codex/config.toml` 的临时路径条目删干净并在 done: 里贴证据。
dispatch: 2026-09-21T19:41:16Z worker=pi agent=qwb-worker-trust-preseed pane=wF2:p7 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/worker-trust-preseed
wake: 2026-09-21T19:42:22Z state=running fp=5e31250d0c4174af49ae6b61b72f250e937685b5
working: 2026-09-21T19:55:00Z 执行者（pi，pane wF2:p7）开工：已读票+QWBUDDY+E2E-RUNBOOK+DECISIONS；git merge main=Already up to date（分支即从 d10b0d6 开出）。实现顺序：qwb-run.sh 预置块 → templates/config.sh devin 参数 → QWBUDDY §1.7 → smoke.sh（顶部 export HOME=$TMP/home 隔离 + 51g 模板断言更新 + 新 52 节）→ 快门/全门 → 真机 claude 验证。
wake: 2026-09-21T19:46:23Z state=running fp=efed2277ed9ab7f817f5df155d74c83bb2a5a2a1
done: 2026-09-21T20:10:00Z 执行者（pi，pane wF2:p7）完成，提交 036cb18 于分支 worker-trust-preseed（merge main=Already up to date，基 d10b0d6）。实现：① bin/qwb-run.sh DIR 确定后、起工人前按实际工人预置——claude 用 perl JSON::PP 读改写 ~/.claude.json projects[DIR].hasTrustDialogAccepted=true（临时文件+rename 原子写，已 true 完全不动文件=幂等）；codex 往 ~/.codex/config.toml 尾部追加 [projects."DIR"] trust_level="trusted"（已有同路径块不动；追加失败也只警告）；缺失/非法 → stderr 恰一行警告跳过，不阻塞派发。② templates/config.sh devin=--permission-mode dangerous --respect-workspace-trust false。③ templates/QWBUDDY.md §1.7 改为派发前自动预置。④ tests/smoke.sh 顶部 HOME=$TMP/home 全程隔离（seed 合法 codex config 保 48 节 stderr 空断言），51g 模板断言同步 devin 参数，新增 52 节 7 项。检查与原始结果：快门 `bash bin/qwb-test.sh fast` 退出码 0；全门 `bash bin/qwb-test.sh full` 退出码 0（SMOKE PASS + REVIEW-IDENTITY PASS + LINT PASS，其中 52 节：claude 写入/原项目保留/合法 JSON PASS、已受信任再派文件字节不变 PASS、codex 追加/原内容逐字保留 PASS、再派不重复追加 PASS、非法 JSON stderr 恰一行警告文件不动派发 rc=0 PASS、派 codex 不碰 .claude.json 对照 PASS；git status 仅白名单 4 文件）。真机验证：临时项目 /tmp/qwb-trust-e2e（clone 本分支+qwb-init+临时探针票），qwb-run --worker claude 默认开 .worktrees/trust-e2e 隔离副本，herdr pane read wEN:p3 首屏干净无信任框、直接是 claude 交互界面（bypass permissions on），agent prompt 一次投递成功（agent_prompted，cwd=预置 worktree），claude 自己往探针票写 done: 真机探针：无信任框，提示词已收到；事后清理：herdr tab close wEN:t2、~/.claude.json 里 qwb-trust-e2e 相关条目已删（perl 删键后 grep 计数 0，残留核对「无残留」）、/tmp/qwb-trust-e2e 与备份已 rm -rf。观察一条（非阻塞）：真机中 claude 会把 ~/.claude.json 的 projects 键按物理路径/git 根重写（/tmp→/private/tmp），qwb-run 写的逻辑路径条目会被 claude 自身写回覆盖；真实项目在 /Users 下无 symlink 组件，DIR 与 claude 键一致，不受影响。
wake: 2026-09-21T20:04:29Z state=running fp=e70ddcb3bc724f1de7a80a98e2a1848fdd982884
working: 2026-09-21T20:06:00Z 主控验货（独立复跑于 worktree 036cb18）：`qwb-test.sh fast` rc=0；`tests/smoke.sh` rc=0、483 PASS / 0 FAIL（52 节 7 项全绿）；`qwb-lint.sh` LINT PASS；diff main 仅白名单 4 文件（+117/−4）；反转：把 claude 写 hasTrustDialogAccepted 改成直接 exit 0 → 52 节断言变红，恢复后 shasum cdb05b62… 一致、工作树干净；真家目录残留核对：~/.claude.json 无 qwb-trust-e2e 条目（grep 0）。已知边界（执行者观察，接受）：claude 会按物理路径重写 projects 键，/tmp 下 symlink 路径会被覆盖，/Users 下真实项目不受影响；perl 整文件重写 ~/.claude.json 与 Claude Code 自身写入之间存在竞争窗口，属改第三方状态文件的固有风险。结论：通过，state → verified，fast-forward 合并。
worktree: merged branch=worker-trust-preseed tag=-
