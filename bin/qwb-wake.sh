#!/usr/bin/env bash
# qwb-wake.sh —— 值守：以账本未结项为准，叫醒主控窗口；同一项进展未变不重复叫
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-wake.sh [选项]

循环：读账本列未结项 → 有未结项且进展指纹已变 → **只发一条** herdr pane run（多票拼进同一条文本）叫醒主控 → 等事件或超时 → 再来。
未结项 = 任务书头部 state ∈ {running, blocked, needs-decision}。
去重：fp = sha1(state 值 + "\n" + 最后一条 working:/done:/blocked:/needs-decision: 行原文，无则空串；
     running 票判定为工人丢失时再追加 "\nlost=<pane>" 段——工人一消失指纹变一次、叫一次，之后指纹不变不重叫）；
     叫醒后写 wake: <时间戳> state=<值> fp=<sha1>。fp 未变不再叫；无 fp= 的旧 wake 行视为指纹不同。
     投递成功才逐票写 wake 行，失败一行都不写（下轮重试）。
兜底重叫：仅对 state=running 生效——fp 未变但最近一条 wake: 行的时间戳距今 ≥ config.sh 的
     QWB_REWAKE_MS（>0 才启用）→ 仍再叫一次（兜底目的是「工人挂起/崩溃没写行」，只在 running 成立；
     blocked/needs-decision 等的是主控裁决或使用者，指纹未变即跳过不重叫）；时间戳解析失败按超期处理。
投递失败：不写 wake 行、报 stderr、继续处理下一项；值守主循环不因单次投递失败退出。
等待：只取未结项任务书里时间戳最新的 dispatch: pane 做 agent wait；一轮预算 = 1×interval
     （毫秒级计时 + 小数秒 sleep），无论 wait 成功/失败/超时，已耗时间都计入预算、
     剩余部分补 sleep；无可用 pane 才整睡一个间隔，不得忙循环。

选项:
  --project <根>      项目根（默认：当前目录）
  --pane <pane_id>    主控 pane（默认：$QWB_CONTROLLER_PANE 或 config.sh QWB_CONTROLLER_PANE）
  --interval <毫秒>   事件等待的超时（默认：config.sh QWB_WAKE_INTERVAL_MS，否则 120000）
  --once              只检查一轮就退出
  --dry-run           只报告未结项，不叫、不写 wake 行
  --ensure            幂等确保值守在跑：建/复用一个可见 shell tab；新建时 tab 落在项目自己的
                      workspace（config.sh 的 QWB_WORKSPACE 优先，查不到即拒绝；未声明则按
                      worktree.repo_root 匹配项目根；都没有才落调用者 workspace 并警告）；
                      判定依据是 pane 前台进程组里真实的 qwb-wake.sh 进程 + 项目路径，
                      不凭 pane 存在或名字相似；查不到/多实例明确报错，不擅自多开
  --block             前台阻塞值守（无窗口：不 pane run、不开 tab，供 Claude Code Stop hook /
                      Codex 前台 checkpoint 等主控 harness 自己调用）：每轮判定前先复核主控锁
                      （qwbuddy/.controller.lock/owner 末字段 ≠ 本进程 HERDR_PANE_ID 或锁不存在
                      → exit 0 不消费唤醒；HERDR_PANE_ID 为空则跳过复核），之后轮询账本，
                      有可动作变化 → stdout 打印摘要 + 往对应票追加 wake: 行 + 退出码 2；
                      账本无未结项 → 退出码 0；--max-ms 到期无变化 → 退出码 124；其他非 0 = 错误。
                      去重与时间兑底逻辑与循环模式完全共用（wake: 行状态记在同一本账本上，
                      两种值守形态不会互相重复叫）
  --max-ms <毫秒>     --block 的单轮阻塞上限（毫秒，超时一律毫秒）；不给则无限阻塞直到 exit 2 或 0
  --check             只报告本项目值守健康并退出：运行 / 未运行 / 未知（不写账本不改状态）
  -h, --help          显示本帮助
EOF
}

PROJECT_ROOT="$(pwd)"; PANE="${QWB_CONTROLLER_PANE:-}"; INTERVAL=""; ONCE=0; DRY=0; ENSURE=0; CHECK=0; BLOCK=0; MAX_MS=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --project) PROJECT_ROOT="$2"; shift 2 ;;
    --pane) PANE="$2"; shift 2 ;;
    --interval) INTERVAL="$2"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    --ensure) ENSURE=1; shift ;;
    --check) CHECK=1; shift ;;
    --block) BLOCK=1; shift ;;
    --max-ms) MAX_MS="$2"; shift 2 ;;
    *) echo "错误：未知参数 $1" >&2; usage >&2; exit 2 ;;
  esac
done
if [[ "$ENSURE" -eq 1 || "$CHECK" -eq 1 ]]; then
  [[ "$ENSURE" -eq 1 && "$CHECK" -eq 1 ]] && { echo "错误：--ensure 与 --check 互斥" >&2; exit 2; }
  [[ "$ONCE" -eq 0 && "$DRY" -eq 0 ]] || { echo "错误：--ensure/--check 与 --once/--dry-run 互斥" >&2; exit 2; }
fi
if [[ "$BLOCK" -eq 1 ]]; then
  (( ENSURE + CHECK + ONCE + DRY == 0 )) || { echo "错误：--block 与 --ensure/--check/--once/--dry-run 互斥" >&2; exit 2; }
