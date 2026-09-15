# E2E-RUNBOOK — scenario-01-live 真实闭环验证报告

验证阶段: 基线完成。真实工人、值守投递、主控后续验收与收尾已观察到；首次派发需人工授权/补发，原始默认路径不算无干预 PASS。

## 0. 环境快照（实测）

- 母本仓基线：e917008；`bash bin/qwb-test.sh fast` → 退出码 0（2026-09-15 ~18:35 Madrid）
- 验证主控：Devin CLI v3000.10.27，原生 session `sunny-temple`，pane `w93:pH`，tab `w93:tG`，workspace `w93`
- 工人：Devin CLI v3000.10.27，原生 session `mixolydian-yamamomo`，slug `qwb-live01-worker`，pane `w93:pJ`，tab `w93:tH`（工人-闭环交付，已回收）；**TUI 底栏实测 SWE-2 Max**（Free 档），bypass permissions on（`DEVIN_PERMISSION_MODE=dangerous`，一次性 mktemp 目录无人值守跑通所需）
- 值守：纯 shell pane `w93:pK`，tab `w93:tJ`（值守-闭环交付，已回收），`qwb-wake.sh --project <TMP> --pane w93:pH --interval 20000`
- 临时项目：`/var/folders/s6/1ctcm6010k911b19ckg_gkrm0000gn/T/qwb-live.ZCBo9DXOVf`（保留备查）；token `QWBLIVE-1789490030-417954910`
- 模型路径：qwb-run 不透传 agent 参数 → `herdr tab create --env DEVIN_MODEL=swe-2-max --env DEVIN_PERMISSION_MODE=dangerous` 注入 + `qwb-run.sh --pane` 复用（原生机制，非 wrapper/mock）

## 1. 时间线（UTC 时间戳来自账本）

- 18:35 本仓 `qwb-test.sh fast` = 0；mktemp 项目建成、qwb-init 实装、config 填门与 QWB_CONTROLLER_PANE=w93:pH
- 18:36 派发第 1 次：**场景门真实拒绝**（exit 1）——失败路径判定只扫标题行/Then 行关键词，标题补"失败"后放行
- 16:36:33Z 派发第 2 次：exit 0；worktree/branch `live-note` 实建；`dispatch:` 落账
- ~16:37Z **现象 A**：`agent prompt` 返回 prompted 但 trust 对话框吞掉提示，工人停 idle → 人工介入①Enter ②补发 prompt → working
- 16:38:00Z 工人 `done:` 落账（commit `0a3a155`，自检门 0）
- 16:39:08Z wake#1（fp=9e40…）；16:39:48Z wake#2（fp=e3aa…，done: 触发）→ **18:41 本回合被真实唤醒**：读账→独立验货→篡改测试→verified→merge→worktree finish→停值守→关两 tab
- 值守日志实测：wake 后 fp 未变多轮"跳过"；verified 后"账本无未结项"；C-c 正常退出

## 2. 场景验收矩阵

| 场景 | 判定 | 证据 |
|---|---|---|
| user_只提需求后主控被真实叫回 | **部分通过（恢复后可唤醒；首次无人干预未通过）** | wake#2 在工人 done: 后投递，本回合即被唤醒的新原生回合；验收动作（读账/核对/门/verified/收尾）由主控独立完成，非命令回显 |
| user_主控忙时不丢工人结果 | **部分验证** | wake#1 在主控回合内到达→排队为新回合输入，未丢；"工人结果在忙时投递是否丢/打断"未构造真实忙态，标未验证（不假造 sleep 忙态） |
| user_验收失败不被标成完成 | **PASS** | 删 token 行后 fast=1 / full=1；恢复后 fast=0 / full=0 → 才标 verified |
| user_收尾只清自己的临时资源 | **PASS** | finish --merged 核实 OID 0a3a155 并入 HEAD 后删 worktree+分支（exit 0）；只关本轮所建 w93:tH/tJ；母仓零改动、零 commit |

## 3. 已确认缺陷/现象（候选 spec-defect 或 02/03 修复清单）

1. **现象 A（投递未生效）**：`qwb-run.sh` 先 `agent start` 紧接 `agent prompt`，devin 首启 trust 对话框会吞掉 prompt——退出码 0 但工人未开始。建议：`agent start` 后等 `idle`+无对话框再 prompt，或派发后由值守兜底重叫覆盖（当前 REWAKE 兜底能覆盖此洞，但默认 30min 偏长）。影响：本次尚未完成 trust 准备的首次派发被阻断；不外推所有 CLI 或已受信任项目
2. **`--pane` 复用不随 worktree 改 cwd**：pane cwd=建 tab 时目录；只有自建 tab 路径才 `--cwd $DIR`。工人靠提示词 cd 补救（本次成功）。建议：qwb-run 在 --pane 模式下显式 `cd $DIR` 或文档明示
3. **值守唤醒内容**：wake 文本只说"看账本"，不含工人完成摘要——够用但主控需自行读账（符合设计，非缺陷）
4. TUI 顶栏 "Pro · 0% remaining"：付费档额度显示，Free 档 SWE-2 不受影响——记录备查

## 4. 人工介入登记（全部）

| # | 动作 | 原因 |
|---|---|---|
| 1 | trust 对话框按 Enter | devin 首启 workspace trust prompt；qwb-run 无透传 `--respect-workspace-trust` 的通道 |
| 2 | `herdr agent prompt` 原样补发 | 现象 A 恢复 |
| 3 | 篡改/恢复 PROJECT_NOTE.md | 验收失败路径场景的有意动作（独立验证者职责） |

## 5. 未验证边界（诚实声明）

- 主控**真实忙态**（长回合中）下提示是否排队/丢失：未构造，不结论
- 值守脚本长期存活/跨天：未测；前台 shell 实测本轮正常，不外推
- 主控进程退出后的恢复：设计明确不保证，未测
- Rocky 主控 pane（w93:t1 pi）全程未触碰

## 6. 复现要点

```bash
TMP=$(mktemp -d -t qwb-live) && git -C "$TMP" init -b main
bash <母仓>/bin/qwb-init.sh "$TMP"
# config.sh: QWB_WORKERS 加 devin、QWB_CONTROLLER_PANE=<主控pane>、QWB_GATE_* 指向真实产物
herdr tab create --cwd "$TMP" --label "工人-x" --env DEVIN_MODEL=swe-2-max --env DEVIN_PERMISSION_MODE=dangerous --no-focus
bash "$TMP/qwbuddy/bin/qwb-run.sh" --project "$TMP" --task <id> --worker devin --pane <返回pane> --name <slug>
# 注意：补发 prompt 前确认 trust 对话框已处置（现象 A）
herdr tab create --cwd "$TMP" --label "值守-x" --no-focus
herdr pane run <值守pane> "bash $TMP/qwbuddy/bin/qwb-wake.sh --project $TMP --pane <主控pane> --interval 20000"
```
