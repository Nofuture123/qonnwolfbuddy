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

SELF_BIN="${BASH_SOURCE[0]:-$0}"
QWB_DIR="$(cd "$(dirname "$SELF_BIN")/.." && pwd)"   # <项目>/qwbuddy
ROOT="$(cd "$QWB_DIR/.." && pwd)"                     # 项目根
HOOK_LOCK="$QWB_DIR/.hook.lock"

# 只在短暂的接管/释放临界区持有目录 inode 的内核锁；值守期间不占住主控正常锁操作。
# 内部命令由带 flock 的 Perl 调用，FD 随子 Bash 继承；崩溃后内核自动释放。
if [[ "${1:-}" == --lock-acquire || "${1:-}" == --lock-release ]]; then
  [[ "${QWB_HOOK_GUARDED:-}" == "$PPID" ]] || exit 1
  mode="$1"; token="$2"; hook_pid="$3"
  if [[ "$mode" == --lock-acquire ]]; then
    if [[ -d "$HOOK_LOCK" ]]; then
      oldpid="$(cat "$HOOK_LOCK/pid" 2>/dev/null || true)"
      [[ "$oldpid" =~ ^[0-9]+$ ]] && kill -0 "$oldpid" 2>/dev/null && exit 1
      rm -rf "$HOOK_LOCK" || exit 1
    fi
    mkdir "$HOOK_LOCK" || exit 1
    printf '%s\n' "$hook_pid" > "$HOOK_LOCK/pid" || exit 1
    printf '%s\n' "$token" > "$HOOK_LOCK/token" || exit 1
  else
    [[ "$(cat "$HOOK_LOCK/token" 2>/dev/null || true)" == "$token" ]] || exit 0
    [[ "$(cat "$HOOK_LOCK/pid" 2>/dev/null || true)" == "$hook_pid" ]] || exit 0
    rm -rf "$HOOK_LOCK"
  fi
  exit $?
fi

cat >/dev/null 2>&1 || true   # 消费 stdin 的 hook JSON（本脚本不读内容，但不能堵住管道）

# 1) 守卫：只有持有主控锁的 Claude 会话值守；锁不存在同样不值守。此路径不得有任何耗时副作用。
owner=""
if [[ -f "$QWB_DIR/.controller.lock/owner" ]]; then
  owner="$(awk 'NF { v=$NF } END { print v }' "$QWB_DIR/.controller.lock/owner" 2>/dev/null || true)"
fi
if [[ -z "$owner" || "$owner" != "${HERDR_PANE_ID:-}" ]]; then
  exit 0
fi

# 2) 单飞：Claude Code 不去重 async hook，每个 Stop 都会触发本脚本；同一时刻只允许一个 --block。
guard_lock() {
  perl -MFcntl=:flock,F_GETFD,F_SETFD,FD_CLOEXEC -e '
    my ($dir, @cmd) = @ARGV;
    open my $guard, "<", $dir or die "hook guard open: $!\n";
    flock($guard, LOCK_EX) or die "hook guard flock: $!\n";
    my $flags = fcntl($guard, F_GETFD, 0);
    defined($flags) && fcntl($guard, F_SETFD, $flags & ~FD_CLOEXEC)
      or die "hook guard fd: $!\n";
    $ENV{QWB_HOOK_GUARDED} = $$;
    my $rc = system @cmd;
    exit 1 if $rc == -1;
    exit 128 + ($rc & 127) if $rc & 127;
    exit $rc >> 8;
  ' "$QWB_DIR" bash "$SELF_BIN" "$1" "$HOOK_TOKEN" "$$"
}
HOOK_TOKEN="$$:$(date +%s):${RANDOM}"
if ! guard_lock --lock-acquire 2>> "$QWB_DIR/.hook.err"; then
  exit 0
fi
trap 'guard_lock --lock-release 2>/dev/null || true' EXIT
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
