#!/usr/bin/env bash
# tests/collab-all.sh —— 已迁票协议（collab-* 等定向测试）并发跑批
# 用法：
#   bash tests/collab-all.sh            # 跑默认清单（下方显式写死的测试）
#   bash tests/collab-all.sh <脚本…>    # 跑指定脚本，替代默认清单（验收失败路径用）
# 每个测试一个后台进程，最多四项同时跑，stdout+stderr 各写一份日志；结束后按清单顺序汇报，
# 末行汇总，任一失败退出码 1。一个失败不影响其他测试的运行与汇报。
#
# 清单内测试使用各自的 mktemp/tempfile 项目与 AF_UNIX 路径，环境变量仅影响该进程。
# 入口清理回归在自己的源码导出目录内发 TERM、检查残留，不观察其他并发测试的目录。
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1
# PATH 替身失效时也不能连现场 Herdr；只为本跑批建仓内日志，不改子测试 TMPDIR。
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
TMPBASE="$ROOT/.qwb-tmp"

# 默认 15 项：每项显式指定解释器和脚本，不用 glob；新增文件须有入口或具名豁免。
# collab-land.sh 覆盖本地 land 与收尾恢复，三个 Python 回归覆盖进程夹具、TERM 清理与 socket 路径。
DEFAULT_TESTS=(
  'bash tests/collab-ci-diagnostics.sh'
  'bash tests/collab-gate.sh'
  'bash tests/collab-handoff.sh'
  'bash tests/collab-herdr.sh'
  'bash tests/collab-land.sh'
  'bash tests/collab-ledger.sh'
  'bash tests/collab-planning.sh'
  'bash tests/collab-posture.sh'
  'bash tests/collab-roles.sh'
  'bash tests/collab-test-policy.sh'
  'bash tests/lint-scenario-stream.sh'
  'bash tests/path-canonicalization.sh'
  'python3 tests/process-fixture-check.py'
  'python3 tests/process-entry-cleanup.py'
  'python3 tests/socket-path-regression.py'
)

# 只读入口自检：在建立跑批日志或启动任何测试之前执行，指定脚本也不能绕过。
python3 -B - "${DEFAULT_TESTS[@]}" <<'PY' || exit $?
from collections import Counter
from pathlib import Path
import re
import sys

files = {p.as_posix(): p.read_text() for p in sorted(Path('tests').rglob('*'))
         if p.is_file() and p.suffix in {'.sh', '.py', '.mjs'}}
# 仅两个付费手工入口豁免；夹具已有文件名引用，不需要按目录或模式放行。
exempt = {
    'tests/e2e-real.sh': '连接真实 Herdr、启动付费模型的手工验收入口',
    'tests/e2e-real.py': '付费手工验收实现，仅由手工入口调用',
}
covered = {entry.split(' ', 1)[1]: '默认清单' for entry in sys.argv[1:]}
covered['tests/smoke.sh'] = 'smoke 入口'
covered.update({name: '豁免：' + reason for name, reason in exempt.items() if name in files})
pending = [name for name in covered if name not in exempt]
names = Counter(Path(name).name for name in files)
patterns = {name: re.compile(r'(?<![\w.-])' + re.escape(
                name if names[Path(name).name] > 1 else Path(name).name) + r'(?![\w.-])')
            for name in files}


def admit(content, reason):
    for name, pattern in patterns.items():
        if name not in covered and pattern.search(content):
            covered[name] = reason
            pending.append(name)


config = '\n'.join(line for line in Path('qwb.config.sh').read_text().splitlines()
                   if re.match(r'^QWB_GATE_(FAST|FULL)=', line))
admit(config, 'qwb.config.sh 门命令引用')
# 只从已有入口向下追踪；互相引用但无人调用的文件仍会失败。
for source in pending:
    if source not in files:
        print('错误：测试入口文件不存在：' + source, file=sys.stderr)
        sys.exit(1)
    # 跑批入口的清单已通过 argv 提供，不把自检或豁免声明当作测试调用。
    if source != 'tests/collab-all.sh':
        admit(files[source], '被 ' + source + ' 引用')
