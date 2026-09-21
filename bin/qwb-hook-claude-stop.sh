#!/usr/bin/env bash
# qwb-hook-claude-stop.sh —— Claude Code Stop hook（asyncRewake）值守入口：无窗口值守
#
# qwb-init.sh 往目标项目 .claude/settings.json 合并（幂等）：
#   {"type":"command","command":"bash \"$CLAUDE_PROJECT_DIR\"/qwbuddy/bin/qwb-hook-claude-stop.sh",
#    "asyncRewake":true,"timeout":7200}
#
# 语义三方核实（2026-09，claude 2.1.278 + code.claude.com/docs/en/hooks.md + 真机 E2E，不凭 firstmate 转述）：
#   - hook 的 timeout 字段单位是「秒」（文档 "Seconds before canceling"）：7200 = 2 小时，
#     与 config.sh 的 QWB_HOOK_MAX_MS=7200000（毫秒）对齐；timeout 对 asyncRewake hook 仍生效。
#   - asyncRewake=true：后台运行、不阻塞 turn；exit 2 时唤醒 Claude（Stop 事件 exit 2 效果 =
#     "Prevents Claude from stopping, continues the conversation"）；stderr（为空才退回 stdout）
#     以 system reminder 交付。本脚本把摘要 stdout 与 stderr 双写，两条通道任一生效都能到模型。
#   - async hook 每次 Stop 都触发、不去重（文档 "no deduplication"）→ 本脚本用 .hook.lock 单飞。
#   - hook 出错绝不能卡主控：一切错误写 qwbuddy/.hook.err 后 exit 0。
set -uo pipefail

cat >/dev/null 2>&1 || true   # 消费 stdin 的 hook JSON（本脚本不读内容，但不能堵住管道）

SELF_BIN="${BASH_SOURCE[0]:-$0}"
QWB_DIR="$(cd "$(dirname "$SELF_BIN")/.." && pwd)"   # <项目>/qwbuddy
ROOT="$(cd "$QWB_DIR/.." && pwd)"                     # 项目根

# 1) 守卫：只有持有主控锁的 Claude 会话值守；锁不存在同样不值守。此路径不得有任何耗时副作用。
owner=""
if [[ -f "$QWB_DIR/.controller.lock/owner" ]]; then
  owner="$(awk 'NF { v=$NF } END { print v }' "$QWB_DIR/.controller.lock/owner" 2>/dev/null || true)"
fi
if [[ -z "$owner" || "$owner" != "${HERDR_PANE_ID:-}" ]]; then
  exit 0
fi

# 2) 单飞：Claude Code 不去重 async hook，每个 Stop 都会触发本脚本；同一时刻只允许一个 --block。
HOOK_LOCK="$QWB_DIR/.hook.lock"
take_lock() {
  if mkdir "$HOOK_LOCK" 2>/dev/null; then
    printf '%s\n' "$$" > "$HOOK_LOCK/pid" 2>/dev/null || true
    return 0
  fi
  local lpid=""
  lpid="$(cat "$HOOK_LOCK/pid" 2>/dev/null || true)"
  if [[ -n "$lpid" ]] && kill -0 "$lpid" 2>/dev/null; then
    return 1   # 已有活的单飞实例：立即让位
  fi
  # 残留死锁（宿主被 SIGKILL/断电等）：接管
  rm -rf "$HOOK_LOCK" 2>/dev/null || true
  mkdir "$HOOK_LOCK" 2>/dev/null || return 1   # 并发接管失败：本轮放弃，下次 Stop 再试
  printf '%s\n' "$$" > "$HOOK_LOCK/pid" 2>/dev/null || true
  return 0
}
if ! take_lock; then
  exit 0
fi
QWB_HOOK_LOCKDIR="$HOOK_LOCK"        # 须全局：EXIT 触发时本函数已不在栈上
trap 'rm -rf "$QWB_HOOK_LOCKDIR"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# 3) 前台阻塞值守：exit 2 = 有可动作变化（摘要交回模型）；0/124 = 安静退出；其他 = 错误不卡主控
# shellcheck source=/dev/null
if [[ -f "$QWB_DIR/config.sh" ]]; then . "$QWB_DIR/config.sh"; fi
MAX_MS="${QWB_HOOK_MAX_MS:-7200000}"
[[ "$MAX_MS" =~ ^[1-9][0-9]*$ ]] || MAX_MS=7200000

set +e
hook_out="$(bash "$QWB_DIR/bin/qwb-wake.sh" --project "$ROOT" --block --max-ms "$MAX_MS" 2>&1)"
hook_rc=$?
set -u

case "$hook_rc" in
  2)
    # 摘要双写：文档说 stderr 优先交付、stderr 空才用 stdout——双写保证任一通道都到模型。
    printf '%s\n' "$hook_out"
    printf '%s\n' "$hook_out" >&2
    exit 2
    ;;
  0|124)
    exit 0
    ;;
  *)
    {
      echo "qwb-hook-claude-stop.sh：qwb-wake.sh --block 异常退出 rc=${hook_rc}（$(date -u +%Y-%m-%dT%H:%M:%SZ)）"
      printf '%s\n' "$hook_out"
    } >> "$QWB_DIR/.hook.err" 2>/dev/null || true
    exit 0   # hook 出错不能卡死主控
    ;;
esac