else
  [[ -z "$MAX_MS" ]] || { echo "错误：--max-ms 只随 --block 使用" >&2; exit 2; }
fi
if [[ -n "$MAX_MS" ]]; then
  [[ "$MAX_MS" =~ ^[1-9][0-9]*$ ]] || { echo "错误：--max-ms 须为正整数毫秒（当前：${MAX_MS}）" >&2; exit 2; }
fi

[[ -d "$PROJECT_ROOT" ]] || { echo "错误：项目根不存在：${PROJECT_ROOT}" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"
LEDGER="$PROJECT_ROOT/tasks"
CONF="$PROJECT_ROOT/qwbuddy/config.sh"
# 共享库（resolve_workspace 等；与 qwb-run.sh 同一份，两处不各写一份）
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/qwb-lib.sh"
[[ -f "$LIB" ]] || { echo "错误：找不到共享库 ${LIB}——安装副本不完整（旧版安装缺此文件），请用母本仓重跑 bin/qwb-init.sh 更新（幂等）" >&2; exit 1; }
# shellcheck source=/dev/null
. "$LIB"

if [[ "$DRY" -eq 0 && "$CHECK" -eq 0 && "$BLOCK" -eq 0 ]]; then
  command -v herdr >/dev/null 2>&1 || { echo "错误：找不到 herdr 命令，无法叫醒主控" >&2; exit 1; }
fi
# 配置唯一来源是 bash 文件：直接 source（PANE 已被 --pane/环境变量占上则不覆盖）
# shellcheck source=/dev/null
if [[ -f "$CONF" ]]; then . "$CONF"; fi
INTERVAL="${INTERVAL:-${QWB_WAKE_INTERVAL_MS:-120000}}"
PANE="${PANE:-${QWB_CONTROLLER_PANE:-}}"
[[ "$INTERVAL" =~ ^[1-9][0-9]*$ ]] \
  || { echo "错误：interval 须为正整数毫秒（当前：${INTERVAL}）" >&2; exit 2; }

# —— 值守身份 / 健康（--ensure / --check 共用；status 经 --check 复用同一判定）——
# 健康判定只看 pane 前台进程组里真实的 qwb-wake.sh 进程且项目路径匹配，不凭 pane 存在或名字相似。
WATCHF="$PROJECT_ROOT/qwbuddy/.watch"

# pane get → stdout "cwd<TAB>agent<TAB>workspace"；rc：0 ok / 3 pane 不存在 / 2 其他查询失败
pane_info() {
  local out
  if ! out="$(herdr pane get "$1" 2>&1)"; then
    printf '%s' "$out" | grep -q 'pane_not_found' && return 3 || return 2
  fi
  printf '%s' "$out" | perl -MJSON::PP=decode_json -e '
    my $j = eval { decode_json(join "", <STDIN>) } or exit 2;
    my $p = $j->{result}{pane} or exit 2;
    printf "%s\t%s\t%s",
      ($p->{foreground_cwd} // $p->{cwd} // ""), ($p->{agent} // ""), ($p->{workspace_id} // "");
  '
}

# pane process-info 一次判定 → stdout：wake:<pid>@<值守目标pane> | idle | busy | gone | err
# 值守进程认定：前台进程组里 argv0 是 shell/脚本本体 且 cmdline 含 qwb-wake.sh 且项目路径匹配；
# --ensure/--check/--once/--dry-run 这类短调用不算持续值守实例。
pane_probe() {
  local out
  if ! out="$(herdr pane process-info --pane "$1" 2>&1)"; then
    printf '%s' "$out" | grep -q 'pane_not_found' && echo gone || echo err
    return 0
  fi
  printf '%s' "$out" | perl -MJSON::PP=decode_json -MCwd=realpath -e '
    my $root = $ARGV[0];
    my $j = eval { decode_json(join "", <STDIN>) };
    my $pi = ($j && $j->{result}{process_info}) or do { print "err"; exit 0 };
    my $rr = -d $root ? realpath($root) : $root;
    for my $p (@{ $pi->{foreground_processes} // [] }) {
      next unless ($p->{cmdline} // "") =~ /qwb-wake\.sh(\s|$)/;
      next unless ($p->{argv0} // "") =~ m{(^|/)(ba)?sh$|(^|/)zsh$|qwb-wake\.sh$};
      next if ($p->{cmdline} // "") =~ /--(ensure|check|once|dry-run)(\s|$)/;
      my $argv = $p->{argv} // [];
      my ($proj, $tgt);
      for (my $i = 0; $i < @$argv; $i++) {
        if ($argv->[$i] eq "--project" && $i + 1 < @$argv) { $proj = $argv->[$i + 1]; next }
        if ($argv->[$i] eq "--pane"    && $i + 1 < @$argv) { $tgt  = $argv->[$i + 1]; next }
      }
      my $cand = defined $proj ? $proj : ($p->{cwd} // "");
      next if $cand eq "";
      my $rc = -d $cand ? realpath($cand) : undef;
      if (defined $rc && defined $rr && $rc eq $rr) {
        print "wake:", ($p->{pid} // ""), "@", ($tgt // ""); exit 0
      }
    }
    my $idle = defined $pi->{foreground_process_group_id} && defined $pi->{shell_pid}
               && $pi->{foreground_process_group_id} == $pi->{shell_pid};
    print($idle ? "idle" : "busy");
  ' "$PROJECT_ROOT"
}

# 活值守的目标核验：$1=pane $2=pane_probe 的 wake:* 判定；值守目标 ≠ 本次要求 → 打印修复步骤并 return 1
ensure_target_ok() {
  local wpid wtgt
  wpid="${2#wake:}"; wtgt="${wpid#*@}"; wpid="${wpid%@*}"
  if [[ "$wtgt" != "$PANE" ]]; then
    {
      echo "错误：本项目值守已在 pane $1 运行，但它叫醒的主控目标是 '${wtgt:-未指定}'，本次要求 '${PANE}'——不能静默复用错误目标。"
      echo "修复：到 pane $1 停掉值守（Ctrl-C）后重跑 --ensure；或确认它就是要用的值守，改用 --pane ${wtgt:-<其目标>} 再跑。"
    } >&2
    return 1
  fi
  return 0
}

# 候选 pane = pane list 里没有 agent 字段的（值守是纯 shell tab）：stdout 空格分隔 id；rc2=查询失败
# $1=workspace：非空时只列该 workspace 的 pane——ensure 只在调用者 workspace 内行动
watch_candidates() {
  local out
  out="$(herdr pane list 2>/dev/null)" || return 2
  printf '%s' "$out" | perl -MJSON::PP=decode_json -e '
    my $ws = $ARGV[0];
    my $j = eval { decode_json(join "", <STDIN>) } or exit 2;
    print(($_->{pane_id} // ""), " ") for grep {
      !defined $_->{agent} && ($ws eq "" || (($_->{workspace_id} // "") eq $ws))
    } @{ $j->{result}{panes} // [] };
  ' "$1"
}

# 扫本项目值守进程：WATCH_FOUND=活着的 pane 列表；WATCH_QERR=查询失败 pane 数；rc2=list 失败
# $1 同 watch_candidates 的 workspace 过滤参数
watch_scan() {
  WATCH_FOUND=""; WATCH_QERR=0
  local ids p v
  ids="$(watch_candidates "$1")" || return 2
  for p in $ids; do
    v="$(pane_probe "$p")"
    case "$v" in
      wake:*) WATCH_FOUND="${WATCH_FOUND:+$WATCH_FOUND }$p" ;;
      err)    WATCH_QERR=$((WATCH_QERR + 1)) ;;
    esac
  done
  return 0
}

watch_field() { grep -oE "(^|[[:space:]])$1=[^[:space:]]+" "$WATCHF" 2>/dev/null | head -1 | cut -d= -f2 || true; }
watch_write() { # $1=pane $2=workspace $3=pid（可空）
  printf 'pane=%s workspace=%s pid=%s started=%s cmd=%s\n' \
    "$1" "$2" "$3" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$WATCH_CMD" > "$WATCHF"
}

watch_check() {
  command -v herdr >/dev/null 2>&1 || { echo "值守：未知（herdr 不在 PATH，无法查询）"; return 0; }
  # 形态一：hook（值守隐形化）—— .hook.lock 里的 pid 存活即视为 Claude Code Stop hook 的 --block 在跑；
  # 检测在 tab 形态之前：同一项目两种形态同时存在时报 hook（前台阻塞形态优先，tab 是 fallback）
  local hpid=""
  hpid="$(cat "$PROJECT_ROOT/qwbuddy/.hook.lock/pid" 2>/dev/null || true)"
  if [[ -n "$hpid" ]] && kill -0 "$hpid" 2>/dev/null; then
    echo "值守：hook（pid ${hpid}）"
    return 0
  fi
  # 形态二：pi 扩展（值守隐形化）——.watch 记 kind=pi-ext pid=<子进程 pid>，pid 活即值守在跑；
  # pid 死 = pi 已退出或扩展收工 → 未运行。判活用 kill -0 不需要 herdr，故放在 tab 扫描之前；
  # 同项目 Claude hook 与 pi 扩展互斥（一个主控只用一种 harness），hook 在前优先。
  if [[ -f "$WATCHF" ]] && [[ "$(watch_field kind)" == "pi-ext" ]]; then
    local wpid=""
    wpid="$(watch_field pid)"
    if [[ -n "$wpid" ]] && [[ "$wpid" != 0 ]] && kill -0 "$wpid" 2>/dev/null; then
      echo "值守：pi-ext（pid ${wpid}）"
    else
      echo "值守：未运行（pi-ext 子进程已退出）"
    fi
    return 0
  fi
  local rp="" dead="" qfail=0 v="" target_ws=""
  target_ws="$(resolve_workspace "$PROJECT_ROOT" 2>/dev/null)" || {
    echo "值守：未知（目标 workspace 查询失败）"; return 0;
  }
  [[ -n "$target_ws" ]] || target_ws="${HERDR_WORKSPACE_ID:-}"
  [[ -f "$WATCHF" ]] && rp="$(watch_field pane)"
  if [[ -n "$rp" && -n "$target_ws" && "$(watch_field workspace)" != "$target_ws" ]]; then
    echo "值守：未知（登记 workspace 与当前项目目标不符）"; return 0
  fi
  if ! watch_scan "$target_ws"; then
    echo "值守：未知（herdr pane list 查询失败，无法确认值守是否在跑）"; return 0
  fi
  if [[ -n "$rp" && " ${WATCH_FOUND} " != *" ${rp} "* ]]; then
    v="$(pane_probe "$rp")"
    case "$v" in
      wake:*) WATCH_FOUND="${WATCH_FOUND:+$WATCH_FOUND }$rp" ;;
      gone)   dead="登记 pane ${rp} 已不存在" ;;
      idle)   dead="登记 pane ${rp} 的值守进程已退出（shell 仍空闲在）" ;;
      busy)   dead="登记 pane ${rp} 的值守进程已不在（前台被其他进程占用）" ;;
      err)    qfail=1 ;;
    esac
  fi
  if [[ -n "$WATCH_FOUND" ]]; then
    local n; n=$(wc -w <<<"$WATCH_FOUND" | tr -d ' ')
    if (( WATCH_QERR + qfail > 0 )); then
      # 混合不确定态：见了活实例但还有查不出的 pane——明确未知，不保证单实例
      echo "值守：未知（pane ${WATCH_FOUND} 在跑，但 $((WATCH_QERR + qfail)) 个候选 pane 查询失败，无法排除第二实例）"
    elif [[ "$n" -gt 1 ]]; then
      echo "值守：异常（发现 ${n} 个实例：${WATCH_FOUND}——请手工关停多余的）"
    else
      local extra=""
      [[ "$WATCH_FOUND" != "$rp" || -z "$rp" ]] && extra="（未登记，系手工/外部启动）"
      echo "值守：tab（pane ${WATCH_FOUND}）${extra}"
    fi
    return 0
  fi
  [[ -n "$dead" ]] && { echo "值守：未运行（${dead}）"; return 0; }
  if [[ "$qfail" -gt 0 || "$WATCH_QERR" -gt 0 ]]; then
    echo "值守：未知（部分 pane 进程查询失败，无法确认）"; return 0
  fi
  if [[ -n "$rp" ]]; then echo "值守：未运行（登记 pane ${rp} 无值守进程）"
  else echo "值守：未运行（无登记，扫描也未发现本项目值守进程）"; fi
  return 0
}

SELF_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
# printf %q 逐参数转义：项目路径含空格/单引号时启动命令仍然合法
printf -v WATCH_CMD 'bash %q --project %q --pane %q --interval %q' \
  "$SELF_BIN" "$PROJECT_ROOT" "$PANE" "$INTERVAL"

watch_ensure() {
  [[ -d "$PROJECT_ROOT/qwbuddy" ]] \
    || { echo "错误：项目未安装 qwb（缺 ${PROJECT_ROOT}/qwbuddy），先跑 bin/qwb-init.sh" >&2; return 1; }
  [[ -n "$PANE" ]] \
    || { echo "错误：--ensure 需要主控 pane（--pane / QWB_CONTROLLER_PANE / config.sh）" >&2; return 2; }
  # 建 tab 目标 workspace：优先环境；仅有 HERDR_PANE_ID 时从 pane get 推导
  local ws="${HERDR_WORKSPACE_ID:-}" info=""
  if [[ -z "$ws" && -n "${HERDR_PANE_ID:-}" ]]; then
    info="$(pane_info "$HERDR_PANE_ID")" \
      || { echo "错误：无法确认调用者 workspace（herdr pane get ${HERDR_PANE_ID} 失败）" >&2; return 1; }
    ws="$(printf '%s' "$info" | cut -f3)"
  fi
  [[ -n "$ws" ]] \
    || { echo "错误：无 herdr 上下文（需 HERDR_WORKSPACE_ID 或 HERDR_PANE_ID），不能定位建 tab 的 workspace" >&2; return 1; }

  # 本次要叫醒的目标主控 pane 必须真实存在且同属该 workspace——在获锁与一切副作用前核对；
  # 不存在/查不到/无 workspace 归属/异 workspace 一律拒绝（fail-closed）
  local tinfo trc=0 tws
  tinfo="$(pane_info "$PANE")" || trc=$?
  if [[ "$trc" -ne 0 ]]; then
    if [[ "$trc" -eq 3 ]]; then
      echo "错误：目标主控 pane ${PANE} 不存在（pane_not_found）——ensure 不擅自假定或跨边界行动" >&2
    else
      echo "错误：目标主控 pane ${PANE} 查询失败，无法确认存在与归属——不擅自行动" >&2
    fi
    return 1
  fi
  tws="$(printf '%s' "$tinfo" | cut -f3)"
  [[ -n "$tws" ]] \
    || { echo "错误：目标主控 pane ${PANE} 无 workspace 归属可查——拒绝" >&2; return 1; }
  [[ "$tws" == "$ws" ]] \
    || { echo "错误：目标主控 pane ${PANE} 属于 workspace ${tws}（当前 ${ws}）——ensure 只在调用者 workspace 内行动" >&2; return 1; }

  # 创建、扫描、登记、复用统一使用项目目标 workspace；主控仍可在调用者 workspace。
  local tabws
  tabws="$(resolve_workspace "$PROJECT_ROOT")" || return 1
  [[ -n "$tabws" ]] || tabws="$ws"

  # 防并发 ensure 双开：独立 mkdir 原子锁（不能用主控锁——主控长期持有它，ensure 正是主控调用的）
  local WLOCK="$PROJECT_ROOT/qwbuddy/.watch.lock" rcr=0
  mkdir "$WLOCK" 2>/dev/null \
    || { echo "错误：另一个 ensure 正在执行或留下残留锁（${WLOCK}）；确认无并发后可 rm -rf 该目录重跑" >&2; return 1; }
  # 中断清锁：EXIT/INT/TERM 都只清自己拿到的这一把。
  # SIGKILL/断电捕获不到，残留锁属「需人工核实后恢复」的边界，不假称全覆盖。
  QWB_WATCH_LOCKDIR="$WLOCK"   # 须全局：EXIT trap 触发时本函数可能已不在栈上
  trap 'rm -rf "$QWB_WATCH_LOCKDIR"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  _ensure_body || rcr=$?
  rm -rf "$WLOCK"
  trap - EXIT INT TERM
  unset QWB_WATCH_LOCKDIR
  return "$rcr"
}

_ensure_body() {
  local rp="" scanrc=0 v="" np="" nv="" tries=0
  [[ -f "$WATCHF" ]] && rp="$(watch_field pane)"
  # 只扫描本项目选定的值守 workspace。
  watch_scan "$tabws" || scanrc=$?
  # 不确定态必须先于一切成功分支：list 挂或候选查不出 → 拒绝（fail-closed），不复用不新开
  if [[ "$scanrc" -ne 0 ]]; then
    echo "错误：herdr pane list 查询失败，无法排除已有值守——不擅自多开。修好 herdr 后重跑 --ensure" >&2
    return 1
  fi
  if [[ "$WATCH_QERR" -gt 0 ]]; then
    echo "错误：${WATCH_QERR} 个候选 pane 进程查询失败，无法排除已有值守——不擅自多开/复用。修好 herdr 后重跑 --ensure" >&2
    return 1
  fi
  if [[ -n "$WATCH_FOUND" ]]; then
    local n; n=$(wc -w <<<"$WATCH_FOUND" | tr -d ' ')
    if [[ "$n" -gt 1 ]]; then
      echo "错误：发现 ${n} 个本项目值守实例（${WATCH_FOUND}）。不擅自多开/清理，请手工关停多余实例后重跑 --ensure" >&2
      return 1
    fi
    # 换主控不能静默复用：复核值守命令的真实 --pane 目标，不符即拒并给修复步骤
    v="$(pane_probe "$WATCH_FOUND")"
    ensure_target_ok "$WATCH_FOUND" "$v" || return 1
    if [[ "$WATCH_FOUND" != "$rp" || ! -f "$WATCHF" ]]; then
      local iws; iws="$(pane_info "$WATCH_FOUND" 2>/dev/null | cut -f3 || true)"
      watch_write "$WATCH_FOUND" "${iws:-$ws}" "" \
        || { echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1; }
      echo "复用已在运行的值守（pane ${WATCH_FOUND}，此前未登记/登记不一致，已补记 .watch）"
    else
      echo "复用已在运行的值守（pane ${WATCH_FOUND}）"
    fi
    return 0
  fi
  # 无活值守：登记 pane 还在且 shell 空闲 → 原地重启；占用/消失 → 另开新 tab。
  # 登记 pane 属于别的 workspace → 不认领不重启，拒绝给修复步骤。
  if [[ -n "$rp" ]]; then
    [[ "$(watch_field workspace)" == "$tabws" ]] || {
      echo "错误：登记 pane ${rp} 的 workspace 与项目目标 ${tabws} 不符——拒绝认领" >&2; return 1;
    }
    local rinfo grc
    rinfo="$(pane_info "$rp")"; grc=$?
    if [[ "$grc" -eq 0 ]]; then
      local rws; rws="$(printf '%s' "$rinfo" | cut -f3)"
      [[ "$rws" == "$tabws" ]] || {
        echo "错误：登记 pane ${rp} 属于 workspace ${rws}（目标 ${tabws}）——不认领不重启。" >&2
        echo "修复：核实该 pane 后删掉 ${WATCHF} 登记重跑 --ensure；或到 workspace ${rws} 手工处理" >&2
        return 1; }
    elif [[ "$grc" -eq 2 ]]; then
      echo "错误：登记 pane ${rp} 查询失败，无法确认 workspace 归属——不擅自多开" >&2; return 1
    fi
    # grc=3（pane 不存在）→ 交给 pane_probe 走 gone 分支
    v="$(pane_probe "$rp")"
    case "$v" in
      wake:*)
        ensure_target_ok "$rp" "$v" || return 1
        echo "复用已在运行的值守（pane ${rp}）"; return 0 ;;
      err)
        echo "错误：登记 pane ${rp} 进程查询失败，无法确认值守状态——不擅自多开" >&2; return 1 ;;
      idle)
        herdr pane run "$rp" "$WATCH_CMD" >/dev/null \
          || { echo "错误：往 pane ${rp} 投递值守启动命令失败" >&2; return 1; }
        while (( tries < 6 )); do
          nv="$(pane_probe "$rp")"; [[ "$nv" == wake:* ]] && break
          sleep 0.5; tries=$((tries + 1))
        done
        [[ "$nv" == wake:* ]] || {
          echo "错误：已向 pane ${rp} 投递值守启动命令，但连续探测未确认进程出现——不算确保成功，未登记 .watch；请到该 pane 看实际报错后重跑" >&2
          return 1; }
        local wpid="${nv#wake:}"; wpid="${wpid%@*}"
        watch_write "$rp" "$(watch_field workspace)" "$wpid" \
          || { echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1; }
        echo "值守已在原 pane 重启（pane ${rp} pid ${wpid}）"
        return 0 ;;
      busy) echo "登记 pane ${rp} 已被其他进程占用，另开新 tab（不动旧 pane）" ;;
      gone) echo "登记 pane ${rp} 已不存在，另开新 tab" ;;
    esac
  fi
  # tabws 在任何副作用之前已经确定，与扫描/复用范围相同。
  local tout
  tout="$(herdr tab create --workspace "$tabws" --cwd "$PROJECT_ROOT" --label "qwb-值守" --no-focus 2>&1)" \
    || { echo "错误：herdr tab create 失败：${tout}" >&2; return 1; }
  np="$(printf '%s' "$tout" | perl -MJSON::PP=decode_json -e '
    my $j = eval { decode_json(join "", <STDIN>) } or exit 1;
    print($j->{result}{root_pane}{pane_id} // "");' || true)"
  [[ -n "$np" ]] || { echo "错误：tab create 响应缺 root_pane.pane_id" >&2; return 1; }
  herdr pane run "$np" "$WATCH_CMD" >/dev/null \
    || { echo "错误：新 tab ${np} 投递值守启动命令失败" >&2; return 1; }
  while (( tries < 6 )); do
    nv="$(pane_probe "$np")"; [[ "$nv" == wake:* ]] && break
    sleep 0.5; tries=$((tries + 1))
  done
  [[ "$nv" == wake:* ]] || {
    echo "错误：已建值守 tab ${np} 并投递启动命令，但连续探测未确认进程出现——不算确保成功，未登记 .watch；请到 pane ${np} 看实际报错后重跑" >&2
    return 1; }
  local wpid="${nv#wake:}"; wpid="${wpid%@*}"
  watch_write "$np" "$tabws" "$wpid" \
    || { echo "错误：值守身份登记写入失败（${WATCHF}）" >&2; return 1; }
  echo "已在 workspace ${tabws} 新建值守 tab 并启动（pane ${np} pid ${wpid}）"
  return 0
}

if [[ "$CHECK" -eq 1 ]]; then watch_check; exit 0; fi
if [[ "$ENSURE" -eq 1 ]]; then watch_ensure; exit 0; fi

# 未结项：输出「文件<TAB>state」。state 不在 5 值域 → stderr 警告（不算未结项，但必须说出来）。
# 无 state: 字段行的文件（如 tasks/lessons.md）不算任务书，跳过不警告。
open_items() {
  local f st
  for f in "$LEDGER"/*.md; do
    [[ -e "$f" ]] || continue
    grep -q '^state:' "$f" || continue
    st="$(sed -n 's/^state:[[:space:]]*//p' "$f" | head -1 | tr -d '[:space:]')"
    case "$st" in
      running|blocked|needs-decision) printf '%s\t%s\n' "$f" "$st" ;;
      done|verified) ;;
      *) echo "警告：$(basename "$f") state=${st} 非法（不在 5 值域内），不会被叫醒" >&2 ;;
    esac
  done
}