orphans = sorted(files.keys() - covered.keys())
if orphans:
    print('错误：以下测试文件没有入口：', file=sys.stderr)
    for name in orphans:
        print('  ' + name, file=sys.stderr)
    print('请加入 collab-all.sh 默认清单、由 smoke.sh/qwb.config.sh 门命令或已有入口测试按文件名引用，'
          '或加入显式豁免名单并逐项说明理由。', file=sys.stderr)
    sys.exit(1)
print(f'测试入口自检 PASS（{len(files)} 个文件）')
PY

if [[ $# -gt 0 ]]; then
  TESTS=()
  for script in "$@"; do
    case "$script" in
      *.py) TESTS+=("python3 $script") ;;
      *.mjs) TESTS+=("node $script") ;;
      *) TESTS+=("bash $script") ;;
    esac
  done
else
  TESTS=("${DEFAULT_TESTS[@]}")
fi

mkdir -p "$TMPBASE" || exit 1

TMPD="$(mktemp -d "$TMPBASE/collab-all.XXXXXXXX")" || exit 1
PIDS=()
# shellcheck disable=SC2329 # EXIT trap 调用
cleanup() { # 通知各测试的监督器，等待进程与目录清理结束再删除日志。
  local p
  if [[ "${#PIDS[@]}" -gt 0 ]]; then
    for p in "${PIDS[@]}"; do
      [[ -z "$p" ]] || kill "$p" 2>/dev/null || true
    done
    for p in "${PIDS[@]}"; do
      [[ -z "$p" ]] || wait "$p" 2>/dev/null || true
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
# 先启动最慢四项，避免 socket 回归排在短项之后；输出仍按 TESTS 原序。
ORDER=()
for name in tests/collab-gate.sh tests/socket-path-regression.py tests/collab-herdr.sh tests/collab-land.sh; do
  for ((i=0; i<total; i++)); do
    [[ "${TESTS[$i]#* }" != "$name" ]] || ORDER+=("$i")
  done
done
for ((i=0; i<total; i++)); do
  case " ${ORDER[*]-} " in *" $i "*) ;; *) ORDER+=("$i") ;; esac
  PIDS[i]=""
done

# ponytail: 四个槽限制进程开销；仅在同机实测证明更快时增加。
next=0; running=0
while [[ "$next" -lt "$total" || "$running" -gt 0 ]]; do
  while [[ "$next" -lt "$total" && "$running" -lt 4 ]]; do
    i=${ORDER[$next]}
    ( s=$(date +%s)
      read -r interpreter script <<< "${TESTS[$i]}"
      "$interpreter" "$script" >"$TMPD/$i.log" 2>&1 &
      child=$!
      trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 130' INT
      trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' TERM
      wait "$child"
      rc=$?
      trap - INT TERM
      printf '%s %s\n' "$rc" "$(( $(date +%s) - s ))" >"$TMPD/$i.st" ) &
    PIDS[i]=$!
    next=$((next + 1)); running=$((running + 1))
  done
  for ((i=0; i<total; i++)); do
    [[ -n "${PIDS[$i]}" ]] || continue
    if [[ -f "$TMPD/$i.st" ]] || ! kill -0 "${PIDS[$i]}" 2>/dev/null; then
      wait "${PIDS[$i]}" || true
      PIDS[i]="" # 退休已回收的 PID，避免退出清理误杀复用它的其他进程。
      running=$((running - 1))
    fi
  done
  [[ "$running" -eq 0 ]] || sleep .05
done

fails=0
for ((i=0; i<total; i++)); do
  rc=1; secs=0
  if [[ -f "$TMPD/$i.st" ]]; then read -r rc secs <"$TMPD/$i.st"; fi
  if [[ "$rc" -eq 0 ]]; then
    printf 'PASS  %s（%ss）\n' "${TESTS[$i]#* }" "$secs"
  else
    printf 'FAIL  %s（rc=%s，%ss）\n' "${TESTS[$i]#* }" "$rc" "$secs"
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
