# 任务书：真机验证 finish --root-tab-missing（smoke-root-tab-missing）

state: verified

任务 id: smoke-root-tab-missing
来源：qonnwolf-sites 升级回执遗留——兜底路径缺真机证据，母本主控补验。

## 1. 验收场景

### user_正常路径_真机兜底收尾
Given 真实 herdr Space 中根 tab 被手工关闭、工人 tab 与 Space 仍在
When finish --archive --root-tab-missing
Then Space 关闭、worktree 与分支删除、记账行含 root-tab-missing=1
### user_失败路径_无参数拒绝
Given 同上
When 不带参数 finish --archive
Then 拒绝且 Git 与 Space 均未动

worktree-space: id=wTF root-tab=wTF:t1 path=/Users/rocky/projects/qonnwolfbuddy/.worktrees/smoke-root-tab-missing
dispatch: 2026-09-27T23:30:00Z worker=smoke agent=qwb-smoke-root-tab-missing pane=wTF:p2 dir=/Users/rocky/projects/qonnwolfbuddy/.worktrees/smoke-root-tab-missing
worktree: archive branch=smoke-root-tab-missing tag=archive/smoke-root-tab-missing root-tab-missing=1
