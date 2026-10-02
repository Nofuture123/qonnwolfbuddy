#!/usr/bin/env bash
# qwb-test.sh —— 快门/全门执行器：读项目声明的 QWB_GATE_FAST/QWB_GATE_FULL，原样执行
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-test.sh <fast|full> [--project <根>] [--report <新文件>]

执行项目声明的质量门：
  fast  快门（QWB_GATE_FAST）：快、无外部依赖，改一行跑它
  full  全门（QWB_GATE_FULL）：完整检查，合并前跑

配置来源（按序取第一个存在的）：
  <项目>/qwbuddy/config.sh    装过 QW buddy 的项目
  <项目>/qwb.config.sh        母本仓自用回退（母本仓是模板源，不给自己装 qwbuddy/）

门命令以 bash -c 在**项目根目录**下执行；stdout/stderr 原样转发，退出码透传。
门未声明时报错并给出正确写法；门失败时额外打印一行「门失败」到 stderr。

选项:
  --project <根>    项目根（默认：当前目录）
  --report <新文件>  可选 Markdown 执行报告；目标必须尚不存在
  --task <票> --ledger-project <主项目> --op <本人claim>
                    按票检查，report必填且在候选之外，输出candidate-bound JSON收据
                    --project必须是获授权候选；rc0不自动accepted/verified
                    同条件有效收据自动复用，report写复用依据；--rerun显式重测
  -h, --help        显示本帮助
EOF
}

GATE=""; PROJECT_ROOT="$(pwd)"; REPORT=""; REPORT_SET=0
TASK=""; LEDGER_PROJECT=""; OP=""; RERUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    fast|full)
      [[ -z "$GATE" ]] || { echo "错误：门只能选一个（fast|full）" >&2; exit 2; }
      GATE="$1"; shift ;;
    --project) PROJECT_ROOT="${2:-}"; shift 2 ;;
    --rerun) RERUN=1; shift ;;
    --task|--ledger-project|--op)
      [[ -n "${2:-}" && "$2" != --* ]] || { echo "错误：$1 缺值" >&2; exit 2; }
      case "$1" in --task) TASK="$2" ;; --ledger-project) LEDGER_PROJECT="$2" ;; --op) OP="$2" ;; esac
      shift 2 ;;
    --report)
      case "${2:-}" in
        ''|--project|--report|--task|--ledger-project|--op|--help|-h) echo "错误：--report 缺值或重复" >&2; exit 2 ;;
      esac
      [[ "$REPORT_SET" -eq 0 ]] || { echo "错误：--report 缺值或重复" >&2; exit 2; }
      REPORT="$2"; REPORT_SET=1; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$GATE" ]] || { echo "错误：需要 <fast|full>" >&2; usage >&2; exit 2; }
[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

CONF="$PROJECT_ROOT/qwbuddy/config.sh"
[[ -f "$CONF" ]] || CONF="$PROJECT_ROOT/qwb.config.sh"
[[ -f "$CONF" ]] || { echo "错误：找不到配置（试过 qwbuddy/config.sh 与 qwb.config.sh）：${PROJECT_ROOT}" >&2; exit 1; }

QWB_GATE_FAST=""; QWB_GATE_FULL=""
# shellcheck source=/dev/null
. "$CONF"

if [[ "$GATE" == "fast" ]]; then VAR="QWB_GATE_FAST"; CMD="$QWB_GATE_FAST"; else VAR="QWB_GATE_FULL"; CMD="$QWB_GATE_FULL"; fi

if [[ -z "$CMD" ]]; then
  cat >&2 <<EOF
错误：本项目尚未声明质量门（${CONF} 的 ${VAR} 为空/缺失）——请编辑 ${CONF} 填写 QWB_GATE_FAST / QWB_GATE_FULL（示例写法，命令在项目根下执行，按项目布局调路径）：
  QWB_GATE_FAST='for f in bin/*.sh tests/smoke.sh; do bash -n "\$f" || exit 1; done && shellcheck bin/*.sh'
  QWB_GATE_FULL="bash tests/smoke.sh && bash bin/qwb-lint.sh"
EOF
  exit 1
fi

# 按票薄封装：候选外JSON收据；门命令仍是上面同一配置命令，不另造测试策略。
if [[ -n "$TASK$LEDGER_PROJECT$OP" ]]; then
  [[ -n "$TASK" && -n "$LEDGER_PROJECT" && -n "$OP" && "$REPORT_SET" -eq 1 ]] || { echo '错误：按票检查需要task/ledger-project/op/report' >&2; exit 2; }
  BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  context() { bash "$BINDIR/qwb-ledger.sh" gate-context --project "$LEDGER_PROJECT" --task "$TASK" -- "$OP" "$@"; }
  BEFORE="$(context)" || exit 2
  REPORT_PATH="$(python3 -B - "$PROJECT_ROOT" "$REPORT" "$BEFORE" "$GATE" "$CMD" <<'PY'
import hashlib,json,sys
from pathlib import Path
root,report,raw,gate,cmd=sys.argv[1:]; c=json.loads(raw); p=Path(report).absolute()
try:
    assert p.parent.is_dir() and not p.exists() and not p.is_symlink(), '报告须新文件且父目录存在'
    p=p.parent.resolve()/p.name; candidate=Path(c['candidate'])
    assert candidate==Path(root).resolve() and c['status']=='clean', '实际候选不符或dirty'
    assert p!=candidate and candidate not in p.parents, '报告必须位于候选之外'
    assert c['commands'].get(gate)==hashlib.sha256(cmd.encode()).hexdigest(), '命令未授权或配置变化'
    print(p)
except AssertionError as e:
    print('按票检查拒绝: '+str(e),file=sys.stderr); sys.exit(2)
PY
)" || exit 2
  if [[ "$RERUN" -eq 0 && "$BEFORE" == *'"test_policy_sha256":'* ]] && REUSE="$(bash "$BINDIR/qwb-ledger.sh" gate-reuse --project "$LEDGER_PROJECT" --task "$TASK" -- "$OP" "$GATE" 2>/dev/null)"; then
    AFTER="$(context)" || exit 2
    python3 -B - "$REPORT_PATH" "$REUSE" "$BEFORE" "$AFTER" <<'PY'
