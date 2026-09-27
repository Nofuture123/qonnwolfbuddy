# worktree Space 根 tab 别当单点身份证据；缺失兜底要显式且留痕

- 票：qwb-root-tab-fix（2026-09-27）；反馈：qonnwolf-sites 主控（Rocky 截图「为什么都有一个 1 的空 tab」；w20/w21 因根 tab 被关而 finish 拒绝、手工收尾）。

## 现象与根因

- `herdr worktree open` 建 Space 时**自带根 tab**（内含空 shell，herdr 默认 label 是「1」）。隔离派发在它之外再 `herdr tab create` 开工人 tab，于是每张票都有一个空根 tab——视觉垃圾。
- 更重的是：`qwb-worktree.sh finish` 用 `worktree-space:` 行里的根 tab id 做**身份核对**。根 tab 是用户可随手关闭的 UI 对象，把它当单点证据，等于收尾流程被一个空 tab 卡死。

## 修法（两半）

1. 消灭空 tab：`qwb-run.sh` 本次新建 Space（`already_open=false`）时，工人直接落在 `worktree open` 响应 `result.root_pane.pane_id` 的根 pane，不再 tab create。工人 tab 即根 tab，finish 核对不变。复用既有 Space（重派）不占根 pane，仍开新 tab——根 pane 占用状态未知时不贸然接管。
2. 兜底已有残留：`finish --root-tab-missing` 只放宽「根 tab 存在」这一条证据；Space id 吻合、`worktree-space:` 路径吻合、无外来 tab、全 pane 空闲仍逐项核对，全过才放行，`worktree:` 记账行追加 `root-tab-missing=1` 留痕。无参数维持拒绝。

## 泛化

- 身份证据选**用户不可随手破坏**的东西；依赖 UI 对象（tab/pane id）时必须想清楚它被手工关掉后流程是否死锁。
- 放宽身份核对只走**显式参数 + 其余证据齐全 + 账本留痕**，不静默放行，也不留永久死锁。
- stub/mock 更新要跟着契约走：`worktree open` 的 mock 响应此前只造了 `root_pane.tab_id`，方案 A 需要的是 `root_pane.pane_id`——多份测试替身（smoke stub、worker-config.py、worktree-space.py、r2-cli.py）都要同步补，漏一处就是一条旧断言钉死旧行为的 FAIL。
