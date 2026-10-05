# 副主控与门控真机演练（第五轮：副主控换成 Claude Code）

- 日期：2026-10-05，09:25Z–09:59Z
- 候选：main @ `198d7da`（含 `claude-role-adapter` 的头两次提交与 `claude-prompt-length`）
- 环境：Herdr 0.9.3、Pi 1.0.2、Claude Code 2.1.289；隔离的具名 Herdr 会话，项目建在本仓 `.qwb-tmp/drill-roles-r5/project`，会话已停止并删除
- 角色：主控 Claude Code `claude-opus-5-5` medium；**副主控（规划）Claude Code `claude-opus-5-5` medium（工人 `claude-opus-medium`）**；门控（门禁）Pi magpie `codex/gpt-6-astra` low；工人 `pi-sol-high`；独立审核工人 `pi-astra-low`
- 需求原话与前几轮相同，本轮不追加修订；纪律同第四轮（不许读脚本源码）
- 前几轮：[第一轮](2026-10-05-real-herdr-roles-drill.md)、[第二轮](2026-10-05-real-herdr-roles-drill-r2.md)、[第三轮](2026-10-05-real-herdr-roles-drill-r3.md)、[第四轮](2026-10-05-real-herdr-roles-drill-r4.md)

## 结论

Claude Code 能当副主控，但第一次在真机上启动就暴露了两处缺陷，离线测试和全门都没拦住；主仓主控介入修掉之后，整条链走通：Claude 副主控被值守叫醒后没有要求任何确认，自己接了需求原话、开票、派工、把结果上报主控；之后工人交付、门控验收通过并交还、主控落地、两张票结案。演练项目 main 为 `d13b133`。

人工介入 3 次：两次是 Claude 副主控启动的缺陷，一次是第四轮已知的「审核工人收工不回票」。演练主控被拒 6 次（5 次与 Claude 副主控启动有关，1 次是 herdr 命令用法），靠猜 1 处。

花费（各窗口界面显示）：主控 $4.84，副主控 $1.06，门控 $1.79；两个工人窗口在收尾时已关，未读到。

## 本轮发现

演练主控的笔记、时间线、人工介入记录、各窗口记录在 `.qwb-tmp/drill-roles-r5/`（`notes.md`、`timeline.log`、`interventions.log`、`evidence/`）。标「主控已实测」的是本仓主控对着演练现场或代码核实过的。

- **V1 真实安装的项目里 Claude 副主控起不来（缺陷，主控已实测）。** `qwb-role.sh start --role 规划 --worker claude-opus-medium` 被拒「Claude角色仅允许--model/--effort与--dangerously-skip-permissions」。安装器写进项目的 `workers.sh` 里，Claude 工人的声明带 `--add-dir 项目根`，新加的参数白名单不认它。任务书里「其余参数拒绝」是本仓主控只看了模板、没看安装产物就写下的；离线测试用的是手写声明，所以全门通过。已退回返修，并要求测试改用安装器真实装出的配置。
- **V2 握手后一直「真实活动未知」（缺陷，主控已实测）。** 副主控读完职责文件、回了「就绪」，会话文件也在，但脚本不认。原因：回合结束时窗口不在前台，Herdr 报 `done` 而不是 `idle`；新判定只认 `idle`。主控对着活着的窗口实测：`pane get` 为 `done`、`focused: false`，活动判定返回 `unknown`，模型与档位证明都对。早上的探测窗口一直在前台，没见过 `done`。已退回返修。
- **V3 拒绝信息让人猜。** `reconcile` 不带代次被拒「旧代际/缺expect-gen」，没说该填几；参数白名单拒绝也不说是哪个参数。已并入返修（拒绝信息写明当前代次、点名不被允许的参数）。
- **V4 说明书彼此矛盾或过时**：宿主值守专项仍写「Claude 及其他 CLI 的空闲未核验，报告未知并拒绝」，与 Claude 可当副主控相冲突；`config.sh` 注释说开局要把主控窗口号填进配置，宿主值守专项说不要写进去。
- **V5 说明书没写清的几处**：`qwb-send.sh send` 输出的事件号带 `send:` 前缀（原样可用）；副主控新开的票在派工前是 `blocked`、派工后才变 `running`；主控自己往票上追加的进度行、`plan-assign` 派生的授权行会在 `pending` 里显示成给主控的交接；落地前怎样核实工人进程已退出；`pending` 里的收件人字段与实际门铃对象不一致（门控待接手的交接显示收件人是主控，实际叫的是门控）。
- **V6 第四轮的 U1、U6、U7 原样重现**：审核工人收工不回票（全员停 4 分钟后主仓主控介入）；落地后 `pending` 仍列出已满足的通知；自检把 `QWB_ROLE_PI_CONTROL` 判成死配置。三者的修复票都在做，本轮候选不含。
- **正面结果**：Claude 副主控被门铃叫醒后直接办理，没有出现「粘贴内容要本人确认」；目录已被主控信任，没有信任弹窗；身份证明为会话记录里的实际模型与档位。它与主控有一次撞车（两边同时去接同一批进度交接，账本拒绝了后到的一方，没有副作用）。

## 后续

V1–V3 在 `claude-role-adapter` 返修；V4、V5 归入说明书修订。三张在途的票落地后再演练一轮，目标是 Claude 副主控零介入走通。