import json,os,sys,tempfile
path,raw,before,after=sys.argv[1:]; r=json.loads(raw)
assert r['basis']==json.loads(before)==json.loads(after), '复用采样间对象/条件变化'
r['schema']='qwb-reused-receipt-v1'
fd,tmp=tempfile.mkstemp(prefix='.qwb-reuse-',dir=os.path.dirname(path))
try:
    with os.fdopen(fd,'w') as f:json.dump(r,f,ensure_ascii=False,sort_keys=True);f.write('\n');f.flush();os.fsync(f.fileno())
    os.link(tmp,path)
finally:os.unlink(tmp)
PY
    echo "复用可信收据（${GATE}）：${REUSE}" >&2
    exit 0
  fi
  STARTED_AT="$(date +%s)" || { echo '错误：无法记录开始时间，门未执行' >&2; exit 2; }
  rc=0; (cd "$PROJECT_ROOT" && bash -c "$CMD") || rc=$?
  ENDED_AT="$(date +%s)" || {
    echo '错误：结束时间元信息无法记录，不发布可信收据' >&2
    [[ "$rc" -ne 0 ]] || rc=3
    exit "$rc"
  }
  AFTER="$(context observe)" || AFTER='null'
  report_rc=0
  python3 -B - "$REPORT_PATH" "$BEFORE" "$AFTER" "$GATE" "$CMD" "$rc" "$STARTED_AT" "$ENDED_AT" "${HERDR_PANE_ID:-pid:$PPID}" <<'PY' || report_rc=$?
