# 左侧Space不是顶部Tab

2026-10-01，firstmate通过本任务006/007指令转达纠正：顶部Tab改名不等于左侧Spaces分组，Unicode `└` 标签配平铺Space也不能充当原生项目树。

- 单独Space只证明workspace分离；本次要求的项目/主副本/子任务树须使用Herdr原生Git worktree分组，不以标签、缩进或Tab父子关系代替。
- 用原生 `worktree open` 打开现有母仓/任务副本；核实际worktree list中的同一 `repo_key`、父级非linked、子级linked，才有原生树归属证据。打开现有副本不等于获准新建、删除或回收Git worktree。
- UI父Space可命名为firstmate，但标签不证明运行身份；仍须保留并核原terminal、原生session、进程、实际FM_HOME及cwd/工作区内容，不为改分组重启或新建替身。
- pane迁移会改变公开端点ID，旧ID可能通过pane alias读回；alias只帮助连续定位，不能代替核对当前workspace/tab/pane及同步任务meta。
- 活进程可能仍持有旧环境快照。后续控制读取已核对的任务meta新端点，不依赖旧HERDR_*环境、alias或UI焦点猜目标。
- 已审代码先按准确冻结范围提交；本类流程经验单独维护，不能混进已审实现提交。没有独立读回证据时，只说“收到迁移报告”，不冒充已验证。
