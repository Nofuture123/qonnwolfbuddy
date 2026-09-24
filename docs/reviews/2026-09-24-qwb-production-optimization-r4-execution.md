# QWB 生产优化 r4 返修执行记录

起点 `0abb697cdc7715bacdb86632ed5c6fd3042e283e`；代码定稿与两轮真实 E2E 候选 `556b82871da5f3aa09e486a07765128080193a46`。r4 审核原文随第一笔代码提交入库。本轮未开新分支、push、合并本分支或修改其他真实项目；代码定稿之后只提交本执行报告。

## 逐项改动、红绿证据

1. **唤醒摘要 UTF-8**：保留入口 `LC_ALL=C` 的账本字节解析和原始进展指纹；在 `qwb-lib.sh` 新增 `qwb_utf8_excerpt`，把坏字节替换为 U+FFFD，再按 Unicode 字符截取最多 160 个字符。`qwb-wake.sh` 的 `collect_due` 统一调用它，故 `--once`、循环和 `--block` 共用合法摘要。公开 CLI 测试 `tests/r4-cli.py wake` 使用模拟 Herdr 0.9.1 的严格 stub，遇非法 UTF-8 参数就报错、返回非零；覆盖第 160 字节落在汉字中间的长末行，以及 `done:` 含 `\x80\x82`。两种都检查 `--once` 投递与一条 `wake:`、`--block` 输出的 UTF-8 合法性，长文本核对恰好前 160 个字符。指定起点导出副本红证据 `/tmp/qwb-r4-reversal.sXG0UI/wake-red.log`：rc=1，stub 拒收非法参数且无 wake 行；修复后 `python3 -B tests/r4-cli.py` rc=0，绿证据 `/tmp/qwb-r4-green-1.log`。
2. **默认工人名**：`qwb_default_agent_name` 对纯 ASCII id 保持原逐字节净化与短名兜底；含非 ASCII 的 id 按字符截取、保留可读 ASCII 段，再附完整 id 的 SHA-1 前 8 位，总长不超过 32。显式 `--name` 保留旧净化路径。`tests/r4-cli.py name` 经安装后的公开 `qwb-run.sh` 验证：同一中文 id 在 `LC_ALL=C` 与 `LANG=en_US.UTF-8` 下同名，同日两张中文票不同名，ASCII 和显式名不变。指定起点红证据 `/tmp/qwb-r4-reversal.sXG0UI/name-red.log`：rc=1，两票都叫 `qwb--e2e`；修复后见上述绿证据。旧 smoke §66 已按新语义核对可读 `-01` 段与完整 id 哈希；新 §83 调用公开 CLI 回归。
3. **操作文档**：`templates/QWBUDDY.md` 明确非法 state/损坏账本仍列未结、按 needs-decision 叫主控，run 拒派、lint FAIL，同时保留五个合法 state 的规矩；`qwb-wake.sh --help` 同步说明。`docs/DECISIONS.md` 新 §四十规定 `LC_ALL=C` 下解析与对外 UTF-8 文本分开，并记录默认工人名规则。
4. **真实 E2E 夹具**：票改为 `tasks/2099-01-01-真实闭环-e2e.md`，因此真实 worktree、Git 分支和 Herdr Space 路径都含中文；主控提示要求默认派发且不传 `--name`。devin 轮新增 `dispatch: agent=qwb--e2e-8c270138` 的独立断言。两轮仍只接受 devin 与 cmdc，保留 r3 的物理路径会话级信任覆盖、弹框即失败以及全局项目配置前后比对。

第一次 `bash tests/smoke.sh` rc=1，仅旧 §66 的两条期望仍要求纯哈希名；更新这两条断言后，`/tmp/qwb-r4-smoke-precommit-2.log` rc=0，§83 是 `SMOKE PASS` 前最后一节。代码提交前 `bash bin/qwb-test.sh fast --project "$PWD"` rc=0。

## 真实 Herdr 复放

