# herdr worktree open 自带根 tab：另开工人 tab 留空 tab，根 tab 成为收尾单点证据

**日期**：2026-09-27
**发现者**：qonnwolf-sites 主控缺陷反馈（Rocky 要求修复；w20/w21 两例手工收尾）

## 现象

`qwb-run.sh` 默认隔离派发先 `herdr worktree open` 建 Space（自带根 tab，内含空 shell，herdr 默认 label 显示「1」），再 `herdr tab create` 另开工人 tab。后果两层：

1. 每个工人窗口都多出一个空的「1」tab，纯噪音；
2. `qwb-worktree.sh finish` 把「根 tab 在不在 Space 里」当作身份核对证据，主控手工关掉这个空根 tab 后，finish 以「本票根 tab 已不存在」拒绝收尾，只能手工收尾（w20/w21 两例）。

## 根因

`herdr worktree open` 的响应本来就有 `result.root_pane.pane_id`（真录 fixture 证实），新建 Space 的根 pane 就是天然工人位——另开 tab 既留垃圾窗口，又把根 tab 变成收尾单点证据。

## 修复（方案 A + 显式兜底）

- **方案 A**：新建 Space（`already_open=false`）时工人直接落根 pane，不再 `tab create`；工人 tab 即根 tab，`worktree-space:` 记账格式不变。根 pane 分支下回滚 TAB_ID 必须留空——启动失败不得 `tab close` 根 tab（Space 连同根 tab 保留供重派）。
- **复用既有 Space（`already_open=true`）仍开新 tab**：重派场景根 pane 占用状态未知，不得贸然占用。
- **兜底**：`finish --root-tab-missing` 服务 B 方案时代遗留票与手工场景：根 tab 已不在、但 Space id 与 `worktree-space:` 记录吻合、记录路径与 worktree 物理路径吻合、Space 内除工人 tab 外无外来 tab、全 pane 空闲——其余证据一项不少，缺一仍拒绝；全过才放行 `--merged|--archive`，最终 `worktree:` 行追加 `root-tab-missing=1` 留痕。

## 教训

- 平台自带的结构（根 pane）优先于另起炉灶（再开一个 tab）；接 API 前先看响应里已有什么字段。
- 身份证据缺失时以「显式参数 + 其余证据齐全 + 留痕」放行：不静默放行（安全），也不永久死锁（可用性）。
- 桩/fixture 的内联响应必须与真录 fixture 结构一致：真 herdr 0.9.1 的 `worktree open` 响应一直带 `root_pane.pane_id`，三处测试桩漏了它，实现按契约拒收后回归才暴露。
