#!/usr/bin/env bash
# qwb-lock.sh —— 主控锁：mkdir 原子目录锁，防两个主控同时动手
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-lock.sh <acquire|release|status> [选项]

  acquire   抢锁：建 qwbuddy/.controller.lock 目录并写 owner 文件；已被占用则先判活：
            锁主 pid 已退出 / pane 已不存在 → 自动回收残留锁后重新获锁；
            锁主仍活或查不出死活（herdr 不在 PATH / 查询报错）→ 拒绝（fail-closed，不猜）
  release   放锁：删除锁目录（只在确认是残留锁时用；不做自动夺锁）
  status    查锁：打印锁主或「无锁」

选项:
  --project <根>    项目根（默认：当前目录）
  --owner <标识>    锁主标识（pane_id 或 pid；默认：${HERDR_PANE_ID}，否则 pid:<本进程>）
  -h, --help        显示本帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  acquire|release|status) CMD="$1"; shift ;;
  *) echo "错误：需要子命令 acquire|release|status" >&2; usage >&2; exit 2 ;;
esac

PROJECT_ROOT="$(pwd)"; OWNER=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
ME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
LOCK_DIR="$PROJECT_ROOT/qwbuddy/.controller.lock"
OWNER="${OWNER:-${HERDR_PANE_ID:-pid:$$}}"

lock_holder() {
  if [[ -f "$LOCK_DIR/owner" ]]; then cat "$LOCK_DIR/owner"; else echo "（无 owner 文件）"; fi
}

# 残留锁判活：owner 形如 pid:<n> 用 kill -0；其余视为 herdr pane id 查 pane get。
# 返回：0 = 死（可回收，stdout 打印原锁主）；1 = 活；2 = 无法判活（herdr 不在 PATH / 查询失败 / 无 owner 文件）
lock_holder_dead() {
  local holder_id="$1"
  case "$holder_id" in
    pid:*)
      local npid="${holder_id#pid:}"
      [[ "$npid" =~ ^[0-9]+$ ]] || return 2
      kill -0 "$npid" 2>/dev/null && return 1
      return 0
      ;;
    "") return 2 ;;   # 无 owner 文件/解析不出：无法判活
    *)
      command -v herdr >/dev/null 2>&1 || return 2   # herdr 不在 PATH：无法判活
      local pout="" prc=0
      pout="$(herdr pane get "$holder_id" 2>&1)" || prc=$?
      if [[ "$prc" -ne 0 ]]; then
        if printf '%s' "$pout" | grep -q 'pane_not_found'; then return 0; fi
        return 2   # 其他查询失败：无法判活（fail-closed）
      fi
      return 1   # pane 查得到 → 活锁
      ;;
  esac
}

case "$CMD" in
  acquire)
    [[ -d "$PROJECT_ROOT/qwbuddy" ]] || { echo "错误：${PROJECT_ROOT}/qwbuddy 不存在（先跑 qwb-init.sh）" >&2; exit 1; }
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OWNER" > "$LOCK_DIR/owner"
      echo "已获锁：${OWNER}（${LOCK_DIR}）"
    else
      holder="$(lock_holder)"
      holder_id="$(sed -n 's/^[^ ]*[[:space:]]*//p' "$LOCK_DIR/owner" 2>/dev/null | head -1)"
      lhd=2
      lock_holder_dead "$holder_id" && lhd=0 || lhd=$?
      if [[ "$lhd" -eq 0 ]]; then
        if rm -rf "$LOCK_DIR" && mkdir "$LOCK_DIR" 2>/dev/null; then
          printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$OWNER" > "$LOCK_DIR/owner"
          echo "回收残留锁（原锁主 ${holder_id} 已不存在）"
          echo "已获锁：${OWNER}（${LOCK_DIR}）"
        else
          echo "错误：锁已被占用：${LOCK_DIR}；残留锁回收时又被并发抢走（两次 mkdir 都失败），本次拒绝" >&2
          exit 1
        fi
      else
        echo "错误：锁已被占用：${LOCK_DIR}；锁主：${holder}" >&2
        [[ "$lhd" -eq 2 ]] && echo "说明：无法判活（herdr 不在 PATH 或 pane 查询失败），故不回收残留锁（fail-closed，不猜）" >&2
        echo "确认是残留锁后手动释放：bash ${ME} release --project ${PROJECT_ROOT}" >&2
        exit 1
      fi
    fi
    ;;
  release)
    if [[ -d "$LOCK_DIR" ]]; then
      rm -rf "$LOCK_DIR"
      echo "已释放：${LOCK_DIR}"
    else
      echo "无锁：${LOCK_DIR}"
    fi
    ;;
  status)
    if [[ -d "$LOCK_DIR" ]]; then
      echo "有锁：$(lock_holder)（${LOCK_DIR}）"
    else
      echo "无锁：${LOCK_DIR}"
    fi
    ;;
esac
