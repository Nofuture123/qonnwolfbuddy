# 测试桩失效会打到真 Herdr

2026-10-03，全仓审核第 1 波。主控（Claude Code）并行派了五个 Pi 工人，各自在隔离副本里跑全门。

## 经过

1. 一个工人为清理临时文件执行了 `rm -rf <系统临时目录>/tmp.*`，把另一个工人正在跑的 `tests/smoke.sh` 的 `$TMP` 整个删掉。
2. smoke 的假 herdr 在 `$TMP/stubbin`，只靠 `PATH` 前置遮住真 herdr。桩没了之后，后续各节的 `herdr` 调用全部打到真服务。
3. 真 Herdr 里多出两个 Space（`wtproj`、`wtsetup`），另一个项目的主控 workspace 里多出 6 个 tab，每个都起了真 Pi 并收到测试夹具票的提示词。Rocky 发现后要求查清并禁止。主控按「cwd 位于该次 smoke 的临时目录」逐个核对后关闭。

## 教训

- **测试必须失效关闭**：隔离不能只靠「桩排在 PATH 前面」。连接目标（`HERDR_SOCKET_PATH` 等）要先指向死路径，桩不在时宁可失败。
- **任务书必须写明禁止通配删除**：只许删自己 `mktemp` 出的确切路径。「临时目录自己建自己删」这句话不够。
- **测试临时目录放在本项目内**（Rocky 2026-10-03）：不往系统目录、不往 Herdr 根层级或别的项目的 workspace 里开东西。
- 并行验收时出现与被验代码无关的「No such file or directory」，先查各工人会话记录里的 `rm`。

## 同日另一条纠正：排 pi 不要自己指定模型

Rocky 说「排 pi」，主控照 9 月 24 日的旧记忆给工人显式传了 `--model zai-coding-cn/glm-5.3-flash`，而 pi 当时的默认已是 magpie `codex/gpt-6.1-sol` high。Rocky 叫停并要求立刻切换。派工前先读 `~/.pi/agent/settings.json` 现查默认；模型以当轮指令为准，历史路由不是默认。
