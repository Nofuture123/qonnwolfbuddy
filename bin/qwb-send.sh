#!/usr/bin/env bash
# 薄协议入口；正文/收据只由同票ledger writer保存，不创建第二本任务进度。
set -euo pipefail
usage() {
  cat <<'EOF'
用法: qwb-send.sh <send|diagnosis|pending|received|accept|activity|prepared|handled|reconcile|transport> --project <根> --task <票> [选项]
仅合法controller通道；未开票请求须先开票，未知角色不回退主控。
send: --corr <关联> --attempt <来源尝试> --text <单行正文> [--to controller]；corr不得以source:开头（自动来源保留）
diagnosis: --report <本地JSON>；仅按需CI角色，来源须主控ci-assign，提案不执行、不作成功收据。
pending: [--due] [--retry-ms <1..86400000>]，完整event集合，不使用吞中间事件的最后seq游标。
received: --event <id>；accept/prepared: --event <id> --op <op_id>
activity: --event <id> [--wait-ms <0..86400000> --reason <条件>]
handled: --event <id> --op <op_id> --result-ref <项目内JSON读回证据>
reconcile: --event <id> --proof <接班对账JSON> --expect <版本>；旧owner确死才接同一op。
transport: --event <id> [--mode escalation|reminder --route-role <角色> --route-pane <pane> --retry-ms <1..86400000>]；仅代码监督使用，不等于received/handled。
三次仍未接收：角色交接升级主控一次；主控按max(30分钟,retry-ms)低频提醒，计数封顶3，不派生新交接。
宿主API交付不确认；模型读正文后received，接手accept，动作前prepared，读回后handled。
EOF
}
CMD="${1:-}"; [[ "$CMD" != --help && "$CMD" != -h ]] || { usage; exit 0; }; shift || true
ROOT="$(pwd)"; TASK=""; TO=controller; CORR=""; ATTEMPT=""; TEXT=""; EVENT=""; OP=""; RESULT=""; PROOF=""; EXPECT=""; RETRY=120000; MODE=all; WAIT=0; REASON=""; REPORT=""; TRANSPORT_MODE=""; ROUTE_ROLE=""; ROUTE_PANE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) ROOT="${2:?}"; shift 2 ;;
    --task) TASK="${2:?}"; shift 2 ;;
    --to) TO="${2:?}"; shift 2 ;;
    --corr) CORR="${2:?}"; shift 2 ;;
    --attempt) ATTEMPT="${2:?}"; shift 2 ;;
    --text) TEXT="${2:?}"; shift 2 ;;
    --event) EVENT="${2:?}"; shift 2 ;;
    --op) OP="${2:?}"; shift 2 ;;
    --result-ref) RESULT="${2:?}"; shift 2 ;;
    --report) REPORT="${2:?}"; shift 2 ;;
    --proof) PROOF="${2:?}"; shift 2 ;;
    --expect) EXPECT="${2:?}"; shift 2 ;;
    --retry-ms) RETRY="${2:?}"; shift 2 ;;
    --mode) TRANSPORT_MODE="${2:?}"; shift 2 ;;
    --route-role) ROUTE_ROLE="${2:?}"; shift 2 ;;
    --route-pane) ROUTE_PANE="${2:?}"; shift 2 ;;
    --due) MODE=due; shift ;;
    --wait-ms) WAIT="${2:?}"; shift 2 ;;
    --reason) REASON="${2:?}"; shift 2 ;;
    *) echo "错误：未知交接参数 $1" >&2; exit 2 ;;
  esac
done
[[ -n "$TASK" && "$TO" == controller ]] || { echo '错误：需同项目票且收件人为controller' >&2; exit 2; }
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ARGS=()
case "$CMD" in
  diagnosis) exec bash "$BINDIR/qwb-ledger.sh" ci-report --project "$ROOT" --task "$TASK" --expect "$EXPECT" -- "$REPORT" ;;
  send) ARGS=("$TO" "$CORR" "$ATTEMPT" "$TEXT") ;;
  pending|transport)
    OWNER="$(awk 'NR==1 {print $NF}' "$ROOT/qwbuddy/.controller.lock/owner")"
    if [[ "$CMD" == pending ]]; then ARGS=("$OWNER" "$RETRY" "$MODE"); else
      ARGS=("$OWNER" "$EVENT")
      if [[ -n "$TRANSPORT_MODE$ROUTE_ROLE$ROUTE_PANE" ]]; then ARGS+=("$TRANSPORT_MODE" "$ROUTE_ROLE" "$ROUTE_PANE" "$RETRY"); fi
    fi ;;
  received) ARGS=("$EVENT") ;;
  accept|prepared) ARGS=("$EVENT" "$OP") ;;
  activity) ARGS=("$EVENT" "$WAIT" "$REASON") ;;
  handled) ARGS=("$EVENT" "$OP" "$RESULT") ;;
  reconcile) ARGS=("$EVENT" "$PROOF") ;;
  *) usage >&2; exit 2 ;;
esac
exec bash "$BINDIR/qwb-ledger.sh" "handoff-$CMD" --project "$ROOT" --task "$TASK" --expect "$EXPECT" -- "${ARGS[@]}"