# 最近一次 wake 行里的 fp（无 wake 行或解析不到 fp= 则为空 → 视为指纹不同）
last_wake_fp() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/.*fp=\([^[:space:]]*\).*/\1/p' || true
}

# 最近一条 wake: 行的时间戳字段（无则空）
last_wake_ts() {
  grep '^wake:' "$1" 2>/dev/null | tail -1 | sed -n 's/^wake:[[:space:]]*\([^[:space:]]*\).*/\1/p' || true
}

# ISO8601 UTC（YYYY-MM-DDTHH:MM:SSZ）→ epoch 秒；格式或数值非法 → 输出空、退出非 0
ts_epoch() {
  perl -MTime::Local=timegm -e '
    my $s = shift // "";
    exit 1 unless $s =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
    my $e = eval { timegm($6, $5, $4, $3, $2 - 1, $1) };
    exit 1 unless defined $e;
    print $e;
  ' "$1" 2>/dev/null
}

# —— 一轮判定：--once/--dry-run 循环与 --block 完全共用同一份判定，不写两份 ——
# collect_due <输出文件>：遍历未结项，把「本轮要叫」的票逐行 TSV 写进 $1：
#   文件路径 <TAB> state <TAB> fp <TAB> 最后状态行原文截160字符 <TAB> 丢失pane（空=未丢失/未知）
# 跳过的票往 stdout 打「跳过：…」说明；全局 OPEN_N = 未结项总数。
# fp 输入 = state\n最后状态行（\nlost=<pane> 仅 running 票判定为工人丢失时追加）；
# 工人丢失判定只在有 herdr 且非 --dry-run 时做；无法确认不当丢失、不拼 lost 段（不猜）。
OPEN_N=0
collect_due() {
  local out="$1" f st last fp lwf we lostpane="" lostrc=1
  OPEN_N=0
  while IFS=$'\t' read -r f st; do
    OPEN_N=$((OPEN_N + 1))
    last="$(grep -E '^(working|done|blocked|needs-decision):' "$f" 2>/dev/null | tail -1 || true)"
    lostpane=""
    if [[ "$st" == "running" && "$DRY" -eq 0 ]]; then
      lostpane="$(worker_lost "$f")" && lostrc=0 || lostrc=$?
      [[ "$lostrc" -ne 0 ]] && lostpane=""
    fi
    # fp 输入 = state\n最后状态行；running 票判定为丢失时再追加 \nlost=<pane>
    # （直接管道进 shasum：命令替换会剥尾随换行；尾部 || true 保 pipefail 下群组非空退出不炸）
    fp="$( { printf '%s\n' "$st"
             printf '%s' "$last"
             [[ -n "$lostpane" ]] && printf '\nlost=%s' "$lostpane" || true
           } | shasum | cut -d' ' -f1)"
    lwf="$(last_wake_fp "$f")"
    if [[ -n "$lwf" && "$lwf" == "$fp" ]]; then
      # 时间兜底重叫只对 running 生效：兜底目的是「工人挂起/崩溃没写行」，只在 running 成立；
      # blocked/needs-decision 等的是主控裁决或使用者，指纹未变即跳过（重叫只烧主控 token）。
      if [[ "$st" != "running" ]]; then
        echo "跳过：$(basename "$f") state=${st} 等裁决（进展未变，不重叫）"
        continue
      fi
      if [[ "${QWB_REWAKE_MS:-0}" =~ ^[1-9][0-9]*$ ]]; then
        we="$(ts_epoch "$(last_wake_ts "$f")")" || we=""
        if [[ -n "$we" ]] && (( $(now_ms) - we * 1000 < QWB_REWAKE_MS )); then
          echo "跳过：$(basename "$f") state=${st}（已叫过，进展未变）"
          continue
        fi
      else
        echo "跳过：$(basename "$f") state=${st}（已叫过，进展未变）"
        continue
      fi
    fi
    if [[ "$DRY" -eq 1 ]]; then
      echo "未结项（将叫醒）: $(basename "$f") state=$st"
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$st" "$fp" "${last:0:160}" "$lostpane" >> "$out"
  done < <(open_items)
}

