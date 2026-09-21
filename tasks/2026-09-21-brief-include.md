# 任务：移植 firstmate 的常驻规则附页（brief-include）到 qwbuddy

```
任务 id:  brief-include
state: verified
scenarios-fp: 94b2aa098baae0f0d0f91891d1c21a6d1daeb195
日期:     2026-09-21
派发:     主控（Pi）
主账本:   /Users/rocky/projects/qonnwolfbuddy/tasks/2026-09-21-brief-include.md
工作目录: /Users/rocky/projects/qonnwolfbuddy/.worktrees/brief-include
分支:     brief-include
```

## 0. 背景与范围

上游 firstmate 于 2026-09-21 落地「home-local include to briefs」（提交 fcbaa375 系列，PR #5115，
`git -C /Users/rocky/projects/firstmate show fcbaa735` 可读全文）：home 的 `config/brief-include.md`
存在时，每份任务书末尾**原样**追加一节常驻内容，供各 home 写一次常驻规则（如提交纪律、命名规范），
不必每张票重抄。精髓三条：

1. 读之前先校验：必须是可读的常规文件，否则报错拒绝（配置错误不许被绕过或静默跳过）；
   全空白视为无附页，行为与没有该文件完全一致。
2. 附页永远是任务书**最后一节**，且声明「其余各节优先」——附页不得覆盖任务书正文。
3. 无附页时零改动、零输出：不开这个功能的项目行为与今天完全一致。

本票把它移植进 qwbuddy：项目根的 `qwbuddy/brief-include.md`（可选）作为常驻附页，
`qwb-run.sh` 派发时自动追加到任务书末尾。上游特有的概念（secondmate 分支、
`Delivery contract: mode=` 校验、FM_HOME config 路径）一律不带。

## 1. 验收场景（先写场景，再写代码；场景冻结后才许可提交实现）

### user_有附页原样追加

Given 项目根存在非空 `qwbuddy/brief-include.md`（内容含中文与多行规则）
When  `qwb-run.sh` 派发一张新任务书
Then  任务书末尾出现「常驻附页」节，节内为附页原文**逐字**内容（无 trim、无改写），
      且节首声明与其他各节冲突时以其他各节为准；`bin/qwb-lint.sh` 与 `bin/qwb-test.sh` 全绿

### user_无附页行为不变

Given 项目根不存在 `qwbuddy/brief-include.md`
When  `qwb-run.sh` 派发
Then  任务书与今天完全一致（无附页节），stderr 无附页相关字样，派发退出码 0

### user_附页不可读拒绝派发（失败路径）

Given `qwbuddy/brief-include.md` 是一个目录（或不可读的非常规文件）
When  `qwb-run.sh` 派发
Then  报一行明确错误并拒绝派发（exit 非 0），任务书不产生半截写入

### user_重复派发附页不叠加（失败路径）

Given 任务书已含本票追加的常驻附页节（同一附页内容）
When  对同一任务书再次派发
Then  附页仍只有一份，不出现重复叠加

## 2. 硬约束

- 实现落点三处，不许扩散：`bin/qwb-run.sh`（读校验+追加）、`templates/brief-include.md`（新增模板示例）、
  `bin/qwb-init.sh`（装项目时拷模板，幂等：目标已有则不覆盖）。
- 附页路径固定为 `<项目根>/qwbuddy/brief-include.md`，不新增任何配置项。
- 内容逐字追加；唯一允许的加工是「全空白→视为无附页」判定（对照上游实现）。
- 幂等查重防叠加：追加前识别任务书是否已含同一附页节；判重实现须对附页内容变化安全
  （附页内容改了要能追加新版，不能因为「已有附页节」就永远跳过）。
- 与 `scenarios-fp` 场景指纹的关系：附页节在「验收场景」块之外，追加动作不得改变现有指纹语义；
  smoke 里加对照用例钉住。
- bash 3.2 兼容（`set -u` 下空数组展开坑，上游栽过）；shellcheck 干净。
- 零新依赖；最小实现；不顺手重构任何其他文件。

