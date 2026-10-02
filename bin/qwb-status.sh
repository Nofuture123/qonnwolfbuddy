#!/usr/bin/env bash
# qwb-status.sh —— 点名 + 汇报：读账本列出全部任务与状态，合并 herdr 窗口/状态输出
set -euo pipefail
export LC_ALL=C  # 账本可能含损坏 UTF-8；状态前缀按字节解析，不能让整票消失。

usage() {
  cat <<'EOF'
用法: qwb-status.sh [选项]

读 tasks/ 账本，逐份任务书打印 state 与最近一条状态行；有未决规格疑点
（最后一个 spec-defect:/spec-resolved: 相关事件是 blocked: spec-defect:，与
qwb-run.sh 疑点门同判定）的额外标注一行「规格疑点未处理」——后续普通状态行
遮不住它。若本机有 herdr，附带 agent / pane 窗口状态。账本为空也正常退出（退出码 0）。

选项:
  --project <根>    项目根（默认：当前目录）
  --metrics         仅输出逐票真实事件/原始时间JSON，旧缺项unknown
  -h, --help        显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"; METRICS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --metrics) METRICS=1; shift ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
# 共享库（worker_lost 工人丢失判定；与 qwb-run.sh / qwb-wake.sh 同一份）
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整，请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

if [[ "$METRICS" -eq 1 ]]; then
  shopt -s nullglob
  for f in "$LEDGER"/*.md; do
    grep -q '^state:' "$f" || continue
    printf '%s\t' "$(basename "$f")"
    qwb_ledger "$PROJECT_ROOT" "$f" metrics || exit 1
  done
  exit 0
fi

echo "== 账本：$LEDGER =="
shopt -s nullglob
files=("$LEDGER"/*.md)
if [[ ${#files[@]} -eq 0 ]]; then
  echo "（无任务书）"
else
  for f in "${files[@]}"; do
    grep -q '^state:' "$f" || continue   # 无 state 字段行 → 非任务书（如 lessons.md），跳过
    name="$(basename "$f")"
    st="$(qwb_task_state "$f")"
    bytes_ok=1
    qwb_ledger_utf8_ok "$f" || bytes_ok=0
    if [[ "$bytes_ok" -eq 0 ]]; then
      mark="未结"
    else
      case "$st" in
        running|blocked|needs-decision) mark="未结" ;;
        done|verified) mark="已结" ;;
        *) mark="未结" ;;
      esac
    fi
    [[ -z "$(qwb_task_obligations "$PROJECT_ROOT" "$f")" ]] || mark="未结"
    last="$(grep -E '^(working|done|blocked|needs-decision|wake|dispatch):' "$f" 2>/dev/null | tail -1 || true)"
    if [[ "$bytes_ok" -eq 0 ]]; then
      printf '[未结] %-40s state=%s —— 账本 UTF-8 损坏，须主控查看\n' "$name" "$st"
    elif [[ "$st" != running && "$st" != blocked && "$st" != needs-decision && "$st" != "done" && "$st" != verified ]]; then
      printf '[未结] %-40s state=%s —— 状态异常，须主控查看\n' "$name" "$st"
    else
      printf '[%s] %-40s state=%s\n' "$mark" "$name" "$st"
    fi
    [[ -n "$last" ]] && printf '       最近: %s\n' "$last"
    if grep -q '^<!-- qwb-collab-v1$' "$f"; then
      if collab="$(qwb_ledger "$PROJECT_ROOT" "$f" read)"; then
        printf '%s' "$collab" | perl -MJSON::PP -0777 -e '
          my $d=decode_json(<STDIN>);
          print "       claim未释放: $d->{claim}{op_id}\n" if $d->{claim};
          if (my $p=$d->{planning}) {
            print "       规划: request=$p->{request_id} package=$p->{package_id} spec_rev=$d->{spec_rev} source=$p->{source}{event}\n";
            print "       就绪: ".($p->{ready}{status} // "未扫描")." 修订=".($p->{pending_revision} ? "待显式handoff/CAS" : "无")."\n";
            for my $stage (qw(start accept land)) {
              print "       依赖[$stage]: $_->{task}/$_->{artifact}@$_->{version} spec_rev=$_->{spec_rev} condition=$_->{condition}\n" for @{$p->{needs}{$stage}};
            }
          }
          if (my $g=$d->{gate}) {
            print "       门禁: verdict=$g->{verdict} attempt=$g->{binding}{attempt} candidate=$g->{binding}{head} 待land/cleanup（不自动verified）\n";
            my $elapsed=0; $elapsed+=$_->{receipt}{elapsed_seconds} for @{$g->{receipts}};
            print "       核证据: receipts=".scalar(@{$g->{receipts}})." reviews=".scalar(@{$g->{reviews}})." validation_seconds=$elapsed tokens=unknown\n";
          }
          for my $k (sort keys %{$d->{questions}}) {
            my $q=$d->{questions}{$k};
            print "       问题未结: key=$k ".($q->{answer} eq "" ? "未答" : "待恢复")."\n" if $q->{resumed} eq "";
          }
          my $h=$d->{handoffs} // {};
          for my $id (sort keys %$h) {
            next if $h->{$id}{handled};
            my $r=$h->{$id};
            print "       交接待办: event_id=$id received=".($r->{received} ne "" ? "yes" : "no")." accepted=".($r->{accepted} ne "" ? "yes" : "no")." transport=$r->{transport_count}/3".($r->{prepared} ? " 先对账" : "").($r->{transport_count}>=3 ? " 重投预算耗尽，须显式核查" : "")."\n";
          }
        '
      else
        printf '       [未结] 协作区损坏/未知，须主控对账\n'
      fi
    fi
    # 工人丢失判定（关机/herdr 重启后 pane 没了、票还 running）：丢主控开局点名能直接看出
    # 工人已不存在，重派同一票会幂等复用 worktree。无 herdr 或查询失败不当丢失（不猜）。
    if [[ "$st" == "running" ]] && command -v herdr >/dev/null 2>&1; then
      lostpane="$(worker_lost "$f")" && lrc=0 || lrc=$?
      if [[ "$lrc" -eq 0 ]]; then
        printf '       工人丢失: pane %s 已不存在/无 agent——重派同一票会幂等复用 worktree\n' "$lostpane"
      elif [[ "$lrc" -eq 2 ]]; then
        printf '       工人状态未知（查询失败，不当丢失）\n'
      fi
    fi
    # 规格疑点未处理：与 qwb-run.sh 疑点门同判定——最后一个相关事件（spec-defect:/spec-resolved:）
    # 是 spec-defect: 即未决；普通状态行不参与判定，疑点不会被后续 working:/done:/dispatch: 行遮住
    spev="$(qwb_last_spec_event "$f" 2>/dev/null)"
    if printf '%s' "$spev" | grep -qE '^blocked:[[:space:]]*spec-defect:'; then
      printf '       规格疑点未处理: %s\n' "$spev"
    fi
  done
fi

echo
echo "== 值守 =="
# 值守健康复用 qwb-wake.sh --check 的同一判定：真查 herdr 前台进程，pane 存在不算健康，查不到明说未知
WAKE_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-wake.sh"
if [[ -f "$WAKE_BIN" ]]; then
  bash "$WAKE_BIN" --project "$PROJECT_ROOT" --check
else
  echo "值守：未知（缺 qwb-wake.sh，无法判定）"
fi

echo
echo "== 常驻角色（当前活动/记录冲突）=="
ROLE_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-role.sh"
if [[ -d "$PROJECT_ROOT/qwbuddy/.roles" && -f "$ROLE_BIN" ]]; then
  bash "$ROLE_BIN" status --project "$PROJECT_ROOT" || echo "角色：unknown（记录/原生查询失败，不能认闲）"
else
  echo "（未登记角色）"
fi
echo
echo "== Herdr 窗口 =="
if command -v herdr >/dev/null 2>&1; then
  herdr agent list 2>/dev/null || echo "（herdr agent list 失败：无运行中的 server 或无 agent）"
else
  echo "（herdr 不在 PATH，仅列账本）"
fi
exit 0
