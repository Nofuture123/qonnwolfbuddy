# 真 Herdr 收尾演练记录（2026-10-04）

主控（Claude Code Fable 5.1）在 `main` @ `47de4b6`（运行代码同 `20ea2cc`）上做的三轮演练。每轮各起一个独立 named Herdr 会话（`qwb-drill-*`，跑完 stop 与 delete 均 rc=0），临时项目建在本仓库 `.qwb-tmp/drill.*` 下，默认会话只做过一次只读查询。Herdr 0.9.3，工人 devin（`workers.sh` 默认档）。演练票只让工人回一句「收到」，不改文件；分支与 main 同提交，所以 `--merged` 的 Git 前提天然成立。

## 结论

| 轮 | 情形 | 结果 |
|---|---|---|
| 1 | 证据改写成旧版留下的「身份未知、无 PID」；关掉工人 pane 后带 `--writer-proof-missing` 收尾 | **通过**。工人还在时带不带参数都拒绝；pane 关掉后不带参数拒绝、带参数放行；副本、分支、Space 清理，账本留痕 `writer-proof-missing=1` 与一条 `working:` |
| 2 | 同样的证据；工人用两次 Ctrl+C 退回 shell，pane 保留 | **不通过，产品缺陷**。shell 的 cwd 仍在副本里时拒绝（合理）；把 shell `cd` 出副本后仍拒绝，报「缺PID兑底：pane w2:p1 身份未知」 |
| 3 | 证据保持真机派发写下的带 PID 形态；关掉工人 pane 后不带任何兑底参数收尾 | **通过**。说明「关闭工人 pane」是默认收尾被拒后的通用出路 |

另外三轮的派发证据都带 PID（`"proof": "native-pid; CLI idle not verified"`），证实 F43 的修复在真机上生效。

## 发现

- **F45 真 Herdr 对没有 agent 的 pane 不返回 `agent` 键，产品要求该键存在且为 null。** 只读查询默认会话里一个普通 shell pane，`herdr pane get` 的应答键为 `agent_status, cwd, focused, foreground_cwd, label, pane_id, revision, scroll, tab_id, terminal_id, workspace_id`，没有 `agent`。`bin/qwb-worktree.sh` 三处、`bin/qwb-herdr.sh` 一处按「键存在且为 null」判定，假 Herdr 夹具一律返回 `"agent": null`，所以测试全绿、真机永远拒绝。受影响：pane 仍在时的 `--writer-proof-missing` 兑底（第 2 轮实测）；land 收尾的两处判定（读代码得出，未做真机演练）。方向是拒绝而不是误删，没有丢成果的风险，但这些路径在真机上走不通。起点 `4678ba0` 已有同样写法，不是本轮引入。
- **F46 默认收尾被「候选写入者仍持cwd/FD」拒绝后，产品不给出路。** 工人停在自己的界面里时进程 cwd 就在副本目录，默认 `finish --merged` 必然被拒（第 1、3 轮 A 步）。拒绝本身符合「idle/done 不等于已停」的设计，但拒绝信息与两份主控说明都没写该怎么办。同日 Claude Code 主控真机验收的会话记录显示：主控被拒两次，自己读源码、给 devin 发 `/exit`、再把工人 shell `cd` 出副本，才收尾成功。验收脚本的断言全过、也确实无人介入，但这靠的是主控模型临场摸索，不是产品指引。
- devin 不认主控发的 `/exit`（第 1 轮；Claude 主控那轮是 `/exit` 加两次回车后退出），两次 Ctrl+C 能退回 shell（第 2 轮）。退出方式因工人而异，所以出路选「关闭 pane」而不是「发退出命令」。

修复票：`tasks/2026-10-04-audit-finish-real.md`。

## 第 1 轮原始日志

```
session=qwb-drill-1791135645-1118 base=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un
controller pane=w1:p1 workspace=w1
已获锁：w1:p1（/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project/qwbuddy/.controller.lock）
lock rc=0
run rc=0
已派发：drill → devin（agent=qwb-drill pane=w2:p1 dir=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project/.worktrees/drill）
Preparing worktree (new branch 'drill')
--- 派发后账本里的活动证据（真机，修复后应带 PID）:
working: worker-activity op=672eed43a58cc17ad82177a80a8b22f4 pane=w2:p1 evidence={"activity": "unknown", "proof": "native-pid; CLI idle not verified", "pid": 2883, "pid_start": "Sun Oct  4 19:40:48 2026"}
worker pane=w2:p1
--- 起始状态:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project                  9b23fba [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project/.worktrees/drill c9624d0 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== A. 工人还在时，不带参数收尾（应拒绝）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
=== B. 工人还在时，带兑底参数收尾（应拒绝：仍有 agent）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
--- B 之后状态（应与起始相同）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project                  9b23fba [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project/.worktrees/drill c9624d0 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== 让工人退出
退出方式=pane close
worker pane agent=closed
=== C. 工人已退出，不带参数收尾（应拒绝：旧启动代 PID/start 未知）
rc=1
拒绝：旧启动代PID/start未知
--- C 之后状态（应与起始相同）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project                  9b23fba [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project/.worktrees/drill c9624d0 [drill]
refs/heads/drill
refs/heads/main
w1
=== D. 工人已退出，带兑底参数收尾（应成功）
rc=0
      若收尾时该副本仍在被写入，窗口内的新提交会成为未引用对象（dangling），
      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。
已记账：2099-01-01-drill.md ← worktree: merged branch=drill tag=- writer-proof-missing=1
--- D 之后状态（副本、分支、Space 应已清理）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un/project 9b23fba [main]
refs/heads/main
w1
--- 账本留痕:
working: writer-proof-missing op=672eed43a58cc17ad82177a80a8b22f4 pane=w2:p1 reason="真机演练" evidence={"op": "672eed43a58cc17ad82177a80a8b22f4", "pane": "w2:p1", "pane_proof": "pane-not-found", "resource_proof": "lsof-clean", "known_generations_ended": 0, "later_live_generation": "none"}
worktree: merged branch=drill tag=- writer-proof-missing=1
BASE=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.yEH6un
session stop rc=0
session delete rc=0
```