import hashlib,json,os,sys,tempfile
from pathlib import Path
path,before,after,gate,cmd,rc,start,end,executor=sys.argv[1:]; path=Path(path)
r=dict(schema='qwb-candidate-receipt-v1',before=json.loads(before),after=json.loads(after),gate=gate,command_sha256=hashlib.sha256(cmd.encode()).hexdigest(),rc=int(rc),started_at=int(start),ended_at=int(end),elapsed_seconds=int(end)-int(start),executor=executor)
fd,tmp=tempfile.mkstemp(prefix='.qwb-receipt-',dir=path.parent)
try:
    with os.fdopen(fd,'w') as f: json.dump(r,f,ensure_ascii=False,sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
    os.link(tmp,path)
finally: os.unlink(tmp)
PY
  if [[ "$report_rc" -eq 0 ]]; then
    bash "$BINDIR/qwb-ledger.sh" gate-receipt --project "$LEDGER_PROJECT" --task "$TASK" -- "$OP" "$REPORT_PATH" >/dev/null || report_rc=$?
  fi
  if [[ "$report_rc" -ne 0 ]]; then
    echo '错误：收据发布/对象核验失败；不得采信本次成功文本' >&2
    [[ "$rc" -ne 0 ]] || rc=3
  fi
  [[ "$rc" -eq 0 ]] || echo "门失败（${GATE}）：退出码=${rc}" >&2
  exit "$rc"
fi

if [[ "$REPORT_SET" -eq 1 ]]; then
  REPORT_PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
  [[ "$REPORT" != */ ]] || { echo "错误：报告目标不能是目录路径" >&2; exit 2; }
  REPORT_INPUT="$REPORT"
  [[ "$REPORT_INPUT" != -* ]] || REPORT_INPUT="./$REPORT_INPUT"
  REPORT_DIR="$(dirname "$REPORT_INPUT")"
  REPORT_NAME="$(basename "$REPORT_INPUT")"
  [[ -d "$REPORT_DIR" ]] || { echo "错误：报告父目录不存在：${REPORT_DIR}" >&2; exit 2; }
  REPORT_DIR="$(cd "$REPORT_DIR" && pwd -P)"
  REPORT_PATH="$REPORT_DIR/$REPORT_NAME"
  [[ ! -e "$REPORT_PATH" && ! -L "$REPORT_PATH" ]] || { echo "错误：报告目标已存在：${REPORT_PATH}" >&2; exit 2; }
  git_snapshot() {
    local head status
    head="$(git -C "$PROJECT_ROOT" rev-parse --verify HEAD 2>/dev/null)" || head=unknown
    status="$(git -C "$PROJECT_ROOT" status --porcelain --untracked-files=normal 2>/dev/null)" || {
      printf '%s\tunknown\n' "$head"; return;
    }
    if [[ -z "$status" ]]; then status=clean; else status=dirty; fi
    printf '%s\t%s\n' "$head" "$status"
  }
  BEFORE="$(git_snapshot)"
  CMD_SHA="$(printf '%s' "$CMD" | shasum -a 256 | cut -d' ' -f1)" \
    || { echo "错误：无法记录本次质量门命令摘要" >&2; exit 2; }
  CONF_SHA_BEFORE="$(shasum -a 256 "$CONF" | cut -d' ' -f1)" \
    || { echo "错误：无法记录配置运行前摘要" >&2; exit 2; }
  # 先采样，再创建本次的任何临时文件，避免把自己的探针记作 dirty。
  REPORT_PROBE="$(mktemp "$REPORT_DIR/.qwb-test-preflight.XXXXXXXX" 2>/dev/null)" || {
    echo "错误：报告父目录不可写：${REPORT_DIR}" >&2; exit 2;
  }
  rm -f "$REPORT_PROBE" || { echo "错误：报告路径预检清理失败" >&2; exit 2; }
  [[ ! -e "$REPORT_PATH" && ! -L "$REPORT_PATH" ]] || { echo "错误：报告目标已存在：${REPORT_PATH}" >&2; exit 2; }
  STARTED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')" || { echo "错误：无法记录报告开始时间" >&2; exit 2; }
fi

cd "$PROJECT_ROOT"
rc=0
bash -c "$CMD" || rc=$?
if [[ "$rc" -ne 0 ]]; then
  echo "门失败（${GATE}）：${CMD} 退出码=${rc}" >&2
fi
if [[ "$REPORT_SET" -eq 1 ]]; then
  metadata_ok=1
  ENDED_AT="$(date '+%Y-%m-%dT%H:%M:%S%z')" || metadata_ok=0
  AFTER="$(git_snapshot)" || metadata_ok=0
  CONF_SHA_AFTER="$(shasum -a 256 "$CONF" | cut -d' ' -f1)" || metadata_ok=0
  IFS=$'\t' read -r HEAD_BEFORE STATUS_BEFORE <<< "$BEFORE"
  IFS=$'\t' read -r HEAD_AFTER STATUS_AFTER <<< "$AFTER"
  REPORT_TMP="$(mktemp "$REPORT_DIR/.qwb-test-report.XXXXXXXX" 2>/dev/null)" || REPORT_TMP=""
  report_ok="$metadata_ok"
  if [[ -n "$REPORT_TMP" ]]; then
    trap '[[ -z "${REPORT_TMP:-}" ]] || rm -f "$REPORT_TMP"' EXIT
    {
      printf '# qwb-test-report-v1\n\n' &&
      printf -- '- 检查：%s\n- 项目目录：%s\n- 配置来源：%s + %s\n' "$GATE" "$REPORT_PROJECT_ROOT" "$CONF" "$VAR" &&
      printf -- '- 命令 SHA-256：%s\n- 配置运行前 SHA-256：%s\n- 配置运行后 SHA-256：%s\n' \
        "$CMD_SHA" "$CONF_SHA_BEFORE" "$CONF_SHA_AFTER" &&
      printf -- '- 开始时间：%s\n- 结束时间：%s\n' "$STARTED_AT" "$ENDED_AT" &&
      printf -- '- 运行前提交：%s\n- 运行前工作区：%s\n' "$HEAD_BEFORE" "$STATUS_BEFORE" &&
      printf -- '- 运行后提交：%s\n- 运行后工作区：%s\n' "$HEAD_AFTER" "$STATUS_AFTER" &&
      printf -- '- 门退出码：%s\n- 证明范围：仅证明这次配置命令的执行记录，不自动等于产品验收或部署成功。\n' "$rc"
    } > "$REPORT_TMP" || report_ok=0
    if [[ "$report_ok" -eq 1 ]]; then
      perl -e 'link($ARGV[0], $ARGV[1]) or exit 1' "$REPORT_TMP" "$REPORT_PATH" || report_ok=0
    fi
  else
    report_ok=0
  fi
  if [[ "$report_ok" -eq 1 ]]; then
    echo "报告已写入：${REPORT_PATH}" >&2
  else
    echo "错误：报告写入失败：${REPORT_PATH}" >&2
    [[ "$rc" -ne 0 ]] || rc=3
  fi
fi
exit "$rc"