在执行者自建 named session `qwb-r4-replay-1790215461-31468` 中，用 `/tmp/qwb-r4-replay-8wv00x6v/project` 的安装副本和普通 shell pane `w1:p1` 作投递目标；没有使用 default 或审核会话。原始逐命令与 rc：`/tmp/qwb-r4-replay-8wv00x6v/commands.jsonl`；总日志：`/tmp/qwb-r4-replay-final.log`。

| 末行 | 执行命令 | rc | 账本与 pane 证据 |
|---|---|---:|---|
| 200 个汉字的 `working:` | `bash <临时项目>/qwbuddy/bin/qwb-wake.sh --once --project <临时项目> --pane w1:p1` | 0 | `long-ticket.bin` 恰一条 `wake:`；`long-pane.txt` 含前 160 字符的摘要 |
| `done: SHA=\x80\x82 please verify` | 同上 | 0 | `invalid-ticket.bin` 恰一条 `wake:`；`invalid-pane.txt` 收到 U+FFFD 替换后的合法 UTF-8 摘要 |

`pane read` 对长中文软换行会插入显示空格，复放校验去掉显示空格后逐字符比对 160 字符；第一版复放脚本因直接连续字符串比较而误报，产品投递与 wake 当时已经成功。修正显示层比较后两例通过。`herdr session stop` 与 `delete` 均 rc=0；临时项目和转录留在 `/tmp` 供核查。

## 冻结代码上的真实 E2E

两轮按 devin → cmdc 串行，在执行者 Space `wGR` 的新 tab `wGR:t4` 前台运行，主控 `gpt-6-luna/max`。每轮脚本只在唯一 named session 和 `/tmp` 临时 Git 项目工作，报告列明工具版本、转录与全部断言。

| 工人 | named session | 报告 | 原始 rc | 关键结果 |
|---|---|---|---:|---|
| devin `swe-2-max` | `qwb-e2e-devin-1790215993-98728` | `/tmp/qwb-e2e-devin-556b828.md` | 0 | 中文票、Space、默认 agent 名、提交字节、主控验收及收尾断言全 PASS |
| cmdc `deepseek/deepseek-v4-flash` | `qwb-e2e-cmdc-1790216393-15595` | `/tmp/qwb-e2e-cmdc-556b828.md` | 0 | 中文票、Space、提交字节、主控验收及收尾断言全 PASS |

devin 提交 `72d19a44475f7f4c7ac581cfe19e1306baebe5c7`；cmdc 提交 `3f632f2fe3890765e82e8bc056915e1d1e8d58dc`。两轮主控均在临时候选上独立核对唯一文件字节并运行 fast/full（各 rc=0），快进合并到临时 main、标记 verified、执行 `qwb-worktree.sh finish 真实闭环-e2e --merged`，最后值守无未结项；named session stop/delete 均 rc=0。cmdc 的临时 worktree 曾有 Command Code 生成的 `.commandcode/taste/` 未跟踪文件，主控核实后完成收尾，未进入候选提交。两轮报告的 `config_projects_unchanged` 均 PASS；`~/.codex/config.toml` 跑前、两轮间、跑后 SHA-256 均为 `26363e19c2f95520cd198992e28ef8a93ffcb3123f82c98437b75c7c0edce2d2`。default 会话仅作只读核对。

## 最终门与未验证范围

本执行报告提交后，须在最终提交 SHA 上运行 `bash bin/qwb-test.sh fast --project "$PWD"`，再运行 `bash bin/qwb-test.sh full --project "$PWD" --report /tmp/qwb-full-<SHA前7位>.md`，原始 full 日志存 `/tmp/qwb-full-<SHA前7位>.log`；提交前不能预写该最终 SHA 的结果。最终提交与代码定稿的 `git diff --stat` 应只列本报告。

未验证：没有安装或合并到真实生产项目；没有跑 devin/cmdc 以外的工人；没有测试 Herdr 服务重启恢复。真实 E2E 票没有故意注入非法 UTF-8；该故障由公开 CLI 回归和上述真实 Herdr 投递复放覆盖。