# 一轮一条投递的共用拼装：$1 = due 文件 → 全局 DUE_N / DUE_MSG
seq_mark() {
  local marks=(① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩ ⑪ ⑫ ⑬ ⑭ ⑮ ⑯ ⑰ ⑱ ⑲ ⑳)
  if (( $1 >= 1 && $1 <= 20 )); then printf '%s' "${marks[$(($1 - 1))]}"; else printf '(%s)' "$1"; fi
}
compose_msg() {
  DUE_N=0; DUE_MSG=""
  local f st fp last lostpane sep=""
  while IFS=$'\t' read -r f st fp last lostpane; do
    DUE_N=$((DUE_N + 1))
    DUE_MSG="${DUE_MSG}${sep}$(seq_mark "$DUE_N") $(basename "$f" .md)(${st}) 最近: ${last}"
    [[ -n "$lostpane" ]] && DUE_MSG="${DUE_MSG}（工人丢失）"
    sep=" "
  done < "$1"
}

check_round() {
  local duef
  duef="$(mktemp "${TMPDIR:-/tmp}/qwb-due.XXXXXX")"
  : > "$duef"
  collect_due "$duef"
  if [[ ! -s "$duef" ]]; then
    (( OPEN_N == 0 )) && echo "账本无未结项"
    rm -f "$duef"
    return 0
  fi
  compose_msg "$duef"
  if [[ "$DRY" -eq 1 ]]; then rm -f "$duef"; return 0; fi
  [[ -n "$PANE" ]] || { echo "错误：有未结项但不知道主控 pane（--pane / QWB_CONTROLLER_PANE / config.sh QWB_CONTROLLER_PANE）" >&2; rm -f "$duef"; exit 1; }
  # 一轮只发一条投递：全部要叫的票拼进同一条文本；投递成功才逐票写 wake 行，失败一行都不写
  if herdr pane run "$PANE" "看账本：${DUE_N} 张未结项有进展 →${DUE_MSG}。只需读这些票。"; then
    local f st fp last lostpane
    while IFS=$'\t' read -r f st fp last lostpane; do
      printf 'wake: %s state=%s fp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$st" "$fp" >> "$f" \
        || { echo "警告：wake 行写入失败（下轮重试）：$f" >&2; continue; }
      echo "已叫醒：$(basename "$f" .md) state=${st} → pane ${PANE}"
    done < "$duef"
  else
    echo "错误：投递失败（pane ${PANE}）：本轮 ${DUE_N} 张票一行 wake 都不写、保持未叫，下轮重试" >&2
  fi
  rm -f "$duef"
  return 0
}

