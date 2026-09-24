# QWB 生产优化 r3 返修执行记录

起点 `7ae8cadfe2e826945b8bbfee70d0c894a20c1c26`；真实 E2E 的代码定稿 `a08c7fdbb1cd3652d63ad9243707943fe5474401`。本轮按审点 1 → 审点 2 → 真实 E2E 的顺序执行，未 push、未合并本分支、未开新分支或触碰其他真实项目。E2E 仅在隔离临时 Git 项目和新建 named Herdr session 中运行；本执行报告是代码定稿后的文档提交。

## 逐项返修与验证

1. **非法 UTF-8 账本**：`qwb-status.sh`、`qwb-wake.sh`、`qwb-lint.sh`、`qwb-run.sh`、`qwb-worktree.sh` 的账本解析固定按字节处理；`qwb-lib.sh` 用严格 UTF-8 解码检查账本。无效字节不能再把运行票从 status、wake 或 worktree list 隐去；lint 明确报错且不显示假 PASS，派发场景/规格缺陷及门判断保持稳定。公开 CLI 回归 `tests/invalid-ledger.py` 覆盖 state 行、state 后、done、working、场景、疑点、已验证票共 7 组。原基线导出副本上第一组即红：`/tmp/qwb-r3-ledger-red-ambq6sa4/baseline-red.log`，原始失败为 `tr: Illegal byte sequence`，status 未列出运行票；修复后 `python3 -B tests/invalid-ledger.py` rc=0，输出 `INVALID LEDGER PASS`。`tests/smoke.sh` §82 纳入该公开 CLI 回归；`/tmp/qwb-r3-smoke-precommit-2.log` rc=0，§82 是 `SMOKE PASS` 前最后一节。
2. **工人启动文档**：`docs/DECISIONS.md` 追加当前入口决定，保留旧决定作为历史；`templates/worker-launch-guide.md` 更新为 devin / `cmdc` 实际参数；`tests/smoke.sh` §47 的多词 argv 样例换为 `zcode tui` 并明确仅为模拟 argv 测试。zcode 0.16.9 当前不能被本机 Herdr 0.9.1 识别，写文件默认要审批；按使用者决定，本轮不使用 zcode、不开发集成，也不把该模拟用例视为可用工人验收。pi-kimi 预设与轮次均未加入。
3. **真实 E2E 脚本**：新增 `tests/e2e-real.sh`、`tests/e2e-real.py`，只接受 devin/cmdc。每轮用唯一 named session、隔离项目、真实交互 Codex 主控和真实工人；定期保存 Herdr/账本/主控与工人转录，对账本、Git、Space、主控结果和 default 会话作独立断言，结束时停止并删除本轮 session。Codex 以物理 `/private/tmp/.../project` 路径传入 `-c projects."<路径>".trust_level="trusted"` 和同路径的 `projects` 表覆盖，信任框若出现立即失败且不按键；运行前后比对全局 `config.toml` 的项目条目，有新增或修改即失败并列入报告。真实 E2E 有模型花费、外部结果不确定且要求 CLI 登录，因此不纳入 fast/full；合并生产相关改动前和安装到生产项目前必须在冻结候选上另跑。

## 真实 E2E：代码定稿 `a08c7fdbb1cd3652d63ad9243707943fe5474401`

两轮串行，均在执行者 Space `wGR` 新建的 tab `wGR:t3` 前台运行，主控 `gpt-6-luna/max`。每轮开始均打印模型；只修改临时项目。逐命令日志、转录、Space 前后 JSON 和完整断言在各报告所列临时目录中。

| 顺序 | 工人 | named session | 报告 | 原始 rc | 结果 |
|---|---|---|---|---:|---|
| 1 | devin `swe-2-max`（herdr） | `qwb-e2e-devin-1790212795-32086` | `/tmp/qwb-e2e-devin-a08c7fd.md` | 0 | 8 项独立断言及配置不变检查全 PASS；session stop/delete 均 rc=0 |
| 2 | cmdc `deepseek/deepseek-v4-flash`（pane-run） | `qwb-e2e-cmdc-1790213209-63895` | `/tmp/qwb-e2e-cmdc-a08c7fd.md` | 0 | 同上；session stop/delete 均 rc=0 |

devin 工人提交 `0edd51c6122210243d75e3f3648e5d0bb576020d`；cmdc 工人提交 `f5723807ee4554ec9961632f4c161b5b7f315f02`。两轮主控均独立核对唯一新增文件的提交 blob 与 nonce 字节，候选 fast/full 退出码均为 0，快进到临时 main、标记 verified、执行 `qwb-worktree.sh finish e2e --merged`，最后值守报告无未结项。cmdc 首次收尾因 Command Code 在临时 worktree 生成的未跟踪 `.commandcode/taste/` 被拒；主控核实并只清理该临时工件后重试成功。两轮报告都显示 `config_projects_unchanged=PASS`、新增/修改/删除均为空；default 会话只读核对通过。

早期试跑不作为验收：第一版信任处理按 Enter，导致四个临时项目被 Codex 写入全局信任记录；后续脚本已改为弹框即失败。`ea2ab5d` 试跑证明弹框拒绝 rc=1 且无新增记录；`06f6f22` 试跑的真实 devin 工作流完成，但脚本误把 Herdr 首次列表中未附带的主 Space worktree 元数据当作清理失败，报告 rc=1。该断言用保存的前后 JSON 修正并在最终代码 SHA 上重跑两轮。

两轮最终通过后，先将全局配置备份为 `/tmp/qwb-r3-config-before-cleanup.toml`（0600），再只删除本轮早期试跑新增的四个 `[projects."/private/tmp/qwb-e2e-devin.*/project"]` 块。删前删后逐行 diff 为 `/tmp/qwb-r3-config-cleanup.diff`；路径清单和 SHA-256 见 `/tmp/qwb-r3-config-cleanup-proof.json`。TOML 解析核对其余值未变，先前已有的 `/private/tmp/qwb-e2e-codex` 条目保留；最后的两轮没有新增配置条目。

## 门与边界

代码定稿前 `bash tests/smoke.sh` rc=0，最后测试节为 §82；`bash bin/qwb-test.sh fast --project "$PWD"` rc=0。文档提交后须在**最终提交 SHA** 运行 `bash bin/qwb-test.sh fast --project "$PWD"` 和 `bash bin/qwb-test.sh full --project "$PWD" --report /tmp/qwb-full-<最终SHA前7位>.md`，将 full 原始输出存 `/tmp/qwb-full-<最终SHA前7位>.log`；提交前不能预写最终 SHA 的门结果。

未验证：没有对真实生产项目安装或合并；没有跑 zcode、pi-kimi 或其他工人；没有做 Herdr 重启恢复。两轮真实账本均是有效 UTF-8，非法字节场景由上述 7 组公开 CLI 回归验证。临时项目和转录留在 `/tmp` 供复核，named session 已清理。