## 第 2 轮原始日志

```
session=qwb-drill-1791135718-25978 base=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA
controller pane=w1:p1 workspace=w1
已获锁：w1:p1（/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/qwbuddy/.controller.lock）
lock rc=0
run rc=0
已派发：drill → devin（agent=qwb-drill pane=w2:p1 dir=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/.worktrees/drill）
Preparing worktree (new branch 'drill')
--- 派发后账本里的活动证据（真机，修复后应带 PID）:
working: worker-activity op=748b22b3b2ab9cb9ca15cacb2ba42744 pane=w2:p1 evidence={"activity": "unknown", "proof": "native-pid; CLI idle not verified", "pid": 27290, "pid_start": "Sun Oct  4 19:42:00 2026"}
worker pane=w2:p1
--- 起始状态:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project                  dd1ed6b [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/.worktrees/drill 42abc38 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== A. 工人还在时，不带参数收尾（应拒绝）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
=== B. 工人还在时，带兑底参数收尾（应拒绝：仍有 agent）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
--- B 之后状态（应与起始相同）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project                  dd1ed6b [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/.worktrees/drill 42abc38 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== 让工人退出
退出方式=ctrl+c x2
worker pane agent=null
shell=27097 fg_group=27097 procs=27097:zsh
=== C. 工人已退出，不带参数收尾（应拒绝：旧启动代 PID/start 未知）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
--- C 之后状态（应与起始相同）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project                  dd1ed6b [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/.worktrees/drill 42abc38 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== D. 工人已退出，带兑底参数收尾（应成功）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
=== D2. D 被拒：把工人 shell 的 cwd 挪出副本后重试
rc=1
拒绝：缺PID兑底：pane w2:p1 身份未知
--- D 之后状态（副本、分支、Space 应已清理）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project                  dd1ed6b [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA/project/.worktrees/drill 42abc38 [drill]
refs/heads/drill
refs/heads/main
w1,w2
--- 账本留痕:
BASE=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.e3tzxA
session stop rc=0
session delete rc=0
```

## 第 3 轮原始日志

```
session=qwb-drill-1791135856-52136 base=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5
controller pane=w1:p1 workspace=w1
已获锁：w1:p1（/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5/project/qwbuddy/.controller.lock）
lock rc=0
run rc=0
已派发：drill → devin（agent=qwb-drill pane=w2:p1 dir=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5/project/.worktrees/drill）
Preparing worktree (new branch 'drill')
--- 派发后账本里的活动证据（真机，修复后应带 PID）:
working: worker-activity op=804c0ac8ff9352a275b57290b40fb3b5 pane=w2:p1 evidence={"activity": "unknown", "proof": "native-pid; CLI idle not verified", "pid": 53004, "pid_start": "Sun Oct  4 19:44:17 2026"}
worker pane=w2:p1
--- 起始状态:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5/project                  3d72ea7 [main]
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5/project/.worktrees/drill 64243e4 [drill]
refs/heads/drill
refs/heads/main
w1,w2
=== A. 工人还在时，不带参数收尾（应拒绝）
rc=1
拒绝：候选写入者仍持cwd/FD，保留成果
=== 让工人退出
退出方式=pane close
worker pane agent=closed
=== C. 工人窗格已关，证据带 PID，不带任何兑底参数收尾（应成功）
rc=0
      可用 git fsck --lost-found 找回。收尾前提是工人已停止写入。
已记账：2099-01-01-drill.md ← worktree: merged branch=drill tag=-
--- C 之后状态（副本、分支、Space 应已清理）:
/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5/project 3d72ea7 [main]
refs/heads/main
w1
--- 账本留痕:
worktree: merged branch=drill tag=-
BASE=/Users/rocky/projects/qonnwolfbuddy/.qwb-tmp/drill.tzpdG5
session stop rc=0
session delete rc=0
```