# 毫秒级计时：macOS 的 date 不支持 %N，用 perl Time::HiRes（硬约束允许的基础工具，无新依赖）。
# 测试注入点：QWB_NOW_MS_CMD 非空时执行它取毫秒值，否则用 perl 实现——默认行为不变。
now_ms() {
  if [[ -n "${QWB_NOW_MS_CMD:-}" ]]; then "$QWB_NOW_MS_CMD"; return; fi
  perl -MTime::HiRes=time -e 'printf "%d", time()*1000'
}

# 小数秒 sleep（GNU 与 BSD/macOS 的 sleep 都接受小数）：$1 = 毫秒，下限 1ms 防空转。
# 测试注入点：QWB_SLEEP_CMD 非空时把毫秒传给它执行，不真睡——默认行为不变。
sleep_ms() {
  local ms="$1"
  (( ms > 0 )) || ms=1
  if [[ -n "${QWB_SLEEP_CMD:-}" ]]; then "$QWB_SLEEP_CMD" "$ms"; return; fi
  sleep "$(printf '%d.%03d' "$(( ms / 1000 ))" "$(( ms % 1000 ))")"
}

sleep_interval() { sleep_ms "$INTERVAL"; }

wait_round() {
  # 事件：只对未结项任务书取 dispatch 行、用时间戳最新的一条做 agent wait；
  # 无可用 pane → 按 interval sleep 退化等待，不得忙循环
  local f st disp p=""
  disp="$(
    while IFS=$'\t' read -r f st; do
      grep -h '^dispatch:' "$f" 2>/dev/null || true
    done < <(open_items) | sort | tail -1
  )"
  if [[ -n "$disp" ]]; then
    p="$(printf '%s' "$disp" | grep -o 'pane=[^[:space:]]*' | head -1 | cut -d= -f2)"
  fi
  if [[ -n "$p" ]]; then
    # 一轮预算 = 1×interval（毫秒精度）：无论 wait 成功/失败/超时，已耗时间都计入预算，
    # 剩余部分按毫秒补小数秒 sleep；耗尽 timeout（耗时≈interval）不再额外 sleep。
    local t0 dt
    t0="$(now_ms)"
    herdr agent wait "$p" --timeout "$INTERVAL" >/dev/null 2>&1 || true
    dt=$(( $(now_ms) - t0 ))
    if (( dt < INTERVAL )); then
      sleep_ms "$(( INTERVAL - dt ))"
    fi
  else
    sleep_interval
  fi
}

