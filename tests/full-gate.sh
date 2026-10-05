#!/usr/bin/env bash
# 全门四段并发收齐后按原顺序汇报，再串行量订阅回收；失败不取消后续段。
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
  QWB_FULL_GATE_REAP=1 bash "${STAGES[$i]}" >"$TMPD/$i.log" 2>&1 &
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
# Keep the serial probe supervised and visible to the same interruption cleanup.
python3 -B "$ROOT/tests/process_fixture.py" --command \
  python3 -B "$ROOT/tests/subscribe-reap.py" >"$TMPD/reap.log" 2>&1 &
PIDS=("$!")
wait "${PIDS[0]}" || {
  echo "FAIL  订阅子进程回收公开入口回归" >>"$TMPD/reap.log"
  rc=1
}
PIDS[0]=""
cat "$TMPD/reap.log" || rc=1
exit "$rc"
