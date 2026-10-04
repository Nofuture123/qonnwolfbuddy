#!/usr/bin/env bash
# 全门四段独立日志；全部收齐后按原顺序汇报，失败不取消其他段。
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
# shellcheck source=/dev/null
. "$ROOT/tests/process-fixture.sh"
qwb_test_scope "$@"

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
  qwb_test_drain
}
trap cleanup EXIT

for ((i=0; i<${#STAGES[@]}; i++)); do
  bash "${STAGES[$i]}" >"$QWB_TEST_SCOPE_DIR/$i.log" 2>&1 &
  PIDS+=("$!")
done
rc=0
for ((i=0; i<${#PIDS[@]}; i++)); do
  wait "${PIDS[$i]}" || rc=1
  PIDS[i]=""
done
for ((i=0; i<${#STAGES[@]}; i++)); do
  cat "$QWB_TEST_SCOPE_DIR/$i.log" || rc=1
done
exit "$rc"