# —— block 模式：前台阻塞值守（Claude Code Stop hook / Codex 前台 checkpoint 的共用核心）——
# 判定与循环模式完全共用（collect_due 的指纹去重 + 仅 running 的时间兑底 + 工人丢失指纹段），
# 只有「叫醒」动作不同：不 pane run，而是把同一份拼装打到 stdout、往票追加 wake: 行后以退出码 2 交还调用方。
# 返回码：2 = 有可动作变化（已写 wake 行）；0 = 账本无未结项（不写任何行）；1 = 有未结项但无变化（内部）
block_owner_ok() {
  # Pi 以宿主 PID 绑定子进程；SIGKILL 后 PPID 改变，旧 pane 锁即使尚在也不能消费进展。
  if [[ -n "${QWB_WATCH_PARENT_PID:-}" ]]; then
    [[ "$QWB_WATCH_PARENT_PID" =~ ^[1-9][0-9]*$ ]] || return 1
    local actual_parent
    actual_parent="$(ps -o ppid= -p "$$" 2>/dev/null | tr -d '[:space:]')"
    [[ "$actual_parent" == "$QWB_WATCH_PARENT_PID" ]] || return 1
  fi
  # 孤儿值守复核：主控锁不在本进程手里（换会话后被新主控接管 / 锁已不存在）→ 不消费唤醒。
  # HERDR_PANE_ID 为空（非 herdr 环境，如 smoke）跳过复核。
  [[ -n "${HERDR_PANE_ID:-}" ]] || return 0
  local owner=""
  owner="$(sed -n 's/^[^ ]*[[:space:]]*//p' "$PROJECT_ROOT/qwbuddy/.controller.lock/owner" 2>/dev/null | head -1)"
  [[ "$owner" == "$HERDR_PANE_ID" ]]
}

