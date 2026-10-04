#!/usr/bin/env bash
# tests/collab-all.sh —— 已迁票协议（collab-* 等定向测试）并发跑批
# 用法：
#   bash tests/collab-all.sh            # 跑默认清单（下方显式写死的测试）
#   bash tests/collab-all.sh <脚本…>    # 跑指定脚本，替代默认清单（验收失败路径用）
# 每个测试一个后台进程并发跑，stdout+stderr 各写一份日志；全部结束后按清单顺序汇报，
# 末行汇总，任一失败退出码 1。一个失败不影响其他测试的运行与汇报。
#
# 清单内测试使用各自的 mktemp/tempfile 项目与 AF_UNIX 路径，环境变量仅影响该进程。
# 没有发现共享固定文件或端口；并发安全仍须以任务书要求的三连跑验收。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# PATH 替身失效时也不能连现场 Herdr；只为本跑批建仓内日志，不改子测试 TMPDIR。
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
TMPBASE="$ROOT/.qwb-tmp"
mkdir -p "$TMPBASE" || exit 1

# 默认清单：显式写死，不用 glob——新增测试文件必须有人有意接入才进全门。
# collab-land.sh 在 4678ba0 基线退出 1，暂不接入，失败输出另记主账本。
# 根因待主控诊断，本脚本不修改该测试。
DEFAULT_TESTS=(
  tests/collab-ci-diagnostics.sh
  tests/collab-gate.sh
  tests/collab-handoff.sh
  tests/collab-herdr.sh
  tests/collab-ledger.sh
  tests/collab-planning.sh
  tests/collab-posture.sh
  tests/collab-roles.sh
  tests/collab-test-policy.sh
  tests/lint-scenario-stream.sh
  tests/path-canonicalization.sh
)

if [[ $# -gt 0 ]]; then TESTS=("$@"); else TESTS=("${DEFAULT_TESTS[@]}"); fi

TMPD="$(mktemp -d "$TMPBASE/collab-all.XXXXXXXX")" || exit 1
PIDS=()
# shellcheck disable=SC2329 # 仅被下方 trap 字符串间接调用，shellcheck 数据流分析看不出
kill_tree() { # 递归杀整棵进程树：测试会派生 python/git 等子进程，只杀直接子进程会留孤儿
  local pid="$1" k kids
  kids="$(pgrep -P "$pid" 2>/dev/null)"
  for k in $kids; do kill_tree "$k"; done
  kill "$pid" 2>/dev/null || true
}
# shellcheck disable=SC2329 # 同上，由 trap 间接调用
cleanup() { # 退出（含被 INT/TERM 打断）时删临时目录并杀掉仍在跑的测试进程树
  local p
  if [[ "${#PIDS[@]}" -gt 0 ]]; then
    for p in "${PIDS[@]}"; do
      if [[ -n "$p" ]]; then kill_tree "$p"; wait "$p" 2>/dev/null || true; fi
    done
  fi
  rm -rf "$TMPD"
}
trap 'cleanup' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

total=${#TESTS[@]}
# 每个测试自己记退出码+耗时：父进程按清单序 wait，先结束的测试会被后面的等待拖住，
# 到时才读表会把所有测试都报成总时长——所以耗时必须由子进程自己写状态文件。
i=0
while [[ $i -lt $total ]]; do
  ( s=$(date +%s)
    bash "${TESTS[$i]}" >"$TMPD/$i.log" 2>&1
    rc=$?
    printf '%s %s\n' "$rc" "$(( $(date +%s) - s ))" >"$TMPD/$i.st" ) &
  PIDS+=($!)
  i=$((i + 1))
done

# 全部回收后再汇报；清空已回收的 PID，避免退出清理误杀复用该 PID 的其他进程。
for ((i=0; i<total; i++)); do
  wait "${PIDS[$i]}"
  PIDS[i]=""
done

fails=0
for ((i=0; i<total; i++)); do
  rc=1; secs=0
  if [[ -f "$TMPD/$i.st" ]]; then read -r rc secs <"$TMPD/$i.st"; fi
  if [[ "$rc" -eq 0 ]]; then
    printf 'PASS  %s（%ss）\n' "${TESTS[$i]}" "$secs"
  else
    printf 'FAIL  %s（rc=%s，%ss）\n' "${TESTS[$i]}" "$rc" "$secs"
    fails=$((fails + 1))
    tail -n 40 "$TMPD/$i.log"
  fi
done

if [[ "$fails" -eq 0 ]]; then
  printf 'COLLAB-ALL PASS（%s 项）\n' "$total"
  exit 0
fi
printf 'COLLAB-ALL FAIL（%s/%s 项）\n' "$fails" "$total"
exit 1