## 3. 验收门

- `bin/qwb-lint.sh` 退出码 0。
- `bin/qwb-test.sh` fast 与 full 全绿，PASS 数 ≥ 现基线（468）+ 新增用例；
  smoke 至少覆盖上面四个场景（fake 手法沿 `tests/` 现有写法）。

## 4. 报告要求

- 过程用 `working:` 行留痕，完成写 `done:` 行（含最终 PASS/FAIL 数、分支名、worktree 路径）。
- 验收通过前分支留在 worktree，等主控验货；通过后按本仓惯例做 worktree 收尾记账。

## 6. 本票不允许做的事

- 不动 `templates/TASK.md`、`bin/qwb-dispatch.sh`、`bin/qwb-wake.sh`、`templates/config.sh`。
- 不改 QWB_WORKERS 语义、不改质量门定义。
- 不合并 main、不动主工作区。
dispatch: 2026-09-21T16:19:20Z worker=pi agent=qwb-brief-include pane=wE0:p3 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/brief-include
working: 2026-09-21T16:19:51Z 已读规格与上游 fcbaa735；开始读 qwb-run/qwb-init/lint/test 与 tests/ 现有写法
working: 2026-09-21T16:31:26Z 基线确认：full 门 PASS=468（smoke 446 + review-identity 15 + lint 7）；开始实现三处落点（templates/brief-include.md、qwb-init.sh 拷模板、qwb-run.sh 读校验+追加）+ smoke 四场景用例
done: 2026-09-21T17:05:00Z 实现完成待验货。落点三处：bin/qwb-run.sh（读前校验：非可读常规文件拒绝派发+全空白视为无附页；追加：末尾「## 常驻附页」节+逐字原文+其余各节优先声明+brief-include-fp: 幂等查重、内容变化可追加新版）、templates/brief-include.md（示例模板）、bin/qwb-init.sh（拷模板幂等不覆盖）。上游 secondmate/Delivery contract/FM_HOME 概念未带。检查与原始结果：bin/qwb-test.sh fast 退出码 0（bash -n + shellcheck bin/*.sh 干净）；bin/qwb-test.sh full 退出码 0、PASS 总数 475 = 基线 468 + 新增 7（smoke 453 全绿 + review-identity 15 + lint 7，LINT PASS）；smoke 第 50 节 7 项全 PASS 钉死四场景：①有附页逐字追加（保留行首空格/$(id) 不展开/声明在节首/附页节在 dispatch 行之后）②无附页退出 0 且任务书无附页节且 stderr 无附页字样 ③附页是目录拒绝派发 rc≠0 且任务书与派发前逐字节一致（cmp）④重复派发附页仅一份且 scenarios-fp 冻结基线核对通过（对照用例）；另覆盖附页内容变化追加新版、init 拷模板且改后不覆盖。提交 dd7daf7 于分支 brief-include，worktree=/Users/rocky/projects/qonnwolfbuddy/.worktrees/brief-include，留 worktree 待主控验货。过程坑：smoke 断言里 $bi_rc 后跟中文逗号触发 set -u unbound（本仓 lint 检查 4 同款坑），已改 ${VAR} 形式。
working: 2026-09-21T19:04Z 主控验货通过：不采信 done 声明，独立复跑 bin/qwb-lint.sh（rc=0 LINT PASS）、qwb-test.sh fast（rc=0）、full（rc=0，475 PASS / 0 FAIL）；diff 范围核对 4 文件 +126 行全在票内落点（qwb-run.sh/qwb-init.sh/模板/smoke），无越界改动。待 Rocky 授权合并。
done: 2026-09-21T19:06Z Rocky 授权合并，主控执行：merge brief-include（fast-forward → dd7daf7）后主工作区 lint+fast 门复验全绿；worktree .worktrees/brief-include 已 remove、分支已 -d、worktree list 已 prune。主线领先远端 10 个提交，push 待 Rocky 指示。
