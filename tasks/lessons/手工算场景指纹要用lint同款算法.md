# 手工算 scenarios-fp 要用 lint 同款算法（`$(…)` 去尾换行后再 shasum）

**日期**：2026-09-16　**谁踩的**：主控（claude-opus-5）

## 现象

母本仓不装 `qwbuddy/`，`qwb-run.sh` 跑不了，主控手工派发时自己算 `scenarios-fp:`：`awk … | shasum`。三张票全被 `qwb-lint.sh` 判「验收场景在派发后被改动」，场景其实一字未改。

## 根因

`qwb-run.sh` / `qwb-lint.sh` 都是 `blk="$(scenario_block f)"; printf '%s' "$blk" | shasum`——命令替换会吃掉块尾换行。管道直喂 shasum 多了一个 `\n`，哈希必然不同。

## 教训

- 手工复制脚本里的哈希逻辑时，**整段照抄含引号与 `$(…)`**，不要"意思一样就行"。
- 更根本：母本仓自派发缺 `qwb-run.sh` 可用路径，手工步骤越多越容易走样。若母本仓自派发频繁，考虑让 `qwb-run.sh` 认 `qwb.config.sh` 回退（与 `qwb-test.sh` 同款）。
