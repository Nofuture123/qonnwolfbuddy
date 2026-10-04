#!/usr/bin/env bash
# 全门四段独立日志；全部收齐后按原顺序汇报，失败不取消其他段。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
mkdir -p "$ROOT/.qwb-tmp" || exit 1
TMPD="$(mktemp -d "$ROOT/.qwb-tmp/full-gate.XXXXXXXX")" || exit 1

STAGES=(tests/smoke.sh tests/review-identity.sh bin/qwb-lint.sh tests/collab-all.sh)
PIDS=()
# shellcheck disable=SC2329 # EXIT trap 调用
cleanup() {
  local p
  for p in "${PIDS[@]}"; do
    [[ -z "$p" ]] || kill "$p" 2>/dev/null || true
  done
  for p in "${PIDS[@]}"; do
    [[ -z "$p" ]] || wait "$p" 2>/dev/null || true
  done
  rm -rf "$TMPD"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

for ((i=0; i<${#STAGES[@]}; i++)); do
  bash "${STAGES[$i]}" >"$TMPD/$i.log" 2>&1 &
  PIDS+=("$!")
done
rc=0
for ((i=0; i<${#PIDS[@]}; i++)); do
  wait "${PIDS[$i]}" || rc=1
  PIDS[i]=""
done
for ((i=0; i<${#STAGES[@]}; i++)); do
  cat "$TMPD/$i.log" || rc=1
done
exit "$rc"