block_round() {
  local duef
  duef="$(mktemp "${TMPDIR:-/tmp}/qwb-due.XXXXXX")"
  : > "$duef"
  collect_due "$duef"
  local any="$OPEN_N" f st fp last lostpane
  if [[ -s "$duef" ]]; then
    if ! block_owner_ok; then rm -f "$duef"; return 0; fi
    compose_msg "$duef"
    local lost_host=0
    while IFS=$'\t' read -r f st fp last lostpane; do
      if ! block_owner_ok; then lost_host=1; break; fi
      printf 'wake: %s state=%s fp=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$st" "$fp" >> "$f" \
        || echo "警告：wake 行写入失败（仍叫醒，下轮会重写）：$f" >&2
    done < "$duef"
    if (( lost_host )); then rm -f "$duef"; return 0; fi
    printf '看账本：%d 张未结项有进展 →%s。只需读这些票。\n' "$DUE_N" "$DUE_MSG"
    rm -f "$duef"
    return 2
  fi
  rm -f "$duef"
  (( any )) || return 0
  return 1
}

if [[ "$BLOCK" -eq 1 ]]; then
  block_deadline=""
  if [[ -n "$MAX_MS" ]]; then
    block_deadline=$(( $(now_ms) + MAX_MS ))
  fi
  while :; do
    # 每轮判定前复核主控锁：锁不在手 = 本值守是孤儿（主控会话已退出 / 锁被新主控接管），
    # exit 0、不写任何 wake 行，不消费唤醒
    if ! block_owner_ok; then
      echo "值守：主控锁不在本进程（owner=$(sed -n 's/^[^ ]*[[:space:]]*//p' "$PROJECT_ROOT/qwbuddy/.controller.lock/owner" 2>/dev/null | head -1)，本进程 ${HERDR_PANE_ID}），孤儿值守退出不消费唤醒"
      exit 0
    fi
    brc=0; block_round || brc=$?
    if (( brc == 2 )); then exit 2; fi
    if (( brc == 0 )); then echo "账本无未结项"; exit 0; fi
    if [[ -n "$block_deadline" ]] && (( $(now_ms) >= block_deadline )); then
      echo "值守：--block 到期（--max-ms ${MAX_MS}ms）无变化" >&2
      exit 124
    fi
    sleep_interval
  done
fi

while :; do
  check_round
  if [[ "$ONCE" -eq 1 || "$DRY" -eq 1 ]]; then
    exit 0
  fi
  wait_round
done
